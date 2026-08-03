#!/bin/bash
# Capture main Helm screens from the booted iOS Simulator into Screenshots/tour/.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen required. Install: brew install xcodegen"
  exit 1
fi

DEVICE_ID="$(xcrun simctl list devices booted | sed -n 's/.*(\([A-F0-9-]\{36\}\)).*/\1/p' | head -1)"
if [[ -z "${DEVICE_ID}" ]]; then
  echo "No booted Simulator. Boot an iPhone sim, install Helm, re-run."
  exit 1
fi

echo "Regenerating Xcode project..."
xcodegen generate

OUT_DIR="$(pwd)/Screenshots/tour"
mkdir -p "${OUT_DIR}"
echo "Screenshots → ${OUT_DIR}"
echo "Destination Simulator: ${DEVICE_ID}"

xcodebuild test \
  -project Helm.xcodeproj \
  -scheme Helm \
  -destination "platform=iOS Simulator,id=${DEVICE_ID}" \
  -only-testing:HelmUITests/ScreenshotTourTests/testScreenshotTour \
  -parallel-testing-enabled NO \
  -quiet

echo ""
echo "Done. PNGs:"
ls -1 "${OUT_DIR}"
