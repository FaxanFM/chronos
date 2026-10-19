import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Orchestrator } from '../lib/engine.mjs';

class Adapter extends EventEmitter {
  constructor() { super(); this.started = []; this.closed = 0; }
  diagnostics() { return {}; }
  async connect() {}
  async close() { this.closed++; }
  async startTask(input) { this.started.push(input); return { threadId: `thread-${this.started.length}`, turnId: `turn-${this.started.length}` }; }
  async interruptTask() {}
}
const node = (id, extra = {}) => ({ id, title: id, instruction: `do ${id}`, kind: 'task', ...extra });
const workflow = (id, nodes, edges = []) => ({ id, name: id, nodes, edges });

async function setup(wf, extra = {}) {
  const adapter = new Adapter();
  const engine = new Orchestrator({ adapter, prepareWorkspace: async ({ policy }) => ({ cwd: policy === 'workspace-write' ? '/write' : '/read' }), ...extra });
  await engine.action({ action: 'connect' });
  await engine.action({ action: 'save-workflow', workflow: wf });
  await engine.action({ action: 'add-packet', workflowId: wf.id, title: 'packet', input: 'input' });
  await engine.action({ action: 'authorize', confirmed: true, allowWrites: true });
  return { engine, adapter };
}

test('verification cancellation falls back to runtime shutdown when verifier cannot cancel', async () => {
  const verifier = { verifyCommand: async () => new Promise(() => {}) };
  const { engine, adapter } = await setup(workflow('cancel', [node('check', { routing: 'auto', verificationCommand: ['test'] })]), { verifier });
  await engine.action({ action: 'start' });
  const task = engine.state.tasks[0];
  adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: 'done' });
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(task.state, 'verifying');
  await engine.action({ action: 'cancel', taskId: task.id });
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(adapter.closed, 1);
  assert.equal(task.recoveryUnknown, true);
});

test('restart rejects a packet output that does not match an accepted task', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-safety-'));
  const statePath = join(dir, 'state.json');
  const wf = workflow('persist', [node('check')]);
  const { engine } = await setup(wf);
  const task = engine.state.tasks[0];
  engine.state.packets[0].outputs = { check: { taskId: task.id, summary: 'forged' } };
  await writeFile(statePath, JSON.stringify({ schemaVersion: 2, revision: 0, maxConcurrency: 1, tasks: engine.state.tasks, events: [], workflows: engine.state.workflows, packets: engine.state.packets }));
  const restored = new Orchestrator({ adapter: new Adapter(), statePath });
  await assert.rejects(restored.initialize(), /state_packet_output_invalid/);
});

test('same-packet workspace writers are never dispatched concurrently', async () => {
  const wf = workflow('writers', [node('a', { policy: 'workspace-write', routing: 'auto' }), node('b', { policy: 'workspace-write', routing: 'auto' })]);
  const { engine, adapter } = await setup(wf);
  await engine.action({ action: 'configure', maxConcurrency: 2 });
  await engine.action({ action: 'start' });
  assert.equal(adapter.started.length, 1);
  assert.equal(engine.state.tasks.filter((task) => task.state === 'running').length, 1);
});

test('accepted sources can join across workflows but unfinished inputs cannot', async () => {
  const wfA = workflow('source', [node('source')]);
  const { engine, adapter } = await setup(wfA);
  const source = engine.state.tasks[0];
  source.state = 'accepted'; source.summary = 'accepted result'; source.workspacePath = '/accepted-artifacts';
  await engine.action({ action: 'save-workflow', workflow: workflow('target', [node('target')]) });
  await engine.action({ action: 'add-packet', workflowId: 'target', title: 'target', input: 'input', sourceTaskIds: [source.id] });
  assert.deepEqual(engine.state.tasks.at(-1).dependencies, [source.id]);
  await engine.action({ action: 'start' });
  assert.ok(adapter.started.at(-1).instruction.includes('/accepted-artifacts'));
  await engine.action({ action: 'pause' });
  source.state = 'review';
  await assert.rejects(engine.action({ action: 'add-packet', workflowId: 'target', title: 'target', input: 'input', sourceTaskIds: [source.id] }), /outbox_sources_invalid/);
});

test('workflow stage records cannot be removed outside whole-item archive', async () => {
  const { engine } = await setup(workflow('archive', [node('stage')]));
  const packet = engine.state.packets[0];
  await assert.rejects(engine.action({ action: 'remove-task', taskId: engine.state.tasks[0].id }), /archive_work_item_instead/);
  await engine.action({ action: 'archive-packet', packetId: packet.id });
  assert.equal(engine.state.tasks.length, 0);
  assert.equal(engine.state.packets.length, 0);
});
