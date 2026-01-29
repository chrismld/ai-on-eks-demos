#!/bin/bash
set -e

# Run Demo - Starts load test and dashboard side by side
# Usage: ./scripts/run-demo.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚇 Starting Tube Demo..."
echo ""
echo "This will:"
echo "  1. Start the k6 load test (in-cluster)"
echo "  2. Launch the terminal dashboard"
echo ""

# Start the load test
echo "🔥 Starting k6 load test..."
bash "$SCRIPT_DIR/run-load-test.sh"

echo ""
echo "📊 Starting terminal dashboard..."
echo "   (Press Ctrl+C to exit)"
echo ""
sleep 2

# Start the dashboard (runs in foreground)
bash "$SCRIPT_DIR/../dashboard/demo-dashboard.sh"
