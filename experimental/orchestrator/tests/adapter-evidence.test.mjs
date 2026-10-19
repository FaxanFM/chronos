import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { CodexAdapter } from '../lib/codex-adapter.mjs';

function transport() { const t = new EventEmitter(); t.sent = []; t.send = (m) => { t.sent.push(m); queueMicrotask(() => { let result = {}; if (m.method === 'initialize') result = {}; else if (m.method === 'account/read') result = { requiresOpenaiAuth: false, account: null }; else if (m.method === 'config/read') result = { config: { mcp_servers: {} } }; else if (m.method === 'mcpServerStatus/list') result = { data: [], nextCursor: null }; else if (m.method === 'thread/start') result = { thread: { id: 'owned-thread' }, cwd: m.params.cwd, approvalPolicy: 'never', sandbox: { type: 'readOnly', networkAccess: false } }; else if (m.method === 'turn/start') result = { turn: { id: 'owned-turn' } }; if (m.id !== undefined) t.emit('message', { jsonrpc: '2.0', id: m.id, result }); }); }; t.onMessage = (cb) => t.on('message', cb); t.close = () => {}; return t; }

test('execution evidence aggregates native items and deduplicates', async () => { const t = transport(); const a = new CodexAdapter({ transportFactory: async () => t }); const events = []; a.on('task-event', e => events.push(e)); await a.connect(); await a.startTask({ id: 'x', instruction: 'do it' }); const item = (method, id, type, status) => t.emit('message', { method, params: { threadId: 'owned-thread', turnId: 'owned-turn', item: { id, type, ...(status ? { status } : {}) } } }); item('item/started', 'a', 'commandExecution'); item('item/started', 'a', 'commandExecution'); item('item/completed', 'a', 'commandExecution', 'completed'); item('item/completed', 'missing', 'webSearch', 'failed'); t.emit('message', { method: 'turn/completed', params: { threadId: 'owned-thread', turnId: 'owned-turn', turn: { status: { type: 'completed' } } } }); const e = events.at(-1).executionEvidence; assert.equal(e.counts.commandExecution.started, 1); assert.equal(e.counts.commandExecution.completed, 1); assert.equal(e.partial, true); assert.ok(e.partialReasons.includes('duplicate-item')); assert.ok(e.partialReasons.includes('unmatched-item')); assert.equal('text' in e, false); await a.close(); });

test('ignores prose, preserves unknown coverage and treats nonzero command exit as failure', async () => {
  const t = transport();
  const a = new CodexAdapter({ transportFactory: async () => t });
  const events = []; a.on('task-event', (event) => events.push(event));
  await a.connect(); await a.startTask({ instruction: 'do it' });
  const send = (method, item) => t.emit('message', { method, params: { threadId: 'owned-thread', turnId: 'owned-turn', item } });
  send('item/started', { id: 'msg', type: 'agentMessage' });
  send('item/completed', { id: 'msg', type: 'agentMessage' });
  send('item/started', { id: 'cmd', type: 'commandExecution' });
  send('item/completed', { id: 'cmd', type: 'commandExecution', status: 'completed', exitCode: 2 });
  send('item/started', { id: 'future', type: 'futureEvent' });
  send('item/completed', { id: 'future', type: 'futureEvent' });
  t.emit('message', { method: 'turn/completed', params: { threadId: 'owned-thread', turnId: 'owned-turn', turn: { status: { type: 'completed' } } } });
  const evidence = events.at(-1).executionEvidence;
  assert.equal(evidence.coverage, 'observed_events_only');
  assert.equal(evidence.counts.commandExecution.failed, 1);
  assert.equal(evidence.counts.unknownItem.started, 1);
  assert.equal('otherTool' in evidence.counts, false);
  assert.equal(evidence.partial, true);
  assert.ok(evidence.partialReasons.includes('unknown-item-type'));
  await a.close();
});
