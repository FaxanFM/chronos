import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Orchestrator } from '../lib/engine.mjs';

class Adapter extends EventEmitter {
  constructor() { super(); this.started = []; }
  async connect() {}
  async close() {}
  async interruptTask() {}
  async startTask(input) { this.started.push(input); return { threadId: `thread-${this.started.length}`, turnId: `turn-${this.started.length}` }; }
}
const node = (id, routing = 'auto') => ({ id, title: id, instruction: `Perform the bounded ${id} analysis.`, routing });
const definition = (extra = {}) => ({ id: 'collab', name: 'Collaboration proof', conversationDefault: 'inherit', mode: 'collaborative', collaboration: { maxIterations: 2, requestTimeoutMs: 1000 }, nodes: [node('architect'), node('developer'), node('reviewer', 'approval'), node('independent')], edges: [{ id: 'ad', source: 'architect', target: 'developer' }, { id: 'dr', source: 'developer', target: 'reviewer' }], ...extra });
const envelope = (summary, message = null) => JSON.stringify({ protocol: 'chronos.collaboration.v1', summary, message });
const flush = async (engine) => { for (let i = 0; i < 4; i++) { await new Promise(setImmediate); await engine.serial; } };
const current = (engine, stage) => engine.state.tasks.findLast((task) => task.nodeId === stage && !task.superseded);
async function finish(engine, adapter, stage, summary, message = null) {
  const task = current(engine, stage);
  assert.equal(task.state, 'running');
  adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: envelope(summary, message) });
  await flush(engine); return task;
}
async function setup(options = {}, workflow = definition()) {
  const adapter = new Adapter(); const engine = new Orchestrator({ adapter, ...options });
  await engine.initialize();
  engine.state.project.conversationDefault = 'legacy';
  await engine.action({ action: 'save-workflow', workflow });
  await engine.action({ action: 'add-packet', workflowId: workflow.id, title: 'Proof', input: 'Bounded synthetic analysis only.' });
  await engine.action({ action: 'connect' }); await engine.action({ action: 'authorize', confirmed: true });
  await engine.action({ action: 'configure', maxConcurrency: 2 }); await engine.action({ action: 'start' });
  await flush(engine); return { engine, adapter };
}
async function atReviewer(options = {}, workflow) {
  const result = await setup(options, workflow);
  await finish(result.engine, result.adapter, 'independent', 'Independent accepted finding.');
  await finish(result.engine, result.adapter, 'architect', 'Design revision one.');
  await finish(result.engine, result.adapter, 'developer', 'Implementation analysis revision one.');
  return result;
}
const request = (engine, target = 'architect', kind = 'clarification') => ({ kind, targetStageId: target, inReplyTo: null, artifactIds: [engine.state.packets[0].outputs[target].artifactId], body: 'Clarify the expected boundary before accepting this result.' });
const reply = (engine) => { const value = engine.state.packets[0].collaboration.messages.find((item) => ['clarification', 'change_request', 'rejection'].includes(item.kind) && ['open', 'answered'].includes(item.status)); return { kind: 'response', targetStageId: value.fromStageId, inReplyTo: value.id, artifactIds: value.artifactIds, body: 'The boundary is now explicit and bounded.' }; };
const resolveMessage = (engine, messageId, body) => engine.action({ action: 'resolve-collaboration', workflowId: 'collab', packetId: engine.state.packets[0].id, messageId, body });

