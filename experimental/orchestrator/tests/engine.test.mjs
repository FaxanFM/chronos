import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Orchestrator } from '../lib/engine.mjs';

class Adapter extends EventEmitter {
  constructor() { super(); this.starts = []; this.interrupts = []; this.closes = 0; }
  async connect() {}
  async startTask(task) { this.starts.push(task); return { threadId: 'thread-' + task.id, turnId: 'turn-' + task.id }; }
  async interruptTask(task) { this.interrupts.push(task); }
  async close() { this.closes++; }
  finish(index = 0, kind = 'completed', summary = 'Verified report') { const task = this.starts[index]; this.emit('task-event', { taskId: task.id, turnId: 'turn-' + task.id, kind, summary }); }
}
const flush = async (engine) => { for (let i = 0; i < 4; i++) { await new Promise(setImmediate); await engine.serial; } };
const add = async (e, title, dependencies = []) => (await e.action({ action: 'add-task', title, instruction: 'Read and report on ' + title, dependencies })).tasks.at(-1).id;
const start = async (e) => { await e.action({ action: 'connect' }); await e.action({ action: 'authorize', confirmed: true }); await e.action({ action: 'start' }); await flush(e); };

test('nothing executes without explicit consent, connection and start', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  await add(e, 'One'); await e.tick(); assert.equal(a.starts.length, 0);
  await assert.rejects(e.action({ action: 'start' }), /explicit_execution_consent/);
  await assert.rejects(e.action({ action: 'authorize', confirmed: false }), /explicit_execution_consent/);
  await e.action({ action: 'authorize', confirmed: true });
  await assert.rejects(e.action({ action: 'start' }), /connect_runtime_first/);
  assert.equal(a.starts.length, 0); await e.close();
});

test('dependencies wait for human acceptance, not model completion', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  const one = await add(e, 'Research'), two = await add(e, 'Verify', [one]);
  await start(e); assert.equal(a.starts.length, 1);
  a.finish(); await flush(e); assert.equal(e.snapshot().tasks[0].state, 'review'); assert.equal(a.starts.length, 1);
  await e.action({ action: 'accept', taskId: one }); await flush(e); assert.equal(a.starts.length, 2);
  assert.match(a.starts[1].instruction, /Verified report/); assert.equal(e.snapshot().tasks.find((t) => t.id === two).state, 'running');
  await e.close();
});

test('concurrency is bounded and pause prevents new dispatch', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  await e.action({ action: 'configure', maxConcurrency: 2 });
  for (const title of ['A', 'B', 'C']) await add(e, title);
  await start(e); assert.equal(a.starts.length, 2);
  await assert.rejects(e.action({ action: 'configure', maxConcurrency: 1 }), /pause_and_finish/);
  await e.action({ action: 'pause' }); a.finish(); await flush(e); assert.equal(a.starts.length, 2);
  await e.action({ action: 'start' }); await flush(e); assert.equal(a.starts.length, 3);
  await e.close();
});

test('cancel acknowledgement cannot free a slot; terminal event does', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  const id = await add(e, 'A'); await add(e, 'B'); await start(e);
  await e.action({ action: 'cancel', taskId: id }); await flush(e);
  assert.equal(a.interrupts.length, 1); assert.equal(a.starts.length, 1); assert.equal(e.snapshot().activeCount, 1);
  a.finish(0, 'interrupted'); await flush(e); assert.equal(a.starts.length, 2); assert.equal(e.snapshot().tasks[0].state, 'cancelled');
  await e.close();
});

test('approval requests stop dispatch and never auto-approve', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  await add(e, 'A'); await add(e, 'B'); await start(e);
  a.finish(0, 'approval-required'); await flush(e); assert.equal(e.snapshot().mode, 'paused'); assert.equal(a.interrupts.length, 1);
  a.finish(0, 'interrupted'); await flush(e); assert.equal(e.snapshot().tasks[0].state, 'blocked'); assert.equal(a.starts.length, 1);
  await e.close();
});

test('unobserved interruption closes only owned runtime after bounded wait', async () => {
  let clock = 1000;
  const a = new Adapter(), e = new Orchestrator({ adapter: a, now: () => clock });
  const id = await add(e, 'A'); await start(e); await e.action({ action: 'cancel', taskId: id });
  clock += 15001; await e.tick();
  assert.equal(a.closes, 1); assert.equal(e.snapshot().connected, false); assert.equal(e.snapshot().tasks[0].recoveryUnknown, true);
  await assert.rejects(e.action({ action: 'retry', taskId: id }), /confirm_previous_worker_stopped/); await e.close();
});

