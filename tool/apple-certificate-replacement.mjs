export function validateReplacement(row, id, fingerprint) {
  if (!/^[A-Z0-9]{10}$/.test(id) || !/^[A-F0-9]{40}$/.test(fingerprint)) throw new Error('Invalid certificate selection');
  if (row.id !== id || row.type !== 'DEVELOPMENT' || row.name !== 'Apple Development: Created via API' || row.sha1 !== fingerprint) {
    throw new Error('Refusing to revoke a certificate that is not the selected temporary API development identity');
  }
}

export function decodeRequest(encoded) {
  const csr = Buffer.from(encoded ?? '', 'base64').toString('utf8').trim();
  if (csr.length > 8192 || !/^-----BEGIN CERTIFICATE REQUEST-----\r?\n[A-Za-z0-9+/=\r\n]+\r?\n-----END CERTIFICATE REQUEST-----$/.test(csr)) {
    throw new Error('Expected a public CSR; private keys are never accepted');
  }
  return csr + '\n';
}
