# Client / rail boundary

Hapo Ndani's intended flow is **scope → offer → per-offer consent → payment →
provenance**. Folder access permits local reads; it does not authorize a sale.
The participant is the seller. Any offered payout must mean what the participant
receives. No file-content field belongs in a submission.

**Current state:** the public Swift core can sign typed summaries and validate a
minimal, request-bound consent response. The app screens do not yet connect a
secure key store to this flow. Electron blocks submissions and private-account
reads in its main process; Android has no network permission. No working payout
integration ships here, and this work provides no evidence of a paid participant.

The authoritative implemented wire contract is
[CONSENT_SALE_PROTOCOL.md](CONSENT_SALE_PROTOCOL.md). The earlier unsigned
`/api/offers/submit` and `/api/vault/offer` shapes are obsolete. Do not implement a
fallback to them. A signature copied from Settings is not per-offer consent.

## Try the protocol offline

From the repository root, with **Node.js 22 or newer**:

```bash
node tools/consent-proof.cjs --demo
node --test tools/tests/consent-proof.test.cjs
```

No install, account, network, model or payment is required. The committed vectors
were signed separately by Swift CryptoKit and Node crypto. They contain synthetic
text with an emoji, a combining character, a slash and a newline. Their disposable
private keys were discarded. Both byte representations verify without reordering
or normalizing the signed JSON.

The demo rejects changes to the signed summary or terms digest, a substituted
participant key, and an invented amount in a consent response. A third,
Python-signed fixture also matches a complete frozen offer to its consent digest,
and rejects changed buyer, purpose, price or contributor amount. **This verifies
integrity and terms binding, not the truth of the offer.** It does not authenticate
the response's rail, check buyer identity/licensing or funding, establish legal
consent, or prove payment. The
fixture clock is historical and fixed solely for repeatable tests.

To inspect a fresh envelope and optional consent response locally:

```bash
node tools/consent-proof.cjs --verify envelope.json receipt.json offer.json
```

This command checks the current 300-second freshness window and prints hashes and
status only, never the summary or private keys. A copied response matching the
request proves no server accepted it: authenticated transport and a durable
journal remain a rail responsibility. With an `offer.json` file the complete
flat offer is hashed using the rail's sorted-key, compact UTF-8 JSON convention;
`terms_match` is `matched` only when that digest equals the signed digest.
Omit the offer file and terms matching remains `not_checked`. Replay checking,
buyer authentication and receipt authentication remain explicitly `not_checked`.
An offer match does not establish that its buyer, rights or price are legitimate. Receipt input here is
the minimal **consent acceptance response**, not a settlement/payment receipt.

## Configuring discovery

An unset origin disables hosted features. Apple reads `NDANI_BACKEND_BASE_URL`,
then `NdaniBackendBaseURL` in Info.plist. Electron reads the same environment
variable, then `backendBaseURL` in `config.json`. Example: `https://api.example.com`.
Local model loading, journal and memory do not depend on that origin.

- `GET /api/offers/available` returns `{ "offers": [] }` when there is no demand.
  Apple accepts camelCase or snake_case field aliases and rejects conflicts.
  Required fields: id, buyer, title, description, data type, and finite payout.
  Data types: writing-style, topic-interests, work-patterns, language-use.
  No fabricated offers or verification badges are provided by the clients.
- `POST /api/consent-sale/submit` is the signed core path described in the wire
  contract. A successful consent response conveys **no accrued earnings**.
  Unavailable/non-success/malformed/unbound responses stay unavailable.
- `GET /api/balance` is an incomplete Apple integration surface, not a working
  payout rail. Missing/malformed financial fields stay unknown; they are never
  converted to zero. Secure request authentication is still a required task.
- `GET /api/updates/latest` is an optional, user-requested update check.

Electron's IPC permits only exact public discovery/update GET routes with no
body or extra options. It does not permit identity history, balance, consent,
legacy submissions or payouts. Its current offer screen remains empty; the
allowlist does not imply a connected offer-loading UI.

## Identity and its limits

The target is a locally generated Ed25519 keypair, with the public key as the
participant handle and the private key held by an OS key store. The Swift core
currently takes a caller-supplied per-use key; it does not implement custody or
recovery. The rail does not issue this signing identity.

A key is pseudonymous, not anonymous or proof of a unique human. A rail can link
submissions made with it; summaries and network metadata can reveal identity.
Payout onboarding requires its own identity controls. A payment account can help
with duplicate-account checks but does not prove one person has only one account.
Key rotation, recovery and account linking need an explicit policy before launch.

## Local provenance

`NdaniAllowedFolder` represents revocable folder scope. Apple security-scoped
bookmarks report stale access instead of silently widening permissions.
`NdaniLocalReadLedgerEntry` records a timestamp, paths, status, preview length and
`wasSentOffDevice`, without the preview content. This bounded local log records
what the app reported; it is not a network-egress monitor or immutable attestation.

The signed summary is a separate act. A consent receipt is distinct from a local
file-read record, buyer acceptance, settlement, an accrued contributor obligation
and a confirmed payment. An implementation must keep those facts separate.
