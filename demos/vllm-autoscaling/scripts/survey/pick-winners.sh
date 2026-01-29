#!/bin/bash
set -e

echo "🎁 Drawing winners from current session"

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

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$AWS_ACCOUNT" ]; then
  echo "❌ Error: Could not determine AWS account ID"
  exit 1
fi

BUCKET="${PROJECT_NAME}-responses-${AWS_ACCOUNT}"

echo "📦 Using bucket: $BUCKET"
echo ""

# Check if bucket exists
if ! aws s3api head-bucket --bucket $BUCKET --region $AWS_REGION 2>/dev/null; then
  echo "❌ Error: Bucket $BUCKET does not exist"
  exit 1
fi

# List responses from current session
echo "🔍 Looking for survey responses..."
RESPONSES=$(aws s3 ls s3://$BUCKET/current/responses/ --recursive 2>/dev/null | awk '{print $4}' | grep -v "^$" || echo "")

if [ -z "$RESPONSES" ]; then
  echo "❌ No responses found in current session"
  exit 1
fi

RESPONSE_COUNT=$(echo "$RESPONSES" | wc -l | tr -d ' ')
echo "📊 Found $RESPONSE_COUNT survey responses"

# Pick 2 random (or all if less than 2)
if [ "$RESPONSE_COUNT" -lt 2 ]; then
  echo "⚠️  Only $RESPONSE_COUNT response(s) found, selecting all"
  WINNERS="$RESPONSES"
else
  # Use gshuf on macOS (from coreutils) or shuf on Linux, fallback to sort -R
  if command -v gshuf &> /dev/null; then
    WINNERS=$(echo "$RESPONSES" | gshuf -n 2)
  elif command -v shuf &> /dev/null; then
    WINNERS=$(echo "$RESPONSES" | shuf -n 2)
  else
    WINNERS=$(echo "$RESPONSES" | sort -R | head -n 2)
  fi
fi

echo ""
echo "🎉 Winners:"
echo "=================================="
echo "$WINNERS" | sed "s|current/responses/||g" | sed 's|.json||g'
echo "=================================="
echo ""

# Extract just the IDs for the JSON
WINNER_IDS=$(echo "$WINNERS" | sed "s|current/responses/||g" | sed 's|.json||g')

# Write winners to S3
echo "💾 Saving winners to S3..."
WINNERS_JSON=$(echo "$WINNER_IDS" | jq -Rs 'split("\n") | map(select(length > 0))')

aws s3 cp - s3://$BUCKET/current/winners.json <<EOF
{"winners": $WINNERS_JSON}
EOF

echo "✅ Winners announced!"
echo ""
echo "💡 Winners will see a notification on their screen automatically"
