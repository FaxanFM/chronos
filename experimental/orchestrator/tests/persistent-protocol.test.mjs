import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { realpath } from 'node:fs/promises';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { protocolCapabilities } from '../lib/protocol-capabilities.mjs';

const threadId = '11111111-1111-4111-8111-111111111111';
const schema = {
  oneOf: ['thread/start', 'thread/resume', 'thread/read', 'turn/start', 'thread/compact/start', 'thread/unsubscribe', 'thread/archive', 'thread/list'].map((method) => ({ method: { enum: [method] } })),
  lifecycleContract: { sourceKinds: ['appServer', 'subAgent', 'unknown'], thread: { parentThreadId: {} }, listResponse: { nextCursor: {} }, ancestorFilter: true, omittedCursorIsEnd: true }
};
async function host(overrides = {}) {
  const t = new EventEmitter(); t.sent = [];
  t.onMessage = (cb) => t.on('message', cb); t.close = () => {};
  const emit = (method, params) => t.emit('message', { jsonrpc: '2.0', method, params });
  t.send = (message) => {
    t.sent.push(message);
    queueMicrotask(() => {
      let result = {};
      if (overrides[message.method]) return overrides[message.method](message, t, emit);
      if (message.method === 'account/read') result = { requiresOpenaiAuth: false, account: null };
      if (message.method === 'config/read') result = { config: { mcp_servers: {} } };
      if (message.method === 'model/list' || message.method === 'mcpServerStatus/list') result = { data: [], nextCursor: null };
      if (message.method === 'thread/start' || message.method === 'thread/resume') result = { thread: { id: threadId, cwd: process.cwd(), model: 'host-default', status: { type: 'idle' } }, cwd: process.cwd(), model: 'host-default', approvalPolicy: 'never', sandbox: { type: 'readOnly', networkAccess: false } };
      if (message.method === 'thread/read') result = { thread: { id: threadId, cwd: process.cwd(), status: { type: 'idle' } } };
      if (message.method === 'thread/list') result = { data: [], nextCursor: null };
      if (message.method === 'thread/archive') { emit('thread/archived', { threadId }); emit('thread/closed', { threadId }); }
      if (message.method === 'thread/unsubscribe') result = { status: 'notLoaded' };
      if (message.method === 'thread/compact/start') emit('thread/compacted', { threadId });
      if (message.id != null) t.emit('message', { jsonrpc: '2.0', id: message.id, result });
    });
  };
  const adapter = new CodexAdapter({ cwd: process.cwd(), protocolSchema: schema, transportFactory: async () => t });
  await adapter.connect();
  const spec = { sessionId: 'session-1', agentId: 'agent-1', projectId: 'project-1', workItemId: 'item-1', instructionVersion: 2, dataScope: 'approved-data', instructionsHash: 'a'.repeat(64), cwd: process.cwd() };
  const prepared = await adapter.prepareSession(spec);
  return { adapter, t, spec, prepared, emit };
}

test('installed-method presence alone is not descendant-proof capability', () => {
  const weak = protocolCapabilities({ oneOf: schema.oneOf });
  assert.equal(weak.resume, true); assert.equal(weak.archive, false); assert.equal(weak.delete, false);
  assert.equal(protocolCapabilities(schema).ancestorFilter, true);
});

test('scope changes cannot be hidden by supplying a persisted binding', async () => {
  const { adapter, prepared, spec, t } = await host();
  assert.equal(prepared.binding.instructionVersion, 2);
  const before = t.sent.filter((entry) => entry.method === 'thread/resume').length;
  await assert.rejects(adapter.prepareSession({ ...spec, ...prepared, projectId: 'another-project' }), /session_binding_scope_mismatch/);
  assert.equal(t.sent.filter((entry) => entry.method === 'thread/resume').length, before);
  await adapter.prepareSession({ ...spec, ...prepared });
  assert.equal(t.sent.at(-2)?.method === 'thread/resume' || t.sent.some((entry) => entry.method === 'thread/resume'), true);
  await adapter.close();
});

test('early stale terminal events cannot settle the new managed turn', async () => {
  const { adapter, prepared } = await host({ 'turn/start': (message, t, emit) => {
    emit('turn/completed', { threadId, turn: { id: 'old-turn', status: { type: 'completed' } } });
    emit('item/completed', { threadId, turnId: 'new-turn', item: { type: 'agentMessage', text: 'Current result' } });
    emit('turn/completed', { threadId, turn: { id: 'new-turn', status: { type: 'completed' } } });
    t.emit('message', { jsonrpc: '2.0', id: message.id, result: { turn: { id: 'new-turn' } } });
  } });
  const events = []; adapter.on('task-event', (event) => events.push(event));
  await adapter.startSessionTurn({ ...prepared, id: 'new-attempt', instruction: 'Bounded analysis', outputSchema: { type: 'object' } });
  const terminal = events.filter((event) => event.kind === 'completed');
  assert.equal(terminal.length, 1); assert.equal(terminal[0].turnId, 'new-turn'); assert.equal(terminal[0].taskId, 'new-attempt'); assert.equal(terminal[0].threadId, threadId); assert.equal(terminal[0].summary, 'Current result');
  await adapter.close();
});

