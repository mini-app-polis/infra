variable "region" {
  description = "Everything in this account lives in US East, next to the Railway fleet the workers call back to."
  type        = string
  default     = "us-east-1"
}

variable "doppler_workplace_id" {
  description = "Doppler workplace ID, the external ID on the sync role's trust policy. Not a secret: it only works together with Doppler's own credentials."
  type        = string
  default     = "20209dff73a41e59b6c6"
}
