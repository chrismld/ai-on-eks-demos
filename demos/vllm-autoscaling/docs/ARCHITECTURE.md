# Architecture: GPU-Accelerated LLM Inference on EKS

## Overview

This project demonstrates production-ready LLM inference on Kubernetes with intelligent autoscaling. Audience members interact via a web UI, their requests flow through a FastAPI gateway to vLLM pods running on GPU Spot instances—orchestrated by Karpenter for node provisioning and KEDA for pod scaling.

The key insight: we scale on vLLM's request queue, not CPU metrics. This proactive approach scales capacity *before* latency degrades.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Audience + Load Generator                         │
│                     (QR Code → Mobile / k6 scripts)                     │
└─────────────────────────────────────────────────────────────────────────┘
                              │ HTTPS
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         CloudFront + ALB                                 │
└─────────────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│   Frontend (Next.js)     │    │   API Gateway (FastAPI)  │
│   - Quiz mode UI         │    │   - /v1/chat/completions │
│   - Survey mode UI       │    │   - Response storage (S3)│
└──────────────────────────┘    └─────────────┬────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        vLLM Inference Pods                               │
│   Model: Mistral 7B AWQ (4-bit quantized, streamed from S3)             │
│   Cold Start: ~90-120 seconds (SOCI + S3 streaming)                     │
│   Metrics: /metrics endpoint → KEDA scaling                             │
└─────────────────────────────────────────────────────────────────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│     KEDA      │    │   Karpenter   │    │      S3       │
│  Pod Scaling  │    │ Node Scaling  │    │ Model Storage │
│  (queue-based)│    │ (GPU Spot)    │    │ (streaming)   │
└───────────────┘    └───────────────┘    └───────────────┘
```

---

## Core Components

### vLLM: The Inference Engine

vLLM serves Mistral 7B with an OpenAI-compatible API. Key configuration:

```yaml
args:
  - "--model"
  - "s3://bucket/models/mistral-7b-awq/"
  - "--load-format"
  - "runai_streamer"      # Stream weights from S3
  - "--quantization"
  - "awq_marlin"          # 4-bit with Marlin kernels
  - "--max-model-len"
  - "4096"
  - "--max-num-seqs"
  - "32"                  # Concurrent requests per pod
```

**Why these choices:**
- `runai_streamer`: Streams model weights directly from S3 to GPU (~750 MiB/s)
- `awq_marlin`: 4-bit quantization with optimized kernels—near FP16 speed at 1/4 memory
- `max-num-seqs: 32`: Balance between throughput and latency

### Karpenter: Just-in-Time GPU Nodes

Karpenter provisions GPU nodes on-demand when vLLM pods can't be scheduled.

```yaml
requirements:
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot", "on-demand"]    # Prefer Spot (60-70% savings)
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["g", "p"]               # GPU families
- key: karpenter.k8s.aws/instance-gpu-manufacturer
  operator: In
  values: ["nvidia"]               # NVIDIA only
```

**EC2NodeClass with SOCI:**
```yaml
userData: |
  [settings.container-runtime]
  snapshotter = "soci"
  
  [settings.container-runtime-plugins.soci-snapshotter]
  pull-mode = "parallel-pull-unpack"
```

SOCI (Seekable OCI) enables lazy loading of container images—the 8-10GB vLLM image starts in ~30 seconds instead of 3-4 minutes.

### KEDA: Queue-Based Pod Scaling

KEDA scales vLLM pods based on request queue depth, not CPU:

```yaml
triggers:
- type: kedify-otel
  metadata:
    metricQuery: 'sum(vllm_num_requests_running)'
    targetValue: '25'
- type: kedify-otel
  metadata:
    metricQuery: 'sum(vllm_num_requests_waiting)'
    targetValue: '5'

advanced:
  scalingModifiers:
    formula: "running + (waiting * 10)"  # Weight queue heavily
    target: "25"
