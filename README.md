# Hapo Ndani

**A consent layer for personal data, with a local-AI client as its reference
implementation.**

A person grants scoped access to their own files. They see an offer — who wants
what, and what it pays. They decide, per offer, whether to send anything. The design calls for the money to reach *them*. A production payout integration is still required. Every local read is written to an
append-only ledger, including whether it ever left the device.

That sequence — **scope → offer → consent → payment → provenance** — is what
this repository specifies.

**What works today:** local folder scope and read records, plus a Swift core
that signs per-offer consent and checks a hash-bound consent response. The app
screens still need secure key storage and that consent flow connected. There is
no production payout integration in this repository and **no paid-participant
track record demonstrated here**. Consent acceptance is never shown as earnings.

**Try the signed proof in one command** (Node.js 22+, no install or account):

```bash
node tools/consent-proof.cjs --demo
```

It verifies synthetic Swift and Node signatures, then rejects a changed summary,
changed signed terms digest, substituted key and invented receipt amount. A
Python-signed fixture binds the full frozen offer and rejects changes to the buyer,
purpose, price or contributor amount. It checks integrity and terms binding,
not buyer identity, funding, legal adequacy or payment. See the
[implemented protocol](docs/CONSENT_SALE_PROTOCOL.md) and
[conformance guide](docs/BACKEND_SEAM.md).

*Hapo ndani* is Swahili for "in there".

<p align="center">
  <img src="docs/screenshots/ios-chat.png" alt="Hapo Ndani running a local model on iPhone" width="240">
  <img src="docs/screenshots/ios-journal.png" alt="The local journal" width="240">
  <img src="docs/screenshots/ios-device.png" alt="Device and model status" width="240">
</p>

---

## The primitive

Plenty of software runs a model on your laptop. What is missing is the part where
a person can **sell access to their own data on terms they can see**, and have
the proceeds reach them rather than a platform.

Four pieces define the work; their implementation status differs:

| | |
| --- | --- |
| **Scope** | Access is granted per folder and is revocable. On Apple platforms it uses security-scoped bookmarks, so a grant can go *stale* — and the app reports that rather than silently retrying. No scope, no read. |
| **Consent** | Granting folder access is **not** consent to sell. Submitting to an offer is a separate, explicit act, for one offer, carrying text the person wrote themselves. The signed core payload has no file-content field; the app UI integration is pending. |
| **Payment** | *No production integration shipped.* The payout figure is defined as what the **person** receives, not a platform cut, and balance, earnings and withdrawal eligibility are defined as user-visible — but a verified money source is still required. The core signs with a caller-supplied **Ed25519 keypair**; secure storage and recovery remain to build. Payout is the deliberate exception, because getting paid requires KYC. |
| **Provenance** | Every read lands in an append-only ledger with a `wasSentOffDevice` flag and the *length* of what was read, never the content. This records app behavior; it is not an immutable attestation or independent network monitor. |

The protocol is specified in **[docs/BACKEND_SEAM.md](docs/BACKEND_SEAM.md)** —
the current boundary, identity limitations, and offline conformance commands. The signed wire contract lives in **[docs/CONSENT_SALE_PROTOCOL.md](docs/CONSENT_SALE_PROTOCOL.md)**.

## The reference client

The apps are a working local-AI workspace: chat, a journal, and a memory, with
the model loaded from a file on your own disk.

This matters for one reason — it proves the consent layer against a real
workload on real hardware rather than a toy. If no valid model is present the app
says so and refuses to chat; it will not quietly fall back to a hosted API,
because that would make the ledger a lie.

- **Local chat** against a GGUF or LiteRT-LM model you supply
- **Journal and memory** in a local store (Room on Android; app-owned storage on
  Apple platforms). Android backup is switched off so they are not swept into a
  cloud backup
- **The permission ledger and audit trail**, described above
- **Honest capability reporting** — RAM, storage and runtime are checked before a
  model tier is offered

Three platforms: `desktop-local/` (macOS + iOS), `android-companion/` (Android),
`desktop-windows/` (Windows + Linux). Android makes **no network calls at all**.

## Free app, open code, models under their own terms

Three separate facts, and conflating them is the usual mistake.

**The app is free.** There is no purchase, no licence key, no activation and no
paid tier. Nothing in it is gated behind money.

**The code is Apache-2.0.** You can read it, fork it, ship your own build and
use it commercially, subject to the licence.

**The models are neither.** They are not ours, several are not open source, and
two of them place obligations on you:

| Model | Licence | |
| --- | --- | --- |
| Qwen3 4B / 8B / 14B | **Apache-2.0** | Clean. |
| Gemma 3n / 4 (E2B, E4B) | **Google Gemma Terms of Use** | **Not an open-source licence.** Carries a prohibited-use policy you must pass downstream. |
| Hermes 3 Llama 3.1 8B | **Llama 3.1 Community License** | Requires **"Built with Llama"** attribution; acceptable-use policy applies; MAU threshold above which you need a separate licence from Meta. |

**No weights are in this repository and none are redistributed by it.** Nothing
here grants you any rights to any model's weights — those come from the
publisher, to you, directly. **[MODELS.md](MODELS.md)** has the full table and
the links.

