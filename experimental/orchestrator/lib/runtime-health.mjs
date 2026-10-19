import os from 'node:os';

const clamp = (n, min, max) => Math.max(min, Math.min(max, Math.round(n)));

export class RuntimeHealth {
  constructor({ adapter, engine, now = () => Date.now(), system = os, processInfo = process } = {}) {
    this.adapter = adapter;
    this.engine = engine;
    this.now = now;
    this.system = system;
    this.processInfo = processInfo;
    this.cached = null;
  }

  async sample() {
    const sampledAt = new Date(this.now()).toISOString();
    const diagnostics = this.adapter?.diagnostics?.() || {};
    const child = this.adapter?.child;
    const pid = Number.isInteger(child?.pid) ? child.pid : null;
    let alive = null;
    if (pid != null && typeof child?.killed === 'boolean') alive = !child.killed && child.exitCode == null && child.signalCode == null;
    const connected = this.engine?.state?.connected === true && diagnostics.connected !== false;
    const tasks = this.engine?.state?.tasks || [];
    const queue = {
      queued: tasks.filter((t) => t.state === 'queued' || t.state === 'blocked').length,
      running: tasks.filter((t) => t.state === 'running').length,
      verifying: tasks.filter((t) => t.state === 'verifying').length,
      review: tasks.filter((t) => t.state === 'review').length,
      failed: tasks.filter((t) => t.state === 'failed').length,
      recoveryUnknown: tasks.filter((t) => t.recoveryUnknown === true).length
    };
    const total = Number(this.system.totalmem?.() || 0);
    const free = Number(this.system.freemem?.() || 0);
    const cpuCount = Number(this.system.cpus?.().length || 0);
    const platform = this.system.platform?.() || process.platform;
    const lowMemory = total > 0 && free < Math.max(512 * 1048576, total * 0.08);
    const health = !connected ? 'unavailable' : lowMemory ? 'degraded' : 'available';
    const loadAverage = platform === 'win32' ? null : (this.system.loadavg?.() || null);
    const recommendedConcurrency = clamp(Math.min(cpuCount || 1, lowMemory ? 2 : 16), 1, 16);
    let processMemoryBytes = null;
    try { processMemoryBytes = this.processInfo?.memoryUsage?.().rss ?? null; } catch { /* optional telemetry */ }
    const owned = diagnostics.activeTurns || diagnostics.activeThreads || diagnostics.activeThreadCount || 0;
    const snapshot = {
      sampledAt, health, coverage: 'managed_runtime_only',
      ownedRuntime: { pid, alive, connected, activeTurns: Number.isFinite(owned) ? owned : 0, lastProtocolAt: diagnostics.lastProtocolAt || null },
      host: { cpuCount, totalMemoryBytes: total, freeMemoryBytes: free, loadAverage, platform, processMemoryBytes },
      queue,
      recommendedConcurrency
    };
    this.cached = snapshot;
    return structuredClone(snapshot);
  }

  snapshot() { return this.cached ? structuredClone(this.cached) : null; }
}