test('failure blocks dependencies and retry needs a new explicit action', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  const id = await add(e, 'A'); await add(e, 'B', [id]); await start(e);
  a.finish(0, 'failed'); await flush(e); assert.equal(a.starts.length, 1); assert.equal(e.snapshot().tasks[1].state, 'blocked');
  await e.action({ action: 'retry', taskId: id }); await flush(e); assert.equal(a.starts.length, 2);
  a.finish(1); await flush(e); await e.action({ action: 'accept', taskId: id }); await flush(e);
  assert.equal(a.starts.length, 3); await e.close();
});

test('stale events cannot settle a later attempt', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a }); const id = await add(e, 'A'); await start(e);
  a.finish(0, 'failed'); await flush(e); await e.action({ action: 'retry', taskId: id }); await flush(e);
  a.finish(0, 'completed'); await flush(e); assert.equal(e.snapshot().tasks[0].state, 'running');
  a.finish(1); await flush(e); assert.equal(e.snapshot().tasks[0].state, 'review'); await e.close();
});

test('three attempts maximum; dependency targets and concurrency validated', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  await assert.rejects(add(e, 'Invalid', ['missing']), /dependencies_invalid/);
  await assert.rejects(e.action({ action: 'configure', maxConcurrency: 3 }), /concurrency_must/);
  const id = await add(e, 'A'); await start(e);
  for (let i = 0; i < 3; i++) { a.finish(i, 'failed'); await flush(e); if (i < 2) { await e.action({ action: 'start' }); await e.action({ action: 'retry', taskId: id }); await flush(e); } }
  await assert.rejects(e.action({ action: 'retry', taskId: id }), /attempt_limit/); assert.equal(a.starts.length, 3); await e.close();
});

