# CloudFront VPC Origin for internal ALB
# Note: VPC origins must be created via AWS CLI first
# The VPC Origin ID is passed via variable

data "aws_lb" "frontend_alb" {
  tags = {
    "elbv2.k8s.aws/cluster"    = module.eks.cluster_name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "default/frontend"
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# CloudFront cache policy - Disabled for demo (always fetch from origin)
resource "aws_cloudfront_cache_policy" "frontend" {
  name        = "${local.name}-frontend-cache-policy"
  comment     = "No caching - always fetch from origin for demo"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}

# CloudFront origin request policy
resource "aws_cloudfront_origin_request_policy" "frontend" {
  name    = "${local.name}-frontend-origin-policy"
  comment = "Origin request policy for frontend application"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allViewer"
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# CloudFront Distribution with VPC Origin
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${local.name} frontend"
  default_root_object = ""
  price_class         = "PriceClass_100"

  origin {
    domain_name = data.aws_lb.frontend_alb.dns_name
    origin_id   = "vpc-origin"

    vpc_origin_config {
      vpc_origin_id            = var.cloudfront_vpc_origin_id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  default_cache_behavior {
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "vpc-origin"
    cache_policy_id          = aws_cloudfront_cache_policy.frontend.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.frontend.id
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
  }

  # API path should not be cached
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "vpc-origin"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = false
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # Managed-AllViewer
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

# WAF Web ACL (optional)
resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "${local.name}-cloudfront-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitRule"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRuleMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}
