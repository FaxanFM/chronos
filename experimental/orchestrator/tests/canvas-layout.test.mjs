import test from 'node:test';
import assert from 'node:assert/strict';
import { autoLayout, hasWorkflowEdits, isLayoutOnlyChange, snapPosition } from '../frontend/canvas-layout.mjs';

test('snapPosition uses stable grid coordinates', () => {
  assert.deepEqual(snapPosition({ x: 37, y: 49 }), { x: 48, y: 48 });
});

test('autoLayout places a DAG from upstream to downstream', () => {
  const nodes = [{ id: 'a', position: { x: 0, y: 0 } }, { id: 'b', position: { x: 0, y: 0 } }, { id: 'c', position: { x: 0, y: 0 } }];
  const result = autoLayout(nodes, [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }]);
  assert.deepEqual(result.map((node) => node.position), [{ x: 48, y: 48 }, { x: 360, y: 48 }, { x: 648, y: 48 }]);
});

test('layout comparison ignores names, positions and connection anchors', () => {
  const saved = { id: 'w', name: 'Old name', nodes: [{ id: 'a', title: 'Build', position: { x: 0, y: 0 } }], edges: [{ id: 'e', source: 'a', target: 'b' }] };
  const draft = { id: 'w', name: 'New name', nodes: [{ id: 'a', title: 'Build', position: { x: 240, y: 96 } }], edges: [{ id: 'e', source: 'a', target: 'b', sourceHandle: 'out-top', targetHandle: 'in-bottom' }] };
  assert.equal(isLayoutOnlyChange(draft, saved), true);
  assert.equal(isLayoutOnlyChange({ ...draft, nodes: [{ ...draft.nodes[0], title: 'Changed' }] }, saved), false);
});

test('layout comparison tolerates collaborative property ordering and legacy handles', () => {
  const saved = { id: 'w', name: 'Saved', mode: 'collaborative', collaboration: { maxIterations: 2, requestTimeoutMs: 900000 }, nodes: [{ id: 'a', title: 'Build', position: { x: 0, y: 0 } }], edges: [{ id: 'e', source: 'a', target: 'b' }] };
  const draft = { edges: [{ target: 'b', source: 'a', targetHandle: 'in-left', sourceHandle: 'out-right', id: 'e' }], nodes: [{ position: { y: 24, x: 48 }, title: 'Build', id: 'a' }], collaboration: { requestTimeoutMs: 900000, maxIterations: 2 }, mode: 'collaborative', name: 'Renamed', id: 'w' };
  assert.equal(isLayoutOnlyChange(draft, saved), true);
});

test('a name-only rename is clean while other draft edits remain unsaved', () => {
  const saved = { id: 'w', name: 'Renamed', nodes: [{ id: 'a', title: 'Build', instruction: 'Build', position: { x: 100, y: 120 } }], edges: [{ id: 'e', source: 'a', target: 'b' }], mode: 'collaborative', collaboration: { maxIterations: 2, requestTimeoutMs: 900000 } };
  const draft = { mode: 'collaborative', collaboration: { requestTimeoutMs: 900000, maxIterations: 2 }, name: 'Renamed', id: 'w', edges: [{ id: 'e', source: 'a', target: 'b', sourceHandle: 'out-right', targetHandle: 'in-left' }], nodes: saved.nodes };
  assert.equal(hasWorkflowEdits(draft, saved), false);
  assert.equal(hasWorkflowEdits({ ...draft, name: 'Another name' }, saved), true);
  assert.equal(hasWorkflowEdits({ ...draft, nodes: [{ ...draft.nodes[0], position: { x: 200, y: 120 } }] }, saved), true);
  assert.equal(hasWorkflowEdits({ ...draft, nodes: [{ ...draft.nodes[0], instruction: 'Changed' }] }, saved), true);
});