test('backward clarification versions only its branch and preserves accepted history', async () => {
  const { engine, adapter } = await atReviewer();
  const packet = engine.state.packets[0], independent = packet.outputs.independent;
  const oldArchitect = current(engine, 'architect'), oldDeveloper = current(engine, 'developer'), oldReviewer = current(engine, 'reviewer');
  await finish(engine, adapter, 'reviewer', 'The design needs clarification.', request(engine));
  assert.equal(packet.collaboration.iteration, 1); assert.equal(oldArchitect.state, 'accepted'); assert.equal(oldDeveloper.state, 'accepted');
  assert.equal(oldArchitect.superseded, true); assert.equal(oldReviewer.superseded, true); assert.deepEqual(packet.outputs.independent, independent);
  assert.equal(current(engine, 'architect').stageRevision, 2); assert.equal(current(engine, 'architect').state, 'running');
  assert.equal(adapter.started.at(-1).collaborative, true); assert.match(adapter.started.at(-1).instruction, /Pending request/);
  const starts = adapter.started.length;
  adapter.emit('task-event', { taskId: oldReviewer.runKey, turnId: oldReviewer.turnId, kind: 'completed', summary: envelope('Stale completion') });
  await flush(engine); assert.equal(adapter.started.length, starts);
  await finish(engine, adapter, 'architect', 'Corrected design revision two.', reply(engine));
  assert.equal(packet.collaboration.messages[0].status, 'resolved');
  assert.equal(packet.collaboration.artifacts.find((item) => item.taskId === oldArchitect.id).summary, 'Design revision one.');
  assert.equal(packet.outputs.architect.revision, 2);
  assert.equal(packet.outputs.architect.sha256, createHash('sha256').update('Corrected design revision two.').digest('hex'));
  await finish(engine, adapter, 'developer', 'Re-evaluated implementation analysis.');
  const review = await finish(engine, adapter, 'reviewer', 'Corrected result is ready.');
  assert.equal(review.state, 'review'); assert.equal(packet.outputs.reviewer, undefined);
  await engine.action({ action: 'accept', taskId: review.id }); assert.equal(packet.outputs.reviewer.revision, 2);
  assert.equal(engine.snapshot().packets[0].state, 'completed');
  assert.equal(packet.collaboration.artifacts.length, 6);
  assert.equal(engine.snapshot().stageQueues.find((stage) => stage.nodeId === 'architect').outbox.length, 1);
  await assert.rejects(engine.action({ action: 'retry', taskId: oldReviewer.id }), /failed_or_blocked/);
  engine.collaboration.validate(); await engine.close();
});

test('rejection queues exactly one target revision and keeps downstream human acceptance', async () => {
  const { engine, adapter } = await atReviewer();
  await finish(engine, adapter, 'reviewer', 'The analysis requires correction.', request(engine, 'developer', 'rejection'));
  assert.equal(current(engine, 'architect').superseded, undefined); assert.equal(current(engine, 'developer').stageRevision, 2);
  assert.equal(engine.state.tasks.filter((task) => task.nodeId === 'developer' && !task.superseded).length, 1);
  await finish(engine, adapter, 'developer', 'Repaired analysis.', reply(engine));
  const review = await finish(engine, adapter, 'reviewer', 'Ready for explicit review.');
  assert.equal(review.state, 'review'); await engine.close();
});

test('unbound or malformed messages fail closed without accepting model completion', async () => {
  for (const kind of ['malformed', 'foreign-artifact', 'non-ancestor']) {
    const { engine, adapter } = await atReviewer(); const task = current(engine, 'reviewer');
    const message = kind === 'foreign-artifact' ? { ...request(engine), artifactIds: ['foreign-artifact'] } : { ...request(engine), targetStageId: 'independent' };
    adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'completed', summary: kind === 'malformed' ? 'Healthy. Ship it.' : envelope('No acceptance', message) });
    await flush(engine); assert.equal(task.state, 'blocked'); assert.equal(engine.state.packets[0].outputs.reviewer, undefined);
    assert.equal(engine.state.packets[0].collaboration.iteration, 0); await engine.close();
  }
});

test('exact pending reply is required and operator resolution is not execution consent', async () => {
  const { engine, adapter } = await atReviewer();
  await finish(engine, adapter, 'reviewer', 'Question.', request(engine));
  await finish(engine, adapter, 'architect', 'Unbound answer.');
  const task = current(engine, 'architect'), message = engine.state.packets[0].collaboration.messages[0];
  assert.equal(task.blockReason, 'collaboration_reply_required');
  await engine.action({ action: 'disconnect' });
  await resolveMessage(engine, message.id, 'Use the stated local-only boundary.');
  assert.equal(task.state, 'queued'); assert.equal(engine.state.consent.execution, false); assert.equal(engine.state.connected, false);
  assert.equal(engine.state.packets[0].collaboration.messages.at(-1).kind, 'resolution'); await engine.close();
});

