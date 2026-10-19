import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile, readdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { CodexAdapter } from '../lib/codex-adapter.mjs';
import { Orchestrator } from '../lib/engine.mjs';

const sleep = (ms) => new Promise((accept) => setTimeout(accept, ms));
async function waitFor(engine, predicate, label, timeout = 180000) {
  const until = Date.now() + timeout;
  while (Date.now() < until) {
    await engine.serial;
    const state = engine.snapshot();
    if (predicate(state)) return state;
    if (state.tasks.some((t) => t.state === 'failed' || (t.state === 'blocked' && !t.recoveryUnknown))) {
      throw new Error(label + ':task_failed:' + state.tasks.filter((t) => t.error).map((t) => t.error).join(';'));
    }
    await sleep(150);
  }
  const state = engine.snapshot();
  throw new Error(label + ':timeout:' + JSON.stringify({ mode: state.mode, connected: state.connected, tasks: state.tasks.map((t) => ({ state: t.state, error: t.error })) }));
}

export async function runLiveCheck({ codexPath, outputDirectory, executionOnly = false, codexHome } = {}) {
  assert.ok(codexPath, 'An explicit installed Codex executable is required.');
  const root = resolve(outputDirectory), workspace = join(root, 'workspace');
  await mkdir(workspace, { recursive: true });
  const nonce = randomBytes(6).toString('hex');
  const marker = 'CHRONOS_LIVE_' + nonce;
  await writeFile(join(workspace, 'fixture.txt'), marker + '\n', { flag: 'wx' });
  const statePath = join(root, 'queue.json');
  let adapter, engine;
  const protocol = { methods: {}, stderrSignals: {}, errors: [], commandStarts: 0 };
  const diagnosticSpawn = (...args) => {
    const child = spawn(...args);
    let pending = '';
    child.stdout.on('data', (chunk) => {
      pending += chunk.toString('utf8');
      let end;
      while ((end = pending.indexOf('\n')) >= 0) {
        const line = pending.slice(0, end); pending = pending.slice(end + 1);
        try {
          const message = JSON.parse(line);
          if (typeof message.method === 'string' && /^[a-zA-Z0-9_./-]{1,100}$/.test(message.method)) protocol.methods[message.method] = (protocol.methods[message.method] || 0) + 1;
          if (message.method === 'item/started' && message.params?.item?.type === 'commandExecution') protocol.commandStarts += 1;
          if (message.method === 'error' && protocol.errors.length < 10) {
            const error = message.params?.error;
            const value = String(error?.message || '').toLowerCase();
            const signals = ['stream disconnected', 'connection', 'unauthorized', 'authentication', 'permission denied', 'network', 'timed out', '401', '403', '429', '500', '502', '503'].filter((signal) => value.includes(signal));
            protocol.errors.push({ code: typeof error?.codexErrorInfo === 'string' ? error.codexErrorInfo : Object.keys(error?.codexErrorInfo || {}).slice(0, 3), willRetry: message.params?.willRetry === true, signals });
          }
        } catch {}
      }
      if (pending.length > 1048576) pending = '';
    });
    child.stderr.on('data', (chunk) => {
      const value = chunk.toString('utf8');
      for (const signal of ['unauthorized', 'authentication', 'permission denied', 'connection', 'network', 'reconnecting', 'stream', 'sandbox', 'error']) {
        if (value.toLowerCase().includes(signal)) protocol.stderrSignals[signal] = (protocol.stderrSignals[signal] || 0) + 1;
      }
    });
    return child;
  };
  const make = async () => {
    adapter = new CodexAdapter({ codexPath, cwd: workspace, codexHome, spawnProc: diagnosticSpawn });
    adapter.on('error', (error) => console.log('Owned runtime event:', error.message));
    engine = await new Orchestrator({ adapter, statePath }).initialize();
  };
  const add = async (title, instruction, dependencies = []) => (await engine.action({ action: 'add-task', title, instruction, dependencies })).tasks.at(-1).id;
  const enable = async () => {
    await engine.action({ action: 'connect' });
    await engine.action({ action: 'authorize', confirmed: true });
    await engine.action({ action: 'start' });
  };
  const report = { kind: 'real_local_codex', protocol: 'real_codex_app_server', workspaceScope: 'disposable_fixture_only', scenarios: {}, actualModelTurnsRequested: 0, accountSettingsChanged: false, marketplaceChanged: false };
  const progress = setInterval(() => console.log('Protocol progress:', JSON.stringify(protocol)), 30000); progress.unref();
  try {
    await make();
    const first = await add('Read the local fixture', 'Use the shell to read fixture.txt in the current workspace. Return exactly its contents. Do not inspect any other directory.');
    const dependent = await add('Verify the accepted result', 'Use only the supplied accepted dependency result. Return exactly its marker followed by _DEPENDENT. No tool use is needed.', [first]);
    await enable(); report.actualModelTurnsRequested++;
    console.log('Live execution started in a disposable workspace.');
    let state = await waitFor(engine, (s) => s.tasks.find((t) => t.id === first)?.state === 'review', 'execution');
    assert.ok(state.tasks.find((t) => t.id === first).summary.includes(marker), 'Real result must contain the file marker.');
    assert.equal(state.tasks.find((t) => t.id === dependent).attempts, 0);
    report.effectivePolicy = adapter.effectivePolicy;
    report.scenarios.execution = 'PASS';
    console.log('PASS: real task completion and bounded result.');
    await engine.action({ action: 'accept', taskId: first }); report.actualModelTurnsRequested++;
    state = await waitFor(engine, (s) => s.tasks.find((t) => t.id === dependent)?.state === 'review', 'dependency');
    assert.ok(state.tasks.find((t) => t.id === dependent).summary.includes(marker + '_DEPENDENT'));
    await engine.action({ action: 'accept', taskId: dependent });
    report.scenarios.acceptanceAndDependency = 'PASS';
    console.log('PASS: human acceptance gated the dependent real task.');
    if (!executionOnly) {
      const beforeCancellationCommands = protocol.commandStarts;
      const cancellation = await add('Cancellation check', 'Run a read-only shell command that waits 60 seconds, then reads fixture.txt. Do not finish until the command returns.'); report.actualModelTurnsRequested++;
      await waitFor(engine, (s) => !!s.tasks.find((t) => t.id === cancellation)?.turnId && protocol.commandStarts > beforeCancellationCommands, 'cancel_command_started');
      await engine.action({ action: 'pause' });
      await engine.action({ action: 'cancel', taskId: cancellation });
      state = await waitFor(engine, (s) => s.tasks.find((t) => t.id === cancellation)?.state === 'cancelled', 'cancel_terminal', 45000);
      assert.equal(state.activeCount, 0);
      report.scenarios.cancellationAfterShellStarted = 'PASS';
      console.log('PASS: native terminal interruption observed; slot released afterward.');

      const beforeRecoveryCommands = protocol.commandStarts;
      const recovery = await add('Recovery check', 'Run a read-only shell command that waits 15 seconds, then reads fixture.txt. Return its contents followed by _RECOVERED.');
      await engine.action({ action: 'start' }); report.actualModelTurnsRequested++;
      await waitFor(engine, (s) => !!s.tasks.find((t) => t.id === recovery)?.turnId && protocol.commandStarts > beforeRecoveryCommands, 'recovery_command_started');
      const child = adapter.child;
      assert.ok(child?.pid, 'Only the child started by this adapter may be stopped.');
      const stopped = new Promise((accept) => child.once('close', accept));
      child.kill(); await stopped;
      await waitFor(engine, (s) => !s.connected && s.tasks.find((t) => t.id === recovery)?.recoveryUnknown, 'process_loss');
      await engine.close();
      await make();
      assert.equal(engine.snapshot().mode, 'paused'); assert.equal(engine.snapshot().consent.execution, false);
      await assert.rejects(engine.action({ action: 'retry', taskId: recovery }), /confirm_previous_worker_stopped/);
      await engine.action({ action: 'retry', taskId: recovery, confirmedStopped: true });
      await enable(); report.actualModelTurnsRequested++;
      state = await waitFor(engine, (s) => s.tasks.find((t) => t.id === recovery)?.state === 'review', 'recovered_execution');
      assert.ok(state.tasks.find((t) => t.id === recovery).summary.includes(marker + '_RECOVERED'));
      assert.equal(state.tasks.find((t) => t.id === recovery).attempts, 2);
      await engine.action({ action: 'accept', taskId: recovery });
      report.scenarios.processLossRestartExplicitRetry = 'PASS';
      console.log('PASS: real process loss, paused restore, fresh consent and bounded retry.');
    }
    assert.equal(await readFile(join(workspace, 'fixture.txt'), 'utf8'), marker + '\n');
    assert.deepEqual((await readdir(workspace)).sort(), ['fixture.txt']);
    report.scenarios.workspaceUnchanged = 'PASS'; report.result = 'PASS';
    await engine.close(); engine = null;
    await writeFile(join(root, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report)); return report;
  } catch (error) {
    report.result = 'FAIL'; report.error = error.message; report.diagnostics = protocol;
    await writeFile(join(root, 'report.json'), JSON.stringify(report, null, 2) + '\n');
    throw error;
  } finally { clearInterval(progress); if (engine) await engine.close(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  if (!args.includes('--confirm-live-model-turns')) throw new Error('Live checks spend your Codex allowance. Pass --confirm-live-model-turns explicitly.');
  const get = (name) => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
  await runLiveCheck({ codexPath: get('--codex'), codexHome: get('--codex-home'), outputDirectory: get('--output') || join('dist', 'control-room-live-' + Date.now()), executionOnly: args.includes('--execution-only') });
}
