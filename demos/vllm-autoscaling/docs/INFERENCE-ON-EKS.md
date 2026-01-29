# Self-Managed LLM Inference on EKS: A Practitioner's Guide

## Purpose

You've decided to run your own LLM inference on Kubernetes. Maybe you need data sovereignty, custom models, or just want to avoid per-token pricing at scale. Whatever the reason, you're now facing the same challenges every team encounters: GPU costs, cold starts, and autoscaling that actually works.

This guide shares what we learned building a production-ready inference platform on EKS. We'll skip the basics—you already know what KEDA and Karpenter do. Instead, we'll focus on the decisions that matter: why queue-based metrics beat CPU utilization, how to get cold starts under 2 minutes, and the configuration choices that make or break your scaling behavior.

---

## Why Queue-Based Scaling Changes Everything

Here's the uncomfortable truth about LLM inference: traditional autoscaling doesn't work.

CPU and memory metrics are lagging indicators. By the time CPU spikes, your users have already experienced latency. Worse, GPU inference workloads often show low CPU utilization even when completely saturated—the bottleneck is the GPU, not the CPU.

**The insight:** vLLM exposes `num_requests_waiting`—the number of requests queued for processing. This is a *leading* indicator. When the queue grows, latency is *about* to spike. Scale now, not after users complain.

```
Traditional HPA:                    Queue-Based Scaling:
                                    
Request → Process → CPU spike       Request → Queue grows → Scale
                ↓                                    ↓
         Scale decision              Scale decision (proactive)
                ↓                                    ↓
         New pod (too late)          New pod (before latency degrades)
```

### The Metrics That Matter

vLLM exposes several metrics at `/metrics`. Here's what to watch:

| Metric | What It Tells You | Scaling Signal? |
|--------|-------------------|-----------------|
| `vllm:num_requests_waiting` | Requests queued for processing | ✅ Primary |
| `vllm:num_requests_running` | Requests currently being processed | ✅ Secondary |
| `vllm:gpu_cache_usage_perc` | KV cache utilization | ⚠️ Capacity limit |
| `vllm:avg_generation_throughput_toks_per_s` | Tokens generated per second | 📊 Monitoring |

**Why both waiting AND running?** A pod can be "busy" (high running count) without a queue. That's fine—it's handling load efficiently. But when requests start *waiting*, you're falling behind. The combination tells the full story.

### KEDA Configuration Deep Dive

Here's our ScaledObject with annotations explaining each choice:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: vllm-queue-scaler
spec:
  scaleTargetRef:
    name: vllm
  minReplicaCount: 1          # Keep one warm pod (adjust for cost vs latency)
  maxReplicaCount: 10         # Match your GPU budget
  pollingInterval: 2          # Check every 2s—LLM queues build fast
  cooldownPeriod: 300         # 5 min cooldown prevents thrashing
  
  triggers:
  - type: kedify-otel
    name: running
    metadata:
      metricQuery: 'sum(vllm_num_requests_running)'
      targetValue: '25'       # Each pod handles ~32 concurrent, target 25 for headroom
  
  - type: kedify-otel
    name: waiting
    metadata:
      metricQuery: 'sum(vllm_num_requests_waiting)'
      targetValue: '5'        # Scale when 5+ requests waiting
  
  advanced:
    scalingModifiers:
      # Weight queue buildup heavily: running + (waiting * 10)
      formula: "running + (waiting * 10)"
      target: "25"
      activationTarget: "5"   # Don't scale from zero until combined > 5
