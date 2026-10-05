# Lets GitHub Actions assume AWS roles with short-lived OIDC tokens instead of stored keys.
# Two roles: "plan" (read-only, any branch / PR) and "apply" (write, main branch + environment only).

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "repository" {
  description = "owner/repo allowed to assume the roles."
  type        = string
}

variable "apply_environment" {
  description = "GitHub environment (with required reviewers) that may assume the apply role."
  type        = string
  default     = "production"
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform state bucket the plan role may read."
  type        = string
}

data "aws_partition" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
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
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repository}:pull_request", "repo:${var.repository}:ref:refs/heads/*"]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only jobs running in the protected environment, which itself only deploys from main.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repository}:environment:${var.apply_environment}"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name = "read-terraform-state"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "List", Effect = "Allow", Action = ["s3:ListBucket"], Resource = [var.state_bucket_arn] },
      { Sid = "ReadState", Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${var.state_bucket_arn}/*"] },
      # plan takes the S3 lock too; it may create and delete lock files, never state files.
      { Sid = "LockFiles", Effect = "Allow", Action = ["s3:PutObject", "s3:DeleteObject"], Resource = ["${var.state_bucket_arn}/*.tflock"] },
    ]
  })
}

resource "aws_iam_role" "apply" {
  name                 = "github-terraform-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# Broad by necessity (it creates IAM roles, VPCs, EKS); fenced by the trust policy above,
# a permissions boundary in real accounts, and required reviewers on the environment.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}
