# Media E2E Tests

This directory contains KUTTL-based end-to-end tests for the media stack in the `media` namespace.

## Framework

- [KUTTL](https://kuttl.dev/) (free and open source)

## What is validated

### ARR checks

For each app (`sonarr`, `radarr`, `lidarr`, `readarr`) the test checks:

1. API key is present in `/config/config.xml`.
2. `system/status` endpoint is reachable.
3. At least one root folder exists.
4. At least one indexer exists.
5. `indexer/testall` reports all indexers as valid.
6. At least one download client exists.
7. `downloadclient/testall` reports all clients as valid.
8. `queue/status` reports `errors == false`.

### Prowlarr checks

The ARR test step also validates Prowlarr:

1. Prowlarr API is reachable.
2. If secret `prowlarr-private-trackers` contains credentials for a supported private tracker, that indexer must exist and be enabled.

Supported optional private tracker keys:

- `torrentsyndikat_api_key`
- `flood_api_key`
- `immortuos_username`, `immortuos_password`
- `speedmasterhd_username`, `speedmasterhd_password`
- `world_of_tomorrow_username`, `world_of_tomorrow_password`, optional `world_of_tomorrow_pin`
- `explosiv_world_username`, `explosiv_world_password`
- `torrentleech_username`, `torrentleech_password`, optional `torrentleech_alt_2fa_token`
- `iptorrents_cookie`, optional `iptorrents_user_agent`
- `filelist_username`, `filelist_passkey`
- `beyondhd_api_key`, `beyondhd_rss_key`
- `passthepopcorn_api_user`, `passthepopcorn_api_key`
- `aither_api_key`
- `blutopia_api_key`
- `digitalcore_api_key`
- `hdtorrentsit_api_key`

### Jellyfin checks

The Jellyfin E2E step:

1. Downloads free sample media for movie/tv/music into `/media/e2e-test/**`.
2. Ensures Jellyfin libraries exist for those paths.
3. Triggers a library refresh.
4. Verifies Jellyfin indexed movie/episode/audio items.
5. Probes each streaming endpoint and verifies non-zero bytes are returned.

### Jellyseerr checks

The Jellyseerr E2E step verifies:

1. `/app/config/settings.json` has `public.initialized == true`.
2. Jellyseerr settings enable OIDC login and include an `authelia` OIDC provider.
3. Jellyseerr settings include non-empty `radarr` and `sonarr` service configuration.
4. Live API (`/api/v1/settings/public`) reports `initialized == true` and exposes OIDC providers.

### Jellyseerr login checks

The Jellyseerr login E2E step validates a real login flow:

1. Port-forwards Jellyseerr service.
2. Verifies `initialized == true`.
3. Logs in using either:
   - `mode=local` via `/api/v1/auth/local`, or
   - `mode=jellyfin` via `/api/v1/auth/jellyfin`.
4. Confirms `/api/v1/auth/me` returns a valid user.

Authentication for Jellyfin checks is required:

- Preferred: set `JELLYFIN_API_KEY`.
- Or provide `JELLYFIN_USERNAME` + `JELLYFIN_PASSWORD`.
- Or create secret `jellyfin-e2e-auth` in namespace `media` with keys:
  - `api_key` (preferred), or
  - `username` and `password`.

Example secret:

```bash
kubectl -n media create secret generic jellyfin-e2e-auth \
  --from-literal=username='<user>' \
  --from-literal=password='<password>'
```

In GitOps-managed clusters, define this secret in the cluster repo (SOPS-encrypted)
instead of creating it manually.

For Jellyseerr login tests, optional secret `jellyseerr-e2e-auth`:

```bash
kubectl -n media create secret generic jellyseerr-e2e-auth \
  --from-literal=mode='local' \
  --from-literal=email='jellyseerr-e2e@example.invalid' \
  --from-literal=username='jellyseerr-e2e' \
  --from-literal=password='<jellyseerr-password>'
```

When `mode=local`, the test now bootstraps/updates a local Jellyseerr user from
that secret before executing the login check.

## Run

```bash
apps/media/tests/run-media-arr-e2e.sh
```

Optional environment overrides:

- `NAMESPACE` (default: `media`)
- `TIMEOUT` (default: `600`, seconds)
- `JELLYFIN_API_KEY`
- `JELLYFIN_USERNAME`
- `JELLYFIN_PASSWORD`
- `JELLYFIN_E2E_SECRET_NAME` (default: `jellyfin-e2e-auth`)
- `JELLYFIN_E2E_LOCAL_PORT` (default: `18096`)
- `REQUIRE_JELLYFIN_AUTH` (`true` to fail when Jellyfin auth credentials are missing; default skips authenticated checks)
- `JELLYSEERR_E2E_LOCAL_PORT` (default: `15055`)
- `JELLYSEERR_AUTH_E2E_LOCAL_PORT` (default: `15056`)
- `JELLYSEERR_E2E_SECRET_NAME` (default: `jellyseerr-e2e-auth`)
- `JELLYSEERR_AUTH_MODE` (`local` or `jellyfin`)
- `JELLYSEERR_LOCAL_EMAIL` (for `local` mode)
- `JELLYSEERR_LOCAL_USERNAME` (optional for `local` mode)
- `JELLYSEERR_JELLYFIN_USERNAME` (for `jellyfin` mode)
- `JELLYSEERR_AUTH_PASSWORD`
- `REQUIRE_JELLYSEERR_AUTH` (`true` to fail when Jellyseerr auth credentials are missing; default skips login step)
