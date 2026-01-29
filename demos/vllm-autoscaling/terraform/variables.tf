variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "tube-demo"
}

variable "eks_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.8.1"
}

variable "cloudfront_vpc_origin_id" {
  description = "CloudFront VPC Origin ID (must be created manually via AWS CLI)"
  type        = string
  default     = ""
}
