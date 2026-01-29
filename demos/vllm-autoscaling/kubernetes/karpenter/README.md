# Karpenter NodePools

This directory contains Karpenter NodePool and NodeClass configurations for GPU workloads.

## Default NodePool

The default NodePool is managed by Terraform and provisions general-purpose compute nodes:
- **Intent**: `apps` (API, frontend, general workloads)
- **Architecture**: amd64
- **Capacity**: On-demand
- **Instance Types**: c, m, r families (generation > 2)
- **Consolidation**: WhenEmpty after 1 minute

## GPU NodePool

The GPU NodePool is defined here for inference workloads:
- **Intent**: `inference` (vLLM pods)
- **Architecture**: amd64
- **Capacity**: Spot instances
- **Instance Types**: g5.2xlarge, g5.4xlarge, g5.12xlarge
- **Consolidation**: WhenUnderutilized after 30 seconds
- **Disruption Budget**: 0% during active scaling (1 minute)

## Applying NodePools

NodePools are applied via kustomize:

```bash
kubectl apply -k kubernetes/
```

## Customizing NodePools

To add more NodePools:

1. Create a new NodeClass YAML (if needed)
2. Create a new NodePool YAML
3. Add both to `kubernetes/kustomization.yaml`

Example for CPU-optimized workloads:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: cpu-optimized
spec:
  template:
    metadata:
      labels:
        workload: compute
    spec:
      requirements:
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["c"]
      nodeClassRef:
        name: default
```

## Node Selectors

Pods must use the correct node selector to land on the right NodePool:

- **Default NodePool**: `intent: apps`
- **GPU NodePool**: `workload: inference`

See deployment manifests in `kubernetes/api/`, `kubernetes/frontend/`, and `kubernetes/vllm/` for examples.
