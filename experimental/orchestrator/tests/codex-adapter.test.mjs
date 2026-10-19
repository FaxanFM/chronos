import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { CodexAdapter } from '../lib/codex-adapter.mjs';

function fakeTransport() {
  const t = new EventEmitter();
  t.sent = [];
  t.send = (message) => {
    t.sent.push(message);
    queueMicrotask(() => {
      if (message.method === 'initialize') t.emit('message', { jsonrpc: '2.0', id: message.id, result: {} });
      else if (message.method === 'account/read') t.emit('message', { jsonrpc: '2.0', id: message.id, result: { requiresOpenaiAuth: false, account: null } });
      else if (message.method === 'config/read') t.emit('message', { jsonrpc: '2.0', id: message.id, result: { config: { mcp_servers: {} }, origins: {} } });
      else if (message.method === 'mcpServerStatus/list') t.emit('message', { jsonrpc: '2.0', id: message.id, result: { data: [], nextCursor: null } });
      else if (['thread/start', 'thread/fork'].includes(message.method)) t.emit('message', { jsonrpc: '2.0', id: message.id, result: { thread: { id: 'owned-thread' }, cwd: message.params.cwd, approvalPolicy: 'never', sandbox: message.params.sandbox === 'workspace-write' ? { type: 'workspaceWrite', writableRoots: [message.params.cwd], networkAccess: false } : { type: 'readOnly' }, model: 'host-default', modelProvider: 'host' } });
      else if (message.method === 'thread/goal/clear') t.emit('message', { jsonrpc: '2.0', id: message.id, result: {} });
      else if (message.method === 'command/exec') t.emit('message', { jsonrpc: '2.0', id: message.id, result: { exitCode: 0, stdout: 'native verification', stderr: '' } });
      else if (message.method === 'turn/start') t.emit('message', { jsonrpc: '2.0', id: message.id, result: { turn: { id: 'owned-turn' } } });
      else if (message.method === 'turn/interrupt') t.emit('message', { jsonrpc: '2.0', id: message.id, result: {} });
    });
  };
  t.onMessage = (cb) => t.on('message', cb); t.close = () => {};
  return t;
}

test('starts only an owned task and omits a model override by default', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ transportFactory: async () => transport });
  await adapter.connect(); const started = await adapter.startTask({ id: 'task-1', instruction: 'read only' });
  assert.deepEqual(started, { threadId: 'owned-thread', turnId: 'owned-turn' });
  assert.equal(transport.sent.find((x) => x.method === 'thread/start').params.model, undefined);
  await assert.rejects(() => adapter.interruptTask({ threadId: 'other-thread' }), /task_not_owned/); await adapter.close();
});

test('fails closed when the host requires OpenAI login but has no account', async () => {
  const transport = fakeTransport();
  const original = transport.send;
  transport.send = (message) => {
    if (message.method === 'account/read') {
      queueMicrotask(() => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { requiresOpenaiAuth: true, account: null } }));
      return;
    }
    original(message);
  };
  const adapter = new CodexAdapter({ transportFactory: async () => transport });
  await assert.rejects(() => adapter.connect(), /codex_login_required/);
  assert.equal(adapter.connected, false);
});

test('fails closed on a malformed account status response', async () => {
  const transport = fakeTransport(); const original = transport.send;
  transport.send = (message) => {
    if (message.method === 'account/read') { queueMicrotask(() => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: {} })); return; }
    original(message);
  };
  const adapter = new CodexAdapter({ transportFactory: async () => transport });
  await assert.rejects(() => adapter.connect(), /codex_account_status_unavailable/);
});

test('rejects a host that does not return the requested read-only policy', async () => {
  const transport = fakeTransport(); const original = transport.send;
  transport.send = (message) => { if (message.method === 'thread/start') queueMicrotask(() => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { thread: { id: 'owned-thread' }, approvalPolicy: 'on-request', sandbox: { type: 'workspaceWrite' } } })); else original(message); };
  const adapter = new CodexAdapter({ transportFactory: async () => transport }); await adapter.connect();
  await assert.rejects(() => adapter.startTask({ id: 'task-1', instruction: 'read only' }), /codex_policy_mismatch/); assert.equal(adapter.connected, false); await adapter.close();
});

