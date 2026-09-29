# Hapo Ndani for macOS and iOS

Both Apple apps live here and share their core. Despite the folder name, this is
not desktop-only.

- `NdaniDesktop` — macOS 15+
- `NdaniMobile` — iOS 18+ (iPhone and iPad)

See the [repository README](../README.md) for what the product is and the
[backend seam](../docs/BACKEND_SEAM.md) for the optional hosted features.

## Layout

```
App/                    Both app entry points, assets, entitlements, privacy manifest
AppTests/               Unit tests (Swift Testing)
AppUITests/             iOS UI tests
Packages/
  AppCore/              State, chat, journal, memory, permission ledger, model catalog
  AppUI/                SwiftUI views and theme
  AppInference/         Local model loading — llama.cpp via llama.swift
  AppDocuments/         Document type
  AppIntegrations/      Service profiles
  AppTesting/           Shared test fixtures
project.yml             XcodeGen source — the .xcodeproj is generated, not committed
Signing.xcconfig        Contributor-supplied signing (see below)
scripts/
  generate.sh           Regenerate the Xcode project
  test-macos.sh         macOS test run
  eval-local-chat.py    Compare local model output against a local Ollama endpoint
```

`AppCore` is platform-agnostic. Anything that differs between macOS and iOS goes
behind `NdaniPlatform` rather than into a `#if os(...)` in a view.

## Build

Needs macOS 15+, Xcode 16+ (Swift 6), and XcodeGen (`brew install xcodegen`).

```bash
./scripts/generate.sh      # writes NdaniDesktop.xcodeproj — gitignored
swift test --package-path Packages/AppCore
xcodebuild build -project NdaniDesktop.xcodeproj -scheme NdaniDesktop -destination 'platform=macOS'
xcodebuild build -project NdaniDesktop.xcodeproj -scheme NdaniMobile -destination 'generic/platform=iOS Simulator'
```

Run `./scripts/generate.sh` again whenever you change `project.yml` or add a
package — the project file is derived, so editing it in Xcode will be
overwritten.

## Signing

Signing is **off by default**, so a fresh clone builds with no Apple account.

To run on a device or distribute your own build, create
`Signing.local.xcconfig` next to `Signing.xcconfig` — it is gitignored:

```
NDANI_DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGNING_REQUIRED  = YES
CODE_SIGNING_ALLOWED   = YES
CODE_SIGN_STYLE        = Automatic
CODE_SIGN_IDENTITY     = Apple Development
```

Never put a Team ID, certificate, or provisioning profile in a committed file.

## Models

The app looks for models in `~/.ndani/models/` on macOS and in the app's
Application Support `models/` directory on iOS. Nothing is bundled. The in-app
list offers recommended packages with direct download links; the app verifies a
package before offering to load it, and refuses to chat when none is valid.

`scripts/eval-local-chat.py` compares this app's output against a local Ollama
server on `127.0.0.1:11434` — useful when you are changing prompt handling and
want to know whether a regression is yours or the model's.

## Privacy posture

`App/PrivacyInfo.xcprivacy` declares no tracking and no collected data types,
and that is meant to stay true. There is no analytics, telemetry, or crash SDK
in either target. The only network traffic in a default build is a model
download you initiated.

If you add a dependency, check what it phones home about before opening a pull
request.
