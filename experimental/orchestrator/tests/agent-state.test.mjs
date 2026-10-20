import test from 'node:test';
import assert from 'node:assert/strict';
import { AgentController, AGENT_RETENTION, validateRetention } from '../lib/agent-state.mjs';

function engine() {
  const state = { schemaVersion: 5, workflows: [], tasks: [], packets: [], mode: 'paused', connected: true, consent: { execution: true }, events: [] };
  return { state, now: () => 1000, adapter: { cwd: process.cwd(), diagnostics: () => ({ sessionCapabilities: { prepare: true, resume: true, turn: true } }), runtimeIdentity: () => 'test-runtime', prepareSession: async ({ threadId, binding }) => ({ threadId: threadId || 'test-thread', binding: binding || { threadId: threadId || 'test-thread' } }), startSessionTurn: async () => ({ ok: true }) }, event: (...args) => state.events.push(args), save: async () => {}, enqueue: async (fn) => fn() };
}

test('retention validation preserves bounded defaults and rejects unsafe reductions', () => {
  assert.equal(validateRetention({}).maxUnarchivedSessions, AGENT_RETENTION.maxUnarchivedSessions);
  assert.throws(() => validateRetention({ maxSessionRecords: 1 }), /agent_retention_invalid/);
  assert.throws(() => validateRetention({ maxUnarchivedSessions: 65, maxSessionRecords: 64 }), /agent_retention_invalid/);
});

test('bootstrap creates stable stage agents and hybrid only for new projects', () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', name: 'Workflow', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  const controller = new AgentController(e);
  controller.bootstrap();
  assert.equal(e.state.project.conversationDefault, 'hybrid');
  assert.equal(e.state.agents.length, 1);
  assert.equal(e.state.agents[0].stageRefs[0].workflowId, 'wf');
  const legacy = engine(); legacy.state.workflows = e.state.workflows;
  controller.bootstrap();
  assert.equal(e.state.project.conversationDefault, 'hybrid');
  assert.equal(legacy.state.project, undefined);
});

test('recovery inspects the owned native session before clearing uncertainty', async () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', name: 'Workflow', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  e.state.tasks = [{ id: 'task', sessionId: 'session', recoveryUnknown: true, state: 'blocked' }];
  e.state.save = async () => {};
  e.enqueue = async (fn) => fn();
  e.event = () => {};
  e.adapter.inspectSession = async () => ({ status: 'idle' });
  const controller = new AgentController(e); controller.bootstrap();
  e.state.sessions = [{ id: 'session', projectId: e.state.project.id, agentId: e.state.agents[0].id, role: 'worker', state: 'uncertain', recoveryRequired: true, threadId: 'thread', binding: { threadId: 'thread' }, generation: 1, scope: { projectId: e.state.project.id, agentId: e.state.agents[0].id }, turns: 1, attemptHistory: [] }];
  const result = await controller.action({ action: 'recover-agent-session', sessionId: 'session', confirmed: true });
  assert.equal(result.recovered, true);
  assert.equal(e.state.sessions[0].state, 'idle');
  assert.equal(e.state.tasks[0].recoveryUnknown, false);
});

test('unobserved compaction exposes explicit recovery instead of stranding maintenance', async () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  const controller = new AgentController(e); controller.bootstrap();
  const agent = e.state.agents[0]; agent.primarySessionId = 'primary';
  e.state.sessions = [{ id: 'primary', agentId: agent.id, state: 'idle', threadId: 'thread', binding: {}, scope: {} }];
  e.adapter.diagnostics = () => ({ sessionCapabilities: { compact: true } });
  e.adapter.compactSession = async () => ({ accepted: true, completed: false });
  e.adapter.inspectSession = async () => ({ status: 'idle' });
  await controller.action({ action: 'compact-agent', agentId: agent.id, confirmed: true });
  assert.equal(e.state.sessions[0].state, 'uncertain'); assert.equal(e.state.sessions[0].recoveryRequired, true);
  await controller.action({ action: 'recover-agent-session', sessionId: 'primary', confirmed: true });
  assert.equal(e.state.sessions[0].state, 'idle'); assert.equal(e.state.sessions[0].recoveryRequired, false);
});