test('fails closed when inherited MCP servers are present', async () => {
  const transport = fakeTransport(); const original = transport.send;
  transport.send = (message) => {
    if (message.method === 'mcpServerStatus/list') {
      queueMicrotask(() => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { data: [{ name: 'unexpected' }], nextCursor: null } }));
      return;
    }
    original(message);
  };
  const adapter = new CodexAdapter({ transportFactory: async () => transport }); await adapter.connect();
  await assert.rejects(() => adapter.startTask({ id: 'task-1', instruction: 'read only' }), /codex_external_tools_not_isolated/);
  assert.equal(adapter.connected, false);
});

test('passes explicit per-thread disable overrides for inherited MCP names', async () => {
  const transport = fakeTransport(); const original = transport.send; let config;
  transport.send = (message) => {
    if (message.method === 'config/read') {
      queueMicrotask(() => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { config: { mcp_servers: { local: {}, remote: {} } }, origins: {} } })); return;
    }
    if (message.method === 'thread/start') config = message.params.config;
    original(message);
  };
  const adapter = new CodexAdapter({ transportFactory: async () => transport }); await adapter.connect(); await adapter.startTask({ id: 'task-1', instruction: 'read only' });
  assert.deepEqual(config.mcp_servers, { local: { enabled: false }, remote: { enabled: false } });
  assert.equal(config.web_search, 'disabled'); assert.equal(config.sandbox_workspace_write.network_access, false); await adapter.close();
});

test('workspace writes require an explicitly registered root and constrain the native policy', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ cwd: process.cwd(), transportFactory: async () => transport });
  await adapter.connect();
  await assert.rejects(adapter.startTask({ id: 'write', policy: 'workspace-write', instruction: 'Write one fixture.' }), /workspace_write_root_not_registered/);
  await adapter.allowWorkspace(process.cwd());
  await adapter.startTask({ id: 'write', policy: 'workspace-write', instruction: 'Write one fixture.' });
  const turn = transport.sent.find((message) => message.method === 'turn/start');
  assert.equal(turn.params.sandboxPolicy.type, 'workspaceWrite');
  assert.deepEqual(turn.params.sandboxPolicy.writableRoots, [process.cwd()]);
  assert.equal(turn.params.sandboxPolicy.networkAccess, false);
  assert.equal(adapter.diagnostics().effectivePolicy.sandbox, 'workspaceWrite');
  await adapter.close();
});

test('a selected deep link forks context with native goal continuation disabled', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ transportFactory: async () => transport }); await adapter.connect();
  const source = '01a151cc-f0c6-7572-aa76-7db9477460b1';
  await adapter.startTask({ id: 'linked', instruction: 'Continue the bounded task.', sourceThreadLink: 'codex://threads/' + source });
  const fork = transport.sent.find((message) => message.method === 'thread/fork');
  assert.equal(fork.params.threadId, source); assert.equal(fork.params.excludeTurns, true); assert.equal(fork.params.deferGoalContinuation, true);
  assert.equal(fork.params.config.features.goals, false);
  assert.equal(transport.sent.some((message) => message.method === 'thread/goal/clear'), false);
  assert.equal(transport.sent.some((message) => message.method === 'thread/resume'), false);
  await adapter.close();
});

test('native verification uses explicit sandbox policy and bounded output', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ cwd: process.cwd(), transportFactory: async () => transport }); await adapter.connect();
  const result = await adapter.verifyCommand({ command: ['node', '--test'], policy: 'read-only', taskId: 'verify' });
  assert.equal(result.exitCode, 0);
  const request = transport.sent.find((message) => message.method === 'command/exec');
  assert.equal(request.params.sandboxPolicy.type, 'readOnly'); assert.equal(request.params.timeoutMs, 60000);
  await assert.rejects(adapter.verifyCommand({ command: [], taskId: 'bad' }), /verification_command_invalid/);
  await adapter.close();
});

