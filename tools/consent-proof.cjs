#!/usr/bin/env node
'use strict';

// Offline conformance helper. No network, dependencies, key store or money moves.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { TextDecoder } = require('node:util');
const fail = (reason) => { throw new Error(reason); };
const hex64 = (s) => typeof s === 'string' && /^[a-f0-9]{64}$/.test(s);
const scalarLength = (s) => [...s].length;
const fields = ['participant', 'offer_id', 'terms_sha256', 'summary', 'user_authored',
  'explicit_consent', 'nonce', 'timestamp', 'retention_until'];

function exactKeys(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
      || Object.keys(value).sort().join('|') !== [...keys].sort().join('|')) fail('unexpected_fields');
}

function decodeBase64url(value, length) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) fail('invalid_base64url');
  const raw = Buffer.from(value, 'base64url');
  if (raw.toString('base64url') !== value || (length !== undefined && raw.length !== length)) fail('invalid_base64url');
  return raw;
}

// These protocol objects are flat. A token scan catches duplicate keys, including
// escaped aliases, BEFORE JSON.parse can silently discard one. Nested values are
// deliberately rejected; the closed payload has no file or arbitrary-object slot.
function parseFlatJSON(raw) {
  let source;
  try { source = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(raw); }
  catch { fail('invalid_utf8'); }
  if (source.charCodeAt(0) === 0xfeff) fail('invalid_utf8');
  let i = 0;
  const space = () => { while (/[\x20\t\r\n]/.test(source[i] || '\0')) i++; };
  const token = /"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/y;
  const take = () => { space(); token.lastIndex = i; const m = token.exec(source); if (!m) fail('invalid_json'); i = token.lastIndex; return m[0]; };
  const seen = new Set();
  space(); if (source[i++] !== '{') fail('invalid_json'); space();
  if (source[i] !== '}') {
    while (true) {
      const keyToken = take(); if (!keyToken.startsWith('"')) fail('invalid_json');
      const key = JSON.parse(keyToken); if (seen.has(key)) fail('duplicate_key'); seen.add(key);
      space(); if (source[i++] !== ':') fail('invalid_json');
      const valueToken = take();
      if (/^-?[0-9]/.test(valueToken) && !/^-?[0-9]+$/.test(valueToken)) fail('integer_required');
      space();
      if (source[i] !== ',') break;
      i++;
    }
  }
  if (source[i++] !== '}') fail('invalid_json'); space(); if (i !== source.length) fail('invalid_json');
  const value = JSON.parse(source);
  for (const v of Object.values(value)) {
    if (typeof v === 'number' && !Number.isFinite(v)) fail('invalid_number');
    if (typeof v === 'string' && !v.isWellFormed()) fail('invalid_unicode');
  }
  return value;
}

function verifyConsent(envelope, { now } = {}) {
  exactKeys(envelope, ['participant', 'payload', 'signature']);
  if (typeof envelope.payload !== 'string' || envelope.payload.length > 16000) fail('payload_too_large');
  const publicKey = decodeBase64url(envelope.participant, 32);
  const signature = decodeBase64url(envelope.signature, 64);
  const raw = decodeBase64url(envelope.payload);
  if (raw.length > 12000) fail('payload_too_large');
  const payload = parseFlatJSON(raw);
  exactKeys(payload, fields);
  if (payload.participant !== envelope.participant) fail('participant_mismatch');
  if (typeof payload.offer_id !== 'string' || !payload.offer_id.trim() || scalarLength(payload.offer_id) > 512) fail('invalid_offer');
  if (!hex64(payload.terms_sha256)) fail('invalid_terms');
  if (typeof payload.summary !== 'string' || !payload.summary.trim() || scalarLength(payload.summary) > 1200) fail('invalid_summary');
  if (payload.explicit_consent !== true || payload.user_authored !== true) fail('explicit_consent_required');
  if (typeof payload.nonce !== 'string' || scalarLength(payload.nonce) < 16 || scalarLength(payload.nonce) > 128) fail('invalid_nonce');
  if (![payload.timestamp, payload.retention_until].every((n) => Number.isSafeInteger(n) && n > 0)
      || payload.retention_until <= payload.timestamp) fail('invalid_timestamp');
  const key = crypto.createPublicKey({ key: Buffer.concat([
    Buffer.from('302a300506032b6570032100', 'hex'), publicKey,
  ]), format: 'der', type: 'spki' });
  if (!crypto.verify(null, raw, key, signature)) fail('invalid_signature');
  if (now !== undefined) {
    if (!Number.isSafeInteger(now) || now <= 0) fail('invalid_clock');
    if (Math.abs(now - payload.timestamp) > 300 || payload.retention_until <= now) fail('stale_consent');
  }
  return { signature_valid: true, request_sha256: crypto.createHash('sha256').update(raw).digest('hex'),
    freshness: now === undefined ? 'not_checked' : 'within_window', terms_match: 'not_checked', replay_check: 'not_checked', buyer_authentication: 'not_checked',
    funding_status: 'unverified', payment_status: 'unverified' };
}

