# Signed consent-sale implementation

The reference Swift client can build a per-use Ed25519 envelope using CryptoKit.
The caller supplies a user signing key; no production key or custody service is
created. Existing unsigned submit and legacy fallback paths now hold rather than
transmit. The client core caps summaries at1200 Unicode scalar values; Python
uses the corresponding Unicode code points. Offer field normalization accepts
camelCase/snake_case aliases and explicitly rejects conflicting or missing terms.

`POST /api/consent-sale/submit` accepts `{participant,payload,signature}` with
unpadded base64url fields. `payload` is the exact signed UTF-8 JSON bytes; the
backend verifies Ed25519 and rejects duplicate JSON keys. Payload fields are
participant, offer_id, terms_sha256, summary, user_authored, explicit_consent,
nonce, timestamp (Unix seconds), and retention_until (Unix seconds). Consent
binds the exact summary and frozen server offer terms. Offers must specify the
buyer, language, purpose, format, license scope, acceptance criteria, provenance
policy, quantity1, price/share/reserve/fee policy and distinct platform/contributor
destinations. Research consent does not imply model-training or resale rights.

The mounted backend router is **disabled by default**, returning503. The local
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
