# ---------- 5. Image repos + GitHub Actions deploy role (OIDC, no keys) ----------

resource "aws_ecr_repository" "app" {
  for_each = toset(["api", "worker", "web"])

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE" # tag = commit SHA, never overwritten
  force_delete         = true        # lab: delete images on destroy

  image_scanning_configuration {
    scan_on_push = true
  }
}

# The GitHub OIDC provider already exists in this account (created once in uconia-infra)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only this repo's main branch (name format and GitHub's newer ID format)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${split("/", var.github_repo)[0]}@${var.github_owner_id}/${split("/", var.github_repo)[1]}@*:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy" "github_deploy" {
  name = "push-images-and-deploy"
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EcrLogin", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Sid    = "EcrPushOwnRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages",
        ]
        Resource = [for r in aws_ecr_repository.app : r.arn]
      },
      # Needed for `aws eks update-kubeconfig`; what it may do inside the cluster is set by the access entry
      { Sid = "DescribeCluster", Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = module.eks.cluster_arn },
    ]
  })
}
