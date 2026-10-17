import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { token, evaluate } from './check-testflight.mjs';

test('Apple JWT signature is P-256 raw format with bounded lifetime', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const value = token({ ASC_KEY_ID: 'fixture', ASC_ISSUER_ID: 'fixture', ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }) }, 100);
  const [header, payload, signature] = value.split('.');
  assert.equal(Buffer.from(signature, 'base64url').length, 64);
  assert.equal(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
  assert.equal(JSON.parse(Buffer.from(payload, 'base64url')).exp, 700);
});

const fixture = () => ({
  data: [{ type: 'builds', id: 'build', attributes: { version: '20', processingState: 'VALID', expired: false, usesNonExemptEncryption: false }, relationships: {
    preReleaseVersion: { data: { type: 'preReleaseVersions', id: 'version' } },
    buildBetaDetail: { data: { type: 'buildBetaDetails', id: 'detail' } },
    betaGroups: { data: [{ type: 'betaGroups', id: 'group' }] },
  } }],
  included: [
    { type: 'preReleaseVersions', id: 'version', attributes: { version: '1.6.0' } },
    { type: 'buildBetaDetails', id: 'detail', attributes: { internalBuildState: 'IN_BETA_TESTING' } },
    { type: 'betaGroups', id: 'group', attributes: { name: 'Family testers', isInternalGroup: true } },
  ],
});
test('checks exact marketing version, processing, compliance and internal access', () => {
  assert.equal(evaluate(fixture(), '1.6.0', '20').ready, true);
  assert.equal(evaluate(fixture(), '1.5.0', '20').ready, false);
  for (const changes of [{ processingState: 'PROCESSING' }, { usesNonExemptEncryption: null }, { expired: true }]) {
    const doc = fixture(); Object.assign(doc.data[0].attributes, changes);
    assert.equal(evaluate(doc, '1.6.0', '20').ready, false);
  }
  const doc = fixture(); doc.included[2].attributes.isInternalGroup = false;
  assert.equal(evaluate(doc, '1.6.0', '20').ready, false);
  const missing = fixture(); missing.data[0].relationships.betaGroups.data = [];
  assert.equal(evaluate(missing, '1.6.0', '20').ready, false);
});
