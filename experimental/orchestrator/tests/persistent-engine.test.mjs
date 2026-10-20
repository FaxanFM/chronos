import test from 'node:test';
import assert from 'node:assert/strict';
import { AgentController } from '../lib/agent-state.mjs';

const workspace = process.cwd();

function fixture({ saved = null, workflowDefault = 'hybrid' } = {}) {
  const workflow = {
    id: 'wf-main', mode: 'serial', conversationDefault: workflowDefault,
    nodes: [{ id: 'stage-main', title: 'Main stage', instruction: 'Review the work.', conversationMode: 'hybrid' }],
    edges: []
  };
  const state = {
    schemaVersion: 5, mode: 'paused', connected: true,
    consent: { execution: true, writes: false }, workflows: [workflow], tasks: [], packets: [],
    ...(saved || {})
  };
  const engine = {
    state,
    adapter: {
      cwd: workspace,
      prepareSession: async () => ({ threadId: 'thread-1', binding: { threadId: 'thread-1' } }),
      startSessionTurn: async () => ({ ok: true }),
      runtimeIdentity: () => 'test-runtime',
      inspectSession: async () => ({ status: 'idle' })
    },
    now: () => '2026-10-20T00:00:00.000Z',
    event: () => {},
    save: async () => {},
    enqueue: async (fn) => fn(),
    closed: false
  };
  const controller = new AgentController(engine);
  controller.bootstrap(saved);
  return { engine, controller, workflow, node: workflow.nodes[0] };
}

function task(overrides = {}) {
  return {
    id: 'task-1', packetId: 'packet-1', nodeId: 'stage-main', workflowId: 'wf-main', runKey: 'run-1',
    state: 'running', policy: 'read-only', cwd: workspace, dependencies: [], stageRevision: 1,
    summary: '', ...overrides
  };
}

test('fresh projects default to Hybrid while a new stage gets a stable agent', () => {
  const { engine, controller } = fixture();
  assert.equal(engine.state.project.conversationDefault, 'hybrid');
  assert.equal(engine.state.agents.length, 1);
  assert.equal(engine.state.agents[0].stageRefs[0].nodeId, 'stage-main');
  assert.equal(controller.describe(task(), engine.state.workflows[0].nodes[0], engine.state.workflows[0], null).mode, 'hybrid');
});

test('legacy migration preserves the old conversation policy and records its source schema', () => {
  const { engine } = fixture({ saved: { schemaVersion: 4, workflows: [], tasks: [], packets: [] } });
  assert.equal(engine.state.project.conversationDefault, 'legacy');
  assert.equal(engine.state.project.migratedFrom, 4);
  assert.equal(engine.state.workflows.length, 0);
});

test('serial related Hybrid work reuses the idle primary session', () => {
  const { engine, controller, workflow, node } = fixture();
  const first = task({ id: 'task-1', relatedToProject: true });
  const firstPlan = controller.plan(first, node, workflow, { conversationMode: 'hybrid', relatedToProject: true });
  firstPlan.session.state = 'idle';
  firstPlan.agent.primarySessionId = firstPlan.session.id;
  const second = task({ id: 'task-2', runKey: 'run-2', relatedToProject: true });
  const secondPlan = controller.plan(second, node, workflow, { conversationMode: 'hybrid', relatedToProject: true });
  assert.equal(secondPlan.session.id, firstPlan.session.id);
  assert.equal(secondPlan.decision.role, 'primary');
  assert.equal(engine.state.sessions.length, 1);
});

test('needs-input blocks the same item and answering queues continuation without acceptance', async () => {
  const { engine, controller, workflow, node } = fixture();
  const item = task();
  const plan = controller.plan(item, node, workflow, { conversationMode: 'hybrid', relatedToProject: true });
  plan.session.state = 'active';
  item.sessionId = plan.session.id; item.agentId = plan.agent.id;
  engine.state.tasks.push(item);
  controller.outcome(item, { kind: 'completed', summary: JSON.stringify({ status: 'needs-input', summary: 'Need a decision.', question: { body: 'Which source should I use?', targetAgentId: null } }) });
  assert.equal(item.state, 'blocked');
  assert.equal(engine.state.ledger.length, 0);
  const question = engine.state.agentQuestions[0];
  await controller.action({ action: 'answer-agent-question', questionId: question.id, message: 'Use the approved source.' });
  assert.equal(question.state, 'answered');
  assert.equal(item.state, 'queued');
  assert.equal(item.continuationAnswer.answer, 'Use the approved source.');
  assert.equal(engine.state.ledger.length, 0);
});

test('restart marks active sessions uncertain and explicit inspection recovers idle state', async () => {
  const initial = fixture();
  const item = task();
  const plan = initial.controller.plan(item, initial.node, initial.workflow, { conversationMode: 'hybrid', relatedToProject: true });
  plan.session.threadId = 'thread-restart'; plan.session.binding = { threadId: 'thread-restart' }; plan.session.state = 'active';
  const saved = structuredClone(initial.engine.state);
  const restarted = fixture({ saved });
  const recovered = await restarted.controller.action({ action: 'recover-agent-session', sessionId: plan.session.id, confirmed: true });
  assert.equal(recovered.recovered, true);
  assert.equal(restarted.engine.state.sessions[0].state, 'idle');
  assert.equal(restarted.engine.state.sessions[0].recoveryRequired, false);
});
