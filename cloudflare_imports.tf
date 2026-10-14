# One-time adoption of what was built in the Cloudflare dashboard. Once
# main has applied these, delete this file in the next pull request.

locals {
  # DNS record key → "<zone_id>/<record_id>".
  cloudflare_dns_import_ids = {
    "_domainconnect.dancegeekproductions.art CNAME"  = "a8352b0a8083ed08661ba44a12b2223b/61982c12aac0a1aff1520fb355d78cb3"
    "dancegeekproductions.art CNAME"                 = "a8352b0a8083ed08661ba44a12b2223b/ef108538211eb6fd45ac973cdc61b982"
    "www.dancegeekproductions.art CNAME"             = "a8352b0a8083ed08661ba44a12b2223b/9179cd8acf1f3082510b288493ef7059"
    "_railway-verify.api-dev.deejaytools.com TXT"    = "210ee7814003903a62dcb7e8d365de43/1ad7b44f68da4df93682ed11832ab8e5"
    "_railway-verify.api-dev.deejaytools.com TXT #2" = "210ee7814003903a62dcb7e8d365de43/ee5be47730c3ddcac5247352ca8e2d61"
    "_railway-verify.api.deejaytools.com TXT"        = "210ee7814003903a62dcb7e8d365de43/0cee155fe1f2ddd6b6eec89c8dc86f91"
    "_railway-verify.api.deejaytools.com TXT #2"     = "210ee7814003903a62dcb7e8d365de43/2a8d16ff3fd3068ad01df5dd8d35f3c8"
    "accounts.deejaytools.com CNAME"                 = "210ee7814003903a62dcb7e8d365de43/e7bb4d9ac01408e41642d57264263277"
    "api-dev.deejaytools.com CNAME"                  = "210ee7814003903a62dcb7e8d365de43/2e05f207a611396af9239d823031502a"
    "api.deejaytools.com CNAME"                      = "210ee7814003903a62dcb7e8d365de43/8ebc8dd4ff4a102430e111efcac1f2df"
    "clerk.deejaytools.com CNAME"                    = "210ee7814003903a62dcb7e8d365de43/ce656fb7e2b77f01ace9e0502e36f6e5"
    "clk._domainkey.deejaytools.com CNAME"           = "210ee7814003903a62dcb7e8d365de43/2df5b7f5848514adaf7ff5784d68a0f0"
    "clk2._domainkey.deejaytools.com CNAME"          = "210ee7814003903a62dcb7e8d365de43/22bbb6271ef39babb6c9d7e73ee2e5e1"
    "clkmail.deejaytools.com CNAME"                  = "210ee7814003903a62dcb7e8d365de43/c321bc20a2caca2c24bb1d61f3e10927"
    "deejaytools.com CNAME"                          = "210ee7814003903a62dcb7e8d365de43/9069547f2a131215a219e46edcb88cc2"
    "dev.deejaytools.com CNAME"                      = "210ee7814003903a62dcb7e8d365de43/2b149fb4cadf21ba9b592e19e67e2c8b"
    "www.deejaytools.com CNAME"                      = "210ee7814003903a62dcb7e8d365de43/a76970867b3c33b9a48667a1672f0db6"
    "_vercel.emberlabshq.app TXT"                    = "b96d22aab9f9bd297e93d09da2c2ac88/964160ccdea0c7cee5518ffab90d138c"
    "torch.emberlabshq.app CNAME"                    = "b96d22aab9f9bd297e93d09da2c2ac88/0b0a55e646fc0fb757a90745718c7ff7"
    "kaiano.fyi CNAME"                               = "973a1acc2064db9b190ef54c03df2f23/37e6868009d1f91c526d3767c713bbc6"
    "www.kaiano.fyi CNAME"                           = "973a1acc2064db9b190ef54c03df2f23/bc35e47400382097ba43b3d7626e985c"
    "_dmarc.kaianolevine.com TXT"                    = "1f0c5adaaf7879e2ac4d6c169a485895/94f4e55e27d60f946a0b16f123b8dfa4"
    "_railway-verify.api.kaianolevine.com TXT"       = "1f0c5adaaf7879e2ac4d6c169a485895/5e0403a386e839ff22a8b3d5a6e4fff0"
    "_railway-verify.dev-api.kaianolevine.com TXT"   = "1f0c5adaaf7879e2ac4d6c169a485895/35cbacb581b162a7177ce6d2660de261"
    "accounts.kaianolevine.com CNAME"                = "1f0c5adaaf7879e2ac4d6c169a485895/49090d1628dabcd073d037e692ca3fb3"
    "all.kaianolevine.com CNAME"                     = "1f0c5adaaf7879e2ac4d6c169a485895/8433ba3647f2821b71a6e030365f6349"
    "api.kaianolevine.com CNAME"                     = "1f0c5adaaf7879e2ac4d6c169a485895/01220cef623a2c21f7e3804da0a28f20"
    "brevo1._domainkey.kaianolevine.com CNAME"       = "1f0c5adaaf7879e2ac4d6c169a485895/7149712d8b20722c5c243a77a503cef4"
    "brevo2._domainkey.kaianolevine.com CNAME"       = "1f0c5adaaf7879e2ac4d6c169a485895/440ee7e35693c46eed8ae4d51d4d2c46"
    "career.kaianolevine.com CNAME"                  = "1f0c5adaaf7879e2ac4d6c169a485895/b2a694a8eea790c65ba5d08e81bd5894"
    "clerk.kaianolevine.com CNAME"                   = "1f0c5adaaf7879e2ac4d6c169a485895/b975c351c4a759c2e2300b7829ac8c09"
    "clk._domainkey.kaianolevine.com CNAME"          = "1f0c5adaaf7879e2ac4d6c169a485895/c033901c1ddd4065e8bec0509ba8e261"
    "clk2._domainkey.kaianolevine.com CNAME"         = "1f0c5adaaf7879e2ac4d6c169a485895/f042deeb22acb41ebb423873271ea6cf"
    "clkmail.kaianolevine.com CNAME"                 = "1f0c5adaaf7879e2ac4d6c169a485895/52c434eb2bc7abf23577e606b1bfa99c"
    "dev-api.kaianolevine.com CNAME"                 = "1f0c5adaaf7879e2ac4d6c169a485895/7afbad91e2bf266164182a4680842c3e"
    "dev.software.kaianolevine.com CNAME"            = "1f0c5adaaf7879e2ac4d6c169a485895/718050689d5eed65b96598a2f9354477"
    "dev.wcs.kaianolevine.com CNAME"                 = "1f0c5adaaf7879e2ac4d6c169a485895/fbcd3bd73a94a950919294f0875f1a89"
    "hub.kaianolevine.com CNAME"                     = "1f0c5adaaf7879e2ac4d6c169a485895/412b3b518abea649c94ee2a39943bed2"
    "kaianolevine.com CNAME"                         = "1f0c5adaaf7879e2ac4d6c169a485895/c9b7aad4dfb4774c0d345302c8858f2b"
    "kaianolevine.com MX"                            = "1f0c5adaaf7879e2ac4d6c169a485895/36e2c5682bed903e9831785f8256982d"
    "kaianolevine.com TXT"                           = "1f0c5adaaf7879e2ac4d6c169a485895/1ecc962aeba132385e094a02dcec0efd"
    "kaianolevine.com TXT #2"                        = "1f0c5adaaf7879e2ac4d6c169a485895/82cf4aef4b71535614b0eb81234c72e7"
    "software.kaianolevine.com CNAME"                = "1f0c5adaaf7879e2ac4d6c169a485895/0f6a258b1ab9323feb14ac56bcfd0f71"
    "tech.kaianolevine.com CNAME"                    = "1f0c5adaaf7879e2ac4d6c169a485895/6d1314c3b0b858c035e57693d3d4ba4e"
    "wcs.kaianolevine.com CNAME"                     = "1f0c5adaaf7879e2ac4d6c169a485895/5fdbbc06b74867c792bac16bd8b4be68"
    "www.kaianolevine.com CNAME"                     = "1f0c5adaaf7879e2ac4d6c169a485895/2dfd4e9cb53b4a2ce057acef75d3d2cc"
    "kwalla.dance CNAME"                             = "820408fee4063914e2bdc15f6a33412b/01d0abef0cd7b8021f52b2cc47bfa389"
    "www.kwalla.dance CNAME"                         = "820408fee4063914e2bdc15f6a33412b/48496f20a6ce2444e790efbc8f510f5a"
    "_dmarc.mnmusicmovement.com TXT"                 = "16eda36fbb6fc03e454eafc99c1c2bcc/7edeaf0c5eaf29d83b6ce39f09467770"
    "brevo1._domainkey.mnmusicmovement.com CNAME"    = "16eda36fbb6fc03e454eafc99c1c2bcc/be7ce5f64d9420124504531ad9b11a94"
    "brevo2._domainkey.mnmusicmovement.com CNAME"    = "16eda36fbb6fc03e454eafc99c1c2bcc/816e14edb4125c2a0241e12f3a7c6cd1"
    "mnmusicmovement.com TXT"                        = "16eda36fbb6fc03e454eafc99c1c2bcc/dd561c8796d1abeb2eddbc5a61c2b8b5"
    "www.mnmusicmovement.com CNAME"                  = "16eda36fbb6fc03e454eafc99c1c2bcc/4e8accac98f2407d9790f8ea13174c3a"
    "mnwcs.com CNAME"                                = "f02b1de4ea672bfb6844cd4885fb6fb5/31a3168e4af4d0b0d78929803525b51f"
    "www.mnwcs.com CNAME"                            = "f02b1de4ea672bfb6844cd4885fb6fb5/62d84105058e7176415fef3c83355de5"
    "_domainconnect.swingtacular.art CNAME"          = "e47355e5817fa876c4e9c2aab6037bcf/2f90cc2264ea3f66472d809c2578ae11"
    "dev.swingtacular.art CNAME"                     = "e47355e5817fa876c4e9c2aab6037bcf/7cbe239e5a1da3abd3cfec096e8aec35"
    "pay.swingtacular.art CNAME"                     = "e47355e5817fa876c4e9c2aab6037bcf/d078643c26e8a80b5d059f10cc29f40d"
    "swingtacular.art CNAME"                         = "e47355e5817fa876c4e9c2aab6037bcf/07ab2ed48ca5cf363626f492615b80a0"
    "swingtacular.art TXT"                           = "e47355e5817fa876c4e9c2aab6037bcf/7e0208d1dc3ab64b08212129be7b4cc0"
    "www.swingtacular.art CNAME"                     = "e47355e5817fa876c4e9c2aab6037bcf/4b07185d2a8d757bf73b240a40d09366"
    "_railway-verify.app.syncright.dev TXT"          = "531ff3c01cdf67b5d9b01dc19c8d98e0/3af0160a8395dcdfdca275ed012788b9"
    "app.syncright.dev CNAME"                        = "531ff3c01cdf67b5d9b01dc19c8d98e0/5195a8e9956f2f244f0294add67ea3c7"
    "_dmarc.wcsmn.com TXT"                           = "bc661db2a663cb9cf78a07706ffd7ab2/80331f58026ab293181a2c4a0838485f"
    "brevo1._domainkey.wcsmn.com CNAME"              = "bc661db2a663cb9cf78a07706ffd7ab2/d9cb1d08a1fbf89fcef9b363f0741c55"
    "brevo2._domainkey.wcsmn.com CNAME"              = "bc661db2a663cb9cf78a07706ffd7ab2/599243b1a535f611a17343b49da7425a"
    "dev.wcsmn.com CNAME"                            = "bc661db2a663cb9cf78a07706ffd7ab2/0fc95cb42bd679502b416b7e0ed9ade1"
    "wcsmn.com CNAME"                                = "bc661db2a663cb9cf78a07706ffd7ab2/587492d43f3a6642a85c9c325775a1d1"
    "wcsmn.com TXT"                                  = "bc661db2a663cb9cf78a07706ffd7ab2/8617f1e31872049766428c6a74aa2ed4"
    "www.wcsmn.com CNAME"                            = "bc661db2a663cb9cf78a07706ffd7ab2/66526fcb65909733db151610d971948e"
  }
}

