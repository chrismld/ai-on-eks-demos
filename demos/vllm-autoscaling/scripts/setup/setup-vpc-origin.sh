#!/bin/bash
set -e

echo "🔧 Setting up CloudFront VPC Origin for internal ALB..."

# Get region from Terraform
cd terraform
AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-1")
cd ..

# Get ALB ARN
echo "📋 Getting ALB ARN from region: $AWS_REGION..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-default-frontend')].LoadBalancerArn" \
  --output text \
  --region $AWS_REGION)

if [ -z "$ALB_ARN" ]; then
  echo "❌ Error: Could not find internal ALB"
  echo "   Make sure the ingress is deployed: kubectl get ingress frontend -n default"
  exit 1
fi

echo "✅ Found ALB: $ALB_ARN"
echo ""

# List all VPC Origins (without region filter to see everything)
echo "🔍 Listing all VPC Origins..."
ALL_ORIGINS=$(aws cloudfront list-vpc-origins --query 'VpcOrigins[*].[Id,VpcOriginEndpointConfig.Name,Status]' --output text 2>/dev/null || echo "")

if [ -n "$ALL_ORIGINS" ]; then
  echo "$ALL_ORIGINS"
  echo ""
fi

# Try to create VPC Origin with a unique name
TIMESTAMP=$(date +%s)
ORIGIN_NAME="frontend-alb-${TIMESTAMP}"

echo "🌐 Creating CloudFront VPC Origin with name: $ORIGIN_NAME"
VPC_ORIGIN_ID=$(aws cloudfront create-vpc-origin \
  --vpc-origin-endpoint-config \
    Name=$ORIGIN_NAME,\
Arn=$ALB_ARN,\
HTTPPort=80,\
HTTPSPort=443,\
OriginProtocolPolicy=http-only \
  --query 'VpcOrigin.Id' \
  --output text 2>&1)

# Check if creation failed
if echo "$VPC_ORIGIN_ID" | grep -q "error occurred"; then
  echo "❌ Error creating VPC Origin:"
  echo "$VPC_ORIGIN_ID"
  echo ""
  echo "Trying to find existing VPC Origin by listing all..."
  
  # Get the first VPC Origin ID if any exist
  FIRST_ORIGIN=$(aws cloudfront list-vpc-origins --query 'VpcOrigins[0].Id' --output text 2>/dev/null || echo "")
  
  if [ -n "$FIRST_ORIGIN" ] && [ "$FIRST_ORIGIN" != "None" ]; then
    echo "Found VPC Origin: $FIRST_ORIGIN"
    echo "Checking if it points to the correct ALB..."
    
    ORIGIN_ARN=$(aws cloudfront get-vpc-origin --id "$FIRST_ORIGIN" --query 'VpcOrigin.VpcOriginEndpointConfig.Arn' --output text 2>/dev/null || echo "")
    
    if [ "$ORIGIN_ARN" == "$ALB_ARN" ]; then
      echo "✅ This VPC Origin already points to your ALB!"
      VPC_ORIGIN_ID=$FIRST_ORIGIN
    else
      echo "❌ This VPC Origin points to a different ALB: $ORIGIN_ARN"
      echo "   Expected: $ALB_ARN"
      echo ""
      echo "Please delete the old VPC Origin and run this script again:"
      echo "   aws cloudfront delete-vpc-origin --id $FIRST_ORIGIN"
      exit 1
    fi
  else
    echo "❌ Could not find or create VPC Origin"
    exit 1
  fi
fi

echo "✅ VPC Origin ID: $VPC_ORIGIN_ID"

# Check status
echo "📊 Checking VPC Origin status..."
STATUS=$(aws cloudfront get-vpc-origin --id "$VPC_ORIGIN_ID" --query 'VpcOrigin.Status' --output text 2>/dev/null || echo "Unknown")
echo "   Status: $STATUS"
echo ""
echo "⏳ Waiting for VPC Origin to be deployed (this takes ~15 minutes)..."
echo "   You can check status with:"
echo "   aws cloudfront get-vpc-origin --id $VPC_ORIGIN_ID --query 'VpcOrigin.Status'"
echo ""

# Wait for deployment
while true; do
  STATUS=$(aws cloudfront get-vpc-origin --id $VPC_ORIGIN_ID --query 'VpcOrigin.Status' --output text --region us-east-1)
  echo "   Status: $STATUS"
  
  if [ "$STATUS" == "Deployed" ]; then
    echo "✅ VPC Origin is deployed!"
    break
  elif [ "$STATUS" == "Failed" ]; then
    echo "❌ VPC Origin deployment failed"
    exit 1
  fi
  
  sleep 30
done

echo ""
echo "📝 Updating terraform.tfvars with VPC Origin ID..."

# Check if terraform.tfvars exists
if [ ! -f terraform/terraform.tfvars ]; then
  echo "❌ Error: terraform/terraform.tfvars not found"
  echo "   Copy terraform.tfvars.example first: cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
  exit 1
fi

# Update or add the VPC Origin ID
if grep -q "cloudfront_vpc_origin_id" terraform/terraform.tfvars; then
  # Update existing line
  sed -i.bak "s|^.*cloudfront_vpc_origin_id.*|cloudfront_vpc_origin_id = \"$VPC_ORIGIN_ID\"|" terraform/terraform.tfvars
  rm terraform/terraform.tfvars.bak
else
  # Add new line
  echo "" >> terraform/terraform.tfvars
  echo "# CloudFront VPC Origin ID" >> terraform/terraform.tfvars
  echo "cloudfront_vpc_origin_id = \"$VPC_ORIGIN_ID\"" >> terraform/terraform.tfvars
fi

echo "✅ terraform.tfvars updated with VPC Origin ID"
echo ""
echo "🚀 Now run: make setup-cloudfront"
