# infra

All of mini-app-polis's AWS infrastructure, and its Cloudflare account, in
one Terraform root with one state:

- `state.tf` — the bucket this repository's own state lives in
- `account.tf` — one-per-account resources: the budget, the GitHub OIDC
  provider, and the API's producer user
- `doppler.tf` — the role Doppler assumes to sync secrets into Parameter
  Store
- `ci.tf` — the roles this repository's workflow plans and applies with
- `cogs.tf` — one `module` block per pipeline cog, from
  `modules/cog-worker`: queue and dead-letter queue, the worker function
  and its event source mapping, alarms for a dead-lettered job, a stalled
  queue and a job nearing the function timeout, and the role the cog's CI
  deploys code through. watcher-cog is the exception: it has no queue and runs on a
  schedule, from `modules/scheduled-worker` — the function, an EventBridge
  rule, a failing-ticks alarm, and the same deploy role
- `database_backups.tf` — the off-platform backup bucket for the two
  production Postgres databases (versioned, Object Lock in governance
  mode, lifecycle by prefix), with a write-only user for db-backup and a
  read-only user for db-drill
- `database_metrics.tf` — the db-poller user, which may only publish
  under the `MiniAppPolis/Postgres` CloudWatch namespace, and each
  database's alarms (unreachable, connections, WAL archive), emailed
  through their own SNS topic
