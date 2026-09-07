#!/bin/bash
# Sleep / readiness hot-path decision harness.
#
# 1) Runs Swift Testing benches → /tmp/helm-sleep-hotpath.json
# 2) Optionally records Time Profiler via xctrace (device/sim)
# 3) Exports hangs + aggregates → /tmp/helm-hotpath-report.md
#
# Usage:
#   scripts/profile-hotpath.sh              # benches + report from matrix only
#   scripts/profile-hotpath.sh --record     # also xctrace record (needs DEST device)
#   scripts/profile-hotpath.sh --trace PATH # aggregate an existing .trace
#
# Env:
#   DEST   xcodebuild destination (default: booted sim / generic like xcodebuild.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

RECORD=0
EXISTING_TRACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --record) RECORD=1; shift ;;
    --trace) EXISTING_TRACE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

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

DEST_VAL="$(default_dest)"
export DEST="$DEST_VAL"

echo "==> Running sleep hot-path benches (Persistence then HealthKitIngest)"
# Persistence writes the matrix; readiness suite merges readinessHistory30d into it.
scripts/xcodebuild.sh test \
  -only-testing:PersistenceTests/SleepHotPathBenchmarks \
  || true
scripts/xcodebuild.sh test \
  -only-testing:HealthKitIngestTests/SleepHotPathReadinessBenchmarks \
  || true

MATRIX="/tmp/helm-sleep-hotpath.json"
if [[ ! -f "$MATRIX" ]]; then
  echo "WARN: $MATRIX missing after benches. Check test output for HELM_SLEEP_HOTPATH_JSON." >&2
fi

TRACE_PATH=""
HANGS_XML=""
TP_XML=""

if [[ -n "$EXISTING_TRACE" ]]; then
  TRACE_PATH="$EXISTING_TRACE"
elif [[ "$RECORD" -eq 1 ]]; then
  echo "==> Recording Time Profiler (30s). Keep device connected; launch Helm if prompted."
  OUT_TRACE="/tmp/helm-hotpath-$(date +%Y%m%d-%H%M%S).trace"
  # Prefer device from DEST id when present.
  DEVICE_ARGS=()
  if [[ "$DEST_VAL" == *id=* ]]; then
    DEV_ID="${DEST_VAL##*id=}"
    DEVICE_ARGS=(--device "$DEV_ID")
  fi
  # Record attaching to / launching Helm. If launch fails, print manual steps.
  if xcrun xctrace record \
      --template 'Time Profiler' \
      --time-limit 30s \
      --output "$OUT_TRACE" \
      "${DEVICE_ARGS[@]}" \
      --launch com.cameronro.helm \
      2>/tmp/helm-xctrace-record.err; then
    TRACE_PATH="$OUT_TRACE"
  else
    echo "xctrace record failed (see /tmp/helm-xctrace-record.err)." >&2
    echo "Manual: Instruments → Time Profiler → filter POI SleepFetchOverlapping / ReadinessHistoryBuild." >&2
    echo "Then: scripts/profile-hotpath.sh --trace /path/to/run.trace" >&2
  fi
fi

if [[ -n "$TRACE_PATH" && -e "$TRACE_PATH" ]]; then
  echo "==> Exporting hangs + time-profile from $TRACE_PATH"
  HANGS_XML="/tmp/helm-hotpath-hangs.xml"
  TP_XML="/tmp/helm-hotpath-tp.xml"
  xcrun xctrace export --input "$TRACE_PATH" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]' \
    --output "$HANGS_XML" || true
  xcrun xctrace export --input "$TRACE_PATH" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
    --output "$TP_XML" || true
fi

echo "==> Aggregating report"
AGG_ARGS=(--matrix "$MATRIX" --out /tmp/helm-hotpath-report.md)
[[ -n "$HANGS_XML" && -f "$HANGS_XML" ]] && AGG_ARGS+=(--hangs "$HANGS_XML")
[[ -n "$TP_XML" && -f "$TP_XML" ]] && AGG_ARGS+=(--time-profile "$TP_XML")
python3 scripts/aggregate-hotpath-trace.py "${AGG_ARGS[@]}"

echo ""
echo "Matrix: $MATRIX"
echo "Report: /tmp/helm-hotpath-report.md"
echo ""
echo "Instruments POI: SleepFetchOverlapping, ReadinessHistoryBuild"
