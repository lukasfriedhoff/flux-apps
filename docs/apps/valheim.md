# Valheim

A Valheim dedicated server running in the homelab cluster. Game traffic is
published through a MetalLB VIP, worlds live on Longhorn with a second replica,
and operations (backup, restore, restart, status) are driven from a web UI
behind Authelia.

Unlike [icarus](../../apps/icarus), Valheim ships a **native Linux server**, so
there is no custom image or build pipeline: this runs the upstream
`lloesche/valheim-server` image through the Harbor ghcr proxy-cache, pinned to
an immutable `sha-*` tag.

> **This repository is public — never commit the join password, the public DNS
> name, or any other credential into these docs.** Both live in the
> `valheim-credentials` SOPS secret; the commands below read them at runtime.

---

## For players

| What | Value |
|------|-------|
| Server name | `h4xx Valheim` (as shown in the in-game browser) |
| World | `Midgard` |
| Slots | 10 (Valheim's hard maximum) |
| Crossplay | Enabled — the server is listed publicly |

**Joining.** In Valheim choose *Start Game → (character) → Join Game* and look
for **h4xx Valheim** under the **Community** tab, then enter the join password.
If you prefer a direct connect, use *Join IP* with the server address and port
`2456`.

The join password and the server address are **not written down in this repo** —
ask the admin, or if you have cluster access:

```sh
kubectl -n valheim get secret valheim-credentials -o jsonpath='{.data.server_pass}' | base64 -d; echo
kubectl -n valheim get secret valheim-credentials -o jsonpath='{.data.public_host}' | base64 -d; echo
```

**Can't find the server in the browser?** That is almost always because the
server is running an outdated build — Valheim hides outdated servers from
clients entirely. See [Updates](#updates) below; it normally self-heals within
15 minutes of a game patch.

---

## For admins

Two web UIs, both published through the Cloudflare tunnel and gated by Authelia:

| URL | Purpose | Required group |
|-----|---------|----------------|
| `https://valheim.h4xx.io` | OliveTin — operational actions | `valheim-admins` or `valheim-users` |
| `https://valheim-files.h4xx.io` | Filebrowser over `/config` (worlds, admin lists) | `valheim-admins` |

Accounts and groups live in LLDAP (`https://lldap.h4xx.io`). Add a person to
`valheim-admins` there to grant access; nothing in this repo needs changing.

### OliveTin actions

| Action | What it does |
|--------|--------------|
| **Server status (who is online)** | Reads the server's `status.json` — current state and connected players. |
| **Backup now** | Creates a one-off Job from the nightly backup CronJob. |
| **List snapshots** | `restic snapshots --compact` against the S3 repository. |
| **Restart server** | Rolling restart. Also triggers a Steam update check on boot. |
| **Check Steam listing** | Confirms the server is registered with Steam's master list on the expected game port. |
| **Restore snapshot** | **Stops the server**, restores the chosen restic snapshot over `/config`, then starts it again. Destructive — take a fresh backup first. |

### In-game admin rights

In-game admin (`/kick`, `/ban`, `/save`, spawn commands) is **separate** from
web-UI access: Valheim identifies admins by **SteamID64**, not by directory
account. Add IDs to `valheim_adminlist_ids` (space separated) in the homelab
overlay of `flux-cluster` and reconcile:

```yaml
valheim_adminlist_ids: "76561198000000001 76561198000000002"
```

A player can find their own SteamID64 at `steamcommunity.com/my/profile` →
*Edit Profile* → the numeric URL, or via any SteamID lookup site.

---

## How it is wired

```
players ──UDP 2456/2457──▶ router DNAT ──▶ MetalLB VIP ──▶ valheim pod (srv9)
                                            10.1.20.43
```

- **Publishing.** `valheim-game` is a `LoadBalancer` Service holding a pinned
  MetalLB VIP with `externalTrafficPolicy: Local`, so players' real source IPs
  reach the server and the VIP is announced from whichever node runs the pod.
  The router's DNAT targets the **VIP**, not a node — moving the server between
  nodes needs no router change.
- **Ports.** UDP `2456` (game) and `2457` (Steam query). The Service port and
  the container port must stay equal: Steam advertises whatever port the server
  binds, so a mismatch makes the server unreachable while looking healthy.
- **Node pin.** `valheim_node` exists for Longhorn replica locality only.
- **Storage.** `valheim-config` (worlds and admin lists; a second Longhorn
  replica is pinned with the `longhorn.h4xx.io/replica-count` annotation) and
  `valheim-server` (the steamcmd install — re-downloadable, single replica).
- **Health probes** run a real **A2S query** against the query port rather than
  checking that a process exists. A wedged server keeps its PID and its HTTP
  status page while refusing every join; only a live protocol answer proves it
  is actually joinable.

## Backups

Two layers, deliberately:

1. **In-container world zips** every 6 hours into `/config/backups`, kept 3 days.
   These are world-consistent artifacts written by the image itself.
2. **Nightly restic backup** of the whole `/config` volume (including those
   zips) to S3, `keep-daily 14` / `keep-weekly 8`.

Restore via the OliveTin **Restore snapshot** action, which stops the server
first — never restore over a running world.

The backup job only runs `restic init` when the repository genuinely does not
exist (restic exit code `10`). Any other failure aborts loudly: a transient S3
outage must never be mistaken for an uninitialised repository.

## Updates

Update checks run on `valheim_update_cron` (default every 15 minutes) and only
fire when the server is **empty** (`UPDATE_IF_IDLE`), so a patch never kicks
players mid-session. This is intentionally more automatic than icarus's manual
gate, for two reasons: an outdated Valheim server is invisible to clients, and
upstream's updater leaves the existing install untouched when Steam fails.

Bump the server image by changing `valheim_image` in `flux-cluster` to a newer
immutable `sha-*` tag. Tags are not dated — resolve which one `latest` currently
points at by comparing manifest digests on ghcr.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Server missing from the in-game browser | Outdated build. Check the update logs; restart to force a check. |
| Pod never becomes ready | The startup probe waits for a live A2S answer. First boot downloads the server and generates the world — allow up to 20 minutes. |
| Players connect but cannot join | Port mismatch: the Service port must equal the container port, or Steam advertises the wrong endpoint. |
| Backup job fails | Check free space on the S3 target first — MinIO reports a full filesystem as `Resource requested is unreadable`, not as a capacity error. |
| Web UI returns 401 | The account is not in `valheim-admins` / `valheim-users` in LLDAP. |

Useful commands:

```sh
kubectl -n valheim logs deploy/valheim --tail=50
kubectl -n valheim get svc valheim-game          # VIP + ports
kubectl -n valheim get pvc                       # world + server volumes
```

## Configuration

All keys are `valheim_*` in `flux-cluster` (`base/base-config.yaml` for
defaults, the cluster overlay for per-cluster values). See
[`examples/apps/valheim/base-config.defaults.yaml`](../../examples/apps/valheim/base-config.defaults.yaml)
for the full list with defaults. The most commonly changed ones:

| Variable | Purpose |
|----------|---------|
| `valheim_server_name` / `valheim_world_name` | Browser name and world file |
| `valheim_adminlist_ids` | SteamID64s with in-game admin rights |
| `valheim_image` | Pinned upstream image tag |
| `valheim_vip` | MetalLB address for game traffic |
| `valheim_update_cron` / `valheim_update_if_idle` | Update check schedule and idle gating |
| `valheim_backup_cron` / `valheim_backup_keep_*` | restic schedule and retention |

Changing the **join password** means editing the SOPS secret and restarting the
server (it is written into the server config at boot):

```sh
cd flux-cluster/overlays/homelab/secrets
sops set valheim-credentials.yaml '["stringData"]["server_pass"]' '"<new password>"'
# commit + push, then:
kubectl -n valheim rollout restart deployment/valheim
```

Valheim requires the password to be at least 5 characters and it must not be a
substring of the server or world name.

## Tests

`apps/valheim/tests/verify-valheim-stack.sh` asserts the invariants that have
bitten this stack or its sibling: service/container port equality, A2S-based
probes on both the startup and liveness paths, the `Recreate` strategy (one
world, one writer), idle-gated updates, the pinned replica count on the world
volume, the restic init gate, authelia-gated UIs, and `${quote}` wrapping on
cron values (kustomize drops quotes that only matter after Flux substitution,
and a cron starting with `*` then parses as a YAML alias).
