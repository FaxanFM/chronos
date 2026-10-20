import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Orchestrator } from '../lib/engine.mjs';

class Adapter extends EventEmitter {
  async connect() {}
  async close() {}
  async interruptTask() {}
  async startTask() { return { threadId: 'thread-safety', turnId: 'turn-safety' }; }
}
const node = (id, routing = 'auto') => ({ id, title: id, instruction: `Perform bounded ${id} work.`, routing });
const workflow = { id: 'safety-collab', name: 'Safety collaboration', conversationDefault: 'inherit', mode: 'collaborative', collaboration: { maxIterations: 2, requestTimeoutMs: 1000 }, nodes: [node('architect'), node('reviewer', 'approval')], edges: [{ id: 'ar', source: 'architect', target: 'reviewer' }] };
const flush = async (engine) => { for (let i = 0; i < 4; i++) { await new Promise(setImmediate); await engine.serial; } };
const envelope = (summary, message = null) => JSON.stringify({ protocol: 'chronos.collaboration.v1', summary, message });
const current = (engine, stage) => engine.state.tasks.findLast((task) => task.nodeId === stage && !task.superseded);
async function fixture() {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-collab-safety-')); const statePath = join(dir, 'state.json'); const adapter = new Adapter(); const engine = new Orchestrator({ adapter, statePath });
  await engine.initialize(); engine.state.project.conversationDefault = 'legacy'; await engine.action({ action: 'save-workflow', workflow }); await engine.action({ action: 'add-packet', workflowId: workflow.id, title: 'Safety', input: 'Synthetic bounded input.' });
  await engine.action({ action: 'connect' }); await engine.action({ action: 'authorize', confirmed: true }); await engine.action({ action: 'start' }); await flush(engine);
  const architect = current(engine, 'architect'); adapter.emit('task-event', { taskId: architect.runKey, turnId: architect.turnId, kind: 'completed', summary: envelope('Accepted architecture.') }); await flush(engine);
  return { dir, statePath, engine };
}
async function mutateAndReject(mutator) {
  const value = await fixture(); try {
    await value.engine.close();
    const state = JSON.parse(await readFile(value.statePath, 'utf8')); await mutator(state); await writeFile(value.statePath, JSON.stringify(state));
    await assert.rejects(new Orchestrator({ adapter: new Adapter(), statePath: value.statePath }).initialize(), /state_collaboration_invalid|state_task_reference_invalid|state_packet_output_invalid/);
  } finally { await value.engine.close().catch(() => {}); await rm(value.dir, { recursive: true, force: true }); }
}

test('rejects an input artifact imported from another packet', async () => {
  await mutateAndReject((state) => {
    const packet = state.packets[0], sourceTask = state.tasks.find((task) => task.packetId === packet.id && task.state === 'accepted');
    const foreignPacketId = 'foreign-packet'; const foreignTaskId = 'foreign-task'; const foreignArtifactId = 'foreign-artifact';
    const foreignPacket = { ...packet, id: foreignPacketId, outputs: { architect: { taskId: foreignTaskId, summary: sourceTask.summary, artifactId: foreignArtifactId, revision: 1, sha256: hash(sourceTask.summary) }, }, collaboration: structuredClone(packet.collaboration) };
    foreignPacket.collaboration.artifacts = [{ ...packet.collaboration.artifacts.find((artifact) => artifact.taskId === sourceTask.id), id: foreignArtifactId, taskId: foreignTaskId }];
    const foreignTask = { ...sourceTask, id: foreignTaskId, packetId: foreignPacketId, artifactId: foreignArtifactId, inputArtifactIds: [] };
    state.packets.push(foreignPacket); state.tasks.push(foreignTask); packet.collaboration.artifacts[0].inputArtifactIds = [foreignArtifactId];
  });
});

test('rejects a persisted reply with the wrong target stage', async () => {
  await mutateAndReject((state) => {
    const packet = state.packets[0]; packet.collaboration.messages.push({ id: 'request-1', kind: 'clarification', fromTaskId: state.tasks.find((task) => task.packetId === packet.id && task.state === 'accepted').id, fromStageId: 'architect', toStageId: 'reviewer', artifactIds: [packet.collaboration.artifacts[0].id], body: 'Question', inReplyTo: null, status: 'open', createdAt: 1, resolvedAt: null });
    const task = state.tasks.find((item) => item.packetId === packet.id && item.nodeId === 'reviewer'); task.replyTo = 'request-1'; task.state = 'blocked'; task.blockReason = 'collaboration_reply_required';
  });
});

test('rejects a persisted request targeting a non-ancestor stage', async () => {
  await mutateAndReject((state) => {
    const packet = state.packets[0], task = state.tasks.find((item) => item.packetId === packet.id && item.state === 'accepted');
    packet.collaboration.messages.push({ id: 'request-2', kind: 'clarification', fromTaskId: task.id, fromStageId: task.nodeId, toStageId: 'reviewer', artifactIds: [task.artifactId], body: 'Invalid route', inReplyTo: null, status: 'open', createdAt: 1, resolvedAt: null });
  });
});

test('rejects a current-stage output selection that is missing from packet outputs', async () => {
  await mutateAndReject((state) => { delete state.packets[0].outputs.architect; });
});

test('rejects duplicate non-superseded current-stage tasks', async () => {
  await mutateAndReject((state) => {
    const task = state.tasks.find((item) => item.packetId === state.packets[0].id && item.nodeId === 'reviewer'); state.tasks.push({ ...task, id: 'duplicate-current-stage', state: 'queued', runKey: null, threadId: null, turnId: null });
  });
});

test('rejects collaboration history beyond the bounded message capacity', async () => {
  await mutateAndReject((state) => {
    const packet = state.packets[0], task = state.tasks.find((item) => item.packetId === packet.id && item.state === 'accepted');
    for (let i = 0; i < 129; i++) packet.collaboration.messages.push({ id: `history-${i}`, kind: 'blocker', fromTaskId: task.id, fromStageId: task.nodeId, toStageId: null, artifactIds: [], body: 'bounded history', inReplyTo: null, status: 'resolved', createdAt: i + 1, resolvedAt: i + 1 });
  });
});

test('retains explicitly declared cross-packet source task IDs', async () => {
  const value = await fixture(); try {
    await value.engine.action({ action: 'pause' });
    await value.engine.action({ action: 'add-packet', workflowId: workflow.id, title: 'Consumer', input: 'Uses an accepted source.', sourceTaskIds: [value.engine.state.tasks.find((task) => task.state === 'accepted').id] });
    value.engine.collaboration.validate();
  } finally { await value.engine.close(); await rm(value.dir, { recursive: true, force: true }); }
});

function hash(value) { return createHash('sha256').update(value).digest('hex'); }
