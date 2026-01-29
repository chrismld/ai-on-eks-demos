#!/bin/bash
set -e

# Load config from .demo-config if it exists
if [ -f ".demo-config" ]; then
  echo "🔍 Loading configuration from .demo-config..."
  source .demo-config
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-"eu-west-1"}
PROJECT_NAME=${PROJECT_NAME:-"tube-demo"}

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "📦 Configuration:"
echo "   Account: ${AWS_ACCOUNT_ID}"
echo "   Region: ${AWS_REGION}"
echo "   Project: ${PROJECT_NAME}"
echo "   Registry: ${REGISTRY}"
echo ""

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY

# Ensure we're using a buildx builder that supports multi-platform
if ! docker buildx inspect multiarch-builder &>/dev/null; then
  echo "Creating multiarch builder..."
  docker buildx create --name multiarch-builder --use
else
  echo "Using existing multiarch-builder..."
  docker buildx use multiarch-builder
fi

# Build and push API
echo "📦 Building API..."
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t $REGISTRY/${PROJECT_NAME}/api:latest \
  --push \
  app/api/

# Build and push Frontend
echo "📦 Building Frontend..."
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t $REGISTRY/${PROJECT_NAME}/frontend:latest \
  --push \
  app/frontend/

echo "✅ Images built and pushed!"
echo ""
echo "💡 Next step: Update Kubernetes manifests with these image URLs"
echo "   Run: ./scripts/update-manifests.sh"