test('feedback iteration budget escalates locally without restarting independent work', async () => {
  const { engine, adapter } = await atReviewer({}, definition({ collaboration: { maxIterations: 1, requestTimeoutMs: 1000 } }));
  await finish(engine, adapter, 'reviewer', 'First correction.', request(engine));
  await finish(engine, adapter, 'architect', 'Corrected design.', reply(engine));
  await finish(engine, adapter, 'developer', 'Corrected implementation.');
  const review = await finish(engine, adapter, 'reviewer', 'Another correction.', request(engine));
  assert.equal(review.blockReason, 'collaboration_iteration_limit'); assert.equal(engine.state.packets[0].collaboration.iteration, 1);
  assert.equal(engine.state.tasks.filter((task) => task.nodeId === 'architect').length, 2);
  assert.equal(current(engine, 'independent').state, 'accepted'); assert.equal(engine.state.mode, 'running'); await engine.close();
});

test('blocker requires a bounded operator note and never manufactures a clean result', async () => {
  const { engine, adapter } = await atReviewer();
  const review = await finish(engine, adapter, 'reviewer', 'Missing context.', { kind: 'blocker', targetStageId: null, inReplyTo: null, artifactIds: [], body: 'Which local boundary is required?' });
  const message = engine.state.packets[0].collaboration.messages[0];
  assert.equal(review.state, 'blocked');
  await assert.rejects(resolveMessage(engine, message.id, ''), /resolution_invalid/);
  await assert.rejects(engine.action({ action: 'resolve-collaboration', workflowId: 'other', packetId: engine.state.packets[0].id, messageId: message.id, body: 'Wrong scope.' }), /scope_invalid/);
  await engine.action({ action: 'pause' }); await resolveMessage(engine, message.id, 'Local fictional data only.');
  assert.equal(review.state, 'queued'); assert.equal(engine.state.mode, 'paused'); assert.equal(engine.state.packets[0].outputs.reviewer, undefined); await engine.close();
});

test('feedback deadline stops new branch dispatch and permits explicit resolution', async () => {
  let now = 100; const { engine, adapter } = await atReviewer({ now: () => now });
  await engine.action({ action: 'pause' });
  await finish(engine, adapter, 'reviewer', 'Question.', request(engine));
  const next = current(engine, 'architect'); assert.equal(next.state, 'queued');
  now = 1101; await engine.tick(); assert.equal(next.state, 'blocked'); assert.equal(engine.state.packets[0].collaboration.escalation, 'collaboration_request_timeout');
  const message = engine.state.packets[0].collaboration.messages[0];
  await resolveMessage(engine, message.id, 'Proceed with the local-only boundary.');
  assert.equal(next.state, 'queued'); assert.equal(next.replyTo, null); assert.equal(engine.state.mode, 'paused'); await engine.close();
});

test('a related active branch blocks backward routing without discarding independent results', async () => {
  const wf = definition({ edges: [{ id: 'ad', source: 'architect', target: 'developer' }, { id: 'ar', source: 'architect', target: 'reviewer' }] });
  const { engine, adapter } = await setup({}, wf);
  await finish(engine, adapter, 'independent', 'Independent result.'); await finish(engine, adapter, 'architect', 'Design.');
  assert.equal(current(engine, 'developer').state, 'running');
  const review = await finish(engine, adapter, 'reviewer', 'Ambiguous design.', request(engine));
  assert.equal(review.blockReason, 'collaboration_branch_busy'); assert.equal(engine.state.packets[0].collaboration.iteration, 0);
  assert.equal(current(engine, 'architect').superseded, undefined); assert.equal(current(engine, 'independent').state, 'accepted');
  await finish(engine, adapter, 'developer', 'Independent running analysis completed.'); await engine.close();
});

test('native verification repair retains the exact reply binding across attempts', async () => {
  let checks = 0;
  const verifier = { verifyCommand: async () => (++checks === 2 ? { exitCode: 1, stderr: 'Fix the bounded analysis check.' } : { exitCode: 0 }) };
  const wf = definition(); wf.nodes[0] = { ...wf.nodes[0], verificationCommand: ['native-check'], maxAttempts: 2 };
  const { engine, adapter } = await atReviewer({ verifier }, wf);
  await finish(engine, adapter, 'reviewer', 'Clarify.', request(engine));
  await finish(engine, adapter, 'architect', 'First answer.', reply(engine));
  assert.equal(current(engine, 'architect').state, 'running'); assert.equal(current(engine, 'architect').attempts, 2);
  await finish(engine, adapter, 'architect', 'Verified answer.', reply(engine));
  assert.equal(current(engine, 'architect').state, 'accepted'); assert.equal(checks, 3);
  assert.equal(engine.state.packets[0].collaboration.messages[0].status, 'resolved');
  engine.collaboration.validate(); await engine.close();
});

