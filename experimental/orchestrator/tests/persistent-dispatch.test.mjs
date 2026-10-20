import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, readFile, writeFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Orchestrator } from '../lib/engine.mjs';

class Host extends EventEmitter {
  constructor() { super(); this.cwd = process.cwd(); this.prepares = []; this.starts = []; this.archives = []; }
  async connect() {}
  async close() {}
  runtimeIdentity() { return 'test-installed-runtime'; }
  diagnostics() { return { sessionCapabilities: { prepare: true, resume: true, turn: true, archive: true } }; }
  async prepareSession(spec) {
    this.prepares.push(structuredClone(spec));
    if (this.creationFails) throw new Error('session_creation_uncertain');
    const threadId = spec.threadId || 'thread-' + spec.sessionId;
    return { threadId, binding: spec.binding || { threadId, scope: structuredClone(spec) }, status: 'idle' };
  }
  async startSessionTurn(spec) { this.starts.push(spec); return { threadId: spec.threadId, turnId: 'turn-' + spec.id }; }
  async inspectSession() { return { status: this.observed || 'idle' }; }
  async cleanupSession(spec) { this.archives.push(spec); return { archived: true, threadId: spec.threadId }; }
  async interruptTask() {}
  finish(index, status = 'completed', question = null) {
    const spec = this.starts[index];
    this.emit('task-event', { taskId: spec.id, threadId: spec.threadId, turnId: 'turn-' + spec.id, kind: 'completed', summary: JSON.stringify({ status, summary: 'Bounded result', question }) });
  }
}
const flush = async (e) => { for (let i = 0; i < 40; i++) { await delay(2); await e.serial; } };
const workflow = (mode = 'hybrid', extra = {}) => ({ id: 'persistent-test', name: 'Agent test', conversationDefault: mode, nodes: [{ id: 'analyse', title: 'Analyst', instruction: 'Analyse the assigned input.', routing: 'auto', slots: 2, ...extra }], edges: [] });
const packet = (e, more = {}) => e.action({ action: 'add-packet', workflowId: 'persistent-test', title: 'Assignment', input: 'Test data', relatedToProject: true, ...more });
async function boot(e) { await e.action({ action: 'connect' }); await e.action({ action: 'authorize', confirmed: true }); await e.action({ action: 'start' }); await flush(e); }

test('real engine dispatch persists intent and native identity before a turn, and reuses the primary', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-agents-dispatch-')), path = join(dir, 'queue.json');
  const host = new Host(), e = await new Orchestrator({ adapter: host, statePath: path }).initialize();
  await e.action({ action: 'save-workflow', workflow: workflow() }); await packet(e);
  const prepare = host.prepareSession.bind(host);
  host.prepareSession = async (spec) => { const state = JSON.parse(await readFile(path)); assert.equal(state.sessions[0].state, 'creation-pending'); assert.equal(state.sessions[0].threadId, null); return prepare(spec); };
  const start = host.startSessionTurn.bind(host);
  host.startSessionTurn = async (spec) => { const state = JSON.parse(await readFile(path)); assert.equal(state.sessions[0].threadId, spec.threadId); assert.equal(state.tasks.find((task) => task.runKey === spec.id)?.threadId, spec.threadId); assert.ok(spec.outputSchema); return start(spec); };
  await boot(e); assert.equal(host.starts.length, 1);
  host.finish(0); await flush(e); assert.equal(e.state.tasks[0].state, 'accepted');
  host.prepareSession = prepare; await packet(e); await flush(e);
  assert.equal(host.starts.length, 2); assert.equal(host.starts[0].threadId, host.starts[1].threadId); assert.equal(e.state.sessions.length, 1);
  assert.equal(e.state.sessions[0].attemptHistory[1].runKey, host.starts[1].id);
  await e.close();
});

test('one-off question continuation reuses its session and attempt, without opening the outbox', async () => {
  const host = new Host(), e = new Orchestrator({ adapter: host });
  await e.action({ action: 'save-workflow', workflow: workflow('one-off') }); await packet(e); await boot(e);
  host.finish(0, 'needs-input', { body: 'Which option?', targetAgentId: null }); await flush(e);
  assert.equal(e.state.tasks[0].state, 'blocked'); assert.deepEqual(e.state.packets[0].outputs, {}); assert.equal(e.snapshot().activeCount, 0);
  await e.action({ action: 'answer-agent-question', questionId: e.state.agentQuestions[0].id, message: 'Option A.' }); await flush(e);
  assert.equal(host.starts.length, 2); assert.equal(host.starts[0].threadId, host.starts[1].threadId); assert.equal(e.state.tasks[0].attempts, 1);
  host.finish(1); await flush(e); assert.equal(e.state.tasks[0].state, 'accepted');
  await e.close();
});

