#!/bin/bash
set -e

echo "🔍 Getting frontend URL..."

# Check if CloudFront is configured
CLOUDFRONT_URL=$(cd terraform && terraform output -raw cloudfront_url 2>/dev/null || echo "")

if [ -n "$CLOUDFRONT_URL" ] && [ "$CLOUDFRONT_URL" != "" ]; then
  echo ""
  echo "✅ CloudFront URL: $CLOUDFRONT_URL"
  echo ""
  echo "💡 Using CloudFront distribution (secure, global CDN)"
  echo "📱 Generate QR code with: make generate-qr"
  echo ""
  exit 0
fi

# Fallback to ALB if CloudFront not configured
INGRESS_URL=$(kubectl get ingress frontend -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$INGRESS_URL" ]; then
  echo "❌ Frontend ingress not found or ALB not ready yet"
  echo "   Run 'kubectl get ingress -n default' to check status"
  exit 1
fi

echo ""
echo "✅ Frontend ALB URL: http://$INGRESS_URL"
echo ""
echo "💡 For secure public access, run: make setup-cloudfront"
echo "📱 Generate QR code with: make generate-qr"
echo ""