test('native archive proves all-source descendants and observes archive plus subscription release', async () => {
  const { adapter, prepared, t } = await host();
  const receipt = await adapter.cleanupSession(prepared);
  assert.equal(receipt.archived, true); assert.equal(receipt.notificationObserved, true); assert.equal(receipt.subscriptionReleased, true);
  const lists = t.sent.filter((entry) => entry.method === 'thread/list');
  const descendantLists = lists.filter((entry) => entry.params.ancestorThreadId);
  assert.deepEqual(descendantLists.map((entry) => entry.params.archived), [false, true]);
  assert.ok(descendantLists.every((entry) => entry.params.ancestorThreadId === threadId && entry.params.sourceKinds.includes('subAgent') && entry.params.modelProviders.length === 0));
  assert.equal(adapter.isSessionLoaded(threadId), false); await adapter.close();
});

test('a descendant prevents archival even with a caller-provided proof flag', async () => {
  const { adapter, prepared, t } = await host({ 'thread/list': (message, transport) => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { data: [{ id: '22222222-2222-4222-8222-222222222222', parentThreadId: threadId }], nextCursor: null } }) });
  await assert.rejects(adapter.cleanupSession({ ...prepared, verifiedNoDescendants: true }), /session_archive_descendants_unproven/);
  assert.equal(t.sent.some((entry) => entry.method === 'thread/archive'), false); await adapter.close();
});

test('compaction completion is observed separately from its RPC response', async () => {
  const { adapter, prepared } = await host();
  const receipt = await adapter.compactSession(prepared);
  assert.equal(receipt.accepted, true); assert.equal(receipt.completed, true); assert.equal(adapter.diagnostics().activeTurns, 0); await adapter.close();
});

test('current compaction requires a correlated context item and completed maintenance turn', async () => {
  const { adapter, prepared, emit, t } = await host({ 'thread/compact/start': (message, transport) => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: {} }) });
  let settled = false;
  const pending = adapter.compactSession(prepared).then((value) => { settled = true; return value; });
  for (let i = 0; i < 10 && !t.sent.some((entry) => entry.method === 'thread/compact/start'); i++) await new Promise(setImmediate);
  assert.equal(settled, false);
  emit('turn/started', { threadId, turn: { id: 'maintenance', status: 'inProgress' } });
  emit('item/started', { threadId, turnId: 'maintenance', item: { id: 'compact-item', type: 'contextCompaction' } });
  emit('item/completed', { threadId, turnId: 'old-turn', item: { id: 'compact-item', type: 'contextCompaction' } });
  emit('turn/completed', { threadId, turn: { id: 'maintenance', status: 'completed' } });
  await new Promise(setImmediate); assert.equal(settled, false);
  emit('item/completed', { threadId, turnId: 'maintenance', item: { id: 'compact-item', type: 'contextCompaction' } });
  await new Promise(setImmediate); assert.equal(settled, false);
  emit('turn/completed', { threadId, turn: { id: 'maintenance', status: 'completed' } });
  const receipt = await pending;
  assert.equal(receipt.completed, true); assert.equal(receipt.evidence, 'context_compaction_item_and_turn_completed');
  assert.equal(adapter.diagnostics().activeTurns, 0); await adapter.close();
});

test('lost archive receipts recover from exact archived inventory, without archiving twice', async () => {
  const { adapter, prepared, t } = await host({ 'thread/list': (message, transport) => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { data: message.params.cwd ? [{ id: threadId, cwd: process.cwd() }] : [], nextCursor: null } }) });
  const receipt = await adapter.cleanupSession(prepared);
  assert.equal(receipt.archived, true); assert.equal(receipt.evidence, 'archived_inventory_observed');
  assert.equal(t.sent.some((entry) => entry.method === 'thread/archive'), false);
  await adapter.close();
});

test('Windows archived inventory checks the canonical path as well as the bound case-folded path', { skip: process.platform !== 'win32' }, async () => {
  const canonical = await realpath(process.cwd());
  const { adapter, spec, t } = await host({ 'thread/list': (message, transport) => transport.emit('message', { jsonrpc: '2.0', id: message.id, result: { data: message.params.cwd === canonical ? [{ id: threadId }] : [], nextCursor: null } }) });
  const prepared = await adapter.prepareSession({ ...spec, cwd: canonical.toLowerCase() });
  const receipt = await adapter.cleanupSession(prepared);
  assert.equal(receipt.evidence, 'archived_inventory_observed');
  assert.ok(t.sent.some((entry) => entry.method === 'thread/list' && entry.params.cwd === canonical));
  assert.equal(t.sent.some((entry) => entry.method === 'thread/archive'), false);
  await adapter.close();
});
