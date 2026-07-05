#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
dashboards_dir="${repo_root}/apps/monitoring/dashboards"
kustomization="${dashboards_dir}/kustomization.yaml"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[dashboard-test] missing required command: %s\n' "$1" >&2
    exit 1
  }
}

fail() {
  printf '[dashboard-test] FAIL: %s\n' "$*" >&2
  exit 1
}

need jq
need kustomize
need yq

declare -A seen_uids=()
declare -A listed_files=()

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  listed_files["$rel"]=1
  [ -f "${dashboards_dir}/${rel}" ] || fail "kustomization references missing dashboard: ${rel}"
done < <(yq -r '.configMapGenerator[]?.files[]?' "$kustomization" | sort)

while IFS= read -r file; do
  rel="${file#${dashboards_dir}/}"
  [ "${listed_files[$rel]+set}" = "set" ] || fail "dashboard JSON is not included in kustomization: ${rel}"

  jq -e . "$file" >/dev/null || fail "invalid JSON: ${rel}"
  title="$(jq -r '.title // ""' "$file")"
  [ -n "$title" ] || fail "dashboard has empty title: ${rel}"

  jq -e '((.panels // []) | type == "array") or ((.rows // []) | type == "array")' "$file" >/dev/null \
    || fail "dashboard has neither panels[] nor legacy rows[]: ${rel}"

  uid="$(jq -r '.uid // ""' "$file")"
  if [ -n "$uid" ]; then
    if [ -n "${seen_uids[$uid]:-}" ]; then
      fail "duplicate dashboard uid ${uid}: ${seen_uids[$uid]} and ${rel}"
    fi
    seen_uids["$uid"]="$rel"
  fi

  jq -e '
    [
      .. | objects | select(has("expr")) | .expr
      | select((type == "string") and (length == 0))
    ] | length == 0
  ' "$file" >/dev/null || fail "dashboard contains an empty PromQL expression: ${rel}"

  if [ "$rel" = "cnpg/cnpg-backup.json" ]; then
    jq -e '
      [
        .. | objects | select(has("expr")) | .expr
        | select(test("cnpg_pg_stat_archiver_failed_count") and (test("increase\\(") | not))
      ] | length == 0
    ' "$file" >/dev/null || fail "CNPG backup dashboard must show recent WAL failures, not raw cumulative counters"

    jq -e '
      [
        .. | objects | select(has("expr")) | .expr
        | select(test("last_available_backup_timestamp|first_recoverability_point") and test("by \\(namespace, cluster\\)"))
      ] | length == 0
    ' "$file" >/dev/null || fail "CNPG backup dashboard must group backup metrics by namespace,pod, not namespace,cluster"

    jq -e '
      [
        .. | objects | select(has("expr")) | .expr
        | select(test("last_available_backup_timestamp|first_recoverability_point") and (test("by \\(namespace, pod\\)") | not))
      ] | length == 0
    ' "$file" >/dev/null || fail "CNPG backup dashboard backup timestamp panels must preserve pod identity"

    jq -e '
      [
        .. | objects | select(has("expr")) | .expr
        | select(test("cnpg_pg_stat_archiver_last_archive_age"))
      ] | length == 0
    ' "$file" >/dev/null || fail "CNPG backup dashboard must use cnpg_pg_stat_archiver_seconds_since_last_archival for WAL age"
  fi

  printf '[dashboard-test] %s ok\n' "$rel"
done < <(find "$dashboards_dir" -type f -name '*.json' | sort)

kustomize build "$dashboards_dir" >/dev/null || fail "dashboard kustomization does not render"

printf '[dashboard-test] verified %s dashboards\n' "$(find "$dashboards_dir" -type f -name '*.json' | wc -l)"
