resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  github_deploy_repositories = {
    be = {
      repository     = "Gangwon-Companion/Gangwon-Companion"
      oidc_repository = "Gangwon-Companion/Gangwon-Companion"
      ecr_repository = aws_ecr_repository.be.arn
    }
    ai = {
      repository     = "Gangwon-Companion/Gangwon-AI"
      oidc_repository = "Gangwon-Companion@291513436/Gangwon-AI@1320145032"
      ecr_repository = aws_ecr_repository.ai.arn
    }
  }
}

data "aws_iam_policy_document" "github_infra_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Gangwon-Companion/Gangwon-Infra:environment:prod"]
    }
  }
}

resource "aws_iam_role" "github_infra" {
  name                 = "${local.name}-github-infra"
  assume_role_policy   = data.aws_iam_policy_document.github_infra_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_infra" {
  role       = aws_iam_role.github_infra.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "github_deploy_assume_role" {
  for_each = local.github_deploy_repositories

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${each.value.oidc_repository}:environment:prod"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  for_each = local.github_deploy_repositories

  name                 = "${local.name}-github-${each.key}-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_assume_role[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "github_deploy" {
  for_each = local.github_deploy_repositories

  name = "${local.name}-${each.key}-deploy"
  role = aws_iam_role.github_deploy[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = each.value.ecr_repository
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = aws_ecs_service.app.id
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}
