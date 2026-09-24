# One state for the account: the fleet's shared resources and every cog's
# stack. At this size one plan covering everything is normal, and a change
# to one cog still touches only that cog.
#
# Backend blocks cannot read variables, so the values are literal. The
# bucket is created once by hand and then managed by state.tf — see
# README.md for the bootstrap.
terraform {
  backend "s3" {
    bucket       = "mini-app-polis-tfstate-400200465748"
    key          = "infra.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
