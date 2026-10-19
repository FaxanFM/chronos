import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Orchestrator } from '../lib/engine.mjs';

const workflow = (id = 'guided-flow') => ({ id, name: 'Guided flow', nodes: [{ id: 'intake', title: 'Intake', instruction: 'Inspect the request.', policy: 'read-only', slots: 1, routing: 'auto', join: 'all', maxAttempts: 1, position: { x: 0, y: 0 } }], edges: [] });
const adapterFor = (cwd) => ({ cwd, diagnostics: () => ({ connected: false }), on() {}, async close() {}, async connect() {} });
const plan = (workspace, id = 'guided-flow', workItem = { title: 'First request', input: 'Review the selected material.' }) => ({ schemaVersion: 1, workspace, goal: 'Set up a bounded review flow.', references: ['README.md'], workflow: workflow(id), workItem, maxConcurrency: 2 });
async function room() { const root = await mkdtemp(join(tmpdir(), 'chronos-setup-')); await writeFile(join(root, 'README.md'), '# fixture\n'); const statePath = join(root, 'state.json'); const engine = new Orchestrator({ adapter: adapterFor(root), statePath }); await engine.initialize(); return { root, statePath, engine }; }

test('setup applies atomically while paused with consent false and no model calls', async () => {
  const { root, engine } = await room(); try { await engine.action({ action: 'apply-setup-plan', plan: plan(root) }); const s = engine.snapshot(); assert.equal(s.mode, 'paused'); assert.equal(s.consent.execution, false); assert.equal(s.packets.length, 1); assert.equal(s.tasks.length, 1); assert.equal(s.maxConcurrency, 2); } finally { await engine.close(); await rm(root, { recursive: true, force: true }); }
});

test('same setup plan is idempotent and does not duplicate packet or workflow', async () => {
  const { root, engine } = await room(); try { const p = plan(root); await engine.action({ action: 'apply-setup-plan', plan: p }); const first = engine.snapshot(); await engine.action({ action: 'apply-setup-plan', plan: p }); const second = engine.snapshot(); assert.equal(second.workflows.filter((w) => w.id === 'guided-flow').length, 1); assert.equal(second.packets.length, first.packets.length); assert.equal(second.tasks.length, first.tasks.length); } finally { await engine.close(); await rm(root, { recursive: true, force: true }); }
});

test('changed initial work cannot silently replace or duplicate an imported plan', async () => {
  const { root, engine } = await room();
  try {
    const initial = plan(root); await engine.action({ action: 'apply-setup-plan', plan: initial });
    const before = JSON.stringify({ workflows: engine.state.workflows, packets: engine.state.packets, tasks: engine.state.tasks });
    await assert.rejects(engine.action({ action: 'apply-setup-plan', plan: { ...initial, workItem: { title: 'Changed work', input: 'Do something different.' } } }), /setup_workflow_conflict/);
    assert.equal(JSON.stringify({ workflows: engine.state.workflows, packets: engine.state.packets, tasks: engine.state.tasks }), before);
  } finally { await engine.close(); await rm(root, { recursive: true, force: true }); }
});

test('setup respects reserved downstream tasks, not only existing root records', async () => {
  const { root, engine } = await room();
  try {
    for (let index = 0; index < 512; index++) engine.state.packets.push({ id: `reserved-${index}`, workflowId: 'software_factory-default' });
    const before = JSON.stringify({ workflows: engine.state.workflows, packets: engine.state.packets, tasks: engine.state.tasks });
    await assert.rejects(engine.action({ action: 'apply-setup-plan', plan: plan(root) }), /task_capacity/);
    assert.equal(JSON.stringify({ workflows: engine.state.workflows, packets: engine.state.packets, tasks: engine.state.tasks }), before);
  } finally { await engine.close(); await rm(root, { recursive: true, force: true }); }
});

test('invalid plan and conflicting workflow leave state unchanged', async () => {
  const { root, engine } = await room(); try { const before = JSON.stringify(engine.snapshot()); await assert.rejects(() => engine.action({ action: 'apply-setup-plan', plan: { ...plan(root), references: ['missing.md'] } }), /ENOENT|setup/); assert.equal(JSON.stringify(engine.snapshot().workflows), JSON.stringify(JSON.parse(before).workflows)); const same = plan(root, 'software_factory-default'); await assert.rejects(() => engine.action({ action: 'apply-setup-plan', plan: same }), /setup_workflow_conflict/); assert.equal(engine.snapshot().packets.length, 0); } finally { await engine.close(); await rm(root, { recursive: true, force: true }); }
});

test('active room rejects setup before mutation', async () => {
  const { root, engine } = await room(); try { await engine.action({ action: 'start' }).catch(() => {}); engine.state.mode = 'running'; const before = JSON.stringify(engine.snapshot()); await assert.rejects(() => engine.action({ action: 'apply-setup-plan', plan: plan(root) }), /pause_and_finish_running_tasks_first/); assert.equal(JSON.stringify(engine.snapshot().packets), JSON.stringify(JSON.parse(before).packets)); } finally { await engine.close(); await rm(root, { recursive: true, force: true }); }
});

test('workflow capacity failure leaves all arrays unchanged', async () => {
  const { root, engine } = await room(); try {
    for (let index = 0; index < 127; index++) engine.state.workflows.push({ ...workflow(`existing-${index}`), nodes: workflow(`existing-${index}`).nodes });
    const before = JSON.stringify({ workflows: engine.state.workflows, packets: engine.state.packets, tasks: engine.state.tasks });
    await assert.rejects(() => engine.action({ action: 'apply-setup-plan', plan: plan(root, 'capacity-test') }), /workflow_capacity/);
    assert.equal(JSON.stringify({ workflows: engine.state.workflows, packets: engine.state.packets, tasks: engine.state.tasks }), before);
  } finally { await engine.close(); await rm(root, { recursive: true, force: true }); }
});

test('setup persists and restores workflow, packet and concurrency', async () => {
  const { root, statePath, engine } = await room(); await engine.action({ action: 'apply-setup-plan', plan: plan(root) }); await engine.close(); const second = new Orchestrator({ adapter: adapterFor(root), statePath }); try { await second.initialize(); const s = second.snapshot(); assert.equal(s.workflows.some((w) => w.id === 'guided-flow'), true); assert.equal(s.packets.length, 1); assert.equal(s.maxConcurrency, 2); } finally { await second.close(); await rm(root, { recursive: true, force: true }); }
});
