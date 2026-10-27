# Its own state, beside the root's in the same bucket. This root is applied
# from the workstation, never from CI, so it is not part of the root's
# plan; it reads the root's outputs instead (main.tf).
terraform {
  backend "s3" {
    bucket       = "mini-app-polis-tfstate-400200465748"
    key          = "doppler.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
