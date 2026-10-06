output "alb_url" {
  description = "Application load balancer API URL."
  value       = "${var.acm_certificate_arn == "" ? "http" : "https"}://${aws_lb.main.dns_name}"
}

output "be_ecr_repository_url" {
  value = aws_ecr_repository.be.repository_url
}

output "ai_ecr_repository_url" {
  value = aws_ecr_repository.ai.repository_url
}

output "community_bucket_name" {
  value = aws_s3_bucket.community.id
}

output "web_bucket_name" {
  value = aws_s3_bucket.web.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.web.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.web.id
}

output "application_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}

output "github_deploy_role_arns" {
  value = {
    infra = aws_iam_role.github_infra.arn
    be    = aws_iam_role.github_deploy["be"].arn
    ai    = aws_iam_role.github_deploy["ai"].arn
    fe    = aws_iam_role.github_fe_deploy.arn
  }
}

