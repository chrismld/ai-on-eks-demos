locals {
  karpenter_namespace = "karpenter"
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.3.2"

  cluster_name = module.eks.cluster_name
  namespace    = local.karpenter_namespace

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ECRPullThroughCache          = aws_iam_policy.ecr_pull_through_cache.arn
    S3ModelsReadOnly             = aws_iam_policy.s3_models_read.arn
  }

  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name
  create_pod_identity_association = true

  tags = local.tags
}

# IAM policy for S3 model access
# Nodes need read access to stream model weights from S3
resource "aws_iam_policy" "s3_models_read" {
  name        = "${local.name}-s3-models-read"
  description = "Allow EKS nodes to read model weights from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.models.arn,
          "${aws_s3_bucket.models.arn}/*"
        ]
      }
    ]
  })

  tags = local.tags
}

# IAM policy for ECR pull-through cache
# Nodes need these permissions to create cached repositories on first pull
resource "aws_iam_policy" "ecr_pull_through_cache" {
  name        = "${local.name}-ecr-pull-through-cache"
  description = "Allow EKS nodes to use ECR pull-through cache"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:BatchImportUpstreamImage"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = local.karpenter_namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  wait             = false

  values = [<<-EOT
    nodeSelector:
      CriticalAddonsOnly: 'true'
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    webhook:
      enabled: false
  EOT
  ]

  lifecycle {
    ignore_changes = [repository_password]
  }

  depends_on = [helm_release.aws_load_balancer_controller, helm_release.metrics_server]
}

# Default NodeClass
resource "kubectl_manifest" "karpenter_default_nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: "${module.karpenter.node_iam_role_name}"
      amiSelectorTerms:
      - alias: bottlerocket@1.50.0
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML

  depends_on = [helm_release.karpenter]
}

# Default NodePool
resource "kubectl_manifest" "karpenter_default_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        metadata:
          labels:
            intent: apps
        spec:
          requirements:
          - key: intent
            operator: In
            values: ["apps"]
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64","arm64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          - key: karpenter.k8s.aws/instance-category
            operator: In
            values: ["c", "m", "r"]
          - key: karpenter.k8s.aws/instance-generation
            operator: Gt
            values: ["2"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
      expireAfter: 720h
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 1m
  YAML

  depends_on = [kubectl_manifest.karpenter_default_nodeclass]
}
