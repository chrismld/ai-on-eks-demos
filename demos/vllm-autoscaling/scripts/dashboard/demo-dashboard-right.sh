#!/bin/bash

NC='\033[0m'
BOLD='\033[1m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;37m'
COLOR_GOOD='\033[38;5;40m'
COLOR_WARNING='\033[38;5;226m'
COLOR_ERROR='\033[38;5;196m'
COLOR_INFO='\033[38;5;51m'
COLOR_MUTED='\033[38;5;245m'

BOX_L_TL='┌'
BOX_L_TR='┐'
BOX_L_BL='└'
BOX_L_BR='┘'
BOX_L_H='─'
BOX_L_V='│'

CURSOR_HOME='\033[H'
CLEAR_SCREEN='\033[2J'
CLEAR_LINE='\033[K'
CURSOR_HIDE='\033[?25l'
CURSOR_SHOW='\033[?25h'

REFRESH_INTERVAL=1
MAX_ROWS=10
PANEL_WIDTH=72
INNER_WIDTH=70  # PANEL_WIDTH - 2 (for borders)

cleanup() {
    printf "${CURSOR_SHOW}${NC}"
    # Kill tmux session if running inside one
    if [[ -n "$TMUX" ]]; then
        tmux kill-session -t demo-dashboard 2>/dev/null
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

get_pod_timing_info() {
    kubectl get pods -n default -l app=vllm -o json 2>/dev/null | jq -r '
        .items[] | 
        {
            name: .metadata.name,
            phase: .status.phase,
            creationTime: .metadata.creationTimestamp,
            scheduledCondition: (.status.conditions[] | select(.type=="PodScheduled") | .lastTransitionTime // ""),
            readyCondition: (.status.conditions[] | select(.type=="Ready"))
        } |
        .name + "|" + 
        .phase + "|" + 
        (if .readyCondition.status == "True" then "Ready" else "NotReady" end) + "|" +
        .creationTime + "|" +
        .scheduledCondition + "|" +
        (if .readyCondition.status == "True" then .readyCondition.lastTransitionTime else "" end)
    ' 2>/dev/null || echo ""
}

get_inference_nodes_info() {
    kubectl get nodes -l karpenter.sh/nodepool=gpu-inference -o json 2>/dev/null | jq -r '
        .items[] |
        {
            name: .metadata.name,
            instance_type: .metadata.labels["node.kubernetes.io/instance-type"],
            capacity_type: .metadata.labels["karpenter.sh/capacity-type"],
            zone: .metadata.labels["topology.kubernetes.io/zone"],
            status: (if .spec.taints then (if any(.spec.taints[]; .key == "karpenter.sh/disruption" and .effect == "NoSchedule") then "Deleting" else "Ready" end) else (if (.status.conditions[] | select(.type=="Ready") | .status) == "True" then "Ready" else "NotReady" end) end)
        } |
        .name + "|" + 
        (.instance_type // "unknown") + "|" + 
        (if .capacity_type == "on-demand" then "OD" elif .capacity_type == "spot" then "SP" else "?" end) + "|" +
        (.zone // "unknown") + "|" +
        .status
    ' 2>/dev/null || echo ""
}

get_pods_per_node() {
    local node_name="$1"
    kubectl get pods -n default -l app=vllm --field-selector spec.nodeName="$node_name" -o json 2>/dev/null | jq -r '.items | length' 2>/dev/null || echo "0"
}

# Get the most recently created pod's startup timeline breakdown
get_latest_pod_startup_timeline() {
    kubectl get pods -n default -l app=vllm -o json 2>/dev/null | jq -r '
        [.items[] | select(.status.phase == "Running" and .status.containerStatuses[0].ready == true)] |
        sort_by(.metadata.creationTimestamp) |
        last |
        if . == null then
            ""
        else
            {
                name: .metadata.name,
                created: .metadata.creationTimestamp,
                scheduled: (.status.conditions[] | select(.type=="PodScheduled") | .lastTransitionTime),
                initialized: (.status.conditions[] | select(.type=="Initialized") | .lastTransitionTime),
                containerStarted: .status.containerStatuses[0].state.running.startedAt,
                ready: (.status.conditions[] | select(.type=="Ready") | .lastTransitionTime)
            } |
            .name + "|" + .created + "|" + .scheduled + "|" + .initialized + "|" + .containerStarted + "|" + .ready
        end
    ' 2>/dev/null || echo ""
}

# Render a line with exact padding to PANEL_WIDTH
# Usage: render_line "content" content_visible_length
render_line() {
    local content="$1"
    local visible_len="$2"
    local padding=$((INNER_WIDTH - visible_len))
    printf "${BOLD_CYAN}${BOX_L_V}${NC}"
    printf "%b" "$content"
    printf "%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "$padding" ""
}

# Render horizontal border line
render_hline() {
    printf "${BOLD_CYAN}${BOX_L_V}"
    for ((i=0; i<INNER_WIDTH; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_V}${NC}${CLEAR_LINE}\n"
}

# Render empty line
render_empty_line() {
    printf "${BOLD_CYAN}${BOX_L_V}${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "$INNER_WIDTH" ""
}

render_pod_timing_panel() {
    local pod_data="$1"
    
    # Header: "┌─ vLLM Pods ─────...─┐" (total 72 chars)
    # "┌─ vLLM Pods " = 12 chars, "┐" = 1 char, need 59 dashes = 72 total
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} vLLM Pods ${NC}${BOLD_CYAN}"
    for ((i=0; i<58; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}${CLEAR_LINE}\n"
    
    # Column header line: " Name              Status     Node     Pod      Total       "
    # Widths: Name=18, Status=10, Node=8, Pod=8, Total=8 = 52 + 5 spaces + 1 leading = 58
    # Inner width is 70, so visible content = 57, padding = 13
    local header_content
    header_content=$(printf " ${BOLD}%-18s %-10s %-8s %-8s %-8s${NC}" "Name" "Status" "Node" "Pod" "Total")
    render_line "$header_content" 57
    
    # Separator
    render_hline
    
    local row_count=0
    
    if [[ -z "$pod_data" ]]; then
        local empty_msg=" ${COLOR_MUTED}No pods found${NC}"
        render_line "$empty_msg" 14
        row_count=1
    else
        while IFS='|' read -r name phase ready_status creation_time scheduled_time ready_time; do
            [[ -z "$name" ]] && continue
            [[ $row_count -ge $MAX_ROWS ]] && break
            
            local short_name="${name: -16}"
            
            local status_display="$ready_status"
            local status_color="$COLOR_INFO"
            [[ "$ready_status" == "Ready" ]] && status_color="$COLOR_GOOD"
            [[ "$ready_status" == "NotReady" ]] && status_color="$COLOR_WARNING"
            [[ "$phase" == "Failed" ]] && status_color="$COLOR_ERROR" && status_display="Failed"
            [[ "$phase" == "Pending" ]] && status_color="$COLOR_WARNING" && status_display="Pending"
            
            local node_time_display="-"
            local pod_time_display="-"
            local total_time_display="-"
            
            if [[ -n "$creation_time" ]] && [[ -n "$scheduled_time" ]]; then
                local creation_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$creation_time" "+%s" 2>/dev/null)
                local scheduled_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$scheduled_time" "+%s" 2>/dev/null)
                if [[ -n "$creation_epoch" ]] && [[ -n "$scheduled_epoch" ]]; then
                    local node_secs=$((scheduled_epoch - creation_epoch))
                    [[ $node_secs -lt 0 ]] && node_secs=0
                    node_time_display="${node_secs}s"
                fi
            fi
            
            if [[ -n "$scheduled_time" ]] && [[ -n "$ready_time" ]] && [[ "$ready_status" == "Ready" ]]; then
                local scheduled_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$scheduled_time" "+%s" 2>/dev/null)
                local ready_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ready_time" "+%s" 2>/dev/null)
                if [[ -n "$scheduled_epoch" ]] && [[ -n "$ready_epoch" ]]; then
                    local pod_secs=$((ready_epoch - scheduled_epoch))
                    [[ $pod_secs -lt 0 ]] && pod_secs=0
                    pod_time_display="${pod_secs}s"
                fi
            fi
            
            if [[ -n "$creation_time" ]] && [[ -n "$ready_time" ]] && [[ "$ready_status" == "Ready" ]]; then
                local creation_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$creation_time" "+%s" 2>/dev/null)
                local ready_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ready_time" "+%s" 2>/dev/null)
                if [[ -n "$creation_epoch" ]] && [[ -n "$ready_epoch" ]]; then
                    local total_secs=$((ready_epoch - creation_epoch))
                    [[ $total_secs -lt 0 ]] && total_secs=0
                    total_time_display="${total_secs}s"
                fi
            fi
            
            # Data row: same layout as header (57 visible chars)
            local row_content
            row_content=$(printf " %-18s ${status_color}%-10s${NC} %-8s %-8s %-8s" \
                "$short_name" "$status_display" "$node_time_display" "$pod_time_display" "$total_time_display")
            render_line "$row_content" 57
            
            ((row_count++))
        done <<< "$pod_data"
    fi
    
    # Fill remaining rows
    while [[ $row_count -lt $MAX_ROWS ]]; do
        render_empty_line
        ((row_count++))
    done
    
    # Footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<INNER_WIDTH; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}${CLEAR_LINE}\n"
}

render_nodes_panel() {
    local node_data="$1"
    
    # Header: "┌─ Inference Nodes ─────...─┐" (total 72 chars)
    # "┌─ Inference Nodes " = 19 chars, "┐" = 1 char, need 52 dashes = 72 total
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} Inference Nodes ${NC}${BOLD_CYAN}"
    for ((i=0; i<52; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}${CLEAR_LINE}\n"
    
    # Column header: " Name         Instance       Type   AZ   Pods   Status     "
    # Widths: Name=12, Instance=14, Type=6, AZ=4, Pods=6, Status=10 = 52 + 5 spaces + 1 leading = 58
    local header_content
    header_content=$(printf " ${BOLD}%-12s %-14s %-6s %-4s %-6s %-10s${NC}" "Name" "Instance" "Type" "AZ" "Pods" "Status")
    render_line "$header_content" 58
    
    # Separator
    render_hline
    
    local row_count=0
    local max_node_rows=6
    
    if [[ -z "$node_data" ]]; then
        local empty_msg=" ${COLOR_MUTED}No inference nodes found${NC}"
        render_line "$empty_msg" 25
        row_count=1
    else
        while IFS='|' read -r name instance_type capacity_type zone node_status; do
            [[ -z "$name" ]] && continue
            [[ $row_count -ge $max_node_rows ]] && break
            
            # Short name: first part before dot, last 12 chars
            local short_name
            if [[ "$name" == *"."* ]]; then
                short_name="${name%%.*}"
                short_name="${short_name: -12}"
            else
                short_name="${name: -12}"
            fi
            
            # Short AZ: just the zone letter (e.g., eu-west-1a -> 1a)
            local short_az="${zone: -2}"
            
            # Get pod count for this node
            local pod_count=$(get_pods_per_node "$name")
            
            # Status color
            local status_color="$COLOR_INFO"
            [[ "$node_status" == "Ready" ]] && status_color="$COLOR_GOOD"
            [[ "$node_status" == "NotReady" ]] && status_color="$COLOR_WARNING"
            [[ "$node_status" == "Deleting" ]] && status_color="$COLOR_ERROR"
            
            # Capacity type color
            local cap_color="$COLOR_INFO"
            [[ "$capacity_type" == "SP" ]] && cap_color="$COLOR_WARNING"
            
            # Data row: same layout as header (58 visible chars)
            local row_content
            row_content=$(printf " %-12s %-14s ${cap_color}%-6s${NC} %-4s %-6s ${status_color}%-10s${NC}" \
                "$short_name" "$instance_type" "$capacity_type" "$short_az" "$pod_count" "$node_status")
            render_line "$row_content" 58
            
            ((row_count++))
        done <<< "$node_data"
    fi
    
    # Fill remaining rows
    while [[ $row_count -lt $max_node_rows ]]; do
        render_empty_line
        ((row_count++))
    done
    
    # Footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<INNER_WIDTH; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}${CLEAR_LINE}\n"
}

render_startup_timeline_panel() {
    local timeline_data="$1"
    
    # Header: "┌─ vLLM Startup Breakdown ─────...─┐" (total 72 chars)
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} vLLM Startup Breakdown ${NC}${BOLD_CYAN}"
    for ((i=0; i<45; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}${CLEAR_LINE}\n"
    
    if [[ -z "$timeline_data" ]]; then
        printf "${BOLD_CYAN}${BOX_L_V}${NC} ${COLOR_MUTED}No ready pods found${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" 50 ""
        for ((i=0; i<10; i++)); do render_empty_line; done
    else
        IFS='|' read -r name created scheduled initialized container_started ready <<< "$timeline_data"
        
        local short_name="${name: -30}"
        
        # Calculate time differences for K8s phases
        local node_time="-"
        local image_time="-"
        local total_time="-"
        
        if [[ -n "$created" ]] && [[ -n "$scheduled" ]]; then
            local created_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$created" "+%s" 2>/dev/null)
            local scheduled_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$scheduled" "+%s" 2>/dev/null)
            if [[ -n "$created_epoch" ]] && [[ -n "$scheduled_epoch" ]]; then
                local secs=$((scheduled_epoch - created_epoch))
                [[ $secs -lt 0 ]] && secs=0
                node_time="${secs}s"
            fi
        fi
        
        if [[ -n "$scheduled" ]] && [[ -n "$container_started" ]]; then
            local scheduled_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$scheduled" "+%s" 2>/dev/null)
            local started_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$container_started" "+%s" 2>/dev/null)
            if [[ -n "$scheduled_epoch" ]] && [[ -n "$started_epoch" ]]; then
                local secs=$((started_epoch - scheduled_epoch))
                [[ $secs -lt 0 ]] && secs=0
                image_time="${secs}s"
            fi
        fi
        
        if [[ -n "$created" ]] && [[ -n "$ready" ]]; then
            local created_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$created" "+%s" 2>/dev/null)
            local ready_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ready" "+%s" 2>/dev/null)
            if [[ -n "$created_epoch" ]] && [[ -n "$ready_epoch" ]]; then
                local secs=$((ready_epoch - created_epoch))
                [[ $secs -lt 0 ]] && secs=0
                total_time="${secs}s"
            fi
        fi
        
        # Pod name line (30 chars for name)
        printf "${BOLD_CYAN}${BOX_L_V}${NC} ${BOLD}Pod:${NC} ${COLOR_INFO}%-30s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "$short_name" 34 ""
        
        render_hline
        
        # K8s infrastructure phases
        printf "${BOLD_CYAN}${BOX_L_V}${NC} ${COLOR_MUTED}K8s:${NC} %-40s ${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "Node provisioning (Karpenter)" "$node_time" 15 ""
        printf "${BOLD_CYAN}${BOX_L_V}${NC}      %-40s ${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "Image pull (SOCI lazy-load)" "$image_time" 15 ""
        
        render_hline
        
        # vLLM internal phases (from logs analysis)
        printf "${BOLD_CYAN}${BOX_L_V}${NC} ${COLOR_MUTED}vLLM:${NC}%-40s ${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "S3 model stream (RunAI @ 1.6GiB/s)" "~2s" 15 ""
        printf "${BOLD_CYAN}${BOX_L_V}${NC}      %-40s ${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "Model loading to GPU" "~23s" 15 ""
        printf "${BOLD_CYAN}${BOX_L_V}${NC}      %-40s ${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "torch.compile (EFS cache hit)" "~8s" 15 ""
        printf "${BOLD_CYAN}${BOX_L_V}${NC}      %-40s ${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "CUDA graph capture" "~1s" 15 ""
        printf "${BOLD_CYAN}${BOX_L_V}${NC}      %-40s ${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "Engine init (KV cache, warmup)" "~17s" 15 ""
        
        render_hline
        
        # Total line
        printf "${BOLD_CYAN}${BOX_L_V}${NC} ${BOLD}%-45s${NC} ${BOLD}${COLOR_GOOD}%8s${NC}%*s${BOLD_CYAN}${BOX_L_V}${NC}${CLEAR_LINE}\n" "Total Time to Ready:" "$total_time" 15 ""
    fi
    
    # Footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<INNER_WIDTH; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}${CLEAR_LINE}\n"
}

# Only run main loop if script is executed directly (not sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main() {
        printf "${CURSOR_HIDE}${CLEAR_SCREEN}${CURSOR_HOME}"
        
        while true; do
            printf "${CURSOR_HOME}"
            
            # Title header
            printf "${BOLD_CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}${CLEAR_LINE}\n"
            printf "${BOLD_CYAN}║${NC}${BOLD_WHITE}                  Cluster Infrastructure Status                       ${NC}${BOLD_CYAN}║${NC}${CLEAR_LINE}\n"
            printf "${BOLD_CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}${CLEAR_LINE}\n"
            echo ""
            
            local pod_data=$(get_pod_timing_info)
            render_pod_timing_panel "$pod_data"
            
            echo ""
            
            local node_data=$(get_inference_nodes_info)
            render_nodes_panel "$node_data"
            
            echo ""
            
            local timeline_data=$(get_latest_pod_startup_timeline)
            render_startup_timeline_panel "$timeline_data"
            
            sleep $REFRESH_INTERVAL
        done
    }
    
    main
fi
