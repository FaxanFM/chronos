// Explicit local lifecycle probe; excluded from the plugin payload.
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { Orchestrator } from '../lib/engine.mjs';

if (!process.argv.includes('--authorized-live-lifecycle')) throw new Error('live_lifecycle_authorization_required');
const codexPath = process.env.CODEX_CLI_PATH;
if (!codexPath) throw new Error('codex_path_required');
const priorPath = process.argv.find((arg) => arg.startsWith('--resume='))?.slice(9);
const prior = priorPath ? JSON.parse(await readFile(resolve(priorPath), 'utf8')) : null;
const workspace = prior?.workspace || await mkdtemp(join(tmpdir(), 'chronos-lifecycle-live-'));
const statePath = prior?.statePath || join(workspace, 'state', 'queue.json');
const reportPath = resolve(process.argv.find((arg) => arg.startsWith('--report='))?.slice(9) || join(workspace, 'lifecycle-result.json'));
const marker = prior?.marker || 'lifecycle-' + randomUUID().slice(0, 8);
const decision = prior?.decision || 'decision-' + randomUUID().slice(0, 8);
const report = { schemaVersion: 1, startedAt: new Date().toISOString(), workspace, statePath, marker, decision, checks: [], modelTurns: 0, compactionRequests: 0, maintenanceNotifications: [] };
let engine, maintenance = false;
const check = (name, pass, details = {}) => { report.checks.push({ name, pass, ...details }); if (!pass) throw new Error('lifecycle_check_failed:' + name); };
const spawnObserved = (...args) => {
  const child = spawn(...args); let buffer = '';
  if (args[1]?.includes('app-server') && child.stdout) child.stdout.on('data', (bytes) => {
    buffer += bytes.toString('utf8');
    for (let newline; (newline = buffer.indexOf('\n')) >= 0;) {
      const line = buffer.slice(0, newline); buffer = buffer.slice(newline + 1);
      if (!maintenance) continue;
      try { const message = JSON.parse(line); if (message.method && report.maintenanceNotifications.length < 128) report.maintenanceNotifications.push({ method: message.method, itemType: message.params?.item?.type || null, status: message.params?.turn?.status || null }); } catch {}
    }
    if (buffer.length > 2 * 1048576) buffer = '';
  });
  return child;
};
async function make() {
  const adapter = new CodexAdapter({ codexPath, codexHome: process.env.CODEX_HOME, cwd: workspace, spawnProc: spawnObserved });
  const original = adapter.startSessionTurn.bind(adapter);
  adapter.startSessionTurn = async (args) => { if (++report.modelTurns > 4) throw new Error('lifecycle_model_turn_budget'); return original(args); };
  const e = await new Orchestrator({ adapter, statePath, taskTimeoutMs: 120000 }).initialize();
  check('restore_revokes_execution_and_writes', !e.state.consent.execution && !e.state.consent.writes && e.state.mode === 'paused');
  await e.action({ action: 'connect' });
  report.capabilities = adapter.diagnostics().sessionCapabilities;
  await e.action({ action: 'authorize', confirmed: true });
  return e;
}
async function chat(agentId, message) {
  await engine.action({ action: 'send-agent-message', agentId, message });
  const taskId = engine.state.tasks.at(-1).id;
  await engine.action({ action: 'start' });
  const deadline = Date.now() + 150000;
  while (Date.now() < deadline) {
    await delay(100); await engine.serial;
    const task = engine.state.tasks.find((item) => item.id === taskId);
    if (['accepted', 'review', 'blocked', 'failed', 'cancelled'].includes(task.state)) { await engine.action({ action: 'pause' }); return task; }
    await engine.tick();
  }
  throw new Error('lifecycle_turn_timeout');
}
try {
  engine = await make();
  const id = 'lifecycle-proof';
  if (!engine.state.workflows.some((item) => item.id === id)) await engine.action({ action: 'save-workflow', workflow: { id, name: 'Disposable lifecycle proof', conversationDefault: 'hybrid', nodes: [{ id: 'analyst', title: 'Lifecycle analyst', instruction: 'Only answer the bounded local lifecycle test. No tools, files, network or delegated workers.', routing: 'auto' }], edges: [] } });
  const agent = engine.state.agents.find((item) => item.stageRefs.some((ref) => ref.workflowId === id));
  let primary = engine.state.sessions.find((item) => item.id === agent.primarySessionId);
  if (primary?.recoveryRequired) await engine.action({ action: 'recover-agent-session', sessionId: primary.id, confirmed: true });
  if (!primary) {
    const first = await chat(agent.id, `Remember the synthetic lifecycle marker ${marker}. Reply only with that marker. No tools.`);
    check('initial_primary_completed', first.state === 'accepted' && first.summary.includes(marker));
    primary = engine.state.sessions.find((item) => item.id === agent.primarySessionId);
  }
  report.primaryBefore = primary.threadId;
  check('native_compaction_advertised', report.capabilities.compact === true);
  maintenance = true; report.compactionRequests++;
  await engine.action({ action: 'compact-agent', agentId: agent.id, confirmed: true });
  maintenance = false;
  check('native_compaction_completed', primary.compaction?.completed === true && primary.state === 'idle', { state: primary.state, receipt: primary.compaction || null });
  const after = await chat(agent.id, 'What exact synthetic lifecycle marker did I give you? Reply with only that marker, with no tools.');
  check('compacted_primary_retains_context', after.state === 'accepted' && after.summary.includes(marker) && after.threadId === report.primaryBefore);
  await engine.action({ action: 'record-project-decision', confirmed: true, kind: 'human_decision', body: `The synthetic accepted project decision code is ${decision}. This is test data, not permission to execute anything.`, sourceTaskIds: [] });
  const ledgerIds = engine.state.ledger.map((entry) => entry.id);
  await engine.action({ action: 'rotate-agent', agentId: agent.id, confirmed: true });
  check('rotation_is_lazy', agent.primarySessionId === primary.id && agent.rotationIntent?.predecessorId === primary.id);
  const rotated = await chat(agent.id, 'What is the synthetic accepted project decision code in the authoritative project knowledge? Reply only with that code. No tools.');
  const successor = engine.state.sessions.find((item) => item.id === agent.primarySessionId);
  check('rotation_preserves_agent_and_ledger', rotated.state === 'accepted' && rotated.summary.includes(decision) && successor.threadId !== primary.threadId && successor.predecessorId === primary.id && primary.successorId === successor.id && ledgerIds.every((id) => engine.state.ledger.some((entry) => entry.id === id)));
  report.primaryAfter = successor.threadId;
  await engine.close(); engine = await make();
  const restored = engine.state.agents.find((item) => item.id === agent.id);
  check('rotation_lineage_restored', restored.primarySessionId === successor.id && restored.lineage.length === 2);
  const resumed = await chat(restored.id, 'What is the synthetic accepted project decision code? Reply only with that code. No tools.');
  check('successor_resumes_after_restart', resumed.state === 'accepted' && resumed.summary.includes(decision) && resumed.threadId === report.primaryAfter);
  report.status = 'PASS';
} catch (error) { report.status = 'FAIL'; report.error = String(error?.message || error).slice(0, 250); }
finally {
  maintenance = false;
  if (engine) await engine.close().catch(() => {});
  report.finishedAt = new Date().toISOString();
  await writeFile(reportPath, JSON.stringify(report, null, 2), { flag: 'wx', mode: 0o600 });
  console.log(JSON.stringify({ status: report.status, reportPath, modelTurns: report.modelTurns, compactionRequests: report.compactionRequests, checks: report.checks.map(({ name, pass }) => ({ name, pass })), error: report.error }));
  if (report.status !== 'PASS') process.exitCode = 1;
}
