#!/bin/bash
# Quiet xcodebuild wrapper for agents / terminals.
# Usage:
#   scripts/xcodebuild.sh build
#   scripts/xcodebuild.sh test
#   scripts/xcodebuild.sh -- raw xcodebuild args...
# Env:
#   DEST     destination (default: booted iPhone sim, else generic iOS Simulator)
#   SCHEME   scheme (default: Helm)
#   PROJECT  project (default: Helm.xcodeproj)
#   CONFIG   configuration (default: Debug)
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="${SCHEME:-Helm}"
PROJECT="${PROJECT:-Helm.xcodeproj}"
CONFIG="${CONFIG:-Debug}"

beautify() {
  if command -v xcbeautify >/dev/null 2>&1; then
    # Preserve xcodebuild exit code through the pipe.
    set -o pipefail
    # quieter = errors only; --is-ci keeps test results under quiet flags.
    xcbeautify --quieter --is-ci --disable-colored-output --disable-logging
  else
    # Fallback: drop compile chatter, keep errors/warnings/summary lines.
    grep -E 'error:|warning:|fatal error:|\*\*|failed|SUCCEEDED|FAILED|Testing failed|Test Case|Test Suite' || true
  fi
}

default_dest() {
  if [[ -n "${DEST:-}" ]]; then
    printf '%s\n' "$DEST"
    return
  fi
  local booted
  booted="$(xcrun simctl list devices booted 2>/dev/null | awk -F '[()]' '/iPhone|iPad/ {print $2; exit}' || true)"
  if [[ -n "$booted" ]]; then
    printf 'platform=iOS Simulator,id=%s\n' "$booted"
  else
    printf 'generic/platform=iOS Simulator\n'
  fi
}

cmd="${1:-build}"
shift || true

case "$cmd" in
  build)
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -destination "$(default_dest)" \
      -quiet \
      build \
      "$@" 2>&1 | beautify
    ;;
  test)
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -destination "$(default_dest)" \
      -quiet \
      test \
      "$@" 2>&1 | beautify
    ;;
  --)
    xcodebuild "$@" 2>&1 | beautify
    ;;
  *)
    echo "Usage: $0 {build|test|--} [extra xcodebuild args...]" >&2
    exit 2
    ;;
esac
