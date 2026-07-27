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
  Helm/Resources/MethodologySeed/methodology.json \
  Packages/ExportKit/Package.swift
do
  if [ ! -f "$path" ]; then
    echo "Missing required path: $path"
    exit 1
  fi
done

echo "Removing stale Xcode project and package caches..."
rm -rf Helm.xcodeproj
rm -rf Packages/ExportKit/.build Packages/ExportKit/.swiftpm

echo "Generating Helm.xcodeproj..."
xcodegen generate

echo "Resolving Swift packages..."
if ! xcodebuild -resolvePackageDependencies -project Helm.xcodeproj -scheme Helm 2>&1 | tee /tmp/helm-resolve.log; then
  echo "Package resolution failed. See /tmp/helm-resolve.log"
  exit 1
fi

if ! rg -q "ExportKit: /" /tmp/helm-resolve.log; then
  echo "ExportKit did not resolve. See /tmp/helm-resolve.log"
  exit 1
fi

echo "Generated Helm.xcodeproj and resolved packages."
echo "Open Helm.xcodeproj in Xcode (not Packages/ExportKit)."
