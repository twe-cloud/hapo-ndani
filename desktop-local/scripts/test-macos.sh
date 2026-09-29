#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf NdaniDesktop.xcodeproj
xcodegen generate >/dev/null
xcodebuild test \
  -project NdaniDesktop.xcodeproj \
  -scheme NdaniDesktop \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

for package in Packages/AppCore Packages/AppDocuments; do
  (cd "$package" && swift test)
done
