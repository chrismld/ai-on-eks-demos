#!/bin/bash
set -e

echo "💥 Tearing down..."

# Load config
if [ -f ".demo-config" ]; then
  source .demo-config
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
cd terraform
terraform destroy -auto-approve

echo "✅ Cleanup complete!"
