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
