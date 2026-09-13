# Nextcloud docker-host → k8s migration

> **v3 (2026-09-13) — MERGE INTO PROD (current, supersedes v2 below).**
> Operator pivot: do NOT stand up a second instance. Merge the docker-host
> instance (`nextcloud.h4.ddnss.org`, NC31/MariaDB) INTO the existing prod
> k8s Nextcloud (NC34/CNPG-PG), keeping all 27 users; only **h4xx → lukasf**
> is identity-mapped. v2 (separate instance) and v1 (merge) are kept below
> for reference.

## Current state (2026-09-13, autonomous session)

**DONE**
- **Apps**: 11 ddnss third-party apps added to the prod seed + enabled
  (calendar_news, carnet, cospend, deck, gpoddersync, groupfolders,
  impersonate, news, nextpod, previewgenerator, tasks) — commit `7568ff2`,
  zero-downtime. `appstoreenabled` stays false.
- **Data PVC**: prod `nextcloud-data-hdd` expanded to **5 Ti** (4.9 T free);
  RWX `longhorn-disk-rwx-2r`.
- **Source inventory**: 27 users, 4 groups, 151 shares, 1 groupfolder,
  encryption OFF, instanceid `occ7puli0xhw`, ~2.3 TB user data + 362 G
  appdata. h4xx="Lukas" 326 G. Password hashes portable (argon2id/bcrypt).

**IN PROGRESS — bulk data copy (resumable, runs a day+)**
- A migration pod `nc-migration` (namespace nextcloud, pinned to **srv9**,
  mounts `nextcloud-data-hdd` RWX) rsync-pulls from docker-host
  (`root@10.0.11.22:/mnt/dockerstorage/nextcloud/data`) via an ephemeral key.
- **3-way parallel, `--inplace --partial --whole-file`, bwlimit 20 MB/s/stream**
  (single-stream is ~6 MiB/s — small files over Longhorn RWX-NFS are
  latency-bound; parallelism is the lever, not tar).
- Targets: **h4xx → `…/08f11a25…/files/h4-import/`** (lukasf, mapping known);
  all others → **`/data/_import_ddnss/<uid>/files/`** (staging).
- Logs: `/data/.migration/<uid>.status` + `.log`; done marker
  `/data/.migration/_ALL.status`.
- **Resume after interruption**: `kubectl -n nextcloud exec nc-migration --
  setsid sh -c 'sh /root/migrate.sh >/dev/null 2>&1 &'` (idempotent; rsync
  skips finished files). If the pod is gone, recreate from
  `scratchpad/nc-migration-pod-srv9.yaml` + re-`cp` `one.sh`/`migrate.sh`, and
  re-authorize the pubkey on docker-host.

## Identity: KEEP FRIENDLY UIDS (resolved 2026-09-13) — the earlier "UUID blocker" was wrong

Discovered facts on prod: all users are `backend: Database` (local, incl.
Lukas); `oidc_login_attributes['id'] => 'sub'` (why oidc-created uids are
UUIDs); `oidc_login_auto_redirect => false` (password form IS available);
`user_ldap` 1.25.0 enabled but UNCONFIGURED; **LLDAP is live** (ns lldap).

So we CAN keep the source friendly uids (`bj`,`vivian`,…, `lukasf` exists):
create the 27 as **local users with friendly uids + their portable password
hashes** → data lands in `data/<uid>/` (matches the `_import_ddnss/<uid>/`
staging layout; just move the parent). No UUID remap. Form login works today.
h4xx still merges into existing `lukasf` (08f11a25).

**Add all 27 to LLDAP** (friendly uids) and wire prod's dormant `user_ldap`
→ LLDAP (username attr = uid) so NC uses friendly uids natively + authelia
(LDAP-backed) gives SSO. LLDAP = identity source of truth.

**Fork to decide with operator (touches EXISTING users + live org auth — do NOT
do unattended):**
- (a) Non-disruptive: friendly local/LDAP users + password(form) login now; add
  to LLDAP; DEFER oidc-uid unification. Lukas stays `08f11a25`.
