import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve, relative, isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { Orchestrator } from '../lib/engine.mjs';

const args = process.argv.slice(2);
if (!args.includes('--confirm-live-model-turns')) throw new Error('explicit_live_model_consent_required');
const option = (key) => args.includes(key) ? args[args.indexOf(key) + 1] : null;
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(option('--output') || join(root, '.local', `collaboration-${Date.now()}`));
const inside = relative(join(root, '.local'), output);
if (!inside || inside.startsWith('..') || isAbsolute(inside)) throw new Error('live_evidence_path_must_be_owned_local_subdirectory');
await mkdir(output, { recursive: true });
const workspace = join(root, 'tests', 'fixtures', 'collaboration');
const adapter = new CodexAdapter({ codexPath: option('--codex') || process.env.CODEX_CLI_PATH, cwd: workspace });
const engine = await new Orchestrator({ adapter, statePath: join(output, 'queue.json'), taskTimeoutMs: 180000 }).initialize();
const report = { kind: 'real_native_read_only_collaboration', fixture: 'explicit_synthetic_fault_injection', result: 'RUNNING', observed: {} };
let maximumActive = 0;
const interval = setInterval(() => { maximumActive = Math.max(maximumActive, engine.snapshot().activeCount); }, 50);
interval.unref();
const native = `Use a bounded read-only native command with the installed Node executable ${JSON.stringify(process.execPath)} to read rate.json and check the arithmetic. Do not edit, access accounts, use the network or start another worker.`;
const node = (id, instruction, routing = 'auto') => ({ id, title: id, instruction, routing, policy: 'read-only' });
try {
  await engine.action({ action: 'save-workflow', workflow: {
    id: 'native-collaboration-proof', name: 'Native clarification proof', mode: 'collaborative', collaboration: { maxIterations: 1, requestTimeoutMs: 300000 },
    nodes: [
      node('analyst', `${native} On the initial revision only, read the supplied legacyRateEventsPerSecond and report it as an UNVERIFIED legacy estimate. Do not compute or substitute a corrected rate in this initial handoff: this is an explicit fault-injection test of downstream verification. If a Pending request is present, compute sampleEvents / durationSeconds and answer the exact pending request with the corrected rate and units.`),
      node('reviewer', `${native} Independently verify the analyst's rate against sampleEvents / durationSeconds. If the accepted input is the unverified legacy estimate, send exactly one clarification to analyst, referencing its exact current artifact ID. Ask for the corrected numerical rate and units. If the accepted input correctly reports 2 events per second, return a concise verified result with message:null. Do not request another correction when it is correct.`, 'approval'),
      node('independent', `${native} Independently report only the fixture's sampleEvents and durationSeconds, and state that it is synthetic. This branch must not depend on the rate calculation.`)
    ], edges: [{ id: 'analysis-review', source: 'analyst', target: 'reviewer' }]
  } });
  await engine.action({ action: 'add-packet', workflowId: 'native-collaboration-proof', title: 'Verify a legacy event-rate estimate', input: 'Use only the synthetic rate.json. Preserve independent accepted work; do not perform external effects.' });
  await engine.action({ action: 'connect' }); await engine.action({ action: 'authorize', confirmed: true });
  await engine.action({ action: 'configure', maxConcurrency: 2 }); await engine.action({ action: 'start' });
  const deadline = Date.now() + 540000;
  let final;
  while (Date.now() < deadline) {
    await engine.serial;
    const snapshot = engine.snapshot();
    if (snapshot.tasks.some((task) => !task.superseded && ['failed', 'blocked'].includes(task.state))) throw new Error(`native_collaboration_blocked:${snapshot.tasks.filter((task) => !task.superseded).map((task) => `${task.nodeId}:${task.state}:${task.blockReason || task.error}`).join(',')}`);
    const review = snapshot.tasks.find((task) => task.nodeId === 'reviewer' && !task.superseded && task.stageRevision === 2 && task.state === 'review');
    if (review) { final = snapshot; break; }
    await new Promise((done) => setTimeout(done, 250));
  }
  if (!final) throw new Error('native_collaboration_deadline');
  await engine.action({ action: 'pause' });
  const packet = final.packets[0], state = packet.collaboration;
  assert.equal(state.iteration, 1); assert.equal(maximumActive, 2);
  assert.equal(state.messages.filter((message) => message.kind === 'clarification').length, 1);
  assert.ok(state.messages.some((message) => ['response', 'resolution'].includes(message.kind) && message.fromStageId === 'analyst'));
  assert.ok(state.messages.every((message) => message.status === 'resolved'));
  assert.equal(final.tasks.filter((task) => task.nodeId === 'independent').length, 1);
  assert.equal(final.tasks.find((task) => task.nodeId === 'independent').state, 'accepted');
  assert.ok(final.tasks.filter((task) => task.nodeId === 'analyst').some((task) => task.superseded && task.state === 'accepted'));
  assert.equal(packet.outputs.reviewer, undefined);
  assert.equal(final.tasks.reduce((count, task) => count + task.attempts, 0), 5);
  assert.ok(final.tasks.every((task) => (task.executionEvidence?.counts?.commandExecution?.completed || 0) >= 1));
  engine.collaboration.validate();
  report.observed = { modelTurns: 5, maximumManagedActive: maximumActive, feedbackIterations: state.iteration, typedMessages: state.messages.map(({ kind, fromStageId, toStageId, status }) => ({ kind, fromStageId, toStageId, status })), independentBranchExecutions: 1, acceptedTextRevisions: state.artifacts.length, nativeCommandsCompleted: final.tasks.reduce((sum, task) => sum + task.executionEvidence.counts.commandExecution.completed, 0), reviewerState: 'review', humanGateAccepted: false, installedPluginChanged: false, desktopSessionsControlled: false, monetaryCost: 'unavailable', tokenUsage: 'unavailable' };
  report.result = 'PASS';
} catch (error) { report.result = 'FAIL'; report.error = String(error.message).slice(0, 1000); process.exitCode = 1; }
finally { clearInterval(interval); await engine.close(); await writeFile(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n'); console.log(JSON.stringify(report)); }
