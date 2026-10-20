import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { Orchestrator } from '../lib/engine.mjs';
import { WorkspaceManager, executeWorkspaceGit } from '../lib/workspaces.mjs';

const run = promisify(execFile);
const envelope = (summary, message = null) => JSON.stringify({ protocol: 'chronos.collaboration.v1', summary, message });

class Adapter extends EventEmitter {
  constructor() { super(); this.started = []; }
  async connect() {}
  async close() {}
  async interruptTask() {}
  async startTask(input) { this.started.push(input); return { threadId: `thread-${this.started.length}`, turnId: `turn-${this.started.length}` }; }
}

const flush = async (engine) => { for (let i = 0; i < 4; i++) { await new Promise(setImmediate); await engine.serial; } };
const current = (engine, nodeId) => engine.state.tasks.findLast((task) => task.nodeId === nodeId && !task.superseded);

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), 'chronos-collab-checkpoint-'));
  const source = join(root, 'source'); await mkdir(source);
  const ignore = join(root, 'ignore'); await writeFile(ignore, '');
  const git = (args) => run('git', ['-C', source, '-c', `core.excludesFile=${ignore}`, ...args], { windowsHide: true });
  await git(['init']); await git(['config', 'user.name', 'Chronos fixture']); await git(['config', 'user.email', 'fixture@example.invalid']);
  await writeFile(join(source, 'brief.md'), 'original brief\n');
  await git(['add', '.']); await git(['-c', 'commit.gpgsign=false', 'commit', '-m', 'fixture']);
  const manager = new WorkspaceManager({ sourceRoot: source, storageRoot: join(root, 'owned'), execute: (file, args, options) => executeWorkspaceGit(file, ['-c', `core.excludesFile=${ignore}`, ...args], options) });
  return { root, source, manager };
}

function workflow() {
  return {
    id: 'checkpoint-collaboration', name: 'Checkpoint collaboration', conversationDefault: 'inherit', mode: 'collaborative',
    collaboration: { maxIterations: 2, requestTimeoutMs: 1000 },
    nodes: [
      { id: 'builder', title: 'Builder', instruction: 'Build the bounded local change.', policy: 'workspace-write', routing: 'approval' },
      { id: 'reviewer', title: 'Reviewer', instruction: 'Review the bounded local change.', policy: 'read-only', routing: 'approval' },
    ], edges: [{ id: 'br', source: 'builder', target: 'reviewer' }],
  };
}

async function setup({ statePath, manager, checkpoints, workflow: suppliedWorkflow } = {}) {
  const adapter = new Adapter();
  const engine = new Orchestrator({ adapter, statePath, prepareWorkspace: manager?.prepare.bind(manager), checkpoints });
  await engine.initialize();
  engine.state.project.conversationDefault = 'legacy';
  const wf = suppliedWorkflow || workflow();
  await engine.action({ action: 'save-workflow', workflow: wf });
  await engine.action({ action: 'add-packet', workflowId: wf.id, title: 'Checkpoint proof', input: 'Bounded local fixture.' });
  await engine.action({ action: 'connect' });
  await engine.action({ action: 'authorize', confirmed: true, allowWrites: true });
  await engine.action({ action: 'configure', maxConcurrency: 1 });
  await engine.action({ action: 'start' });
  await flush(engine);
  return { engine, adapter };
}

