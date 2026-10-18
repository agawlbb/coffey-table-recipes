import { createPublicKey, X509Certificate } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { token } from './check-testflight.mjs';
import { decodeRequest, validateReplacement } from './apple-certificate-replacement.mjs';

async function request(path, method = 'GET', body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method, redirect: 'error', signal: AbortSignal.timeout(60000),
    headers: { Authorization: `Bearer ${token(process.env)}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) throw new Error(`Apple certificate request failed: HTTP ${response.status}`);
  return response.status === 204 ? null : response.json();
}

try {
  const document = await request('/v1/certificates?limit=200');
  if (document.links?.next) throw new Error('Certificate inventory unexpectedly paginated');
  for (const row of document.data) {
    const cert = new X509Certificate(Buffer.from(row.attributes.certificateContent, 'base64'));
    console.log(JSON.stringify({ id: row.id, type: row.attributes.certificateType,
      name: row.attributes.name, expires: row.attributes.expirationDate,
      sha1: cert.fingerprint.replaceAll(':', ''), sha256: cert.fingerprint256.replaceAll(':', '') }));
  }
  if (process.env.CERT_ACTION === 'replace') {
    const csr = decodeRequest(process.env.CSR_BASE64);
    // Verify the public CSR signature before any irreversible operation.
    execFileSync('openssl', ['req', '-verify', '-noout'], { input: csr, stdio: ['pipe', 'pipe', 'pipe'] });
    const requestedKey = createPublicKey(execFileSync('openssl', ['req', '-pubkey', '-noout'], { input: csr }))
      .export({ type: 'spki', format: 'der' });
    let existing = document.data.find(row => new X509Certificate(Buffer.from(row.attributes.certificateContent, 'base64'))
      .publicKey.export({ type: 'spki', format: 'der' }).equals(requestedKey));
    if (!existing) {
      const old = document.data.find(row => row.id === process.env.REVOKE_CERTIFICATE_ID);
      if (old) {
        const cert = new X509Certificate(Buffer.from(old.attributes.certificateContent, 'base64'));
        validateReplacement({ id: old.id, type: old.attributes.certificateType, name: old.attributes.name,
          sha1: cert.fingerprint.replaceAll(':', '') }, process.env.REVOKE_CERTIFICATE_ID, process.env.REVOKE_SHA1);
        await request(`/v1/certificates/${old.id}`, 'DELETE');
        console.log('Revoked only the explicitly selected temporary development certificate');
      } else {
        console.log('Selected certificate is already absent; no certificate was revoked');
      }
      existing = (await request('/v1/certificates', 'POST', { data: { type: 'certificates',
        attributes: { certificateType: 'DEVELOPMENT', csrContent: csr } } })).data;
    }
    const der = Buffer.from(existing.attributes.certificateContent, 'base64');
    if (!new X509Certificate(der).publicKey.export({ type: 'spki', format: 'der' }).equals(requestedKey)) throw new Error('Certificate public key does not match the CSR');
    mkdirSync('build/apple-public-certificate', { recursive: true });
    writeFileSync('build/apple-public-certificate/development.cer', der);
    console.log(`Replacement certificate public key verified; certificate ID ${existing.id}`);
  } else if (process.env.CERT_ACTION && process.env.CERT_ACTION !== 'inspect') {
    throw new Error('Unsupported certificate action');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
