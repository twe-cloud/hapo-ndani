#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf NdaniDesktop.xcodeproj
xcodegen generate
