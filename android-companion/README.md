# Hapo Ndani for Android

Local-first Android app: **Home → Chat → Journal**, with inference running on
the device through LiteRT-LM.

This module makes **no network calls at all** — there is no backend to
configure, no analytics SDK, and no billing client. See the
[repository README](../README.md) for the product, and
[CONTRIBUTING.md](../CONTRIBUTING.md) before sending changes.

- Application ID: `biz.nibiashara.hapondani`
- Runtime: `com.google.ai.edge.litertlm:litertlm-android`
- Storage: local Room database; Android backup is **disabled** in the manifest so
  journal and memory are not swept into a cloud backup

## Layout

```
app/                        Application module
core-data/                  Repositories
core-database/              Room entities and DAOs
core-designsystem/          Compose theme and components
core-testing/               Shared test utilities
feature-home/               Home, Chat, Journal, and the inference runtime
feature-home-navigation/    Navigation graph
model-pack-part0..2/        Play fast-follow asset packs for model delivery
benchmark/                  Macrobenchmark
test-app/                   Harness for isolated feature testing
build-logic/                Convention plugins
```

## Build

Needs JDK 17+ and the Android SDK. The Gradle wrapper does the rest.

```bash
./gradlew assembleDebug
./gradlew testDebugUnitTest
./scripts/validate.sh        # both of the above
```

## Two things to know before filing a bug

**Inference does not work on an emulator.** The full E2B model reproduces a
native `SIGILL` inside `liblitertlm_jni.so` while XNNPack prepares its weight
cache. Rather than crash, the app now blocks native initialisation on emulators
and tells you a physical device is required. The emulator remains useful for UI,
navigation, model detection, and the fail-closed paths — it is not a valid
conversation-quality test.

**8 GB of RAM is the floor** for the E2B tier. E4B is optional for stronger
phones and is gated behind a device check.

## Models

No weights are in this repository, and `assembleDebug` bundles none.

For local testing, use **Choose model file** in the app: it copies the model you
pick into the app's no-backup storage at
`context.noBackupFilesDir/models/`. The app recognises the standard Gemma 3n
LiteRT-LM filenames, e.g. `gemma-3n-E2B-it-int4.litertlm`.

Until a valid `.litertlm` file is present and initialises, the app **fails
closed** — it reports the missing model instead of pretending to chat. Keep it
that way.

In release builds, models are delivered by Play fast-follow asset packs
`hapondani_model_pack_0..2`, which chunk the model across
`model-pack-part*/src/main/assets/model_chunks/`. Those asset directories are
gitignored, so an AAB built from a clean clone contains no weights — intended.

> Gemma weights are governed by Google's Gemma Terms of Use, not this
> repository's Apache-2.0 licence. Read them before you ship anything.

## Release signing

Four Gradle properties, each also readable from the environment:

```
NDANI_ANDROID_UPLOAD_STORE_FILE
NDANI_ANDROID_UPLOAD_STORE_PASSWORD
NDANI_ANDROID_UPLOAD_KEY_ALIAS
NDANI_ANDROID_UPLOAD_KEY_PASSWORD
```

Debug builds need none of them. Put yours in `~/.gradle/gradle.properties`.
Never commit a keystore — `*.keystore` and `*.jks` are gitignored, and that is a
floor, not a substitute for care.
