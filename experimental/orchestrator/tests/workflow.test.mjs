import test from 'node:test';
import assert from 'node:assert/strict';
import { validateWorkflow, parseThreadLink } from '../lib/workflow-contracts.mjs';
import { TEMPLATES } from '../lib/templates.mjs';

test('validates DAG workflows and rejects cycles', () => {
  const workflow = validateWorkflow({ id: 'w', name: 'W', nodes: [{ id: 'a', title: 'A', instruction: 'A' }, { id: 'b', title: 'B', instruction: 'B' }], edges: [{ id: 'ab', source: 'a', target: 'b' }] });
  assert.equal(workflow.nodes[0].policy, 'read-only');
  assert.throws(() => validateWorkflow({ id: 'w', name: 'W', nodes: [{ id: 'a', title: 'A', instruction: 'A' }, { id: 'b', title: 'B', instruction: 'B' }], edges: [{ id: 'ab', source: 'a', target: 'b' }, { id: 'ba', source: 'b', target: 'a' }] }), /workflow_cycle/);
});

test('accepts only strict local Codex thread links', () => {
  assert.equal(parseThreadLink(null), null);
  assert.equal(parseThreadLink('codex://threads/123e4567-e89b-12d3-a456-426614174000'), 'codex://threads/123e4567-e89b-12d3-a456-426614174000');
  assert.throws(() => parseThreadLink('https://chatgpt.com/c/123'), /source_thread_link_invalid/);
});

test('templates are paused workflow definitions', () => {
  assert.ok(TEMPLATES.software_factory.nodes.length > 0);
  assert.equal(TEMPLATES.blank.edges.length, 0);
});

test('keeps explicit connection anchors without changing legacy edge shape', () => {
  const input = { id: 'anchors', name: 'Anchors', nodes: [{ id: 'a', title: 'A', instruction: 'A' }, { id: 'b', title: 'B', instruction: 'B' }], edges: [{ id: 'ab', source: 'a', target: 'b' }] };
  assert.deepEqual(validateWorkflow(input).edges, input.edges);
  const anchored = { ...input.edges[0], sourceHandle: 'out-bottom', targetHandle: 'in-top' };
  assert.deepEqual(validateWorkflow({ ...input, edges: [anchored] }).edges, [anchored]);
  for (const overrides of [{ sourceHandle: 'in-left' }, { targetHandle: 'out-right' }, { sourceHandle: 'arbitrary' }, { targetHandle: {} }]) {
    assert.throws(() => validateWorkflow({ ...input, edges: [{ ...anchored, ...overrides }] }), /workflow_edge_handle_invalid/);
  }
});

test('preserves legacy conversation behavior while validating new agent modes', () => {
  const legacy = validateWorkflow({ id: 'legacy', name: 'Legacy', nodes: [{ id: 'a', title: 'A', instruction: 'A' }], edges: [] });
  assert.equal(Object.hasOwn(legacy, 'conversationDefault'), false);
  const modern = validateWorkflow({ id: 'modern', name: 'Modern', conversationDefault: 'hybrid', nodes: [{ id: 'a', title: 'A', instruction: 'A', conversationMode: 'persistent', agentId: 'writer', complexity: 'high', independentReview: true }], edges: [] });
  assert.equal(modern.conversationDefault, 'hybrid');
  assert.equal(modern.nodes[0].conversationMode, 'persistent');
  assert.equal(modern.nodes[0].agentId, 'writer');
  assert.equal(modern.nodes[0].complexity, 'high');
  assert.equal(modern.nodes[0].independentReview, true);
  for (const field of [{ conversationDefault: 'invalid' }, { nodes: [{ id: 'a', title: 'A', instruction: 'A', conversationMode: 'invalid' }] }, { nodes: [{ id: 'a', title: 'A', instruction: 'A', complexity: 'extreme' }] }]) {
    assert.throws(() => validateWorkflow({ id: 'bad', name: 'Bad', nodes: field.nodes || [{ id: 'a', title: 'A', instruction: 'A' }], edges: [], ...(field.conversationDefault ? { conversationDefault: field.conversationDefault } : {}) }), /conversation_mode_invalid|task_complexity_invalid/);
  }
});
