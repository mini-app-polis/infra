# Every custom ruleset in the account: per-zone WAF custom rules, rate
# limiting and single redirects, and the account's bulk redirects with the
# lists they read. Cloudflare's managed rulesets (Free managed, DDoS,
# normalization) are on every zone by default and are not managed here.
#
# Free plan limits: 5 custom rules and 1 rate-limiting rule per zone, and
# the rate-limit period and mitigation timeout are fixed at 10 seconds.

resource "cloudflare_ruleset" "deejaytools_com_rate_limit" {
  zone_id = cloudflare_zone.this["deejaytools.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "66611518ffd94b8e88fde6682d6bd480"
      description = "api-per-ip-burst"
      expression  = "   (http.host eq \"api.deejaytools.com\")"
      action      = "block"
      ratelimit   = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 50
        mitigation_timeout  = 10
      }
      enabled = true
    },
  ]
}

resource "cloudflare_ruleset" "deejaytools_com_waf_custom" {
  zone_id = cloudflare_zone.this["deejaytools.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      ref         = "0b32c468bc9b43d483bc4db8236a15bd"
      description = "block-scanner-paths"
      expression  = "   (http.host eq \"api.deejaytools.com\") and ((lower(url_decode(http.request.uri.path)) contains \"/.\" and not starts_with(http.request.uri.path, \"/.well-known/\")) or ends_with(lower(url_decode(http.request.uri.path)), \".php\") or lower(url_decode(http.request.uri.path)) contains \"wp-\" or lower(url_decode(http.request.uri.path)) contains \"tfstate\" or starts_with(http.request.uri.path, \"//\"))"
      action      = "block"
      enabled     = true
    },
  ]
}

resource "cloudflare_ruleset" "kaianolevine_com_rate_limit" {
  zone_id = cloudflare_zone.this["kaianolevine.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "14025f3a8608426f8377b17da787953f"
      description = "api-per-ip-burst"
      expression  = "(http.host eq \"api.kaianolevine.com\")"
      action      = "block"
      ratelimit   = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 50
        mitigation_timeout  = 10
      }
      enabled = true
    },
  ]
}

resource "cloudflare_ruleset" "kaianolevine_com_redirect" {
  zone_id = cloudflare_zone.this["kaianolevine.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      ref               = "c457627d66ee4613a7bca34d43a9ad2b"
      description       = "kaianolevine -> wcs.kaianolevine"
      expression        = "(http.host eq \"kaianolevine.com\" or http.host eq \"www.kaianolevine.com\")\nand (http.request.uri.path ne \"/\")\nand not (\n  starts_with(http.request.uri.path, \"/assets/\")\n  or http.request.uri.path eq \"/favicon.ico\"\n  or http.request.uri.path eq \"/favicon.png\"\n  or http.request.uri.path eq \"/favicon-96x96.png\"\n  or http.request.uri.path eq \"/favicon.svg\"\n  or starts_with(http.request.uri.path, \"/favicon\")\n  or starts_with(http.request.uri.path, \"/apple-touch-icon\")\n  or http.request.uri.path eq \"/site.webmanifest\"\n  or http.request.uri.path eq \"/robots.txt\"\n  or starts_with(http.request.uri.path, \"/sitemap\")\n  or starts_with(http.request.uri.path, \"/cdn-cgi/\")\n)"
      action            = "redirect"
      action_parameters = {
        from_value = {
          status_code           = 301
          preserve_query_string = true
          target_url            = {
            expression = "concat(\"https://wcs.kaianolevine.com\", http.request.uri.path)"
          }
        }
      }
      enabled = true
    },
  ]
}

resource "cloudflare_ruleset" "kaianolevine_com_waf_custom" {
  zone_id = cloudflare_zone.this["kaianolevine.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      ref         = "705ecac2b7df44ae90ace85bebe12fe2"
      description = "block-scanner-paths"
      expression  = "(http.host eq \"api.kaianolevine.com\") and ((lower(url_decode(http.request.uri.path)) contains \"/.\" and not starts_with(http.request.uri.path, \"/.well-known/\")) or ends_with(lower(url_decode(http.request.uri.path)), \".php\") or lower(url_decode(http.request.uri.path)) contains \"wp-\" or lower(url_decode(http.request.uri.path)) contains \"tfstate\" or starts_with(http.request.uri.path, \"//\"))"
      action      = "block"
      enabled     = true
    },
  ]
}

resource "cloudflare_ruleset" "mnmusicmovement_com_rate_limit" {
  zone_id = cloudflare_zone.this["mnmusicmovement.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "7a08fb5aeea548e986f41d5f9dd3bc33"
      description = "Leaked credential check"
      expression  = "(cf.waf.credential_check.password_leaked)"
      action      = "block"
      ratelimit   = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 5
        mitigation_timeout  = 10
      }
      enabled = true
    },
  ]
}