- (b) Coordinated cutover: remap Lukas `08f11a25`→`lukasf`, set oidc
  `id=preferred_username`, authelia issues `preferred_username=uid` → unified
  friendly-uid SSO for everyone.

Provisioning caveat: LLDAP stores its own credentials — NC password hashes are
not importable into LLDAP; users either reset in LLDAP or keep NC-local
password auth (option a). Decide per path.

## Post-copy runbook (per user, once its UUID is known)

1. `occ user:add <uid>` (or OIDC first-login) → note the prod data dir UUID.
2. Move staged files into place: `mv /data/_import_ddnss/<uid>/files/*
   /data/<UUID>/files/` (same volume → instant), `chown -R 33:33`.
3. `occ files:scan --path="<UUID>/files"` (registers files in the DB).
4. Password: copy the source `oc_users.password` hash (portable) into prod
   `oc_users.password` for that uid so old passwords work (or leave OIDC-only).
5. Shares (151 total) + groupfolder: re-create via `occ`/DB — file IDs differ
   after scan, so shares can't be lifted 1:1; script by (owner, path, target).

### h4xx → lukasf (pilot, UUID known — do this first when copy of h4xx finishes)
1. `occ files:scan --path="08f11a25-d9f3-487d-8a31-0a15df131ca1/files"`
2. Verify h4-import/ appears in Lukas's account (web/DAV).
3. (Optional) set lukasf's local password from h4xx's hash so "login via
   password" works alongside authelia — **operator to confirm** (auth change).

## Cleanup when done
- Delete pod `nc-migration` + secret `nc-migration-sshkey` (nextcloud ns);
  shred `scratchpad/nc-mig-key*`; **remove the migration pubkey from
  `root@docker-host:~/.ssh/authorized_keys`**.

---

# Migration plan v2: docker-host Nextcloud → k8s as a SECOND instance

Status: **PLAN v2** (2026-09-12). Strategy pivoted by operator: **move, not
merge** — the old instance becomes its own Nextcloud in a new namespace,
reusing the existing flux-apps `apps/nextcloud` definition, DB converted
MySQL→Postgres. The v1 user-merge plan is retired (appendix).

## Why this approach wins

- **App passwords / device tokens SURVIVE**: carrying `config.php`'s
  `secret`, `passwordsalt`, `instanceid` keeps every token hash + encrypted
  payload valid — 27 users' devices keep working (impossible in a merge).
- Passwords, shares (incl. public link tokens), calendars, contacts,
  quotas, groups — all survive automatically (same DB, converted).
- `appdata_<instanceid>` moves along → previews survive, no regen storm.
- No h4xx→lukasf merge now; account unification = optional later project.

## Facts (discovered)

- Source: docker-host (icarus VM, 10.0.11.22), NC **31.0.14**, MySQL, **27
  users**, data `/var/www/html/data` (size: phase B step 0), domain
  `nextcloud.h4.ddnss.org`.
- Target: namespace **`nextcloud-h4`** (proposal) on homelab-prod, from
  `flux-apps/apps/nextcloud` (chart 9.2.6 / NC 34.0.3), CNPG PG18, own
  valkey, **OIDC disabled** (`nextcloud_oidc: "disabled"` — the existing
  NEXTCLOUD_OIDC_PROVIDER gate handles it; client secret is optional).

## Phase A — instantiability (DONE 2026-09-12, commit 7b8c5f6)

- flux `targetNamespace` rewrites all 30 hardcoded `namespace: nextcloud`
  resources (all namespace-scoped, verified).
- The only two cross-reference FQDNs parametrized:
  `nextcloud-postgres-rw.${nextcloud_namespace:=nextcloud}.svc` +
  metrics-exporter target. Defaults keep prod byte-identical (verified: no
  helm diff on reconcile).
- Host/domain needs NO new var: the nextcloud-h4 Kustomization overrides
  `delegating_domain: h4.ddnss.org` + `public_host_suffix: ""` in its own
  substitution scope → host renders `nextcloud.h4.ddnss.org`.

