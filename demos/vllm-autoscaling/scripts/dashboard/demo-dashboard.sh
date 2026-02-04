#!/bin/bash

# =============================================================================
# Demo Dashboard - Terminal-based Real-time Kubernetes Autoscaling Monitor
# =============================================================================
# A professional dashboard for monitoring vLLM autoscaling demos with KEDA
# and Karpenter. Displays load graphs, queue metrics, pod/node scaling status,
# and performance metrics in a clean, organized layout.
#
# Requirements: kubectl, jq (optional for JSON parsing)
# Usage: ./demo-dashboard.sh
# =============================================================================

# -----------------------------------------------------------------------------
# Color Constants and ANSI Escape Codes
# Requirements: 7.4 (consistent color coding)
# -----------------------------------------------------------------------------

# Reset
NC='\033[0m'           # No Color / Reset

# Standard Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold Colors
BOLD='\033[1m'
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;37m'

# 256-Color Extended Palette (for status indicators)
COLOR_GOOD='\033[38;5;40m'       # Bright green
COLOR_WARNING='\033[38;5;226m'   # Bright yellow
COLOR_ERROR='\033[38;5;196m'     # Bright red
COLOR_INFO='\033[38;5;51m'       # Bright cyan
COLOR_MUTED='\033[38;5;245m'     # Gray

# Background Colors (for highlights)
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_RED='\033[41m'
BG_BLUE='\033[44m'

# Text Formatting
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'

# Cursor Control
CURSOR_HIDE='\033[?25l'
CURSOR_SHOW='\033[?25h'
CURSOR_HOME='\033[H'
CLEAR_SCREEN='\033[2J'
CLEAR_LINE='\033[2K'

# -----------------------------------------------------------------------------
# Configuration Variables
# Requirements: 6.1 (2-second refresh), 7.3 (80-column width)
# -----------------------------------------------------------------------------

# Refresh and Timing
REFRESH_INTERVAL=2               # Seconds between updates
STARTUP_RETRY_INTERVAL=5         # Seconds between connection retries
GRAPH_UPDATE_INTERVAL=4          # Seconds between graph data points (every 2 refreshes)

# Graph Dimensions
GRAPH_WIDTH=73                   # Width of ASCII graph in characters
GRAPH_HEIGHT=10                  # Height of ASCII graph in lines
MAX_HISTORY_SIZE=75              # Rolling window size (~5 min at 4s intervals)

# Terminal Layout
TERMINAL_WIDTH=80                # Maximum terminal width

# Kubernetes Configuration
VLLM_NAMESPACE="default"         # Namespace for vLLM deployment
VLLM_DEPLOYMENT="vllm"           # vLLM deployment name
VLLM_LABEL="app=vllm"            # Label selector for vLLM pods
NODE_LABEL="karpenter.sh/nodepool"  # Label for Karpenter-managed nodes
GPU_NODE_LABEL="workload=inference"  # Alternative label for GPU nodes

# -----------------------------------------------------------------------------
# Threshold Configuration
# Requirements: 2.3, 2.4 (scaling indicators), 5.5 (performance color coding)
# -----------------------------------------------------------------------------

# KEDA scaling thresholds
THRESHOLD_QUEUE_TARGET=5              # KEDA target value for waiting requests
THRESHOLD_QUEUE_SCALE_UP=10           # Queue depth indicating scale-up pressure
THRESHOLD_QUEUE_HIGH=20               # High queue depth (warning)
THRESHOLD_RUNNING_TARGET=25           # KEDA target value for running requests
THRESHOLD_QUEUE_CRITICAL=50           # Critical queue depth (error)

# Response time thresholds (milliseconds)
THRESHOLD_RESPONSE_GOOD=500           # Response time considered good
THRESHOLD_RESPONSE_WARNING=1000       # Response time considered degraded
THRESHOLD_RESPONSE_CRITICAL=2000      # Response time considered poor

# Throughput thresholds (requests per second)
THRESHOLD_THROUGHPUT_LOW=1            # Low throughput threshold
THRESHOLD_THROUGHPUT_GOOD=10          # Good throughput threshold

# Load intensity thresholds (RPS)
THRESHOLD_LOAD_LOW=10                 # Low load
THRESHOLD_LOAD_MEDIUM=50              # Medium load
THRESHOLD_LOAD_HIGH=100               # High load

# -----------------------------------------------------------------------------
# Data Structure Arrays
# Requirements: 1.2 (rolling window), 6.5 (last known values)
# -----------------------------------------------------------------------------

# Load history for graph (rolling window of last 60 values)
LOAD_HISTORY=()
LOAD_TIMESTAMPS=()

# Current metrics (using individual variables for bash 3.2 compatibility)
METRIC_QUEUE_DEPTH=0
METRIC_RUNNING_REQUESTS=0
METRIC_PODS_RUNNING=0
METRIC_PODS_DESIRED=0
METRIC_PODS_READY=0
METRIC_PODS_PENDING=0
METRIC_PODS_NOT_READY=0
METRIC_POD_STARTUP_MIN="N/A"
METRIC_POD_STARTUP_MAX="N/A"
METRIC_NODES_COUNT=0
METRIC_NODES_READY=0
METRIC_NODES_PENDING=0
METRIC_NODECLAIMS_PENDING=0
METRIC_NODES_ONDEMAND=0
METRIC_NODES_SPOT=0
METRIC_NODE_TYPE="N/A"
METRIC_THROUGHPUT=0
METRIC_TOKENS_PER_SEC=0
METRIC_TOKENS_PER_REQ=0
METRIC_KV_CACHE_PCT=0
METRIC_TTFT_P50=0
METRIC_TTFT_P95=0
METRIC_ITL_P50=0
METRIC_ITL_P95=0
METRIC_E2E_AVG=0
METRIC_E2E_P50=0
METRIC_E2E_P95=0
METRIC_SCALING_STATUS="stable"
METRIC_LAST_UPDATE=""
METRIC_CURRENT_RPS=0

# Last known good values (for stale data handling)
LAST_GOOD_QUEUE_DEPTH=0
LAST_GOOD_PODS_RUNNING=0
LAST_GOOD_PODS_DESIRED=0
LAST_GOOD_PODS_READY=0
LAST_GOOD_NODES_COUNT=0
LAST_GOOD_NODE_TYPE="N/A"
LAST_GOOD_THROUGHPUT=0
LAST_GOOD_TOKENS_PER_SEC=0

# Session-persistent startup times (only reset on dashboard start, not when pods scale down)
SESSION_STARTUP_MIN=""
SESSION_STARTUP_MAX=""

# Session-persistent performance metrics (only reset on dashboard start)
# These retain the last good values so they display after load test ends
SESSION_RPS=""
SESSION_TOKENS_SEC=""
SESSION_TTFT_P50=""
SESSION_TTFT_P95=""
SESSION_ITL_P50=""
SESSION_ITL_P95=""
SESSION_E2E_AVG=""
SESSION_E2E_P50=""
SESSION_E2E_P95=""
SESSION_TOKENS_REQ=""

# Token tracking for tokens/s calculation
LAST_TOKENS_TOTAL=0
LAST_TOKENS_TIME=0

# RPS tracking for requests/s calculation
LAST_REQUESTS_TOTAL=0
LAST_REQUESTS_TIME=0

# Graph update timing (add point every GRAPH_UPDATE_INTERVAL seconds)
LAST_GRAPH_UPDATE=0

# Stale indicators (true if data might be stale)
STALE_QUEUE_DEPTH=false
STALE_PODS=false
STALE_NODES=false
STALE_PERFORMANCE=false

# k6 Load Test Results (populated when k6 job completes)
K6_JOB_STATUS=""           # "running", "completed", "failed", ""
K6_TOTAL_REQUESTS=""       # Total HTTP requests made
K6_RPS=""                  # Requests per second (final)
K6_AVG_DURATION=""         # Average request duration
K6_MIN_DURATION=""         # Min request duration
K6_MED_DURATION=""         # Median request duration
K6_MAX_DURATION=""         # Max request duration
K6_P90_DURATION=""         # P90 request duration
K6_P95_DURATION=""         # P95 request duration
K6_FAILURE_RATE=""         # Failure rate percentage
K6_LAST_CHECK=0            # Timestamp of last k6 status check

# -----------------------------------------------------------------------------
# Display Configuration
# Requirements: 7.4 (consistent color coding)
# -----------------------------------------------------------------------------

DISPLAY_REFRESH_INTERVAL=$REFRESH_INTERVAL
DISPLAY_GRAPH_WIDTH=$GRAPH_WIDTH
DISPLAY_GRAPH_HEIGHT=$GRAPH_HEIGHT
DISPLAY_TERMINAL_WIDTH=$TERMINAL_WIDTH
DISPLAY_COLOR_GOOD="$COLOR_GOOD"
DISPLAY_COLOR_WARNING="$COLOR_WARNING"
DISPLAY_COLOR_ERROR="$COLOR_ERROR"
DISPLAY_COLOR_INFO="$COLOR_INFO"

# -----------------------------------------------------------------------------
# Runtime State
# -----------------------------------------------------------------------------

# Dashboard start time (for elapsed time calculation)
START_TIME=0

# Error log file
ERROR_LOG="/tmp/demo-dashboard.log"

# Flag to track if we should continue running
RUNNING=true

# -----------------------------------------------------------------------------
# Box Drawing Characters (for visual layout)
# Requirements: 7.2 (box-drawing characters)
# -----------------------------------------------------------------------------

BOX_TL='╔'    # Top-left corner
BOX_TR='╗'    # Top-right corner
BOX_BL='╚'    # Bottom-left corner
BOX_BR='╝'    # Bottom-right corner
BOX_H='═'     # Horizontal line
BOX_V='║'     # Vertical line
BOX_LT='╠'    # Left T-junction
BOX_RT='╣'    # Right T-junction
BOX_TT='╦'    # Top T-junction
BOX_BT='╩'    # Bottom T-junction
BOX_X='╬'     # Cross junction

# Light box characters (for inner sections)
BOX_L_TL='┌'
BOX_L_TR='┐'
BOX_L_BL='└'
BOX_L_BR='┘'
BOX_L_H='─'
BOX_L_V='│'

# Block characters for graphs
BLOCK_FULL='█'
BLOCK_LIGHT='░'
BLOCK_MEDIUM='▒'
BLOCK_DARK='▓'
BLOCK_UPPER='▀'
BLOCK_LOWER='▄'

# Status indicators
INDICATOR_UP='↑'
INDICATOR_DOWN='↓'
INDICATOR_STABLE='●'
INDICATOR_WARNING='⚠'
INDICATOR_CHECK='✓'
INDICATOR_CROSS='✗'

# Pod/Node visual representations
POD_ICON='●'
POD_EMPTY='○'
NODE_ICON='■'
NODE_EMPTY='□'

# =============================================================================
# STARTUP CHECKS AND ERROR HANDLING
# =============================================================================
# These functions verify prerequisites and handle errors gracefully.
# Requirements: 8.2 (prerequisite checks), 8.4 (error logging)
# =============================================================================

# -----------------------------------------------------------------------------
# Log error to file without disrupting display
# Requirements: 8.4
# Parameters:
#   $1 - Error message to log
# Side effects:
#   - Appends timestamped error message to ERROR_LOG file
#   - Creates log file if it doesn't exist
# -----------------------------------------------------------------------------
log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >> "$ERROR_LOG" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Log info to file
# Requirements: 8.4
# Parameters:
#   $1 - Info message to log
# Side effects:
#   - Appends timestamped info message to ERROR_LOG file
# -----------------------------------------------------------------------------
log_info() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $message" >> "$ERROR_LOG" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Log warning to file
# Requirements: 8.4
# Parameters:
#   $1 - Warning message to log
# Side effects:
#   - Appends timestamped warning message to ERROR_LOG file
# -----------------------------------------------------------------------------
log_warning() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $message" >> "$ERROR_LOG" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Initialize error log file
# Requirements: 8.4
# Side effects:
#   - Creates or truncates the error log file
#   - Writes startup header to log
# -----------------------------------------------------------------------------
init_error_log() {
    # Create log directory if needed (for /tmp this is usually not necessary)
    local log_dir
    log_dir=$(dirname "$ERROR_LOG")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null
    fi
    
    # Write startup header to log (append mode to preserve previous logs)
    echo "" >> "$ERROR_LOG" 2>/dev/null
    echo "============================================================" >> "$ERROR_LOG" 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Dashboard session started" >> "$ERROR_LOG" 2>/dev/null
    echo "============================================================" >> "$ERROR_LOG" 2>/dev/null
}

# -----------------------------------------------------------------------------
# check_kubectl_installed - Verify kubectl is installed
# Requirements: 8.2
# Returns: 0 if kubectl is installed, 1 otherwise
# Output: Prints error message to stderr on failure
# -----------------------------------------------------------------------------
check_kubectl_installed() {
    if ! command -v kubectl &>/dev/null; then
        echo -e "${COLOR_ERROR}Error: kubectl is not installed or not in PATH${NC}" >&2
        echo "" >&2
        echo "Please install kubectl to use this dashboard." >&2
        echo "Installation guide: https://kubernetes.io/docs/tasks/tools/" >&2
        log_error "Prerequisite check failed: kubectl not installed"
        return 1
    fi
    log_info "Prerequisite check passed: kubectl is installed"
    return 0
}

# -----------------------------------------------------------------------------
# check_cluster_connectivity - Verify Kubernetes cluster is reachable
# Requirements: 8.2
# Returns: 0 if cluster is reachable, 1 otherwise
# Output: Prints error message to stderr on failure
# -----------------------------------------------------------------------------
check_cluster_connectivity() {
    local cluster_info
    
    # Try to get cluster info with a timeout
    if ! cluster_info=$(kubectl cluster-info --request-timeout=5s 2>&1); then
        echo -e "${COLOR_ERROR}Error: Cannot connect to Kubernetes cluster${NC}" >&2
        echo "" >&2
        echo "Please ensure:" >&2
        echo "  1. Your kubeconfig is properly configured" >&2
        echo "  2. The cluster is running and accessible" >&2
        echo "  3. Your credentials are valid" >&2
        echo "" >&2
        echo "Try running: kubectl cluster-info" >&2
        log_error "Prerequisite check failed: Cannot connect to cluster - $cluster_info"
        return 1
    fi
    
    log_info "Prerequisite check passed: Cluster is reachable"
    return 0
}

# -----------------------------------------------------------------------------
# check_vllm_namespace - Verify vLLM namespace exists
# Requirements: 8.2
# Returns: 0 if namespace exists, 1 otherwise
# Output: Prints error message to stderr on failure
# -----------------------------------------------------------------------------
check_vllm_namespace() {
    local ns_check
    
    # Check if the vLLM namespace exists
    if ! ns_check=$(kubectl get namespace "$VLLM_NAMESPACE" --request-timeout=5s 2>&1); then
        echo -e "${COLOR_ERROR}Error: Namespace '${VLLM_NAMESPACE}' does not exist${NC}" >&2
        echo "" >&2
        echo "Please ensure the vLLM deployment is set up correctly." >&2
        echo "The dashboard expects the vLLM workload in namespace: ${VLLM_NAMESPACE}" >&2
        echo "" >&2
        echo "Try running: kubectl get namespaces" >&2
        log_error "Prerequisite check failed: Namespace '$VLLM_NAMESPACE' not found - $ns_check"
        return 1
    fi
    
    log_info "Prerequisite check passed: Namespace '$VLLM_NAMESPACE' exists"
    return 0
}

# -----------------------------------------------------------------------------
# check_vllm_deployment - Verify vLLM deployment exists (optional check)
# Requirements: 8.2
# Returns: 0 if deployment exists, 1 otherwise (warning only, not fatal)
# Output: Prints warning message to stderr if deployment not found
# -----------------------------------------------------------------------------
check_vllm_deployment() {
    local deploy_check
    
    # Check if the vLLM deployment exists
    if ! deploy_check=$(kubectl get deployment "$VLLM_DEPLOYMENT" -n "$VLLM_NAMESPACE" --request-timeout=5s 2>&1); then
        echo -e "${COLOR_WARNING}Warning: Deployment '${VLLM_DEPLOYMENT}' not found in namespace '${VLLM_NAMESPACE}'${NC}" >&2
        echo "The dashboard will start but may show N/A for some metrics." >&2
        echo "" >&2
        log_warning "Deployment '$VLLM_DEPLOYMENT' not found in namespace '$VLLM_NAMESPACE' - $deploy_check"
        # Return success - this is a warning, not a fatal error
        return 0
    fi
    
    log_info "Prerequisite check passed: Deployment '$VLLM_DEPLOYMENT' exists"
    return 0
}

# -----------------------------------------------------------------------------
# run_prerequisite_checks - Run all prerequisite checks
# Requirements: 8.2
# Returns: 0 if all required checks pass, 1 otherwise
# Output: Prints status messages and errors to stdout/stderr
# Side effects:
#   - Logs check results to error log
#   - May retry cluster connectivity on failure
# -----------------------------------------------------------------------------
run_prerequisite_checks() {
    echo -e "${BOLD_CYAN}Checking prerequisites...${NC}"
    echo ""
    
    # Check 1: kubectl installed (required)
    echo -n "  Checking kubectl... "
    if ! check_kubectl_installed; then
        return 1
    fi
    echo -e "${COLOR_GOOD}✓${NC}"
    
    # Check 2: Cluster connectivity (required)
    echo -n "  Checking cluster connectivity... "
    local retry_count=0
    local max_retries=3
    
    while ! check_cluster_connectivity; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $max_retries ]]; then
            echo -e "${COLOR_ERROR}✗${NC}"
            echo "" >&2
            echo -e "${COLOR_ERROR}Failed to connect after $max_retries attempts.${NC}" >&2
            return 1
        fi
        echo -e "${COLOR_WARNING}Retrying ($retry_count/$max_retries)...${NC}"
        sleep "$STARTUP_RETRY_INTERVAL"
        echo -n "  Checking cluster connectivity... "
    done
    echo -e "${COLOR_GOOD}✓${NC}"
    
    # Check 3: vLLM namespace exists (required)
    echo -n "  Checking vLLM namespace... "
    if ! check_vllm_namespace; then
        echo -e "${COLOR_ERROR}✗${NC}"
        return 1
    fi
    echo -e "${COLOR_GOOD}✓${NC}"
    
    # Check 4: vLLM deployment exists (optional - warning only)
    echo -n "  Checking vLLM deployment... "
    if check_vllm_deployment; then
        echo -e "${COLOR_GOOD}✓${NC}"
    else
        echo -e "${COLOR_WARNING}⚠${NC} (will continue with warnings)"
    fi
    
    echo ""
    echo -e "${COLOR_GOOD}All prerequisite checks passed!${NC}"
    echo ""
    log_info "All prerequisite checks completed successfully"
    
    return 0
}

