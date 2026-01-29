resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}/api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}/frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "vllm" {
  name                 = "${var.project_name}/vllm"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

################################################################################
# ECR Pull Through Cache Rules
################################################################################

resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

output "ecr_repositories" {
  value = {
    api      = aws_ecr_repository.api.repository_url
    frontend = aws_ecr_repository.frontend.repository_url
    vllm     = aws_ecr_repository.vllm.repository_url
  }
}