import {
  for_each = local.cloudflare_dns_import_ids
  to       = cloudflare_dns_record.this[each.key]
  id       = each.value
}

import {
  to = cloudflare_ruleset.deejaytools_com_rate_limit
  id = "zones/210ee7814003903a62dcb7e8d365de43/2574137261c44cfcbf8dc01cf7975491"
}

import {
  to = cloudflare_ruleset.deejaytools_com_waf_custom
  id = "zones/210ee7814003903a62dcb7e8d365de43/95fa648d4f474541a7f3677474983b79"
}

import {
  to = cloudflare_ruleset.kaianolevine_com_rate_limit
  id = "zones/1f0c5adaaf7879e2ac4d6c169a485895/cdefddc595814bfea1b741b42e765b70"
}

import {
  to = cloudflare_ruleset.kaianolevine_com_redirect
  id = "zones/1f0c5adaaf7879e2ac4d6c169a485895/495755b76efd483f9fab76698c622c7a"
}

import {
  to = cloudflare_ruleset.kaianolevine_com_waf_custom
  id = "zones/1f0c5adaaf7879e2ac4d6c169a485895/b52ff1658357431cb37c07dd29d0052d"
}

import {
  to = cloudflare_ruleset.mnmusicmovement_com_rate_limit
  id = "zones/16eda36fbb6fc03e454eafc99c1c2bcc/029cfc2fe94840dabf2d74424fc268b4"
}

import {
  to = cloudflare_ruleset.swingtacular_art_rate_limit
  id = "zones/e47355e5817fa876c4e9c2aab6037bcf/2bdd26ba9cf14114babb351983d43e7d"
}

import {
  to = cloudflare_ruleset.account_bulk_redirect
  id = "accounts/0314578fe75f14199c748d0065583f93/93710d11826046bb96663de1907c9925"
}

import {
  to = cloudflare_list.dancegeekproductions
  id = "0314578fe75f14199c748d0065583f93/b8f537e5b6b54aaeaca3df57f26a90c0"
}

import {
  to = cloudflare_list.kaianolevine
  id = "0314578fe75f14199c748d0065583f93/a54aa5a56344457986808b9f9877f630"
}

import {
  to = cloudflare_list.swingtacular
  id = "0314578fe75f14199c748d0065583f93/76bf85d70606462591fd754ad058c797"
}

import {
  to = cloudflare_list.wcsmn_com
  id = "0314578fe75f14199c748d0065583f93/4abfae514533448cbfd7edb11ed1a309"
}
