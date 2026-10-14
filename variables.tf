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

variable "cloudflare_account_id" {
  description = "The Cloudflare account every zone, Pages project and Worker lives in. Not a secret: it appears in every dashboard URL and does nothing without a token."
  type        = string
  default     = "0314578fe75f14199c748d0065583f93"
}

# Build-time values for the Pages sites. Public by design — each is baked
# into the JavaScript every visitor downloads — but edited in Doppler, which
# syncs them to this repository's Actions secrets; the workflow passes them
# in as TF_VAR_*.
variable "deejaytools_clerk_publishable_key" {
  description = "deejaytools-com production Clerk publishable key (pk_live_…)."
  type        = string
}

variable "deejaytools_clerk_publishable_key_preview" {
  description = "deejaytools-com preview Clerk publishable key; the production key again if preview uses the same instance."
  type        = string
}

variable "deejaytools_sentry_dsn" {
  description = "deejaytools-com browser Sentry DSN."
  type        = string
}

variable "wcsmn_google_calendar_api_key" {
  description = "website-astro-wcsmn Google Calendar API key. Referrer-restricted in Google Cloud."
  type        = string
}
