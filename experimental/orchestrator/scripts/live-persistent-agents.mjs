// Explicitly authorized integration probe. Never included in the plugin payload.
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { Orchestrator } from '../lib/engine.mjs';

if (!process.argv.includes('--authorized-six-turns')) throw new Error('explicit_live_test_authorization_required');
const codexPath = process.env.CODEX_CLI_PATH;
if (!codexPath) throw new Error('codex_path_required');
const workspace = await mkdtemp(join(tmpdir(), 'chronos-persistent-live-'));
const statePath = join(workspace, 'state', 'queue.json');
const reportPath = resolve(process.argv.find((value) => value.startsWith('--report='))?.slice(9) || join(workspace, 'result.json'));
const marker = 'chronos-' + randomUUID().slice(0, 8);
let turns = 0, engine;
const report = { schemaVersion: 1, startedAt: new Date().toISOString(), workspace, statePath, checks: [], actualModelTurns: 0 };
const check = (name, pass, evidence = {}) => { report.checks.push({ name, pass, ...evidence }); if (!pass) throw new Error('live_assertion_failed:' + name); };
const make = async () => {
  const adapter = new CodexAdapter({ codexPath, cwd: workspace });
  const original = adapter.startSessionTurn.bind(adapter);
  adapter.startSessionTurn = async (args) => { if (++turns > 6) throw new Error('live_turn_budget_exceeded'); report.actualModelTurns = turns; return original(args); };
  const e = await new Orchestrator({ adapter, statePath, taskTimeoutMs: 120000 }).initialize();
  check('restored_queue_has_no_execution_or_write_consent', !e.state.consent.execution && !e.state.consent.writes);
  await e.action({ action: 'connect' });
  report.capabilities = adapter.diagnostics().sessionCapabilities;
  check('installed_schema_supports_managed_sessions', report.capabilities.prepare && report.capabilities.resume && report.capabilities.turn);
  await e.action({ action: 'authorize', confirmed: true });
  return e;
};
const wait = async (taskId, desired = ['accepted', 'review', 'blocked', 'failed', 'cancelled']) => {
  const deadline = Date.now() + 150000;
  while (Date.now() < deadline) {
    await delay(200); await engine.serial;
    const task = engine.state.tasks.find((item) => item.id === taskId);
    if (task && desired.includes(task.state)) return task;
    await engine.tick();
  }
  throw new Error('live_task_timeout');
};
const chat = async (agentId, message) => {
  await engine.action({ action: 'send-agent-message', agentId, message });
  const taskId = engine.state.tasks.at(-1).id;
  if (engine.state.mode !== 'running') await engine.action({ action: 'start' });
  return wait(taskId);
};
try {
  engine = await make();
  const workflow = { id: 'continuity', name: 'Local continuity proof', conversationDefault: 'hybrid', nodes: [{ id: 'analyst', title: 'Local test analyst', instruction: 'Answer only the bounded local integration test. Do not inspect files, use the network, write or create workers.', routing: 'auto' }], edges: [] };
  await engine.action({ action: 'save-workflow', workflow });
  const agent = engine.state.agents.find((item) => item.stageRefs.some((ref) => ref.workflowId === workflow.id));
  const first = await chat(agent.id, `Remember this exact private test marker in this conversation: ${marker}. Reply with only that marker. No tools.`);
  check('first_primary_turn', first.state === 'accepted' && first.summary.includes(marker));
  const second = await chat(agent.id, 'What exact marker did I ask you to remember in this conversation? Reply with only that marker. No tools.');
  check('same_primary_native_context', second.summary.includes(marker) && second.threadId === first.threadId, { sameThread: second.threadId === first.threadId });
  await engine.action({ action: 'pause' });
  await engine.action({ action: 'save-workflow', workflow: { ...workflow, id: 'one-off', name: 'Clarification proof', conversationDefault: 'one-off', nodes: [{ ...workflow.nodes[0], instruction: 'On the first turn return the required structured needs-input outcome with question body "Which colour?" and targetAgentId null. After an answer to that exact question, return completed with the chosen colour in summary. Do not use tools.' }] } });
  await engine.action({ action: 'add-packet', workflowId: 'one-off', title: 'Clarification', input: 'Choose the colour after asking.', relatedToProject: false });
  const questionTaskId = engine.state.tasks.at(-1).id;
  await engine.action({ action: 'start' });
  const waiting = await wait(questionTaskId);
  check('question_not_accepted', waiting.state === 'blocked' && waiting.blockReason === 'needs_input' && !engine.state.packets.at(-1).outputs.analyst);
  const questionThread = waiting.threadId;
  const question = engine.state.agentQuestions.find((item) => item.taskId === questionTaskId && item.state === 'waiting');
  await engine.action({ action: 'answer-agent-question', questionId: question.id, message: 'Cobalt.' });
  const answered = await wait(questionTaskId);
  check('clarification_continues_same_session', answered.state === 'accepted' && answered.summary.toLowerCase().includes('cobalt') && answered.threadId === questionThread && answered.attempts === 1);
  await engine.action({ action: 'pause' });
  await engine.action({ action: 'send-agent-message', agentId: agent.id, message: 'For a cancellation integration test, run one read-only PowerShell command: Start-Sleep -Seconds 25. Then reply done. Do not read or write files.' });
  const cancelId = engine.state.tasks.at(-1).id;
  await engine.action({ action: 'start' });
  const cancelDeadline = Date.now() + 30000;
  while (!engine.state.tasks.find((item) => item.id === cancelId).turnId && Date.now() < cancelDeadline) { await delay(100); await engine.serial; }
  await engine.action({ action: 'cancel', taskId: cancelId });
  const cancelled = await wait(cancelId);
  check('cancellation_observed_terminal', cancelled.state === 'cancelled' && engine.state.sessions.find((item) => item.id === cancelled.sessionId).state === 'idle');
  await engine.close();
  engine = await make();
  check('restart_remains_paused_after_explicit_reauthorization', engine.state.mode === 'paused');
  const final = await chat(agent.id, 'After reopening this same managed conversation, what exact marker did I ask you to remember earlier? Reply with only that marker. No tools.');
  check('restart_resumes_same_primary', final.state === 'accepted' && final.summary.includes(marker) && final.threadId === first.threadId);
  await engine.action({ action: 'pause' });
  report.status = 'PASS';
} catch (error) {
  report.status = 'FAIL'; report.error = String(error?.message || error).slice(0, 300);
} finally {
  if (engine) await engine.close().catch(() => {});
  report.finishedAt = new Date().toISOString();
  await writeFile(reportPath, JSON.stringify(report, null, 2), { flag: 'wx', mode: 0o600 });
  process.stdout.write(JSON.stringify({ status: report.status, turns, reportPath, checks: report.checks, error: report.error }) + '\n');
  if (report.status !== 'PASS') process.exitCode = 1;
}
