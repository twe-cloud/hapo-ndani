# Contributing to Hapo Ndani

Thanks for looking. This is a small project maintained by a small company, so
this document is short and tries to be honest about what will and will not get
merged.

## Before you write code

**Open an issue first** for anything beyond a bug fix. A pull request that
arrives with no prior discussion may be declined for reasons that have nothing
to do with its quality — it might conflict with something unreleased, or with
the product direction. An issue costs you ten minutes and can save you a
weekend.

Bug reports and platform-specific fixes need no preamble. Send those.

## The one non-negotiable

**Local code paths stay local.** Chat, the journal, memory, model loading and
the permission ledger must work with the machine offline, and must not acquire a
dependency on any network service — ours or anyone's.

A change that adds telemetry, analytics, a crash reporter, a hosted inference
fallback, or a "just check in with the server once" call to those paths will be
declined regardless of how well it is written. This is the product, not a
preference. If a feature seems to need a network call, open an issue and let's
find another way.

The consent rail is the only place network calls belong, and it must degrade to
"switched off" when unconfigured.

**The two protocol invariants are also non-negotiable**, and they are the reason
this repository exists:

1. **The user is the seller.** The payout figure shown to a person is what that
   person receives.
2. **Nothing leaves the device without a per-offer act.** Folder scope is not
   consent to sell. The submission payload has no field for file contents, and a
   pull request that adds one will be declined.

Both are specified in [docs/BACKEND_SEAM.md](docs/BACKEND_SEAM.md). A change
that weakens the audit ledger — dropping `wasSentOffDevice`, recording content
instead of length, making a read outside an approved folder indistinguishable
from a generic failure — breaks the same guarantee and will also be declined.

One more, learned the hard way: **never show a person a money statement the code
cannot back.** If a payout is not implemented, the UI says it is not
implemented. If an offer is a sample, the UI says it is a sample.

## What is most useful

- Bug fixes with a reproduction.
- Real-device findings — especially Android hardware, where we have tested on
  little.
- Accessibility fixes.
- Making the app clearer when something is wrong: a bad model file, not enough
  RAM, a revoked folder permission. Fail-closed with a plain-English reason is
  the standard.
- Linux packaging, which is thin.

## What we will probably decline

- New dependencies, unless they remove more than they add.
- A redesign sent as a finished pull request. Open an issue with a picture.
- Renaming or restructuring for tidiness alone.
- Anything that needs the account backend to be useful — that service is not
  open, so we cannot review or test your change against it.

## Standards

Match the surrounding code. Beyond that:

- **Swift** — Swift 6 with strict concurrency. Keep `AppCore` platform-agnostic;
  platform differences belong behind `NdaniPlatform`. Tests use Swift Testing.
- **Kotlin** — Compose for UI, the existing multi-module split, `ktlint`
  defaults.
- **JavaScript** — the Electron main process keeps `nodeIntegration` off and
  `contextIsolation` on. Everything the renderer needs goes through
  `preload.js`. Do not widen that bridge without a good reason.

Commit messages: one line, plain English, imperative. `Fix crash on quit when
Metal teardown races the model unload` — not `fix stuff`.

## Running the tests

```bash
# macOS + iOS
cd desktop-local && ./scripts/generate.sh && swift test --package-path Packages/AppCore
xcodebuild test -project NdaniDesktop.xcodeproj -scheme NdaniDesktop -destination 'platform=macOS'

# Android
cd android-companion && ./gradlew testDebugUnitTest

# Windows/Linux
cd desktop-windows && npm install && npm start
```

Note that Android **inference** cannot be tested on an emulator — see the README
for why. Please state which physical device you tested on.

## Pull requests

Keep them focused; one concern per pull request. Say what you tested on, and say
plainly what you did not test. "I could not test iOS, no Mac" is useful
information, not a weakness.

## Licence and sign-off

Contributions are accepted under the [Apache License 2.0](LICENSE). By opening a
pull request you confirm you have the right to contribute the code and agree to
license it under those terms. There is no CLA.

Apache-2.0 §5 covers this, so we do not ask for anything additional — but if
your employer owns your output, please sort that out on your side first.

## Security

Never in a pull request or a public issue. [SECURITY.md](SECURITY.md).
