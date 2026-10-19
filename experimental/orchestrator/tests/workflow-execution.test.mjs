import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Orchestrator } from '../lib/engine.mjs';

class FixtureAdapter extends EventEmitter {
  constructor() { super(); this.started = []; this.child = { pid: 9, killed: false }; }
  diagnostics() { return {}; }
  async connect() {}
  async close() {}
  async startTask(input) { this.started.push(input); return { threadId: `thread-${this.started.length}`, turnId: `turn-${this.started.length}` }; }
  async interruptTask() {}
}
const workflow = (nodes, edges) => ({ id: 'wf', name: 'Execution', nodes, edges });
const node = (id, extra = {}) => ({ id, title: id, instruction: `do ${id}`, kind: 'task', ...extra });

async function setup(wf, extra = {}) {
  const adapter = new FixtureAdapter(); const engine = new Orchestrator({ adapter, prepareWorkspace: async ({ policy }) => ({ cwd: policy === 'workspace-write' ? '/write' : '/read', workspacePath: policy === 'workspace-write' ? '/write' : null }), ...extra });
  await engine.action({ action: 'connect' }); await engine.action({ action: 'save-workflow', workflow: wf }); await engine.action({ action: 'add-packet', workflowId: 'wf', title: 'packet', input: 'input' }); await engine.action({ action: 'authorize', confirmed: true }); return { engine, adapter };
}

test('write stage remains blocked at zero attempts until write consent', async () => {
  const { engine, adapter } = await setup(workflow([node('write', { policy: 'workspace-write', routing: 'auto' })], []));
  await engine.action({ action: 'start' }); assert.equal(engine.state.tasks[0].state, 'blocked'); assert.equal(engine.state.tasks[0].attempts, 0); assert.equal(adapter.started.length, 0);
  await engine.action({ action: 'authorize', confirmed: true, allowWrites: true }); await engine.action({ action: 'start' }); assert.equal(engine.state.tasks[0].state, 'running'); assert.equal(engine.state.tasks[0].attempts, 1);
});

test('verification failure queues one bounded repair and never accepts first failure', async () => {
  let calls = 0; const verifier = { verifyCommand: async () => (++calls === 1 ? { exitCode: 1, stderr: 'bad' } : { exitCode: 0 }) };
  const { engine, adapter } = await setup(workflow([node('build', { routing: 'auto', verificationCommand: ['npm', 'test'], maxAttempts: 2 })], []), { verifier }); await engine.action({ action: 'start' });
  const task = engine.state.tasks[0]; adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: 'built' }); await new Promise((r) => setTimeout(r, 20));
  assert.equal(task.state, 'running'); assert.equal(task.attempts, 2); assert.match(adapter.started[1].instruction, /bad/); assert.equal(engine.state.packets[0].outputs.build, undefined);
  adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: 'repaired' }); await new Promise((r) => setTimeout(r, 20));
  assert.equal(task.state, 'accepted'); assert.equal(calls, 2); assert.equal(task.verification.exitCode, 0); assert.equal(engine.state.packets[0].outputs.build.summary, 'repaired');
});

test('fan-out join-all waits for both accepted parents and carries both dependencies', async () => {
  const wf = workflow([node('a', { routing: 'auto' }), node('b', { routing: 'auto' }), node('join', { routing: 'auto', join: 'all' })], [{ id: 'aj', source: 'a', target: 'join' }, { id: 'bj', source: 'b', target: 'join' }]);
  const { engine, adapter } = await setup(wf); await engine.action({ action: 'configure', maxConcurrency: 2 }); await engine.action({ action: 'start' });
  const roots = engine.state.tasks.filter((t) => ['a', 'b'].includes(t.nodeId));
  for (const task of roots) adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: task.nodeId });
  await new Promise((r) => setTimeout(r, 10)); const join = engine.state.tasks.find((t) => t.nodeId === 'join'); assert.ok(join); assert.deepEqual(new Set(join.dependencies), new Set(roots.map((t) => t.id)));
});

test('join-any routes once from first accepted parent', async () => {
  const wf = workflow([node('a', { routing: 'auto' }), node('b', { routing: 'auto' }), node('join', { routing: 'auto', join: 'any' })], [{ id: 'aj', source: 'a', target: 'join' }, { id: 'bj', source: 'b', target: 'join' }]);
  const { engine, adapter } = await setup(wf); await engine.action({ action: 'start' }); const first = engine.state.tasks.find((t) => t.nodeId === 'a');
  adapter.emit('task-event', { taskId: first.runKey, turnId: first.turnId, kind: 'completed', summary: 'a' }); await new Promise((r) => setTimeout(r, 10)); assert.equal(engine.state.tasks.filter((t) => t.nodeId === 'join').length, 1);
  const second = engine.state.tasks.find((t) => t.nodeId === 'b'); if (second) adapter.emit('task-event', { taskId: second.runKey, turnId: second.turnId, kind: 'completed', summary: 'b' }); await new Promise((r) => setTimeout(r, 10)); assert.equal(engine.state.tasks.filter((t) => t.nodeId === 'join').length, 1);
});

test('missing native verifier fails closed instead of accepting an auto stage', async () => {
  const { engine, adapter } = await setup(workflow([node('check', { routing: 'auto', verificationCommand: ['test'] })], [])); await engine.action({ action: 'start' }); const task = engine.state.tasks[0]; adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: 'done' }); await new Promise((r) => setTimeout(r, 10)); assert.notEqual(task.state, 'accepted'); assert.equal(task.blockReason, 'verification_unavailable');
});

test('500-node workflow validates while execution remains bounded to roots', async () => {
  const nodes = Array.from({ length: 500 }, (_, i) => node(`n${i}`, { routing: 'auto' })); const edges = nodes.slice(1).map((n, i) => ({ id: `e${i}`, source: `n${i}`, target: n.id }));
  const { engine } = await setup(workflow(nodes, edges)); await engine.action({ action: 'start' }); assert.equal(engine.state.tasks.length, 1); assert.equal(engine.state.tasks[0].nodeId, 'n0');
});
