#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
derived_data="$repo_root/.release-evidence/NativeAXDerivedData"
project="$repo_root/apps/macos/Automaatkorrektor.xcodeproj"

mkdir -p "$derived_data"
xcodebuild \
  -project "$project" \
  -scheme NativeAXEvidence \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  build

open "$derived_data/Build/Products/Debug/NativeTextControlHost.app"
open "$derived_data/Build/Products/Debug/AXIntegrationHarness.app"