// Frozen offers currently contain flat strings/booleans/null and integer money.
// Match Python's sort_keys/compact/ensure_ascii=False without normalizing text.
function canonicalOffer(offer) {
  if (!offer || typeof offer !== 'object' || Array.isArray(offer)) fail('invalid_frozen_offer');
  const scalarCompare = (a, b) => {
    const x = [...a], y = [...b];
    for (let i = 0; i < Math.min(x.length, y.length); i++) {
      const d = x[i].codePointAt(0) - y[i].codePointAt(0); if (d) return d;
    }
    return x.length - y.length;
  };
  const pairs = Object.keys(offer).sort(scalarCompare).map(key => {
    const value = offer[key];
    if (!key.isWellFormed() || !(value === null || typeof value === 'boolean'
      || (typeof value === 'string' && value.isWellFormed())
      || (typeof value === 'number' && Number.isSafeInteger(value)))) fail('invalid_frozen_offer');
    return JSON.stringify(key) + ':' + JSON.stringify(value);
  });
  return Buffer.from('{' + pairs.join(',') + '}', 'utf8');
}

function verifyFrozenOffer(envelope, offer, options = {}) {
  const proof = verifyConsent(envelope, options);
  const payload = parseFlatJSON(decodeBase64url(envelope.payload));
  const hash = crypto.createHash('sha256').update(canonicalOffer(offer)).digest('hex');
  if (hash !== payload.terms_sha256) fail('frozen_offer_mismatch');
  // These are the amount and buyer in the signed offer, NOT verified funding,
  // buyer identity, acceptance or an earned contributor obligation.
  return { ...proof, terms_match: 'matched', terms_sha256: hash };
}

function verifyReceipt(receipt, proof) {
  exactKeys(receipt, ['submission_id', 'request_sha256', 'status', 'payout_status',
    'contributor_obligation_cents', 'withdrawal_available']);
  if (!hex64(receipt.submission_id) || receipt.request_sha256 !== proof.request_sha256
      || receipt.status !== 'consented' || receipt.payout_status !== 'unverified'
      || receipt.contributor_obligation_cents !== null || receipt.withdrawal_available !== false) fail('invalid_consent_receipt');
  return { ...proof, consent_response_matches: true, receipt_authentication: 'not_checked', payment_status: 'unverified', withdrawal_available: false };
}

module.exports = { parseFlatJSON, canonicalOffer, verifyConsent, verifyFrozenOffer, verifyReceipt };

if (require.main === module) {
  try {
    if (process.argv[2] === '--demo') {
      const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, '../protocol/fixtures/consent-v1.json'), 'utf8'));
      for (const vector of fixtures.vectors) {
        const proof = verifyReceipt(vector.receipt, verifyConsent(vector.envelope, { now: fixtures.test_clock }));
        console.log(`${vector.producer}: exact-byte Ed25519 signature and hash-bound consent response PASS`);
        for (const [label, alter] of [
          ['summary', (s) => s.replace('synthetic:', 'tampered:')],
          ['terms', (s) => s.replace('a'.repeat(64), 'b'.repeat(64))],
        ]) {
          const altered = { ...vector.envelope, payload: Buffer.from(alter(Buffer.from(vector.envelope.payload, 'base64url').toString('utf8'))).toString('base64url') };
          let rejected = false;
          try { verifyConsent(altered); } catch (error) { if (error.message === 'invalid_signature') rejected = true; else throw error; }
          if (!rejected) fail('tampering_was_accepted');
          console.log(`${vector.producer}: changed ${label} rejected`);
        }
        let keyRejected = false, amountRejected = false;
        try { verifyConsent({ ...vector.envelope, participant: fixtures.vectors.find(v => v !== vector).envelope.participant }); } catch { keyRejected = true; }
        try { verifyReceipt({ ...vector.receipt, contributor_obligation_cents: 500 }, proof); } catch { amountRejected = true; }
        if (!keyRejected || !amountRejected) fail('tampering_was_accepted');
        console.log(`${vector.producer}: changed key and invented amount rejected; payment=${proof.payment_status}, withdrawal=${proof.withdrawal_available}`);
      }
      const frozen = JSON.parse(fs.readFileSync(path.join(__dirname, '../protocol/fixtures/frozen-offer-v1.json'), 'utf8'));
      const bound = verifyFrozenOffer(frozen.envelope, frozen.offer, { now: frozen.test_clock });
      verifyReceipt(frozen.receipt, bound);
      for (const change of [{ buyer: 'changed buyer' }, { contributor_cents: frozen.offer.contributor_cents + 1 },
        { buyer_price_cents: frozen.offer.buyer_price_cents + 1 }, { purpose: 'model training' }]) {
        let rejected = false;
        try { verifyFrozenOffer(frozen.envelope, { ...frozen.offer, ...change }); } catch (error) { if (error.message === 'frozen_offer_mismatch') rejected = true; else throw error; }
        if (!rejected) fail('changed_offer_was_accepted');
      }
      console.log('Python signed offer: full frozen terms MATCH; changed buyer, price, contributor amount and purpose REJECTED');
      console.log(JSON.stringify(verifyReceipt(frozen.receipt, bound), null, 2));
      console.log('Synthetic offline proof only. No buyer, consent collection, network call or payment.');
    } else if (process.argv[2] === '--verify' && process.argv[3]) {
      const envelope = parseFlatJSON(fs.readFileSync(process.argv[3]));
      const options = { now: Math.floor(Date.now() / 1000) };
      const proof = process.argv[5]
        ? verifyFrozenOffer(envelope, parseFlatJSON(fs.readFileSync(process.argv[5])), options)
        : verifyConsent(envelope, options);
      const result = process.argv[4] ? verifyReceipt(parseFlatJSON(fs.readFileSync(process.argv[4])), proof) : proof;
      console.log(JSON.stringify(result, null, 2));
    } else {
      fail('Usage: node tools/consent-proof.cjs --demo | --verify envelope.json [receipt.json [offer.json]]');
    }
  } catch (error) { console.error(`Consent proof rejected: ${error.message}`); process.exitCode = 1; }
}