test('accepts disabled MCP metadata only when its catalogs are empty', async () => {
  const transport = fakeTransport(); const original = transport.send;
  transport.send = (message) => {
    if (message.method === 'mcpServerStatus/list') {
      queueMicrotask(() => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { data: [{ runtimeStatus: 'disabled', tools: {}, resources: [], resourceTemplates: [] }], nextCursor: null } })); return;
    }
    original(message);
  };
  const adapter = new CodexAdapter({ transportFactory: async () => transport }); await adapter.connect();
  await adapter.startTask({ id: 'task-1', instruction: 'read only' }); await adapter.close();
});

test('denies approval requests and emits bounded task events', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ transportFactory: async () => transport }); const events = [];
  adapter.on('task-event', (event) => events.push(event)); await adapter.connect(); await adapter.startTask({ id: 'task-1', instruction: 'read only' });
  transport.emit('message', { jsonrpc: '2.0', id: 99, method: 'item/guardian/approval/request', params: { threadId: 'owned-thread', turnId: 'owned-turn' } });
  assert.equal(transport.sent.at(-1).error.message, 'Chronos adapter denies approval requests'); assert.equal(events.at(-1).kind, 'approval-required'); await adapter.close();
});

test('does not mistake an interrupt acknowledgement for termination', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ transportFactory: async () => transport }); const events = [];
  adapter.on('task-event', (event) => events.push(event)); await adapter.connect(); await adapter.startTask({ id: 'task-1', instruction: 'read only' });
  await adapter.interruptTask({ threadId: 'owned-thread' });
  assert.equal(events.some((event) => event.kind === 'interrupted'), false);
  transport.emit('message', { jsonrpc: '2.0', method: 'turn/interrupted', params: { threadId: 'owned-thread', turnId: 'owned-turn' } });
  assert.equal(events.at(-1).kind, 'interrupted'); await adapter.close();
});

test('ignores foreign and failed turn events while preserving bounded failure output', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ transportFactory: async () => transport }); const events = [];
  adapter.on('task-event', (event) => events.push(event)); await adapter.connect(); await adapter.startTask({ id: 'task-1', instruction: 'read only' });
  transport.emit('message', { jsonrpc: '2.0', method: 'turn/completed', params: { threadId: 'other', turnId: 'x', text: 'foreign' } });
  transport.emit('message', { jsonrpc: '2.0', method: 'turn/failed', params: { threadId: 'owned-thread', turnId: 'owned-turn', text: 'x'.repeat(3000) } });
  assert.equal(events.length, 1); assert.equal(events[0].kind, 'failed'); assert.equal(events[0].summary.length, 2000); await adapter.close();
});

test('requires terminal status and captures only agent-message text', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ transportFactory: async () => transport }); const events = [];
  adapter.on('task-event', (event) => events.push(event)); await adapter.connect(); await adapter.startTask({ id: 'task-1', instruction: 'read only' });
  transport.emit('message', { jsonrpc: '2.0', method: 'turn/completed', params: { threadId: 'owned-thread', turn: { id: 'owned-turn', status: { type: 'idle' } } } });
  assert.equal(events.length, 0);
  transport.emit('message', { jsonrpc: '2.0', method: 'item/completed', params: { threadId: 'owned-thread', turn: { id: 'owned-turn' }, item: { type: 'agentMessage', text: 'bounded result' } } });
  assert.equal(events.at(-1).kind, 'progress');
  transport.emit('message', { jsonrpc: '2.0', method: 'turn/completed', params: { threadId: 'owned-thread', turn: { id: 'owned-turn', status: { type: 'completed' } } } });
  assert.equal(events.at(-1).kind, 'completed'); assert.equal(events.at(-1).summary, 'bounded result'); await adapter.close();
});

test('diagnostics expose bounded protocol state without payloads', async () => {
  const transport = fakeTransport(); const adapter = new CodexAdapter({ transportFactory: async () => transport }); await adapter.connect();
  await adapter.startTask({ id: 'task-1', instruction: 'read only' });
  transport.emit('message', { jsonrpc: '2.0', method: 'turn/completed', params: { threadId: 'owned-thread', turn: { id: 'owned-turn', status: { type: 'completed' } }, text: 'secret prompt' } });
  const d = adapter.diagnostics(); assert.equal(d.connected, true); assert.equal(d.lastMethod, 'turn/completed'); assert.equal(d.lastStatus, 'completed'); assert.equal('text' in d, false); assert.equal(d.ownedTaskCount, 1); await adapter.close();
});
