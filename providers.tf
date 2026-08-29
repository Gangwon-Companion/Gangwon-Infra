provider "aws" {
  region = var.aws_region

  # The deployment account and region are verified by AWS CLI before Terraform.
  # Skipping duplicate provider bootstrap calls avoids AWS Sign-In credential stalls.
  skip_credentials_validation = true
  skip_region_validation      = true

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
