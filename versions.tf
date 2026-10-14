terraform {
  # 1.11 is the floor for S3-native state locking (`use_lockfile`), which is
  # what lets this backend lock without a DynamoDB table. CI runs 1.16.2,
  # the same version the workstation applies with.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.20"
    }
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "~> 1.0"
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

# The token comes from CLOUDFLARE_API_TOKEN in the environment, never from
# configuration: a read-only token in the plan job, an edit token in the
# apply job (see .github/workflows/terraform.yml and cloudflare.tf).
provider "cloudflare" {}

# Read-only. The token comes from DOPPLER_TOKEN in the environment: a
# service token scoped to the one Doppler config the Pages sites read from
# (see cloudflare_pages_sites.tf).
provider "doppler" {}
