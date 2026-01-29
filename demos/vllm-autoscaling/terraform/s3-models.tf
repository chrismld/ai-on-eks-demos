################################################################################
# S3 Bucket for Model Storage
################################################################################

resource "aws_s3_bucket" "models" {
  bucket = "${local.name}-models-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.tags, {
    Name = "${local.name}-models"
  })
}

resource "aws_s3_bucket_public_access_block" "models" {
  bucket = aws_s3_bucket.models.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "models" {
  bucket = aws_s3_bucket.models.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "models" {
  bucket = aws_s3_bucket.models.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

################################################################################
# EKS Pod Identity for vLLM S3 Access
################################################################################

# IAM Role for vLLM pods using Pod Identity
resource "aws_iam_role" "vllm_pod_identity" {
  name = "${local.name}-vllm-pod-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "vllm_s3_access" {
  name        = "${local.name}-vllm-s3-access"
  description = "Allow vLLM pods to read model weights from S3"

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

resource "aws_iam_role_policy_attachment" "vllm_s3_access" {
  role       = aws_iam_role.vllm_pod_identity.name
  policy_arn = aws_iam_policy.vllm_s3_access.arn
}

# Pod Identity Association - links the IAM role to the Kubernetes service account
resource "aws_eks_pod_identity_association" "vllm" {
  cluster_name    = module.eks.cluster_name
  namespace       = "default"
  service_account = "vllm"
  role_arn        = aws_iam_role.vllm_pod_identity.arn

  depends_on = [module.eks]
}

# Service account without IRSA annotation (Pod Identity doesn't need it)
resource "kubernetes_service_account" "vllm" {
  metadata {
    name      = "vllm"
    namespace = "default"
  }

  depends_on = [module.eks]
}

################################################################################
# Outputs
################################################################################

output "models_bucket_name" {
  description = "S3 bucket name for model storage"
  value       = aws_s3_bucket.models.id
}

output "models_bucket_arn" {
  description = "S3 bucket ARN for model storage"
  value       = aws_s3_bucket.models.arn
}

output "vllm_pod_identity_role_arn" {
  description = "IAM role ARN for vLLM Pod Identity"
  value       = aws_iam_role.vllm_pod_identity.arn
}
