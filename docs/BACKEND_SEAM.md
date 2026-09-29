# The consent rail protocol

This is the boundary between the open client and a consent rail. It is written
as a **specification**, not as instructions for filling in our URL — you can
implement it yourself, and the clients in this repository will talk to your
implementation.

The clients here are a **reference implementation**. Everything about consent,
scope, the audit ledger and the local data store is in this repository and runs
without any server. The rail handles the parts that need a counterparty: what is
on offer, and moving money to the user.

## The flow being specified

```
  ┌─────────────┐
  │   1. SCOPE  │  The user grants access to a named folder. Revocable,
  │             │  per-folder, stored on device. No scope, no read.
  └──────┬──────┘
         │
  ┌──────▼──────┐
  │   2. OFFER  │  The rail publishes what a buyer wants and what it pays.
  │             │  The user sees the buyer, the price and the ask up front.
  └──────┬──────┘
         │
  ┌──────▼──────┐
  │  3. CONSENT │  The user writes their own summary and chooses to submit it.
  │             │  Per-offer. Nothing is inferred, scraped or pre-filled.
  └──────┬──────┘
         │
  ┌──────▼──────┐
  │   4. PAY    │  The payout accrues to the user, not to the platform.
  │             │  Balance and withdrawal eligibility are user-visible.
  └──────┬──────┘
         │
  ┌──────▼──────┐
  │ 5. PROVENANCE│ Every local read is written to an append-only ledger,
  │             │  including whether it ever left the device.
  └─────────────┘
```

Steps 1, 3 and 5 are **local and open** — they are in this repository. Steps 2
and 4 need a rail.

## Two invariants

An implementation that breaks either of these is not implementing this protocol.

1. **The user is the seller.** The payout in an offer is what the *user*
   receives. The rail may take a fee, but the number shown to the user is what
   reaches the user.
2. **Nothing leaves the device without a per-offer act.** Granting folder scope
   is not consent to sell. The submission in step 3 is a separate, explicit
   action for one offer, carrying text the user wrote themselves. The client
   never uploads file contents — only the user's own summary.

The reference clients enforce the second invariant structurally: the submission
payload has no field for file contents.

## Configuring a rail

One value per platform. An origin with no trailing slash, e.g.
`https://api.example.com`. Unset, the rail features report that they are
switched off; local chat, journal, memory and the ledger are unaffected.

| Platform | Source, in order | File |
| --- | --- | --- |
| macOS, iOS | `NDANI_BACKEND_BASE_URL` env, then `NdaniBackendBaseURL` in Info.plist | `desktop-local/Packages/AppCore/Sources/AppCore/NdaniBackendConfig.swift` |
| Windows, Linux | `NDANI_BACKEND_BASE_URL` env, then `backendBaseURL` in `config.json` | `desktop-windows/main.js` (copy `config.example.json`) |
| Android | — | No rail calls. Local-only by construction. |

Every call site treats an unconfigured rail as "feature unavailable", never as an
error. `NdaniBackendConfig.url(_:)` returns `nil`; the Electron IPC handlers
return `{ ok: false, error: 'no_backend_configured' }`.

## Endpoints

Six, relative to the configured origin. JSON in, JSON out.

### 2. Offer

**`GET /api/offers/available`**

```json
{
  "offers": [
    {
      "id": "string",
      "buyer": "string",
      "buyerVerified": false,
      "title": "string",
      "description": "string",
      "dataType": "writing-style | topic-interests | work-patterns | language-use",
      "payoutUSD": 5.0,
      "spotsLeft": 200,
      "tags": ["string"],
      "expiresAt": "YYYY-MM-DD"
    }
  ]
}
```

`buyerVerified` is a claim **your rail is making and must be able to
substantiate.** The reference clients ship example offers with this field absent
and render no verification badge, because a reference implementation cannot
verify anybody. If you set it true, be prepared to say what you checked.

`dataType` is a closed set — see `NdaniVaultDataType` in `StarterAppState.swift`.

### 3. Consent and submission

**`POST /api/offers/submit`**

```json
{ "participant": "base64url ed25519 public key", "offer_id": "string",
  "data_type": "string",
  "title": "string", "summary": "string" }
```

Response:

```json
{ "submission_id": "string", "offer_id": "string",
  "payout_usd": 5.0, "message": "string" }
```

On refusal, return `detail` with a reason the user can act on. `summary` is text
the user typed; the reference clients cap it at 1200 characters. **There is no
field for file contents, and adding one would break invariant 2.**

**`POST /api/vault/offer`** — the earlier submission path, kept as a fallback.
Same shape without `offer_id`; responds with `{ offer_id, credit_code,
credit_amount_usd, message }`.

**`GET /api/vault/history?participant=&sig=`** — prior submissions for a participant.

### 4. Payment

**`GET /api/balance?participant=&sig=`**

