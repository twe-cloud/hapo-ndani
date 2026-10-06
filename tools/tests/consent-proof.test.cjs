'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const { parseFlatJSON, canonicalOffer, verifyConsent, verifyFrozenOffer, verifyReceipt } = require('../consent-proof.cjs');
const { allowedRailRead } = require('../../desktop-windows/rail-policy');
const fixtures = require('../../protocol/fixtures/consent-v1.json');
const textOf = (envelope) => Buffer.from(envelope.payload, 'base64url').toString('utf8');
const mutate = (envelope, fn) => ({ ...envelope, payload: Buffer.from(fn(textOf(envelope))).toString('base64url') });

for (const vector of fixtures.vectors) {
  test(`${vector.producer}: exact bytes, Unicode and consent response interoperate`, () => {
    const proof = verifyConsent(vector.envelope, { now: fixtures.test_clock });
    assert.equal(proof.request_sha256, vector.receipt.request_sha256);
    assert.equal(verifyReceipt(vector.receipt, proof).payment_status, 'unverified');
    assert.match(textOf(vector.envelope), /🙂/u);
  });
  test(`${vector.producer}: summary and frozen terms tampering fail`, () => {
    for (const alter of [s => s.replace('synthetic:', 'tampered:'), s => s.replace('a'.repeat(64), 'b'.repeat(64))]) {
      assert.throws(() => verifyConsent(mutate(vector.envelope, alter)), /invalid_signature/);
    }
    const other = fixtures.vectors.find(v => v !== vector).envelope.participant;
    assert.throws(() => verifyConsent({ ...vector.envelope, participant: other }), /participant_mismatch/);
    assert.throws(() => verifyConsent({ ...vector.envelope, signature: 'A'.repeat(86) }), /invalid_signature/);
  });
  test(`${vector.producer}: consent response cannot invent payment or obligation`, () => {
    const proof = verifyConsent(vector.envelope);
    for (const change of [{contributor_obligation_cents:500}, {payout_status:'paid'},
      {withdrawal_available:true}, {request_sha256:'f'.repeat(64)}, {withdrawal_available:0}, {amount:500}]) {
      assert.throws(() => verifyReceipt({...vector.receipt,...change}, proof));
    }
    assert.throws(() => verifyConsent(vector.envelope, {now:fixtures.test_clock+301}), /stale_consent/);
  });
}

test('flat UTF-8 JSON parser rejects ambiguity before parsing', () => {
  for (const text of ['{"nonce":"a","nonce":"b"}', '{"nonce":"a","no\\u006ece":"b"}']) {
    assert.throws(() => parseFlatJSON(Buffer.from(text)), /duplicate_key/);
  }
  for (const raw of [Buffer.from('{"x":1}', 'utf16le'), Buffer.from([0xff]), Buffer.from('{"x":"\\ud800"}'),
    Buffer.from('{"x":{"file":"content"}}'), Buffer.from('{"x":1e999}'), Buffer.from('{"x":1,}')]) {
    assert.throws(() => parseFlatJSON(raw));
  }
  assert.deepEqual(parseFlatJSON(Buffer.from(' {"x": "quotes \\\" and slash /", "y": true}\n')), {x:'quotes " and slash /', y:true});
});

test('valid signatures do not authorize malformed or expanded payloads', () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const participant = publicKey.export({format:'der',type:'spki'}).subarray(-32).toString('base64url');
  const base = {...JSON.parse(textOf(fixtures.vectors[0].envelope)), participant};
  const signed = (payload) => { const raw=Buffer.from(JSON.stringify(payload)); return {participant,payload:raw.toString('base64url'),signature:crypto.sign(null,raw,privateKey).toString('base64url')}; };
  for (const change of [{summary:' '}, {summary:'🙂'.repeat(1201)}, {explicit_consent:1},
    {user_authored:false}, {terms_sha256:'Z'.repeat(64)}, {nonce:'x'.repeat(129)},
    {timestamp:1.5}, {timestamp:0}, {retention_until:Number.MAX_SAFE_INTEGER+1},
    {retention_until:base.timestamp}, {offer_id:'x'.repeat(513)}, {files:'content'}]) {
    assert.throws(() => verifyConsent(signed({...base,...change})));
  }
  assert.equal(verifyConsent(signed({...base,summary:'🙂'.repeat(1200)})).signature_valid, true);
  const envelope = signed(base);
  for (const field of ['participant','payload','signature']) {
    assert.throws(() => verifyConsent({...envelope,[field]:envelope[field]+'='}), /invalid_base64url/);
  }
});

