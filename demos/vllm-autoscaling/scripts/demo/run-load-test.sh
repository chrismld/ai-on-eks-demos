#!/bin/bash
# Run k6 load test inside the cluster
# Usage: ./scripts/run-load-test.sh [--watch] [--cleanup-only] [--report]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
    echo -e "${YELLOW}Cleaning up previous k6 job...${NC}"
    kubectl delete job k6-load-test --ignore-not-found=true -n default 2>/dev/null || true
    while kubectl get pods -n default -l job-name=k6-load-test 2>/dev/null | grep -q k6; do
        echo "Waiting for old k6 pod to terminate..."
        sleep 2
    done
    echo -e "${GREEN}Cleanup complete${NC}"
}

run_test() {
    echo -e "${GREEN}Applying k6 ConfigMap and Job...${NC}"
    kubectl apply -f "$PROJECT_ROOT/kubernetes/k6-load-test.yaml"
    
    echo -e "${YELLOW}Waiting for k6 pod to start...${NC}"
    kubectl wait --for=condition=Ready pod -l job-name=k6-load-test -n default --timeout=60s 2>/dev/null || true
    
    echo -e "${GREEN}k6 load test started at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
}

wait_for_completion() {
    echo -e "${YELLOW}Waiting for test to complete...${NC}"
    kubectl wait --for=condition=complete job/k6-load-test -n default --timeout=600s 2>/dev/null || true
}

show_report() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}                    LOAD TEST REPORT                            ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # k6 Results
    echo -e "${BOLD}${GREEN}📊 k6 Results${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    kubectl logs job/k6-load-test -n default 2>/dev/null | grep -A 30 "█ TOTAL RESULTS" | head -25
    echo ""
    
    # Scaling Summary
    echo -e "${BOLD}${GREEN}📈 Scaling Summary${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo "vLLM Pods:"
    kubectl get pods -l app=vllm -n default -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status,AGE:.metadata.creationTimestamp' 2>/dev/null
    echo ""
    
    echo "GPU Nodes:"
    kubectl get nodes -l intent=gpu-inference -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status,AGE:.metadata.creationTimestamp' 2>/dev/null
    echo ""
    
    echo "Node Claims:"
    kubectl get nodeclaims 2>/dev/null | grep gpu || echo "  No GPU node claims"
    echo ""
    
    # HPA Status
    echo -e "${BOLD}${GREEN}⚖️  HPA Status${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    kubectl get hpa -n default 2>/dev/null || echo "  No HPA found"
    echo ""
    
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Test completed at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
}

show_status() {
    echo ""
    echo -e "${GREEN}=== Current Status ===${NC}"
    echo ""
    echo "k6 Job:"
    kubectl get job k6-load-test -n default 2>/dev/null || echo "  No k6 job running"
    echo ""
    echo "vLLM Pods:"
    kubectl get pods -l app=vllm -n default 2>/dev/null
    echo ""
    echo "GPU Nodes:"
    kubectl get nodes -l intent=gpu-inference 2>/dev/null || echo "  No GPU nodes"
    echo ""
}

# Parse arguments
WATCH=false
CLEANUP_ONLY=false
REPORT=false

for arg in "$@"; do
    case $arg in
        --watch|-w)
            WATCH=true
            ;;
        --cleanup-only|-c)
            CLEANUP_ONLY=true
            ;;
        --report|-r)
            REPORT=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --watch, -w        Stream k6 logs after starting"
            echo "  --report, -r       Wait for completion and show full report"
            echo "  --cleanup-only, -c Only cleanup, don't start new test"
            echo "  --help, -h         Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                 # Cleanup and run new test"
            echo "  $0 --watch         # Cleanup, run, and stream logs"
            echo "  $0 --report        # Cleanup, run, wait, and show report"
            echo "  $0 --cleanup-only  # Just cleanup old job"
            exit 0
            ;;
    esac
done

# Always cleanup first
cleanup

if [ "$CLEANUP_ONLY" = true ]; then
    echo -e "${GREEN}Done!${NC}"
    exit 0
fi

# Run the test
run_test

if [ "$REPORT" = true ]; then
    wait_for_completion
    show_report
elif [ "$WATCH" = true ]; then
    echo -e "${YELLOW}Streaming k6 logs (Ctrl+C to stop watching, test continues)...${NC}"
    echo ""
    kubectl logs -f job/k6-load-test -n default 2>/dev/null || true
    show_report
else
    show_status
    echo -e "${YELLOW}Tip: Run with --report to wait and show full report${NC}"
    echo -e "${YELLOW}     Run with --watch to stream logs${NC}"
    echo ""
    echo "Manual commands:"
    echo "  kubectl logs -f job/k6-load-test"
    echo "  kubectl get pods -l app=vllm -w"
fi
