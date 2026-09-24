# The two roles this repository's GitHub Actions assume — the only way
# changes reach AWS day to day.
#
#   pull request dev → main   plan, with infra-plan (read-only)
#   push to main              plan, then apply with infra-apply once the
#                             `production` environment's reviewer approves
#
# Nothing is applied from dev, and main takes changes only by pull request
# (branch protection), so main is always what is applied. The admin IAM
# user on the workstation is for break-glass only.
#
# Both trust the account's GitHub OIDC provider (account.tf). Pull requests
# from forks receive no OIDC token, so neither role is reachable from
# outside the organisation.

locals {
  # GitHub issues this repository's tokens with immutable ids in the
  # subject — owner@owner_id/repo@repo_id — because it was created after
  # GitHub made that the default for new repositories. The older cog
  # repositories still present `mini-app-polis/<repo>`. The ids are the
  # better match: a repository deleted and recreated under the same name
  # gets a new id, so it cannot inherit these roles.
  github_sub = "repo:mini-app-polis@270520182/infra@1385980329"
  oidc_sub   = "token.actions.githubusercontent.com:sub"
  oidc_aud   = "token.actions.githubusercontent.com:aud"
}

# ── Plan ─────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "infra_plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = local.oidc_aud
      values   = ["sts.amazonaws.com"]
    }

    # A pull request in this repository, or a push to main (the plan shown
    # before the apply is approved).
    condition {
      test     = "StringEquals"
      variable = local.oidc_sub
      values = [
        "${local.github_sub}:pull_request",
        "${local.github_sub}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "infra_plan" {
  name               = "infra-plan"
  description        = "mini-app-polis/infra CI: plans on pull requests and pushes to main. Read-only."
  assume_role_policy = data.aws_iam_policy_document.infra_plan_assume.json
}

resource "aws_iam_role_policy_attachment" "infra_plan_read" {
  role       = aws_iam_role.infra_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "infra_plan_limits" {
  # ReadOnlyAccess can read — and decrypt — every parameter Doppler syncs.
  # A plan needs exactly one of them, the alert address; deny the rest.
  # (State is read through ReadOnlyAccess. Plans run with -lock=false, so
  # the role writes nothing, not even the lock file.)
  statement {
    sid    = "OnlyTheAlertAddress"
    effect = "Deny"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory",
    ]
    not_resources = [data.aws_ssm_parameter.alert_email.arn]
  }
}

resource "aws_iam_role_policy" "infra_plan_limits" {
  name   = "infra-plan-limits"
  role   = aws_iam_role.infra_plan.id
  policy = data.aws_iam_policy_document.infra_plan_limits.json
}

# ── Apply ────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "infra_apply_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = local.oidc_aud
      values   = ["sts.amazonaws.com"]
    }

    # Only a job running in the `production` environment, which GitHub
    # holds until its required reviewer approves and which is restricted
    # to the main branch.
    condition {
      test     = "StringEquals"
      variable = local.oidc_sub
      values   = ["${local.github_sub}:environment:production"]
    }
  }
}

resource "aws_iam_role" "infra_apply" {
  name               = "infra-apply"
  description        = "mini-app-polis/infra CI: applies merges to main, from the production environment after approval."
  assume_role_policy = data.aws_iam_policy_document.infra_apply_assume.json
}

# Administrator, honestly labelled. This root creates IAM roles and
# policies, and anything that can do that can grant itself anything — a
# narrower policy would be a list that looks least-privilege and is not.
# The control is who can assume it: one environment, one reviewer, one
# branch.
resource "aws_iam_role_policy_attachment" "infra_apply_admin" {
  role       = aws_iam_role.infra_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
