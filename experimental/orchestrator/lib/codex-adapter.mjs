import { EventEmitter } from 'node:events';
import { stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { isAbsolute, resolve } from 'node:path';
import { StringDecoder } from 'node:string_decoder';

const MAX_TASKS = 64 * 3;
const MAX_LINE = 1024 * 1024;
const MAX_SUMMARY = 2000;
const REQUEST_TIMEOUT = 10000;

export class CodexAdapter extends EventEmitter {
  constructor({ codexPath, cwd, codexHome, transportFactory, spawnProc = spawn } = {}) {
    super();
    this.codexPath = codexPath;
    this.cwd = cwd;
    this.codexHome = codexHome;
    this.transportFactory = transportFactory;
    this.spawnProc = spawnProc;
    this.child = null;
    this.transport = null;
    this.nextId = 1;
    this.pending = new Map();
    this.owned = new Map();
    this.connected = false;
    this.generation = 0;
    this.effectivePolicy = null;
    this.shutdownUnverified = false;
    this.diagnosticsState = { notifications: 0, responses: 0, errors: 0, lastMethod: null, lastStatus: null, lastErrorCode: null };
  }

  async connect() {
    if (this.connected) return this;
    if (this.shutdownUnverified) throw new Error('codex_previous_runtime_stop_unverified');
    const generation = ++this.generation;
    if (!this.transportFactory) {
      if (!this.codexPath || !isAbsolute(this.codexPath)) throw new Error('codex_path_must_be_absolute');
      const path = resolve(this.codexPath);
      const info = await stat(path).catch(() => null);
      if (!info?.isFile()) throw new Error('codex_path_not_found');
      const dir = resolve(this.cwd || process.cwd());
      const cwdInfo = await stat(dir).catch(() => null);
      if (!cwdInfo?.isDirectory()) throw new Error('adapter_cwd_not_found');
      const env = { ...process.env };
      if (this.codexHome !== undefined) env.CODEX_HOME = resolve(this.codexHome);
      // The orchestrator is a read-only control plane. Hooks are a separate,
      // explicit opt-in and must never be inherited from the user's profile.
      const disabled = ['hooks', 'apps', 'plugins', 'multi_agent', 'multi_agent_v2', 'browser_use', 'computer_use', 'in_app_browser', 'in_app_local_automation'];
      const featureArgs = disabled.flatMap((feature) => ['--disable', feature]);
      this.child = this.spawnProc(path, ['app-server', ...featureArgs, '--config', 'mcp_servers={}', '--config', 'web_search="disabled"', '--listen', 'stdio://'], { cwd: dir, env, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
      this.transport = this.#childTransport(this.child, generation);
    } else {
      this.transport = await this.transportFactory();
    }
    this.transport.onMessage?.((message) => { if (generation === this.generation) this.#message(message); });
    this.transport.onError?.((error) => { if (generation === this.generation) this.#fail(error); });
    this.transport.onClose?.(() => { if (generation === this.generation) this.#fail(new Error('codex_app_server_closed')); });
    try {
      await this.#request('initialize', { clientInfo: { name: 'chronos-orchestrator', version: '0.1.0-experimental' }, capabilities: { experimentalApi: false } });
    } catch (error) {
      await this.close();
      throw error;
    }
    this.#notify('initialized', {});
    let account;
    try {
      account = await this.#request('account/read', { refreshToken: false });
    } catch {
      await this.close();
      throw new Error('codex_account_status_unavailable');
    }
    if (typeof account?.requiresOpenaiAuth !== 'boolean') {
      await this.close();
      throw new Error('codex_account_status_unavailable');
    }
    if (account?.requiresOpenaiAuth === true && !account.account) {
      await this.close();
      throw new Error('codex_login_required');
    }
    let configuredMcpServers;
    try {
      const config = await this.#request('config/read', { cwd: resolve(this.cwd || process.cwd()), includeLayers: false });
      const servers = config?.config?.mcp_servers;
      if (servers != null && (typeof servers !== 'object' || Array.isArray(servers))) throw new Error('invalid');
      configuredMcpServers = Object.fromEntries(Object.keys(servers || {}).slice(0, 64).map((name) => [name, { enabled: false }]));
    } catch {
      await this.close();
      throw new Error('codex_external_tools_not_isolated');
    }
    this.configuredMcpServers = configuredMcpServers;
    this.connected = true;
    return this;
  }

  async startTask(task) {
    if (!this.connected) throw new Error('adapter_not_connected');
    if (!task || typeof task.instruction !== 'string' || !task.instruction.trim()) throw new Error('task_instruction_required');
    if (this.owned.size >= MAX_TASKS) throw new Error('adapter_task_limit');
    const started = await this.#request('thread/start', {
      cwd: task.cwd || this.cwd,
      approvalPolicy: 'never',
      sandbox: 'read-only',
      config: { mcp_servers: this.configuredMcpServers },
      ...(task.model ? { model: task.model } : {})
    });
    if (started?.approvalPolicy !== 'never' || started?.sandbox?.type !== 'readOnly') {
      await this.close();
      throw new Error('codex_policy_mismatch');
    }
    this.effectivePolicy = {
      approvalPolicy: 'never',
      sandbox: 'readOnly',
      model: typeof started.model === 'string' ? started.model : null,
      modelProvider: typeof started.modelProvider === 'string' ? started.modelProvider : null
    };
    const threadId = started?.thread?.id || started?.threadId;
    if (typeof threadId !== 'string' || !threadId) throw new Error('thread_start_missing_id');
    await this.#verifyIsolation(threadId);
    // Register before turn/start so an immediate notification cannot race ownership.
    this.owned.set(threadId, { taskId: task.id || threadId, turnId: null });
    try {
      const turn = await this.#request('turn/start', { threadId, input: [{ type: 'text', text: task.instruction }] });
      const turnId = turn?.turn?.id || turn?.turnId;
      if (typeof turnId !== 'string' || !turnId) throw new Error('turn_start_missing_id');
      this.owned.get(threadId).turnId = turnId;
      return { threadId, turnId };
    } catch (error) {
      await this.close();
      throw error;
    }
  }

  async interruptTask(task) {
    const id = task?.threadId || task?.id;
    const owned = [...this.owned.entries()].find(([threadId, value]) => threadId === id || value.taskId === id)?.[0];
    if (!owned) throw new Error('task_not_owned');
    const turnId = this.owned.get(owned).turnId;
    if (!turnId) return { interrupted: false };
    await this.#request('turn/interrupt', { threadId: owned, turnId });
    return { interrupted: true };
  }

  async close() {
    this.generation++;
    for (const pending of this.pending.values()) clearTimeout(pending.timer);
    this.#fail(new Error('adapter_closed'));
    this.connected = false;
    await this.transport?.close?.();
    this.transport = null;
    const child = this.child;
    if (child) {
      let exited = false;
      if (child.exitCode != null || child.signalCode != null) exited = true;
      await new Promise((resolveClose) => {
        if (exited) return resolveClose();
        let done = false;
        const finish = () => { if (!done) { done = true; exited = true; resolveClose(); } };
        child.once('close', finish); child.kill(); setTimeout(() => { if (!done) { done = true; resolveClose(); } }, 2000);
      });
      this.shutdownUnverified = !exited;
    }
    if (!this.shutdownUnverified) this.child = null;
    this.owned.clear();
    this.effectivePolicy = null;
  }

  diagnostics() {
    return Object.freeze({ connected: this.connected, shutdownUnverified: this.shutdownUnverified,
      ownedTaskCount: this.owned.size, effectivePolicy: this.effectivePolicy && { ...this.effectivePolicy },
      ...this.diagnosticsState });
  }

  #childTransport(child, generation) {
    let buffer = '';
    const decoder = new StringDecoder('utf8');
    const callbacks = new Set();
    child.stdout.on('data', (chunk) => {
      if (generation !== this.generation) return;
      buffer += decoder.write(chunk);
      if (buffer.length > MAX_LINE * 2) return this.#fail(new Error('codex_protocol_line_limit'));
      let index;
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
        if (line.length > MAX_LINE) return this.#fail(new Error('codex_protocol_line_limit'));
        try { for (const cb of callbacks) cb(JSON.parse(line)); } catch { this.#fail(new Error('codex_protocol_invalid_json')); return; }
      }
    });
    // Always drain stderr so a noisy child cannot block its stdout protocol.
    child.stderr?.on('data', () => {});
    child.on('error', (error) => { if (generation === this.generation) this.#fail(error); });
    child.on('close', () => { if (generation === this.generation) this.#fail(new Error('codex_app_server_closed')); });
    return { onMessage: (cb) => callbacks.add(cb), onError: () => {}, onClose: () => {}, send: (message) => child.stdin.write(`${JSON.stringify(message)}\n`), close: () => child.stdin.end() };
  }

  #request(method, params) {
    if (!this.transport?.send) return Promise.reject(new Error('adapter_transport_unavailable'));
    const id = this.nextId++;
    return new Promise((resolveRequest, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`codex_request_timeout:${method}`)); }, REQUEST_TIMEOUT);
      this.pending.set(id, { resolve: resolveRequest, reject, timer });
      try { this.transport.send({ jsonrpc: '2.0', id, method, params }); } catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }

  async #verifyIsolation(threadId) {
    let cursor = null;
    for (let page = 0; page < 32; page++) {
      let result;
      try { result = await this.#request('mcpServerStatus/list', { threadId, cursor, limit: 100 }); }
      catch { await this.close(); throw new Error('codex_external_tools_not_isolated'); }
      if (!result || !Array.isArray(result.data) || result.data.some((server) => {
        if (!server || server.runtimeStatus !== 'disabled') return true;
        return !server.tools || typeof server.tools !== 'object' || Array.isArray(server.tools) || Object.keys(server.tools).length !== 0 ||
          !Array.isArray(server.resources) || server.resources.length !== 0 || !Array.isArray(server.resourceTemplates) || server.resourceTemplates.length !== 0;
      })) {
        await this.close(); throw new Error('codex_external_tools_not_isolated');
      }
      if (result.nextCursor == null) return;
      if (typeof result.nextCursor !== 'string' || result.nextCursor.length > 256 || result.nextCursor === cursor) {
        await this.close(); throw new Error('codex_external_tools_not_isolated');
      }
      cursor = result.nextCursor;
    }
    await this.close(); throw new Error('codex_external_tools_not_isolated');
  }

  #notify(method, params) {
    if (!this.transport?.send) throw new Error('adapter_transport_unavailable');
    this.transport.send({ jsonrpc: '2.0', method, params });
  }

  #message(message) {
    if (message?.id !== undefined && this.pending.has(message.id)) {
      this.diagnosticsState.responses++;
      const entry = this.pending.get(message.id); this.pending.delete(message.id); clearTimeout(entry.timer);
      if (message.error) { this.diagnosticsState.errors++; this.diagnosticsState.lastErrorCode = String(message.error.code || 'unknown').slice(0, 80); entry.reject(new Error(`codex_request_failed:${this.diagnosticsState.lastErrorCode}`)); } else entry.resolve(message.result);
      return;
    }
    // Unknown responses are stale or late protocol traffic. Never answer a
    // response with another response; only method-bearing messages are server
    // requests or notifications.
    if (message?.id !== undefined && !message?.method) return;
    const method = String(message?.method || '');
    this.diagnosticsState.notifications++;
    this.diagnosticsState.lastMethod = /^(?:thread|turn|item|hook|error)\/[A-Za-z0-9._/-]+$/.test(method) ? method : 'other';
    const params = message?.params || {};
    if (/approval|permission|elicitation|user.?input/i.test(method) || message?.id !== undefined) {
      if (message.id !== undefined) this.transport?.send?.({ jsonrpc: '2.0', id: message.id, error: { code: -32001, message: 'Chronos adapter denies approval requests' } });
      const owned = this.owned.get(params.threadId); if (owned) this.#emitTask(params.threadId, 'approval-required', params.turnId);
      return;
    }
    const owned = this.owned.get(params.threadId); if (!owned) return;
    const turnId = params.turnId || params.turn?.id || params.item?.turnId || owned.turnId;
    if (owned.turnId && turnId && owned.turnId !== turnId) return;
    const nestedStatus = params.turn?.status?.type || params.turn?.status;
    if (owned) this.diagnosticsState.lastStatus = typeof nestedStatus === 'string' ? nestedStatus.slice(0, 40) : null;
    if (/turn\/completed$/.test(method) && nestedStatus === 'completed') this.#emitTask(params.threadId, 'completed', turnId, owned.summary);
    else if (/turn\/(failed|error)$/.test(method) || nestedStatus === 'failed' || nestedStatus === 'error') this.#emitTask(params.threadId, 'failed', turnId, this.#boundedText(params));
    else if (/turn\/interrupted$/.test(method) || nestedStatus === 'interrupted') this.#emitTask(params.threadId, 'interrupted', turnId);
    else if (/item\/completed$/.test(method) && params.item?.type === 'agentMessage') {
      owned.summary = this.#agentMessageText(params.item);
      this.#emitTask(params.threadId, 'progress', turnId);
    }
    else if (/turn.*started|item.*started|delta|progress/i.test(method)) this.#emitTask(params.threadId, 'progress', turnId);
  }

  #emitTask(threadId, kind, turnId, text) {
    const owned = this.owned.get(threadId); if (!owned) return;
    this.emit('task-event', { taskId: owned.taskId, kind, turnId, ...(text ? { summary: text } : {}) });
  }

  #boundedText(value) {
    const text = typeof value === 'string' ? value : value?.text || value?.message || '';
    return String(text).slice(0, MAX_SUMMARY);
  }

  #agentMessageText(item) {
    return typeof item.text === 'string' ? item.text.slice(0, MAX_SUMMARY) : '';
  }

  #fail(error) {
    for (const entry of this.pending.values()) { clearTimeout(entry.timer); entry.reject(error); }
    this.pending.clear();
    this.connected = false;
    if (this.listenerCount('error') > 0) this.emit('error', error);
  }
}
