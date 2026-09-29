# Security Policy

## Reporting a vulnerability

**Do not open a public issue.** Report privately, either way:

- **GitHub Security Advisories** — the *Security* tab → *Report a vulnerability*.
  This is preferred; it keeps the report, the discussion and the fix together and
  private until we publish.
- **Email** — `admin@nibiashara.biz`, with `SECURITY` in the subject.

Please include:

- which app and version (macOS, iOS, Android, Windows, Linux), and the OS version
- what an attacker gets out of it
- steps to reproduce, or a proof of concept
- whether you have told anyone else

Write in English. A rough report sent early beats a polished one sent late.

## What to expect

| | |
| --- | --- |
| We acknowledge your report | within **3 business days** |
| We tell you whether we can reproduce it, and our assessment | within **10 business days** |
| We aim to ship a fix | within **90 days**, sooner for anything actively exploitable |

We are a small company and these are honest targets, not a contractual SLA. If
you have not heard from us in 3 business days, assume the mail went astray and
send it again.

You will be credited in the advisory and the release notes unless you'd rather
not be. We do not run a paid bounty programme, so we cannot offer money.

## Scope

**In scope** — the client apps in this repository:

- `desktop-local/` (macOS, iOS), `android-companion/` (Android),
  `desktop-windows/` (Windows, Linux)
- the permission ledger and folder-approval model — anything that lets the app
  read a path the user did not approve
- the local data stores — anything that exposes journal, memory or chat content
  to another app or user on the same device
- model loading — anything where a crafted model file achieves code execution
  beyond what loading a model inherently implies
- the Electron bridge in `preload.js` / `main.js` — renderer escape, IPC abuse
- the release signing configuration

**Out of scope:**

- The account backend service and `nibiashara.biz`. It is not in this repository.
  Report issues there to `admin@nibiashara.biz` — we will handle it, but it is not
  covered by this repo's advisories.
- Third-party dependencies and model runtimes (llama.swift, LiteRT-LM, Electron).
  Report upstream. Tell us too if we are using them unsafely.
- Model behaviour — jailbreaks, prompt injection into a model's own output,
  hallucination, offensive generations. Real concerns, but not vulnerabilities in
  this code. A prompt injection that reaches the **file or permission layer** is
  in scope, and we want to hear about it.
- A user's own device being compromised, or an attacker with root/physical access
  and an unlocked device.
- The Android emulator `SIGILL` in `liblitertlm_jni.so`. Known, documented in the
  README, and the app already refuses to initialise there.
- Reports generated wholesale by a scanner with no analysis attached.

## Supported versions

We support the latest released version of each app. There are no long-term
support branches.

## Please don't

Access data that isn't yours, degrade the service for others, or run automated
scans against `nibiashara.biz`. Test against your own devices and your own
builds. Report privately and give us the 90 days.

Do that, and we will treat your research as authorised and welcome, and we will
not pursue you for it.