test('collaborative write seals an immutable checkpoint before review and preserves it across correction', async () => {
  const fixtureValue = await fixture();
  try {
    const { manager } = fixtureValue;
    const { engine, adapter } = await setup({ manager, checkpoints: manager });
    try {
      const first = current(engine, 'builder');
      assert.equal(first.state, 'running', first.error || first.blockReason);
      assert.equal(adapter.started[0].collaborative, true);
      adapter.emit('task-event', { taskId: first.runKey, turnId: first.turnId, kind: 'completed', summary: envelope('Initial build.') });
      await flush(engine);
      assert.equal(first.state, 'review');
      assert.ok(first.fileCheckpoint?.manifestSha256);
      assert.ok(first.checkpointBase?.manifestSha256);
      const originalBytes = await readFile(join(first.cwd, 'brief.md'), 'utf8');
      await engine.action({ action: 'accept', taskId: first.id });
      await flush(engine);
      const review = current(engine, 'reviewer');
      assert.equal(review.state, 'running');
      adapter.emit('task-event', { taskId: review.runKey, turnId: review.turnId, kind: 'completed', summary: envelope('Needs a correction.', { kind: 'rejection', targetStageId: 'builder', inReplyTo: null, artifactIds: [engine.state.packets[0].outputs.builder.artifactId], body: 'Update the brief.' }) });
      await flush(engine);
      const correction = current(engine, 'builder');
      assert.equal(correction.state, 'running');
      assert.notEqual(correction.cwd, first.cwd);
      assert.equal(await readFile(join(first.cwd, 'brief.md'), 'utf8'), originalBytes);
      assert.equal(await readFile(join(correction.cwd, 'brief.md'), 'utf8'), originalBytes);
      await engine.close();
    } finally { await engine.close().catch(() => {}); }
  } finally { await rm(fixtureValue.root, { recursive: true, force: true }); }
});

test('collaborative writes fail closed before a model turn without checkpoint manager', async () => {
  const adapter = new Adapter();
  const engine = new Orchestrator({ adapter });
  try {
    await engine.initialize();
    const wf = workflow();
    await engine.action({ action: 'save-workflow', workflow: wf });
    await engine.action({ action: 'add-packet', workflowId: wf.id, title: 'Missing manager', input: 'Bounded local fixture.' });
    await engine.action({ action: 'connect' });
    await engine.action({ action: 'authorize', confirmed: true, allowWrites: true });
    await engine.action({ action: 'configure', maxConcurrency: 1 });
    await engine.action({ action: 'start' });
    await flush(engine); await new Promise((resolve) => setTimeout(resolve, 50)); await flush(engine);
    const task = current(engine, 'builder');
    assert.equal(task.state, 'blocked');
    assert.equal(task.blockReason, 'collaboration_checkpoints_unavailable');
    assert.equal(adapter.started.length, 0);
  } finally { await engine.close().catch(() => {}); }
});

test('restart blocks the running writer until stop is confirmed, then requires fresh consent', async () => {
  const value = await fixture(); const statePath = join(value.root, 'state.json');
  let engine;
  try {
    const first = await setup({ statePath, manager: value.manager, checkpoints: value.manager }); engine = first.engine;
    const original = current(engine, 'builder'); const originalCwd = original.cwd;
    await engine.close();
    engine = new Orchestrator({ adapter: new Adapter(), statePath, prepareWorkspace: value.manager.prepare.bind(value.manager), checkpoints: value.manager });
    await engine.initialize();
    const recovered = current(engine, 'builder');
    assert.equal(recovered.recoveryUnknown, true);
    await assert.rejects(engine.action({ action: 'retry', taskId: recovered.id }), /confirm_previous_worker_stopped/);
    await engine.action({ action: 'retry', taskId: recovered.id, confirmedStopped: true });
    assert.equal(current(engine, 'builder').state, 'queued');
    assert.equal(engine.state.consent.execution, false);
    await engine.action({ action: 'connect' });
    await engine.action({ action: 'authorize', confirmed: true, allowWrites: true });
    await engine.action({ action: 'start' }); await flush(engine);
    const restarted = current(engine, 'builder');
    assert.equal(restarted.state, 'running'); assert.notEqual(restarted.cwd, originalCwd);
  } finally { await engine?.close().catch(() => {}); await rm(value.root, { recursive: true, force: true }); }
});

test('missing checkpoint manifest blocks restart instead of restoring a writer', async () => {
  const value = await fixture(); const statePath = join(value.root, 'state.json');
  let engine;
  try {
    const first = await setup({ statePath, manager: value.manager, checkpoints: value.manager }); engine = first.engine;
    const task = current(engine, 'builder');
    first.adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: envelope('Initial build.') }); await flush(engine);
    assert.ok(task.fileCheckpoint?.id);
    await engine.close(); engine = null;
    await rm(join(value.root, 'owned', 'checkpoints', 'manifests', `${task.fileCheckpoint.id}.json`), { force: true });
    const restored = new Orchestrator({ adapter: new Adapter(), statePath, prepareWorkspace: value.manager.prepare.bind(value.manager), checkpoints: value.manager });
    await assert.rejects(restored.initialize(), /state_checkpoint|checkpoint/);
    await restored.close().catch(() => {});
  } finally { await engine?.close().catch(() => {}); await rm(value.root, { recursive: true, force: true }); }
});

