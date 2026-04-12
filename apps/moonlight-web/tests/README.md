# Moonlight Web E2E Tests

This directory contains KUTTL-based smoke tests for `moonlight-web` in the `media` namespace.

## Framework

- [KUTTL](https://kuttl.dev/) (free and open source)

## What is validated

1. Deployment `moonlight-web` becomes `Available`.
2. Ingress annotation contains Authelia middleware (`traefik-authelia-forwardauth@kubernetescrd`).
3. Container env contains `FORWARDED_HEADER=X-Forwarded-User`.
4. Port-forwarded service root (`/`) responds with HTTP 200 and contains `Moonlight`.

## Run

```bash
apps/moonlight-web/tests/run-moonlight-web-e2e.sh
```

Optional environment overrides:

- `NAMESPACE` (default: `media`)
- `TIMEOUT` (default: `300`, seconds)
- `MOONLIGHT_E2E_LOCAL_PORT` (default: `18080`)

