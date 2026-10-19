import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { Orchestrator } from '../lib/engine.mjs';

function transport({ catalog = null, configuredModel = null } = {}) {
  const t = new EventEmitter(); t.sent = []; let page = 0;
  t.send = (message) => { t.sent.push(message); queueMicrotask(() => {
    let result = {};
    if (message.method === 'initialize') result = {};
    else if (message.method === 'account/read') result = { requiresOpenaiAuth: false, account: null };
    else if (message.method === 'config/read') result = { config: { mcp_servers: {}, ...(configuredModel ? { model: configuredModel } : {}) } };
    else if (message.method === 'mcpServerStatus/list') result = { data: [], nextCursor: null };
    else if (message.method === 'model/list') {
      if (catalog === 'fail') return;
      const pages = catalog || [{ data: [{ id: 'gpt-default', displayName: 'Default', isDefault: true, reasoningEfforts: [{ reasoningEffort: 'low', description: 'fast' }, { reasoningEffort: 'high', description: 'deep' }] }], nextCursor: null }];
      result = pages[Math.min(page++, pages.length - 1)];
    } else if (['thread/start', 'thread/fork'].includes(message.method)) result = { thread: { id: `owned-${message.method}` }, cwd: message.params.cwd, approvalPolicy: 'never', sandbox: { type: 'readOnly', networkAccess: false }, model: message.params.model || 'gpt-default' };
    else if (message.method === 'turn/start') result = { turn: { id: 'turn-1' } };
    else if (message.method === 'thread/goal/clear') result = {};
    if (message.id !== undefined) t.emit('message', { jsonrpc: '2.0', id: message.id, result });
  }); };
  t.onMessage = (cb) => t.on('message', cb); t.close = () => {};
  return t;
}

test('catalog pagination preserves host ordering and normalizes the runtime contract', async () => {
  const t = transport({ catalog: [{ data: [{ id: 'model-a', description: 'A', supportedReasoningEfforts: ['low'] }], nextCursor: 'next' }, { data: [{ id: 'model-b', displayName: 'B', isDefault: true, reasoningEfforts: ['high'] }], nextCursor: null }] });
  const adapter = new CodexAdapter({ transportFactory: async () => t }); await adapter.connect();
  const d = adapter.diagnostics(); assert.equal(d.modelCatalogStatus, 'available'); assert.deepEqual(d.models.map((m) => m.id), ['model-a', 'model-b']); assert.equal(d.defaultModel, 'model-b'); await adapter.close();
});

test('direct and fork dispatch carry advertised model and effort', async () => {
  const t = transport(); const adapter = new CodexAdapter({ transportFactory: async () => t }); await adapter.connect();
  await adapter.startTask({ id: 'direct', instruction: 'x', model: 'gpt-default', reasoningEffort: 'high' });
  await adapter.startTask({ id: 'fork', instruction: 'x', sourceThreadLink: 'codex://threads/01a151cc-f0c6-7572-aa76-7db9477460b1', model: 'gpt-default', reasoningEffort: 'low' });
  const starts = t.sent.filter((m) => m.method === 'thread/start' || m.method === 'thread/fork'); const turns = t.sent.filter((m) => m.method === 'turn/start');
  assert.equal(starts[0].params.model, 'gpt-default'); assert.equal(starts[1].params.model, 'gpt-default'); assert.equal(turns[0].params.effort, 'high'); assert.equal(turns[1].params.effort, 'low'); await adapter.close();
});

test('unsupported explicit selections reject before native thread creation', async () => {
  const t = transport(); const adapter = new CodexAdapter({ transportFactory: async () => t }); await adapter.connect();
  await assert.rejects(() => adapter.startTask({ id: 'bad', instruction: 'x', model: 'unknown' }), /model_not_advertised/);
  await assert.rejects(() => adapter.startTask({ id: 'bad-effort', instruction: 'x', model: 'gpt-default', reasoningEffort: 'ultra' }), /reasoning_effort_not_advertised/);
  assert.equal(t.sent.some((m) => m.method === 'thread/start'), false); await adapter.close();
});