```

**Why queue-based?** CPU metrics are lagging indicators. By the time CPU spikes, users already experience latency. Queue depth is a *leading* indicator—scale before problems occur.

---

## Scaling Dynamics

### Timeline: Request Spike to Additional Capacity

```
T+0s     Request arrives, queue grows
T+2s     KEDA detects queue > threshold
T+3s     New vLLM pod created (Pending)
T+5s     Karpenter launches Spot instance
T+45s    Node ready, pod scheduled
T+80s    Container starts (SOCI), vLLM initializes
T+110s   Model streamed from S3, pod ready
T+120s   Serving requests
```

**Total: ~2 minutes** from queue spike to additional capacity.

### Scale-Up Configuration

```yaml
scaleUp:
  stabilizationWindowSeconds: 0   # No delay
  policies:
  - type: Percent
    value: 900                    # Allow 1→10 pods
    periodSeconds: 15
```

Aggressive scale-up is intentional—LLM queues build fast, and GPU nodes take time to provision.

---

## Storage Architecture

### Model Storage: S3 (Streaming)

```
S3 Bucket
└── models/
    └── mistral-7b-awq/
        ├── config.json
        ├── tokenizer.json
        └── model-*.safetensors (~4GB total)
```

vLLM streams weights directly from S3 using Run:ai Streamer. No local storage needed—the model loads in ~30 seconds at ~750 MiB/s.

### Response Storage: S3

Survey responses and question logs go to S3:
- Bucket: `{project_name}-responses-{account_id}`
- Simple, serverless, no database required

---

## Cost Optimization

| Strategy | Savings | Implementation |
|----------|---------|----------------|
| Spot Instances | 60-70% | NodePool allows spot + on-demand |
| AWQ Quantization | 75% memory | Fits on T4 instead of A10G |
| Scale to Zero | Variable | `minReplicaCount: 0` (dev only) |
| Fast Cold Starts | Indirect | SOCI + S3 streaming |

---

## Instance Types

Karpenter selects from available GPU instances:

| Instance | GPU | VRAM | Best For |
|----------|-----|------|----------|
| g4dn.xlarge | T4 | 16GB | Cost-optimized |
| g5.xlarge | A10G | 24GB | Better throughput |
| g6.xlarge | L4 | 24GB | Power efficient |
| p3.2xlarge | V100 | 16GB | High memory bandwidth |

The AWQ model (~4GB) fits comfortably on any of these with room for KV cache.

---

## Security

- vLLM pods run in private subnets
- ALB handles TLS termination
- IAM roles scoped to specific S3 buckets (Pod Identity)
- No HuggingFace tokens in production (model pre-uploaded to S3)

---

## Infrastructure Optimizations

These infrastructure choices enable the performance characteristics above:

| Component | Purpose | Impact |
|-----------|---------|--------|
| S3 Gateway Endpoint | Direct S3 access without NAT | ~750 MiB/s model streaming, $0 transfer cost |
| ECR Interface Endpoints | Private ECR access | Faster image pulls, no public internet |
| ECR Pull-Through Cache | Cache public images locally | Avoid rate limits during scale-out |
| EFS (torch.compile cache) | Shared compilation cache | Skip 60s compilation on subsequent pods |
| EKS Pod Identity | Pod-level IAM roles | Least-privilege S3 access, simpler than IRSA |

See [INFERENCE-ON-EKS.md](INFERENCE-ON-EKS.md#infrastructure-that-makes-this-possible) for detailed explanations.

---

## What This Proves

1. **Queue-based scaling works** for LLM inference
2. **Cold starts can be fast** (~2 min with SOCI + S3)
3. **Spot instances are viable** for inference workloads
4. **Karpenter + KEDA** is the right combination for GPU autoscaling

For deep dives into scaling configuration and optimization strategies, see [INFERENCE-ON-EKS.md](INFERENCE-ON-EKS.md).
