.PHONY: setup-infra build-push-images deploy-apps setup-cloudfront run-demo dashboard dashboard-right restart-demo enable-survey pick-winners teardown get-frontend-url generate-qr setup-model-s3 load-test load-test-cleanup update-manifests help

# Ensure /usr/local/bin is in PATH for kubectl and aws
export PATH := /usr/local/bin:$(PATH)

help:
	@echo "🚇 AI Workloads Tube Demo - Available targets"
	@echo ""
	@echo "  make setup-infra         Create EKS cluster, Karpenter, S3 bucket"
	@echo "  make setup-model-s3      Upload model weights to S3"
	@echo "  make build-push-images   Build multi-arch images and push to ECR"
	@echo "  make update-manifests    Regenerate Kubernetes manifests from templates"
	@echo "  make deploy-apps         Deploy vLLM, API, frontend with KEDA"
	@echo "  make setup-cloudfront    Configure CloudFront with internal ALB (optional)"
	@echo "  make get-frontend-url    Get the frontend URL (ALB or CloudFront)"
	@echo "  make generate-qr         Generate QR code for audience"
	@echo "  make run-demo            Start load test and terminal dashboard"
	@echo "  make load-test           Run k6 load test (cleanup + start)"
	@echo "  make load-test-cleanup   Cleanup k6 load test job"
	@echo "  make dashboard           Start terminal dashboard"
	@echo "  make dashboard-right     Start right panel (pods & nodes detail)"
	@echo "  make restart-demo        Restart demo to quiz mode"
	@echo "  make enable-survey       Switch to survey mode (auto-archives previous)"
	@echo "  make pick-winners        Draw 2 random winners"
	@echo "  make teardown            Destroy all AWS resources"
	@echo ""

setup-infra:
	@echo "📦 Setting up EKS infrastructure..."
	@echo ""
	@echo "This will create:"
	@echo "  - VPC and networking"
	@echo "  - EKS cluster with Karpenter"
	@echo "  - S3 bucket for model storage"
	@echo "  - ECR repositories"
	@echo ""
	@echo "Deploying Terraform infrastructure..."
	cd terraform && terraform init
	cd terraform && terraform apply -auto-approve
	@echo ""
	@echo "✅ Infrastructure ready!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. make setup-model-s3    # Upload model to S3"
	@echo "  2. make build-push-images # Build containers"
	@echo "  3. make deploy-apps       # Deploy everything"

setup-model-s3:
	@echo "📦 Uploading model to S3..."
	@echo ""
	@echo "This will:"
	@echo "  1. Download model from HuggingFace (~4GB)"
	@echo "  2. Upload to S3 bucket"
	@echo ""
	bash scripts/setup/setup-model-s3.sh
	@echo ""
	@echo "📝 Updating vLLM deployment with S3 path..."
	bash scripts/setup/update-manifests.sh

update-manifests:
	@echo "📝 Updating Kubernetes manifests from templates..."
	bash scripts/setup/update-manifests.sh

build-push-images:
	@echo "🔨 Building and pushing images..."
	bash scripts/setup/build-images.sh
	bash scripts/setup/update-manifests.sh

deploy-apps:
	@echo "🚀 Deploying applications..."
	@echo ""
	@echo "Note: Model weights are streamed from S3 (no EFS needed)"
	@echo "      Make sure you've run 'make setup-model-s3' first"
	@echo ""
	kubectl apply -k kubernetes/
	@echo ""
	@echo "🎉 Deployment complete!"
	@echo ""
	@echo "Watch vLLM startup:"
	@echo "  kubectl logs -f deployment/vllm"

setup-cloudfront:
	@echo "☁️  Setting up CloudFront with VPC Origin..."
	@if ! grep -q "cloudfront_vpc_origin_id" terraform/terraform.tfvars || grep -q '^# cloudfront_vpc_origin_id' terraform/terraform.tfvars; then \
		echo "❌ Error: VPC Origin ID not set in terraform.tfvars"; \
		echo "   Run: bash scripts/setup/setup-vpc-origin.sh first"; \
		exit 1; \
	fi
	cd terraform && terraform apply \
		-target=aws_cloudfront_cache_policy.frontend \
		-target=aws_cloudfront_origin_request_policy.frontend \
		-target=aws_cloudfront_distribution.frontend \
		-target=aws_wafv2_web_acl.cloudfront \
		-auto-approve
	@echo "✅ CloudFront setup complete!"
	@echo ""
	@echo "📋 CloudFront URL:"
	@cd terraform && terraform output cloudfront_url
	@echo ""
	@echo "💡 Your internal ALB is now accessible via CloudFront"

get-frontend-url:
	@echo "🔍 Getting frontend URL..."
	bash scripts/demo/get-frontend-url.sh

generate-qr:
	@echo "📱 Generating QR code..."
	bash scripts/demo/generate-qr.sh

load-test:
	@echo "🔥 Running k6 load test..."
	bash scripts/demo/run-load-test.sh --watch

run-demo:
	@echo "🎬 Starting demo..."
	bash scripts/demo/run-demo.sh

load-test-cleanup:
	@echo "🧹 Cleaning up k6 load test..."
	bash scripts/demo/run-load-test.sh --cleanup-only

dashboard:
	@echo "📊 Starting terminal dashboard..."
	bash scripts/dashboard/demo-dashboard.sh

dashboard-right:
	@echo "📊 Starting right panel dashboard (pods & nodes)..."
	bash scripts/dashboard/demo-dashboard-right.sh

restart-demo:
	@echo "🔄 Restarting demo to quiz mode..."
	bash scripts/demo/restart-demo.sh

enable-survey:
	@echo "📝 Switching to survey mode..."
	bash scripts/survey/enable-survey.sh

pick-winners:
	@echo "🎁 Drawing winners..."
	bash scripts/survey/pick-winners.sh

teardown:
	@echo "💥 Destroying everything..."
	bash scripts/setup/teardown.sh
	cd terraform && terraform destroy -auto-approve
