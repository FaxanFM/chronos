import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { dirname, resolve, relative, isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { Orchestrator } from '../lib/engine.mjs';
import { WorkspaceManager, executeWorkspaceGit } from '../lib/workspaces.mjs';

const args = process.argv.slice(2);
if (!args.includes('--confirm-live-model-turns')) throw new Error('explicit_live_model_consent_required');
const option = (name) => args.includes(name) ? args[args.indexOf(name) + 1] : null;
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(option('--output') || join(root, '.local', `write-collaboration-${Date.now()}`));
const part = relative(join(root, '.local'), output);
if (!part || part.startsWith('..') || isAbsolute(part)) throw new Error('live_evidence_path_must_be_owned_local_subdirectory');
await mkdir(output, { recursive: true });
const source = join(output, 'fixture');
await mkdir(source);
const git = option('--git') || 'git';
const ignore = join(output, 'empty-ignore'); await writeFile(ignore, '');
const execute = (file, argv, settings) => executeWorkspaceGit(file, ['-c', `core.excludesFile=${ignore}`, ...argv], settings);
const sourceGit = (argv) => execute(git, ['-C', source, ...argv], { windowsHide: true });
await sourceGit(['init']);
await sourceGit(['config', 'user.name', 'Chronos local test']);
await sourceGit(['config', 'user.email', 'fixture@example.invalid']);
const initial = 'export function sum(values) { throw new Error("Not implemented"); }\n';
await writeFile(join(source, 'sum.mjs'), initial);
await writeFile(join(source, 'smoke-check.mjs'), 'import assert from "node:assert/strict"; import {sum} from "./sum.mjs"; assert.equal(sum([1,2,3]),6); console.log("positive smoke PASS");\n');
await writeFile(join(source, 'negative-check.mjs'), 'import assert from "node:assert/strict"; import {sum} from "./sum.mjs"; assert.equal(sum([-3,1]),-2); assert.equal(sum([]),0); assert.throws(()=>sum([NaN])); console.log("signed arithmetic PASS");\n');
await writeFile(join(source, 'brief.md'), 'Synthetic arithmetic fixture. No account, network, installation or deployment actions.\n');
await sourceGit(['add', '.']);
await sourceGit(['-c', 'commit.gpgsign=false', 'commit', '-m', 'Synthetic local checkpoint fixture']);
const manager = () => new WorkspaceManager({ sourceRoot: source, storageRoot: join(output, 'workspaces'), gitExecutable: git, execute });
let workspaces = manager(), adapter, engine;
const nativeResults = [];
const makeEngine = async () => {
  adapter = new CodexAdapter({ codexPath: option('--codex') || process.env.CODEX_CLI_PATH, cwd: source });
  adapter.on('error', (error) => { if (error.message !== 'adapter_closed') { const diagnostic = adapter.diagnostics(); console.log(JSON.stringify({ nativeRuntimeError: String(error.message || error).slice(0, 200), lastMethod: diagnostic.lastMethod, lastErrorCode: diagnostic.lastErrorCode })); } });
  adapter.on('task-event', (event) => { if (event.kind === 'completed' && nativeResults.length < 12) nativeResults.push({ taskId: event.taskId, result: event.summary?.slice(0, 4096) }); });
  engine = await new Orchestrator({ adapter, statePath: join(output, 'queue.json'), checkpoints: workspaces, taskTimeoutMs: 180000,
    prepareWorkspace: async (input) => { const value = await workspaces.prepare(input); if (value.workspacePath) await adapter.allowWorkspace(value.workspacePath); return value; }
  }).initialize();
};
const wait = (ms) => new Promise((done) => setTimeout(done, ms));
const current = (stage) => engine.state.tasks.findLast((task) => task.nodeId === stage && !task.superseded);
async function until(predicate, label, timeout = 360000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    await engine.serial;
    if (predicate()) return;
    const blocked = engine.state.tasks.find((task) => !task.superseded && ['failed', 'blocked'].includes(task.state));
    if (blocked) throw new Error(`${label}:${blocked.nodeId}:${blocked.state}:${blocked.error || blocked.blockReason}`);
    await wait(100);
  }
  throw new Error(`live_write_timeout:${label}`);
}
const report = { kind: 'real_native_collaborative_write_recovery', fixture: 'explicit_synthetic_fault_injection', result: 'RUNNING', observed: {} };
const node = (id, instruction, policy, routing = 'auto', verificationCommand = []) => ({ id, title: id, instruction, policy, routing, verificationCommand });
const scope = `Use only this synthetic local workspace. No network, accounts, installs, publishing or extra workers. For native checks use the installed Node executable ${JSON.stringify(process.execPath)}. Do not modify the check scripts. `;
try {
  await makeEngine();
  await engine.action({ action: 'save-workflow', workflow: {
    id: 'native-write-checkpoint-proof', name: 'Build, reject, correct and recover', mode: 'collaborative', collaboration: { maxIterations: 1, requestTimeoutMs: 900000 },
    nodes: [
      node('build', scope + 'Implement sum.mjs and run smoke-check.mjs. INITIAL revision only: this is a deliberate faulty-handoff test. Implement sum as values.reduce((total,value)=>total+Math.abs(value),0). Do not fix negatives yet. Return a summary explicitly labeling this initial implementation as fault-injected. When a Pending request exists, instead implement correct signed summation with validation: array input, every value finite number, empty array returns zero. Run both check scripts. Respond to the exact pending request and its artifact IDs with the corrected result.', 'workspace-write', 'auto', [process.execPath, 'smoke-check.mjs']),
      node('review', scope + 'Run negative-check.mjs using a native command. If it fails, send exactly one typed rejection to build, using the exact current build artifact ID, explaining the negative/invalid-value defect. If it passes, return message:null and the observed native check result. Do not reject a corrected passing implementation and do not approve the human gate.', 'read-only', 'approval'),
      node('independent', scope + 'Use a native read-only command to inspect brief.md. Report that it is a synthetic local fixture, without judging the arithmetic.', 'read-only')
    ], edges: [{ id: 'build-review', source: 'build', target: 'review' }]
  } });
  await engine.action({ action: 'add-packet', workflowId: 'native-write-checkpoint-proof', title: 'Signed arithmetic test', input: 'Exercise a deliberate faulty build, typed review rejection, bounded correction, and coordinator restart. No external effects.' });
  await engine.action({ action: 'connect' });
  await engine.action({ action: 'authorize', confirmed: true, allowWrites: true });
  await engine.action({ action: 'configure', maxConcurrency: 2 });
  await engine.action({ action: 'start' });
  await until(() => current('build')?.stageRevision === 2 && current('build').state === 'running' && current('build').turnId, 'correction_started');
  await engine.action({ action: 'pause' });
  const interrupted = structuredClone(current('build'));
  const original = structuredClone(engine.state.tasks.find((task) => task.nodeId === 'build' && task.stageRevision === 1));
  assert.equal(original.state, 'accepted');
  assert.equal(original.verification.exitCode, 0);
  const oldManifest = await workspaces.verifyCheckpoint(original.fileCheckpoint, { ownerId: `task:${original.id}` });
  const seedManifest = await workspaces.verifyCheckpoint(engine.state.packets[0].fileBaseCheckpoint);
  const assertChecksUnmodified = (manifest) => {
    for (const name of ['smoke-check.mjs', 'negative-check.mjs']) assert.equal(manifest.files.find((file) => file.path === name)?.sha256, seedManifest.files.find((file) => file.path === name)?.sha256, `Native check script changed: ${name}`);
  };
  assertChecksUnmodified(oldManifest);
  const oldFile = oldManifest.files.find((file) => file.path === 'sum.mjs');
  const badBytes = await workspaces.checkpointStore.readBlob(oldFile);
  assert.match(badBytes.toString(), /Math\.abs/);
  assert.notEqual(interrupted.cwd, original.cwd);
  console.log(JSON.stringify({ milestone: 'build_rejected_correction_started', revision: 2, initialFileCheckpoint: original.fileCheckpoint.id }));

  // Close only this test's native runtime. The saved active task must require explicit recovery.
  const nativeProcess = adapter.child;
  await engine.close();
  assert.equal(adapter.diagnostics().shutdownUnverified, false);
  assert.ok(!nativeProcess || nativeProcess.exitCode !== null || nativeProcess.signalCode !== null);
  workspaces = manager(); await makeEngine();
  assert.equal(engine.state.mode, 'paused'); assert.equal(engine.state.connected, false);
  assert.deepEqual(engine.state.consent, { execution: false, writes: false });
  const recovered = current('build');
  assert.equal(recovered.recoveryUnknown, true);
  await assert.rejects(engine.action({ action: 'retry', taskId: recovered.id }), /confirm_previous_worker_stopped/);
  await engine.action({ action: 'retry', taskId: recovered.id, confirmedStopped: true });
  assert.equal(adapter.diagnostics().activeTurns, 0);
  await engine.action({ action: 'connect' });
  await engine.action({ action: 'authorize', confirmed: true, allowWrites: true });
  await engine.action({ action: 'start' });
  await until(() => current('review')?.stageRevision === 2 && current('review').state === 'review', 'corrected_review');
  await engine.action({ action: 'pause' });
  const final = engine.snapshot(), fixed = current('build'), review = current('review');
  const packet = final.packets[0], history = packet.collaboration;
  assert.equal(fixed.state, 'accepted'); assert.equal(fixed.attempts, 2);
  assert.notEqual(fixed.cwd, interrupted.cwd); assert.notEqual(fixed.fileCheckpoint.id, original.fileCheckpoint.id);
  assert.equal(fixed.verification.exitCode, 0);
  const finalManifest = await workspaces.verifyCheckpoint(fixed.fileCheckpoint, { ownerId: `task:${fixed.id}` });
  assertChecksUnmodified(finalManifest);
  const finalBytes = await workspaces.checkpointStore.readBlob(finalManifest.files.find((file) => file.path === 'sum.mjs'));
  assert.notEqual(finalBytes.toString(), badBytes.toString());
  assert.deepEqual(await workspaces.checkpointStore.readBlob(oldFile), badBytes);
  assert.equal(await readFile(join(source, 'sum.mjs'), 'utf8'), initial);
  assert.equal(final.tasks.filter((task) => task.nodeId === 'independent').length, 1);
  assert.equal(final.tasks.find((task) => task.nodeId === 'independent').attempts, 1);
  assert.equal(final.tasks.find((task) => task.nodeId === 'independent').state, 'accepted');
  assert.equal(history.iteration, 1);
  assert.equal(history.messages.filter((message) => message.kind === 'rejection').length, 1);
  assert.ok(history.messages.some((message) => ['response', 'resolution'].includes(message.kind) && message.fromStageId === 'build'));
  assert.ok(history.messages.every((message) => message.status === 'resolved'));
  assert.equal(packet.outputs.review, undefined);
  assert.ok(review.fileCheckpoint);
  assert.ok(final.tasks.filter((task) => task.state === 'accepted' || task.state === 'review').every((task) => (task.executionEvidence?.counts?.commandExecution?.completed || 0) >= 1));
  engine.collaboration.validate(); await engine.validateFileState();
  report.observed = { modelTurnsDispatched: final.tasks.reduce((sum, task) => sum + task.attempts, 0), feedbackIterations: 1, rejectionCount: 1, correctionRestarted: true, unknownWorkerRequiresConfirmation: true, runtimeShutdownVerified: true, executionAndWriteConsentReset: true, freshRecoveryWorkspace: true, originalSourceUnchanged: true, priorCheckpointPreserved: true, independentBranchExecutions: 1, nativeSmokeVerification: fixed.verification.exitCode, reviewNativeCommands: review.executionEvidence.counts.commandExecution.completed, reviewerState: review.state, humanGateAccepted: false, acceptedFileRevisions: history.artifacts.filter((artifact) => artifact.fileCheckpoint).length, installedPluginChanged: false, desktopSessionsControlled: false, tokenUsage: 'unavailable', monetaryCost: 'unavailable' };
  report.result = 'PASS';
} catch (error) { report.result = 'FAIL'; report.error = String(error.stack || error).slice(0, 2000); process.exitCode = 1; }
finally {
  if (engine) await engine.close().catch(() => {});
  await writeFile(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  await writeFile(join(output, 'native-results.json'), JSON.stringify(nativeResults, null, 2) + '\n');
  console.log(JSON.stringify(report));
}