Remaining wiring (Phase A2, ~1 commit each side):
- flux-cluster: `base/kustomizations/infra/nextcloud-h4.yaml` — same
  `path: ./apps/nextcloud`, `targetNamespace: nextcloud-h4`, dependsOn like
  nextcloud, `postBuild.substituteFrom: [base-config, nextcloud-h4-config]`
  (later source wins → per-instance values). Homelab overlay only
  (staging/testing keep one instance).
- namespaces app += `nextcloud-h4`.
- Overlay SOPS secrets (namespace nextcloud-h4): `nextcloud-admin`
  (carry old admin creds), `nextcloud-valkey`, postgres backup credentials
  (same MinIO key), and **instance-secrets config file** carrying old
  `secret` + `passwordsalt` + `instanceid` (the token-survival piece;
  mounted as an extra `*.config.php`).
- nextcloud-h4-config values: namespace, domains, sizes (data PVC sized to
  source du + growth), storage classes, HPA (1-2 pods), backup
  `serverName: nextcloud-h4-postgres` + fresh `generation g<date>/`
  (the g20260616 lesson: never delete a generation without checking the
  live destinationPath).

## Phase B — rehearsal (in-cluster, zero risk to the live old instance)

0. `occ encryption:status` on source (encrypted-at-rest would change the
   rsync story); data `du` per top-dir; app list diff vs our seeded apps.
1. Bulk rsync (repeatable, online): docker-host `data/` → new data PVC,
   **including `appdata_<instanceid>`**; `-a` semantics (mtimes matter for
   files:scan; NC data has no hardlinks).
2. DB conversion rehearsal, fully in-cluster:
   - `mysqldump` → throwaway mariadb pod in nextcloud-h4.
   - Temp NC **31.0.14** deployment (carried config.php; DB=temp mariadb;
     data=the real PVC): `occ db:convert-type pgsql …` → into CNPG
     `nextcloud-postgres` (nextcloud-h4 ns).
   - Step the temp deployment's image 31→32→33→**34.0.3**, `occ upgrade`
     each (NC forbids skipping majors). Fix app incompat as found — that is
     the rehearsal's purpose.
   - Smoke-test via port-forward: login with OLD passwords, files, DAV,
     share links, and **a client with an OLD app password** (proves token
     survival end-to-end).
3. Record timings → cutover window size (expect: dump+convert minutes for a
   small DB + upgrade chain 10–20 min + delta rsync).

## Phase C — cutover (downtime = old instance only)

1. Old: `occ maintenance:mode --on`.
2. Final delta rsync; fresh mysqldump → repeat rehearsed convert + upgrade
   chain into a CLEAN database (drop rehearsal DB first).
3. Flip the flux HR live (chart-managed NC 34), verify the smoke-test list.
4. Operator: DNS/ingress for `nextcloud.h4.ddnss.org` → cluster.
5. Old stack stays in maintenance mode 2–4 weeks (rollback; restic archive
   of docker-host already exists), then decommission.

## Parked / future

- Router DNS DoH (`/ip dns set use-doh-server=https://1.1.1.1/dns-query
  verify-doh-cert=yes`) — fixes residual authelia session-save timeouts,
  no privacy loss (rides Proton).
- Authelia/LLDAP for the 27 users + instance unification — blocked
  conceptually by oidc_login sub-UUID mapping (prod uids ARE UUIDs, e.g.
  `08f11a25-…` = Lukas); solve mapping before any SSO for migrated users.
- NC 35 for both instances when the image ships (unlocks external v10).

## Appendix — retired v1 (merge) findings worth keeping

- Password hashes are portable across instances/DB engines (self-contained
  argon2id/bcrypt); only pre-2015 legacy hashes depend on `passwordsalt`.
- App passwords/TOTP are instance-`secret`-bound: unmergeable, movable.
- UID collision check 2026-09-12: zero overlap between the 27 source uids
  and prod's 5 (admin + 4 oidc-sub UUIDs).

## Phase B0 results (discovered 2026-09-13)

- **Server-side encryption: DISABLED** — plain rsync copies real files; no
  `encryption:decrypt-all` needed. Move-not-merge confirmed viable.