```

**Why the formula?** A single waiting request might be a blip. But `waiting * 10` means even a small queue triggers aggressive scaling. This is intentional—for LLM inference, queue depth is the enemy.

**Why `pollingInterval: 2`?** LLM requests take seconds to complete. A 30-second polling interval (the default) means you could have 15+ requests queued before KEDA even notices. Two seconds keeps you responsive.

**Why `cooldownPeriod: 300`?** GPU nodes are expensive. You don't want to scale down, then immediately scale back up. Five minutes of quiet before scaling down prevents thrashing.

### Scale-Up Behavior

The HPA behavior configuration is where most teams get it wrong:

```yaml
horizontalPodAutoscalerConfig:
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0   # No delay—scale immediately
      policies:
      - type: Percent
        value: 900                    # Allow 900% increase
        periodSeconds: 15
      - type: Pods
        value: 9                      # Or add up to 9 pods
        periodSeconds: 15
      selectPolicy: Max               # Use whichever allows more scaling
```

**Why 900%?** If you have 1 pod and suddenly need 10, you want to get there fast. The default HPA behavior limits scale-up to 100% (doubling), which means 1→2→4→8→10 over multiple periods. That's too slow for bursty LLM traffic.

**Why `selectPolicy: Max`?** With both Percent and Pods policies, Kubernetes picks the one that allows *more* scaling. This ensures you can go from 1 to 10 pods in a single scaling decision if needed.

---

## Cold Start Optimization: The 2-Minute Target

Cold starts are the Achilles' heel of GPU autoscaling. Here's the breakdown of where time goes:

```
Standard Cold Start (~6-8 minutes):
├── Karpenter provisions node      ~45s
├── Container image pull           ~3-4 min  ← Biggest problem
├── vLLM initialization            ~30s
└── Model loading                  ~2-3 min  ← Second biggest problem

Optimized Cold Start (~90-120 seconds):
├── Karpenter provisions node      ~45s
├── Container image (SOCI)         ~30s      ← Lazy loading
├── vLLM initialization            ~30s
└── Model streaming (S3)           ~30s      ← Concurrent streaming
```

### Strategy 1: SOCI for Container Images

[Seekable OCI (SOCI)](https://github.com/awslabs/soci-snapshotter) enables lazy loading of container images. Instead of pulling the entire 8-10GB vLLM image before starting, SOCI pulls only the layers needed to start the container, fetching the rest in the background.

**Bottlerocket configuration:**

```yaml
# EC2NodeClass userData
[settings.container-runtime]
snapshotter = "soci"

[settings.container-runtime-plugins.soci-snapshotter]
pull-mode = "parallel-pull-unpack"

[settings.container-runtime-plugins.soci-snapshotter.parallel-pull-unpack]
max-concurrent-downloads-per-image = 20
concurrent-download-chunk-size = "16mb"
max-concurrent-unpacks-per-image = 12
discard-unpacked-layers = true
```

**Why these settings?**
- `parallel-pull-unpack`: Download and unpack layers concurrently
- `max-concurrent-downloads: 20`: Saturate network bandwidth
- `chunk-size: 16mb`: Balance between parallelism and overhead
- `discard-unpacked-layers: true`: Save disk space after unpacking

**Result:** Container "pull" drops from 3-4 minutes to ~30 seconds.

### Strategy 2: S3 Model Streaming

Traditional model loading downloads the entire model to disk, then loads it into GPU memory. vLLM's Run:ai Streamer integration streams weights directly from S3 to GPU memory concurrently.

```yaml
# vLLM deployment args
args:
  - "--model"
  - "s3://your-bucket/models/mistral-7b-awq/"
  - "--load-format"
  - "runai_streamer"    # Enable S3 streaming
  - "--quantization"
  - "awq_marlin"        # Use Marlin kernels for AWQ
```

**Why AWQ quantization?**
- 4-bit quantized model: ~4GB vs ~14GB for float16
- Fits on T4 GPU (16GB VRAM) with room for KV cache
- Marlin kernels provide near-full-precision inference speed
- Faster to stream, faster to load

**S3 performance:** With proper IAM and VPC endpoints, expect ~750 MiB/s streaming speed. A 4GB model loads in ~5 seconds.

### Strategy 3: Probe Configuration

Misconfigured probes are a silent killer. Too aggressive, and Kubernetes kills pods that are still loading. Too conservative, and you wait minutes for a ready pod.

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 30     # Skip first 30s (node setup)
  periodSeconds: 10           # Check every 10s
  failureThreshold: 30        # Allow up to 330s total startup

readinessProbe:
  httpGet:
    path: /v1/models
    port: 8000
  periodSeconds: 5            # Quick detection once ready
  failureThreshold: 3
```