```json
{ "balance_usd": 0.0, "total_earned_usd": 0.0, "total_paid_out_usd": 0.0,
  "can_withdraw": false, "stripe_connected": false }
```

All fields optional; missing numbers read as `0`, missing booleans as `false`.

`can_withdraw` is the rail's answer, and the client trusts it — so it must
reflect a real, reachable withdrawal, not an aspiration. **Payout request is not
implemented in the reference clients.** `desktop-windows` states plainly that
payouts are unavailable in the build rather than implying money is moving.

### Updates

**`GET /api/updates/latest`** — `{ version, release_notes, download_url }`, all
three required. **Only fetched when the user presses a button.** Do not design a
manifest expecting polling.

## Participant identity

**The app is free.** There is no licence, no activation and no purchase. That
removed what the earlier protocol used to identify a participant, and the
replacement is a deliberate design choice rather than a rename.

**The client generates a keypair locally. The public key is the identity. The
rail issues nothing.**

### The contract

- On first use of a rail feature, the client generates an **Ed25519 keypair**
  and stores the private key in the platform keystore (Keychain on Apple
  platforms, the OS credential store elsewhere). It never leaves the device
  and is never transmitted.
- The **public key**, base64url-encoded, is the `participant` value on every
  rail call. The rail treats it as an opaque account handle.
- Every submission carries a **detached signature** over a canonical
  serialization of the payload, including a timestamp and a single-use nonce
  so a captured submission cannot be replayed.
- The rail **verifies the signature against the public key it was given**. It
  issues no credential, so there is no credential for it to revoke, correlate
  across products, or leak.
- Rotation is the participant generating a new keypair. The rail treats that
  as a new account, because from its side it is one.

### What this does and does not buy

It buys a real property: **a rail cannot link a participant to anything it was
not handed.** There is no issued identifier tying submissions to a purchase, a
device, an email, or an account the rail created. It also removes a whole class
of failure — there is no credential database to breach.

It does **not** buy anonymity, and this spec will not imply that it does:

- A rail sees every submission made under one public key, so submissions are
  **linkable to each other**. That is unavoidable if a balance is to accrue.
- A person writing a summary about their own habits can **identify themselves
  in the text**, whatever the protocol does.
- **Payout requires identity.** Money moves through a payment processor, and
  that processor performs KYC. The moment a participant withdraws, a real
  legal identity attaches to that public key.

So the line is drawn deliberately, and it is worth stating to a participant in
plain words: **the rail learns who you are when you take money out, not when
you submit.** Submission is pseudonymous; withdrawal is not, and it cannot be.
A rail that claims otherwise is either not paying people or not telling the
truth.

### Sybil resistance moved, and you must notice

Under the old paid model, fabricating a participant cost the price of a
licence. **The app is free now, so generating a keypair costs nothing** — a
public key is not a scarce resource, and nothing stops one person minting
thousands.

The scarcity moved to the payout leg: a payment processor's KYC'd account is
the thing that is hard to duplicate. A rail must therefore treat **the payout
account, not the public key, as the unit of uniqueness** for anything that
depends on one-person-one-submission — per-person caps, duplicate detection,
fraud limits. Enforcing a cap per public key enforces nothing at all.

### Reference client status

The clients in this repository **do not implement signing yet.** They send a
`participant` value and pass a `signature` field straight through without
generating or verifying anything. The keypair scheme above is the specified
target and the field shapes already match it; the cryptography is the gap.

Being precise about that, because it matters to anyone building against this:
**a rail must not treat the current clients' `signature` field as
authenticated.** It carries whatever the client was given. Implementing
Ed25519 generation, storage and signing is a welcome contribution.

## Local primitives, for reference## Local primitives, for reference

Not endpoints. These are in this repository and are what the rail is consenting
*against*.

**Scope** — `NdaniAllowedFolder { id, displayName, path, bookmarkData,
isBookmarkStale }`. macOS/iOS use security-scoped bookmarks, so a grant can go
stale and is reported as stale rather than silently retried.

**Provenance** — `NdaniLocalReadLedgerEntry { id, timestamp, folderPath,
filePath, status, previewLength, wasSentOffDevice }`. Append-only, bounded,
persisted locally. `wasSentOffDevice` is the field that makes the claim
auditable: a read is recorded with whether it ever left the machine.
`previewLength` records the size of what was read without recording the content.

**Read status** — `noFolder`, `stalePermission`, `accessDenied`,
`outsideApprovedFolder`, `missingFile`, `unreadable`, `ready`. A read outside an
approved folder is a distinct, reported outcome, not a generic failure.

## If you implement this

The awkward thing about this protocol is worth saying out loud: steps 2 through
4 move a person's own writing to a counterparty for money, which cuts against
everything steps 1, 3 and 5 exist to protect. That tension is the whole design
problem, and it is why the invariants above are invariants.

If you run a rail, be at least as explicit with your users as you would want a
rail to be with you. Show the buyer. Show the price. Never pre-fill the summary.
Never present a sample as live demand.
