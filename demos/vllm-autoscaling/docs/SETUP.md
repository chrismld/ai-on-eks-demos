# Setup Guide

Deploy the complete LLM inference stack on EKS in ~30 minutes.

## Prerequisites

### AWS Account
- Permissions: EC2, EKS, IAM, S3, ECR
- Service quotas: At least 4 GPU instances (g4dn/g5) in your region
- Spot capacity available

### Local Tools

```bash
# macOS
brew install terraform kubectl aws-cli docker jq

# Verify
terraform --version    # >= 1.5
kubectl version        # >= 1.28
aws --version          # >= 2.0
```

### AWS Authentication

```bash
aws configure
aws sts get-caller-identity
```

---

## Quick Start

### 1. Configure (2 min)

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:
```hcl
region       = "us-west-2"      # Good Spot availability
project_name = "llm-inference"  # Unique name for resources
```

### 2. Deploy Infrastructure (20 min)

```bash
make setup-infra
```

Creates: VPC, EKS cluster, Karpenter, S3 bucket, ECR repositories, IAM roles.

### 3. Upload Model to S3 (5 min)

```bash
make setup-model-s3
```

Downloads Mistral 7B AWQ (~4GB) and uploads to S3.

### 4. Build and Push Images (5 min)

```bash
make build-push-images
```

Builds API and frontend containers, pushes to ECR.

### 5. Deploy Applications (5 min)

```bash
make deploy-apps
```

Deploys vLLM, API, frontend, and KEDA scaling.

### 6. Get the URL

```bash
make get-frontend-url
```

Open in browser to test.

---

## Running the Demo

```bash
# Start load test + dashboard
make run-demo

# Generate QR code for audience
make generate-qr

# Switch to survey mode
make enable-survey

# Pick winners
make pick-winners
```

---

## Cleanup

```bash
make teardown
```

Destroys all AWS resources.

---

## Command Reference

| Command | Description |
|---------|-------------|
| `make setup-infra` | Create EKS + Karpenter + S3 |
| `make setup-model-s3` | Upload model to S3 |
| `make build-push-images` | Build and push containers |
| `make deploy-apps` | Deploy all applications |
| `make get-frontend-url` | Get the demo URL |
| `make run-demo` | Start load test + dashboard |
| `make teardown` | Destroy everything |

---

## Troubleshooting

### vLLM pod stuck in Pending

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | tail -20

# Verify NodePool exists
kubectl get nodepool
```

Usually: Spot capacity unavailable. Try a different region or allow on-demand.

### vLLM fails to load model

```bash
# Check logs
kubectl logs deployment/vllm | grep -i error

# Verify S3 access
kubectl exec deployment/vllm -- aws s3 ls s3://YOUR_BUCKET/models/
```

Usually: IAM permissions. Check the vLLM service account has the correct role.

### KEDA not scaling

```bash
# Check ScaledObject
kubectl get scaledobject vllm-queue-scaler -o yaml

# Check OTel collector
kubectl logs -n keda -l app.kubernetes.io/name=scrape-vllm-collector
```

Usually: Metric name mismatch. vLLM uses colons (`vllm:num_requests_waiting`), KEDA expects underscores.

---

## Architecture Details

See [ARCHITECTURE.md](ARCHITECTURE.md) for component overview.
See [INFERENCE-ON-EKS.md](INFERENCE-ON-EKS.md) for scaling and optimization deep dive.
