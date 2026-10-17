import { createPrivateKey, sign } from 'node:crypto';
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const origin = 'https://api.appstoreconnect.apple.com';
export function token(env, now = Math.floor(Date.now() / 1000)) {
  for (const name of ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY']) {
    if (!env[name]) throw new Error(`Missing ${name}`);
  }
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const data = `${encode({ alg: 'ES256', kid: env.ASC_KEY_ID, typ: 'JWT' })}.${encode({ iss: env.ASC_ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
  const key = createPrivateKey(env.ASC_PRIVATE_KEY);
  if (key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new Error('Expected Apple P-256 key');
  return `${data}.${sign('sha256', Buffer.from(data), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
}

export function evaluate(document, version, number) {
  const included = new Map((document.included ?? []).map(row => [`${row.type}:${row.id}`, row]));
  const build = (document.data ?? []).find(row => {
    const rel = row.relationships?.preReleaseVersion?.data;
    return row.attributes?.version === number && rel && included.get(`${rel.type}:${rel.id}`)?.attributes?.version === version;
  });
  if (!build) return { version, build: number, processingState: 'NOT_FOUND', ready: false };
  const details = build.relationships?.buildBetaDetail?.data;
  const attributes = build.attributes;
  const internalState = details ? included.get(`${details.type}:${details.id}`)?.attributes?.internalBuildState : undefined;
  const groups = (build.relationships?.betaGroups?.data ?? [])
    .map(rel => included.get(`${rel.type}:${rel.id}`))
    .filter(row => row?.attributes?.isInternalGroup)
    .map(row => ({ id: row.id, name: row.attributes.name }));
  return {
    version, build: number, id: build.id, processingState: attributes.processingState,
    usesNonExemptEncryption: attributes.usesNonExemptEncryption, internalState, internalGroups: groups,
    ready: attributes.processingState === 'VALID' && !attributes.expired &&
      attributes.usesNonExemptEncryption === false && groups.length > 0 &&
      ['IN_BETA_TESTING', 'READY_FOR_BETA_TESTING'].includes(internalState),
  };
}

async function main() {
  const env = process.env;
  const version = env.APP_VERSION;
  const number = env.BUILD_NUMBER;
  if (!/^\d+\.\d+\.\d+$/.test(version ?? '') || !/^[1-9]\d{0,8}$/.test(number ?? '')) throw new Error('Invalid version/build');
  const attempts = Number(env.STATUS_ATTEMPTS ?? 12);
  if (!Number.isInteger(attempts) || attempts < 1 || attempts > 20) throw new Error('Invalid poll count');
  const query = new URLSearchParams({ 'filter[app]': '6822451610', 'filter[version]': number, include: 'preReleaseVersion,buildBetaDetail,betaGroups', limit: '10' });
  let report;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    const response = await fetch(`${origin}/v1/builds?${query}`, {
      method: 'GET', headers: { Authorization: `Bearer ${token(env)}` },
      redirect: 'error', signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) throw new Error(`Apple status request failed: HTTP ${response.status}`);
    report = evaluate(await response.json(), version, number);
    console.log(JSON.stringify(report));
    if (report.ready) {
      if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `Verified TestFlight delivery:\n\n\`\`\`json\n${JSON.stringify(report, null, 2)}\n\`\`\`\n`);
      return;
    }
    if (['FAILED', 'INVALID'].includes(report.processingState)) throw new Error('Apple rejected build processing');
    if (attempt < attempts) await new Promise(resolve => setTimeout(resolve, 45000));
  }
  throw new Error('TestFlight processing or internal availability remains unverified');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
