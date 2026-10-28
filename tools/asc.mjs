import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

export function nextBuild(versions, minimum) {
  if (!/^[1-9]\d{0,3}$/.test(minimum)) throw new Error('Minimum build must be an integer from 1 to 9999.');
  let next = Number(minimum);
  for (const version of versions) {
    if (!/^\d+(?:\.\d+){0,2}$/.test(version)) {
      throw new Error('Existing build format needs owner review; refusing to guess.');
    }
    next = Math.max(next, Number(version.split('.')[0]) + 1);
  }
  if (next > 9999) throw new Error('Build number exceeds supported range; review versioning with the owner.');
  return String(next);
}

async function main() {
  const { APP_STORE_CONNECT_KEY_ID: keyId, APP_STORE_CONNECT_ISSUER_ID: issuer,
    APP_BUNDLE_ID: bundle, MINIMUM_BUILD_NUMBER: minimum, ASC_KEY_FILE: keyFile } = process.env;
  const key = createPrivateKey(readFileSync(keyFile));
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('Use an App Store Connect ES256 API key, not another key type.');
  }
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const head = encode({ alg: 'ES256', kid: keyId, typ: 'JWT' });
  const payload = encode({ iss: issuer, iat: now - 30, exp: now + 600, aud: 'appstoreconnect-v1' });
  const unsigned = `${head}.${payload}`;
  const jwt = `${unsigned}.${sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
  async function get(url) {
    const parsed = new URL(url, 'https://api.appstoreconnect.apple.com');
    if (parsed.origin !== 'https://api.appstoreconnect.apple.com') throw new Error('Unexpected API pagination host.');
    const response = await fetch(parsed, {
      headers: { Authorization: `Bearer ${jwt}` }, signal: AbortSignal.timeout(30000), redirect: 'error',
    });
    if (!response.ok) throw new Error(`App Store Connect returned HTTP ${response.status}; check app access and API-key permissions. An APNs key cannot upload builds.`);
    return response.json();
  }
  const apps = await get(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundle)}&limit=2`);
  if (apps.data?.length !== 1) throw new Error('Create or grant API access to this app in App Store Connect first.');
  const versions = [];
  let page = `/v1/builds?filter[app]=${encodeURIComponent(apps.data[0].id)}&limit=200`;
  for (let count = 0; page; count++) {
    if (count >= 100) throw new Error('Too many build pages; refusing an incomplete version check.');
    const result = await get(page);
    if (!Array.isArray(result.data)) throw new Error('Unexpected build-list response.');
    for (const build of result.data) versions.push(build.attributes.version);
    page = result.links?.next;
  }
  console.log(nextBuild(versions, minimum));
}

if (process.argv[1]?.endsWith('asc.mjs')) {
  main().catch(error => {
    console.error(`App Store Connect preflight failed: ${error.message}`);
    process.exitCode = 1;
  });
}
