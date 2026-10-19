import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, symlink, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { validateSetupPlan, readSetupPlan } from '../lib/setup-plan.mjs';
import { launch, stop } from '../launcher.mjs';

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), 'chronos-guided-'));
  const workspace = join(root, 'workspace'); await mkdir(workspace);
  await writeFile(join(workspace, 'FRAMEWORK.md'), 'Read-only project framework.\n');
  const plan = { schemaVersion: 1, workspace, goal: 'Prepare a useful research workflow.', references: ['FRAMEWORK.md'], workflow: { id: 'guided-research', name: 'Guided research', nodes: [{ id: 'research', title: 'Read the framework', instruction: 'Produce an evidence-based plan.', routing: 'approval' }], edges: [] }, workItem: { title: 'Review framework', input: 'Use only the selected framework.' }, maxConcurrency: 1 };
  return { root, workspace, plan };
}

test('guided setup records selected context without treating it as execution consent', async () => {
  const { workspace, plan } = await fixture();
  const normalized = await validateSetupPlan(plan, { workspace });
  assert.deepEqual(normalized.references, [{ path: 'FRAMEWORK.md', kind: 'file' }]);
  assert.match(normalized.workflow.nodes[0].instruction, /not permission/);
  assert.match(normalized.workflow.nodes[0].instruction, /FRAMEWORK.md/);
  assert.equal(normalized.workflow.nodes[0].policy, 'read-only');
  await assert.rejects(validateSetupPlan({ ...plan, allowWrites: true }, { workspace }), /setup_plan_invalid/);
  await assert.rejects(validateSetupPlan({ ...plan, workItem: { ...plan.workItem, action: 'start' } }, { workspace }), /setup_plan_invalid/);
  await assert.rejects(validateSetupPlan({ ...plan, maxConcurrency: 17 }, { workspace }), /setup_concurrency_invalid/);
});

test('guided context rejects traversal, links, secrets and another workspace', async () => {
  const { root, workspace, plan } = await fixture();
  for (const reference of ['../FRAMEWORK.md', '.env', '.codex/auth.json', 'a/../../secret', 'C:\\secret.txt']) {
    await assert.rejects(validateSetupPlan({ ...plan, references: [reference] }, { workspace }), /setup_reference_invalid/);
  }
  await mkdir(join(root, 'outside'));
  await symlink(join(root, 'outside'), join(workspace, 'linked'), process.platform === 'win32' ? 'junction' : 'dir');
  await assert.rejects(validateSetupPlan({ ...plan, references: ['linked'] }, { workspace }), /setup_reference_link_rejected/);
  await assert.rejects(validateSetupPlan({ ...plan, workspace: root }, { workspace }), /setup_workspace_mismatch/);
});

test('setup handoff binds exact reviewed JSON bytes', async () => {
  const { root, workspace, plan } = await fixture();
  const file = join(root, 'setup.json'); await writeFile(file, JSON.stringify(plan));
  const loaded = await readSetupPlan(file, { workspace });
  assert.equal(loaded.plan.goal, plan.goal);
  await writeFile(file, JSON.stringify({ ...plan, goal: 'Changed goal' }));
  await assert.rejects(readSetupPlan(file, { workspace, expectedHash: loaded.sha256 }), /setup_plan_changed/);
});

test('launcher imports a guided workflow and work item paused, then reuses without duplicates', async () => {
  const { root, workspace, plan } = await fixture();
  const file = join(root, 'setup.json'); await writeFile(file, JSON.stringify(plan));
  const options = { workspace, stateDir: join(root, 'state'), codex: process.execPath, setupPlan: file };
  try {
    const started = await launch(options);
    assert.equal(started.workflowId, plan.workflow.id);
    assert.equal(new URLSearchParams(new URL(started.url).hash.slice(1)).get('workflow'), plan.workflow.id);
    const token = new URLSearchParams(new URL(started.url).hash.slice(1)).get('token');
    const snapshot = () => fetch(started.origin + '/api/state', { headers: { 'x-chronos-token': token } }).then((response) => response.json());
    const state = await snapshot();
    assert.equal(state.mode, 'paused'); assert.equal(state.connected, false);
    assert.deepEqual(state.consent, { execution: false, writes: false });
    assert.equal(state.packets.length, 1); assert.equal(state.activeCount, 0);
    const again = await launch(options); assert.equal(again.pid, started.pid);
    assert.equal((await snapshot()).packets.length, 1);
  } finally { await stop(options).catch(() => {}); }
});

test('an invalid plan fails before state creation', async () => {
  const { root, workspace, plan } = await fixture();
  const file = join(root, 'setup.json'); await writeFile(file, JSON.stringify({ ...plan, authorize: true }));
  const stateDir = join(root, 'never-created');
  await assert.rejects(launch({ workspace, stateDir, codex: process.execPath, setupPlan: resolve(file) }), /setup_plan_invalid/);
  await assert.rejects(stat(stateDir), /ENOENT/);
});
