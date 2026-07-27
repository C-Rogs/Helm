#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not installed. Install with: brew install xcodegen"
  exit 1
fi

for path in \
  Helm/Resources/ExerciseSeed/exercises.json \
  Helm/Resources/ExerciseSeed/free-exercise-db.json \
  Helm/Resources/MethodologySeed/methodology.json
do
  if [ ! -f "$path" ]; then
    echo "Missing required resource: $path"
    exit 1
  fi
done

rm -rf Helm.xcodeproj
xcodegen generate
echo "Generated Helm.xcodeproj. Open that file in Xcode (not a Package.swift folder)."
