#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# HISTORICAL — this produced the FIRST cut of the public tree from
# the private monorepo @ build/v1-mvp. It is kept so the derivation is
# reproducible and so the exclusion decisions stay auditable.
#
# IT DOES NOT REPRODUCE THE CURRENT TREE. Everything after the first cut was
# edited in place: the signing seam, the backend config seam, the licence ->
# participant rework, the pinned model revisions, the deleted sample offers,
# and every claim correction. Re-running this OVERWRITES those edits.
#
# The committed tree is the source of truth. This is documentation.
# ---------------------------------------------------------------------------
# Stage the candidate PUBLIC tree for Hapo Ndani open-core.
# Source: the private monorepo @ build/v1-mvp working tree (read-only; never modified).
# Destination: scratchpad staging dir. Idempotent — wipes and rebuilds.
set -euo pipefail

# Both paths come from the environment so no local filesystem layout is baked in.
SRC="${NDANI_PRIVATE_REPO:?set NDANI_PRIVATE_REPO to the private monorepo checkout}"
DST="${NDANI_PUBLIC_STAGE:?set NDANI_PUBLIC_STAGE to the staging destination}"

rm -rf "$DST"
mkdir -p "$DST"

copy_tree() {
  # copy_tree <relative src dir> <relative dst dir> <rsync exclude args...>
  local s="$1"; shift
  local d="$1"; shift
  mkdir -p "$DST/$d"
  rsync -a "$@" \
    --exclude '.build/' --exclude '.swiftpm/' --exclude 'DerivedData/' \
    --exclude 'node_modules/' --exclude 'build/' --exclude '.gradle/' \
    --exclude '.kotlin/' --exclude '.idea/' --exclude '.cxx/' \
    --exclude '*.xcodeproj/' --exclude '*.xcworkspace/' \
    --exclude 'local.properties' --exclude '.DS_Store' \
    --exclude '*.litertlm' --exclude '*.litertlm.part*' \
    --exclude '*.gguf' --exclude '*.keystore' --exclude '*.jks' \
    --exclude '*.p12' --exclude '*.mobileprovision' --exclude '*.cer' --exclude '*.pem' \
    --exclude '.env' --exclude 'output/' \
    "$SRC/$s/" "$DST/$d/"
}

# ---------- macOS + iOS (SwiftUI / XcodeGen) ----------
# EXCLUDED: AGENTS.md (internal ops), docs/ (App Store Connect app+version+submission
# ids, launch/PR plans), store-listings/ prose (ASC app id 6763682362, provisioning
# profile names). Screenshots are re-homed under docs/screenshots/.
copy_tree desktop-local desktop-local \
  --exclude 'AGENTS.md' \
  --exclude 'docs/' \
  --exclude 'store-listings/'

# ---------- Android companion (Gradle / Kotlin) ----------
# EXCLUDED: AGENTS.md, STATUS.md, .codex/ (agent + emulator profile),
# ANDROID_RELEASE_READINESS.md and ANDROID_LOCAL_LLM_BASELINE.md (internal QA
# state, named emulator, "no-go" release posture), model-pack/ (orphan — not in
# settings.gradle.kts).
copy_tree android-companion android-companion \
  --exclude 'AGENTS.md' \
  --exclude 'STATUS.md' \
  --exclude '.codex/' \
  --exclude 'ANDROID_RELEASE_READINESS.md' \
  --exclude 'ANDROID_LOCAL_LLM_BASELINE.md' \
  --exclude 'model-pack/'

# ---------- Windows / Linux desktop (Electron) ----------
copy_tree desktop-windows desktop-windows

# ---------- Screenshots for the README ----------
mkdir -p "$DST/docs/screenshots"
cp "$SRC/desktop-local/store-listings/app-store/ios/screenshots/iphone-6-9/2026-05-06/01-journal.png" "$DST/docs/screenshots/ios-journal.png"
cp "$SRC/desktop-local/store-listings/app-store/ios/screenshots/iphone-6-9/2026-05-06/02-chat.png"    "$DST/docs/screenshots/ios-chat.png"
cp "$SRC/desktop-local/store-listings/app-store/ios/screenshots/iphone-6-9/2026-05-06/03-device.png"  "$DST/docs/screenshots/ios-device.png"
cp "$SRC/desktop-local/store-listings/google-play/images/screenshot-1.png" "$DST/docs/screenshots/android-home.png"
cp "$SRC/desktop-local/store-listings/google-play/images/screenshot-2.png" "$DST/docs/screenshots/android-chat.png"

echo "staged -> $DST"
find "$DST" -type f | wc -l