test('failed native verification repairs from a fresh checkpoint workspace', async () => {
  const value = await fixture(); let engine; let checks = 0;
  const wf = workflow(); wf.nodes[0] = { ...wf.nodes[0], verificationCommand: ['native-check'], maxAttempts: 2 };
  const adapter = new Adapter();
  const originalStart = adapter.startTask.bind(adapter);
  adapter.startTask = async (input) => {
    const result = await originalStart(input);
    await writeFile(join(input.cwd, checks === 0 ? 'bad.txt' : 'fixed.txt'), checks === 0 ? 'bad' : 'fixed');
    return result;
  };
  const verifier = { verifyCommand: async ({ cwd }) => { checks++; const hasFix = await readFile(join(cwd, 'fixed.txt'), 'utf8').then(() => true).catch(() => false); return checks === 1 ? { exitCode: 1, stderr: 'repair required' } : { exitCode: hasFix ? 0 : 1, stderr: hasFix ? '' : 'missing fix' }; } };
  try {
    engine = new Orchestrator({ adapter, verifier, prepareWorkspace: value.manager.prepare.bind(value.manager), checkpoints: value.manager }); await engine.initialize();
    engine.state.project.conversationDefault = 'legacy';
    await engine.action({ action: 'save-workflow', workflow: wf }); await engine.action({ action: 'add-packet', workflowId: wf.id, title: 'Native repair', input: 'Bounded local fixture.' });
    await engine.action({ action: 'connect' }); await engine.action({ action: 'authorize', confirmed: true, allowWrites: true }); await engine.action({ action: 'configure', maxConcurrency: 1 }); await engine.action({ action: 'start' }); await flush(engine);
    const task = current(engine, 'builder');
    adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: envelope('Build with native check.') }); await flush(engine);
    assert.equal(task.attempts, 2); assert.equal(task.state, 'running'); assert.equal(checks, 1);
    assert.ok(task.cwd); assert.ok(await readFile(join(task.cwd, 'bad.txt'), 'utf8'));
    await writeFile(join(task.cwd, 'fixed.txt'), 'fixed');
    adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: envelope('Repaired build.') }); await flush(engine);
    await flush(engine); await new Promise((resolve) => setTimeout(resolve, 50)); await flush(engine);
    assert.equal(task.state, 'review'); assert.equal(checks, 2); assert.ok(task.fileCheckpoint);
    assert.equal(task.checkpointHistory.length, 2); assert.equal(task.checkpointHistory[0].kind, 'repair'); assert.equal(task.checkpointHistory[1].kind, 'result');
  } finally { await engine?.close().catch(() => {}); await rm(value.root, { recursive: true, force: true }); }
});

test('tampered checkpoint is rejected at human acceptance without routing output', async () => {
  const value = await fixture(); let engine;
  try {
    const result = await setup({ manager: value.manager, checkpoints: value.manager }); engine = result.engine;
    const task = current(engine, 'builder');
    result.adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: envelope('Ready for review.') }); await flush(engine);
    assert.equal(task.state, 'review');
    const manifest = JSON.parse(await readFile(join(value.root, 'owned', 'checkpoints', 'manifests', `${task.fileCheckpoint.id}.json`), 'utf8'));
    const file = manifest.files[0]; await writeFile(join(value.root, 'owned', 'checkpoints', 'blobs', file.sha256.slice(0, 2), file.sha256), 'tampered');
    await assert.rejects(engine.action({ action: 'accept', taskId: task.id }), /checkpoint|manifest|blob/);
    assert.equal(task.state, 'review'); assert.equal(engine.state.packets[0].outputs.builder, undefined); assert.equal(current(engine, 'reviewer'), undefined);
  } finally { await engine?.close().catch(() => {}); await rm(value.root, { recursive: true, force: true }); }
});
