# AI on EKS Demos

Production-ready patterns for running AI/ML workloads on Amazon EKS. Each demo provides battle-tested configurations, explains the *why* behind each decision, and includes everything you need to deploy and present.

## 🎯 Motivation

Running AI workloads on Kubernetes requires more than just deploying containers. You need to understand GPU scheduling, autoscaling based on the right metrics, cold start optimization, and cost management. These demos provide complete, working examples with detailed explanations of why each configuration choice matters.

## 📦 Available Demos

| Demo | Description | Key Technologies |
|------|-------------|------------------|
| [**vLLM Autoscaling**](demos/vllm-autoscaling/) | LLM inference with queue-based autoscaling | vLLM, KEDA, Karpenter, Kedify |
| **Ray Cluster** *(coming soon)* | Distributed ML training and serving | Ray, KubeRay, Karpenter |

## 🏗️ Demo Structure

Each demo follows a consistent structure:

```
demos/<demo-name>/
├── README.md           # Demo overview and quick start
├── docs/
│   ├── ARCHITECTURE.md # Deep dive into components
│   ├── SETUP.md        # Step-by-step deployment guide
│   └── *.md            # Additional guides
├── terraform/          # Infrastructure as code
├── kubernetes/         # Kubernetes manifests
├── app/                # Application code (if any)
└── scripts/            # Helper scripts
```

## 🚀 Quick Start

### Prerequisites

- AWS account with appropriate permissions
- Local tools: `terraform`, `kubectl`, `aws-cli`, `docker`
- GPU instance quota in your target region

### Deploy a Demo

```bash
# Clone the repository
git clone https://github.com/aws-samples/ai-on-eks-demos.git
cd ai-on-eks-demos

# Navigate to a demo
cd demos/vllm-autoscaling

# Follow the demo's README
cat README.md
```

## 📚 Demo Details

### vLLM Autoscaling

**What it demonstrates:**
- Queue-based pod autoscaling with KEDA (not CPU-based)
- Just-in-time GPU node provisioning with Karpenter
- Cold start optimization with SOCI and S3 model streaming
- Cost optimization with Spot instances and AWQ quantization

**Key insights:**
- Why `num_requests_waiting` is a better scaling signal than CPU utilization
- How to achieve ~2 minute cold starts for GPU workloads
- Scaling formula: `running + (waiting × 10)` for proactive scaling

**Architecture:**
```
Users → CloudFront → ALB → API Gateway → vLLM Pods (GPU)
                                              ↓
                              KEDA (queue metrics) + Karpenter (GPU nodes)
```

[**→ Go to vLLM Autoscaling Demo**](demos/vllm-autoscaling/)

---

### Ray Cluster *(Coming Soon)*

**What it will demonstrate:**
- Distributed training with Ray on EKS
- Autoscaling Ray workers with Karpenter
- GPU sharing and scheduling strategies
- Integration with MLflow for experiment tracking

---

## 🎓 Learning Resources

Each demo includes documentation suitable for:

- **Hands-on workshops** - Step-by-step deployment guides
- **Conference talks** - Architecture diagrams and narrative explanations
- **Team onboarding** - Best practices and configuration rationale

## 🛠️ Supported Versions

| Component | Version |
|-----------|---------|
| Kubernetes | 1.30+ |
| Karpenter | 1.0+ |
| KEDA | 2.14+ |
| Terraform | 1.5+ |
| vLLM | 0.6+ |

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

### Adding a New Demo

1. Create a new folder under `demos/`
2. Follow the standard demo structure
3. Include comprehensive documentation explaining *why*, not just *how*
4. Test the deployment end-to-end
5. Submit a PR with a description of the demo

## 📄 License

This project is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file for details.

## 🔗 Related Projects

- [Karpenter Blueprints](https://github.com/aws-samples/karpenter-blueprints) - Karpenter configuration patterns
- [EKS Blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints) - Terraform modules for EKS
- [Data on EKS](https://github.com/awslabs/data-on-eks) - Data workloads on EKS
- [Gen AI on EKS](https://github.com/aws-samples/gen-ai-on-eks) - Generative AI patterns

## ⭐ Star History

If you find these demos useful, please consider giving the repository a star!
