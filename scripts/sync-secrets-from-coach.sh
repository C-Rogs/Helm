#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COACH_SECRETS="${ROOT}/../coach/Secrets"
HELM_SECRETS="${ROOT}/Secrets"

mkdir -p "${HELM_SECRETS}"

copy_key() {
  local src="$1"
  local dest="$2"
  if [[ -f "${src}" ]]; then
    cp "${src}" "${dest}"
    echo "Copied $(basename "${dest}")"
  else
    echo "Skipped $(basename "${dest}") - missing ${src}" >&2
  fi
}

copy_key "${COACH_SECRETS}/GeminiAPIKey.txt" "${HELM_SECRETS}/gemini.key"
copy_key "${COACH_SECRETS}/OpenRouterAPIKey.txt" "${HELM_SECRETS}/openrouter.key"

echo "Helm Secrets ready at ${HELM_SECRETS}"
echo "Rebuild Debug on your device to push keys into Keychain."
