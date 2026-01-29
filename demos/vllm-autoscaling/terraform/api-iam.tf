# IAM role for API pod to access S3
module "api_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-api-irsa"

  role_policy_arns = {
    s3_access = aws_iam_policy.api_s3_access.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:api"]
    }
  }

  tags = local.tags
}

# IAM policy for S3 bucket access
resource "aws_iam_policy" "api_s3_access" {
  name        = "${local.name}-api-s3-access"
  description = "Allow API pod to access S3 buckets for questions and survey responses"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-questions-*",
          "arn:aws:s3:::${var.project_name}-questions-*/*",
          "arn:aws:s3:::${var.project_name}-responses-*",
          "arn:aws:s3:::${var.project_name}-responses-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:PutPublicAccessBlock"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-questions-*",
          "arn:aws:s3:::${var.project_name}-responses-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

# Kubernetes ServiceAccount for API
resource "kubernetes_service_account" "api" {
  metadata {
    name      = "api"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.api_irsa.iam_role_arn
    }
  }

  depends_on = [module.eks]
}
