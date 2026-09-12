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
