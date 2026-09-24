terraform {
  # 1.11 is the floor for S3-native state locking (`use_lockfile`), which is
  # what lets this backend lock without a DynamoDB table. CI runs 1.16.2,
  # the same version the workstation applies with.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "mini-app-polis"
      ManagedBy = "terraform"
      Repo      = "mini-app-polis/infra"
    }
  }
}
