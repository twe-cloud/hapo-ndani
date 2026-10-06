# Signed consent-sale implementation

The reference Swift client can build a per-use Ed25519 envelope using CryptoKit.
The caller supplies a user signing key; no production key or custody service is
created. Unsigned submit and legacy fallback paths hold rather than transmit in both
Apple and Electron clients. Electron permits public discovery GETs only. The
Swift core is not yet connected to secure key custody or the app consent UI. The client core caps summaries at 1200 Unicode scalar values; Python
uses the corresponding Unicode code points. Offer field normalization accepts
camelCase/snake_case aliases and explicitly rejects conflicting or missing terms.

`POST /api/consent-sale/submit` accepts `{participant,payload,signature}` with
unpadded base64url fields. `payload` is the exact signed UTF-8 JSON bytes; the
backend verifies Ed25519 and rejects duplicate JSON keys. Payload fields are
participant, offer_id, terms_sha256, summary, user_authored, explicit_consent,
nonce, timestamp (Unix seconds), and retention_until (Unix seconds). Consent
binds the exact summary and frozen server offer terms. Offers must specify the
buyer, language, purpose, format, license scope, acceptance criteria, provenance
policy, quantity 1, price/share/reserve/fee policy and distinct platform/contributor
destinations. Research consent does not imply model-training or resale rights.

The mounted backend router is **disabled by default**, returning 503. The local
journal API is implemented and tested, but no production store, buyer catalog,
authenticated settlement transport, payout rail or retention scheduler is bound.
Ephemeral deployment disk cannot be treated as a durable financial journal.
Per-use signing is not a verified identity, copyright grant, KYC or buyer license.
All test data and money are synthetic. Pricing configuration is internal planning,
not a public offer, broker bid, subscription, funded payout promise or inventory.

The journal serializes writers with a file lock and publishes a complete fsynced
atomic state. It rejects conflicting nonce/source/transaction/receipt replays.
Matched buyer settlement plus accepted delivery creates a durable contributor
obligation. It does not mark money paid. A separate matched contributor receipt
is required. The Shelves SDK boundary receives actual SDK after-settlement
contexts, checks chain/asset/destination/atomic amount and transaction identity,
and produces only an allocation candidate. Its installed bridge has no live
lookup/transport/delivery/payout callback; Shelf Passes are not new transactions.

Signed `/api/consent-sale/withdraw` removes retained summary content and blocks
future delivery. Expiry also removes summary content; financial provenance and
accrued obligations remain. Settled-but-undelivered records become
refund_or_reconciliation_pending, without initiating a refund. Already delivered
buyer copies cannot be recalled by a local delete. Monetary withdrawal remains
unavailable. The journal retains no raw signed payload/envelope copy beyond the
single summary field; audit uses hashes and minimal settlement records.

Production activation requires verified persistent storage and retention
execution, registered user key/identity policy, real buyer licensing/funded terms,
authenticated settlement-to-submission binding and an authorized payout adapter.
None is implied by local tests or an SDK status alone.

## Public conformance contract

Run `node tools/consent-proof.cjs --demo` from the repository root (Node.js 22+).
The fixture in `protocol/fixtures/consent-v1.json` contains independently signed
Swift and Node envelopes. Whitespace and object order differ deliberately:
verify the transmitted bytes, never a reserialized or normalized object.
All data and consent responses are synthetic; no private signing key is stored.

Envelope fields are exactly participant, payload, signature; unpadded canonical
base64url only. Public key length is 32 bytes; signature length is 64. Payload
must be strict UTF-8 JSON with the exact fields above and no duplicate keys,
nested fields, unpaired surrogates or nonfinite numbers. A summary is nonblank
and at most 1200 Unicode scalar values; offer ID is nonblank and at most 512;
nonce is 16–128 scalars. Terms digest is 64 lowercase hexadecimal characters.
The base64url payload is at most 16000 characters (at most 12000 decoded bytes). Both timestamps use integer JSON
literals (no decimal or exponent notation) and are positive safe integers (at most 9007199254740991), retention
is after signing, and the rail enforces its offer's retention limit plus a
300-second freshness window. `explicit_consent` and `user_authored` must be true
booleans. Client checks do not replace server nonce/replay, terms or policy checks.

A successful consent response has exactly these fields:

```json
{
  "submission_id": "64 lowercase hex characters",
  "request_sha256": "SHA-256 of the exact decoded payload bytes",
  "status": "consented",
  "payout_status": "unverified",
  "contributor_obligation_cents": null,
  "withdrawal_available": false
}
```

This is **not a payment receipt**. Offline verification checks integrity and
binding, not server acceptance, authenticated transport, buyer identity, funding,
legal adequacy or payment. Supply the complete frozen offer to the verifier to
check its digest against the signed terms; otherwise terms matching stays
`not_checked`. The flat offer uses strings, true/false, null and safe integers;
its canonical bytes use Unicode codepoint key ordering, compact JSON, UTF-8,
no slash escaping and no Unicode normalization. Decimal/exponent money values,
nested values and unpaired surrogates are rejected by this helper.

`protocol/fixtures/frozen-offer-v1.json` adds a Python-signed, complete synthetic
offer and a consent response accepted by an isolated local journal. Its canonical
offer bytes are compared directly in Node tests; changing buyer, purpose, licence,
price, contributor amount or retention breaks the binding. These are test terms,
not a funded offer or price quote. No fixture is authorized for live submission.