resource "cloudflare_ruleset" "swingtacular_art_rate_limit" {
  zone_id = cloudflare_zone.this["swingtacular.art"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "c5252bbbbd2c4ae48780d9267d1ce1c9"
      description = "Leaked credential check"
      expression  = "(cf.waf.credential_check.password_leaked)"
      action      = "block"
      ratelimit   = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 5
        mitigation_timeout  = 10
      }
      enabled = true
    },
  ]
}

# Bulk redirects: one account-level rule per list below.
resource "cloudflare_ruleset" "account_bulk_redirect" {
  account_id = var.cloudflare_account_id
  name       = "default"
  kind       = "root"
  phase      = "http_request_redirect"

  rules = [
    {
      ref               = "c2d32b71e7bd443688c8e619d6ea0b91"
      description       = "wcsmn"
      expression        = "http.request.full_uri in $wcsmn_com"
      action            = "redirect"
      action_parameters = {
        from_list = {
          name = "wcsmn_com"
          key  = "http.request.full_uri"
        }
      }
      enabled = true
    },
    {
      ref               = "42ef446482fd44049d7320394cc684fb"
      description       = "kaianolevine_com"
      expression        = "http.request.full_uri in $kaianolevine"
      action            = "redirect"
      action_parameters = {
        from_list = {
          name = "kaianolevine"
          key  = "http.request.full_uri"
        }
      }
      enabled = true
    },
    {
      ref               = "9e9b0c22162d49449891b72de54add39"
      description       = "swingtacular"
      expression        = "http.request.full_uri in $swingtacular"
      action            = "redirect"
      action_parameters = {
        from_list = {
          name = "swingtacular"
          key  = "http.request.full_uri"
        }
      }
      enabled = true
    },
    {
      ref               = "a4cb35f4c4c743e4890e0d2c863fcfa9"
      description       = "dancegeekproductions"
      expression        = "http.request.full_uri in $dancegeekproductions"
      action            = "redirect"
      action_parameters = {
        from_list = {
          name = "dancegeekproductions"
          key  = "http.request.full_uri"
        }
      }
      enabled = true
    },
  ]
}

resource "cloudflare_list" "dancegeekproductions" {
  account_id = var.cloudflare_account_id
  name       = "dancegeekproductions"
  kind       = "redirect"

  items = [
    {
      redirect = {
        source_url       = "https://dancegeekproductions.art/"
        target_url       = "https://www.dancegeekproductions.art/"
        status_code      = 301
        subpath_matching = true
      }
    },
  ]
}

resource "cloudflare_list" "kaianolevine" {
  account_id = var.cloudflare_account_id
  name       = "kaianolevine"
  kind       = "redirect"

  items = [
    {
      redirect = {
        source_url            = "all.kaianolevine.com/"
        target_url            = "https://www.kaianolevine.com"
        status_code           = 301
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "hub.kaianolevine.com/"
        target_url            = "https://www.kaianolevine.com"
        status_code           = 301
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "kaiano.fyi/"
        target_url            = "https://www.kaianolevine.com"
        status_code           = 301
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "kaianolevine.com/"
        target_url            = "https://www.kaianolevine.com"
        status_code           = 301
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
  ]
}

resource "cloudflare_list" "swingtacular" {
  account_id = var.cloudflare_account_id
  name       = "swingtacular"
  kind       = "redirect"

  items = [
    {
      redirect = {
        source_url            = "dev.website-astro-swingtacular.pages.dev/"
        target_url            = "https://dev.swingtacular.art/"
        status_code           = 301
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "website-astro-swingtacular.pages.dev/"
        target_url            = "https://swingtacular.art/"
        status_code           = 301
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "www.swingtacular.art/"
        target_url            = "https://swingtacular.art/"
        status_code           = 301
        include_subdomains    = true
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
  ]
}

resource "cloudflare_list" "wcsmn_com" {
  account_id = var.cloudflare_account_id
  name       = "wcsmn_com"
  kind       = "redirect"

  items = [
    {
      redirect = {
        source_url            = "mnwcs.com/"
        target_url            = "https://www.wcsmn.com/"
        status_code           = 301
        include_subdomains    = true
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "wcsmn-com.pages.dev/"
        target_url            = "https://www.wcsmn.com/"
        status_code           = 301
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "wcsmn.com/"
        target_url            = "https://www.wcsmn.com/"
        status_code           = 301
        include_subdomains    = false
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
    {
      redirect = {
        source_url            = "www.mnwcs.com/"
        target_url            = "https://www.wcsmn.com/"
        status_code           = 301
        include_subdomains    = true
        subpath_matching      = true
        preserve_path_suffix  = true
        preserve_query_string = true
      }
    },
  ]
}