- **Data: 2.0 TB + appdata 362 GB** (`appdata_occ7puli0xhw` → instanceid
  `occ7puli0xhw`, matches the captured config.php secret set). Size the h4
  data PVC ~**3 Ti**; on the 2-replica Longhorn disk class that is ~6 TB of
  USB-disk capacity on srv2/srv8 — consider NAS-backed storage for h4 data,
  or accept the capacity hit.
- **~40 enabled apps**, many NOT in our curated seed (deck, cospend,
  onlyoffice, news, carnet, libresign, recognize, fulltextsearch
  (+elasticsearch), groupfolders, organization_folders, paperless, nextpod,
  gpoddersync, cookbook, maps, …). **Implication:** prod runs
  `appstoreenabled=false` + seeds a fixed list; h4 must instead run with the
  **appstore ENABLED** and migrate the source `custom_apps/` dir with the
  data, or the DB's 40 app rows error/disable. Add a per-instance
  `nextcloud_appstore_enabled:=false` override (true for h4) and include
  `custom_apps/` in the Phase B rsync. fulltextsearch+elasticsearch implies
  an Elasticsearch dependency to stand up or disable post-move.

## App management on h4 = GitOps (operator decision 2026-09-13)

h4 keeps `appstoreenabled=false` and seeds ALL third-party apps declaratively
(pinned URL+sha256+version via the fetch_app initContainer pattern), NOT
UI/appstore-managed. Mechanism to build: parametrize apps/nextcloud's seed so
the app list is per-instance (prod = curated 9; h4 = full set). Auto-generate
the pinned catalog from the Nextcloud appstore API (per app: NC34-compatible
release -> download URL -> sha256).

30 third-party apps in custom_apps/ (versions are NC31-era; pick NC34-compatible
at seed time):

SELF-CONTAINED (pure seed): calendar, calendar_news, contacts, tasks, deck,
cospend, groupfolders, groupfolder_tags, groupfolder_filesystem_snapshots,
organization_folders, news, cookbook, maps, passwords, previewgenerator,
impersonate, drawio, gpoddersync, nextpod, carnet, riotchat, mail.

BACKEND-DEPENDENT (need a companion service — DECIDE per app: deploy or disable):
- onlyoffice 9.13.0 -> OnlyOffice Document Server deployment
- fulltextsearch 31.0.1 + files_fulltextsearch 31.0.0 + fulltextsearch_elasticsearch
  31.0.2 -> Elasticsearch instance
- files_fulltextsearch_tesseract 27.0.1 -> tesseract OCR in image
- recognize 9.0.9 -> ~2GB ML models + nodejs/tensorflow (heavy CPU/GPU)
- libresign 11.6.0 -> Java + JSignPDF + CFSSL backend
- integration_paperless 1.0.10 -> external Paperless-ngx instance

Note: appdata_occ7puli0xhw (362G) includes previewgenerator thumbnails +
recognize models + fulltextsearch index — migrating it preserves those.

## App scope FINALIZED (operator 2026-09-13) — zero companion services

DROP (10, not migrated; app:remove on source before final dump, exclude their
appdata from rsync): onlyoffice, fulltextsearch, files_fulltextsearch,
fulltextsearch_elasticsearch, files_fulltextsearch_tesseract, recognize,
libresign, riotchat, drawio, integration_paperless. => NO Elasticsearch /
OnlyOffice DS / Paperless / ML runtime / Java needed. User files (onlyoffice/
libresign docs) are plain files, untouched; only the app FEATURES + regenerable
indexes/models are dropped.

SEED via GitOps (20, all self-contained, appstore stays false): calendar,
calendar_news, carnet, contacts, cookbook, cospend, deck, gpoddersync,
groupfolders, groupfolder_tags, groupfolder_filesystem_snapshots,
organization_folders, mail, maps, news, nextpod, impersonate, passwords,
previewgenerator, tasks.

Build: per-instance seed app-list in apps/nextcloud (prod curated / h4 = these
20), pinned URL+sha256+version auto-generated from the appstore API for the
NC34-compatible release of each. appstoreenabled=false on h4 too.
