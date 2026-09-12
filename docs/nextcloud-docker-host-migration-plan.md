# Migration plan: docker-host Nextcloud → k8s Nextcloud (user merge)

Status: **PLAN** (2026-09-12). Discovery done read-only; nothing migrated yet.

## Source (discovered)

- Host: `docker-host` (icarus VM, 10.0.11.22, vlan05). Stack: `nextcloud:fpm-alpine`
  (`nextcloud-app-1`) + nginx (`nextcloud-web-1`/`web2`) + cron + **MySQL/MariaDB**.
- Version: **31.0.14** (target runs **34.0.3** — 3 majors apart).
- Data dir: `/var/www/html/data` (size TBD in phase 0).
- Users (**27**, real people incl. two Aphasie associations): anni, annika,
  aphasieshgessen, bj, christoph, fachschaft1, fredde, friedhoff, **h4xx
  (Lukas)**, hubi, jascha, jens, jmo, jogi, johanna, kevin,
  landesverbandaphasienrw, leon, marv, mascha, max, milena, miro, monika,
  pascal, timo, vivian.
- Domain today: `nextcloud.h4.ddnss.org` (currently resolving to an IONOS IP).

## Target

- k8s Nextcloud 34.0.3 (flux-apps/apps/nextcloud), CNPG postgres, RWX data on
  `nextcloud-data-hdd` (2Ti), OIDC via authelia (`oidc_login`,
  `auto_redirect: false` → password login stays available), LLDAP behind
  authelia since 2026-09-11.
- Both domains must serve the SAME instance: `nextcloud.h4xx.io` +
  `nextcloud.h4.ddnss.org`. Ingress/DNS = operator's task; app side needs
  `trusted_domains` + overwrite handling for the second domain (see phase 4).

## Strategy decision

**Files + DAV + scripted shares** (not `user_migration`, not DB surgery):

- 31→34 version gap + MySQL→Postgres rules out DB-level merges.
- `user_migration` export/import across a 3-major gap is unsupported-fragile,
  and it does not migrate shares anyway.
- Files rsync + `occ files:scan` is version-agnostic; calendars/contacts are
  portable via CalDAV/CardDAV exports; shares are recreatable via the OCS API.
- **Passwords DO migrate** (corrected 2026-09-12): modern NC hashes
  (`3|$argon2id…`, `1|$2y$…`) are self-contained (salt+params inside, no
  instance secret involved) and verify via `password_verify()` on any NC/DB.
  Phase 1 copies each `oc_users.password` hash row-by-row into the target
  after `occ user:add`. Reset mail only as fallback for pre-2015 LEGACY
  hashes (salted with the old instance's `passwordsalt`; detect:
  `password NOT LIKE '_|%'`). NOT portable regardless: app passwords/device
  tokens + TOTP enrollments (encrypted with the instance `secret`) — devices
  re-login, 2FA re-enrolls. Later Authelia/LLDAP accounts can take over auth
  per user (usernames kept identical so `oidc_login` matching is seamless).

## Phase 0 — complete discovery (read-only, ~30 min)

On docker-host via `occ`:
1. Full user list + emails + quotas + last-login: `occ user:list --output=json`,
   `occ user:info <u> --output=json` each.
2. Data size total + per user (`du -s data/<user>`), trash + versions size.
3. Outgoing shares inventory: `occ sharing:list` (or OCS
   `GET /ocs/v2.php/apps/files_sharing/api/v1/shares`) per user → JSON dump.
4. Enabled apps that carry data: calendar, contacts, deck?, notes? → scope.
5. Group memberships: `occ group:list --output=json`.
6. Decide inactive-user policy with operator (accounts dead since years →
   migrate-but-disable?).
7. **`occ encryption:status` on the source** — if server-side encryption is
   ON, files on disk are ciphertext (keys derived from passwords + instance
   secret) and MUST be decrypted in place (`occ encryption:decrypt-all`)
   before any rsync.
8. Hash-format census: `SELECT uid FROM oc_users WHERE password NOT LIKE
   '_|%'` → the (rare) legacy-hash users who WILL need a reset mail.

## Phase 1 — provision users + groups on k8s NC (no downtime)

**UID landscape (verified 2026-09-12): zero collisions.** The k8s instance
has only `admin` + four **UUID-uid accounts created by oidc_login from the
authelia `sub` claim** (`08f11a25-…` = Lukas Friedhoff = the real merge
target for `h4xx` — there is NO `lukasf` uid; data dir is the UUID). All 27
source uids are free.

