# infra

All of mini-app-polis's AWS infrastructure, in one Terraform root with one
state:

- `state.tf` — the bucket this repository's own state lives in
- `account.tf` — one-per-account resources: the budget, the GitHub OIDC
  provider, and the API's producer user
- `doppler.tf` — the role Doppler assumes to sync secrets into Parameter
  Store
- `ci.tf` — the roles this repository's workflow plans and applies with
- `cogs.tf` — one `module` block per pipeline cog, from
  `modules/cog-worker`: queue, dead-letter queue and alarm, the worker
  function and its event source mapping, and the role the cog's CI deploys
  code through

Cog repositories own their **code** and deploy it (`lambda-deploy.yml`,
`UpdateFunctionCode` only). This repository owns everything else.

## State

Remote, in `s3://mini-app-polis-tfstate-400200465748/infra.tfstate`:

- **Versioned.** Every apply keeps the previous state. Roll back by
  restoring an earlier object version. Noncurrent versions expire after 90
  days, and the newest ten are always kept.
- **Locked** with S3's native lock file (`use_lockfile`), so no DynamoDB.
- **Encrypted** with SSE-S3; TLS-only bucket policy; public access blocked.
- **No secrets.** Worker secrets live in SSM Parameter Store, synced from
  Doppler, and are read by the function at cold start. Nothing secret is a
  Terraform variable, so nothing secret is in state or in a plan.

Nothing on a workstation is load-bearing. A fresh machine needs the AWS CLI
profile, Terraform and this repository.

## Bootstrap (once, already done if the bucket exists)

The bucket has to exist before `terraform init` can use it as a backend.
It is created by hand, then adopted by the `import` block in `state.tf`, so
Terraform owns its configuration from the first apply and no local state
file ever exists.

```bash
export AWS_PROFILE=miniapppolis

aws s3api create-bucket --bucket mini-app-polis-tfstate-400200465748 --region us-east-1

terraform init
terraform plan -out tfplan     # expect: 1 to import, 6 to add, 1 to change (the default tags on the imported bucket), 0 to destroy
terraform apply tfplan
terraform providers lock -platform=darwin_arm64 -platform=linux_amd64
```

The first apply used an `import` block in `state.tf` to adopt the bucket; it was removed afterwards. To bootstrap again from scratch, add it back:

```hcl
import {
  to = aws_s3_bucket.tfstate
  id = "mini-app-polis-tfstate-400200465748"
}
```

## Adding a cog

Add a `module` block to `cogs.tf`, list its secrets by name (their values go
in Doppler), apply, confirm the alert subscription email, and set the three
repository variables from `terraform output cogs` in the cog's repository.

## Making a change

1. Commit to `dev` and open a pull request to `main`. CI plans it with the
   read-only `infra-plan` role; the plan is the job summary.
2. Merge. CI plans again on `main` and applies with `infra-apply`, in the
   `production` environment. The merge is the approval: read the PR's plan
   before merging.

Nothing applies from `dev`, and `main` accepts changes only by pull request,
so `main` is always what is applied. Roles: `ci.tf`. Workflow:
`.github/workflows/terraform.yml`.

A plan that destroys or replaces anything fails the pull request's `plan`
check, and the apply job refuses it too — those are the changes that cause
outages. If it is intended, label the pull request **`allow-destroy`**: the
check re-runs, lists exactly what goes, and passes; merging applies it.

### Break-glass

The admin IAM user on the workstation still works, for when CI cannot — a
broken role, a locked state:

```bash
export AWS_PROFILE=miniapppolis
terraform plan -out tfplan
terraform apply tfplan
```

Commit whatever that applied to `main` straight after, through a pull
request, or the next CI apply will undo it.

## Why Terraform, not CloudFormation/SAM/CDK

CloudFormation would hold state for us and roll failed updates back
atomically. Terraform was kept because:

- the infrastructure reaches past AWS — GitHub repository variables,
  Doppler, Cloudflare all have providers; CloudFormation covers AWS only;
- "CI owns the code, Terraform owns the configuration" is one
  `ignore_changes` line here, whereas CloudFormation expects code to ship
  through the stack, which means either widening CI's permissions or living
  with permanent drift;
- switching would rewrite working infrastructure to avoid one S3 bucket.
