#!/usr/bin/env bash
# The player manual exists twice on purpose: MANUAL.md is the readable source,
# and the OliveTin "Manual" tab embeds it as HTML so players never have to
# leave valheim.h4xx.io. Two copies drift, so this asserts both still cover
# the same topics. It deliberately matches on CONTENT, not heading wording -
# the HTML uses imperative headings ("Install a mod") and the markdown uses
# gerunds ("Installing a mod").
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
manual="${repo_root}/apps/valheim/MANUAL.md"
olivetin="${repo_root}/apps/valheim/webui-olivetin.yaml"

fail() {
  printf '[valheim-manual-sync] %s\n' "$*" >&2
  exit 1
}

[ -f "$manual" ] || fail "missing $manual"
[ -f "$olivetin" ] || fail "missing $olivetin"

# topic|regex - each must appear in BOTH documents.
topics=(
  "where mods go|bepinex/plugins"
  "installing a mod|[Rr]estart server"
  "updating a mod|[Dd]elete the old"
  "mods are client+server|client AND|client \*and\*"
  "leather house rule|leather"
  "uploading a world|worlds_local"
  "world switching is not self-service|one-line change|one world"
  "backups and restore|[Rr]estore snapshot"
  "troubleshooting|Check Steam listing"
)

for entry in "${topics[@]}"; do
  topic="${entry%%|*}"
  pattern="${entry#*|}"
  grep -qE "$pattern" "$manual"   || fail "MANUAL.md is missing: $topic (/$pattern/)"
  grep -qE "$pattern" "$olivetin" || fail "the OliveTin Manual tab is missing: $topic (/$pattern/)"
done

# The in-UI manual is only useful if the tab actually exists.
grep -q 'title: Manual' "$olivetin" || fail "the OliveTin dashboard has no Manual tab"

printf '[valheim-manual-sync] manual and OliveTin tab cover the same %d topics\n' "${#topics[@]}"