**Why `/health` for startup but `/v1/models` for readiness?** The `/health` endpoint returns 200 as soon as the server starts. The `/v1/models` endpoint only succeeds after the model is loaded and ready to serve. This distinction matters—you want to know the pod is *alive* (startup) vs *ready to serve traffic* (readiness).

---

## Infrastructure That Makes This Possible

The Kubernetes and application configurations above only work well when the underlying infrastructure is optimized for AI workloads. Here's what matters and why.

### VPC Endpoints: Eliminating the NAT Gateway Bottleneck

When vLLM streams a 4GB model from S3, that traffic has to go somewhere. Without VPC endpoints, it routes through your NAT Gateway—which has bandwidth limits and per-GB charges.

```hcl
# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}
```

**Why this matters:**
- **Throughput:** S3 Gateway endpoints provide direct access to S3 at full network speed. We measured ~750 MiB/s model streaming—that's 4GB in ~5 seconds.
- **Cost:** NAT Gateway charges $0.045/GB processed. Streaming a 4GB model 100 times = $18. With the S3 endpoint: $0.
- **Latency:** Direct path to S3 vs routing through NAT adds milliseconds that compound during model loading.

### ECR Endpoints: Faster Container Pulls

The vLLM container image is 8-10GB. Even with SOCI lazy loading, you're still pulling significant data from ECR.

```hcl
# ECR API + DKR Interface Endpoints
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
}
```

**Why both endpoints?**
- `ecr.api`: Handles authentication and image manifest requests
- `ecr.dkr`: Handles the actual layer blob downloads

Without these, every container pull goes through the public internet, adding latency and potential bandwidth constraints.

### ECR Pull-Through Cache: One-Time Downloads

When Karpenter provisions a new node, it needs to pull container images. If you're using public images (like the vLLM base image from public ECR), every node pulls from the public registry.

```hcl
resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}
```

**How it works:**
1. First node requests `public.ecr.aws/vllm/vllm-openai:latest`
2. ECR caches the image in your private registry as `ecr-public/vllm/vllm-openai:latest`
3. Subsequent nodes pull from your private ECR (faster, no rate limits)

**Why this matters for autoscaling:** When you scale from 1 to 10 pods, you might provision 9 new nodes simultaneously. Without caching, all 9 hit the public registry at once—potentially hitting rate limits or experiencing slower pulls.

### EFS for torch.compile Cache: Amortizing Compilation Cost

vLLM uses PyTorch's `torch.compile` for optimized inference. The first time a model runs, PyTorch compiles optimized CUDA kernels—this takes 30-60 seconds.

```hcl
resource "aws_efs_file_system" "torch_cache" {
  creation_token   = "${local.name}-torch-cache"
  encrypted        = true
  throughput_mode  = "elastic"  # Auto-scales throughput
}
```

**Why EFS instead of local storage?**
- **Shared cache:** When pod 2 starts, it finds the compiled kernels from pod 1 already cached
- **Survives restarts:** Compiled kernels persist across pod restarts and node replacements
- **Elastic throughput:** EFS scales throughput automatically—no provisioning needed

**The math:** First pod startup includes ~60s of compilation. With shared EFS cache, subsequent pods skip this entirely. At scale, this saves minutes of cumulative startup time.

```yaml
# vLLM deployment volume mount
volumeMounts:
  - name: torch-cache
    mountPath: /root/.cache/vllm/torch_compile_cache
```

### EKS Pod Identity: Secure S3 Access