# =============================================================================
# DATA PROCESSING FUNCTIONS
# =============================================================================
# These functions transform raw metrics into displayable formats.
# =============================================================================

# -----------------------------------------------------------------------------
# add_to_load_history - Add a new value to the load history array
# Requirements: 1.2 (rolling window), 1.3 (update graph with latest value)
# Parameters:
#   $1 - The load value to add (numeric)
# Side effects:
#   - Appends value to LOAD_HISTORY array
#   - Appends current timestamp to LOAD_TIMESTAMPS array
#   - Removes oldest values if arrays exceed MAX_HISTORY_SIZE
# -----------------------------------------------------------------------------
add_to_load_history() {
    local value="$1"
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    
    # Validate input - default to 0 if not numeric
    if ! [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        value=0
    fi
    
    # Add new value and timestamp to arrays
    LOAD_HISTORY+=("$value")
    LOAD_TIMESTAMPS+=("$timestamp")
    
    # Remove oldest values if we exceed MAX_HISTORY_SIZE
    while [[ ${#LOAD_HISTORY[@]} -gt $MAX_HISTORY_SIZE ]]; do
        # Remove first element (oldest)
        LOAD_HISTORY=("${LOAD_HISTORY[@]:1}")
        LOAD_TIMESTAMPS=("${LOAD_TIMESTAMPS[@]:1}")
    done
}

# -----------------------------------------------------------------------------
# determine_scaling_status - Determine scaling direction based on metrics
# Requirements: 2.3, 2.4 (queue scaling indicators), 3.4, 3.5 (pod scaling indicators)
# Parameters:
#   $1 - Metric type: "queue" or "pods"
#   $2 - Current value
#   $3 - Target/desired value
# Returns: "scaling_up", "scaling_down", or "stable"
# -----------------------------------------------------------------------------
determine_scaling_status() {
    local metric_type="$1"
    local current="$2"
    local target="$3"
    
    # Handle N/A or non-numeric values
    if [[ "$current" == "N/A" ]] || [[ "$target" == "N/A" ]]; then
        echo "stable"
        return 0
    fi
    
    # Ensure values are numeric
    if ! [[ "$current" =~ ^[0-9]+$ ]] || ! [[ "$target" =~ ^[0-9]+$ ]]; then
        echo "stable"
        return 0
    fi
    
    case "$metric_type" in
        "queue")
            # For queue depth: higher than target means scale-up pressure
            # Queue depth > target threshold indicates need for more pods
            if [[ $current -gt $target ]]; then
                echo "scaling_up"
            elif [[ $current -lt $target ]] && [[ $current -eq 0 ]]; then
                # Queue is empty, might scale down
                echo "scaling_down"
            else
                echo "stable"
            fi
            ;;
        "pods")
            # For pods: desired > running means scaling up
            # desired < running means scaling down
            if [[ $target -gt $current ]]; then
                echo "scaling_up"
            elif [[ $target -lt $current ]]; then
                echo "scaling_down"
            else
                echo "stable"
            fi
            ;;
        *)
            # Default comparison: target > current = scaling_up
            if [[ $target -gt $current ]]; then
                echo "scaling_up"
            elif [[ $target -lt $current ]]; then
                echo "scaling_down"
            else
                echo "stable"
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# determine_status_color - Return ANSI color code based on metric type and value
# Requirements: 1.5 (load intensity colors), 5.5 (performance color coding), 7.4 (consistent colors)
# Parameters:
#   $1 - Metric type: "queue", "response", "throughput", "load"
#   $2 - Numeric value
# Returns: ANSI color code string (always returns a valid color)
# -----------------------------------------------------------------------------
determine_status_color() {
    local metric_type="$1"
    local value="$2"
    
    # Handle N/A or non-numeric values - return info color
    if [[ "$value" == "N/A" ]] || [[ -z "$value" ]]; then
        echo "$COLOR_INFO"
        return 0
    fi
    
    # Strip any non-numeric characters for comparison
    local numeric_value
    numeric_value=$(echo "$value" | sed 's/[^0-9.]//g' | cut -d'.' -f1)
    
    # Default to 0 if still not numeric
    if ! [[ "$numeric_value" =~ ^[0-9]+$ ]]; then
        echo "$COLOR_INFO"
        return 0
    fi
    
    case "$metric_type" in
        "queue")
            # Queue depth: low is good, high is bad
            if [[ $numeric_value -ge $THRESHOLD_QUEUE_CRITICAL ]]; then
                echo "$COLOR_ERROR"
            elif [[ $numeric_value -ge $THRESHOLD_QUEUE_HIGH ]]; then
                echo "$COLOR_WARNING"
            elif [[ $numeric_value -ge $THRESHOLD_QUEUE_SCALE_UP ]]; then
                echo "$COLOR_WARNING"
            else
                echo "$COLOR_GOOD"
            fi
            ;;
        "response")
            # Response time: low is good, high is bad
            if [[ $numeric_value -ge $THRESHOLD_RESPONSE_CRITICAL ]]; then
                echo "$COLOR_ERROR"
            elif [[ $numeric_value -ge $THRESHOLD_RESPONSE_WARNING ]]; then
                echo "$COLOR_WARNING"
            elif [[ $numeric_value -ge $THRESHOLD_RESPONSE_GOOD ]]; then
                echo "$COLOR_WARNING"
            else
                echo "$COLOR_GOOD"
            fi
            ;;
        "throughput")
            # Throughput: high is good, low is bad
            if [[ $numeric_value -ge $THRESHOLD_THROUGHPUT_GOOD ]]; then
                echo "$COLOR_GOOD"
            elif [[ $numeric_value -ge $THRESHOLD_THROUGHPUT_LOW ]]; then
                echo "$COLOR_WARNING"
            else
                echo "$COLOR_ERROR"
            fi
            ;;
        "load")
            # Load intensity: neutral coloring (high load is expected, not an error)
            if [[ $numeric_value -ge $THRESHOLD_LOAD_HIGH ]]; then
                echo "$COLOR_INFO"
            elif [[ $numeric_value -ge $THRESHOLD_LOAD_MEDIUM ]]; then
                echo "$COLOR_INFO"
            elif [[ $numeric_value -ge $THRESHOLD_LOAD_LOW ]]; then
                echo "$COLOR_INFO"
            else
                echo "$COLOR_INFO"
            fi
            ;;
        *)
            # Default: return info color for unknown metric types
            echo "$COLOR_INFO"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# determine_target_color - Color based on value relative to KEDA target
