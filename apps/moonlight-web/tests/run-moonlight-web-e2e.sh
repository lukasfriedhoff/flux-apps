#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KUTTL_DIR="${SCRIPT_DIR}/kuttl"
KUTTL_CONFIG="${KUTTL_DIR}/kuttl-test.yaml"
NAMESPACE="${NAMESPACE:-media}"
TIMEOUT="${TIMEOUT:-300}"

echo ">> Running KUTTL Moonlight Web E2E tests"
echo "   config: ${KUTTL_CONFIG}"
echo "   namespace: ${NAMESPACE}"
echo "   timeout: ${TIMEOUT}s"

nix shell nixpkgs#kuttl nixpkgs#curl -c \
  kubectl-kuttl test "${KUTTL_DIR}" \
    --config "${KUTTL_CONFIG}" \
    --namespace "${NAMESPACE}" \
    --timeout "${TIMEOUT}"

