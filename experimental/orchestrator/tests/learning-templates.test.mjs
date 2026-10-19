import test from 'node:test';
import assert from 'node:assert/strict';
import { TEMPLATES } from '../lib/templates.mjs';
import { validateWorkflow } from '../lib/workflow-contracts.mjs';

const learningIds = ['outcome_learning', 'tool_call_review'];

test('learning templates validate and remain opt-in, read-only, single-attempt workflows', () => {
  for (const id of learningIds) {
    const workflow = validateWorkflow(TEMPLATES[id]);
    assert.equal(workflow.nodes.at(-1).routing, 'approval');
    assert.deepEqual(workflow.nodes.map((node) => node.policy), workflow.nodes.map(() => 'read-only'));
    assert.deepEqual(workflow.nodes.map((node) => node.maxAttempts), workflow.nodes.map(() => 1));
    assert.deepEqual(workflow.nodes.map((node) => node.webSearch), workflow.nodes.map(() => false));
    assert.deepEqual(workflow.nodes.map((node) => node.model), workflow.nodes.map(() => null));
    assert.equal(workflow.edges.length, workflow.nodes.length - 1);
  }
});

test('learning instructions define evidence boundaries and human-gated recommendations', () => {
  for (const id of learningIds) {
    const text = TEMPLATES[id].nodes.map((node) => node.instruction).join(' ');
    assert.match(text, /accepted prior-queue inputs/i);
    assert.match(text, /native verification metadata/i);
    assert.match(text, /artifact paths/i);
    assert.match(text, /human.*accept/i);
    assert.match(text, /baseline/i);
    assert.match(text, /automatically/i);
    assert.match(text, /timings/i);
    assert.match(text, /token/i);
    assert.match(text, /raw secrets/i);
    assert.match(text, /fake model training/i);
    assert.match(text, /permissions/i);
    assert.match(text, /provider/i);
  }
});
