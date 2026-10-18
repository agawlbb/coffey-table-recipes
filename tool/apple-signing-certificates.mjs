import { X509Certificate } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { token } from './check-testflight.mjs';

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
  // This workflow initially supports inventory only. Certificate mutations require
  // a separately reviewed operation and explicit owner authorization.
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