test('rotation preserves the agent identity and existing lineage', async () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  const controller = new AgentController(e); controller.bootstrap();
  const agent = e.state.agents[0];
  agent.primarySessionId = 'primary-1';
  agent.lineage.push({ sessionId: 'primary-1', generation: 1, at: 1000 });
  await controller.action({ action: 'rotate-agent', agentId: agent.id, confirmed: true });
  assert.equal(agent.id, e.state.agents[0].id);
  assert.equal(agent.lineage.length, 1);
  assert.equal(agent.rotationIntent.predecessorId, 'primary-1');
});

test('retention configuration refuses to drop protected records', async () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  const controller = new AgentController(e); controller.bootstrap();
  e.state.projectAudit = Array.from({ length: 3 }, (_, index) => ({ sequence: index + 1, previous: null, sha256: `audit-${index}` }));
  e.state.ledger = Array.from({ length: 2 }, (_, index) => ({ id: `ledger-${index}` }));
  assert.rejects(controller.action({ action: 'configure-agent-retention', retention: { maxAuditEntries: 2 } }), /retention_below_protected_history/);
  assert.rejects(controller.action({ action: 'configure-agent-retention', retention: { maxLedgerEntries: 1 } }), /retention_below_protected_history/);
});

test('cleanup excludes live, pinned, question-blocked and dependent sessions', async () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  const controller = new AgentController(e); controller.bootstrap();
  const agentId = e.state.agents[0].id;
  e.adapter.diagnostics = () => ({ sessionCapabilities: { archive: false } });
  e.state.sessions = [
    { id: 'live', projectId: e.state.project.id, agentId, role: 'worker', state: 'active', threadId: 'live-thread', binding: { threadId: 'live-thread' }, generation: 1, scope: { projectId: e.state.project.id, agentId } },
    { id: 'pinned', projectId: e.state.project.id, agentId, role: 'worker', state: 'idle', pinned: true, threadId: 'pinned-thread', binding: { threadId: 'pinned-thread' }, generation: 1, scope: { projectId: e.state.project.id, agentId } },
    { id: 'question', projectId: e.state.project.id, agentId, role: 'worker', state: 'idle', threadId: 'question-thread', binding: { threadId: 'question-thread' }, generation: 1, scope: { projectId: e.state.project.id, agentId } }
  ];
  e.state.tasks = [
    { id: 'live-task', sessionId: 'live', agentId, state: 'running', dependencies: [] },
    { id: 'pinned-task', sessionId: 'pinned', agentId, state: 'accepted', dependencies: [] },
    { id: 'question-task', sessionId: 'question', agentId, state: 'accepted', dependencies: [] }
  ];
  e.state.agentQuestions = [{ id: 'q1', sessionId: 'question', taskId: 'question-task', agentId, state: 'waiting', question: 'Need a decision' }];
  await controller.cleanup();
  assert.equal(e.state.sessions.find((session) => session.id === 'live').state, 'active');
  assert.equal(e.state.sessions.find((session) => session.id === 'pinned').state, 'idle');
  assert.equal(e.state.sessions.find((session) => session.id === 'question').state, 'idle');
});

test('archiving a task retains question provenance for later recovery', () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  const controller = new AgentController(e); controller.bootstrap();
  const agentId = e.state.agents[0].id;
  const item = { id: 'archived-task', agentId, sessionId: 'session-1', state: 'blocked', summary: 'Waiting' };
  e.state.tasks = [item];
  e.state.agentQuestions = [{ id: 'question-1', agentId, taskId: item.id, state: 'answered', question: 'Need approval' }];
  const record = controller.archiveTasks([item]);
  assert.deepEqual(record.questionIds, ['question-1']);
  assert.equal(record.taskId, item.id);
});

