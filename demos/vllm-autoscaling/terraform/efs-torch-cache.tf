# EFS for torch.compile cache - shared across all vLLM pods
# This dramatically reduces cold start time by caching compiled graphs

################################################################################
# EFS Filesystem
################################################################################

resource "aws_efs_file_system" "torch_cache" {
  creation_token = "${local.name}-torch-cache"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"  # Auto-scales throughput

  tags = merge(local.tags, {
    Name = "${local.name}-torch-cache"
  })
}

resource "aws_efs_mount_target" "torch_cache" {
  for_each = toset(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.torch_cache.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_torch_cache.id]
}

################################################################################
# Security Group for EFS
################################################################################

resource "aws_security_group" "efs_torch_cache" {
  name        = "${local.name}-efs-torch-cache"
  description = "Security group for EFS torch.compile cache"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "NFS from EKS nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name}-efs-torch-cache"
  })
}

################################################################################
# Outputs
################################################################################

output "efs_torch_cache_id" {
  description = "EFS filesystem ID for torch.compile cache"
  value       = aws_efs_file_system.torch_cache.id
}