# Requirements: 7.4 (consistent colors for proactive scaling visualization)
# Parameters:
#   $1 - Current value
#   $2 - Target value (KEDA scaling target)
# Returns: ANSI color code string
# Logic: GREEN=below target, YELLOW=at/above target, RED=50%+ above target
# -----------------------------------------------------------------------------
determine_target_color() {
    local value="$1"
    local target="$2"
    
    # Handle N/A or non-numeric values
    if [[ "$value" == "N/A" ]] || [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$COLOR_INFO"
        return 0
    fi
    
    # Calculate threshold for red (50% above target)
    local red_threshold=$(( (target * 3) / 2 ))
    
    if [[ $value -ge $red_threshold ]]; then
        echo "$COLOR_ERROR"
    elif [[ $value -ge $target ]]; then
        echo "$COLOR_WARNING"
    else
        echo "$COLOR_GOOD"
    fi
}

# =============================================================================
# ASCII GRAPH RENDERING FUNCTIONS
# =============================================================================
# These functions generate ASCII-based visualizations for the dashboard.
# =============================================================================

# -----------------------------------------------------------------------------
# strip_ansi - Remove ANSI escape codes from a string
# Requirements: 7.3 (measuring printable character count)
# Parameters:
#   $1 - String potentially containing ANSI escape codes
# Returns: String with all ANSI escape codes removed
# -----------------------------------------------------------------------------
strip_ansi() {
    local input="$1"
    # Remove ANSI escape sequences: ESC[ followed by parameters and command character
    # Pattern: \033[ or \e[ followed by digits, semicolons, and ending with a letter
    echo "$input" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\033\[[0-9;]*[a-zA-Z]//g'
}

# -----------------------------------------------------------------------------
# build_ascii_graph - Generate ASCII area graph from load history data
# Requirements: 1.1 (ASCII-based line graph showing request load over time)
# Parameters:
#   None (uses global LOAD_HISTORY array)
# Output:
#   Prints GRAPH_HEIGHT+2 lines (graph + x-axis) to stdout
#   Includes Y-axis label and max value, X-axis shows current time
# Notes:
#   - Graph is rendered top-to-bottom (highest values at top)
#   - Shows an AREA graph with filled bars
#   - Y-axis shows "RPS" and max scale value
#   - X-axis shows current MM:SS timestamp
# -----------------------------------------------------------------------------
build_ascii_graph() {
    local -a history=("${LOAD_HISTORY[@]}")
    local width=$GRAPH_WIDTH
    local height=$GRAPH_HEIGHT
    local history_len=${#history[@]}
    
    # Find max value for scaling (minimum of 10 to have meaningful scale)
    local max_value=10
    for value in "${history[@]}"; do
        if [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            local int_value=${value%.*}
            if [[ $int_value -gt $max_value ]]; then
                max_value=$int_value
            fi
        fi
    done
    
    # Pre-calculate the row for each data point (row = height of bar at this column)
    local -a row_for_col=()
    for (( col = 0; col < width; col++ )); do
        local value=0
        
        if [[ $history_len -eq 0 ]]; then
            row_for_col+=(0)  # No data - zero height
        elif [[ $history_len -ge $width ]]; then
            local history_index=$(( history_len - width + col ))
            value="${history[$history_index]}"
            if ! [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                value=0
            fi
            local int_value=${value%.*}
            # Calculate which row this value maps to (0 = no bar, height = full bar)
            local row=$(( (int_value * height) / max_value ))
            [[ $row -gt $height ]] && row=$height
            row_for_col+=($row)
        else
            local data_start=$(( width - history_len ))
            if [[ $col -lt $data_start ]]; then
                row_for_col+=(0)  # No data yet - zero height
            else
                local history_index=$(( col - data_start ))
                value="${history[$history_index]}"
                if ! [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    value=0
                fi
                local int_value=${value%.*}
                local row=$(( (int_value * height) / max_value ))
                [[ $row -gt $height ]] && row=$height
                row_for_col+=($row)
            fi
        fi
    done
    
    # Build the graph line by line (top to bottom)
    # First line shows max value on Y-axis
    local line
    local row_count=0
    for (( row = height; row >= 1; row-- )); do
        row_count=$((row_count + 1))
        line=""
        for (( col = 0; col < width; col++ )); do
            local bar_height=${row_for_col[$col]}
            if [[ $bar_height -ge $row ]]; then
                line+="█"
            else
                line+="·"
            fi
        done
        
        # Add Y-axis label on first row (max value only)
        # Cap display value to 3 chars (use 'k' suffix for thousands)
        if [[ $row_count -eq 1 ]]; then
            if [[ $max_value -ge 1000 ]]; then
                local display_max=$((max_value / 1000))
                printf "%2dk│%s\n" "$display_max" "$line"
            else
                printf "%3d│%s\n" "$max_value" "$line"
            fi
        else
            printf "   │%s\n" "$line"
        fi
    done
    
    # X-axis line with current time (HH:MM:SS)
    local current_time=$(date '+%H:%M:%S')
    printf "   └%s %s\n" "$(printf '─%.0s' $(seq 1 $((width - 9))))" "$current_time"
}

# =============================================================================
# DATA COLLECTION FUNCTIONS
# =============================================================================
# These functions gather metrics from the Kubernetes cluster via kubectl.
# All functions handle failures gracefully by returning "N/A" on error.
# =============================================================================

# -----------------------------------------------------------------------------
# get_vllm_pods - Query vLLM deployment and pod status
# Requirements: 3.1, 3.2, 3.3, 8.1
# Returns: running|desired|ready|pending|not_ready pipe-separated values
# Pod states: Ready (1/1), NotReady (not 1/1 but running), Pending (not scheduled)
# -----------------------------------------------------------------------------
get_vllm_pods() {
    local desired=0
    local ready=0
    local pending=0
    local not_ready=0
    # Use session-persistent values as starting point (don't reset when pods scale down)
    local startup_min="$SESSION_STARTUP_MIN"
    local startup_max="$SESSION_STARTUP_MAX"
    
    # Query deployment for desired replicas
    local deployment_info
    deployment_info=$(kubectl get deployment "$VLLM_DEPLOYMENT" \
        -n "$VLLM_NAMESPACE" \
        -o jsonpath='{.spec.replicas}|{.status.readyReplicas}' \
        2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$deployment_info" ]]; then
        log_error "Failed to get vLLM deployment status"
        echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A"
        return 1
    fi
    
    desired=$(echo "$deployment_info" | cut -d'|' -f1)
    ready=$(echo "$deployment_info" | cut -d'|' -f2)
    [[ -z "$desired" ]] && desired=0
    [[ -z "$ready" ]] && ready=0
    
    # Query individual pod statuses and startup times
    local pod_data
    pod_data=$(kubectl get pods -n "$VLLM_NAMESPACE" -l "$VLLM_LABEL" \
        -o jsonpath='{range .items[*]}{.status.phase}|{.status.containerStatuses[0].ready}|{.status.conditions[?(@.type=="PodScheduled")].lastTransitionTime}|{.status.conditions[?(@.type=="Ready")].lastTransitionTime}{"\n"}{end}' \
        2>/dev/null)
    
    if [[ -n "$pod_data" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local phase=$(echo "$line" | cut -d'|' -f1)
            local container_ready=$(echo "$line" | cut -d'|' -f2)
            local scheduled_time=$(echo "$line" | cut -d'|' -f3)
            local ready_time=$(echo "$line" | cut -d'|' -f4)
            
            case "$phase" in
                "Running")
                    if [[ "$container_ready" == "true" ]]; then
                        # Calculate startup time for ready pods (1/1 state)
                        if [[ -n "$scheduled_time" ]] && [[ -n "$ready_time" ]] && [[ "$scheduled_time" != "null" ]] && [[ "$ready_time" != "null" ]]; then
                            # Handle both macOS and Linux date parsing
                            local scheduled_epoch=""
                            local ready_epoch=""
                            
                            # Try macOS format first, then Linux
                            if [[ "$OSTYPE" == "darwin"* ]]; then
                                scheduled_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$scheduled_time" "+%s" 2>/dev/null)
                                ready_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ready_time" "+%s" 2>/dev/null)
                            else
                                scheduled_epoch=$(date -d "$scheduled_time" "+%s" 2>/dev/null)
                                ready_epoch=$(date -d "$ready_time" "+%s" 2>/dev/null)
                            fi
                            
                            if [[ -n "$scheduled_epoch" ]] && [[ -n "$ready_epoch" ]] && [[ "$scheduled_epoch" =~ ^[0-9]+$ ]] && [[ "$ready_epoch" =~ ^[0-9]+$ ]]; then
                                local startup_secs=$((ready_epoch - scheduled_epoch))
                                if [[ $startup_secs -ge 0 ]]; then
                                    # Update min if empty or new value is smaller
                                    if [[ -z "$startup_min" ]] || [[ ! "$startup_min" =~ ^[0-9]+$ ]] || [[ $startup_secs -lt $startup_min ]]; then
                                        startup_min=$startup_secs
                                    fi
                                    # Update max if empty or new value is larger
                                    if [[ -z "$startup_max" ]] || [[ ! "$startup_max" =~ ^[0-9]+$ ]] || [[ $startup_secs -gt $startup_max ]]; then
                                        startup_max=$startup_secs
                                    fi
                                fi
                            fi
                        fi
                    else
                        not_ready=$((not_ready + 1))
                    fi
                    ;;
                "Pending")
                    pending=$((pending + 1))
                    ;;
            esac
        done <<< "$pod_data"
    fi
    
    # Calculate running as ready + not_ready (excludes pending)
    local running=$((ready + not_ready))
    
    # Update session-persistent values (only if we found new data)
    if [[ -n "$startup_min" ]] && [[ "$startup_min" =~ ^[0-9]+$ ]]; then
        SESSION_STARTUP_MIN="$startup_min"
    fi
    if [[ -n "$startup_max" ]] && [[ "$startup_max" =~ ^[0-9]+$ ]]; then
        SESSION_STARTUP_MAX="$startup_max"
    fi
    
    # Format startup times for output (use session values, N/A if not available)
    local output_min="${SESSION_STARTUP_MIN:-N/A}"
    local output_max="${SESSION_STARTUP_MAX:-N/A}"
    [[ -z "$output_min" ]] && output_min="N/A"
    [[ -z "$output_max" ]] && output_max="N/A"
    
    echo "${running}|${desired}|${ready}|${pending}|${not_ready}|${output_min}|${output_max}"
    return 0
}

# -----------------------------------------------------------------------------
# OTel Prometheus endpoint configuration
# -----------------------------------------------------------------------------
OTEL_PROMETHEUS_SERVICE="otel-vllm-metrics"
OTEL_PROMETHEUS_NAMESPACE="keda"
OTEL_PROMETHEUS_PORT=8889
OTEL_LOCAL_PORT=18889
OTEL_PORT_FORWARD_PID=""

# -----------------------------------------------------------------------------
# start_port_forward - Start kubectl port-forward to OTel Prometheus endpoint
# Returns: 0 on success, 1 on failure
# Side effects: Sets OTEL_PORT_FORWARD_PID with the background process ID
# -----------------------------------------------------------------------------
start_port_forward() {
    # Check if port-forward is already running
    if [[ -n "$OTEL_PORT_FORWARD_PID" ]] && kill -0 "$OTEL_PORT_FORWARD_PID" 2>/dev/null; then
        return 0
    fi
    
    # Start port-forward in background
    kubectl port-forward -n "$OTEL_PROMETHEUS_NAMESPACE" \
        "svc/$OTEL_PROMETHEUS_SERVICE" \
        "$OTEL_LOCAL_PORT:$OTEL_PROMETHEUS_PORT" \
        >/dev/null 2>&1 &
    OTEL_PORT_FORWARD_PID=$!
    
    # Wait briefly for port-forward to establish
    sleep 0.5
    
    # Verify it's running
    if kill -0 "$OTEL_PORT_FORWARD_PID" 2>/dev/null; then
        log_info "Started port-forward to OTel Prometheus (PID: $OTEL_PORT_FORWARD_PID)"
        return 0
    else
        OTEL_PORT_FORWARD_PID=""
        log_error "Failed to start port-forward to OTel Prometheus"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# stop_port_forward - Stop the kubectl port-forward process
# Side effects: Kills the port-forward process and clears OTEL_PORT_FORWARD_PID
# -----------------------------------------------------------------------------
stop_port_forward() {
    if [[ -n "$OTEL_PORT_FORWARD_PID" ]]; then
        kill "$OTEL_PORT_FORWARD_PID" 2>/dev/null
        wait "$OTEL_PORT_FORWARD_PID" 2>/dev/null
        log_info "Stopped port-forward (PID: $OTEL_PORT_FORWARD_PID)"
        OTEL_PORT_FORWARD_PID=""
    fi
}

# -----------------------------------------------------------------------------
# get_otel_metrics_raw - Get raw metrics from OTel Prometheus endpoint
# Requirements: 2.1, 5.1, 8.1
# Returns: Raw Prometheus metrics output, or empty string on failure
# Note: Uses kubectl port-forward for fast, persistent connection
# -----------------------------------------------------------------------------
OTEL_METRICS_CACHE=""
OTEL_METRICS_CACHE_TIME=0

get_otel_metrics_raw() {
    local current_time=$(date +%s)
    
    # Return cached result if less than 2 seconds old
    if [[ -n "$OTEL_METRICS_CACHE" ]] && [[ $((current_time - OTEL_METRICS_CACHE_TIME)) -lt 2 ]]; then
        echo "$OTEL_METRICS_CACHE"
        return 0
    fi
    
    # Ensure port-forward is running
    if ! start_port_forward; then
        return 1
    fi
    
    # Query the local port-forwarded endpoint using curl
    local metrics_output
    metrics_output=$(curl -s --max-time 2 "http://localhost:$OTEL_LOCAL_PORT/metrics" 2>/dev/null)
    
    if [[ -n "$metrics_output" ]]; then
        OTEL_METRICS_CACHE="$metrics_output"
        OTEL_METRICS_CACHE_TIME=$current_time
        echo "$metrics_output"
        return 0
    fi
    
    # Port-forward might have died, try to restart it
    stop_port_forward
    if start_port_forward; then
        sleep 0.3
        metrics_output=$(curl -s --max-time 2 "http://localhost:$OTEL_LOCAL_PORT/metrics" 2>/dev/null)
        if [[ -n "$metrics_output" ]]; then
            OTEL_METRICS_CACHE="$metrics_output"
            OTEL_METRICS_CACHE_TIME=$current_time
            echo "$metrics_output"
            return 0
        fi
    fi
    
    return 1
}

# -----------------------------------------------------------------------------
# parse_metric_from_raw - Parse a specific metric from raw Prometheus output
# Parameters:
#   $1 - Raw metrics output
#   $2 - Metric name to parse (use underscore format, will also match colons)
#   $3 - (optional) "sum" to sum all values, "first" to get first value
# Returns: Metric value, or empty string if not found
# Note: Handles both underscore (vllm_metric) and colon (vllm:metric) formats
# -----------------------------------------------------------------------------
parse_metric_from_raw() {
    local raw_metrics="$1"
    local metric_name="$2"
    local mode="${3:-sum}"
    
    local total=0
    local found=false
    local first_value=""
    
    # Create colon variant by replacing first underscore with colon
    # e.g., vllm_request_success_total -> vllm:request_success_total
    local colon_name="${metric_name/_/:}"
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Check if line starts with either metric name variant
        local match=false
        case "$line" in
            "${metric_name}{"*|"${metric_name} "*)
                match=true
                ;;
            "${colon_name}{"*|"${colon_name} "*)
                match=true
                ;;
        esac
        
        if [[ "$match" == "true" ]]; then
            # Extract the numeric value (second-to-last field if timestamp present, else last)
            # OTel Prometheus format: metric{labels} value timestamp
            # Standard format: metric{labels} value
            local num_fields=$(echo "$line" | awk '{print NF}')
            local value
            if [[ $num_fields -ge 3 ]]; then
                # Has timestamp, get second-to-last field
                value=$(echo "$line" | awk '{print $(NF-1)}')
            else
                # No timestamp, get last field
                value=$(echo "$line" | awk '{print $NF}')
            fi
            if [[ "$value" =~ ^[0-9]+\.?[0-9]*([eE][+-]?[0-9]+)?$ ]]; then
                found=true
                if [[ "$mode" == "first" ]] && [[ -z "$first_value" ]]; then
                    first_value="$value"
                else
                    # Convert to integer and add to total
                    local int_value=${value%.*}
                    # Handle scientific notation
                    if [[ "$value" =~ [eE] ]]; then
                        int_value=$(printf "%.0f" "$value" 2>/dev/null || echo "0")
                    fi
                    total=$((total + int_value))
                fi
            fi
        fi
    done <<< "$raw_metrics"
    
    if [[ "$found" == "true" ]]; then
        if [[ "$mode" == "first" ]]; then
            echo "$first_value"
        else
            echo "$total"
        fi
        return 0
    fi
    
    return 1
}

# -----------------------------------------------------------------------------
# get_queue_depth - Query OTel Prometheus for current vLLM queue depth metric
# Requirements: 2.1, 8.1
# Returns: queue_depth|running_requests pipe-separated values, or "0|0" on failure
# Note: Uses OTel Prometheus endpoint (fast, <1 second)
# -----------------------------------------------------------------------------
get_queue_depth() {
    local queue_depth=""
    local running_requests=""
    
    # Get raw metrics from OTel Prometheus endpoint
    local raw_metrics
    raw_metrics=$(get_otel_metrics_raw 2>/dev/null)
    
    if [[ -n "$raw_metrics" ]]; then
        # Parse vllm_num_requests_waiting (sum across all pods)
        queue_depth=$(parse_metric_from_raw "$raw_metrics" "vllm_num_requests_waiting" "sum")
        # Parse vllm_num_requests_running (sum across all pods)
        running_requests=$(parse_metric_from_raw "$raw_metrics" "vllm_num_requests_running" "sum")
        
        # Validate and default values
        [[ ! "$queue_depth" =~ ^[0-9]+$ ]] && queue_depth=0
        [[ ! "$running_requests" =~ ^[0-9]+$ ]] && running_requests=0
        
        echo "${queue_depth}|${running_requests}"
        return 0
    fi
    
    # Fallback to HPA if OTel is not available (only for queue depth)
    local hpa_metrics
    hpa_metrics=$(kubectl get hpa "keda-hpa-vllm-queue-scaler" \
        -n "$VLLM_NAMESPACE" \
        -o jsonpath='{.status.currentMetrics[0].external.current.averageValue}' \
        2>/dev/null)
    
    if [[ -n "$hpa_metrics" ]] && [[ "$hpa_metrics" != "null" ]]; then
        queue_depth=$(echo "$hpa_metrics" | sed 's/[^0-9.]//g' | cut -d'.' -f1)
        if [[ -n "$queue_depth" ]] && [[ "$queue_depth" =~ ^[0-9]+$ ]]; then
            echo "${queue_depth}|0"
            return 0
        fi
    fi
    
    # Default to 0|0 if no metrics available (system is idle)
    echo "0|0"
    return 0
}

# -----------------------------------------------------------------------------
# get_node_info - Query kubectl for GPU nodes managed by Karpenter
# Requirements: 4.1, 4.2, 8.1
# Returns: ready_count|pending_count|nodeclaims_pending|ondemand_count|spot_count pipe-separated values
# Node states: Ready (green), NotReady/Pending (yellow), NodeClaim only (yellow)
# -----------------------------------------------------------------------------
get_node_info() {
    local ready_count=0
    local pending_count=0
    local nodeclaims_pending=0
    local ondemand_count=0
    local spot_count=0
    
    # Query nodes with Karpenter nodepool label and get their status and capacity type
    local node_data
    node_data=$(kubectl get nodes \
        -l "karpenter.sh/nodepool=gpu-inference" \
        -o jsonpath='{range .items[*]}{.metadata.name}|{.status.conditions[?(@.type=="Ready")].status}|{.metadata.labels.karpenter\.sh/capacity-type}{"\n"}{end}' \
        2>/dev/null)
    
    # If no nodes found with primary label, try alternative
    if [[ -z "$node_data" ]]; then
        node_data=$(kubectl get nodes \
            -l "intent=gpu-inference" \
            -o jsonpath='{range .items[*]}{.metadata.name}|{.status.conditions[?(@.type=="Ready")].status}|{.metadata.labels.karpenter\.sh/capacity-type}{"\n"}{end}' \
            2>/dev/null)
    fi
    
    # Count ready vs not-ready nodes and capacity types
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local status=$(echo "$line" | cut -d'|' -f2)
        local capacity_type=$(echo "$line" | cut -d'|' -f3)
        
        if [[ "$status" == "True" ]]; then
            ready_count=$((ready_count + 1))
            # Count capacity types only for ready nodes
            if [[ "$capacity_type" == "spot" ]]; then
                spot_count=$((spot_count + 1))
            else
                ondemand_count=$((ondemand_count + 1))
            fi
        else
            pending_count=$((pending_count + 1))
        fi
    done <<< "$node_data"
    
    # Check for pending NodeClaims (nodes being provisioned by Karpenter)
    # NodeClaims exist before the actual Node is created
    local nodeclaim_count=0
    local node_count=$((ready_count + pending_count))
    
    nodeclaim_count=$(kubectl get nodeclaims \
        -l "karpenter.sh/nodepool=gpu-inference" \
        -o name 2>/dev/null | wc -l | tr -d ' ')
    
    # Pending nodeclaims = nodeclaims that don't have a corresponding node yet
    if [[ $nodeclaim_count -gt $node_count ]]; then
        nodeclaims_pending=$((nodeclaim_count - node_count))
    fi
    
    echo "${ready_count}|${pending_count}|${nodeclaims_pending}|${ondemand_count}|${spot_count}"
    return 0
}

# -----------------------------------------------------------------------------
# get_pod_timing_info - Collect vLLM pod timing information
# Returns: Pipe-separated lines: name|phase|ready_status|start_time|ready_time
# -----------------------------------------------------------------------------
get_pod_timing_info() {
    kubectl get pods -n default -l app=vllm -o json 2>/dev/null | jq -r '
        .items[] | 
        {
            name: .metadata.name,
            phase: .status.phase,
            startTime: .status.startTime,
            readyCondition: (.status.conditions[] | select(.type=="Ready"))
        } |
        .name + "|" + 
        .phase + "|" + 
        (if .readyCondition.status == "True" then "Ready" else "NotReady" end) + "|" +
        .startTime + "|" +
        (if .readyCondition.status == "True" then .readyCondition.lastTransitionTime else "" end)
    ' 2>/dev/null || echo ""
}

# -----------------------------------------------------------------------------
# get_performance_metrics - Get throughput and latency from OTel Prometheus
# Requirements: 5.1, 5.2, 5.3, 5.4
# Returns: throughput|p50|p95|p99|avg|request_count|tokens_per_sec pipe-separated values
# Note: Uses OTel Prometheus endpoint for real vLLM metrics
# Note: Shows N/A for latency when no active requests (queue=0, running=0)
# -----------------------------------------------------------------------------
get_performance_metrics() {
    local throughput="N/A"
    local ttft_p50="N/A"
    local ttft_p95="N/A"
    local itl_p50="N/A"
    local itl_p95="N/A"
    local e2e_avg="N/A"
    local e2e_p50="N/A"
    local e2e_p95="N/A"
    local tokens_per_req="N/A"
    local request_count=0
    local tokens_per_sec="N/A"
    local kv_cache_pct="N/A"
    
    # Get raw metrics from OTel Prometheus endpoint
    local raw_metrics
    raw_metrics=$(get_otel_metrics_raw 2>/dev/null)
    
    if [[ -n "$raw_metrics" ]]; then
        # Get request count for RPS calculation
        local total_requests
        total_requests=$(echo "$raw_metrics" | awk '/^vllm[:_]request_success_total/ {sum+=$2} END {print int(sum)}')
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: total_requests=$total_requests" >> "$ERROR_LOG" 2>/dev/null
        if [[ -n "$total_requests" ]] && [[ "$total_requests" =~ ^[0-9]+$ ]]; then
            request_count=$total_requests
        fi
        
        # Calculate actual RPS from rate of change of vllm_request_success_total
        local current_time=$(date +%s)
        
        # Load previous state from file
        if [[ -f /tmp/dashboard-state.txt ]]; then
            source /tmp/dashboard-state.txt
        fi
        
        if [[ -n "$total_requests" ]] && [[ "$total_requests" =~ ^[0-9]+$ ]]; then
            if [[ $LAST_REQUESTS_TIME -gt 0 ]] && [[ $LAST_REQUESTS_TOTAL -gt 0 ]]; then
                local time_diff=$((current_time - LAST_REQUESTS_TIME))
                local request_diff=$((total_requests - LAST_REQUESTS_TOTAL))
                if [[ $time_diff -gt 0 ]] && [[ $request_diff -ge 0 ]]; then
                    throughput=$((request_diff / time_diff))
                fi
            else
                # First iteration - set to 0 instead of N/A
                throughput=0
            fi
            # Save state to file
            echo "LAST_REQUESTS_TOTAL=$total_requests" > /tmp/dashboard-state.txt
            echo "LAST_REQUESTS_TIME=$current_time" >> /tmp/dashboard-state.txt
        fi
        
        # Get running requests to check if there's active load (optional metric)
        local running_requests
        running_requests=$(parse_metric_from_raw "$raw_metrics" "vllm_num_requests_running" "sum")
        
        # Calculate tokens/s from generation_tokens_total (rate over time)
        local current_tokens
        current_tokens=$(parse_metric_from_raw "$raw_metrics" "vllm_generation_tokens_total" "sum")
        
        # Load token state from file
        if [[ -f /tmp/dashboard-state.txt ]]; then
            source /tmp/dashboard-state.txt
        fi
        
        if [[ -n "$current_tokens" ]] && [[ "$current_tokens" =~ ^[0-9]+$ ]]; then
            if [[ $LAST_TOKENS_TIME -gt 0 ]] && [[ $LAST_TOKENS_TOTAL -gt 0 ]]; then
                local time_diff=$((current_time - LAST_TOKENS_TIME))
                local token_diff=$((current_tokens - LAST_TOKENS_TOTAL))
                if [[ $time_diff -gt 0 ]] && [[ $token_diff -ge 0 ]]; then
                    tokens_per_sec=$((token_diff / time_diff))
                fi
            fi
            # Save token state to file
            echo "LAST_TOKENS_TOTAL=$current_tokens" >> /tmp/dashboard-state.txt
            echo "LAST_TOKENS_TIME=$current_time" >> /tmp/dashboard-state.txt
        fi
        
        # Calculate tokens per request (generation + prompt tokens / total requests)
        local prompt_tokens
        prompt_tokens=$(parse_metric_from_raw "$raw_metrics" "vllm_prompt_tokens_total" "sum")
        if [[ -n "$current_tokens" ]] && [[ "$current_tokens" =~ ^[0-9]+$ ]] && \
           [[ -n "$prompt_tokens" ]] && [[ "$prompt_tokens" =~ ^[0-9]+$ ]] && \
           [[ -n "$total_requests" ]] && [[ "$total_requests" =~ ^[0-9]+$ ]] && [[ "$total_requests" -gt 0 ]]; then
            tokens_per_req=$(( (current_tokens + prompt_tokens) / total_requests ))
        fi
        
        # Get KV cache usage percentage (0-100)
        # Try both metric names: vllm_kv_cache_usage_perc (vLLM 0.13+) and vllm_gpu_cache_usage_perc (older)
        local kv_cache_raw
        kv_cache_raw=$(parse_metric_from_raw "$raw_metrics" "vllm_kv_cache_usage_perc" "avg")
        if [[ -z "$kv_cache_raw" ]] || [[ ! "$kv_cache_raw" =~ ^[0-9.]+$ ]]; then
            kv_cache_raw=$(parse_metric_from_raw "$raw_metrics" "vllm_gpu_cache_usage_perc" "avg")
        fi
        if [[ -n "$kv_cache_raw" ]] && [[ "$kv_cache_raw" =~ ^[0-9.]+$ ]]; then
            # Convert from 0-1 to 0-100 percentage
            kv_cache_pct=$(printf "%.0f" $(echo "$kv_cache_raw * 100" | bc 2>/dev/null))
            [[ -z "$kv_cache_pct" ]] && kv_cache_pct="N/A"
        fi
        
        # Get waiting requests to check if there's active load (optional metric)
        local waiting_requests
        waiting_requests=$(parse_metric_from_raw "$raw_metrics" "vllm_num_requests_waiting" "sum")
        
        # Determine if there's active load - use throughput as primary indicator
        # Fall back to queue metrics if available
        local has_active_load=false
        if [[ "$throughput" =~ ^[0-9]+$ ]] && [[ "$throughput" -gt 0 ]]; then
            has_active_load=true
        elif [[ -n "$running_requests" ]] && [[ "$running_requests" =~ ^[0-9]+$ ]] && [[ "$running_requests" -gt 0 ]]; then
            has_active_load=true
        elif [[ -n "$waiting_requests" ]] && [[ "$waiting_requests" =~ ^[0-9]+$ ]] && [[ "$waiting_requests" -gt 0 ]]; then
            has_active_load=true
        fi
        
        # Parse TTFT (Time To First Token) histogram buckets for percentiles
        # Uses awk to aggregate across multiple pods and calculate percentiles
        # Format: metric{labels,le="X"} count [timestamp]
        local ttft_data=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^vllm[_:]time_to_first_token_seconds_bucket ]]; then
                ttft_data+="$line"$'\n'
            fi
        done <<< "$raw_metrics"
        
        if [[ -n "$ttft_data" ]]; then
            local ttft_result
            ttft_result=$(echo "$ttft_data" | awk -F'} ' '
            BEGIN { n = 0 }
            NF < 2 { next }
            {
                # Field 1 is metric{labels, Field 2 is "count [timestamp]"
                labels = $1
                values = $2
                
                # Extract le value from labels
                if (index(labels, "le=\"") == 0) next
                le_part = labels
                sub(/.*le="/, "", le_part)
                sub(/".*/, "", le_part)
                le = le_part
                if (le == "" || le == "+Inf") next
                
                # Extract count (first number in values field)
                split(values, parts, " ")
                count = parts[1]
                # Handle scientific notation or floats by converting to int
                if (count ~ /^[0-9]+\.?[0-9]*([eE][+-]?[0-9]+)?$/) {
                    count = int(count + 0.5)
                } else {
                    next
                }
                
                # Aggregate by bucket across all pods
                bucket_count[le] += count
                if (!(le in seen)) {
                    buckets[n++] = le
                    seen[le] = 1
                }
            }
            END {
                if (n == 0) exit
                # Sort buckets numerically
                for (i = 0; i < n-1; i++) {
                    for (j = i+1; j < n; j++) {
                        if (buckets[i]+0 > buckets[j]+0) {
                            tmp = buckets[i]
                            buckets[i] = buckets[j]
                            buckets[j] = tmp
                        }
                    }
                }
                total = bucket_count[buckets[n-1]]
                if (total <= 0) exit
                p50_target = int(total / 2)
                p95_target = int(total * 95 / 100)
                p50 = "N/A"; p95 = "N/A"
                for (i = 0; i < n; i++) {
                    le = buckets[i]
                    cnt = bucket_count[le]
                    ms = int(le * 1000)
                    if (p50 == "N/A" && cnt >= p50_target) p50 = ms
                    if (p95 == "N/A" && cnt >= p95_target) p95 = ms
                }
                print p50 "|" p95
            }')
            if [[ -n "$ttft_result" ]]; then
                ttft_p50=$(echo "$ttft_result" | cut -d'|' -f1)
                ttft_p95=$(echo "$ttft_result" | cut -d'|' -f2)
            fi
        fi
        
        # Parse ITL (Inter-Token Latency) histogram buckets for percentiles
        # Uses awk to aggregate across multiple pods and calculate percentiles
        # Format: metric{labels,le="X"} count [timestamp]
        local itl_data=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^vllm[_:]request_time_per_output_token_seconds_bucket ]]; then
                itl_data+="$line"$'\n'
            fi
        done <<< "$raw_metrics"
        
        if [[ -n "$itl_data" ]]; then
            local itl_result
            itl_result=$(echo "$itl_data" | awk -F'} ' '
            BEGIN { n = 0 }
            NF < 2 { next }
            {
                # Field 1 is metric{labels, Field 2 is "count [timestamp]"
                labels = $1
                values = $2
                
                # Extract le value from labels
                if (index(labels, "le=\"") == 0) next
                le_part = labels
                sub(/.*le="/, "", le_part)
                sub(/".*/, "", le_part)
                le = le_part
                if (le == "" || le == "+Inf") next
                
                # Extract count (first number in values field)
                split(values, parts, " ")
                count = parts[1]
                # Handle scientific notation or floats by converting to int
                if (count ~ /^[0-9]+\.?[0-9]*([eE][+-]?[0-9]+)?$/) {
                    count = int(count + 0.5)
                } else {
                    next
                }
                
                # Aggregate by bucket across all pods
                bucket_count[le] += count
                if (!(le in seen)) {
                    buckets[n++] = le
                    seen[le] = 1
                }
            }
            END {
                if (n == 0) exit
                # Sort buckets numerically
                for (i = 0; i < n-1; i++) {
                    for (j = i+1; j < n; j++) {
                        if (buckets[i]+0 > buckets[j]+0) {
                            tmp = buckets[i]
                            buckets[i] = buckets[j]
                            buckets[j] = tmp
                        }
                    }
                }
                total = bucket_count[buckets[n-1]]
                if (total <= 0) exit
                p50_target = int(total / 2)
                p95_target = int(total * 95 / 100)
                p50 = "N/A"; p95 = "N/A"
                for (i = 0; i < n; i++) {
                    le = buckets[i]
                    cnt = bucket_count[le]
                    ms = int(le * 1000)
                    if (p50 == "N/A" && cnt >= p50_target) p50 = ms
                    if (p95 == "N/A" && cnt >= p95_target) p95 = ms
                }
                print p50 "|" p95
            }')
            if [[ -n "$itl_result" ]]; then
                itl_p50=$(echo "$itl_result" | cut -d'|' -f1)
                itl_p95=$(echo "$itl_result" | cut -d'|' -f2)
            fi
        fi
        
        # Calculate average latency from histogram sum and count
        # vllm:e2e_request_latency_seconds_sum / vllm:e2e_request_latency_seconds_count
        local latency_sum
        local latency_count
        latency_sum=$(echo "$raw_metrics" | awk '/^vllm[:_]e2e_request_latency_seconds_sum/ {sum+=$2} END {print sum}')
        latency_count=$(echo "$raw_metrics" | awk '/^vllm[:_]e2e_request_latency_seconds_count/ {sum+=$2} END {print int(sum)}')
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: latency_sum=$latency_sum, latency_count=$latency_count" >> "$ERROR_LOG" 2>/dev/null
        
        if [[ -n "$latency_sum" ]] && [[ -n "$latency_count" ]] && [[ "$latency_count" =~ ^[0-9]+$ ]] && [[ $latency_count -gt 0 ]]; then
            # Calculate average e2e latency in milliseconds
            local avg_seconds
            avg_seconds=$(echo "scale=3; $latency_sum / $latency_count" | bc 2>/dev/null)
            if [[ -n "$avg_seconds" ]]; then
                e2e_avg=$(printf "%.0f" $(echo "$avg_seconds * 1000" | bc 2>/dev/null))
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: e2e_avg=$e2e_avg" >> "$ERROR_LOG" 2>/dev/null
                [[ -z "$e2e_avg" ]] && e2e_avg="N/A"
            fi
        fi
        
        # Calculate E2E p50 and p95 from histogram buckets
        local e2e_data=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^vllm[:_]e2e_request_latency_seconds_bucket ]]; then
                e2e_data+="$line"$'\n'
            fi
        done <<< "$raw_metrics"
        
        if [[ -n "$e2e_data" ]]; then
            # Bash 3.2 and BSD awk compatible: use -F'} ' to split on closing brace
            local e2e_result
            e2e_result=$(echo "$e2e_data" | awk -F'} ' '
            BEGIN { n = 0 }
            NF < 2 { next }
            {
                # Field 1 is metric{labels, Field 2 is "count [timestamp]"
                labels = $1
                values = $2
                
                # Extract le value from labels
                if (index(labels, "le=\"") == 0) next
                le_part = labels
                sub(/.*le="/, "", le_part)
                sub(/".*/, "", le_part)
                le = le_part
                if (le == "" || le == "+Inf") next
                
                # Extract count (first number in values field)
                split(values, parts, " ")
                count = parts[1]
                # Handle scientific notation or floats by converting to int
                if (count ~ /^[0-9]+\.?[0-9]*([eE][+-]?[0-9]+)?$/) {
                    count = int(count + 0.5)
                } else {
                    next
                }
                
                # Aggregate by bucket
                bucket_count[le] += count
                if (!(le in seen)) {
                    buckets[n++] = le
                    seen[le] = 1
                }
            }
            END {
                if (n == 0) exit
                # Sort buckets numerically
                for (i = 0; i < n-1; i++) {
                    for (j = i+1; j < n; j++) {
                        if (buckets[i]+0 > buckets[j]+0) {
                            tmp = buckets[i]
                            buckets[i] = buckets[j]
                            buckets[j] = tmp
                        }
                    }
                }
                # Total is the highest bucket count
                total = bucket_count[buckets[n-1]]
                if (total <= 0) exit
                p50_target = int(total / 2)
                p95_target = int(total * 95 / 100)
                p50 = "N/A"; p95 = "N/A"
                for (i = 0; i < n; i++) {
                    le = buckets[i]
                    cnt = bucket_count[le]
                    ms = int(le * 1000)
                    if (p50 == "N/A" && cnt >= p50_target) p50 = ms
                    if (p95 == "N/A" && cnt >= p95_target) p95 = ms
                }
                print p50 "|" p95
            }')
            if [[ -n "$e2e_result" ]]; then
                local e2e_p50_val="${e2e_result%%|*}"
                local e2e_p95_val="${e2e_result##*|}"
                [[ "$e2e_p50_val" != "N/A" ]] && e2e_p50="$e2e_p50_val"
                [[ "$e2e_p95_val" != "N/A" ]] && e2e_p95="$e2e_p95_val"
            fi
        fi
    fi
    
    # Debug: log all values right before output
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: FINAL VALUES - throughput=$throughput ttft_p50=$ttft_p50 ttft_p95=$ttft_p95 itl_p50=$itl_p50 itl_p95=$itl_p95 e2e_avg=$e2e_avg e2e_p50=$e2e_p50 e2e_p95=$e2e_p95 tokens_per_req=$tokens_per_req request_count=$request_count tokens_per_sec=$tokens_per_sec kv_cache_pct=$kv_cache_pct" >> "$ERROR_LOG" 2>/dev/null
    
    # Output the metrics: throughput|ttft_p50|ttft_p95|itl_p50|itl_p95|e2e_avg|e2e_p50|e2e_p95|tokens_per_req|request_count|tokens_per_sec|kv_cache_pct
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: OUTPUT=${throughput}|${ttft_p50}|${ttft_p95}|${itl_p50}|${itl_p95}|${e2e_avg}|${e2e_p50}|${e2e_p95}|${tokens_per_req}|${request_count}|${tokens_per_sec}|${kv_cache_pct}" >> "$ERROR_LOG" 2>/dev/null
    echo "${throughput}|${ttft_p50}|${ttft_p95}|${itl_p50}|${itl_p95}|${e2e_avg}|${e2e_p50}|${e2e_p95}|${tokens_per_req}|${request_count}|${tokens_per_sec}|${kv_cache_pct}"
    
    # Log tracking variables to file for debugging (not to stdout)
    {
        echo "$(date '+%H:%M:%S') - LAST_REQUESTS_TOTAL=$LAST_REQUESTS_TOTAL"
        echo "$(date '+%H:%M:%S') - LAST_REQUESTS_TIME=$LAST_REQUESTS_TIME"
        echo "$(date '+%H:%M:%S') - LAST_TOKENS_TOTAL=$LAST_TOKENS_TOTAL"
        echo "$(date '+%H:%M:%S') - LAST_TOKENS_TIME=$LAST_TOKENS_TIME"
        echo "$(date '+%H:%M:%S') - throughput=$throughput"
    } >> /tmp/dashboard-debug.log 2>&1
    
    return 0
}

# -----------------------------------------------------------------------------
# check_k6_job_status - Check k6 load test job status and extract results
# Requirements: Monitor k6 job completion and parse final results
# Side effects:
#   - Updates K6_JOB_STATUS, K6_TOTAL_REQUESTS, K6_RPS, etc.
#   - Only checks every 10 seconds to avoid kubectl spam
# Returns: 0 on success
# -----------------------------------------------------------------------------
check_k6_job_status() {
    local current_time=$(date +%s)
    
    # Only check every 10 seconds to reduce kubectl calls
    if [[ $((current_time - K6_LAST_CHECK)) -lt 10 ]]; then
        return 0
    fi
    K6_LAST_CHECK=$current_time
    
    # Check if k6 job exists
    local job_status
    job_status=$(kubectl get job k6-load-test -n default -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    local job_failed
    job_failed=$(kubectl get job k6-load-test -n default -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
    
    if [[ "$job_status" == "True" ]]; then
        # Job completed - extract results from logs if not already done
        if [[ "$K6_JOB_STATUS" != "completed" ]]; then
            K6_JOB_STATUS="completed"
            parse_k6_results
        fi
    elif [[ "$job_failed" == "True" ]]; then
        # Job failed - but might still have results if stopped gracefully with SIGTERM
        # k6 prints summary on SIGTERM before exiting, so try to parse results
        if [[ "$K6_JOB_STATUS" != "completed" ]] && [[ "$K6_JOB_STATUS" != "failed" ]]; then
            K6_JOB_STATUS="completed"  # Treat as completed to show results
            parse_k6_results
            # If no results found, mark as failed
            if [[ -z "$K6_TOTAL_REQUESTS" ]]; then
                K6_JOB_STATUS="failed"
            fi
        fi
    elif kubectl get job k6-load-test -n default &>/dev/null; then
        K6_JOB_STATUS="running"
    else
        K6_JOB_STATUS=""
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# parse_k6_results - Parse k6 job logs to extract final test results
# Requirements: Extract http_reqs, http_req_duration, http_req_failed from k6 output
# Side effects:
#   - Updates K6_TOTAL_REQUESTS, K6_RPS, K6_AVG_DURATION, K6_MIN_DURATION, K6_MED_DURATION,
#     K6_MAX_DURATION, K6_P90_DURATION, K6_P95_DURATION, K6_FAILURE_RATE
# -----------------------------------------------------------------------------
parse_k6_results() {
    local logs
    logs=$(kubectl logs job/k6-load-test -n default 2>/dev/null | tail -100)
    
    if [[ -z "$logs" ]]; then
        log_warning "Could not retrieve k6 job logs"
        return 1
    fi
    
    # Extract http_reqs line: http_reqs......................: 17630  36.71276/s
    local reqs_line
    reqs_line=$(echo "$logs" | grep -E "http_reqs\.+:" | head -1)
    if [[ -n "$reqs_line" ]]; then
        # Extract total requests (first number)
        K6_TOTAL_REQUESTS=$(echo "$reqs_line" | awk '{print $2}')
        # Extract RPS (number before /s)
        K6_RPS=$(echo "$reqs_line" | grep -oE '[0-9]+\.[0-9]+/s' | sed 's|/s||')
    fi
    
    # Extract http_req_duration line: avg=735.24ms min=355.83ms med=673.23ms max=1.18s p(90)=1s p(95)=1.04s
    local duration_line
    duration_line=$(echo "$logs" | grep -E "http_req_duration\.+:" | head -1)
    if [[ -n "$duration_line" ]]; then
        # Extract all duration metrics
        K6_AVG_DURATION=$(echo "$duration_line" | grep -oE 'avg=[0-9.]+[ms]*' | sed 's/avg=//')
        K6_MIN_DURATION=$(echo "$duration_line" | grep -oE 'min=[0-9.]+[ms]*' | sed 's/min=//')
        K6_MED_DURATION=$(echo "$duration_line" | grep -oE 'med=[0-9.]+[ms]*' | sed 's/med=//')
        K6_MAX_DURATION=$(echo "$duration_line" | grep -oE 'max=[0-9.]+[ms]*' | sed 's/max=//')
        K6_P90_DURATION=$(echo "$duration_line" | grep -oE 'p\(90\)=[0-9.]+[ms]*' | sed 's/p(90)=//')
        K6_P95_DURATION=$(echo "$duration_line" | grep -oE 'p\(95\)=[0-9.]+[ms]*' | sed 's/p(95)=//')
    fi
    
    # Extract http_req_failed line: http_req_failed................: 0.00%  0 out of 17630
    local failed_line
    failed_line=$(echo "$logs" | grep -E "http_req_failed\.+:" | head -1)
    if [[ -n "$failed_line" ]]; then
        K6_FAILURE_RATE=$(echo "$failed_line" | grep -oE '[0-9.]+%' | head -1)
    fi
    
    log_info "k6 results parsed: reqs=$K6_TOTAL_REQUESTS, rps=$K6_RPS, avg=$K6_AVG_DURATION, min=$K6_MIN_DURATION, med=$K6_MED_DURATION, max=$K6_MAX_DURATION, p90=$K6_P90_DURATION, p95=$K6_P95_DURATION, failed=$K6_FAILURE_RATE"
    return 0
}

# =============================================================================
# DISPLAY RENDERER FUNCTIONS
# =============================================================================
# These functions handle all terminal output and visual formatting.
# Each function renders a specific section of the dashboard.
# =============================================================================

# -----------------------------------------------------------------------------
# get_elapsed_time - Calculate elapsed time since dashboard started
# Requirements: 6.4 (elapsed time display)
# Returns: Formatted elapsed time string (HH:MM:SS)
# -----------------------------------------------------------------------------
get_elapsed_time() {
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

# -----------------------------------------------------------------------------
# render_header - Display dashboard title with box-drawing characters
# Requirements: 7.2 (box-drawing characters), 7.5 (header with demo title),
#               6.3 (timestamp), 6.4 (elapsed time)
# Output: Renders header section to stdout (fits within 80 columns)
# -----------------------------------------------------------------------------
render_header() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local elapsed
    elapsed=$(get_elapsed_time)
    
    local title="vLLM Autoscaling Demo Dashboard"
    local subtitle="KEDA + Karpenter on Amazon EKS"
    local title_len=${#title}
    local subtitle_len=${#subtitle}
    
    # Calculate padding for centering (80 - 2 borders = 78 inner width)
    local inner_width=78
    local title_padding=$(( (inner_width - title_len) / 2 ))
    local subtitle_padding=$(( (inner_width - subtitle_len) / 2 ))
    
    # Top border
    printf "${BOLD_CYAN}${BOX_TL}"
    for ((i=0; i<inner_width; i++)); do printf "${BOX_H}"; done
    printf "${BOX_TR}${NC}\n"
    
    # Title line (centered)
    printf "${BOLD_CYAN}${BOX_V}${NC}"
    printf "%*s" "$title_padding" ""
    printf "${BOLD_WHITE}%s${NC}" "$title"
    printf "%*s" "$((inner_width - title_padding - title_len))" ""
    printf "${BOLD_CYAN}${BOX_V}${NC}\n"
    
    # Subtitle line (centered)
    printf "${BOLD_CYAN}${BOX_V}${NC}"
    printf "%*s" "$subtitle_padding" ""
    printf "${COLOR_INFO}%s${NC}" "$subtitle"
    printf "%*s" "$((inner_width - subtitle_padding - subtitle_len))" ""
    printf "${BOLD_CYAN}${BOX_V}${NC}\n"
    
    # Separator line
    printf "${BOLD_CYAN}${BOX_LT}"
    for ((i=0; i<inner_width; i++)); do printf "${BOX_H}"; done
    printf "${BOX_RT}${NC}\n"
    
    # Timestamp and elapsed time line
    local time_info="Time: ${timestamp}  |  Elapsed: ${elapsed}"
    local time_len=${#time_info}
    local time_padding=$(( (inner_width - time_len) / 2 ))
    
    printf "${BOLD_CYAN}${BOX_V}${NC}"
    printf "%*s" "$time_padding" ""
    printf "${COLOR_MUTED}%s${NC}" "$time_info"
    printf "%*s" "$((inner_width - time_padding - time_len))" ""
    printf "${BOLD_CYAN}${BOX_V}${NC}\n"
    
    # Bottom border
    printf "${BOLD_CYAN}${BOX_BL}"
    for ((i=0; i<inner_width; i++)); do printf "${BOX_H}"; done
    printf "${BOX_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_load_section - Display ASCII load graph with current RPS
# Requirements: 1.1 (ASCII load graph), 1.4 (current RPS)
# Output: Renders load visualization section to stdout
# -----------------------------------------------------------------------------
render_load_section() {
    local current_rps="${METRIC_CURRENT_RPS:-0}"
    local load_color
    load_color=$(determine_status_color "load" "$current_rps")
    
    # Section header (78 inner + 2 borders = 80)
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} Load Graph ${NC}${BOLD_CYAN}"
    for ((i=0; i<65; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}\n"
    
    # Render the ASCII graph
    local graph_output
    graph_output=$(build_ascii_graph)
    
    # Display graph with left border (77 graph chars = 73 width + 4 Y-axis, padding 1 to reach 78)
    while IFS= read -r line; do
        printf "${BOLD_CYAN}${BOX_L_V}${NC}${COLOR_INFO}%s${NC}" "$line"
        printf " "
        printf "${BOLD_CYAN}${BOX_L_V}${NC}\n"
    done <<< "$graph_output"
    
    # RPS line (fit in 78 chars)
    printf "${BOLD_CYAN}${BOX_L_V}${NC} RPS: ${load_color}${BOLD}%-6s${NC}" "$current_rps"
    printf "%*s" "66" ""
    printf "${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Section footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<78; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_queue_section - Display vLLM scaling metrics (queue depth and running requests)
# Requirements: 2.1 (queue depth), 2.2 (KEDA target), 2.3, 2.4 (scaling zone)
# Output: Renders scaling metrics section to stdout
# -----------------------------------------------------------------------------
render_queue_section() {
    local queue_depth="${METRIC_QUEUE_DEPTH:-0}"
    local running_requests="${METRIC_RUNNING_REQUESTS:-0}"
    
    # Color based on value relative to KEDA target (proactive scaling visualization)
    # GREEN=below target, YELLOW=at/above target, RED=50%+ above target
    local queue_color
    queue_color=$(determine_target_color "$queue_depth" "$THRESHOLD_QUEUE_TARGET")
    
    # Running requests uses neutral color (informational only, not a scaling trigger)
    local running_color="$COLOR_INFO"
    
    # Add stale indicator if needed
    local stale_marker=""
    if [[ "$STALE_QUEUE_DEPTH" == "true" ]]; then
        stale_marker=" ${COLOR_WARNING}${INDICATOR_WARNING}${NC}"
    fi
    
    # Section header (78 inner + 2 borders = 80)
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} Scaling Metrics (vLLM # of requests) ${NC}${BOLD_CYAN}"
    for ((i=0; i<39; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}\n"
    
    # Scaling metrics display - aligned with bars below
    # Calculate padding based on stale marker presence (stale marker is 2 chars: space + ⚠)
    local stale_padding=0
    [[ "$STALE_QUEUE_DEPTH" == "true" ]] && stale_padding=2
    
    # "Waiting:" aligned with first bar, "Running:" aligned with second bar
    printf "${BOLD_CYAN}${BOX_L_V}${NC} Waiting: ${queue_color}${BOLD}%-4s${NC}${stale_marker}" "$queue_depth"
    printf " ${COLOR_MUTED}|${NC} Target: ${COLOR_INFO}%-2s${NC}" "$THRESHOLD_QUEUE_TARGET"
    printf "            Running: ${running_color}${BOLD}%-4s${NC}" "$running_requests"
    printf " ${COLOR_MUTED}|${NC} Target: ${COLOR_INFO}%-2s${NC}" "$THRESHOLD_RUNNING_TARGET"
    printf "%*s" "$((13 - stale_padding))" ""
    printf "${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Visual bars - two separate bars for Waiting and Running
    local bar_width_waiting=34
    local bar_width_running=36
    local waiting_filled=0
    local running_filled=0
    
    if [[ "$queue_depth" =~ ^[0-9]+$ ]] && [[ $queue_depth -gt 0 ]]; then
        waiting_filled=$(( (queue_depth * bar_width_waiting) / THRESHOLD_QUEUE_CRITICAL ))
        [[ $waiting_filled -gt $bar_width_waiting ]] && waiting_filled=$bar_width_waiting
    fi
    if [[ "$running_requests" =~ ^[0-9]+$ ]] && [[ $running_requests -gt 0 ]]; then
        running_filled=$(( (running_requests * bar_width_running) / THRESHOLD_QUEUE_CRITICAL ))
        [[ $running_filled -gt $bar_width_running ]] && running_filled=$bar_width_running
    fi
    
    printf "${BOLD_CYAN}${BOX_L_V}${NC} ["
    for ((i=0; i<waiting_filled; i++)); do printf "${queue_color}${BLOCK_FULL}${NC}"; done
    for ((i=waiting_filled; i<bar_width_waiting; i++)); do printf "${COLOR_MUTED}${BLOCK_LIGHT}${NC}"; done
    printf "]  ["
    for ((i=0; i<running_filled; i++)); do printf "${running_color}${BLOCK_FULL}${NC}"; done
    for ((i=running_filled; i<bar_width_running; i++)); do printf "${COLOR_MUTED}${BLOCK_LIGHT}${NC}"; done
    printf "] ${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Section footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<78; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_pods_section - Display vLLM pod scaling status
# Requirements: 3.1-3.6 (pod counts, scaling indicators, visual representation)
# Output: Renders pod status section to stdout
# Colors: Green=Ready (1/1), Yellow=NotReady (running but not 1/1), Yellow empty=Pending
# -----------------------------------------------------------------------------
render_pods_section() {
    local running="${METRIC_PODS_RUNNING:-0}"
    local desired="${METRIC_PODS_DESIRED:-0}"
    local ready="${METRIC_PODS_READY:-0}"
    local pending="${METRIC_PODS_PENDING:-0}"
    local not_ready="${METRIC_PODS_NOT_READY:-0}"
    local startup_min="${METRIC_POD_STARTUP_MIN:-N/A}"
    local startup_max="${METRIC_POD_STARTUP_MAX:-N/A}"
    
    # Ensure numeric values
    [[ ! "$running" =~ ^[0-9]+$ ]] && running=0
    [[ ! "$desired" =~ ^[0-9]+$ ]] && desired=0
    [[ ! "$ready" =~ ^[0-9]+$ ]] && ready=0
    [[ ! "$pending" =~ ^[0-9]+$ ]] && pending=0
    [[ ! "$not_ready" =~ ^[0-9]+$ ]] && not_ready=0
    
    # Determine scaling direction
    local scaling_status
    scaling_status=$(determine_scaling_status "pods" "$running" "$desired")
    
    local direction_icon="$INDICATOR_STABLE"
    local direction_color="$COLOR_GOOD"
    local direction_label="Stable"
    
    # Check if pods are not ready (ready=0 but have running or pending pods)
    # All labels are exactly 10 chars for consistent alignment
    if [[ $ready -eq 0 ]] && [[ $((running + pending)) -gt 0 ]]; then
        direction_icon="$INDICATOR_WARNING"
        direction_color="$COLOR_ERROR"
        direction_label="Not Ready "
    elif [[ "$scaling_status" == "scaling_up" ]]; then
        direction_icon="$INDICATOR_UP"
        direction_color="$COLOR_WARNING"
        direction_label="Scale Up  "
    elif [[ "$scaling_status" == "scaling_down" ]]; then
        direction_icon="$INDICATOR_DOWN"
        direction_color="$COLOR_INFO"
        direction_label="Scale Down"
    else
        direction_label="Stable    "
    fi
    
    # Add stale indicator if needed
    local stale_marker=""
    if [[ "$STALE_PODS" == "true" ]]; then
        stale_marker=" ${COLOR_WARNING}${INDICATOR_WARNING}${NC}"
    fi
    
    # Section header (78 inner + 2 borders = 80)
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} vLLM Pods ${NC}${BOLD_CYAN}"
    for ((i=0; i<66; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}\n"
    
    # Pod counts line - calculate exact widths
    # "│ Ready: XX | Desired: XX | X LabelLabelL                                    │"
    # Without pending: │(1) + space(1) + Ready: (7) + XX(2) + space|space(3) + Desired: (9) + XX(2) + space|space(3) + icon(1) + space(1) + label(10) + padding + │(1) = 80
    # = 1+1+7+2+3+9+2+3+1+1+10 = 40, padding = 78-40+1 = 39
    # With pending: add " | Pending: XX" = 14 more, padding = 39-14 = 25
    local stale_padding=0
    [[ "$STALE_PODS" == "true" ]] && stale_padding=2
    
    printf "${BOLD_CYAN}${BOX_L_V}${NC} Ready: ${COLOR_GOOD}${BOLD}%-2s${NC}${stale_marker}" "$ready"
    printf " ${COLOR_MUTED}|${NC} Desired: ${COLOR_INFO}%-2s${NC}" "$desired"
    if [[ $pending -gt 0 ]]; then
        printf " ${COLOR_MUTED}|${NC} Pending: ${COLOR_WARNING}%-2s${NC}" "$pending"
        printf " ${COLOR_MUTED}|${NC} ${direction_color}%s %s${NC}" "$direction_icon" "$direction_label"
        printf "%*s" "$((25 - stale_padding))" ""
    else
        printf " ${COLOR_MUTED}|${NC} ${direction_color}%s %s${NC}" "$direction_icon" "$direction_label"
        printf "%*s" "$((39 - stale_padding))" ""
    fi
    printf "${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Visual pod representation with startup time on same line
    local max_pods=15
    local display_ready=$ready
    local display_not_ready=$not_ready
    local display_pending=$pending
    
    # Cap display counts
    [[ $display_ready -gt $max_pods ]] && display_ready=$max_pods
    local remaining=$((max_pods - display_ready))
    [[ $display_not_ready -gt $remaining ]] && display_not_ready=$remaining
    remaining=$((remaining - display_not_ready))
    [[ $display_pending -gt $remaining ]] && display_pending=$remaining
    
    # Pods line: "│ ● ● ○ ○ ... | Startup: Min: XXXs Max: XXXs                      │"
    # │(1) + space(1) + 15pods*2(30) + space|space(3) + Startup:(8) + space(1) + Min:(4) + space(1) + XXXs(4) + space(1) + Max:(4) + space(1) + XXXs(4) + padding + │(1)
    # = 1+1+30+3+8+1+4+1+4+1+4+1+4 = 63, padding = 78-63+1 = 16
    printf "${BOLD_CYAN}${BOX_L_V}${NC} "
    # Ready pods (green, filled)
    for ((i=0; i<display_ready; i++)); do
        printf "${COLOR_GOOD}%s${NC} " "$POD_ICON"
    done
    # Not ready pods (yellow, filled) - running but not 1/1
    for ((i=0; i<display_not_ready; i++)); do
        printf "${COLOR_WARNING}%s${NC} " "$POD_ICON"
    done
    # Pending pods (yellow, empty) - not yet scheduled/running
    for ((i=0; i<display_pending; i++)); do
        printf "${COLOR_WARNING}%s${NC} " "$POD_EMPTY"
    done
    # Empty slots (gray)
    local used=$((display_ready + display_not_ready + display_pending))
    for ((i=used; i<max_pods; i++)); do
        printf "${COLOR_MUTED}%s${NC} " "$POD_EMPTY"
    done
    
    # Startup time with Min/Max labels
    local startup_min="${METRIC_POD_STARTUP_MIN:-N/A}"
    local startup_max="${METRIC_POD_STARTUP_MAX:-N/A}"
    
    printf "${COLOR_MUTED}|${NC} ${BOLD_WHITE}Startup:${NC} "
    if [[ "$startup_min" != "N/A" ]] && [[ "$startup_max" != "N/A" ]]; then
        # "Min: XXXs Max: XXXs" with fixed width values
        printf "${COLOR_MUTED}Min:${NC} ${COLOR_GOOD}%-3ss${NC} ${COLOR_MUTED}Max:${NC} ${COLOR_WARNING}%-3ss${NC}" "$startup_min" "$startup_max"
        # │(1) + space(1) + pods(30) + " | Startup: Min: XXXs Max: XXXs"(31) + padding + │(1) = 80
        # padding = 80 - 64 = 16, but visually needs 17
        printf "%*s" "17" ""
    else
        printf "${COLOR_MUTED}N/A${NC}"
        # Same adjustment as values case - needs 33 padding
        printf "%*s" "33" ""
    fi
    printf "${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Section footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<78; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_nodes_section - Display GPU node scaling status
# Requirements: 4.1-4.3 (node count, visual representation)
# Output: Renders node status section to stdout
# Colors: Green=Ready, Yellow=Pending/NodeClaim, Red=NotReady
# -----------------------------------------------------------------------------
render_nodes_section() {
    local ready_count="${METRIC_NODES_READY:-0}"
    local pending_count="${METRIC_NODES_PENDING:-0}"
    local nodeclaims="${METRIC_NODECLAIMS_PENDING:-0}"
    local total_count="${METRIC_NODES_COUNT:-0}"
    local ondemand_count="${METRIC_NODES_ONDEMAND:-0}"
    local spot_count="${METRIC_NODES_SPOT:-0}"
    
    # Ensure numeric values
    [[ ! "$ready_count" =~ ^[0-9]+$ ]] && ready_count=0
    [[ ! "$pending_count" =~ ^[0-9]+$ ]] && pending_count=0
    [[ ! "$nodeclaims" =~ ^[0-9]+$ ]] && nodeclaims=0
    [[ ! "$total_count" =~ ^[0-9]+$ ]] && total_count=0
    [[ ! "$ondemand_count" =~ ^[0-9]+$ ]] && ondemand_count=0
    [[ ! "$spot_count" =~ ^[0-9]+$ ]] && spot_count=0
    
    # Determine status text and color
    local status_text=""
    local status_color="$COLOR_GOOD"
    
    if [[ $total_count -eq 0 ]] && [[ $nodeclaims -eq 0 ]]; then
        status_color="$COLOR_WARNING"
        status_text="(waiting for Karpenter)"
    elif [[ $nodeclaims -gt 0 ]]; then
        status_color="$COLOR_WARNING"
        status_text="(+${nodeclaims} provisioning)"
    elif [[ $pending_count -gt 0 ]]; then
        status_color="$COLOR_WARNING"
        status_text="(${pending_count} not ready)"
    fi
    
    # Add stale indicator if needed
    local stale_marker=""
    if [[ "$STALE_NODES" == "true" ]]; then
        stale_marker=" ${COLOR_WARNING}${INDICATOR_WARNING}${NC}"
    fi
    
    # Section header (78 inner + 2 borders = 80)
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} GPU Nodes ${NC}${BOLD_CYAN}"
    for ((i=0; i<66; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}\n"
    
    # Node info line (fit in 78 chars)
    local stale_padding=0
    [[ "$STALE_NODES" == "true" ]] && stale_padding=2
    
    # Show ready/total count
    local count_display="${ready_count}/${total_count}"
    if [[ $nodeclaims -gt 0 ]]; then
        count_display="${ready_count}/$((total_count + nodeclaims))"
    fi
    
    # Build capacity type display (On-Demand:X Spot:Y)
    local capacity_display=""
    if [[ $ready_count -gt 0 ]]; then
        capacity_display="On-Demand:${ondemand_count} Spot:${spot_count}"
    fi
    
    printf "${BOLD_CYAN}${BOX_L_V}${NC} Ready: ${status_color}${BOLD}%-5s${NC}${stale_marker}" "$count_display"
    if [[ -n "$capacity_display" ]]; then
        printf " ${COLOR_MUTED}|${NC} ${COLOR_INFO}%s${NC}" "$capacity_display"
        local cap_len=${#capacity_display}
        if [[ -n "$status_text" ]]; then
            printf " ${COLOR_WARNING}%s${NC}" "$status_text"
            local text_len=${#status_text}
            printf "%*s" "$((61 - cap_len - text_len - stale_padding))" ""
        else
            printf "%*s" "$((62 - cap_len - stale_padding))" ""
        fi
    elif [[ -n "$status_text" ]]; then
        printf " ${COLOR_WARNING}%s${NC}" "$status_text"
        local text_len=${#status_text}
        printf "%*s" "$((64 - text_len - stale_padding))" ""
    else
        printf "%*s" "$((65 - stale_padding))" ""
    fi
    printf "${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Visual node representation with colors
    local max_display=15
    local display_ready=$ready_count
    local display_pending=$pending_count
    local display_claims=$nodeclaims
    
    # Cap display counts
    [[ $display_ready -gt $max_display ]] && display_ready=$max_display
    local remaining=$((max_display - display_ready))
    [[ $display_pending -gt $remaining ]] && display_pending=$remaining
    remaining=$((remaining - display_pending))
    [[ $display_claims -gt $remaining ]] && display_claims=$remaining
    
    printf "${BOLD_CYAN}${BOX_L_V}${NC} "
    # Ready nodes (green)
    for ((i=0; i<display_ready; i++)); do
        printf "${COLOR_GOOD}%s${NC} " "$NODE_ICON"
    done
    # Pending/NotReady nodes (yellow)
    for ((i=0; i<display_pending; i++)); do
        printf "${COLOR_WARNING}%s${NC} " "$NODE_ICON"
    done
    # NodeClaims being provisioned (yellow, empty icon)
    for ((i=0; i<display_claims; i++)); do
        printf "${COLOR_WARNING}%s${NC} " "$NODE_EMPTY"
    done
    # Empty slots (gray)
    local used=$((display_ready + display_pending + display_claims))
    for ((i=used; i<max_display; i++)); do
        printf "${COLOR_MUTED}%s${NC} " "$NODE_EMPTY"
    done
    printf "%*s" "$((78 - max_display*2 - 1))" ""
    printf "${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Section footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<78; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_performance_section - Display throughput and response time metrics
# Requirements: 5.1-5.5 (throughput, response times, color coding, N/A handling)
# Output: Renders performance metrics section to stdout
# -----------------------------------------------------------------------------
render_performance_section() {
    local throughput="${METRIC_THROUGHPUT:-N/A}"
    local tokens_per_sec="${METRIC_TOKENS_PER_SEC:-N/A}"
    local ttft_p50="${METRIC_TTFT_P50:-N/A}"
    local ttft_p95="${METRIC_TTFT_P95:-N/A}"
    local itl_p50="${METRIC_ITL_P50:-N/A}"
    local itl_p95="${METRIC_ITL_P95:-N/A}"
    
    # Get colors for each metric
    local throughput_color
    throughput_color=$(determine_status_color "throughput" "$throughput")
    
    local ttft_color
    ttft_color=$(determine_status_color "response" "$ttft_p50")
    
    local itl_color
    itl_color=$(determine_status_color "response" "$itl_p50")
    
    # Add stale indicator if needed
    local stale_marker=""
    if [[ "$STALE_PERFORMANCE" == "true" ]]; then
        stale_marker=" ${COLOR_WARNING}${INDICATOR_WARNING}${NC}"
    fi
    
    # Format values with units
    local throughput_display="$throughput"
    local tokens_display="$tokens_per_sec"
    
    # Helper to format latency
    format_latency() {
        local val="$1"
        if [[ "$val" == "N/A" || -z "$val" ]]; then
            echo "N/A"
        elif [[ "$val" -ge 10000 ]] 2>/dev/null; then
            echo "$((val / 1000))s"
        elif [[ "$val" -ge 1000 ]] 2>/dev/null; then
            local secs=$((val / 1000))
            local tenths=$(( (val % 1000) / 100 ))
            echo "${secs}.${tenths}s"
        else
            echo "${val}ms"
        fi
    }
    
    local ttft_p50_display=$(format_latency "$ttft_p50")
    local ttft_p95_display=$(format_latency "$ttft_p95")
    local itl_p50_display=$(format_latency "$itl_p50")
    local itl_p95_display=$(format_latency "$itl_p95")
    
    # Section header (78 inner + 2 borders = 80)
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} Performance ${NC}${BOLD_CYAN}"
    for ((i=0; i<64; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}\n"
    
    # Performance metrics - two lines
    local stale_padding=0
    [[ "$STALE_PERFORMANCE" == "true" ]] && stale_padding=2
    
    # KV Cache display
    local kv_cache_display="${METRIC_KV_CACHE_PCT:-N/A}"
    [[ "$kv_cache_display" != "N/A" ]] && kv_cache_display="${kv_cache_display}%"
    
    # E2E displays
    local e2e_avg_display="${METRIC_E2E_AVG:-N/A}"
    [[ "$e2e_avg_display" != "N/A" ]] && e2e_avg_display="${e2e_avg_display}ms"
    local e2e_p50_display="${METRIC_E2E_P50:-N/A}"
    [[ "$e2e_p50_display" != "N/A" ]] && e2e_p50_display="${e2e_p50_display}ms"
    local e2e_p95_display="${METRIC_E2E_P95:-N/A}"
    [[ "$e2e_p95_display" != "N/A" ]] && e2e_p95_display="${e2e_p95_display}ms"
    
    # Line 1: "│ RPS: 20  | Tok/s: 1500 | E2E p50: 0ms   | p95: 0ms   | KV: 5%       │"
    printf "${BOLD_CYAN}${BOX_L_V}${NC} RPS: ${throughput_color}${BOLD}%-4s${NC}${stale_marker}" "$throughput_display"
    printf " ${COLOR_MUTED}|${NC} Tok/s: ${COLOR_INFO}%-4s${NC}" "$tokens_display"
    printf " ${COLOR_MUTED}|${NC} E2E p50: ${COLOR_INFO}%-6s${NC}" "$e2e_p50_display"
    printf " ${COLOR_MUTED}|${NC} p95: ${COLOR_INFO}%-6s${NC}" "$e2e_p95_display"
    printf " ${COLOR_MUTED}|${NC} KV: ${COLOR_INFO}%-3s${NC}" "$kv_cache_display"
    printf "%*s${BOLD_CYAN}${BOX_L_V}${NC}\n" "$((12 - stale_padding))" ""
    
    # Line 2: "│ TTFT p50: 25ms  | p95: 50ms  | ITL(TPOT) p50: 25ms  | p95: 30ms    │"
    printf "${BOLD_CYAN}${BOX_L_V}${NC} TTFT p50: ${ttft_color}%-5s${NC}" "$ttft_p50_display"
    printf " ${COLOR_MUTED}|${NC} p95: ${ttft_color}%-5s${NC}" "$ttft_p95_display"
    printf " ${COLOR_MUTED}|${NC} ITL(TPOT) p50: ${itl_color}%-5s${NC}" "$itl_p50_display"
    printf " ${COLOR_MUTED}|${NC} p95: ${itl_color}%-5s${NC}" "$itl_p95_display"
    printf "%*s${BOLD_CYAN}${BOX_L_V}${NC}\n" "13" ""
    
    # Section footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<78; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_pod_timing_panel - Display vLLM pod timing information
# Output: Renders pod timing table to stdout
# -----------------------------------------------------------------------------
render_pod_timing_panel() {
    local pod_data="${POD_TIMING_DATA:-}"
    
    # Panel width: 60 chars (58 inner + 2 borders)
    local panel_width=58
    
    # Section header
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} vLLM Pods ${NC}${BOLD_CYAN}"
    for ((i=0; i<46; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}\n"
    
    # Table header
    printf "${BOLD_CYAN}${BOX_L_V}${NC} ${BOLD}%-18s %-8s %-8s %-8s %-6s${NC}" "Pod" "Status" "Start" "Ready" "Time"
    printf " ${BOLD_CYAN}${BOX_L_V}${NC}\n"
    
    # Separator
    printf "${BOLD_CYAN}${BOX_L_V}"
    for ((i=0; i<panel_width; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_V}${NC}\n"
    
    if [[ -z "$pod_data" ]]; then
        printf "${BOLD_CYAN}${BOX_L_V}${NC} ${COLOR_MUTED}No pods found${NC}"
        printf "%*s${BOLD_CYAN}${BOX_L_V}${NC}\n" "$((panel_width - 14))" ""
    else
        while IFS='|' read -r name phase ready_status start_time ready_time; do
            [[ -z "$name" ]] && continue
            
            # Shorten pod name (keep last 16 chars)
            local short_name="${name: -16}"
            
            # Format status
            local status_display="$ready_status"
            local status_color="$COLOR_INFO"
            [[ "$ready_status" == "Ready" ]] && status_color="$COLOR_GOOD"
            [[ "$ready_status" == "NotReady" ]] && status_color="$COLOR_WARNING"
            [[ "$phase" == "Failed" ]] && status_color="$COLOR_ERROR" && status_display="Failed"
            [[ "$phase" == "Pending" ]] && status_color="$COLOR_WARNING" && status_display="Pending"
            
            # Format times (HH:MM:SS)
            local start_display="N/A"
            if [[ -n "$start_time" ]]; then
                start_display=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" "+%H:%M:%S" 2>/dev/null || echo "N/A")
            fi
            
            local ready_display="N/A"
            local time_display="N/A"
            if [[ -n "$ready_time" ]] && [[ "$ready_status" == "Ready" ]]; then
                ready_display=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ready_time" "+%H:%M:%S" 2>/dev/null || echo "N/A")
                
                # Calculate time to ready in seconds
                if [[ "$start_display" != "N/A" ]] && [[ "$ready_display" != "N/A" ]]; then
                    local start_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" "+%s" 2>/dev/null)
                    local ready_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ready_time" "+%s" 2>/dev/null)
                    if [[ -n "$start_epoch" ]] && [[ -n "$ready_epoch" ]]; then
                        time_display=$((ready_epoch - start_epoch))
                        time_display="${time_display}s"
                    fi
                fi
            fi
            
            # Print row
            printf "${BOLD_CYAN}${BOX_L_V}${NC} %-18s ${status_color}%-8s${NC} %-8s %-8s %-6s" \
                "$short_name" "$status_display" "$start_display" "$ready_display" "$time_display"
            printf " ${BOLD_CYAN}${BOX_L_V}${NC}\n"
        done <<< "$pod_data"
    fi
    
    # Section footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<panel_width; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_insights_section - Display key insights based on current metrics
# Requirements: 7.1 (organized layout), 7.4 (consistent color coding)
# Output: Renders key insights section to stdout
# -----------------------------------------------------------------------------
render_insights_section() {
    local insights=()
    local insight_colors=()
    
    # Check k6 job status first - prioritize showing test results
    check_k6_job_status
    
    # If k6 job completed, show results as top priority (use all 3 insight lines)
    if [[ "$K6_JOB_STATUS" == "completed" ]] && [[ -n "$K6_TOTAL_REQUESTS" ]]; then
        # Truncate RPS to 1 decimal place if it has more
        local rps_short="${K6_RPS}"
        if [[ "$rps_short" =~ ^([0-9]+\.[0-9]) ]]; then
            rps_short="${BASH_REMATCH[1]}"
        fi
        
        # Line 1: Throughput - "Load Test: 28398 reqs @ 32.6 RPS, 0.00% failed"
        local line1="Load Test: ${K6_TOTAL_REQUESTS} reqs @ ${rps_short} RPS"
        [[ -n "$K6_FAILURE_RATE" ]] && line1+=", ${K6_FAILURE_RATE} failed"
        insights+=("$line1")
        insight_colors+=("$COLOR_GOOD")
        
        # Line 2: Latency range - "  Latency: avg=735ms, min=355ms, max=1.18s"
        local line2="  Latency: avg=${K6_AVG_DURATION}, min=${K6_MIN_DURATION}, max=${K6_MAX_DURATION}"
        insights+=("$line2")
        insight_colors+=("$COLOR_INFO")
        
        # Line 3: Percentiles - "  Percentiles: med=673ms, p90=1s, p95=1.04s"
        local line3="  Percentiles: med=${K6_MED_DURATION}, p90=${K6_P90_DURATION}, p95=${K6_P95_DURATION}"
        insights+=("$line3")
        insight_colors+=("$COLOR_INFO")
    elif [[ "$K6_JOB_STATUS" == "running" ]]; then
        # During load test, show scaling activity insights
        
        # Check for Karpenter provisioning new nodes
        if [[ "$METRIC_NODECLAIMS_PENDING" =~ ^[0-9]+$ ]] && [[ $METRIC_NODECLAIMS_PENDING -gt 0 ]]; then
            insights+=("Karpenter: Provisioning $METRIC_NODECLAIMS_PENDING GPU node(s)")
            insight_colors+=("$COLOR_WARNING")
        fi
        
        # Check for KEDA/HPA scaling decisions
        if [[ "$METRIC_PODS_DESIRED" =~ ^[0-9]+$ ]] && [[ "$METRIC_PODS_RUNNING" =~ ^[0-9]+$ ]]; then
            if [[ $METRIC_PODS_DESIRED -gt $METRIC_PODS_RUNNING ]]; then
                local pending=$((METRIC_PODS_DESIRED - METRIC_PODS_RUNNING))
                # Show KEDA scaling with queue context
                if [[ "$METRIC_QUEUE_DEPTH" =~ ^[0-9]+$ ]] && [[ $METRIC_QUEUE_DEPTH -gt 0 ]]; then
                    insights+=("KEDA: Scaling ${METRIC_PODS_RUNNING}->${METRIC_PODS_DESIRED} pods (queue: $METRIC_QUEUE_DEPTH)")
                else
                    insights+=("KEDA: Scaling up to $METRIC_PODS_DESIRED pods")
                fi
                insight_colors+=("$COLOR_WARNING")
            fi
        fi
        
        # Check for pods starting up (not ready yet)
        if [[ "$METRIC_PODS_NOT_READY" =~ ^[0-9]+$ ]] && [[ $METRIC_PODS_NOT_READY -gt 0 ]]; then
            insights+=("vLLM: $METRIC_PODS_NOT_READY pod(s) loading model (~2 min)")
            insight_colors+=("$COLOR_INFO")
        fi
        
        # Show queue pressure if high
        if [[ "$METRIC_QUEUE_DEPTH" =~ ^[0-9]+$ ]]; then
            if [[ $METRIC_QUEUE_DEPTH -ge $THRESHOLD_QUEUE_CRITICAL ]]; then
                insights+=("Queue: $METRIC_QUEUE_DEPTH waiting (critical - scaling)")
                insight_colors+=("$COLOR_ERROR")
            elif [[ $METRIC_QUEUE_DEPTH -ge $THRESHOLD_QUEUE_HIGH ]]; then
                insights+=("Queue: $METRIC_QUEUE_DEPTH waiting (high - scaling triggered)")
                insight_colors+=("$COLOR_WARNING")
            fi
        fi
        
        # If no scaling activity, show stable status
        if [[ ${#insights[@]} -eq 0 ]]; then
            insights+=("Load test running - monitoring scaling...")
            insight_colors+=("$COLOR_INFO")
        fi
    elif [[ "$K6_JOB_STATUS" == "failed" ]] && [[ -z "$K6_TOTAL_REQUESTS" ]]; then
        insights+=("Load test failed - check k6 logs")
        insight_colors+=("$COLOR_ERROR")
    fi
    
    # Analyze queue depth (when not in load test)
    if [[ "$K6_JOB_STATUS" != "running" ]] && [[ "$K6_JOB_STATUS" != "completed" ]]; then
        if [[ "$METRIC_QUEUE_DEPTH" =~ ^[0-9]+$ ]]; then
            if [[ $METRIC_QUEUE_DEPTH -ge $THRESHOLD_QUEUE_CRITICAL ]]; then
                insights+=("Queue critical - heavy scaling pressure")
                insight_colors+=("$COLOR_ERROR")
            elif [[ $METRIC_QUEUE_DEPTH -ge $THRESHOLD_QUEUE_HIGH ]]; then
                insights+=("Queue high - scaling in progress")
                insight_colors+=("$COLOR_WARNING")
            elif [[ $METRIC_QUEUE_DEPTH -eq 0 ]]; then
                insights+=("Queue empty - system idle")
                insight_colors+=("$COLOR_INFO")
            fi
        fi
        
        # Analyze pod scaling
        if [[ "$METRIC_PODS_RUNNING" =~ ^[0-9]+$ ]] && [[ "$METRIC_PODS_DESIRED" =~ ^[0-9]+$ ]]; then
            if [[ $METRIC_PODS_DESIRED -gt $METRIC_PODS_RUNNING ]]; then
                local pending=$((METRIC_PODS_DESIRED - METRIC_PODS_RUNNING))
                insights+=("Scaling up: $pending pod(s) pending")
                insight_colors+=("$COLOR_WARNING")
            elif [[ $METRIC_PODS_DESIRED -lt $METRIC_PODS_RUNNING ]]; then
                insights+=("Scaling down in progress")
                insight_colors+=("$COLOR_INFO")
            elif [[ $METRIC_PODS_RUNNING -gt 0 ]]; then
                insights+=("Pods stable at $METRIC_PODS_RUNNING replica(s)")
                insight_colors+=("$COLOR_GOOD")
            fi
        fi
        
        # Analyze node status
        if [[ "$METRIC_NODES_COUNT" =~ ^[0-9]+$ ]]; then
            if [[ $METRIC_NODES_COUNT -eq 0 ]]; then
                insights+=("No GPU nodes - Karpenter may provision")
                insight_colors+=("$COLOR_WARNING")
            elif [[ $METRIC_NODES_COUNT -ge 3 ]]; then
                insights+=("$METRIC_NODES_COUNT GPU nodes active")
                insight_colors+=("$COLOR_GOOD")
            fi
        fi
    fi
    
    # If no insights, show a default message
    if [[ ${#insights[@]} -eq 0 ]]; then
        insights+=("Monitoring autoscaling demo...")
        insight_colors+=("$COLOR_INFO")
    fi
    
    # Section header (78 inner + 2 borders = 80)
    printf "${BOLD_CYAN}${BOX_L_TL}${BOX_L_H}${NC}${BOLD_WHITE} Key Insights ${NC}${BOLD_CYAN}"
    for ((i=0; i<63; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_TR}${NC}\n"
    
    # Display up to 3 insights (fit in 78 chars each)
    local max_insights=3
    local displayed=0
    for i in "${!insights[@]}"; do
        if [[ $displayed -ge $max_insights ]]; then
            break
        fi
        
        local insight="${insights[$i]}"
        local color="${insight_colors[$i]}"
        
        # Truncate insight if too long (max 73 chars to fit with bullet and padding)
        if [[ ${#insight} -gt 73 ]]; then
            insight="${insight:0:70}..."
        fi
        
        printf "${BOLD_CYAN}${BOX_L_V}${NC} ${color}${INDICATOR_CHECK}${NC} %-75s${BOLD_CYAN}${BOX_L_V}${NC}\n" "$insight"
        displayed=$((displayed + 1))
    done
    
    # Pad with empty lines if fewer than max_insights
    while [[ $displayed -lt $max_insights ]]; do
        printf "${BOLD_CYAN}${BOX_L_V}${NC}%-78s${BOLD_CYAN}${BOX_L_V}${NC}\n" ""
        displayed=$((displayed + 1))
    done
    
    # Section footer
    printf "${BOLD_CYAN}${BOX_L_BL}"
    for ((i=0; i<78; i++)); do printf "${BOX_L_H}"; done
    printf "${BOX_L_BR}${NC}\n"
}

# -----------------------------------------------------------------------------
# render_footer - Display footer with controls and status
# Requirements: 7.1 (organized layout)
# Output: Renders footer section to stdout
# -----------------------------------------------------------------------------
render_footer() {
    # Render insights section first
    render_insights_section
    
    # Footer line - just a blank line for spacing
    printf "\n"
}

# =============================================================================
# MAIN DASHBOARD LOOP FUNCTIONS
# =============================================================================
# These functions implement the main dashboard loop including metric collection,
# rendering, and signal handling.
# =============================================================================

# -----------------------------------------------------------------------------
# collect_all_metrics - Collect all metrics from Kubernetes cluster
# Requirements: 6.5 (last known values), 8.3 (continue on failure)
# Side effects:
#   - Updates all METRIC_* variables with current values
#   - Updates LAST_GOOD_* variables on successful collection
#   - Sets STALE_* flags when collection fails
#   - Adds current RPS to load history
# Returns: Always returns 0 (success) - failures are handled gracefully
# Note: Uses parallel collection to minimize refresh time (unless DISABLE_PARALLEL=true for testing)
# -----------------------------------------------------------------------------
collect_all_metrics() {
    local pod_info
    local queue_depth
    local node_info
    local perf_metrics
    
    # Check if parallel collection is disabled (for testing)
    if [[ "${DISABLE_PARALLEL:-false}" == "true" ]]; then
        # Sequential collection (for testing with mocked functions)
        pod_info=$(get_vllm_pods 2>/dev/null) || pod_info="N/A|N/A|N/A|N/A|N/A"
        queue_depth=$(get_queue_depth 2>/dev/null) || queue_depth="N/A"
        node_info=$(get_node_info 2>/dev/null) || node_info="0|0|0"
        perf_metrics=$(get_performance_metrics 2>/dev/null) || perf_metrics="N/A|N/A|N/A|N/A|N/A|N/A|N/A|0|N/A|N/A"
    else
        # Create temp files for parallel collection results
        local tmp_pods=$(mktemp)
        local tmp_queue=$(mktemp)
        local tmp_nodes=$(mktemp)
        local tmp_perf=$(mktemp)
        
        # Collect all metrics in parallel using background processes
        # This reduces total collection time from ~8-10s to ~2-3s
        (get_vllm_pods 2>/dev/null || echo "N/A|N/A|N/A|N/A|N/A") > "$tmp_pods" &
        local pid_pods=$!
        
        (get_queue_depth 2>/dev/null || echo "N/A") > "$tmp_queue" &
        local pid_queue=$!
        
        (get_node_info 2>/dev/null || echo "0|0|0") > "$tmp_nodes" &
        local pid_nodes=$!
        
        (get_performance_metrics 2>/dev/null || echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A|0|N/A|N/A") > "$tmp_perf" &
        local pid_perf=$!
        
        # Wait for all background processes to complete
        wait $pid_pods $pid_queue $pid_nodes $pid_perf 2>/dev/null
        
        # Read results from temp files
        pod_info=$(cat "$tmp_pods")
        queue_depth=$(cat "$tmp_queue")
        node_info=$(cat "$tmp_nodes")
        perf_metrics=$(cat "$tmp_perf")
        
        # Clean up temp files
        rm -f "$tmp_pods" "$tmp_queue" "$tmp_nodes" "$tmp_perf"
    fi
    
    # Process pod info (format: running|desired|ready|pending|not_ready|startup_min|startup_max)
    if [[ -n "$pod_info" ]] && [[ "$pod_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\| ]]; then
        METRIC_PODS_RUNNING=$(echo "$pod_info" | cut -d'|' -f1)
        METRIC_PODS_DESIRED=$(echo "$pod_info" | cut -d'|' -f2)
        METRIC_PODS_READY=$(echo "$pod_info" | cut -d'|' -f3)
        METRIC_PODS_PENDING=$(echo "$pod_info" | cut -d'|' -f4)
        METRIC_PODS_NOT_READY=$(echo "$pod_info" | cut -d'|' -f5)
        METRIC_POD_STARTUP_MIN=$(echo "$pod_info" | cut -d'|' -f6)
        METRIC_POD_STARTUP_MAX=$(echo "$pod_info" | cut -d'|' -f7)
        
        # Update last known good values
        LAST_GOOD_PODS_RUNNING="$METRIC_PODS_RUNNING"
        LAST_GOOD_PODS_DESIRED="$METRIC_PODS_DESIRED"
        LAST_GOOD_PODS_READY="$METRIC_PODS_READY"
        STALE_PODS=false
    elif [[ -n "$pod_info" ]] && [[ "$pod_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
        # Fallback for old 5-field format
        METRIC_PODS_RUNNING=$(echo "$pod_info" | cut -d'|' -f1)
        METRIC_PODS_DESIRED=$(echo "$pod_info" | cut -d'|' -f2)
        METRIC_PODS_READY=$(echo "$pod_info" | cut -d'|' -f3)
        METRIC_PODS_PENDING=$(echo "$pod_info" | cut -d'|' -f4)
        METRIC_PODS_NOT_READY=$(echo "$pod_info" | cut -d'|' -f5)
        METRIC_POD_STARTUP_MIN="N/A"
        METRIC_POD_STARTUP_MAX="N/A"
        LAST_GOOD_PODS_RUNNING="$METRIC_PODS_RUNNING"
        LAST_GOOD_PODS_DESIRED="$METRIC_PODS_DESIRED"
        LAST_GOOD_PODS_READY="$METRIC_PODS_READY"
        STALE_PODS=false
    elif [[ -n "$pod_info" ]] && [[ "$pod_info" != "N/A|N/A|N/A" ]] && [[ "$pod_info" != "N/A|N/A|N/A|N/A|N/A" ]] && [[ "$pod_info" != "N/A|N/A|N/A|N/A|N/A|N/A|N/A" ]]; then
        # Fallback for old 3-field format
        METRIC_PODS_RUNNING=$(echo "$pod_info" | cut -d'|' -f1)
        METRIC_PODS_DESIRED=$(echo "$pod_info" | cut -d'|' -f2)
        METRIC_PODS_READY=$(echo "$pod_info" | cut -d'|' -f3)
        METRIC_PODS_PENDING=0
        METRIC_PODS_NOT_READY=0
        METRIC_POD_STARTUP_MIN="N/A"
        METRIC_POD_STARTUP_MAX="N/A"
        LAST_GOOD_PODS_RUNNING="$METRIC_PODS_RUNNING"
        LAST_GOOD_PODS_DESIRED="$METRIC_PODS_DESIRED"
        LAST_GOOD_PODS_READY="$METRIC_PODS_READY"
        STALE_PODS=false
    else
        # Use last known good values and mark as stale
        METRIC_PODS_RUNNING="${LAST_GOOD_PODS_RUNNING:-N/A}"
        METRIC_PODS_DESIRED="${LAST_GOOD_PODS_DESIRED:-N/A}"
        METRIC_PODS_READY="${LAST_GOOD_PODS_READY:-N/A}"
        STALE_PODS=true
        log_error "Failed to collect pod metrics, using last known values"
    fi
    
    # Process queue depth (format: queue_depth|running_requests)
    if [[ -n "$queue_depth" ]] && [[ "$queue_depth" =~ ^[0-9]+\|[0-9]+$ ]]; then
        METRIC_QUEUE_DEPTH=$(echo "$queue_depth" | cut -d'|' -f1)
        METRIC_RUNNING_REQUESTS=$(echo "$queue_depth" | cut -d'|' -f2)
        LAST_GOOD_QUEUE_DEPTH="$METRIC_QUEUE_DEPTH"
        STALE_QUEUE_DEPTH=false
    elif [[ -n "$queue_depth" ]] && [[ "$queue_depth" =~ ^[0-9]+$ ]]; then
        # Fallback for old format (just queue depth)
        METRIC_QUEUE_DEPTH="$queue_depth"
        METRIC_RUNNING_REQUESTS=0
        LAST_GOOD_QUEUE_DEPTH="$queue_depth"
        STALE_QUEUE_DEPTH=false
    else
        # Use last known good value and mark as stale
        METRIC_QUEUE_DEPTH="${LAST_GOOD_QUEUE_DEPTH:-N/A}"
        METRIC_RUNNING_REQUESTS=0
        STALE_QUEUE_DEPTH=true
        log_error "Failed to collect queue depth, using last known value"
    fi
    
    # Process node info (format: ready|pending|nodeclaims|ondemand|spot)
    if [[ -n "$node_info" ]] && [[ "$node_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
        METRIC_NODES_READY=$(echo "$node_info" | cut -d'|' -f1)
        METRIC_NODES_PENDING=$(echo "$node_info" | cut -d'|' -f2)
        METRIC_NODECLAIMS_PENDING=$(echo "$node_info" | cut -d'|' -f3)
        METRIC_NODES_ONDEMAND=$(echo "$node_info" | cut -d'|' -f4)
        METRIC_NODES_SPOT=$(echo "$node_info" | cut -d'|' -f5)
        METRIC_NODES_COUNT=$((METRIC_NODES_READY + METRIC_NODES_PENDING))
        LAST_GOOD_NODES_COUNT="$METRIC_NODES_COUNT"
        STALE_NODES=false
    elif [[ -n "$node_info" ]] && [[ "$node_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
        # Fallback for old format (ready|pending|nodeclaims)
        METRIC_NODES_READY=$(echo "$node_info" | cut -d'|' -f1)
        METRIC_NODES_PENDING=$(echo "$node_info" | cut -d'|' -f2)
        METRIC_NODECLAIMS_PENDING=$(echo "$node_info" | cut -d'|' -f3)
        METRIC_NODES_ONDEMAND=0
        METRIC_NODES_SPOT=0
        METRIC_NODES_COUNT=$((METRIC_NODES_READY + METRIC_NODES_PENDING))
        LAST_GOOD_NODES_COUNT="$METRIC_NODES_COUNT"
        STALE_NODES=false
    elif [[ -n "$node_info" ]] && [[ "$node_info" =~ ^[0-9]+$ ]]; then
        # Fallback for old format (just count)
        METRIC_NODES_COUNT="$node_info"
        METRIC_NODES_READY="$node_info"
        METRIC_NODES_PENDING=0
        METRIC_NODECLAIMS_PENDING=0
        METRIC_NODES_ONDEMAND=0
        METRIC_NODES_SPOT=0
        LAST_GOOD_NODES_COUNT="$METRIC_NODES_COUNT"
        STALE_NODES=false
    else
        # Use last known good value and mark as stale
        METRIC_NODES_COUNT="${LAST_GOOD_NODES_COUNT:-0}"
        STALE_NODES=true
        log_error "Failed to collect node info, using last known value"
    fi
    
    # Process performance metrics
    # Format: throughput|ttft_p50|ttft_p95|itl_p50|itl_p95|e2e_avg|e2e_p50|e2e_p95|tokens_per_req|request_count|tokens_per_sec|kv_cache_pct
    if [[ -n "$perf_metrics" ]] && [[ "$perf_metrics" != "N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A|0|N/A|N/A" ]]; then
        METRIC_THROUGHPUT=$(echo "$perf_metrics" | cut -d'|' -f1)
        METRIC_TTFT_P50=$(echo "$perf_metrics" | cut -d'|' -f2)
        METRIC_TTFT_P95=$(echo "$perf_metrics" | cut -d'|' -f3)
        METRIC_ITL_P50=$(echo "$perf_metrics" | cut -d'|' -f4)
        METRIC_ITL_P95=$(echo "$perf_metrics" | cut -d'|' -f5)
        METRIC_E2E_AVG=$(echo "$perf_metrics" | cut -d'|' -f6)
        METRIC_E2E_P50=$(echo "$perf_metrics" | cut -d'|' -f7)
        METRIC_E2E_P95=$(echo "$perf_metrics" | cut -d'|' -f8)
        METRIC_TOKENS_PER_REQ=$(echo "$perf_metrics" | cut -d'|' -f9)
        local request_count=$(echo "$perf_metrics" | cut -d'|' -f10)
        METRIC_TOKENS_PER_SEC=$(echo "$perf_metrics" | cut -d'|' -f11)
        METRIC_KV_CACHE_PCT=$(echo "$perf_metrics" | cut -d'|' -f12)
        
        # Update last known good values
        [[ "$METRIC_THROUGHPUT" != "N/A" ]] && LAST_GOOD_THROUGHPUT="$METRIC_THROUGHPUT"
        [[ "$METRIC_TOKENS_PER_SEC" != "N/A" ]] && LAST_GOOD_TOKENS_PER_SEC="$METRIC_TOKENS_PER_SEC"
        
        # Update session-persistent values (only when we have valid non-zero data)
        # These persist even after load test ends so final results screen shows data
        if [[ "$METRIC_THROUGHPUT" =~ ^[0-9]+$ ]] && [[ "$METRIC_THROUGHPUT" -gt 0 ]]; then
            SESSION_RPS="$METRIC_THROUGHPUT"
        fi
        if [[ "$METRIC_TOKENS_PER_SEC" =~ ^[0-9]+$ ]] && [[ "$METRIC_TOKENS_PER_SEC" -gt 0 ]]; then
            SESSION_TOKENS_SEC="$METRIC_TOKENS_PER_SEC"
        fi
        if [[ "$METRIC_TTFT_P50" =~ ^[0-9]+$ ]] && [[ "$METRIC_TTFT_P50" -gt 0 ]]; then
            SESSION_TTFT_P50="$METRIC_TTFT_P50"
        fi
        if [[ "$METRIC_TTFT_P95" =~ ^[0-9]+$ ]] && [[ "$METRIC_TTFT_P95" -gt 0 ]]; then
            SESSION_TTFT_P95="$METRIC_TTFT_P95"
        fi
        if [[ "$METRIC_ITL_P50" =~ ^[0-9]+$ ]] && [[ "$METRIC_ITL_P50" -gt 0 ]]; then
            SESSION_ITL_P50="$METRIC_ITL_P50"
        fi
        if [[ "$METRIC_ITL_P95" =~ ^[0-9]+$ ]] && [[ "$METRIC_ITL_P95" -gt 0 ]]; then
            SESSION_ITL_P95="$METRIC_ITL_P95"
        fi
        if [[ "$METRIC_E2E_AVG" =~ ^[0-9]+$ ]] && [[ "$METRIC_E2E_AVG" -gt 0 ]]; then
            SESSION_E2E_AVG="$METRIC_E2E_AVG"
        fi
        if [[ "$METRIC_E2E_P50" =~ ^[0-9]+$ ]] && [[ "$METRIC_E2E_P50" -gt 0 ]]; then
            SESSION_E2E_P50="$METRIC_E2E_P50"
        fi
        if [[ "$METRIC_E2E_P95" =~ ^[0-9]+$ ]] && [[ "$METRIC_E2E_P95" -gt 0 ]]; then
            SESSION_E2E_P95="$METRIC_E2E_P95"
        fi
        if [[ "$METRIC_TOKENS_PER_REQ" =~ ^[0-9]+$ ]] && [[ "$METRIC_TOKENS_PER_REQ" -gt 0 ]]; then
            SESSION_TOKENS_REQ="$METRIC_TOKENS_PER_REQ"
        fi
        
        STALE_PERFORMANCE=false
    else
        # Use session-persistent values when current metrics are unavailable
        # This ensures final results screen shows data after load test ends
        METRIC_THROUGHPUT="${SESSION_RPS:-${LAST_GOOD_THROUGHPUT:-N/A}}"
        METRIC_TOKENS_PER_SEC="${SESSION_TOKENS_SEC:-${LAST_GOOD_TOKENS_PER_SEC:-N/A}}"
        METRIC_TTFT_P50="${SESSION_TTFT_P50:-N/A}"
        METRIC_TTFT_P95="${SESSION_TTFT_P95:-N/A}"
        METRIC_ITL_P50="${SESSION_ITL_P50:-N/A}"
        METRIC_ITL_P95="${SESSION_ITL_P95:-N/A}"
        METRIC_E2E_AVG="${SESSION_E2E_AVG:-N/A}"
        METRIC_E2E_P50="${SESSION_E2E_P50:-N/A}"
        METRIC_E2E_P95="${SESSION_E2E_P95:-N/A}"
        METRIC_TOKENS_PER_REQ="${SESSION_TOKENS_REQ:-N/A}"
        STALE_PERFORMANCE=true
        log_error "Failed to collect performance metrics, using session-persistent values"
    fi
    
    # Update current RPS from throughput (no fallback - keep it consistent)
    if [[ "$METRIC_THROUGHPUT" =~ ^[0-9]+$ ]]; then
        METRIC_CURRENT_RPS="$METRIC_THROUGHPUT"
    else
        METRIC_CURRENT_RPS=0
    fi
    
    # Update scaling status
    METRIC_SCALING_STATUS=$(determine_scaling_status "pods" "$METRIC_PODS_RUNNING" "$METRIC_PODS_DESIRED")
    
    # Update last update timestamp
    METRIC_LAST_UPDATE=$(date '+%H:%M:%S')
    
    # Always return success - failures are handled gracefully with stale indicators
    return 0
}

# -----------------------------------------------------------------------------
# collect_all_metrics_async - Async version that writes results to a temp file
# Parameters:
#   $1 - Path to temp file where results will be written as shell variable assignments
# Note: This runs in a subshell, so it writes variable assignments to a file
#       that can be sourced by the parent process
# -----------------------------------------------------------------------------
collect_all_metrics_async() {
    local output_file="$1"
    local pod_info queue_depth node_info perf_metrics
    
    # Create temp files for parallel collection
    local tmp_pods=$(mktemp)
    local tmp_queue=$(mktemp)
    local tmp_nodes=$(mktemp)
    local tmp_perf=$(mktemp)
    local tmp_pod_timing=$(mktemp)
    
    # Collect all metrics in parallel
    (get_vllm_pods 2>/dev/null || echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A") > "$tmp_pods" &
    local pid_pods=$!
    
    (get_queue_depth 2>/dev/null || echo "N/A") > "$tmp_queue" &
    local pid_queue=$!
    
    (get_node_info 2>/dev/null || echo "0|0|0") > "$tmp_nodes" &
    local pid_nodes=$!
    
    (get_performance_metrics 2>/dev/null || echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A|0|N/A|N/A") > "$tmp_perf" &
    local pid_perf=$!
    
    (get_pod_timing_info 2>/dev/null || echo "") > "$tmp_pod_timing" &
    local pid_pod_timing=$!
    
    # Wait for all to complete
    wait $pid_pods $pid_queue $pid_nodes $pid_perf $pid_pod_timing 2>/dev/null
    
    # Read results
    pod_info=$(cat "$tmp_pods")
    queue_depth=$(cat "$tmp_queue")
    node_info=$(cat "$tmp_nodes")
    perf_metrics=$(cat "$tmp_perf")
    pod_timing_data=$(cat "$tmp_pod_timing")
    
    # Clean up temp files
    rm -f "$tmp_pods" "$tmp_queue" "$tmp_nodes" "$tmp_perf" "$tmp_pod_timing"
    
    # Write results as shell variable assignments to output file
    {
        # Store pod timing data
        echo "POD_TIMING_DATA='$pod_timing_data'"
        
        # Process pod info (format: running|desired|ready|pending|not_ready|startup_min|startup_max)
        if [[ -n "$pod_info" ]] && [[ "$pod_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\| ]]; then
            echo "METRIC_PODS_RUNNING='$(echo "$pod_info" | cut -d'|' -f1)'"
            echo "METRIC_PODS_DESIRED='$(echo "$pod_info" | cut -d'|' -f2)'"
            echo "METRIC_PODS_READY='$(echo "$pod_info" | cut -d'|' -f3)'"
            echo "METRIC_PODS_PENDING='$(echo "$pod_info" | cut -d'|' -f4)'"
            echo "METRIC_PODS_NOT_READY='$(echo "$pod_info" | cut -d'|' -f5)'"
            echo "METRIC_POD_STARTUP_MIN='$(echo "$pod_info" | cut -d'|' -f6)'"
            echo "METRIC_POD_STARTUP_MAX='$(echo "$pod_info" | cut -d'|' -f7)'"
            echo "LAST_GOOD_PODS_RUNNING='$(echo "$pod_info" | cut -d'|' -f1)'"
            echo "LAST_GOOD_PODS_DESIRED='$(echo "$pod_info" | cut -d'|' -f2)'"
            echo "LAST_GOOD_PODS_READY='$(echo "$pod_info" | cut -d'|' -f3)'"
            echo "STALE_PODS=false"
        elif [[ -n "$pod_info" ]] && [[ "$pod_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
            # Fallback for old 5-field format
            echo "METRIC_PODS_RUNNING='$(echo "$pod_info" | cut -d'|' -f1)'"
            echo "METRIC_PODS_DESIRED='$(echo "$pod_info" | cut -d'|' -f2)'"
            echo "METRIC_PODS_READY='$(echo "$pod_info" | cut -d'|' -f3)'"
            echo "METRIC_PODS_PENDING='$(echo "$pod_info" | cut -d'|' -f4)'"
            echo "METRIC_PODS_NOT_READY='$(echo "$pod_info" | cut -d'|' -f5)'"
            echo "METRIC_POD_STARTUP_MIN='N/A'"
            echo "METRIC_POD_STARTUP_MAX='N/A'"
            echo "LAST_GOOD_PODS_RUNNING='$(echo "$pod_info" | cut -d'|' -f1)'"
            echo "LAST_GOOD_PODS_DESIRED='$(echo "$pod_info" | cut -d'|' -f2)'"
            echo "LAST_GOOD_PODS_READY='$(echo "$pod_info" | cut -d'|' -f3)'"
            echo "STALE_PODS=false"
        elif [[ -n "$pod_info" ]] && [[ "$pod_info" != "N/A|N/A|N/A|N/A|N/A" ]] && [[ "$pod_info" != "N/A|N/A|N/A|N/A|N/A|N/A|N/A" ]]; then
            # Fallback for old format
            echo "METRIC_PODS_RUNNING='$(echo "$pod_info" | cut -d'|' -f1)'"
            echo "METRIC_PODS_DESIRED='$(echo "$pod_info" | cut -d'|' -f2)'"
            echo "METRIC_PODS_READY='$(echo "$pod_info" | cut -d'|' -f3)'"
            echo "METRIC_PODS_PENDING='0'"
            echo "METRIC_PODS_NOT_READY='0'"
            echo "METRIC_POD_STARTUP_MIN='N/A'"
            echo "METRIC_POD_STARTUP_MAX='N/A'"
            echo "STALE_PODS=false"
        else
            echo "STALE_PODS=true"
        fi
        
        # Process queue depth (format: queue_depth|running_requests)
        if [[ -n "$queue_depth" ]] && [[ "$queue_depth" =~ ^[0-9]+\|[0-9]+$ ]]; then
            local qd=$(echo "$queue_depth" | cut -d'|' -f1)
            local rr=$(echo "$queue_depth" | cut -d'|' -f2)
            echo "METRIC_QUEUE_DEPTH='$qd'"
            echo "METRIC_RUNNING_REQUESTS='$rr'"
            echo "LAST_GOOD_QUEUE_DEPTH='$qd'"
            echo "STALE_QUEUE_DEPTH=false"
        elif [[ -n "$queue_depth" ]] && [[ "$queue_depth" =~ ^[0-9]+$ ]]; then
            echo "METRIC_QUEUE_DEPTH='$queue_depth'"
            echo "METRIC_RUNNING_REQUESTS='0'"
            echo "LAST_GOOD_QUEUE_DEPTH='$queue_depth'"
            echo "STALE_QUEUE_DEPTH=false"
        else
            echo "METRIC_RUNNING_REQUESTS='0'"
            echo "STALE_QUEUE_DEPTH=true"
        fi
        
        # Process node info (format: ready|pending|nodeclaims|ondemand|spot)
        if [[ -n "$node_info" ]] && [[ "$node_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
            local ready=$(echo "$node_info" | cut -d'|' -f1)
            local pending=$(echo "$node_info" | cut -d'|' -f2)
            local claims=$(echo "$node_info" | cut -d'|' -f3)
            local ondemand=$(echo "$node_info" | cut -d'|' -f4)
            local spot=$(echo "$node_info" | cut -d'|' -f5)
            local total=$((ready + pending))
            echo "METRIC_NODES_READY='$ready'"
            echo "METRIC_NODES_PENDING='$pending'"
            echo "METRIC_NODECLAIMS_PENDING='$claims'"
            echo "METRIC_NODES_ONDEMAND='$ondemand'"
            echo "METRIC_NODES_SPOT='$spot'"
            echo "METRIC_NODES_COUNT='$total'"
            echo "LAST_GOOD_NODES_COUNT='$total'"
            echo "STALE_NODES=false"
        elif [[ -n "$node_info" ]] && [[ "$node_info" =~ ^[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
            # Fallback for old format (ready|pending|nodeclaims)
            local ready=$(echo "$node_info" | cut -d'|' -f1)
            local pending=$(echo "$node_info" | cut -d'|' -f2)
            local claims=$(echo "$node_info" | cut -d'|' -f3)
            local total=$((ready + pending))
            echo "METRIC_NODES_READY='$ready'"
            echo "METRIC_NODES_PENDING='$pending'"
            echo "METRIC_NODECLAIMS_PENDING='$claims'"
            echo "METRIC_NODES_ONDEMAND='0'"
            echo "METRIC_NODES_SPOT='0'"
            echo "METRIC_NODES_COUNT='$total'"
            echo "LAST_GOOD_NODES_COUNT='$total'"
            echo "STALE_NODES=false"
        elif [[ -n "$node_info" ]] && [[ "$node_info" =~ ^[0-9]+$ ]]; then
            # Fallback for old format
            echo "METRIC_NODES_COUNT='$node_info'"
            echo "METRIC_NODES_READY='$node_info'"
            echo "METRIC_NODES_PENDING='0'"
            echo "METRIC_NODECLAIMS_PENDING='0'"
            echo "METRIC_NODES_ONDEMAND='0'"
            echo "METRIC_NODES_SPOT='0'"
            echo "LAST_GOOD_NODES_COUNT='$node_info'"
            echo "STALE_NODES=false"
        else
            echo "STALE_NODES=true"
        fi
        
        # Process performance metrics
        if [[ -n "$perf_metrics" ]] && [[ "$perf_metrics" != "N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A|0|N/A|N/A" ]]; then
            local throughput=$(echo "$perf_metrics" | cut -d'|' -f1)
            local ttft_p50=$(echo "$perf_metrics" | cut -d'|' -f2)
            local ttft_p95=$(echo "$perf_metrics" | cut -d'|' -f3)
            local itl_p50=$(echo "$perf_metrics" | cut -d'|' -f4)
            local itl_p95=$(echo "$perf_metrics" | cut -d'|' -f5)
            local e2e_avg=$(echo "$perf_metrics" | cut -d'|' -f6)
            local e2e_p50=$(echo "$perf_metrics" | cut -d'|' -f7)
            local e2e_p95=$(echo "$perf_metrics" | cut -d'|' -f8)
            local tokens_per_req=$(echo "$perf_metrics" | cut -d'|' -f9)
            local tokens_per_sec=$(echo "$perf_metrics" | cut -d'|' -f11)
            local kv_cache_pct=$(echo "$perf_metrics" | cut -d'|' -f12)
            echo "METRIC_THROUGHPUT='$throughput'"
            echo "METRIC_TOKENS_PER_SEC='$tokens_per_sec'"
            echo "METRIC_TOKENS_PER_REQ='$tokens_per_req'"
            echo "METRIC_TTFT_P50='$ttft_p50'"
            echo "METRIC_TTFT_P95='$ttft_p95'"
            echo "METRIC_ITL_P50='$itl_p50'"
            echo "METRIC_ITL_P95='$itl_p95'"
            echo "METRIC_E2E_AVG='$e2e_avg'"
            echo "METRIC_E2E_P50='$e2e_p50'"
            echo "METRIC_E2E_P95='$e2e_p95'"
            echo "METRIC_KV_CACHE_PCT='$kv_cache_pct'"
            [[ "$throughput" != "N/A" ]] && echo "LAST_GOOD_THROUGHPUT='$throughput'"
            [[ "$tokens_per_sec" != "N/A" ]] && echo "LAST_GOOD_TOKENS_PER_SEC='$tokens_per_sec'"
            # Update session-persistent values (only when we have valid non-zero data)
            [[ "$throughput" =~ ^[0-9]+$ ]] && [[ "$throughput" -gt 0 ]] && echo "SESSION_RPS='$throughput'"
            [[ "$tokens_per_sec" =~ ^[0-9]+$ ]] && [[ "$tokens_per_sec" -gt 0 ]] && echo "SESSION_TOKENS_SEC='$tokens_per_sec'"
            [[ "$ttft_p50" =~ ^[0-9]+$ ]] && [[ "$ttft_p50" -gt 0 ]] && echo "SESSION_TTFT_P50='$ttft_p50'"
            [[ "$ttft_p95" =~ ^[0-9]+$ ]] && [[ "$ttft_p95" -gt 0 ]] && echo "SESSION_TTFT_P95='$ttft_p95'"
            [[ "$itl_p50" =~ ^[0-9]+$ ]] && [[ "$itl_p50" -gt 0 ]] && echo "SESSION_ITL_P50='$itl_p50'"
            [[ "$itl_p95" =~ ^[0-9]+$ ]] && [[ "$itl_p95" -gt 0 ]] && echo "SESSION_ITL_P95='$itl_p95'"
            [[ "$e2e_avg" =~ ^[0-9]+$ ]] && [[ "$e2e_avg" -gt 0 ]] && echo "SESSION_E2E_AVG='$e2e_avg'"
            [[ "$e2e_p50" =~ ^[0-9]+$ ]] && [[ "$e2e_p50" -gt 0 ]] && echo "SESSION_E2E_P50='$e2e_p50'"
            [[ "$e2e_p95" =~ ^[0-9]+$ ]] && [[ "$e2e_p95" -gt 0 ]] && echo "SESSION_E2E_P95='$e2e_p95'"
            [[ "$tokens_per_req" =~ ^[0-9]+$ ]] && [[ "$tokens_per_req" -gt 0 ]] && echo "SESSION_TOKENS_REQ='$tokens_per_req'"
            echo "STALE_PERFORMANCE=false"
            # Use throughput directly for graph RPS (no fallback to queue_depth)
            if [[ "$throughput" =~ ^[0-9]+$ ]]; then
                echo "METRIC_CURRENT_RPS='$throughput'"
            else
                echo "METRIC_CURRENT_RPS='0'"
            fi
        else
            # Use session-persistent values when current metrics are unavailable
            local fallback_rps="${SESSION_RPS:-${LAST_GOOD_THROUGHPUT:-N/A}}"
            local fallback_tokens="${SESSION_TOKENS_SEC:-${LAST_GOOD_TOKENS_PER_SEC:-N/A}}"
            local fallback_ttft_p50="${SESSION_TTFT_P50:-N/A}"
            local fallback_ttft_p95="${SESSION_TTFT_P95:-N/A}"
            local fallback_itl_p50="${SESSION_ITL_P50:-N/A}"
            local fallback_itl_p95="${SESSION_ITL_P95:-N/A}"
            local fallback_e2e_avg="${SESSION_E2E_AVG:-N/A}"
            local fallback_e2e_p50="${SESSION_E2E_P50:-N/A}"
            local fallback_e2e_p95="${SESSION_E2E_P95:-N/A}"
            local fallback_tokens_req="${SESSION_TOKENS_REQ:-N/A}"
            echo "METRIC_THROUGHPUT='$fallback_rps'"
            echo "METRIC_TOKENS_PER_SEC='$fallback_tokens'"
            echo "METRIC_TTFT_P50='$fallback_ttft_p50'"
            echo "METRIC_TTFT_P95='$fallback_ttft_p95'"
            echo "METRIC_ITL_P50='$fallback_itl_p50'"
            echo "METRIC_ITL_P95='$fallback_itl_p95'"
            echo "METRIC_E2E_AVG='$fallback_e2e_avg'"
            echo "METRIC_E2E_P50='$fallback_e2e_p50'"
            echo "METRIC_E2E_P95='$fallback_e2e_p95'"
            echo "METRIC_TOKENS_PER_REQ='$fallback_tokens_req'"
            echo "METRIC_KV_CACHE_PCT='N/A'"
            echo "STALE_PERFORMANCE=true"
            echo "METRIC_CURRENT_RPS='0'"
        fi
        
        # Update timestamp
        echo "METRIC_LAST_UPDATE='$(date '+%H:%M:%S')'"
    } > "$output_file"
}

# -----------------------------------------------------------------------------
# render_dashboard - Render the complete dashboard to the terminal
# Requirements: 6.2 (cursor positioning), 7.1 (organized layout)
# Side effects:
#   - Moves cursor to home position (top-left)
#   - Renders all dashboard sections in order
#   - Displays footer with controls
# Notes:
#   - Uses cursor positioning instead of full screen clear to avoid flicker
# -----------------------------------------------------------------------------
render_dashboard() {
    # Move cursor to home position (top-left) without clearing screen
    # This prevents flicker during updates
    printf "${CURSOR_HOME}"
    
    # Render all sections in order
    render_header
    echo ""  # Spacing
    render_load_section
    render_queue_section
    render_pods_section
    render_nodes_section
    render_performance_section
    echo ""  # Spacing
    render_footer
    
    # Clear any remaining content from previous renders
    printf "${CLEAR_LINE}"
}

# -----------------------------------------------------------------------------
# cleanup - Cleanup function called on exit
# Requirements: 8.3 (graceful exit)
# Side effects:
#   - Restores cursor visibility
#   - Stops port-forward process
#   - Displays goodbye message
#   - Logs shutdown event
# -----------------------------------------------------------------------------
cleanup() {
    # Prevent recursive cleanup calls
    trap - EXIT
    
    # Stop port-forward if running
    stop_port_forward
    
    # Restore cursor visibility
    printf "${CURSOR_SHOW}"
    
    # Move to a new line and display goodbye message
    echo ""
    echo -e "${COLOR_GOOD}Dashboard stopped. Goodbye!${NC}"
    
    # Log the shutdown
    log_info "Dashboard session ended (cleanup called)"
    
    # Reset RUNNING flag
    RUNNING=false
    
    # Kill tmux session if running inside one
    if [[ -n "$TMUX" ]]; then
        tmux kill-session -t demo-dashboard 2>/dev/null
    fi
}

# -----------------------------------------------------------------------------
# handle_signal - Signal handler for SIGINT and SIGTERM
# Requirements: 8.3 (graceful Ctrl+C handling)
# Side effects:
#   - Sets RUNNING flag to false to stop the main loop
#   - Logs the signal received
# -----------------------------------------------------------------------------
handle_signal() {
    log_info "Received termination signal, shutting down gracefully"
    RUNNING=false
}

# -----------------------------------------------------------------------------
# run_dashboard - Main dashboard loop
# Requirements: 6.1 (2-second refresh), 6.4 (elapsed time)
# Side effects:
#   - Initializes start time
#   - Runs continuous loop: collect → update → render → sleep
#   - Handles Ctrl+C gracefully
# -----------------------------------------------------------------------------
run_dashboard() {
    # Initialize start time for elapsed calculation
    START_TIME=$(date +%s)
    
    # Set up signal handlers for graceful exit
    trap handle_signal SIGINT SIGTERM
    trap cleanup EXIT
    
    # Hide cursor during dashboard operation
    printf "${CURSOR_HIDE}"
    
    # Clear screen once at startup
    printf "${CLEAR_SCREEN}${CURSOR_HOME}"
    
    # Log startup
    log_info "Dashboard started"
    
    # Async collection state
    local collection_pid=""
    local collection_tmp=""
    
    # Main loop - renders every REFRESH_INTERVAL seconds regardless of collection status
    while [[ "$RUNNING" == "true" ]]; do
        # Check if background collection has completed
        if [[ -n "$collection_pid" ]]; then
            if ! kill -0 "$collection_pid" 2>/dev/null; then
                # Collection finished - read results and update metrics
                if [[ -f "$collection_tmp" ]]; then
                    source "$collection_tmp" 2>/dev/null
                    rm -f "$collection_tmp"
                fi
                collection_pid=""
                collection_tmp=""
            fi
        fi
        
        # Start new background collection if none is running
        if [[ -z "$collection_pid" ]]; then
            collection_tmp=$(mktemp)
            (
                # Run collection and write results to temp file
                collect_all_metrics_async "$collection_tmp"
            ) &
            collection_pid=$!
        fi
        
        # Always add current RPS to history for graph animation
        # This ensures graph moves even when waiting for new data
        add_to_load_history "$METRIC_CURRENT_RPS"
        
        # Render the dashboard with current (possibly stale) values
        render_dashboard
        
        # Sleep for refresh interval (responsive to signals)
        local sleep_count=0
        while [[ $sleep_count -lt $REFRESH_INTERVAL ]] && [[ "$RUNNING" == "true" ]]; do
            sleep 1
            sleep_count=$((sleep_count + 1))
        done
    done
    
    # Cleanup background collection if still running
    if [[ -n "$collection_pid" ]]; then
        kill "$collection_pid" 2>/dev/null
        wait "$collection_pid" 2>/dev/null
        [[ -n "$collection_tmp" ]] && rm -f "$collection_tmp"
    fi
    
    # Log shutdown
    log_info "Dashboard stopped"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

main() {
    # Initialize error logging
    init_error_log
    
    # Run prerequisite checks before starting dashboard
    if ! run_prerequisite_checks; then
        echo "" >&2
        echo -e "${COLOR_ERROR}Dashboard cannot start due to failed prerequisite checks.${NC}" >&2
        echo "Check the log file for details: $ERROR_LOG" >&2
        exit 1
    fi
    
    # Small delay to let user see the check results
    sleep 1
    
    # Run the dashboard
    run_dashboard
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
