output "alb_url" {
  description = "Initial HTTP API URL. Add ACM and HTTPS before public production use."
  value       = "http://${aws_lb.main.dns_name}"
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

output "application_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

