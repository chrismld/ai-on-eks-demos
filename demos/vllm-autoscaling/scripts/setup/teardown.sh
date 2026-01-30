#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "💥 Tearing down..."

# Load config
CONFIG_FILE="$PROJECT_ROOT/.demo-config"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# Delete all services (removes ALBs)
kubectl delete --all svc 2>/dev/null || true

# Delete Karpenter resources
kubectl delete --all nodeclaim 2>/dev/null || true
kubectl delete --all nodepool 2>/dev/null || true

# Delete EBS snapshot if it exists
if [ -n "$SNAPSHOT_ID" ]; then
  echo "🗑️  Deleting EBS snapshot: $SNAPSHOT_ID"
  aws ec2 delete-snapshot --snapshot-id "$SNAPSHOT_ID" 2>/dev/null || true
fi

# Terraform destroy
cd "$PROJECT_ROOT/terraform"
terraform destroy -auto-approve

echo "✅ Cleanup complete!"
