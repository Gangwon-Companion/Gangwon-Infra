variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Prefix used for resource names."
  type        = string
  default     = "gangwon-companion"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "prod"
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "gangwon"
}

variable "db_username" {
  description = "RDS master username. The password is generated and managed by RDS in Secrets Manager."
  type        = string
  default     = "gangwon_admin"
}

variable "db_instance_class" {
  description = "Small initial RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "be_image_tag" {
  description = "BE ECR image tag deployed by ECS."
  type        = string
  default     = "latest"
}

variable "ai_image_tag" {
  description = "AI ECR image tag deployed by ECS."
  type        = string
  default     = "latest"
}

variable "ecs_desired_count" {
  description = "Keep at zero until both images and the application secret value exist."
  type        = number
  default     = 0

  validation {
    condition     = var.ecs_desired_count >= 0 && var.ecs_desired_count <= 2
    error_message = "ecs_desired_count must be between 0 and 2 for the initial deployment."
  }
}