Every model URL here is **pinned to an immutable Hugging Face commit revision**,
so the bytes behind it cannot change after the fact. One gap remains and is
documented rather than hidden: `expectedSHA256` is `nil` on every package, so a
download is accepted on the strength of the pinned revision alone. The
verification code exists and works — it is simply not fed any digests yet.
Pull requests welcome.

## What is deliberately not here

| | Why |
| --- | --- |
| A rail — the service that publishes offers and moves money | The commercial counterparty side is outside this repository. A signed protocol and offline proof do not constitute a live buyer catalog, settlement or participant payout integration. |
| Marketing site, internal operations, release-readiness notes, store-submission records, pricing analysis, security audits | Internal business material, of no use to anyone building this. |
| Model weights | No right to redistribute. |
| Our signing certificate, Apple Team ID, Android upload keystore | Yours go in local files this repo ignores. |

**None of it is required to build and run the apps.** With no rail configured,
the offer and payment features report that they are switched off — the
local workspace remains usable.

No placeholder offers ship in any client. Offers come from a configured rail or
the list is empty and says so — a person looking at that screen is seeing real
demand or nothing at all.

## Getting a model

| Platform | Format | Location |
| --- | --- | --- |
| macOS | GGUF | `~/.ndani/models/` |
| iOS | LiteRT-LM / GGUF | app Application Support `models/`, downloaded in-app |
| Android | `.litertlm` | app no-backup storage `models/`, or **Choose model file** |
| Windows / Linux | GGUF | `~/.ndani/models/` |

Reasonable starting points: **Qwen3 4B** (Q4_K_M GGUF) on a laptop,
**Gemma 3n E2B IT** (`.litertlm`) on an 8 GB Android phone. Accept the
publisher's licence first.

---

## Building

### macOS and iOS

macOS 15+, Xcode 16+ (Swift 6), XcodeGen (`brew install xcodegen`).

```bash
cd desktop-local
./scripts/generate.sh      # regenerates NdaniDesktop.xcodeproj — not committed
swift test --package-path Packages/AppCore
xcodebuild build -project NdaniDesktop.xcodeproj -scheme NdaniDesktop -destination 'platform=macOS'
xcodebuild build -project NdaniDesktop.xcodeproj -scheme NdaniMobile -destination 'generic/platform=iOS Simulator'
```

Signing is off by default so a fresh clone builds with no Apple account. For a
device, create `desktop-local/Signing.local.xcconfig` (gitignored) with your own
Team ID — `Signing.xcconfig` documents the four lines. Targets: macOS 15.0,
iOS 18.0.

### Android

JDK 17+ and the Android SDK.

```bash
cd android-companion
./gradlew assembleDebug
./gradlew testDebugUnitTest
```

Release signing reads `NDANI_ANDROID_UPLOAD_STORE_FILE`,
`NDANI_ANDROID_UPLOAD_STORE_PASSWORD`, `NDANI_ANDROID_UPLOAD_KEY_ALIAS` and
`NDANI_ANDROID_UPLOAD_KEY_PASSWORD` from Gradle properties or the environment.
Debug needs none. Put yours in `~/.gradle/gradle.properties`, never in the repo.

Two things to know before filing a bug:

- **Inference needs a physical device.** The emulator crashes inside
  `liblitertlm_jni.so` with `SIGILL` while XNNPack prepares its weight cache, so
  the app blocks native init there and says so. The emulator is still fine for
  UI, model detection and the fail-closed paths.
- **8 GB of RAM is the floor** for the E2B tier.

Release model delivery uses Play fast-follow asset packs
(`model-pack-part0..2`); those asset directories are gitignored, so an AAB from
a clean clone contains no weights. Intended.

### Windows and Linux

Node.js 22+.

```bash
cd desktop-windows
npm install
npm start
npm run build:win          # NSIS installer, x64 + arm64
npm run build:linux        # AppImage
```

There is no code-signing configuration, so installers you build are **unsigned**
and SmartScreen will warn about them. Expected, not a bug.

---

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Start with `node --test tools/tests/consent-proof.test.cjs`. Useful next
contributions: secure OS key storage/recovery, a reviewable per-offer consent UI,
and independent verification against the shared conformance vectors. Real-device
Android findings and clear failure states are also welcome. Keep consent,
acceptance, obligations and confirmed payment separate.

The two invariants in `docs/BACKEND_SEAM.md` are not up for negotiation, and
neither is the local-first posture: a change that adds telemetry, analytics or a
hosted fallback to a local code path will be declined however well written. If
it seems to need a network call, open an issue and let's find another way.

## Security

Not in a public issue. [SECURITY.md](SECURITY.md).

## Licence

[Apache-2.0](LICENSE), Copyright 2026 Ni Biashara LLC. Third-party components and
model weights are under their own licences — [NOTICE](NOTICE),
[MODELS.md](MODELS.md).

"Hapo Ndani" and "Ni Biashara" are trademarks of Ni Biashara LLC. The Apache-2.0
grant covers the code, not the names or the logo.
