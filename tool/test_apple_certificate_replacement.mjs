import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeRequest, validateReplacement } from './apple-certificate-replacement.mjs';

test('revocation requires exact selected temporary development identity', () => {
  const row = { id: 'UH5NHSV67V', type: 'DEVELOPMENT', name: 'Apple Development: Created via API', sha1: '02CA6CF204A5A828CE04B345C76B53265EDB59DA' };
  validateReplacement(row, row.id, row.sha1);
  for (const changed of [{ type: 'DISTRIBUTION' }, { type: 'IOS_DEVELOPMENT' }, { name: 'Personal certificate' }, { sha1: '0'.repeat(40) }, { id: 'OTHERID123' }]) {
    assert.throws(() => validateReplacement({ ...row, ...changed }, row.id, row.sha1));
  }
});

test('only public CSR format is accepted', () => {
  const csr = '-----BEGIN CERTIFICATE REQUEST-----\nZml4dHVyZQ==\n-----END CERTIFICATE REQUEST-----\n';
  assert.equal(decodeRequest(Buffer.from(csr).toString('base64')), csr);
  for (const value of ['', '-----BEGIN PRIVATE KEY-----\nZml4dHVyZQ==\n-----END PRIVATE KEY-----', 'x'.repeat(9000)]) {
    assert.throws(() => decodeRequest(Buffer.from(value).toString('base64')));
  }
});
