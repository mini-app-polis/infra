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

variable "kaiano_api_base_url" {
  description = "api-kaianolevine-com, which every worker calls back to."
  type        = string
  default     = "https://api.kaianolevine.com"
}

variable "budget_limit_usd" {
  description = "Monthly budget. Set low on purpose — this should never fire."
  type        = number
  default     = 10
}
