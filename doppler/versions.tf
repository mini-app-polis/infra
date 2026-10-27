terraform {
  required_version = ">= 1.11"

  required_providers {
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "~> 1.0"
    }
  }
}

# The token comes from DOPPLER_TOKEN in the environment: the owner's own
# CLI login, on the workstation. Nothing in GitHub holds a token that can
# do this — see README.md, "Doppler layout".
provider "doppler" {}
