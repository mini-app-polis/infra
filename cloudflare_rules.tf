# Every custom ruleset in the account: per-zone WAF custom rules, rate
# limiting, cache rules and single redirects, and the account's bulk
# redirects with the lists they read. Cloudflare's managed rulesets (Free
# managed, DDoS, normalization) are on every zone by default and are not
# managed here.
#
# Free plan limits: 5 custom rules, 1 rate-limiting rule and 10 cache rules
# per zone, and the rate-limit period and mitigation timeout are fixed at 10
# seconds.

resource "cloudflare_ruleset" "deejaytools_com_rate_limit" {
  zone_id = cloudflare_zone.this["deejaytools.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      # The Free plan's one rate-limiting rule keys only on the IP and can't
      # read request headers, and a venue's phones share one IP. So the public
      # reads, which the phones poll and the edge and the API cache, are left
      # out of it, and the limit on everything else is a ceiling sized above a
      # venue's peak of signed-in reads, check-ins and staff actions, not a
      # per-client limit: the API limits signed-in callers per user (ADR-0013
      # in api-deejaytools). deejaytools-com's load test checks the venue
      # stays under it. Covers api-dev too so dev mirrors prod. The Free plan
      # has no regex, so the {id} paths are matched by prefix and suffix (the
      # sessions path by prefix with no further "/").
      ref         = "66611518ffd94b8e88fde6682d6bd480"
      description = "api-per-ip-burst"
      expression  = "(http.host in {\"api.deejaytools.com\" \"api-dev.deejaytools.com\"}) and not (http.request.method eq \"GET\" and (http.request.uri.path eq \"/v1/divisions\" or http.request.uri.path eq \"/version\" or http.request.uri.path eq \"/v1/sessions\" or (starts_with(http.request.uri.path, \"/v1/queue/\") and (ends_with(http.request.uri.path, \"/active\") or ends_with(http.request.uri.path, \"/waiting\"))) or (starts_with(http.request.uri.path, \"/v1/sessions/\") and not substring(http.request.uri.path, 13) contains \"/\")))"
      action      = "block"
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 2000
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

resource "cloudflare_ruleset" "deejaytools_com_cache" {
  zone_id = cloudflare_zone.this["deejaytools.com"].id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      # The API's public reads, so a venue's polling phones are answered at
      # the edge: the session list and one session, and a session's active
      # and waiting queues. Cloudflare caches no JSON by default; this makes
      # these paths eligible and keeps the origin's Cache-Control (an
      # anonymous answer is public with s-maxage, anything else private,
      # no-store). Paths that send no Cache-Control are left out, so the
      # edge never applies its own default TTL to them. A request with an
      # Authorization header always goes to the origin: signed-in and staff
      # reads are personal or must be fresh. The default cache key keeps the
      # request's Origin header, so each site origin gets its own CORS
      # headers. Covers api-dev too so dev mirrors prod. The Free plan has no
      # regex, so the {id} paths are matched by prefix and suffix, as in the
      # rate-limit rule.
      ref         = "deejaytools-public-reads"
      description = "api-public-reads"
      expression  = "(http.host in {\"api.deejaytools.com\" \"api-dev.deejaytools.com\"}) and http.request.method eq \"GET\" and not any(lower(http.request.headers.names[*])[*] eq \"authorization\") and (http.request.uri.path eq \"/v1/sessions\" or (starts_with(http.request.uri.path, \"/v1/sessions/\") and not substring(http.request.uri.path, 13) contains \"/\") or (starts_with(http.request.uri.path, \"/v1/queue/\") and (ends_with(http.request.uri.path, \"/active\") or ends_with(http.request.uri.path, \"/waiting\"))))"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode = "respect_origin"
        }
        browser_ttl = {
          mode = "respect_origin"
        }
      }
      enabled = true
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
      ratelimit = {
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
      ref         = "c457627d66ee4613a7bca34d43a9ad2b"
      description = "kaianolevine -> wcs.kaianolevine"
      expression  = "(http.host eq \"kaianolevine.com\" or http.host eq \"www.kaianolevine.com\")\nand (http.request.uri.path ne \"/\")\nand not (\n  starts_with(http.request.uri.path, \"/assets/\")\n  or http.request.uri.path eq \"/favicon.ico\"\n  or http.request.uri.path eq \"/favicon.png\"\n  or http.request.uri.path eq \"/favicon-96x96.png\"\n  or http.request.uri.path eq \"/favicon.svg\"\n  or starts_with(http.request.uri.path, \"/favicon\")\n  or starts_with(http.request.uri.path, \"/apple-touch-icon\")\n  or http.request.uri.path eq \"/site.webmanifest\"\n  or http.request.uri.path eq \"/robots.txt\"\n  or starts_with(http.request.uri.path, \"/sitemap\")\n  or starts_with(http.request.uri.path, \"/cdn-cgi/\")\n)"
      action      = "redirect"
      action_parameters = {
        from_value = {
          status_code           = 301
          preserve_query_string = true
          target_url = {
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
      ratelimit = {
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
      ratelimit = {
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
      ref         = "c2d32b71e7bd443688c8e619d6ea0b91"
      description = "wcsmn"
      expression  = "http.request.full_uri in $wcsmn_com"
      action      = "redirect"
      action_parameters = {
        from_list = {
          name = "wcsmn_com"
          key  = "http.request.full_uri"
        }
      }
      enabled = true
    },
    {
      ref         = "42ef446482fd44049d7320394cc684fb"
      description = "kaianolevine_com"
      expression  = "http.request.full_uri in $kaianolevine"
      action      = "redirect"
      action_parameters = {
        from_list = {
          name = "kaianolevine"
          key  = "http.request.full_uri"
        }
      }
      enabled = true
    },
    {
      ref         = "9e9b0c22162d49449891b72de54add39"
      description = "swingtacular"
      expression  = "http.request.full_uri in $swingtacular"
      action      = "redirect"
      action_parameters = {
        from_list = {
          name = "swingtacular"
          key  = "http.request.full_uri"
        }
      }
      enabled = true
    },
    {
      ref         = "a4cb35f4c4c743e4890e0d2c863fcfa9"
      description = "dancegeekproductions"
      expression  = "http.request.full_uri in $dancegeekproductions"
      action      = "redirect"
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
