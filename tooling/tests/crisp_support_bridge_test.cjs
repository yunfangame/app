const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const source = readFileSync(resolve(__dirname, '../../lib/common/crisp_support.dart'), 'utf8');
const script = source.match(/const crispSummaryBridgeScript = r'''([\s\S]*?)''';/)[1];

function chat({ loggedIn = true, persisted = false, acknowledge = true } = {}) {
  const data = { support_summary_sent: persisted };
  const sent = [];
  const events = [];
  let handler;
  let registrations = 0;
  let fail = false;
  const window = {
    fengwoSupportBound: true,
    fengwoSupportProfile: { data: { logged_in: loggedIn }, summary: 'account summary' },
    FengwoSupportReady: { postMessage: value => events.push(value) },
    $crisp: {
      get: (_, key) => data[key],
      push: ([action, key, value]) => {
        if (action === 'on') { handler = value; registrations++; }
        if (action === 'set') for (const [key, entry] of value[0]) data[key] = entry;
        if (action === 'do' && key === 'message:send') {
          if (fail) throw new Error('SDK failure');
          sent.push(value[1]);
          if (acknowledge) handler({ from: 'user', type: 'text', content: value[1] });
        }
      },
    },
  };
  const context = vm.createContext({ window });
  vm.runInContext(script, context);
  return {
    window, data, sent, events,
    send: (content = 'hello') => handler({ from: 'user', type: 'text', content }),
    receive: () => handler({ from: 'operator', type: 'text', content: 'reply' }),
    reinject: () => vm.runInContext(script, context),
    fail: value => { fail = value; },
    registrations: () => registrations,
  };
}

test('opening and operator replies never send a summary', () => {
  const state = chat();
  state.receive();
  assert.deepEqual(state.sent, []);
});

test('only the first visitor message triggers a summary without recursion', () => {
  const state = chat();
  state.send();
  state.send('another question');
  assert.deepEqual(state.sent, ['account summary']);
  assert.equal(state.data.support_summary_sent, true);
  assert.deepEqual(state.events, ['summary_sent']);
});

test('anonymous visitors never send account information', () => {
  const state = chat({ loggedIn: false });
  state.send();
  assert.deepEqual(state.sent, []);
});

test('reopening and profile refresh install only one listener and use current data', () => {
  const state = chat();
  state.window.fengwoSupportProfile.summary = 'updated plan';
  state.reinject();
  state.send();
  assert.equal(state.registrations(), 1);
  assert.deepEqual(state.sent, ['updated plan']);
});

test('a restored session does not send its summary again', () => {
  const state = chat({ persisted: true });
  state.send();
  assert.deepEqual(state.sent, []);
});

test('multiple messages while awaiting acknowledgment do not duplicate the summary', () => {
  const state = chat({ acknowledge: false });
  state.send();
  state.send('next');
  assert.deepEqual(state.sent, ['account summary']);
  assert.equal(state.data.support_summary_sent, false);
  state.send('account summary');
  assert.equal(state.data.support_summary_sent, true);
});

test('a synchronous SDK failure can retry on the next visitor message', () => {
  const state = chat();
  state.fail(true);
  state.send();
  assert.equal(state.data.support_summary_sent, false);
  state.fail(false);
  state.send('retry');
  assert.deepEqual(state.sent, ['account summary']);
  assert.deepEqual(state.events, ['summary_failed', 'summary_sent']);
});