test('unknown creation and stale events cannot cause a replacement or acceptance', async () => {
  const host = new Host(), e = new Orchestrator({ adapter: host }); host.creationFails = true;
  await e.action({ action: 'save-workflow', workflow: workflow('one-off') }); await packet(e); await boot(e);
  assert.equal(e.state.sessions.length, 1); assert.equal(e.state.sessions[0].state, 'uncertain'); assert.equal(host.starts.length, 0);
  await assert.rejects(e.action({ action: 'retry', taskId: e.state.tasks[0].id, confirmedStopped: true }), /reconcile_managed_session_first/);
  await assert.rejects(e.action({ action: 'start' }), /confirm_previous_worker_stopped/);
  assert.equal(host.prepares.length, 1); await e.close();
});

test('migration preserves exact legacy bytes, graph and absent mode without eager inference', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-agents-migration-')), path = join(dir, 'queue.json');
  const old = { schemaVersion: 2, revision: 10, tasks: [], events: [], workflows: [{ id: 'legacy', name: 'Legacy', nodes: [{ id: 'one', title: 'One', instruction: 'Original instruction' }], edges: [] }], packets: [] };
  const bytes = JSON.stringify(old, null, 2); await writeFile(path, bytes);
  const host = new Host(), e = await new Orchestrator({ adapter: host, statePath: path }).initialize();
  assert.equal(e.state.project.conversationDefault, 'legacy'); assert.equal(e.state.workflows[0].conversationDefault, undefined);
  const backup = (await readdir(dir)).find((name) => name.includes('.pre-agents-v2.'));
  assert.equal(await readFile(join(dir, backup), 'utf8'), bytes); assert.equal(host.prepares.length, 0); assert.equal(host.starts.length, 0);
  await e.close();
  const next = await new Orchestrator({ adapter: new Host(), statePath: path }).initialize();
  assert.equal(next.state.project.conversationDefault, 'legacy'); assert.equal(next.state.consent.execution, false); await next.close();
});

test('Hybrid reserves a pending primary before RPC and isolates concurrent work', async () => {
  const host = new Host(), e = new Orchestrator({ adapter: host });
  await e.action({ action: 'save-workflow', workflow: workflow() }); await e.action({ action: 'configure', maxConcurrency: 2 });
  await packet(e); await packet(e); await boot(e);
  assert.equal(host.starts.length, 2); assert.equal(e.state.sessions.filter((s) => s.role === 'primary').length, 1); assert.equal(e.state.sessions.filter((s) => s.role === 'worker').length, 1);
  assert.notEqual(host.starts[0].threadId, host.starts[1].threadId); await e.close();
});

test('a ready-for-review outcome overrides automatic routing', async () => {
  const host = new Host(), e = new Orchestrator({ adapter: host });
  await e.action({ action: 'save-workflow', workflow: workflow() }); await packet(e); await boot(e);
  host.finish(0, 'ready-for-review'); await flush(e);
  assert.equal(e.state.tasks[0].state, 'review'); assert.deepEqual(e.state.packets[0].outputs, {}); await e.close();
});

test('new API workflows inherit the configured default without changing omitted legacy policies', async () => {
  const host = new Host(), e = new Orchestrator({ adapter: host });
  const raw = workflow(); delete raw.conversationDefault;
  await e.action({ action: 'save-workflow', workflow: raw });
  assert.equal(e.state.workflows.find((item) => item.id === raw.id).conversationDefault, 'hybrid');
  await packet(e); await boot(e);
  assert.equal(host.starts.length, 1); assert.equal(e.state.sessions[0].role, 'primary');
  host.finish(0); await flush(e); await e.action({ action: 'pause' });
  await e.action({ action: 'configure-project-agents', conversationDefault: 'one-off' });
  await e.action({ action: 'save-workflow', workflow: { ...raw, id: 'another-new' } });
  assert.equal(e.state.workflows.find((item) => item.id === 'another-new').conversationDefault, 'one-off');
  e.state.workflows.push({ ...raw, id: 'old-omitted' });
  await e.action({ action: 'save-workflow', workflow: { ...raw, id: 'old-omitted', name: 'Legacy edit' } });
  assert.equal(e.state.workflows.find((item) => item.id === 'old-omitted').conversationDefault, undefined);
  await e.close();
});
