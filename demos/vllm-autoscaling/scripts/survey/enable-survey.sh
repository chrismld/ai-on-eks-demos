#!/bin/bash
set -e

echo "🎯 Switching to survey mode..."
echo ""

# Get config from Terraform if available
if [ -d "terraform" ] && [ -f "terraform/terraform.tfstate" ]; then
  cd terraform
  AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")
  PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null || echo "ai-workloads-tube-demo")
  cd ..
else
  AWS_REGION="eu-west-1"
  PROJECT_NAME="ai-workloads-tube-demo"
fi

# Archive current session if it exists
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$AWS_ACCOUNT" ]; then
  echo "❌ Error: Could not determine AWS account ID"
  exit 1
fi

BUCKET="${PROJECT_NAME}-responses-${AWS_ACCOUNT}"

# Check if there's anything in current/
CURRENT_EXISTS=$(aws s3 ls s3://$BUCKET/current/ 2>/dev/null || echo "")

if [ -n "$CURRENT_EXISTS" ]; then
  ARCHIVE_NAME=$(date +"%Y%m%d-%H%M%S")
  echo "📦 Archiving previous session to archive/$ARCHIVE_NAME/..."
  aws s3 sync s3://$BUCKET/current/ s3://$BUCKET/archive/$ARCHIVE_NAME/ --quiet
  aws s3 rm s3://$BUCKET/current/ --recursive --quiet
  echo "✅ Previous session archived"
  echo ""
fi

SESSION_ID=$(date +"%Y%m%d-%H%M%S")
echo "{\"sessionId\": \"$SESSION_ID\"}" | aws s3 cp - s3://$BUCKET/current/session.json --quiet
echo "📝 Created new session: $SESSION_ID"

echo "🔧 Enabling survey mode..."
kubectl patch configmap api-config \
  -n default \
  --type merge \
  -p '{"data":{"DEMO_MODE":"survey"}}'

echo "🔄 Restarting API..."
kubectl rollout restart deployment/api -n default

echo "⏳ Waiting for API to be ready..."
kubectl rollout status deployment/api -n default

echo "✅ Survey mode enabled!"
echo ""
echo "💡 Refresh the frontend page to see the survey"
echo "🎁 To pick winners: ./scripts/pick-winners.sh"

