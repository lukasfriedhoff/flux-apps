# Nextcloud docker-host → k8s: COMPLETE-DB MOVE runbook (v4, 2026-09-17)

**Decision:** move the *entire* ddnss database (NC31/MariaDB) into prod
(NC34/CNPG-Postgres) by **converting + upgrading it**, not by file-merging.
This is the only approach that preserves the **Passwords-app vault, calendars,
contacts, shares, deck, versions** — everything the earlier files+hashes merge
lost. Rehearsed end-to-end 2026-09-15..17; **PROVEN**.

Supersedes the v3 "merge into prod" plan (kept below for history). The 26
friendly-uid users + hashes created during the merge attempt become redundant
(the converted DB brings all 27 users with their real data).

## Why complete-DB, and why it can't be a "merge"
Two Nextcloud DBs can't be UNIONed — every table (`oc_filecache`,
`oc_storages`, `oc_calendars`, `oc_share`…) has its own primary-key space, so
importing ddnss's DB into the populated prod DB collides on thousands of
PKs/FKs. The complete move therefore **REPLACES** prod's DB with the
converted+upgraded ddnss DB (prod's only real user, lukasf, is also h4xx in
ddnss; adopt ddnss's secret so the vault + tokens stay valid — the 84 "prod
tokens" are ~all Lukas's own devices, re-login is trivial).

## Rehearsal results (temp stack, prod untouched)
- MySQL→PG `db:convert-type` + `occ upgrade` 31→32→33→34 all succeed.
- Verified in the converted PG: **users=27, passwords_password=360 (all h4xx),
  passwords_folder=11, shares=151, deck_cards=361, calendars=51/8181 events,
  addressbooks=21**, argon2id hashes intact.

## ⚠️ Requirements the rehearsal uncovered (do these or data is lost)
1. **Mount ddnss `custom_apps/` in the temp NC31 BEFORE `db:convert-type`.**
   `convert-type` builds each table from the app's *code* schema; without the
   app code it **silently drops** those tables (first pass lost 133 tables incl.
   the entire passwords vault). Calendars/contacts survive regardless (bundled
   `dav` app).
2. **FK-using apps break convert-type's alphabetical copy order.** `news`
   (`oc_news_feeds.folder_id → oc_news_folders`) aborts the whole convert with a
   Postgres FK violation (rc=7). Empty those tables first (news = regenerable
   RSS) or the convert dies. Watch for other FK apps on the real run.
3. **Adopt ddnss's `secret`/`passwordsalt`** at cutover (reference the source
   `config.php` directly — never extract/print it) so the 360 encrypted
   passwords entries + app tokens decrypt. Keep prod's `instanceid`? No — the
   vault + appdata are keyed to ddnss's `occ7puli0xhw`; adopt that too and move
   ddnss `appdata_occ7puli0xhw` into place.
4. **Reuse the already-copied files.** They're laid out `data/<uid>/files`
   (friendly uids, incl. `data/h4xx/files`); rsync preserved mtimes so the
   converted filecache stays valid → **no re-scan**, fileids preserved →
   shares/calendars stay internally consistent.

## Caveats
- **Speed:** the temp PG copied `oc_filecache` (4.45M rows) at ~160 rows/s
  (hours). For the real run use the **prod CNPG** as the convert target (fast)
  or a maintenance window that tolerates the time. In the rehearsal the big
  regenerable index tables (`oc_filecache`, `oc_activity`, `oc_files_metadata*`,
  `oc_fulltextsearch_index`, `oc_files_versions`) were truncated only to race
  to the passwords proof — the real run keeps them.
- **238 vs 277 tables:** ~39 source tables consistently don't convert (likely
  disabled-app / orphan tables). None of the critical data — but enumerate the
  gap and decide keep/drop before cutover.

## Cutover procedure

Prereqs: files already synced (`scripts/nextcloud-db-move/sync.sh`, resumable);
temp conv stack manifests in `scripts/nextcloud-db-move/`.

1. **Old instance → maintenance** (`occ maintenance:mode --on` on ddnss).
2. **Final DB dump** (`dump.sh`) → load into a temp MariaDB (`conv-stack.yaml`).
3. **Temp NC31 with custom_apps** (`conv-nc.yaml`) → empty FK app data (news):
   `SET FOREIGN_KEY_CHECKS=0; TRUNCATE oc_news_feeds; oc_news_folders; oc_news_items;`
4. **Convert** into a FRESH throwaway PG database (or straight into a new
   `nextcloud` DB on the prod CNPG cluster):
   `occ db:convert-type --all-apps --password <pw> pgsql <user> <pghost> <db>`
5. **Upgrade chain** (`upgrade-chain.sh`): bump the NC image 31→32→33→34,
   `occ upgrade` each (detached — each can exceed exec limits).
6. **Adopt into prod:** point prod's HelmRelease DB at the converted DB (or
   `pg_dump`/restore it into `nextcloud-postgres`), set prod `config.php`
   `secret`/`passwordsalt`/`instanceid` = ddnss's, mount the copied
   `data/<uid>` + `appdata_occ7puli0xhw`.
7. **Bring prod up on NC34**, `occ maintenance:mode --off`, verify: login (SSO
   *and* password), files, a Passwords-app entry decrypts, a calendar, a share.
8. **DNS** (operator): `nextcloud.h4.ddnss.org` + `nextcloud.h4xx.io` → prod.
9. Old ddnss stays in maintenance 1-2 weeks (rollback), then decommission.

## Post-cutover
- Re-subscribe the ~handful of news feeds (only regenerable thing dropped).
- Users re-pair devices (app-passwords are instance-bound; if `secret` adopted
  they may survive — verify).
- Delete the temp conv stack (`conv-mariadb`/`conv-postgres`/`conv-nc` +
  PVCs/configmaps in ns `nextcloud`), the migration pod `nc-migration` +
  secret `nc-migration-sshkey`, and remove the migration pubkey from
  `root@docker-host:~/.ssh/authorized_keys`.
