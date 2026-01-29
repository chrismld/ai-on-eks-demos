################################################################################
# VPC Endpoints
################################################################################

# S3 Gateway Endpoint - provides high-throughput access to S3 without NAT Gateway
# This significantly improves model download speeds (from ~880 MiB/s to 1.5+ GiB/s)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = module.vpc.private_route_table_ids

  tags = merge(local.tags, {
    Name = "${local.name}-s3-endpoint"
  })
}

# ECR API Interface Endpoint - improves container image pull performance
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.tags, {
    Name = "${local.name}-ecr-api-endpoint"
  })
}

# ECR DKR Interface Endpoint - for Docker registry operations
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = merge(local.tags, {
    Name = "${local.name}-ecr-dkr-endpoint"
  })
}

# Security group for VPC Interface Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name}-vpc-endpoints-sg"
  })
}
