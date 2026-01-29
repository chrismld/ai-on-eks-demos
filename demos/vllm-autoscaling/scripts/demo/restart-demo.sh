#!/bin/bash
set -e

echo "🔄 Restarting demo to quiz mode..."

kubectl patch configmap api-config \
  -n default \
  --type merge \
  -p '{"data":{"DEMO_MODE":"quiz"}}'

echo "🔄 Restarting API..."
kubectl rollout restart deployment/api -n default

echo "⏳ Waiting for API to be ready..."
kubectl rollout status deployment/api -n default

echo "✅ Demo restarted in quiz mode"
echo ""
echo "💡 Refresh the frontend page to see the quiz"
echo "📋 When ready for survey: make enable-survey"