test('uncertain and cleanup-pending sessions count toward the unarchived limit', () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', conversationDefault: 'hybrid', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  const controller = new AgentController(e); controller.bootstrap();
  e.state.project.retention.maxUnarchivedSessions = 2;
  const agentId = e.state.agents[0].id;
  e.state.sessions = [
    { id: 'uncertain', projectId: e.state.project.id, agentId, role: 'worker', state: 'uncertain', threadId: 'thread-uncertain', binding: { threadId: 'thread-uncertain' }, generation: 1, scope: { projectId: e.state.project.id, agentId } },
    { id: 'pending', projectId: e.state.project.id, agentId, role: 'worker', state: 'cleanup-pending', threadId: 'thread-pending', binding: { threadId: 'thread-pending' }, generation: 1, scope: { projectId: e.state.project.id, agentId } }
  ];
  const task = { id: 'new-task', packetId: 'packet-new', nodeId: 'stage', workflowId: 'wf', runKey: 'run-new', state: 'queued', policy: 'read-only', cwd: process.cwd(), dependencies: [], stageRevision: 1 };
  assert.throws(() => controller.plan(task, e.state.workflows[0].nodes[0], e.state.workflows[0], { relatedToProject: false }), /agent_session_capacity_cleanup_required/);
  assert.equal(e.state.sessions.length, 2);
});

test('loaded-session capacity blocks creation when the host reports no releasable slot', () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', conversationDefault: 'hybrid', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  e.adapter.diagnostics = () => ({ ownedTaskCount: 16, sessionCapabilities: { prepare: true, resume: true, turn: true } });
  const controller = new AgentController(e); controller.bootstrap();
  const task = { id: 'new-task', packetId: 'packet-new', nodeId: 'stage', workflowId: 'wf', runKey: 'run-new', state: 'queued', policy: 'read-only', cwd: process.cwd(), dependencies: [], stageRevision: 1 };
  assert.throws(() => controller.plan(task, e.state.workflows[0].nodes[0], e.state.workflows[0], { relatedToProject: false }), /agent_loaded_session_capacity_release_required/);
  assert.equal(e.state.sessions.length, 0);
});

test('changed runtime or data scope isolates a work item instead of reusing its session', () => {
  const e = engine();
  e.state.workflows = [{ id: 'wf', conversationDefault: 'hybrid', nodes: [{ id: 'stage', title: 'Stage', instruction: 'Do work' }], edges: [] }];
  let runtime = 'runtime-a'; e.adapter.runtimeIdentity = () => runtime;
  const controller = new AgentController(e); controller.bootstrap();
  const node = e.state.workflows[0].nodes[0], workflow = e.state.workflows[0];
  const first = { id: 'first', packetId: 'packet-first', nodeId: 'stage', workflowId: 'wf', runKey: 'run-first', state: 'queued', policy: 'read-only', cwd: process.cwd(), dependencies: [], stageRevision: 1, sourceThreadId: '11111111-1111-4111-8111-111111111111' };
  const firstPlan = controller.plan(first, node, workflow, { relatedToProject: false });
  firstPlan.session.state = 'idle';
  runtime = 'runtime-b';
  const second = { ...first, id: 'second', runKey: 'run-second' };
  const secondPlan = controller.plan(second, node, workflow, { relatedToProject: false });
  assert.notEqual(secondPlan.session.id, firstPlan.session.id);
  assert.equal(e.state.sessions.length, 2);
  secondPlan.session.state = 'idle';
  runtime = 'runtime-a';
  const third = { ...first, id: 'third', runKey: 'run-third', sourceThreadId: '22222222-2222-4222-8222-222222222222' };
  const thirdPlan = controller.plan(third, node, workflow, { relatedToProject: false });
  assert.notEqual(thirdPlan.session.id, firstPlan.session.id);
  assert.notEqual(thirdPlan.session.id, secondPlan.session.id);
  assert.equal(e.state.sessions.length, 3);
});
