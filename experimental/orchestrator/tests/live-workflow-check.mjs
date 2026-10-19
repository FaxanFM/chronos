import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { resolve, join } from 'node:path';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { WorkspaceManager } from '../lib/workspaces.mjs';
import { Orchestrator } from '../lib/engine.mjs';

const execute = promisify(execFile);
const args = process.argv.slice(2);
if (!args.includes('--confirm-live-model-turns')) throw new Error('explicit_live_model_consent_required');
const value = (name) => args[args.indexOf(name) + 1];
const root = resolve(value('--output'));
await mkdir(root, { recursive: true });
const source = join(root, 'source');
await mkdir(source);
const original = 'export function sum(values) { return values.reduce((total, value) => total + value, 0); }\n';
await writeFile(join(source, 'sum.mjs'), original);
await writeFile(join(source, 'sum.test.mjs'), "import { sum } from './sum.mjs';\nimport assert from 'node:assert/strict';\nimport test from 'node:test';\ntest('adds numbers', () => assert.equal(sum([1, 2, 3]), 6));\n");
await execute('git', ['init', source]);
await execute('git', ['-C', source, 'add', '.']);
await execute('git', ['-C', source, '-c', 'user.name=Chronos Fixture', '-c', 'user.email=fixture@localhost', '-c', 'commit.gpgsign=false', 'commit', '-m', 'Disposable engineering fixture']);
const adapter = new CodexAdapter({ codexPath: value('--codex'), cwd: source });
adapter.on('error', (error) => console.log('Owned runtime:', error.message));
const manager = new WorkspaceManager({ sourceRoot: source, storageRoot: join(root, 'workspaces') });
const engine = await new Orchestrator({ adapter, statePath: join(root, 'queue.json'), verifier: adapter, prepareWorkspace: async (input) => {
  const prepared = await manager.prepare(input);
  if (prepared.workspacePath) await adapter.allowWorkspace(prepared.workspacePath);
  return prepared;
} }).initialize();
const report = { kind: 'real_local_writable_workflow', scope: 'disposable_git_fixture', scenarios: {}, result: 'RUNNING' };
const stage = (id, instruction, extra = {}) => ({ id, title: id, instruction, ...extra });
const until = async (predicate, label) => {
  const deadline = Date.now() + 300000;
  while (Date.now() < deadline) {
    await engine.serial;
    const state = engine.snapshot();
    if (predicate(state)) return state;
    if (state.tasks.some((task) => ['blocked', 'failed'].includes(task.state))) throw new Error(label + ':' + JSON.stringify(state.tasks.map(({ nodeId, state, error }) => ({ nodeId, state, error }))));
    await new Promise((done) => setTimeout(done, 300));
  }
  throw new Error(label + '_timeout');
};
const progress = setInterval(() => console.log('Workflow progress:', JSON.stringify(engine.snapshot().tasks.map(({ nodeId, state, attempts }) => ({ nodeId, state, attempts })))), 30000);
progress.unref();
try {
  await engine.action({ action: 'save-workflow', workflow: {
    id: 'live-engineering', name: 'Live engineering proof',
    nodes: [
      stage('intake', 'Read only sum.mjs and sum.test.mjs. Briefly confirm the requested change: sum must accept only arrays of finite numbers; reject other input with TypeError. Empty arrays return zero. Do not edit files.'),
      stage('build', 'Implement that exact change in sum.mjs. Add regression tests in sum.test.mjs for empty arrays, negative numbers, non-array input, strings, NaN and Infinity. Run node --test sum.test.mjs. Edit only these two files. Report the actual test result.', { policy: 'workspace-write', maxAttempts: 2, verificationCommand: [process.execPath, '--test', 'sum.test.mjs'] }),
      stage('review', 'Read sum.mjs and sum.test.mjs in this workspace and independently run node --test sum.test.mjs. Review finite-number validation and test coverage. Return findings and the actual check result. Do not edit files.', { routing: 'approval' }),
      stage('handoff', 'From the accepted review and workspace files, write a concise release handoff with changed files, verified behavior and rollback instructions. Do not edit, commit, publish or deploy anything.', { routing: 'approval' })
    ], edges: [{ id: 'a-b', source: 'intake', target: 'build' }, { id: 'b-c', source: 'build', target: 'review' }, { id: 'c-d', source: 'review', target: 'handoff' }]
  } });
  await engine.action({ action: 'add-packet', workflowId: 'live-engineering', title: 'Validate numeric array inputs', input: 'Add finite-number array validation to sum with complete focused regression coverage. No dependencies, accounts, publishing or other changes.' });
  await engine.action({ action: 'connect' });
  await engine.action({ action: 'authorize', confirmed: true, allowWrites: true });
  await engine.action({ action: 'start' });
  let state = await until((snapshot) => snapshot.tasks.some((task) => task.nodeId === 'review' && task.state === 'review'), 'review_gate');
  const build = state.tasks.find((task) => task.nodeId === 'build');
  assert.equal(build.state, 'accepted');
  assert.equal(build.verification.exitCode, 0);
  assert.ok(build.workspacePath && build.workspacePath !== source);
  assert.equal(await readFile(join(source, 'sum.mjs'), 'utf8'), original);
  assert.notEqual(await readFile(join(build.workspacePath, 'sum.mjs'), 'utf8'), original);
  assert.equal(state.tasks.some((task) => task.nodeId === 'handoff'), false);
  const review = state.tasks.find((task) => task.nodeId === 'review');
  assert.equal(review.cwd, build.cwd);
  report.scenarios.isolatedWriteNativeVerificationAndIndependentReview = 'PASS';
  report.scenarios.sourceUnchanged = 'PASS';
  report.scenarios.humanGateHeldDownstream = 'PASS';
  await engine.action({ action: 'accept', taskId: review.id });
  state = await until((snapshot) => snapshot.tasks.some((task) => task.nodeId === 'handoff' && task.state === 'review'), 'handoff_gate');
  await engine.action({ action: 'accept', taskId: state.tasks.find((task) => task.nodeId === 'handoff').id });
  state = engine.snapshot();
  assert.equal(state.packets[0].state, 'completed');
  assert.equal(state.activeCount, 0);
  report.scenarios.completedFourStageWorkflow = 'PASS';
  report.actualModelTurns = state.tasks.reduce((count, task) => count + task.attempts, 0);
  report.nativeVerificationExitCode = build.verification.exitCode;
  report.result = 'PASS';
  console.log(JSON.stringify(report));
} catch (error) {
  report.result = 'FAIL'; report.error = error.message;
  throw error;
} finally {
  clearInterval(progress);
  await engine.close();
  await writeFile(join(root, 'report.json'), JSON.stringify(report, null, 2) + '\n');
}
