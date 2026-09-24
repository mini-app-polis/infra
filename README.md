# infra

All of mini-app-polis's AWS infrastructure, in one Terraform root with one
state:

- the state bucket this repository's own state lives in (`state.tf`)
- *(step 3)* the account's shared resources — budget, GitHub OIDC provider,
  the API's producer user, the Doppler sync role
- *(step 3)* one `module "<cog>"` per pipeline cog, from `modules/cog-worker`

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

Then delete the `import` block from `state.tf` and commit the lock file.

## Everyday use

```bash
export AWS_PROFILE=miniapppolis
terraform plan -out tfplan
terraform apply tfplan
```

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