test('inherited model effort follows the configured model and canonical ids', async () => {
  const t = transport({ configuredModel: 'configured-native', catalog: [{ data: [
    { id: 'first', model: 'first-native', isDefault: true, supportedReasoningEfforts: ['low'] },
    { id: 'selected-alias', model: 'configured-native', supportedReasoningEfforts: [{ reasoningEffort: 'precise', description: 'Host-specific effort' }] },
  ], nextCursor: null }] });
  const adapter = new CodexAdapter({ transportFactory: async () => t }); await adapter.connect();
  assert.equal(adapter.diagnostics().defaultModel, 'selected-alias');
  await adapter.startTask({ id: 'inherited', instruction: 'x', reasoningEffort: 'precise' });
  await adapter.startTask({ id: 'explicit', instruction: 'x', model: 'selected-alias', reasoningEffort: 'precise' });
  const starts = t.sent.filter((message) => message.method === 'thread/start');
  assert.equal(starts[0].params.model, 'configured-native');
  assert.equal(starts[1].params.model, 'configured-native');
  assert.equal(starts[0].params.reasoningEffort, undefined);
  assert.equal(t.sent.filter((message) => message.method === 'turn/start')[0].params.effort, 'precise');
  await adapter.close();
});

test('catalog without an authoritative default does not invent the first model', async () => {
  const t = transport({ catalog: [{ data: [{ id: 'first', supportedReasoningEfforts: ['low'] }], nextCursor: null }] });
  const adapter = new CodexAdapter({ transportFactory: async () => t }); await adapter.connect();
  assert.equal(adapter.diagnostics().defaultModel, null);
  await assert.rejects(adapter.startTask({ instruction: 'x', reasoningEffort: 'low' }), /reasoning_effort_not_advertised/);
  await adapter.close();
});

test('partial or cycling catalog pages are unavailable, not selectable', async () => {
  const t = transport({ catalog: [{ data: [{ id: 'first', supportedReasoningEfforts: ['low'] }], nextCursor: 'cycle' }] });
  const adapter = new CodexAdapter({ transportFactory: async () => t }); await adapter.connect();
  assert.equal(adapter.diagnostics().modelCatalogStatus, 'unavailable');
  assert.deepEqual(adapter.diagnostics().models, []);
  await adapter.close();
});

test('catalog failure preserves Codex-default execution but rejects explicit choices', async () => {
  const t = transport({ catalog: 'fail' }); const adapter = new CodexAdapter({ transportFactory: async () => t }); await adapter.connect();
  await adapter.startTask({ id: 'default', instruction: 'x' });
  await assert.rejects(() => adapter.startTask({ id: 'explicit', instruction: 'x', model: 'gpt-default' }), /model_catalog_unavailable/); await adapter.close();
});

test('engine restores nullable reasoning effort without dropping task state', async () => {
  const adapter = { cwd: process.cwd(), diagnostics: () => ({ connected: false }), on() {}, async connect() {}, async close() {}, async interruptTask() {} };
  const directory = await mkdtemp(join(tmpdir(), 'chronos-model-roundtrip-'));
  const statePath = join(directory, 'state.json');
  const first = new Orchestrator({ adapter, statePath }); await first.initialize();
  first.state.tasks.push({ id: 't', title: 'T', instruction: 'x', dependencies: [], state: 'queued', attempts: 0, model: 'gpt-default', reasoningEffort: 'high', summary: '', error: '', finishedAt: null }); await first.save(); await first.close();
  const second = new Orchestrator({ adapter, statePath }); await second.initialize(); assert.equal(second.snapshot().tasks[0].reasoningEffort, 'high'); await second.close();
  assert.ok(directory.startsWith(tmpdir()));
  await rm(directory, { recursive: true, force: true });
});
