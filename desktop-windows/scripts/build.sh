#!/usr/bin/env bash
# Build Ndani Desktop for Windows
# Run this on a Windows machine or via GitHub Actions (windows-latest runner)
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Ndani Desktop — Windows Build ==="

# Install dependencies
npm install

# Build Windows installer (NSIS)
npm run build:win

echo "=== Build complete. Artifacts in dist/ ==="
ls -la dist/ 2>/dev/null || echo "(no dist/ yet — run on Windows)"