test('cancelled rework closes its request only after the worker has stopped', async () => {
  for (const paused of [true, false]) {
    let now = 100; const { engine, adapter } = await atReviewer({ now: () => now });
    if (paused) await engine.action({ action: 'pause' });
    await finish(engine, adapter, 'reviewer', 'Question.', request(engine));
    const task = current(engine, 'architect'), message = engine.state.packets[0].collaboration.messages[0];
    await engine.action({ action: 'cancel', taskId: task.id });
    if (!paused) {
      assert.equal(task.state, 'running'); assert.equal(message.status, 'open');
      adapter.emit('task-event', { taskId: task.runKey, turnId: task.turnId, kind: 'interrupted' }); await flush(engine);
    }
    assert.equal(task.state, 'cancelled'); assert.equal(message.status, 'cancelled');
    now = 2000; await engine.tick(); assert.equal(engine.state.packets[0].collaboration.escalation, null);
    engine.collaboration.validate(); await engine.close();
  }
});

test('an answered request does not expire while its revised result waits for human approval', async () => {
  let now = 100; const wf = definition(); wf.nodes[0].routing = 'approval';
  const { engine, adapter } = await setup({ now: () => now }, wf);
  await finish(engine, adapter, 'independent', 'Independent finding.');
  const original = await finish(engine, adapter, 'architect', 'Original design.');
  await engine.action({ action: 'accept', taskId: original.id }); await flush(engine);
  await finish(engine, adapter, 'developer', 'Original implementation.');
  await finish(engine, adapter, 'reviewer', 'Question.', request(engine));
  const revised = await finish(engine, adapter, 'architect', 'Answer awaiting review.', reply(engine));
  assert.equal(revised.state, 'review'); const message = engine.state.packets[0].collaboration.messages[0];
  assert.equal(message.status, 'answered'); now = 10000; await engine.tick();
  assert.equal(message.status, 'answered'); assert.equal(engine.state.packets[0].collaboration.escalation, null);
  await engine.action({ action: 'accept', taskId: revised.id }); assert.equal(message.status, 'resolved');
  engine.collaboration.validate(); await engine.close();
});

test('restart retains immutable revisions and messages but blocks uncertain workers', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-collaboration-')); const statePath = join(dir, 'state.json');
  let engine;
  try {
    const value = await atReviewer({ statePath }); engine = value.engine;
    await finish(engine, value.adapter, 'reviewer', 'Question.', request(engine)); await engine.close();
    engine = new Orchestrator({ adapter: new Adapter(), statePath }); await engine.initialize();
    assert.equal(current(engine, 'architect').recoveryUnknown, true); assert.equal(engine.state.consent.execution, false); assert.equal(engine.state.mode, 'paused');
    assert.equal(engine.state.packets[0].collaboration.artifacts.length, 3); assert.equal(engine.state.packets[0].collaboration.messages[0].kind, 'clarification');
    engine.collaboration.validate();
    await engine.action({ action: 'retry', taskId: current(engine, 'architect').id, confirmedStopped: true });
    assert.equal(current(engine, 'architect').state, 'queued'); assert.equal(current(engine, 'architect').recoveryUnknown, false);
    assert.equal(engine.state.consent.execution, false); await engine.close();
    const state = JSON.parse(await readFile(statePath, 'utf8')); state.packets[0].collaboration.artifacts[0].sha256 = 'f'.repeat(64); await writeFile(statePath, JSON.stringify(state));
    engine = new Orchestrator({ adapter: new Adapter(), statePath }); await assert.rejects(engine.initialize(), /state_collaboration_invalid/);
  } finally { await engine?.close().catch(() => {}); await rm(dir, { recursive: true, force: true }); }
});