test('restart restores queue paused without execution consent', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-engine-')), path = join(dir, 'queue.json');
  try {
    const a = new Adapter(), e = await new Orchestrator({ adapter: a, statePath: path }).initialize();
    await add(e, 'A'); await start(e); await e.close();
    const fresh = await new Orchestrator({ adapter: new Adapter(), statePath: path }).initialize();
    assert.equal(fresh.snapshot().mode, 'paused'); assert.equal(fresh.snapshot().consent.execution, false);
    assert.equal(fresh.snapshot().tasks[0].state, 'blocked'); assert.equal(fresh.snapshot().tasks[0].recoveryUnknown, true); await fresh.close();
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('one state owner and invalid persisted graph fail closed', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-engine-')), path = join(dir, 'queue.json');
  try {
    const e = await new Orchestrator({ adapter: new Adapter(), statePath: path }).initialize();
    await assert.rejects(new Orchestrator({ adapter: new Adapter(), statePath: path }).initialize(), /already_open_or_stale_lock/); await e.close();
    await writeFile(path, JSON.stringify({ schemaVersion: 1, tasks: [{ id: 'a', state: 'queued', title: 'A', instruction: 'Read', attempts: 0, dependencies: ['a'] }], events: [] }));
    await assert.rejects(new Orchestrator({ adapter: new Adapter(), statePath: path }).initialize(), /state_dependency_invalid/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('late start completion cannot write after shutdown', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-engine-')), path = join(dir, 'queue.json');
  try {
    const a = new Adapter(); let rejectStart;
    a.startTask = () => new Promise((_, reject) => { rejectStart = reject; });
    const e = await new Orchestrator({ adapter: a, statePath: path }).initialize(); await add(e, 'A'); await start(e); await e.close();
    const before = await readFile(path, 'utf8'); rejectStart(new Error('closed')); await flush(e);
    assert.equal(await readFile(path, 'utf8'), before);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('restart blocks queued tasks already at the attempt ceiling', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-engine-')), path = join(dir, 'queue.json');
  try {
    await writeFile(path, JSON.stringify({ schemaVersion: 1, revision: 3, maxConcurrency: 1, events: [], tasks: [{
      id: 'at-limit', title: 'At limit', instruction: 'Read', dependencies: [], state: 'queued', attempts: 3,
      summary: '', error: '', runKey: null, threadId: null, turnId: null
    }] }));
    const a = new Adapter(), e = await new Orchestrator({ adapter: a, statePath: path }).initialize();
    await e.action({ action: 'connect' }); await e.action({ action: 'authorize', confirmed: true }); await e.action({ action: 'start' }); await flush(e);
    assert.equal(a.starts.length, 0); assert.equal(e.snapshot().tasks[0].state, 'blocked'); assert.equal(e.snapshot().tasks[0].blockReason, 'attempt_limit'); await e.close();
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('explicit disconnect closes the adapter and revokes execution', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a }); await add(e, 'A'); await start(e);
  await e.action({ action: 'disconnect' });
  assert.equal(a.closes, 1); assert.equal(e.snapshot().connected, false); assert.equal(e.snapshot().consent.execution, false); assert.equal(e.snapshot().mode, 'paused'); await e.close();
});

test('stale lock recovery requires explicit opt-in and a provably dead PID', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-engine-')), path = join(dir, 'queue.json');
  try {
    await writeFile(path + '.lock', JSON.stringify({ schemaVersion: 1, pid: 2147483647, startedAt: new Date().toISOString() }));
    await assert.rejects(new Orchestrator({ adapter: new Adapter(), statePath: path }).initialize(), /already_open_or_stale_lock/);
    const e = await new Orchestrator({ adapter: new Adapter(), statePath: path, recoverStaleLock: true }).initialize();
    const lock = JSON.parse(await readFile(path + '.lock', 'utf8')); assert.equal(lock.pid, process.pid); await e.close();
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('concurrent stale-lock recovery cannot delete a replacement owner lock', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-engine-')), path = join(dir, 'queue.json');
  try {
    await writeFile(path + '.lock', JSON.stringify({ schemaVersion: 1, pid: 2147483647, startedAt: new Date().toISOString() }));
    const first = new Orchestrator({ adapter: new Adapter(), statePath: path, recoverStaleLock: true });
    const second = new Orchestrator({ adapter: new Adapter(), statePath: path, recoverStaleLock: true });
    const results = await Promise.allSettled([first.initialize(), second.initialize()]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    assert.equal(results.filter((r) => r.status === 'rejected').length, 1);
    const live = results.find((r) => r.status === 'fulfilled').value; const lock = JSON.parse(await readFile(path + '.lock', 'utf8')); assert.equal(lock.pid, process.pid); await live.close();
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('removes non-running tasks but protects running tasks and dependencies', async () => {
  const a = new Adapter(), e = new Orchestrator({ adapter: a });
  const terminal = await add(e, 'Finished');
  await start(e); a.finish(); await flush(e);
  assert.equal(e.snapshot().tasks[0].state, 'review');
  await e.action({ action: 'remove-task', taskId: terminal });
  assert.equal(e.snapshot().tasks.length, 0);
  const running = await add(e, 'Running'); await flush(e);
  await assert.rejects(e.action({ action: 'remove-task', taskId: running }), /running_task_not_removable/);
  const dependency = await add(e, 'Dependency'); const child = await add(e, 'Child', [dependency]);
  await e.action({ action: 'pause' });
  await assert.rejects(e.action({ action: 'remove-task', taskId: dependency }), /task_has_dependents/);
  await e.action({ action: 'remove-task', taskId: child });
  await e.action({ action: 'remove-task', taskId: dependency });
  await e.close();
});

test('terminal tasks record finishedAt and retries clear it', async () => {
  let clock = 1000;
  const a = new Adapter(), e = new Orchestrator({ adapter: a, now: () => clock });
  const id = await add(e, 'Timed'); await start(e); clock = 2000; a.finish(); await flush(e);
  assert.equal(e.snapshot().tasks[0].finishedAt, 2000);
  await e.action({ action: 'accept', taskId: id });
  await e.action({ action: 'retry', taskId: id }).catch(() => {});
  assert.equal(e.snapshot().tasks[0].finishedAt, 2000);
  await e.close();
});

test('recovery-unknown tasks block new dispatch until explicitly confirmed stopped', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chronos-engine-')), path = join(dir, 'queue.json');
  try {
    await writeFile(path, JSON.stringify({ schemaVersion: 1, revision: 1, maxConcurrency: 1, events: [], tasks: [{
      id: 'old', title: 'Old worker', instruction: 'Read', dependencies: [], state: 'running', attempts: 1,
      summary: '', error: '', runKey: 'old-run', threadId: 'old-thread', turnId: 'old-turn'
    }] }));
    const a = new Adapter(), e = await new Orchestrator({ adapter: a, statePath: path }).initialize();
    await assert.rejects(e.action({ action: 'connect' }).then(() => e.action({ action: 'authorize', confirmed: true })).then(() => e.action({ action: 'start' })), /confirm_previous_worker_stopped/);
    await assert.rejects(e.action({ action: 'remove-task', taskId: 'old' }), /confirm_previous_worker_stopped/);
    await e.action({ action: 'remove-task', taskId: 'old', confirmedStopped: true });
    await e.close();
  } finally { await rm(dir, { recursive: true, force: true }); }
});
