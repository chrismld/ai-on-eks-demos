#!/bin/bash
set -e
export PATH="/usr/local/bin:$PATH"

SCRIPT_DIR=$(dirname "$0")

echo "🔧 Updating Kubernetes manifests..."

# Source demo config if it exists
CONFIG_FILE="$SCRIPT_DIR/../.demo-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Get values from AWS CLI / environment
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-$(aws configure get region)}

# Use PROJECT_NAME from config, or auto-detect from ECR, or use default
if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME=$(aws ecr describe-repositories \
    --query "repositories[?contains(repositoryName, '/api')].repositoryName | [0]" \
    --output text 2>/dev/null | cut -d'/' -f1)
  [ "$PROJECT_NAME" = "None" ] || [ -z "$PROJECT_NAME" ] && PROJECT_NAME="ai-workloads-tube-demo"
fi

# Use CLUSTER_NAME from config or default (for Karpenter resources)
CLUSTER_NAME="${CLUSTER_NAME:-kedify-on-eks-blueprint}"

# Model configuration from config or defaults (AWQ quantized for T4 GPU compatibility)
MODEL_NAME="${MODEL_NAME:-TheBloke/Mistral-7B-Instruct-v0.2-AWQ}"
MODEL_S3_PATH="${MODEL_S3_PATH:-models/mistral-7b-awq}"

# Get S3 bucket name for models
MODELS_BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name, 'models-${AWS_ACCOUNT_ID}')].Name | [0]" \
  --output text 2>/dev/null || echo "")
[ "$MODELS_BUCKET" = "None" ] && MODELS_BUCKET=""

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "📦 Configuration:"
echo "   Account: ${AWS_ACCOUNT_ID}"
echo "   Region: ${AWS_REGION}"
echo "   Project: ${PROJECT_NAME}"
echo "   Registry: ${REGISTRY}"
echo "   Model: ${MODEL_NAME}"
if [ -n "$MODELS_BUCKET" ]; then
  echo "   Models S3: s3://${MODELS_BUCKET}/${MODEL_S3_PATH}/"
else
  echo "   Models S3: (not found - run 'make setup-infra' first)"
fi
if [ -n "$EFS_FILESYSTEM_ID" ]; then
  echo "   EFS Cache: ${EFS_FILESYSTEM_ID}"
fi
echo ""

# Update API deployment from template
echo "📝 Generating kubernetes/api/deployment.yaml from template..."
sed \
  -e "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g" \
  -e "s|PROJECT_PLACEHOLDER|${PROJECT_NAME}|g" \
  -e "s|REGION_PLACEHOLDER|${AWS_REGION}|g" \
  kubernetes/api/deployment.yaml.template > kubernetes/api/deployment.yaml

# Update Frontend deployment from template
echo "📝 Generating kubernetes/frontend/deployment.yaml from template..."
sed \
  -e "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g" \
  -e "s|PROJECT_PLACEHOLDER|${PROJECT_NAME}|g" \
  kubernetes/frontend/deployment.yaml.template > kubernetes/frontend/deployment.yaml

# Update vLLM deployment from template
if [ -n "$MODELS_BUCKET" ]; then
  echo "📝 Generating kubernetes/vllm/deployment.yaml from template..."
  S3_MODEL_PATH="s3://${MODELS_BUCKET}/${MODEL_S3_PATH}/"
  sed \
    -e "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g" \
    -e "s|S3_MODEL_PATH_PLACEHOLDER|${S3_MODEL_PATH}|g" \
    -e "s|MODEL_NAME_PLACEHOLDER|${MODEL_NAME}|g" \
    kubernetes/vllm/deployment.yaml.template > kubernetes/vllm/deployment.yaml
else
  echo "⚠️  Skipping vLLM manifest (models bucket not found)"
fi

# Update Karpenter EC2NodeClass from template
echo "📝 Generating kubernetes/karpenter/gpu-nodeclass.yaml from template..."

# Check if SNAPSHOT_ID is set for pre-cached container images
if [ -n "$SNAPSHOT_ID" ]; then
  echo "   Using EBS snapshot: ${SNAPSHOT_ID}"
  sed \
    -e "s|\${CLUSTER_NAME}|${CLUSTER_NAME}|g" \
    -e "s|\${SNAPSHOT_ID}|${SNAPSHOT_ID}|g" \
    kubernetes/karpenter/gpu-nodeclass.yaml.template > kubernetes/karpenter/gpu-nodeclass.yaml
else
  echo "⚠️  SNAPSHOT_ID not set - generating nodeclass without snapshot"
  echo "   Set SNAPSHOT_ID in .demo-config after creating a snapshot"
  # Remove the snapshotID line if not set
  sed \
    -e "s|\${CLUSTER_NAME}|${CLUSTER_NAME}|g" \
    -e '/snapshotID:/d' \
    kubernetes/karpenter/gpu-nodeclass.yaml.template > kubernetes/karpenter/gpu-nodeclass.yaml
fi

# Update torch.compile cache storage from template (EFS)
# Get EFS filesystem ID from .demo-config or auto-detect via AWS CLI
if [ -z "$EFS_FILESYSTEM_ID" ]; then
  # Try to find EFS by name tag (created by terraform with name: ${cluster_name}-torch-cache)
  EFS_FILESYSTEM_ID=$(aws efs describe-file-systems \
    --query "FileSystems[?Name=='${CLUSTER_NAME}-torch-cache'].FileSystemId | [0]" \
    --output text 2>/dev/null || echo "")
  [ "$EFS_FILESYSTEM_ID" = "None" ] && EFS_FILESYSTEM_ID=""
fi

if [ -n "$EFS_FILESYSTEM_ID" ]; then
  echo "📝 Generating kubernetes/vllm/torch-cache-storage.yaml from template..."
  echo "   Using EFS filesystem: ${EFS_FILESYSTEM_ID}"
  sed \
    -e "s|EFS_FILESYSTEM_ID_PLACEHOLDER|${EFS_FILESYSTEM_ID}|g" \
    kubernetes/vllm/torch-cache-storage.yaml.template > kubernetes/vllm/torch-cache-storage.yaml
else
  echo "⚠️  Skipping torch-cache-storage manifest (EFS not provisioned yet)"
  echo "   Run 'terraform apply' first, then re-run this script"
fi

echo ""
echo "✅ Manifests generated!"
echo ""
echo "💡 You can now deploy with: make deploy-apps"
