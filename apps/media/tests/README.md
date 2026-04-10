# Media E2E Tests

This directory contains KUTTL-based end-to-end tests for the Arr stack in the `media` namespace.

## Framework

- [KUTTL](https://kuttl.dev/) (free and open source)

## What is validated

For each app (`sonarr`, `radarr`, `lidarr`, `readarr`) the test checks:

1. API key is present in `/config/config.xml`.
2. `system/status` endpoint is reachable.
3. At least one root folder exists.
4. At least one indexer exists.
5. `indexer/testall` reports all indexers as valid.
6. At least one download client exists.
7. `downloadclient/testall` reports all clients as valid.
8. `queue/status` reports `errors == false`.

## Run

```bash
apps/media/tests/run-media-arr-e2e.sh
```

Optional environment overrides:

- `NAMESPACE` (default: `media`)
- `TIMEOUT` (default: `300`, seconds)
