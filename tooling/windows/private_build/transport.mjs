import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createHash, randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';
import { gzipSync, gunzipSync } from 'node:zlib';
import assert from 'node:assert/strict';

const paths = [
  'plugins/proxy/windows/proxy_session.h',
  'plugins/proxy/windows/proxy_settings.h',
  'plugins/proxy/windows/proxy_plugin.cpp',
  'plugins/proxy/windows/test/proxy_session_test.cpp',
  'plugins/proxy/windows/test/proxy_session_windows_test.cpp',
  'test/common/windows_proxy_trace_log_test.dart',
];
const sha = value => createHash('sha256').update(value).digest('hex');
const save = (path, value) => writeFileSync(path, value, { flag: 'wx', mode: 0o600 });
const mode = process.argv[2];
const secretName = 'FENGWO_RAS_20261021_OVERLAY';
const keyName = 'FENGWO_RAS_20261021_ARTIFACT_KEY';

function seal(data, key) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from('FENGWO-RAS-20261021'));
  const body = Buffer.concat([cipher.update(data), cipher.final()]);
  return Buffer.concat([Buffer.from('FWRAS001'), nonce, cipher.getAuthTag(), body]);
}

function open(data, key) {
  assert.equal(data.subarray(0, 8).toString(), 'FWRAS001');
  const cipher = createDecipheriv('aes-256-gcm', key, data.subarray(8, 20));
  cipher.setAAD(Buffer.from('FENGWO-RAS-20261021'));
  cipher.setAuthTag(data.subarray(20, 36));
  return Buffer.concat([cipher.update(data.subarray(36)), cipher.final()]);
}

if (mode === 'prepare') {
  const [source, qa] = process.argv.slice(3);
  const expected = JSON.parse(readFileSync(join(qa, 'completion.json'))).sources;
  const files = paths.map(path => {
    const data = readFileSync(join(source, path));
    const hash = sha(data);
    assert.equal(hash, expected.find(file => file.path === path).sha256);
    assert.deepEqual(Buffer.from(data.toString('utf8'), 'utf8'), data);
    return { path, sha256: hash, content: data.toString('utf8') };
  });
  const data = gzipSync(JSON.stringify({ version: 1, files }), { level: 9 }).toString('base64');
  assert.ok(data.length < 48000, 'Overlay exceeds GitHub secret size');
  save(join(qa, 'private-overlay.secret'), data);
  save(join(qa, 'artifact-key.secret'), randomBytes(32).toString('base64'));
  console.log(JSON.stringify({ files: files.map(({ path, sha256 }) => ({ path, sha256 })), secretBytes: data.length }));
} else if (mode === 'apply') {
  const root = resolve(process.argv[3]);
  const encoded = process.env[secretName];
  assert.ok(encoded && encoded.length < 48000);
  const payload = JSON.parse(gunzipSync(Buffer.from(encoded, 'base64'), { maxOutputLength: 512000 }));
  assert.equal(payload.version, 1);
  assert.deepEqual(payload.files.map(file => file.path), paths);
  const manifest = [];
  for (const file of payload.files) {
    const data = Buffer.from(file.content, 'utf8');
    assert.equal(sha(data), file.sha256);
    const destination = resolve(root, file.path);
    assert.ok(destination.startsWith(root + (process.platform === 'win32' ? '\\' : '/')));
    assert.ok(existsSync(destination), 'Overlay may only replace existing tracked files');
    writeFileSync(destination, data);
    manifest.push({ path: file.path, sha256: file.sha256, bytes: data.length });
  }
  const evidence = join(process.env.RUNNER_TEMP, 'desktop-coexistence-evidence');
  mkdirSync(evidence, { recursive: true });
  save(join(evidence, 'private-overlay-manifest.json'), JSON.stringify({ baseline: '6f3957175e03aeeb21acdcd742817f54d01ae482', files: manifest }, null, 2));
  console.log('Verified six-file private overlay applied');
} else if (mode === 'seal' || mode === 'open') {
  const [input, output, keyFile] = process.argv.slice(3);
  const key = Buffer.from(keyFile ? readFileSync(keyFile, 'utf8').trim() : process.env[keyName], 'base64');
  assert.equal(key.length, 32);
  const result = mode === 'seal' ? seal(readFileSync(input), key) : open(readFileSync(input), key);
  save(output, result);
  console.log(JSON.stringify({ mode, bytes: result.length, sha256: sha(result) }));
} else if (mode === 'selftest') {
  const key = randomBytes(32);
  const data = randomBytes(1024);
  const encrypted = seal(data, key);
  assert.deepEqual(open(encrypted, key), data);
  encrypted[40] ^= 1;
  assert.throws(() => open(encrypted, key));
  assert.throws(() => open(seal(data, key), randomBytes(32)));
  console.log('PASS: authenticated artifact encryption round trip and tamper rejection');
} else {
  throw new Error('Unknown transport mode');
}
