#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not installed. Install with: brew install xcodegen"
  exit 1
fi

xcodegen generate
echo "Generated Helm.xcodeproj. Open that file in Xcode (not a Package.swift folder)."