- `audit_trail.tf` — the account's CloudTrail trail: management events in
  every region, plus every read and write of the database dumps, kept a
  year in its own bucket (see [Audit trail](#audit-trail))
- `observability.tf` — the CloudWatch dashboards: `mini-app-polis-services`
  for the APIs and cogs, `mini-app-polis-data` for the databases
- `cloudflare*.tf` — the Cloudflare zones, DNS, Pages projects, rules, bot
  management and Turnstile (see [Cloudflare](#cloudflare))
- `outputs.tf` — besides each cog's repository variables, a plan-time check
  that api-kaianolevine-com's six-hour dispatch claim window outlasts every
  cog's longest possible job
- `doppler/` — Doppler's layout: a project per consumer and its syncs, a
  separate root applied from the workstation (see
  [Doppler layout](#doppler-layout))
- `scripts/doppler_references.py` — writes the references in those
  projects' configs
- `scripts/check_*.py` — CI checks that the values this configuration
  copies from other repositories still match their owners' main (see
  [Copied constants](#copied-constants))

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
  Doppler, and are read by the function at cold start (the queue workers
  read them again at every invocation). Nothing secret is a
  Terraform variable, and the one Doppler config Terraform reads
  (mini-app-polis-pages / prd) holds only the Pages sites' public build
  values, so nothing secret is in state or in a plan.

Nothing on a workstation is load-bearing. A fresh machine needs the AWS CLI
profile, Terraform and this repository, and, to plan, a Cloudflare token in
`CLOUDFLARE_API_TOKEN` and a Doppler token in `DOPPLER_TOKEN` (the providers
read both from the environment).

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
in Doppler), add it to the `cogs` output and `cog_max_in_flight_seconds` in
`outputs.tf`, apply, confirm the alert subscription email, and set the three
repository variables from `terraform output cogs` in the cog's repository.

## rotator-cog's tokens

rotator-cog writes new secret values into Doppler, so its worker holds two
Doppler service tokens, one for the `prd` config and one for `dev`. They
live outside `/mini-app-polis/` (`terraform output
rotator_doppler_token_parameters`), so Doppler's sync role and the other
workers' grants never reach them; the `rotator-worker` role may read those
two parameters and nothing else outside its own list.

They are put by hand, not declared in Terraform: Terraform reads a
parameter it manages back on every plan, decrypted, and `infra-plan` may
read no parameter but the alert address. Mint each token in Doppler, then:

```bash
export AWS_PROFILE=miniapppolis
read -rs -p "prd token: " token && printf '%s' "$token" | aws ssm put-parameter --name /rotator/DOPPLER_TOKEN_PRD --type SecureString --overwrite --value file:///dev/stdin; unset token
read -rs -p "dev token: " token && printf '%s' "$token" | aws ssm put-parameter --name /rotator/DOPPLER_TOKEN_DEV --type SecureString --overwrite --value file:///dev/stdin; unset token
```

It also redeploys the Railway services that read a rotated secret at boot,
with Railway project tokens of its own. A project token reaches one
environment, so there are two, `ROTATOR_RAILWAY_TOKEN_PRD` for production
and `ROTATOR_RAILWAY_TOKEN_DEV` for development. They are values in the
rotator-cog Doppler project's `prd` config, not references into the vault,
so no other consumer reads them, and its sync puts them in
`/mini-app-polis/rotator-cog/prd/` (`terraform output
rotator_railway_token_parameters`). The worker reads them by path when it
redeploys; they are not in its environment. Mint a token in Railway, then:

```bash
pbpaste | tr -d '\r\n' | doppler secrets set ROTATOR_RAILWAY_TOKEN_PRD -p rotator-cog -c prd > /dev/null
pbpaste | tr -d '\r\n' | doppler secrets set ROTATOR_RAILWAY_TOKEN_DEV -p rotator-cog -c prd > /dev/null
```

## Doppler layout

`mini-app-polis-ecosystem` (`prd` and `dev`) is the vault: every value is
edited there, once, and rotator-cog and `rotate.py` write only there. Each
consumer gets a Doppler project of its own, named for its repository,
whose configs hold only what it reads. Each value there is a reference
into the vault (`${mini-app-polis-ecosystem.prd.NAME}`), named as the
consumer's code reads it, and the consumer's syncs carry only those. A
change in the vault re-syncs every config that references it.

A consumer's config may also hold values of its own that are not
references: the rotator's Railway tokens (above) are the only ones.
`scripts/doppler_references.py --prune` never deletes one.

So far the Lambda workers and this root have projects. Each one's `prd`
syncs to `/mini-app-polis/<repository>/prd/`; a worker's `dev` holds the
same references into the vault's `dev`, for local runs. This root's own
project, `infra`, holds the alert address `account.tf` reads.

GitHub Actions reads the same way (`doppler/github.tf`). A repository's
secrets and variables are its project's `ci` environment, synced to the
repository: masked values as Actions secrets, unmasked ones as Actions
variables. A GitHub environment's are `ci-<name>` (infra's `production`).
What the whole organisation reads is the `github-org` project, synced to
organisation secrets and variables. Values this root produces (role ARNs,
function names) are not secrets and are written by Terraform; everything
else is a reference into the vault. Nothing in GitHub is set by hand.

`doppler/` declares the projects and their syncs. It is a root of its own,
with its own state, applied from the workstation with the owner's Doppler
login. Nothing in GitHub holds a token that can do it: on Doppler's Team
plan any role that can see a project can read its secrets, so a token that
plans this layout reads every secret in it. Terraform does not write the
references themselves, since a `doppler_secret` resource keeps the value
its reference resolves to in state. `scripts/doppler_references.py` writes
them from `doppler/`'s `references` output.

```bash
export AWS_PROFILE=miniapppolis
export DOPPLER_TOKEN="$(doppler configure get token --plain)"

terraform -chdir=doppler init
terraform -chdir=doppler plan -out tfplan
terraform -chdir=doppler apply tfplan

terraform -chdir=doppler output -json references | python3 scripts/doppler_references.py
terraform -chdir=doppler output -json references | python3 scripts/doppler_references.py --apply
```

The script prints what it would write and writes it only with `--apply`.
It skips a reference to a name the vault does not hold, and reports it. That is an
optional setting nobody has set, and the worker leaves it unset. Apply this
root after the root's apply when a worker's parameter list changes, since
it reads the root's `doppler_consumers` output.

A worker reads its own prefix, under the names its code reads, and its
grant covers that prefix alone. A new worker, or a new name in a worker's
`ssm_parameters`, needs this root and the script applied, and the sync run,
before the root's apply ships it: the root's plan role may not read
parameters, so nothing at plan time checks. Every name in the module's
`ssm_parameters` must be listed here (Doppler's own `DOPPLER_*` names sync
beside them and are ignored):

```bash
aws ssm get-parameters-by-path --region us-east-1 --path /mini-app-polis/<repository>/prd --query 'Parameters[].Name' --output text | tr '\t' '\n'
```

## Copied constants

Some values here are copies of ones another repository owns. The `plan` job
checks each out from the owner's `main` — what it releases, as `main` is
what this repository applies — and fails when the copy has drifted:

| Copy | Owner | Check |
| --- | --- | --- |
| `local.dispatch_claim_window_seconds` (`outputs.tf`) | `CLAIM_WINDOW`, api-kaianolevine-com `src/kaianolevine_api/services/dispatch_claims.py` | `scripts/check_claim_window.py` |
| module `watcher`'s `schedule_targets` names (`cogs.tf`) | `get_watchers()`, watcher-cog `src/watcher_cog/config.py` | `scripts/check_watcher_names.py` |
| `local.dashboard_api_routes` (`observability.tf`) | `METRICS_ROUTES`, api-kaianolevine-com `src/kaianolevine_api/main.py` and api-deejaytools `src/api_deejaytools/main.py` | `scripts/check_api_routes.py` |
| `local.rotator_iam_users` (`cogs.tf`) | the `iam_user` of each `aws-access-key` entry, rotator-cog `secrets/inventory.yaml` | `scripts/check_rotator_iam_users.py` |

To change one, change the owner first and release it to its `main`, then
change the copy here. A change only on the owner's `dev` fails these checks
until it reaches `main`. Run a check locally against a clone of the owner:

```bash
python3 scripts/check_claim_window.py ~/git/api-kaianolevine-com/src/kaianolevine_api/services/dispatch_claims.py
python3 scripts/check_watcher_names.py ~/git/watcher-cog/src/watcher_cog/config.py
python3 scripts/check_api_routes.py ~/git/api-kaianolevine-com/src/kaianolevine_api/main.py ~/git/api-deejaytools/src/api_deejaytools/main.py
python3 scripts/check_rotator_iam_users.py ~/git/rotator-cog/secrets/inventory.yaml
```

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

## Audit trail

`audit_trail.tf` records every management event and every object read or
write on the database backup bucket. Management events from the last 90
days can also be searched with `aws cloudtrail lookup-events`. Data events
(the dump reads) are only in the trail's bucket: one gzipped JSON file per
region per few minutes, under
`AWSLogs/<account>/CloudTrail/<region>/<yyyy>/<mm>/<dd>/`.

Who has read a dump, newest last:

```sh
mkdir -p /tmp/audit && aws --profile miniapppolis s3 sync \
  "s3://mini-app-polis-cloudtrail-$(aws --profile miniapppolis sts get-caller-identity --query Account --output text)/AWSLogs/" /tmp/audit --exclude "*" --include "*/us-east-1/*"
find /tmp/audit -name '*.json.gz' -exec gzip -dc {} + \
  | jq -r '.Records[] | select(.eventName == "GetObject") | [.eventTime, .userIdentity.arn, .sourceIPAddress, .requestParameters.key] | @tsv' \
  | sort
```

Expected readers: `db-backup-reader` (db-drill, monthly) and you. Anyone
else, or a source IP that is not Railway's or yours, is the finding.

## Cloudflare

Every zone is managed here (`cloudflare.tf`). CI authenticates with two
API tokens (My Profile → API Tokens → Create custom token), minted by hand
and kept in Doppler:

| Secret | Where | Permissions |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN_READ` | repository secret, plan job | every permission below at **Read** |
| `CLOUDFLARE_API_TOKEN` | `production` environment secret, apply job | every permission below at **Write** (Account Settings stays Read) |

Account permissions: Account Settings, Account Rulesets, Account Filter
Lists, Bulk URL Redirects, Cloudflare Pages, Workers Scripts, Hyperdrive,
Turnstile. (Bulk redirect lists are read through Account Filter Lists;
Bulk URL Redirects alone is not enough.)

Zone permissions, on all zones in the account: Zone, Zone Settings, DNS,
Zone WAF, Single Redirect, Workers Routes, Bot Management.

Registration, renewal and transfer stay in the dashboard and are in
neither token.

## Why Terraform, not CloudFormation/SAM/CDK

The first decision record for the fleet's AWS foundation (region, one
queue and one function per cog, the Terraform choice) is
[docs/aws-foundation.md](docs/aws-foundation.md).

CloudFormation would hold state for us and roll failed updates back
atomically. Terraform was kept because:

- the infrastructure reaches past AWS — GitHub repository variables,
  Doppler, Cloudflare all have providers; CloudFormation covers AWS only;
- "CI owns the code, Terraform owns the configuration" is one
  `ignore_changes` line here, whereas CloudFormation expects code to ship
  through the stack, which means either widening CI's permissions or living
  with permanent drift;
- switching would rewrite working infrastructure to avoid one S3 bucket.
