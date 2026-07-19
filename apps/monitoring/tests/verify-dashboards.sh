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

  jq -e '
    [
      .. | objects | select(has("expr")) | .expr
      | select(type == "string")
      | select(test("job=\\\"(node|kube-state-metrics|kubelet)\\\""))
    ] | length == 0
  ' "$file" >/dev/null || fail "dashboard uses stale scrape job labels; use Grafana Agent integration job names: ${rel}"

  jq -e '
    [
      .templating.list[]?
      | select(.type == "datasource" and ((.query | tostring) == "prometheus"))
      | select(((.current.value // "") != "mimir") or ((.regex // "") != ""))
    ] | length == 0
  ' "$file" >/dev/null || fail "Prometheus datasource variables must default to Mimir without regex filters: ${rel}"

  jq -e '
    [
      .templating.list[]?
      | select(.type == "datasource" and ((.query | tostring) == "loki"))
      | select((.current.value // "") != "loki")
    ] | length == 0
  ' "$file" >/dev/null || fail "Loki datasource variables must default to Loki: ${rel}"

  jq -e '
    [
      .templating.list[]?
      | select(.type == "datasource" and ((.query | tostring) == "tempo"))
      | select((.current.value // "") != "tempo")
    ] | length == 0
  ' "$file" >/dev/null || fail "Tempo datasource variables must default to Tempo: ${rel}"

  jq -e '
    [
      .. | objects | .datasource? // empty
      | if type == "object" then (.uid? // .name? // "") elif type == "string" then . else empty end
      | . as $uid
      | select(["prometheus", "Prometheus", "default", "mimir-ops-03", "cortex-ops-01", "P666011C0B63BDCA4"] | index($uid))
    ] | length == 0
  ' "$file" >/dev/null || fail "dashboard contains hardcoded stale Prometheus datasource references: ${rel}"

  jq -e '
    [
      .annotations.list[]? | .datasource? // empty
      | select(type == "object" and (.uid? // "") == "grafana")
    ] | length == 0
  ' "$file" >/dev/null || fail "dashboard annotations must use Grafana builtin uid '-- Grafana --': ${rel}"

  if grep -q '\${DS_PROMETHEUS}' "$file"; then
    jq -e '[.templating.list[]? | select(.name == "DS_PROMETHEUS")] | length > 0' "$file" >/dev/null \
      || fail "dashboard references \${DS_PROMETHEUS} without defining the datasource variable: ${rel}"
  fi

  jq -e '
    [
      .templating.list[]?
      | select((.name | ascii_downcase) as $name | [
          "namespace", "instance", "instances", "pod", "container", "node", "workload", "volume", "certificate", "cluster"
        ] | index($name))
      | select((.includeAll != true) or (.multi != true) or (((.allValue // "") == ".*" or (.allValue // "") == ".+") | not))
    ] | length == 0
  ' "$file" >/dev/null || fail "namespace/instance/cluster-style selectors must support multi-select All: ${rel}"

  if jq -e '
    [
      .. | objects | select(has("expr")) | .expr
      | select(type == "string")
      | select(contains("|=") or contains("|~") or contains("| logfmt") or contains("|logfmt") or contains("$__auto") or ((startswith("{") and (startswith("{__name__") | not))))
    ] | length > 0
  ' "$file" >/dev/null; then
    jq -e '
      [
        .templating.list[]?
        | select((.name | ascii_downcase) as $name | ["namespace", "pod", "container", "cluster"] | index($name))
        | select(.includeAll == true)
        | select((.allValue // "") != ".+")
      ] | length == 0
    ' "$file" >/dev/null || fail "LogQL dashboards must use non-empty All=~.+ selectors for Loki: ${rel}"
  fi

  jq -e '
    [
      .. | objects | select(has("expr")) | .expr
      | select(type == "string")
      | select(test("[A-Za-z_:][A-Za-z0-9_:]*\\\\s*=\\\\s*\\\"\\\\$\\\\{?(namespace|Namespace|instance|instances|Instances|pod|container|node|workload|volume|Certificate|certificate|cluster)\\\\}?\\\""))
    ] | length == 0
  ' "$file" >/dev/null || fail "PromQL/LogQL selectors using multi-select variables must use regex matching: ${rel}"

  case "$rel" in
    apps/*|media/*)
      jq -e '
        [.templating.list[]? | select(.name == "namespace") | select(.includeAll == true and .multi == true)] | length == 1
      ' "$file" >/dev/null || fail "app/media dashboard namespace variable must support All and multi-select: ${rel}"

      jq -e '
        [
          .templating.list[]?
          | select(.name == "pod" or .name == "container")
          | select((.includeAll != true) or (.multi != true))
        ] | length == 0
      ' "$file" >/dev/null || fail "app/media dashboard pod/container variables must support All and multi-select: ${rel}"
      ;;
  esac

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
