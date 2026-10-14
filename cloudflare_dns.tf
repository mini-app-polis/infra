# Every DNS record in every zone, adopted from the dashboard. One entry per
# record, keyed "<name> <type>" (with " #2" where a name and type repeat).
# Grouped by zone; the zone must be a key of local.cloudflare_zones.

locals {
  cloudflare_dns_records = {
    # dancegeekproductions.art
    "_domainconnect.dancegeekproductions.art CNAME" = { zone = "dancegeekproductions.art", type = "CNAME", name = "_domainconnect.dancegeekproductions.art", content = "_domainconnect.gd.domaincontrol.com", proxied = true, ttl = 1, priority = null }
    "dancegeekproductions.art CNAME"                = { zone = "dancegeekproductions.art", type = "CNAME", name = "dancegeekproductions.art", content = "dance-geek-productions-website.pages.dev", proxied = true, ttl = 1, priority = null }
    "www.dancegeekproductions.art CNAME"            = { zone = "dancegeekproductions.art", type = "CNAME", name = "www.dancegeekproductions.art", content = "dance-geek-productions-website.pages.dev", proxied = true, ttl = 1, priority = null }

    # deejaytools.com
    "_railway-verify.api-dev.deejaytools.com TXT"    = { zone = "deejaytools.com", type = "TXT", name = "_railway-verify.api-dev.deejaytools.com", content = "\"railway-verify=331aa28444c94b6aa6552fd5a984fb54132d9c3f826464aaf69d06ff5d8db29e\"", proxied = false, ttl = 3600, priority = null }
    "_railway-verify.api-dev.deejaytools.com TXT #2" = { zone = "deejaytools.com", type = "TXT", name = "_railway-verify.api-dev.deejaytools.com", content = "\"railway-verify=6323cb3a203955da5d469951390c609a2903f23604208d458d733b6ce9be9b52\"", proxied = false, ttl = 3600, priority = null }
    "_railway-verify.api.deejaytools.com TXT"        = { zone = "deejaytools.com", type = "TXT", name = "_railway-verify.api.deejaytools.com", content = "\"railway-verify=de51a015a616d9948b5b043c86ac34b1c48f4f7116d6bebcef7b2c697a3a198b\"", proxied = false, ttl = 3600, priority = null }
    "_railway-verify.api.deejaytools.com TXT #2"     = { zone = "deejaytools.com", type = "TXT", name = "_railway-verify.api.deejaytools.com", content = "\"railway-verify=fb187670bbec26a60af55edf6e4354bc36e76f1fd5b1828f2e1724503662ddc7\"", proxied = false, ttl = 3600, priority = null }
    "accounts.deejaytools.com CNAME"                 = { zone = "deejaytools.com", type = "CNAME", name = "accounts.deejaytools.com", content = "accounts.clerk.services", proxied = false, ttl = 1, priority = null }
    "api-dev.deejaytools.com CNAME"                  = { zone = "deejaytools.com", type = "CNAME", name = "api-dev.deejaytools.com", content = "a2prg3h9.up.railway.app", proxied = true, ttl = 1, priority = null }
    "api.deejaytools.com CNAME"                      = { zone = "deejaytools.com", type = "CNAME", name = "api.deejaytools.com", content = "rpm7acsp.up.railway.app", proxied = true, ttl = 1, priority = null }
    "clerk.deejaytools.com CNAME"                    = { zone = "deejaytools.com", type = "CNAME", name = "clerk.deejaytools.com", content = "frontend-api.clerk.services", proxied = false, ttl = 1, priority = null }
    "clk._domainkey.deejaytools.com CNAME"           = { zone = "deejaytools.com", type = "CNAME", name = "clk._domainkey.deejaytools.com", content = "dkim1.00mgm3lzia1r.clerk.services", proxied = false, ttl = 1, priority = null }
    "clk2._domainkey.deejaytools.com CNAME"          = { zone = "deejaytools.com", type = "CNAME", name = "clk2._domainkey.deejaytools.com", content = "dkim2.00mgm3lzia1r.clerk.services", proxied = false, ttl = 1, priority = null }
    "clkmail.deejaytools.com CNAME"                  = { zone = "deejaytools.com", type = "CNAME", name = "clkmail.deejaytools.com", content = "mail.00mgm3lzia1r.clerk.services", proxied = false, ttl = 1, priority = null }
    "deejaytools.com CNAME"                          = { zone = "deejaytools.com", type = "CNAME", name = "deejaytools.com", content = "deejaytools-com.pages.dev", proxied = true, ttl = 1, priority = null }
    "dev.deejaytools.com CNAME"                      = { zone = "deejaytools.com", type = "CNAME", name = "dev.deejaytools.com", content = "dev.deejaytools-com.pages.dev", proxied = true, ttl = 1, priority = null }
    "www.deejaytools.com CNAME"                      = { zone = "deejaytools.com", type = "CNAME", name = "www.deejaytools.com", content = "deejaytools-com.pages.dev", proxied = true, ttl = 1, priority = null }

    # emberlabshq.app
    "_vercel.emberlabshq.app TXT" = { zone = "emberlabshq.app", type = "TXT", name = "_vercel.emberlabshq.app", content = "\"vc-domain-verify=torch.emberlabshq.app,86ee37e557a479afb2f8,dc\"", proxied = false, ttl = 600, priority = null }
    "torch.emberlabshq.app CNAME" = { zone = "emberlabshq.app", type = "CNAME", name = "torch.emberlabshq.app", content = "508dee9dcc047fd8.vercel-dns-017.com", proxied = false, ttl = 600, priority = null }

    # kaiano.fyi
    "kaiano.fyi CNAME"     = { zone = "kaiano.fyi", type = "CNAME", name = "kaiano.fyi", content = "kaiano-all-website.pages.dev", proxied = true, ttl = 1, priority = null }
    "www.kaiano.fyi CNAME" = { zone = "kaiano.fyi", type = "CNAME", name = "www.kaiano.fyi", content = "kaiano-all-website.pages.dev", proxied = true, ttl = 1, priority = null }

    # kaianolevine.com
    "_dmarc.kaianolevine.com TXT"                  = { zone = "kaianolevine.com", type = "TXT", name = "_dmarc.kaianolevine.com", content = "\"v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com\"", proxied = false, ttl = 3600, priority = null }
    "_railway-verify.api.kaianolevine.com TXT"     = { zone = "kaianolevine.com", type = "TXT", name = "_railway-verify.api.kaianolevine.com", content = "\"railway-verify=dd8197f6fe1961ff613d9a04d7aae5762d55024665c42262de6f91cf27750bd5\"", proxied = false, ttl = 3600, priority = null }
    "_railway-verify.dev-api.kaianolevine.com TXT" = { zone = "kaianolevine.com", type = "TXT", name = "_railway-verify.dev-api.kaianolevine.com", content = "\"railway-verify=44d117bab78002a2b7252dc10e90cbc3904bd41964ac61a41bcffd94fa507651\"", proxied = false, ttl = 3600, priority = null }
    "accounts.kaianolevine.com CNAME"              = { zone = "kaianolevine.com", type = "CNAME", name = "accounts.kaianolevine.com", content = "accounts.clerk.services", proxied = false, ttl = 1, priority = null }
    "all.kaianolevine.com CNAME"                   = { zone = "kaianolevine.com", type = "CNAME", name = "all.kaianolevine.com", content = "kaiano-all-website.pages.dev", proxied = true, ttl = 1, priority = null }
    "api.kaianolevine.com CNAME"                   = { zone = "kaianolevine.com", type = "CNAME", name = "api.kaianolevine.com", content = "ylpigaog.up.railway.app", proxied = true, ttl = 1, priority = null }
    "brevo1._domainkey.kaianolevine.com CNAME"     = { zone = "kaianolevine.com", type = "CNAME", name = "brevo1._domainkey.kaianolevine.com", content = "b1.kaianolevine-com.dkim.brevo.com", proxied = false, ttl = 3600, priority = null }
    "brevo2._domainkey.kaianolevine.com CNAME"     = { zone = "kaianolevine.com", type = "CNAME", name = "brevo2._domainkey.kaianolevine.com", content = "b2.kaianolevine-com.dkim.brevo.com", proxied = false, ttl = 3600, priority = null }
    "career.kaianolevine.com CNAME"                = { zone = "kaianolevine.com", type = "CNAME", name = "career.kaianolevine.com", content = "website-astro-software.pages.dev", proxied = true, ttl = 1, priority = null }
    "clerk.kaianolevine.com CNAME"                 = { zone = "kaianolevine.com", type = "CNAME", name = "clerk.kaianolevine.com", content = "frontend-api.clerk.services", proxied = false, ttl = 1, priority = null }
    "clk._domainkey.kaianolevine.com CNAME"        = { zone = "kaianolevine.com", type = "CNAME", name = "clk._domainkey.kaianolevine.com", content = "dkim1.zbirvcpyyy3i.clerk.services", proxied = false, ttl = 1, priority = null }
    "clk2._domainkey.kaianolevine.com CNAME"       = { zone = "kaianolevine.com", type = "CNAME", name = "clk2._domainkey.kaianolevine.com", content = "dkim2.zbirvcpyyy3i.clerk.services", proxied = false, ttl = 1, priority = null }
    "clkmail.kaianolevine.com CNAME"               = { zone = "kaianolevine.com", type = "CNAME", name = "clkmail.kaianolevine.com", content = "mail.zbirvcpyyy3i.clerk.services", proxied = false, ttl = 1, priority = null }
    "dev-api.kaianolevine.com CNAME"               = { zone = "kaianolevine.com", type = "CNAME", name = "dev-api.kaianolevine.com", content = "zlpqb0ae.up.railway.app", proxied = true, ttl = 1, priority = null }
    "dev.software.kaianolevine.com CNAME"          = { zone = "kaianolevine.com", type = "CNAME", name = "dev.software.kaianolevine.com", content = "dev.website-astro-software.pages.dev", proxied = true, ttl = 1, priority = null }
    "dev.wcs.kaianolevine.com CNAME"               = { zone = "kaianolevine.com", type = "CNAME", name = "dev.wcs.kaianolevine.com", content = "dev.website-astro-wcs.pages.dev", proxied = true, ttl = 1, priority = null }
    "hub.kaianolevine.com CNAME"                   = { zone = "kaianolevine.com", type = "CNAME", name = "hub.kaianolevine.com", content = "kaiano-all-website.pages.dev", proxied = true, ttl = 1, priority = null }
    "kaianolevine.com CNAME"                       = { zone = "kaianolevine.com", type = "CNAME", name = "kaianolevine.com", content = "kaiano-all-website.pages.dev", proxied = true, ttl = 1, priority = null }
    "kaianolevine.com MX"                          = { zone = "kaianolevine.com", type = "MX", name = "kaianolevine.com", content = "smtp.google.com", proxied = false, ttl = 1, priority = 1 }
    "kaianolevine.com TXT"                         = { zone = "kaianolevine.com", type = "TXT", name = "kaianolevine.com", content = "\"brevo-code:3f35e457274d148d4e25e13f158f84fd\"", proxied = false, ttl = 3600, priority = null }
    "kaianolevine.com TXT #2"                      = { zone = "kaianolevine.com", type = "TXT", name = "kaianolevine.com", content = "\"v=spf1 include:_spf.google.com include:spf.brevo.com ~all\"", proxied = false, ttl = 1, priority = null }
    "software.kaianolevine.com CNAME"              = { zone = "kaianolevine.com", type = "CNAME", name = "software.kaianolevine.com", content = "website-astro-software.pages.dev", proxied = true, ttl = 1, priority = null }
    "tech.kaianolevine.com CNAME"                  = { zone = "kaianolevine.com", type = "CNAME", name = "tech.kaianolevine.com", content = "website-astro-software.pages.dev", proxied = true, ttl = 1, priority = null }
    "wcs.kaianolevine.com CNAME"                   = { zone = "kaianolevine.com", type = "CNAME", name = "wcs.kaianolevine.com", content = "website-astro-wcs.pages.dev", proxied = true, ttl = 1, priority = null }
    "www.kaianolevine.com CNAME"                   = { zone = "kaianolevine.com", type = "CNAME", name = "www.kaianolevine.com", content = "kaiano-all-website.pages.dev", proxied = true, ttl = 1, priority = null }

    # kwalla.dance
    "kwalla.dance CNAME"     = { zone = "kwalla.dance", type = "CNAME", name = "kwalla.dance", content = "kwalla-dance.pages.dev", proxied = true, ttl = 1, priority = null }
    "www.kwalla.dance CNAME" = { zone = "kwalla.dance", type = "CNAME", name = "www.kwalla.dance", content = "kwalla-dance.pages.dev", proxied = true, ttl = 1, priority = null }

    # mnmusicmovement.com
    "_dmarc.mnmusicmovement.com TXT"              = { zone = "mnmusicmovement.com", type = "TXT", name = "_dmarc.mnmusicmovement.com", content = "\"v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com\"", proxied = false, ttl = 1, priority = null }
    "brevo1._domainkey.mnmusicmovement.com CNAME" = { zone = "mnmusicmovement.com", type = "CNAME", name = "brevo1._domainkey.mnmusicmovement.com", content = "b1.kaianolevine-com.dkim.brevo.com", proxied = false, ttl = 1, priority = null }
    "brevo2._domainkey.mnmusicmovement.com CNAME" = { zone = "mnmusicmovement.com", type = "CNAME", name = "brevo2._domainkey.mnmusicmovement.com", content = "b1.kaianolevine-com.dkim.brevo.com", proxied = false, ttl = 1, priority = null }
    "mnmusicmovement.com TXT"                     = { zone = "mnmusicmovement.com", type = "TXT", name = "mnmusicmovement.com", content = "\"brevo-code:3f35e457274d148d4e25e13f158f84fd\"", proxied = false, ttl = 1, priority = null }
    "www.mnmusicmovement.com CNAME"               = { zone = "mnmusicmovement.com", type = "CNAME", name = "www.mnmusicmovement.com", content = "mnmusicmovement.com", proxied = true, ttl = 1, priority = null }

    # mnwcs.com
    "mnwcs.com CNAME"     = { zone = "mnwcs.com", type = "CNAME", name = "mnwcs.com", content = "website-astro-wcsmn.pages.dev", proxied = true, ttl = 1, priority = null }
    "www.mnwcs.com CNAME" = { zone = "mnwcs.com", type = "CNAME", name = "www.mnwcs.com", content = "website-astro-wcsmn.pages.dev", proxied = true, ttl = 1, priority = null }

    # swingtacular.art
    "_domainconnect.swingtacular.art CNAME" = { zone = "swingtacular.art", type = "CNAME", name = "_domainconnect.swingtacular.art", content = "_domainconnect.gd.domaincontrol.com", proxied = true, ttl = 1, priority = null }
    "dev.swingtacular.art CNAME"            = { zone = "swingtacular.art", type = "CNAME", name = "dev.swingtacular.art", content = "dev.website-swingtacular.pages.dev", proxied = true, ttl = 1, priority = null }
    "pay.swingtacular.art CNAME"            = { zone = "swingtacular.art", type = "CNAME", name = "pay.swingtacular.art", content = "paylinks.commerce.godaddy.com", proxied = true, ttl = 1, priority = null }
    "swingtacular.art CNAME"                = { zone = "swingtacular.art", type = "CNAME", name = "swingtacular.art", content = "website-swingtacular.pages.dev", proxied = true, ttl = 1, priority = null }
    "swingtacular.art TXT"                  = { zone = "swingtacular.art", type = "TXT", name = "swingtacular.art", content = "\"google-site-verification=TUaBg-FB-_dE32u5eSEyjKoj4lQXlia1EMmhKaKYgHI\"", proxied = false, ttl = 3600, priority = null }
    "www.swingtacular.art CNAME"            = { zone = "swingtacular.art", type = "CNAME", name = "www.swingtacular.art", content = "website-swingtacular.pages.dev", proxied = true, ttl = 1, priority = null }

    # syncright.dev
    "_railway-verify.app.syncright.dev TXT" = { zone = "syncright.dev", type = "TXT", name = "_railway-verify.app.syncright.dev", content = "\"railway-verify=43a4639f96301bc5d08bee54aaa54533362f5a2ceda292243d15452695bf4ec1\"", proxied = false, ttl = 3600, priority = null }
    "app.syncright.dev CNAME"               = { zone = "syncright.dev", type = "CNAME", name = "app.syncright.dev", content = "y6hwd2zz.up.railway.app", proxied = true, ttl = 1, priority = null }

    # wcsmn.com
    "_dmarc.wcsmn.com TXT"              = { zone = "wcsmn.com", type = "TXT", name = "_dmarc.wcsmn.com", content = "\"v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com\"", proxied = false, ttl = 1, priority = null }
    "brevo1._domainkey.wcsmn.com CNAME" = { zone = "wcsmn.com", type = "CNAME", name = "brevo1._domainkey.wcsmn.com", content = "b1.kaianolevine-com.dkim.brevo.com", proxied = false, ttl = 1, priority = null }
    "brevo2._domainkey.wcsmn.com CNAME" = { zone = "wcsmn.com", type = "CNAME", name = "brevo2._domainkey.wcsmn.com", content = "b2.kaianolevine-com.dkim.brevo.com", proxied = false, ttl = 1, priority = null }
    "dev.wcsmn.com CNAME"               = { zone = "wcsmn.com", type = "CNAME", name = "dev.wcsmn.com", content = "dev.website-astro-wcsmn.pages.dev", proxied = true, ttl = 1, priority = null }
    "wcsmn.com CNAME"                   = { zone = "wcsmn.com", type = "CNAME", name = "wcsmn.com", content = "website-astro-wcsmn.pages.dev", proxied = true, ttl = 1, priority = null }
    "wcsmn.com TXT"                     = { zone = "wcsmn.com", type = "TXT", name = "wcsmn.com", content = "\"brevo-code:3f35e457274d148d4e25e13f158f84fd\"", proxied = false, ttl = 1, priority = null }
    "www.wcsmn.com CNAME"               = { zone = "wcsmn.com", type = "CNAME", name = "www.wcsmn.com", content = "website-astro-wcsmn.pages.dev", proxied = true, ttl = 1, priority = null }
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.cloudflare_dns_records

  zone_id  = cloudflare_zone.this[each.value.zone].id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  priority = each.value.priority
}