For each source user (mapping `h4xx`→**skip creation** — its files merge
into `08f11a25-d9f3-487d-8a31-0a15df131ca1`):
```
occ user:add --display-name "<Display>" --email "<mail>" <username>   # random pw
occ user:disable <username>        # enabled only at cutover
occ group:add <g>; occ group:adduser <g> <u>
# then: copy the password hash from the source DB (portable, see Strategy):
#   psql: UPDATE oc_users SET password='<hash-from-mysql>' WHERE uid='<u>';
```
Scripted from phase-0 JSON; idempotent. h4xx's hash is NOT copied onto
lukasf (existing account keeps its credentials + OIDC).

## Phase 2 — bulk file pre-sync (online, repeatable)

- Transport: rsync over SSH from docker-host directly into a migration Job pod
  mounting `nextcloud-data-hdd` (pod runs sshd? simpler reverse: Job pulls via
  `rsync -aH root@docker-host:/…/data/<user>/files/` per user). Network path
  vlan05→vlan30 exists (same router; add fasttrack rule if CPU becomes a
  bottleneck — see the NAS-copy lesson from 2026-09-12).
- Per user: `data/<user>/files/ → data/<user>/files/` on the target volume;
  `h4xx/files/ → lukasf/files/` (merge; collisions surface in phase-0 report —
  expect none, fresh dirs).
- Skip: trash, versions, appdata, cache (policy: fresh start; call out in
  comms).
- After each sync round: `occ files:scan <user>` (target).

## Phase 3 — metadata (repeatable, near cutover)

1. Calendars/contacts: export per user from source DAV
   (`/remote.php/dav/calendars/<u>/…?export`, addressbook `?export=vcf`),
   import into target DAV (calendar: `occ dav:import-calendar` or PUT ics;
   contacts: PUT vcf). h4xx's → into lukasf.
2. Shares: replay the phase-0 share dump against the target OCS API
   (owner-mapped, path-mapped; drop shares pointing at skipped content).
   Public link shares: recreate → **tokens change** (links break — note in
   comms; optionally keep old instance read-only for a grace period).

## Phase 4 — cutover (target downtime: none on k8s side; old goes ro)

1. Old instance → maintenance mode (`occ maintenance:mode --on`) = freeze.
2. Final delta rsync + final files:scan + final DAV/share replay.
3. `occ user:enable` all migrated users. Passwords already work (migrated
   hashes); reset mails go ONLY to the phase-0 legacy-hash list, if any.
4. App config: add `h4.ddnss.org` names to `trusted_domains` (new
   `previews.config.php`-style config file via GitOps; also check
   `overwrite.cli.url`/protocol interplay — the existing overwritehost pins
   nextcloud.h4xx.io; per-domain overwrite needs care → operator does
   DNS/ingress, app accepts both Host headers).
5. Operator: point `nextcloud.h4.ddnss.org` DNS/ingress at the cluster.
6. Old instance stays up in maintenance/read-only for 2–4 weeks (rollback +
   forgotten-data window), then archive VM backup (restic to storage01
   already covers docker-host) and decommission the containers.

## Later (explicitly out of scope now)

- Authelia/LLDAP accounts for migrated users — **WARNING (found in the UID
  check): oidc_login on this instance maps accounts by the OIDC `sub` claim
  (UUIDs)**, so an SSO login by a migrated user would create a NEW UUID
  account instead of attaching to their provisioned username. Before any SSO
  rollout for migrated users, either reconfigure `oidc_login_attributes`
  id-mapping to `preferred_username`/email (and migrate the four existing
  UUID accounts' uids in the same step) or accept password-login-only for
  migrated users. Design decision deferred.
- Ingress for `nextcloud.h4.ddnss.org` (operator).

## Risks / notes

- ~20 real external users → comms matter more than tech: announce cutover,
  devices/apps must re-login (tokens don't migrate), 2FA re-enrollment,
  broken public links, trash/versions not migrated. Passwords stay the same.
- Quotas: copy from source (`occ user:setting <u> files quota`).
- Guest/ghost accounts (aphasie orgs) may be share-hubs — check share dump
  before deciding to disable anyone.
- k8s NC data volume sizing: +<source size> on the 2Ti volume — verify fit in
  phase 0.
- Preview regeneration for migrated files will burn CPU/IO on first browse —
  the 2048px cap (2026-09-12) limits the damage.
