#!/bin/bash

echo "🔍 Getting frontend URL..."

# Check if CloudFront is configured first
CLOUDFRONT_URL=$(cd terraform && terraform output -raw cloudfront_url 2>/dev/null || echo "")

if [ -n "$CLOUDFRONT_URL" ] && [ "$CLOUDFRONT_URL" != "" ]; then
  FRONTEND_URL="$CLOUDFRONT_URL"
  echo "✅ Using CloudFront URL: $FRONTEND_URL"
else
  # Fallback to ALB
  ALB_HOSTNAME=$(kubectl get ingress frontend -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  
  if [ -z "$ALB_HOSTNAME" ]; then
    echo "❌ Could not get frontend URL. Make sure the ingress is deployed and ALB is provisioned."
    echo ""
    echo "Check status with: kubectl get ingress frontend"
    exit 1
  fi
  
  FRONTEND_URL="http://$ALB_HOSTNAME"
  echo "✅ Using ALB URL: $FRONTEND_URL"
  echo "💡 For secure public access, run: make setup-cloudfront"
fi

echo ""
echo "📱 Generate QR code using one of these methods:"
echo ""
echo "1. Online (quick):"
echo "   https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$FRONTEND_URL"
echo ""
echo "2. Command line (if qrencode installed):"
echo "   qrencode -t UTF8 '$FRONTEND_URL'"
echo ""
echo "3. macOS (if qrencode installed):"
echo "   qrencode -t PNG -o qr-code.png '$FRONTEND_URL' && open qr-code.png"
echo ""
echo "4. Copy URL to clipboard (macOS):"
echo "   echo '$FRONTEND_URL' | pbcopy"
echo ""

# Try to generate QR code if qrencode is available
if command -v qrencode &> /dev/null; then
  echo "🎨 Generating QR code in terminal..."
  echo ""
  qrencode -t UTF8 "$FRONTEND_URL"
  echo ""
  echo "✅ QR code generated above!"
else
  echo "💡 Tip: Install qrencode for terminal QR codes:"
  echo "   macOS: brew install qrencode"
  echo "   Linux: apt-get install qrencode"
fi

echo ""
echo "🚇 Share this QR code with your audience!"