vLLM pods need to read model weights from S3. You could use node-level IAM roles, but that grants access to every pod on the node.

```hcl
# IAM Role with Pod Identity trust policy
resource "aws_iam_role" "vllm_pod_identity" {
  name = "${local.name}-vllm-pod-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Associate the role with the service account
resource "aws_eks_pod_identity_association" "vllm" {
  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "vllm"
  role_arn        = aws_iam_role.vllm_pod_identity.arn
}
```

**Why Pod Identity over IRSA?**
- **Simpler setup:** No OIDC provider configuration needed
- **Cleaner service accounts:** No annotations required on the Kubernetes service account
- **AWS-managed:** EKS handles the credential injection automatically
- **Same security model:** Least-privilege, pod-level IAM roles with full CloudTrail audit

### Putting It Together: The Data Flow

Here's how data flows during a cold start with all optimizations:

```
1. Karpenter launches GPU instance
   └── Instance profile grants ECR + S3 access

2. Kubelet pulls vLLM image
   └── ECR pull-through cache → ECR Interface Endpoint → Node
   └── SOCI lazy loads only needed layers (~30s vs 3-4 min)

3. vLLM pod starts
   └── Mounts EFS for torch.compile cache
   └── Checks cache → finds compiled kernels (skip 60s compilation)

4. vLLM loads model
   └── S3 Gateway Endpoint → Direct to S3 (~750 MiB/s)
   └── Run:ai Streamer loads directly to GPU memory

5. Pod ready to serve (~2 min total)
```

Without these optimizations, the same flow takes 6-8 minutes and costs more in NAT Gateway fees.

---

## Karpenter GPU NodePool Best Practices

### Instance Selection

```yaml
requirements:
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot", "on-demand"]

- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["g", "p"]              # GPU instance families

- key: karpenter.k8s.aws/instance-gpu-manufacturer
  operator: In
  values: ["nvidia"]              # NVIDIA only (excludes AMD)

- key: karpenter.k8s.aws/instance-size
  operator: NotIn
  values: ["metal"]               # Exclude bare metal (slow provisioning)
```

**Why allow both `g` and `p` families?** Spot availability varies. Allowing g4dn, g5, g6, p3, and p4 instances gives Karpenter more options to find capacity. The tradeoff: you need to handle different GPU memory sizes in your deployment.

**Why exclude metal instances?** Bare metal instances take 5-10 minutes to provision vs ~45 seconds for virtualized. Not worth it for autoscaling.

### GPU Taints

```yaml
taints:
- key: nvidia.com/gpu
  effect: NoSchedule
```

**Why taint GPU nodes?** Without taints, Kubernetes might schedule non-GPU workloads on expensive GPU nodes. The taint ensures only pods that explicitly tolerate GPUs land on these nodes.

### Consolidation Policy

```yaml
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 30s
```

**Why `WhenEmpty` instead of `WhenUnderutilized`?** GPU workloads are binary—either you need the GPU or you don't. "Underutilized" doesn't make sense when a single vLLM pod consumes the entire GPU. `WhenEmpty` means Karpenter only removes nodes with no pods, which is the right behavior.

**Why 30 seconds?** Quick consolidation saves money. If a pod moves or terminates, you don't want to pay for an empty GPU node for minutes.

---

## Cost Optimization Strategies

### 1. Spot Instances (60-70% Savings)

GPU Spot instances offer massive savings, but require handling interruptions:

```yaml
# NodePool allows both Spot and on-demand
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot", "on-demand"]
```

**Spot interruption handling:**
- Karpenter automatically drains nodes on interruption notice
- Pods reschedule to new nodes (Spot or on-demand)
- Model weights persist in S3—no data loss
- KEDA maintains desired replica count

**Tip:** Diversify instance types. More options = better Spot availability.

### 2. Scale to Zero (When Appropriate)

```yaml
minReplicaCount: 0  # Allow scale to zero
```

**When to use:** Development environments, batch processing, or workloads with predictable idle periods.