test('Electron main-process boundary refuses signed, unsigned, legacy and payout writes', () => {
  for (const endpoint of ['/api/offers/submit','/api/vault/offer','/api/consent-sale/submit',
    '/api/consent-sale/withdraw','/api/payout/request','/api/balance?participant=x','https://example.test',
    '/api/offers/available?summary=private','/api/updates/latest/../offers/submit']) {
    assert.equal(allowedRailRead(endpoint),false);
    assert.equal(allowedRailRead(endpoint,{method:'POST',body:{summary:'typed text'}}),false);
  }
  for (const endpoint of ['/api/offers/available','/api/updates/latest']) {
    assert.equal(allowedRailRead(endpoint),true);
    assert.equal(allowedRailRead(endpoint,{method:'GET'}),true);
    for(const options of [null,[],{method:'POST'},{body:'text'},{headers:{private:'text'}}]) {
      assert.equal(allowedRailRead(endpoint, options),false);
    }
  }
  assert.match(fs.readFileSync(require.resolve('../../desktop-windows/main.js'),'utf8'), /if \(!allowedRailRead\(endpoint, options\)\)/);
});


test('signed decimal/exponent timestamps cannot masquerade as integer JSON tokens', () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const participant = publicKey.export({format:'der',type:'spki'}).subarray(-32).toString('base64url');
  const fields = {...JSON.parse(textOf(fixtures.vectors[0].envelope)), participant};
  for (const field of ['timestamp','retention_until']) {
    for (const token of ['1700000000.0', '17e8']) {
      const raw = Buffer.from(JSON.stringify(fields).replace(new RegExp(`"${field}":[0-9]+`), `"${field}":${token}`));
      const envelope = {participant,payload:raw.toString('base64url'),signature:crypto.sign(null,raw,privateKey).toString('base64url')};
      assert.throws(() => verifyConsent(envelope), /integer_required/);
    }
  }
  const raw = Buffer.from(JSON.stringify(fields) + ' '.repeat(16000));
  assert.throws(() => verifyConsent({participant,payload:raw.toString('base64url'),signature:crypto.sign(null,raw,privateKey).toString('base64url')}), /payload_too_large/);
});


test('full Python frozen offer matches; changed buyer, scope, price and contributor amount fail', () => {
  const fixture = require('../../protocol/fixtures/frozen-offer-v1.json');
  assert.equal(canonicalOffer(fixture.offer).toString('utf8'), fixture.canonical_offer_utf8);
  const proof = verifyFrozenOffer(fixture.envelope, fixture.offer, {now:fixture.test_clock});
  assert.equal(proof.terms_match, 'matched');
  assert.equal(proof.terms_sha256, fixture.terms_sha256);
  assert.equal(proof.buyer_authentication, 'not_checked');
  assert.equal(proof.replay_check, 'not_checked');
  assert.equal(verifyReceipt(fixture.receipt, proof).payment_status,'unverified');
  for (const change of [{buyer:'different buyer'}, {purpose:'training'}, {contributor_cents:151},
    {buyer_price_cents:301}, {license_scope:'resale allowed'}, {retention_until:1700099999}]) {
    assert.throws(() => verifyFrozenOffer(fixture.envelope,{...fixture.offer,...change}), /frozen_offer_mismatch/);
  }
  assert.throws(() => canonicalOffer({...fixture.offer, contributor_cents:150.5}), /invalid_frozen_offer/);
  // Python orders by Unicode codepoint, not UTF-16 code unit or locale.
  assert.equal(canonicalOffer({'🙂':1,'\uffff':2}).toString('utf8'), '{"\uffff":2,"🙂":1}');
});
