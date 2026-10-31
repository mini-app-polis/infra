# Spotify's refresh token, in a project of its own.
#
# api-kaianolevine-com renews deejay-cog's Spotify refresh token itself (the
# re-auth link in its reminders) and writes it to Doppler with a service
# token, DOPPLER_SPOTIFY_WRITE_TOKEN. A service token reaches a whole
# config, so the token and its sign-in date live apart from the vault, in
# spotify / prd, and the write token is scoped to that config: it can read
# and write those two values and nothing else.
#
# Every reader references them here, from each of its configs, rather than
# in the vault: Doppler refuses a reference to a reference, so the vault
# cannot stand in between.

locals {
  spotify = "spotify"

  # The names whose value is in spotify / prd rather than the vault are
  # local.spotify_names, in spotify_names.tf.json: JSON so the root can read
  # them too, and leave them out of every Lambda's SETTINGS_ALLOWLIST.
}

resource "doppler_project" "spotify" {
  name        = local.spotify
  description = "deejay-cog's Spotify refresh token and its sign-in date, written by api-kaianolevine-com's re-auth. Layout in mini-app-polis/infra doppler/."
}

resource "doppler_environment" "spotify" {
  project          = doppler_project.spotify.name
  slug             = "prd"
  name             = local.environments["prd"]
  personal_configs = false
}