**When NOT to use:** Production APIs where cold start latency matters. Keep `minReplicaCount: 1` for always-warm capacity.

### 3. Right-Size Your Model

| Model Size | GPU Requirement | Use Case |
|------------|-----------------|----------|
| 7B (AWQ) | T4 (16GB) | Cost-optimized, good quality |
| 7B (FP16) | A10G (24GB) | Better quality, higher cost |
| 13B (AWQ) | A10G (24GB) | Better reasoning |
| 70B (AWQ) | A100 (40GB) | Best quality, highest cost |

**Our choice:** Mistral 7B AWQ on T4/A10G. The 4-bit quantization has minimal quality impact for most use cases, and the cost savings are substantial.

---

## The Scaling Timeline

When load increases, here's what happens:

```
T+0s     Request arrives, queue depth increases
T+2s     KEDA polls metrics, detects queue > threshold
T+3s     KEDA creates new pod (Pending)
T+4s     Karpenter detects unschedulable pod
T+5s     Karpenter launches Spot instance request
T+45s    Node ready, joins cluster
T+50s    Pod scheduled, container starts (SOCI)
T+80s    vLLM starts, streams model from S3
T+110s   Model loaded, pod ready
T+120s   Pod serving requests
```

**Total: ~2 minutes from queue spike to additional capacity.**

For comparison, without optimization: 6-8 minutes. That's the difference between "users notice a brief slowdown" and "users give up and leave."

---

## Monitoring and Observability

### Essential Dashboards

1. **Scaling Dashboard**
   - Queue depth over time
   - Replica count over time
   - Overlay to see correlation

2. **Latency Dashboard**
   - P50/P95/P99 response times
   - Time to first token
   - Tokens per second

3. **Cost Dashboard**
   - GPU node hours by instance type
   - Spot vs on-demand ratio
   - Cost per request

### Alerting Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Queue depth | > 10 for 1 min | > 50 for 1 min |
| P99 latency | > 10s | > 30s |
| GPU memory | > 90% | > 95% |
| Failed requests | > 1% | > 5% |

---

## Common Pitfalls

### 1. Polling Interval Too Long

**Symptom:** Queue builds up before scaling kicks in.
**Fix:** Set `pollingInterval: 2` or lower.

### 2. Scale-Up Too Conservative

**Symptom:** Scaling happens but too slowly.
**Fix:** Increase `scaleUp.policies` values, set `stabilizationWindowSeconds: 0`.

### 3. Cooldown Too Short

**Symptom:** Pods scale down, then immediately scale back up.
**Fix:** Increase `cooldownPeriod` to 300s or more.

### 4. Missing GPU Taints

**Symptom:** Non-GPU pods scheduled on GPU nodes.
**Fix:** Add `nvidia.com/gpu` taint to NodePool.

### 5. Probes Too Aggressive

**Symptom:** Pods killed during model loading.
**Fix:** Increase `startupProbe.failureThreshold`, use appropriate `initialDelaySeconds`.

---

## References

- [vLLM Documentation](https://docs.vllm.ai/)
- [KEDA Scaling Documentation](https://keda.sh/docs/)
- [Karpenter Best Practices](https://karpenter.sh/docs/best-practices/)
- [AWS SOCI Snapshotter](https://github.com/awslabs/soci-snapshotter)
- [Run:ai Model Streamer](https://github.com/run-ai/runai-model-streamer)
- [Kedify OTEL Scaler](https://kedify.io/scalers/otel)

---

## What This Proves

1. **LLM inference scales on Kubernetes** with the right metrics
2. **Cold starts can be fast** (~2 min with SOCI + S3 streaming)
3. **Spot instances work** for inference (with proper interruption handling)
4. **Queue-based scaling beats CPU/memory** every time
5. **Karpenter + KEDA** is the right combination for GPU workloads

The patterns here aren't just for demos—this is how you run production inference at scale.
