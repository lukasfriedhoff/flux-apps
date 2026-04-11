# Authelia E2E

This test exercises the testing overlay through real Authelia login and OIDC flows.

## What it checks

1. First-factor login works for the configured test user.
2. ForwardAuth-protected ingresses return HTTP 200 with the Authelia session.
3. OIDC consent + callback succeeds for:
   - Nextcloud
   - Jellyfin
4. Post-login app smoke checks:
   - Grafana `/api/health`
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

Optional environment overrides:

- `AUTHELIA_BASE` (default: `https://auth-testing.h4xx.io`)
- `AUTHELIA_USER` (default: `testuser`)
- `AUTHELIA_TARGET_URL` (default: `https://testing.h4xx.io/`)
- `AUTHELIA_LOCAL_TIMEOUT` (default: `30`)
