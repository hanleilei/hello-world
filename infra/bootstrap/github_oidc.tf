# GitHub Actions OIDC — Identity Provider + IAM Roles
#
# Creates the trust between GitHub Actions and AWS so that workflows can assume
# an AWS role without storing any long-lived Access Key / Secret Key.
#
# Two roles are created (principle of least privilege):
#   hello-world-github-ci  — read-only plan/validate (pull_request events)
#   hello-world-github-cd  — full deploy (push to main + environment-scoped jobs)
#
# After `terraform apply`:
#   1. Note the two role ARNs printed in the outputs.
#   2. GitHub repo → Settings → Secrets and variables → Actions:
#        AWS_ROLE_ARN_CI  = <github_ci_role_arn>
#        AWS_ROLE_ARN_CD  = <github_cd_role_arn>
#   3. Update the workflows to reference the correct secret per workflow
#      (infra-ci / service-ci → AWS_ROLE_ARN_CI, infra-cd / service-cd → AWS_ROLE_ARN_CD).

variable "github_org" {
  description = "GitHub organisation name or personal account login that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)."
  type        = string
  default     = "hello-world"
}

# ─── OIDC Identity Provider ───────────────────────────────────────────────────
# Allows GitHub Actions JWT tokens to be exchanged for temporary AWS credentials
# via STS AssumeRoleWithWebIdentity — no static keys needed.
#
# AWS automatically validates the signing certificate for
# token.actions.githubusercontent.com; the thumbprint list below provides
# forward compatibility should the intermediate CA change.

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Thumbprints for token.actions.githubusercontent.com (updated 2023-06).
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name      = "GitHub Actions OIDC"
    ManagedBy = "terraform-bootstrap"
  }
}

locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.github_actions.arn
  oidc_subject_base = "repo:${var.github_org}/${var.github_repo}"
}

# ─── CI Role ─────────────────────────────────────────────────────────────────
# Assumed only during pull_request workflow runs (infra-ci, service-ci).
# Read-only plan access; still needs DynamoDB write to acquire/release state lock.

data "aws_iam_policy_document" "github_ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Allow pull_request events AND workflow_call from main (called by release.yml).
    # StringLike is required because the sub for push events includes the full ref path.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.oidc_subject_base}:pull_request",
        "${local.oidc_subject_base}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  name               = "hello-world-github-ci"
  assume_role_policy = data.aws_iam_policy_document.github_ci_trust.json

  tags = {
    Name      = "GitHub Actions CI Role"
    ManagedBy = "terraform-bootstrap"
  }
}

# Broad read-only access across all AWS services for terraform plan.
resource "aws_iam_role_policy_attachment" "github_ci_readonly" {
  role       = aws_iam_role.github_ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Additional state bucket + lock table access (write needed even for plan).
data "aws_iam_policy_document" "github_ci_state" {
  statement {
    sid     = "StateRead"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }

  # Terraform 1.10+ native S3 locking writes a .tflock file alongside the
  # state file. CI (plan) must be able to acquire and release that lock.
  # Scope is restricted to *.tflock keys only — actual state files remain
  # read-only for the CI role.
  statement {
    sid     = "S3LockFile"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*.tflock"]
  }

  statement {
    sid     = "StateLock"
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.terraform_lock.arn]
  }
}

resource "aws_iam_role_policy" "github_ci_state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.github_ci.name
  policy = data.aws_iam_policy_document.github_ci_state.json
}

# ─── CD Role ─────────────────────────────────────────────────────────────────
# Assumed by push-to-main jobs and environment-scoped deploy jobs
# (infra-cd, service-cd).  Uses StringLike so that both
# "repo:ORG/REPO:ref:refs/heads/main" and "repo:ORG/REPO:environment:staging"
# (etc.) can match.

data "aws_iam_policy_document" "github_cd_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Allow main-branch pushes AND environment-scoped jobs (deploy-staging, etc.).
    # The repo constraint is the primary security boundary.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.oidc_subject_base}:*"]
    }
  }
}

resource "aws_iam_role" "github_cd" {
  name               = "hello-world-github-cd"
  assume_role_policy = data.aws_iam_policy_document.github_cd_trust.json

  tags = {
    Name      = "GitHub Actions CD Role"
    ManagedBy = "terraform-bootstrap"
  }
}

# Full service access (minus IAM user management) for terraform apply +
# chalice deploy (Lambda, API Gateway, CloudWatch Logs, etc.).
resource "aws_iam_role_policy_attachment" "github_cd_power_user" {
  role       = aws_iam_role.github_cd.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# IAM permissions required to create/manage Lambda execution roles and
# Chalice-generated roles during deployment.
resource "aws_iam_role_policy_attachment" "github_cd_iam" {
  role       = aws_iam_role.github_cd.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

# State bucket read/write + lock table access for apply.
data "aws_iam_policy_document" "github_cd_state" {
  statement {
    sid    = "StateReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }

  statement {
    sid     = "StateLock"
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.terraform_lock.arn]
  }
}

resource "aws_iam_role_policy" "github_cd_state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.github_cd.name
  policy = data.aws_iam_policy_document.github_cd_state.json
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "github_ci_role_arn" {
  value       = aws_iam_role.github_ci.arn
  description = "Set as GitHub secret AWS_ROLE_ARN_CI (used by infra-ci and service-ci workflows)"
}

output "github_cd_role_arn" {
  value       = aws_iam_role.github_cd.arn
  description = "Set as GitHub secret AWS_ROLE_ARN_CD (used by infra-cd and service-cd workflows)"
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github_actions.arn
  description = "ARN of the GitHub Actions OIDC identity provider"
}
