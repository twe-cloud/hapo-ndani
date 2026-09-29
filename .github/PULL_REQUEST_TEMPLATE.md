<!--
Security fixes do not go in a public pull request. See SECURITY.md.
For anything beyond a bug fix, please open an issue first — CONTRIBUTING.md
explains why.
-->

## What this changes

<!-- One or two sentences. Link the issue: Fixes #123 -->

## Why

<!-- What problem does it solve? -->

## How it was tested

<!--
Be specific about hardware, and honest about gaps. "I could not test iOS, no
Mac" is useful information, not a weakness.
-->

- [ ] macOS — `swift test --package-path Packages/AppCore` and an `xcodebuild` build
- [ ] iOS — built for a simulator or a device
- [ ] Android — `./gradlew testDebugUnitTest`, plus a **physical device** if this touches inference
- [ ] Windows / Linux — `npm start`
- [ ] Not tested on: <!-- list platforms and say why -->

Device(s) used:

## Checklist

- [ ] No telemetry, analytics, crash reporting, or hosted inference was added to a local code path
- [ ] The app still works with the machine offline
- [ ] No new dependency, or the addition is justified above
- [ ] No secret, key, certificate, provisioning profile, Team ID, or model weight is in the diff
- [ ] Failure paths report a plain-English reason rather than failing silently
- [ ] I have the right to contribute this code and license it under Apache-2.0
