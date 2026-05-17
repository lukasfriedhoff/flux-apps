# Authelia E2E

This test exercises the testing overlay through login-surface checks and (optionally) full Authelia-authenticated OIDC flows.

## What it checks

1. Unauthenticated login-surface checks:
   - Authelia login page responds.
   - Every ForwardAuth-protected ingress returns an auth gate response (401/302).
   - OIDC entrypoints redirect to Authelia for:
     - Nextcloud
     - Grafana
     - Matrix
   - Matrix login API advertises the Authelia SSO provider (`oidc-authelia`).
   - Jellyseerr public settings (via port-forward) advertise an Authelia OIDC provider.
2. If `AUTHELIA_PASSWORD` is set, authenticated checks:
   - First-factor login works for the configured user.
   - Protected ingresses return HTTP 200 with the session cookie.
   - OIDC consent + callback succeeds for:
   - Nextcloud
   - Jellyfin
   - Grafana
   - Matrix
   - Jellyseerr
3. Post-login app smoke checks:
   - Grafana `/api/health`
   - Jellyseerr `/api/v1/auth/me`
   - Nextcloud dashboard response (including SQL error guard)
   - Jellyfin `/System/Info/Public`
   - Matrix `/_matrix/client/versions`
   - Element `config.json` homeserver target
   - Immich `/api/server/ping`

## Run

```bash
AUTHELIA_PASSWORD='<testuser-password>' \
apps/authelia/tests/run-authelia-e2e.sh
```

Run unauthenticated login-surface checks only:

```bash
apps/authelia/tests/run-authelia-e2e.sh
```

Optional environment overrides:

- `PUBLIC_HOST_SUFFIX` (default: `-testing`; e.g. `-staging`)
- `DELEGATING_DOMAIN` (default: `h4xx.io`)
- `STATUS_HOST` (default derived from suffix, e.g. `testing.h4xx.io`)
- `AUTHELIA_BASE` (default: `https://auth-testing.h4xx.io`)
- `AUTHELIA_USER` (default: `testuser`)
- `AUTHELIA_TARGET_URL` (default: `https://testing.h4xx.io/`)
- `AUTHELIA_LOCAL_TIMEOUT` (default: `30`)
- `AUTHELIA_REQUIRE_PASSWORD` (default: `false`; set `true` to fail if password is missing)
- `JELLYSEERR_PORT_FORWARD_NAMESPACE` (default: `media`)
- `JELLYSEERR_PORT_FORWARD_LOCAL_PORT` (default: `15075`)
