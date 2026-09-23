const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const source = readFileSync(resolve(__dirname, '../../lib/common/crisp_support.dart'), 'utf8');
const summaryScript = source.match(/const crispSummaryBridgeScript = r'''([\s\S]*?)''';/)[1];
const bootstrapTemplate = source.match(/String crispBootstrapScript\([\s\S]*?=>\s*'''([\s\S]*?)''';/)[1];

function fakeTimers() {
  let now = 0;
  let nextId = 0;
  const tasks = new Map();
  const schedule = (callback, delay, repeat) => {
    const id = ++nextId;
    tasks.set(id, { callback, at: now + delay, repeat });
    return id;
  };
  return {
    setTimeout: (callback, delay = 0) => schedule(callback, delay, 0),
    clearTimeout: id => tasks.delete(id),
    setInterval: (callback, delay) => schedule(callback, delay, delay),
    clearInterval: id => tasks.delete(id),
    Date: { now: () => now },
    pending: () => tasks.size,
    advance: (duration = 0) => {
      const until = now + duration;
      while (true) {
        const next = [...tasks.entries()]
          .filter(([, task]) => task.at <= until)
          .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
        if (!next) break;
        const [id, task] = next;
        now = task.at;
        if (task.repeat) task.at += task.repeat;
        else tasks.delete(id);
        task.callback();
      }
      now = until;
    },
  };
}

function chat({ loggedIn = true, persisted = false, acknowledge = true } = {}) {
  const timers = fakeTimers();
  const data = { support_summary_sent: persisted };
  const sent = [];
  const events = [];
  let handler;
  let registrations = 0;
  let fail = false;
  let sessionId = 'session-a';
  let handlingMessage = false;
  let reentered = false;
  const emit = message => {
    const wasHandling = handlingMessage;
    handlingMessage = true;
    try { handler(message); }
    finally { handlingMessage = wasHandling; }
  };
  const window = {
    ...timers,
    fengwoSupportBound: true,
    fengwoSupportProfile: {
      email: 'customer@example.com',
      data: { logged_in: loggedIn },
      summary: 'account summary',
    },
    FengwoSupportReady: { postMessage: value => events.push(value) },
    $crisp: {
      get: (key, name) => key === 'session:identifier' ? sessionId : data[name],
      push: ([action, key, value]) => {
        if (action === 'on' && key === 'message:sent') {
          handler = value;
          registrations++;
        }
        if (action === 'set' && key === 'session:data') {
          for (const [name, entry] of value[0]) data[name] = entry;
        }
        if (action === 'do' && key === 'message:send') {
          reentered ||= handlingMessage;
          if (fail) throw new Error('SDK failure');
          sent.push(value[1]);
          if (acknowledge) emit({ from: 'user', type: 'text', content: value[1] });
        }
      },
    },
  };
  const context = vm.createContext({ window, ...timers });
  vm.runInContext(summaryScript, context);
  return {
    window, data, sent, events, timers, emit,
    send: (content = 'hello') => emit({ from: 'user', type: 'text', content }),
    flush: () => timers.advance(),
    reinject: () => vm.runInContext(summaryScript, context),
    fail: value => { fail = value; },
    setSession: value => { sessionId = value; },
    registrations: () => registrations,
    reentered: () => reentered,
  };
}

function bootstrap({
  sessionId = 'session-a',
  sdkReady = true,
  url = 'https://go.crisp.chat/chat/embed/?website_id=website&token_id=test-token&session_merge=false',
} = {}) {
  const timers = fakeTimers();
  const events = [];
  const commands = [];
  const handlers = new Map();
  const location = new URL(url);
  const window = {
    ...timers,
    location,
    FengwoSupportReady: { postMessage: value => events.push(value) },
  };
  const sdk = {
    get: key => key === 'session:identifier' ? sessionId : null,
    push: command => {
      commands.push(command);
      const [action, key, value] = command;
      if (action === 'on') handlers.set(key, value);
      if (action === 'off') handlers.delete(key);
    },
  };
  window.$crisp = sdkReady ? sdk : [];
  const context = vm.createContext({ window, location, URL, URLSearchParams, ...timers });
  const script = bootstrapTemplate
    .replaceAll('${jsonEncode(sessionToken)}', JSON.stringify('test-token'))
    .replaceAll('\\$', '$');
  const inject = () => vm.runInContext(script, context);
  inject();
  return {
    window, events, commands, timers, inject,
    load: value => {
      sessionId = value;
      handlers.get('session:loaded')?.(value);
    },
    setSdkReady: () => { window.$crisp = sdk; },
  };
}

function countSessionListeners(state) {
  return state.commands.filter(([action, key]) => action === 'on' && key === 'session:loaded').length;
}

test('opening, malformed messages, empty text, and operator replies never send a summary', () => {
  const state = chat();
  for (const message of [
    null,
    undefined,
    {},
    { from: 'user' },
    { from: 'user', type: 'text', content: '' },
    { from: 'user', type: 'text', content: ' \n\t ' },
    { from: 'user', type: 'text', content: {} },
    { from: 'user', type: 'file', content: {} },
    { from: 'user', type: 'file', content: null },
    { from: 'operator', type: 'text', content: 'reply' },
    { type: 'text', content: 'unknown sender' },
  ]) state.emit(message);
  state.flush();
  assert.deepEqual(state.sent, []);
  assert.deepEqual(state.events, []);
  assert.equal(state.timers.pending(), 0);
});

test('only the first visitor message triggers a deferred summary without reentering the SDK', () => {
  const state = chat();
  state.send();
  state.send('another question');
  assert.deepEqual(state.sent, []);
  assert.equal(state.timers.pending(), 1);
  state.flush();
  state.send('after summary');
  state.flush();
  assert.deepEqual(state.sent, ['account summary']);
  assert.equal(state.reentered(), false);
  assert.equal(state.data.support_summary_sent, true);
  assert.deepEqual(state.events, ['summary_sent']);
});

test('a nonempty visitor attachment can trigger the summary', () => {
  const state = chat();
  state.emit({ from: 'user', type: 'file', content: { url: 'https://example.com/file.png' } });
  state.flush();
  assert.deepEqual(state.sent, ['account summary']);
});

test('anonymous visitors never send account information', () => {
  const state = chat({ loggedIn: false });
  state.send();
  state.flush();
  assert.deepEqual(state.sent, []);
});

test('reopening installs only one listener and uses profile data refreshed before sending', () => {
  const state = chat();
  state.send();
  state.window.fengwoSupportProfile = {
    ...state.window.fengwoSupportProfile,
    summary: 'updated plan and client version',
  };
  state.reinject();
  state.flush();
  assert.equal(state.registrations(), 1);
  assert.deepEqual(state.sent, ['updated plan and client version']);
});

test('restored sessions with boolean or string markers do not send their summary again', () => {
  for (const persisted of [true, 'true']) {
    const state = chat({ persisted });
    state.send();
    state.flush();
    assert.deepEqual(state.sent, []);
  }
});

test('a marker received before the deferred send cancels the summary', () => {
  const state = chat();
  state.send();
  state.data.support_summary_sent = true;
  state.flush();
  assert.deepEqual(state.sent, []);
});

test('matching visitor text before an attempted send is not mistaken for acknowledgment', () => {
  const state = chat({ acknowledge: false });
  state.send('account summary');
  state.send('account summary');
  assert.equal(state.data.support_summary_sent, false);
  assert.deepEqual(state.events, []);
  state.flush();
  assert.deepEqual(state.sent, ['account summary']);
  assert.equal(state.data.support_summary_sent, false);
  state.send('account summary');
  assert.equal(state.data.support_summary_sent, true);
});

test('messages awaiting asynchronous acknowledgment do not duplicate the summary', () => {
  const state = chat({ acknowledge: false });
  state.send();
  state.flush();
  state.send('next');
  state.flush();
  assert.deepEqual(state.sent, ['account summary']);
  assert.equal(state.data.support_summary_sent, false);
  state.emit({ from: 'operator', type: 'text', content: 'account summary' });
  assert.equal(state.data.support_summary_sent, false);
  state.send('account summary');
  state.send('account summary');
  assert.equal(state.data.support_summary_sent, true);
  assert.deepEqual(state.events, ['summary_sent']);
});

for (const [name, change] of [
  ['a different session', state => state.setSession('session-b')],
  ['a missing session', state => state.setSession(null)],
  ['logout', state => { state.window.fengwoSupportProfile.data.logged_in = false; }],
  ['a different account', state => { state.window.fengwoSupportProfile.email = 'other@example.com'; }],
  ['an unbound page', state => { state.window.fengwoSupportBound = false; }],
  ['an empty refreshed summary', state => { state.window.fengwoSupportProfile.summary = ' \n '; }],
]) {
  test(`${name} cancels a scheduled summary`, () => {
    const state = chat();
    state.send();
    change(state);
    state.flush();
    assert.deepEqual(state.sent, []);
    assert.equal(state.data.support_summary_sent, false);
  });
}

test('a missing session cannot schedule an account summary', () => {
  const state = chat();
  state.setSession(null);
  state.send();
  state.flush();
  assert.deepEqual(state.sent, []);
});

for (const [name, change] of [
  ['a changed session', state => state.setSession('session-b')],
  ['logout', state => { state.window.fengwoSupportProfile.data.logged_in = false; }],
  ['a different account', state => { state.window.fengwoSupportProfile.email = 'other@example.com'; }],
  ['an unbound page', state => { state.window.fengwoSupportBound = false; }],
]) {
  test(`a late acknowledgment after ${name} cannot mark the session as summarized`, () => {
    const state = chat({ acknowledge: false });
    state.send();
    state.flush();
    change(state);
    state.send('account summary');
    assert.equal(state.data.support_summary_sent, false);
    assert.deepEqual(state.events, []);
  });
}

test('a synchronous SDK failure can retry on the next visitor message', () => {
  const state = chat();
  state.fail(true);
  state.send();
  state.flush();
  assert.equal(state.data.support_summary_sent, false);
  state.fail(false);
  state.send('retry');
  state.flush();
  assert.deepEqual(state.sent, ['account summary']);
  assert.deepEqual(state.events, ['summary_failed', 'summary_sent']);
});

test('an already loaded token session becomes ready without resetting or reopening it', () => {
  const state = bootstrap();
  state.timers.advance(50);
  assert.equal(state.window.fengwoSupportBound, true);
  assert.deepEqual(state.events, ['ready']);
  assert.equal(countSessionListeners(state), 1);
  assert.equal(state.commands.some(([action]) => action === 'do'), false);
  assert.equal(Object.hasOwn(state.window, 'CRISP_TOKEN_ID'), false);
  assert.equal(state.timers.pending(), 0);
});

test('bootstrap waits for the SDK and a delayed session-loaded event', () => {
  const state = bootstrap({ sessionId: null, sdkReady: false });
  state.timers.advance(100);
  assert.deepEqual(state.events, []);
  state.setSdkReady();
  state.timers.advance(50);
  assert.deepEqual(state.events, []);
  assert.equal(state.window.fengwoSupportBound, false);
  state.load('session-delayed');
  assert.equal(state.window.fengwoSupportBound, true);
  assert.deepEqual(state.events, ['ready']);
});

test('duplicate bootstrap injection and loaded events report readiness only once', () => {
  const state = bootstrap({ sessionId: null });
  state.inject();
  state.timers.advance(50);
  state.load('session-a');
  state.load('session-a');
  state.inject();
  state.timers.advance(100);
  assert.deepEqual(state.events, ['ready']);
  assert.equal(countSessionListeners(state), 1);
});

for (const url of [
  'http://go.crisp.chat/chat/embed/?token_id=test-token',
  'https://other.example.com/chat/embed/?token_id=test-token',
  'https://go.crisp.chat/other/?token_id=test-token',
  'https://go.crisp.chat/chat/embed/',
  'https://go.crisp.chat/chat/embed/?token_id=wrong-token',
]) {
  test(`bootstrap rejects an unexpected origin, path, or token: ${url}`, () => {
    const state = bootstrap({ url });
    state.timers.advance(100);
    assert.deepEqual(state.events, []);
    assert.deepEqual(state.commands, []);
    assert.notEqual(state.window.fengwoSupportBound, true);
    assert.equal(state.timers.pending(), 0);
  });
}

test('bootstrap stops polling after the SDK loading timeout', () => {
  const state = bootstrap({ sdkReady: false });
  state.timers.advance(45100);
  assert.equal(state.timers.pending(), 0);
  state.setSdkReady();
  state.timers.advance(100);
  assert.deepEqual(state.events, []);
  assert.deepEqual(state.commands, []);
});
