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

variable "aws_account_id" {
  description = "AWS account ID verified before deployment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain exactly 12 digits."
  }
}

variable "availability_zones" {
  description = "Two availability zones used by public and database subnets."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must contain exactly two zones."
  }
}

variable "acm_certificate_arn" {
  description = "Optional ACM certificate ARN. When set, the ALB redirects HTTP to HTTPS."
  type        = string
  default     = ""
}

variable "cors_allowed_origin_patterns" {
  description = "Comma-separated browser origins accepted by the backend."
  type        = string
  default     = "http://localhost:*,http://127.0.0.1:*,http://10.0.2.2:*"
}

variable "spring_jpa_ddl_auto" {
  description = "Hibernate schema action for the initial deployment. Set to validate after adopting migrations."
  type        = string
  default     = "update"
}

variable "ai_response_llm_enabled" {
  description = "Enable OpenAI-backed AI response rendering. Requires OPENAI_API_KEY in the application secret."
  type        = bool
  default     = false
}

variable "ai_response_llm_model" {
  description = "OpenAI model used by the AI response agent."
  type        = string
  default     = "gpt-4.1"
}

variable "openai_base_url" {
  description = "OpenAI-compatible API base URL."
  type        = string
  default     = "https://api.openai.com"
}

variable "alarm_action_arns" {
  description = "SNS topic ARNs invoked when CloudWatch alarms change state."
  type        = list(string)
  default     = []
}

