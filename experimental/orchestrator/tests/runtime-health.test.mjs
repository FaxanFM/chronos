import test from 'node:test';
import assert from 'node:assert/strict';
import { RuntimeHealth } from '../lib/runtime-health.mjs';

const system = (free, platform = 'linux') => ({ totalmem: () => 8 * 1024 ** 3, freemem: () => free, cpus: () => [1, 2, 3, 4], platform: () => platform, loadavg: () => [1, 2, 3] });
const adapter = { child: { pid: 42, killed: false }, diagnostics: () => ({ activeThreads: 2, lastProtocolAt: '2026-01-01T00:00:00Z' }) };

test('runtime health reports available managed-runtime coverage and caches snapshots', async () => {
  const h = new RuntimeHealth({ adapter, engine: { state: { connected: true, tasks: [{ state: 'queued' }, { state: 'verifying' }, { state: 'review' }] } }, system: system(4 * 1024 ** 3), processInfo: { memoryUsage: () => ({ rss: 123 }) }, now: () => 0 });
  const sample = await h.sample();
  assert.equal(sample.health, 'available'); assert.equal(sample.coverage, 'managed_runtime_only');
  assert.equal(sample.ownedRuntime.pid, 42); assert.equal(sample.ownedRuntime.activeTurns, 2); assert.equal(sample.queue.verifying, 1); assert.equal(h.snapshot().sampledAt, sample.sampledAt);
});

test('runtime health distinguishes memory pressure and disconnection', async () => {
  const engine = { state: { connected: true, tasks: [] } }; const h = new RuntimeHealth({ adapter, engine, system: system(100 * 1024 ** 2) });
  assert.equal((await h.sample()).health, 'degraded'); engine.state.connected = false; assert.equal((await h.sample()).health, 'unavailable');
  const win = new RuntimeHealth({ adapter, engine: { state: { connected: true, tasks: [] } }, system: system(4 * 1024 ** 3, 'win32') });
  assert.equal((await win.sample()).host.loadAverage, null);
});
