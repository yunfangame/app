import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../FengWo-Mac-Authorization-Test.command', import.meta.url));
const probe = process.argv[2];
if (!probe) throw new Error('Usage: node toolkit-tests.mjs /absolute/path/to/FengWoProxyProbe');
const root = mkdtempSync(join(tmpdir(), 'fengwo-proxy-toolkit-'));
let passed = 0;
let failed = 0;
const before = {
  configuredProxyActive: false, tunRouteObserved: false, primaryServiceDigest: 'primary',
  logicalDigest: 'original', routeDigest: 'direct', loopbackProxyVerified: false, proxyPort: 0,
};
const write = (name, value) => {
  const path = join(root, name);
  writeFileSync(path, JSON.stringify(value) + '\n', { mode: 0o600 });
  return path;
};
function test(name, code, expected = 0, fixture = before, match = true, probeExit = 0) {
  const directory = join(root, `case-${passed + failed}`);
  mkdirSync(directory);
  writeFileSync(join(directory, 'before.json'), JSON.stringify(before));
  const state = write('state.json', fixture);
  const audit = write('audit.json', { matched: match });
  const mock = join(root, 'mock-probe');
  writeFileSync(mock, '#!/bin/bash\nif [ "$1" = audit ]; then /bin/cat "$MOCK_AUDIT"; else /bin/cat "$MOCK_STATE"; fi\nexit "$MOCK_PROBE_EXIT"\n');
  chmodSync(mock, 0o700);
  const body = 'source "$1"; FW_LOG_DIR="$2"; FW_PROBE="$3"; FW_EVENTS="$4"; fw_app_running() { return 1; }; ' + code;
  const result = spawnSync('/bin/bash', ['-c', body, '--', script, directory, mock, root], {
    encoding: 'utf8', env: { ...process.env, MOCK_STATE: state, MOCK_AUDIT: audit, MOCK_PROBE_EXIT: String(probeExit) }, timeout: 18000,
  });
  const good = result.status === expected;
  console.log(`${good ? 'PASS' : 'FAIL'} ${name} exit=${result.status}`);
  if (!good) console.log(result.stdout, result.stderr, result.error?.message ?? '');
  good ? passed++ : failed++;
}

try {
  execFileSync('/bin/bash', ['-n', script]);
  const result = JSON.parse(execFileSync(probe, ['self-test'], { encoding: 'utf8' }));
  if (!result.selfTestsPassed || result.systemSettingsWritten) throw new Error('Native probe self tests failed');
  const bad = spawnSync(probe, ['invalid-fixture-mode'], { encoding: 'utf8' });
  const failedProbe = JSON.parse(bad.stdout);
  if (bad.status !== 2 || failedProbe.readOnly !== true || failedProbe.complete !== false || failedProbe.failure.stage !== 'probe') {
    throw new Error('Failed native probe did not preserve structured diagnostics');
  }
  test('snapshot failure preserves its stage, reason and nonzero status', 'fw_snapshot before; status=$?; [ "$status" -eq 2 ] && [[ "$(<"$FW_LOG_DIR/report.txt")" == *"stage=native_auto_discovery reason=service_not_unique"* ]]', 0, {
    readOnly: true, complete: false, failure: { stage: 'native_auto_discovery', reason: 'service_not_unique' },
  }, true, 2);
  test('safe baseline is allowed', 'fw_snapshot fixture; fw_baseline_clear "$FW_LOG_DIR/fixture.json"');
  test('existing proxy is protected', 'fw_snapshot fixture; fw_baseline_clear "$FW_LOG_DIR/fixture.json"', 1, { ...before, configuredProxyActive: true });
  test('existing TUN is protected', 'fw_snapshot fixture; fw_baseline_clear "$FW_LOG_DIR/fixture.json"', 1, { ...before, tunRouteObserved: true });
  test('unknown baseline fails closed', 'fw_snapshot fixture; fw_baseline_clear "$FW_LOG_DIR/fixture.json"', 1, {});
  test('complete baseline restoration is accepted', 'fw_snapshot after; fw_restored "$FW_LOG_DIR/before.json" "$FW_LOG_DIR/after.json"');
  for (const key of ['primaryServiceDigest', 'logicalDigest', 'routeDigest']) {
    test(`changed ${key} is not restored`, 'fw_snapshot after; fw_restored "$FW_LOG_DIR/before.json" "$FW_LOG_DIR/after.json"', 1, { ...before, [key]: 'changed' });
  }
  test('connection requires isolated port and verified readback', 'fw_phase connected 0', 0, { ...before, configuredProxyActive: true, loopbackProxyVerified: true, proxyPort: 17981 });
  test('another proxy on 7890 cannot pass as the test copy', 'fw_phase connected 0', 1, { ...before, configuredProxyActive: true, loopbackProxyVerified: true, proxyPort: 7890 });
  test('readback without a successful client event cannot pass', 'fw_phase connected 0', 1, { ...before, configuredProxyActive: true, loopbackProxyVerified: true, proxyPort: 17981 }, false);
  test('disconnect requires a matching restored baseline', 'fw_phase disconnected 0');
  test('quit with process gone and restoration can pass', 'fw_phase quit 0');
  test('quit while client is still running cannot pass', 'fw_app_running() { return 0; }; fw_phase quit 0', 1);
  test('snapshot failure is never treated as success', 'fw_snapshot() { return 1; }; fw_phase quit 0', 1);
  test('EOF cannot approve a prompt', 'fw_prompt testing </dev/null', 1);
  const content = readFileSync(script, 'utf8');
  if (/sudoers|authorizationdb/.test(content.replace(/fw_log[^\n]*/g, ''))) throw new Error('Unexpected global policy command');
  if (!content.includes('--proxy \'\' --noproxy \'*\'') || content.includes('--insecure')) throw new Error('HTTPS checks are not strict');
  console.log(`SUMMARY passed=${passed} failed=${failed}; fixture tests only; no host proxy writes, app launch, authorization UI or live network test`);
} finally {
  rmSync(root, { recursive: true, force: true });
}
process.exitCode = failed ? 1 : 0;
