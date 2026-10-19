import { EventEmitter } from 'node:events';
import { stat, realpath } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { isAbsolute, resolve } from 'node:path';
import { StringDecoder } from 'node:string_decoder';

const MAX_TASKS = 2048 * 3;
const MAX_LINE = 1024 * 1024;
const MAX_SUMMARY = 2000;
const REQUEST_TIMEOUT = 10000;
const THREAD_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const pathKey = (value) => process.platform === 'win32' ? resolve(value).toLowerCase() : resolve(value);
const EVIDENCE_LIMIT = 256;
const EVIDENCE_TYPES = new Set(['commandExecution', 'webSearch', 'mcpToolCall', 'fileChange']);
const NON_TOOL_ITEM_TYPES = new Set(['agentMessage', 'userMessage', 'reasoning', 'plan', 'contextCompaction']);

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
    this.writeRoots = new Set();
    this.verifications = new Set();
    this.lastProtocolAt = null;
    this.diagnosticsState = { notifications: 0, responses: 0, errors: 0, lastMethod: null, lastStatus: null, lastErrorCode: null };
    this.modelCatalog = [];
    this.modelCatalogStatus = 'unavailable';
    this.defaultModel = null;
    this.configuredModel = null;
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
      // Chronos owns dispatch and consent. Inherited automation must not start
      // untracked turns, account tools or hook side effects in this process.
      const disabled = ['hooks', 'apps', 'plugins', 'goals', 'multi_agent', 'multi_agent_v2', 'browser_use', 'computer_use', 'in_app_browser', 'in_app_local_automation'];
      const featureArgs = disabled.flatMap((feature) => ['--disable', feature]);
      const executable = /\.(?:js|mjs|cjs)$/i.test(path) ? process.execPath : path;
      const commandArgs = /\.(?:js|mjs|cjs)$/i.test(path) ? [path, 'app-server', ...featureArgs, '--config', 'mcp_servers={}', '--config', 'web_search="disabled"', '--listen', 'stdio://'] : ['app-server', ...featureArgs, '--config', 'mcp_servers={}', '--config', 'web_search="disabled"', '--listen', 'stdio://'];
      this.child = this.spawnProc(executable, commandArgs, { cwd: dir, env, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
      this.transport = this.#childTransport(this.child, generation);
    } else {
      this.transport = await this.transportFactory();
    }
    this.transport.onMessage?.((message) => { if (generation === this.generation) this.#message(message); });
    this.transport.onError?.((error) => { if (generation === this.generation) this.#fail(error); });
    this.transport.onClose?.(() => { if (generation === this.generation) this.#fail(new Error('codex_app_server_closed')); });
    try {
      await this.#request('initialize', { clientInfo: { name: 'chronos-orchestrator', version: '0.2.0-experimental' }, capabilities: { experimentalApi: true } });
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
      this.configuredModel = typeof config?.config?.model === 'string' ? config.config.model : null;
      const servers = config?.config?.mcp_servers;
      if (servers != null && (typeof servers !== 'object' || Array.isArray(servers))) throw new Error('invalid');
      configuredMcpServers = Object.fromEntries(Object.keys(servers || {}).slice(0, 64).map((name) => [name, { enabled: false }]));
    } catch {
      await this.close();
      throw new Error('codex_external_tools_not_isolated');
    }
    this.configuredMcpServers = configuredMcpServers;
    await this.#loadModelCatalog();
    this.connected = true;
    return this;
  }

  async startTask(task) {
    if (!this.connected) throw new Error('adapter_not_connected');
    if (!task || typeof task.instruction !== 'string' || !task.instruction.trim()) throw new Error('task_instruction_required');
    if (this.owned.size >= MAX_TASKS) throw new Error('adapter_task_limit');
    const policy = task.policy || 'read-only';
    if (!['read-only', 'workspace-write'].includes(policy)) throw new Error('task_policy_invalid');
    let selectedModel = task.model;
    if (task.model != null || task.reasoningEffort != null) {
      if (this.modelCatalogStatus !== 'available') throw new Error('model_catalog_unavailable');
      const choice = this.modelCatalog.find((entry) => entry.id === (task.model ?? this.defaultModel) || entry.model === (task.model ?? this.defaultModel));
      if (task.model != null && !choice) throw new Error('model_not_advertised');
      if (task.reasoningEffort != null && (!choice || !choice.supportedReasoningEfforts.some((effort) => effort.reasoningEffort === task.reasoningEffort))) throw new Error('reasoning_effort_not_advertised');
      if (!choice) throw new Error('default_model_not_advertised');
      selectedModel = choice.model;
    }
    const cwd = resolve(task.cwd || this.cwd || process.cwd());
    if (policy === 'workspace-write' && !this.writeRoots.has(pathKey(cwd))) throw new Error('workspace_write_root_not_registered');
    let sourceThreadId = task.sourceThreadId;
    if (task.sourceThreadLink) {
      if (!task.sourceThreadLink.startsWith('codex://threads/')) throw new Error('source_thread_link_invalid');
      sourceThreadId = task.sourceThreadLink.slice('codex://threads/'.length);
    }
    if (sourceThreadId && !THREAD_ID.test(sourceThreadId)) throw new Error('source_thread_link_invalid');
    const method = sourceThreadId ? 'thread/fork' : 'thread/start';
    const started = await this.#request(method, {
      ...(sourceThreadId ? { threadId: sourceThreadId, excludeTurns: true, deferGoalContinuation: true } : {}),
      cwd,
      approvalPolicy: 'never',
      sandbox: policy,
      runtimeWorkspaceRoots: policy === 'workspace-write' ? [cwd] : [],
      config: {
        mcp_servers: this.configuredMcpServers,
        features: { goals: false, multi_agent: false, multi_agent_v2: false, hooks: false, apps: false, plugins: false },
        web_search: task.webSearch === true ? 'live' : 'disabled',
        sandbox_workspace_write: { writable_roots: [], network_access: false, exclude_tmpdir_env_var: true, exclude_slash_tmp: true }
      },
      ...(selectedModel ? { model: selectedModel } : {})
    });
    const expectedType = policy === 'workspace-write' ? 'workspaceWrite' : 'readOnly';
    const extraWriteRoots = policy === 'workspace-write' && (!Array.isArray(started?.sandbox?.writableRoots) || started.sandbox.writableRoots.some((root) => typeof root !== 'string' || pathKey(root) !== pathKey(cwd)));
    if (started?.approvalPolicy !== 'never' || started?.sandbox?.type !== expectedType || started?.sandbox?.networkAccess === true || extraWriteRoots || (started.cwd && pathKey(started.cwd) !== pathKey(cwd))) {
      await this.close();
      throw new Error('codex_policy_mismatch');
    }
    this.effectivePolicy = {
      approvalPolicy: 'never',
      sandbox: expectedType,
      cwd,
      model: typeof started.model === 'string' ? started.model : null,
      modelProvider: typeof started.modelProvider === 'string' ? started.modelProvider : null
    };
    const threadId = started?.thread?.id || started?.threadId;
    if (typeof threadId !== 'string' || !threadId) throw new Error('thread_start_missing_id');
    await this.#verifyIsolation(threadId);
    // Register before turn/start so an immediate notification cannot race ownership.
    this.owned.set(threadId, { taskId: task.id || threadId, turnId: null, active: true, policy: expectedType, evidence: this.#newEvidence() });
    try {
      const turn = await this.#request('turn/start', { threadId, cwd, approvalPolicy: 'never', sandboxPolicy: this.sandboxPolicy(cwd, policy), ...(task.reasoningEffort ? { effort: task.reasoningEffort } : {}), input: [{ type: 'text', text: task.instruction }] });
      const turnId = turn?.turn?.id || turn?.turnId;
      if (typeof turnId !== 'string' || !turnId) throw new Error('turn_start_missing_id');
      this.owned.get(threadId).turnId = turnId;
      return { threadId, turnId };
    } catch (error) {
      await this.close();
      throw error;
    }
  }

  async allowWorkspace(cwd) {
    const path = await realpath(cwd);
    if (!(await stat(path)).isDirectory()) throw new Error('workspace_directory_invalid');
    this.writeRoots.add(pathKey(path));
  }

  sandboxPolicy(cwd, policy) {
    return policy === 'workspace-write' ? { type: 'workspaceWrite', writableRoots: [cwd], networkAccess: false, excludeTmpdirEnvVar: true, excludeSlashTmp: true } : { type: 'readOnly', networkAccess: false };
  }

  async inspectThread(sourceThreadLink) {
    if (!this.connected) throw new Error('connect_runtime_first');
    const threadId = typeof sourceThreadLink === 'string' && sourceThreadLink.startsWith('codex://threads/') ? sourceThreadLink.slice('codex://threads/'.length) : '';
    if (!THREAD_ID.test(threadId)) throw new Error('source_thread_link_invalid');
    const result = await this.#request('thread/read', { threadId, includeTurns: false });
    if (result?.thread?.id !== threadId) throw new Error('source_thread_unavailable');
    return { threadId, sourceThreadLink, title: String(result.thread.name || result.thread.preview || 'Selected thread').slice(0, 120), cwd: typeof result.thread.cwd === 'string' ? result.thread.cwd : null, status: result.thread.status?.type || 'unknown', handling: 'fork_on_dispatch' };
  }

  async verifyCommand({ command, cwd, policy = 'read-only', taskId } = {}) {
    if (!this.connected || !Array.isArray(command) || command.length < 1 || command.length > 32 || command.some((arg) => typeof arg !== 'string' || !arg || arg.length > 2000)) throw new Error('verification_command_invalid');
    cwd = resolve(cwd || this.cwd);
    if (policy === 'workspace-write' && !this.writeRoots.has(pathKey(cwd))) throw new Error('workspace_write_root_not_registered');
    this.verifications.add(taskId);
    try {
      // Windows sandbox rejects outputBytesCap; retain the host default there.
      const result = await this.#request('command/exec', { command, cwd, sandboxPolicy: this.sandboxPolicy(cwd, policy), timeoutMs: 60000, ...(process.platform === 'win32' ? {} : { outputBytesCap: 16000 }) }, 70000);
      if (!Number.isInteger(result?.exitCode)) throw new Error('verification_result_invalid');
      return { exitCode: result.exitCode, stdout: String(result.stdout || '').slice(0, 8000), stderr: String(result.stderr || '').slice(0, 8000) };
    } finally { this.verifications.delete(taskId); }
  }

  async cancelVerification(taskId) {
    if (!this.verifications.has(taskId)) return;
    // command/exec has no per-request cancellation in this protocol build.
    // Closing our owned runtime is safer than claiming the command stopped.
    await this.close();
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
      ownedTaskCount: this.owned.size, activeTurns: [...this.owned.values()].filter((task) => task.active).length, verifyingCommands: this.verifications.size, lastProtocolAt: this.lastProtocolAt, effectivePolicy: this.effectivePolicy && { ...this.effectivePolicy },
      modelCatalogStatus: this.modelCatalogStatus, models: structuredClone(this.modelCatalog), defaultModel: this.defaultModel,
      ...this.diagnosticsState });
  }

  async #loadModelCatalog() {
    this.modelCatalog = [];
    this.modelCatalogStatus = 'unavailable';
    this.defaultModel = null;
    let cursor = null;
    const cursors = new Set();
    let complete = false;
    try {
      for (let page = 0; page < 16; page++) {
        const result = await this.#request('model/list', { ...(cursor ? { cursor } : {}), limit: 100 }, 3000);
        const rows = Array.isArray(result?.data) ? result.data : null;
        if (!rows || rows.length + this.modelCatalog.length > 256) throw new Error('model_catalog_invalid');
        for (const row of rows) {
          const id = typeof row?.id === 'string' ? row.id : typeof row?.model === 'string' ? row.model : null;
          if (!id || id.length > 120 || this.modelCatalog.some((entry) => entry.id === id)) throw new Error('model_catalog_invalid');
          const efforts = Array.isArray(row.supportedReasoningEfforts) ? row.supportedReasoningEfforts : Array.isArray(row.reasoningEfforts) ? row.reasoningEfforts : [];
          if (efforts.length > 32) throw new Error('model_catalog_invalid');
          const supportedReasoningEfforts = efforts.map((effort) => typeof effort === 'string' ? { reasoningEffort: effort, description: '' } : { reasoningEffort: effort?.reasoningEffort, description: typeof effort?.description === 'string' ? effort.description.slice(0, 240) : '' });
          if (supportedReasoningEfforts.some((effort) => typeof effort.reasoningEffort !== 'string' || !effort.reasoningEffort.trim() || effort.reasoningEffort.length > 80) || new Set(supportedReasoningEfforts.map((effort) => effort.reasoningEffort)).size !== supportedReasoningEfforts.length) throw new Error('model_catalog_invalid');
          this.modelCatalog.push({ id, model: typeof row.model === 'string' ? row.model : id, displayName: typeof row.displayName === 'string' ? row.displayName.slice(0, 120) : id, description: typeof row.description === 'string' ? row.description.slice(0, 240) : '', isDefault: row.isDefault === true, defaultReasoningEffort: typeof row.defaultReasoningEffort === 'string' ? row.defaultReasoningEffort : null, supportedReasoningEfforts });
        }
        const next = result?.nextCursor ?? result?.next_cursor ?? null;
        if (next == null) { complete = true; break; }
        if (typeof next !== 'string' || !next || next.length > 4096 || cursors.has(next)) throw new Error('model_catalog_pagination_invalid');
        cursors.add(next);
        cursor = next;
      }
      if (!complete || !this.modelCatalog.length) throw new Error('model_catalog_empty_or_partial');
      this.modelCatalogStatus = 'available';
      const configured = this.modelCatalog.find((entry) => entry.id === this.configuredModel || entry.model === this.configuredModel);
      this.defaultModel = this.configuredModel ? configured?.id || null : this.modelCatalog.find((entry) => entry.isDefault)?.id || null;
    } catch { this.modelCatalog = []; this.modelCatalogStatus = 'unavailable'; this.defaultModel = null; /* catalog is optional; Codex-default execution remains valid */ }
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

  #request(method, params, timeout = REQUEST_TIMEOUT) {
    if (!this.transport?.send) return Promise.reject(new Error('adapter_transport_unavailable'));
    const id = this.nextId++;
    return new Promise((resolveRequest, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`codex_request_timeout:${method}`)); }, timeout);
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
    this.lastProtocolAt = new Date().toISOString();
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
    const owned = this.owned.get(params.threadId);
    if (method === 'turn/started' && (!owned || owned.active === false)) {
      this.#fail(new Error('codex_untracked_turn_detected'));
      void this.close();
      return;
    }
    if (!owned) return;
    const turnId = params.turnId || params.turn?.id || params.item?.turnId || owned.turnId;
    if (owned.turnId && turnId && owned.turnId !== turnId) return;
    const nestedStatus = params.turn?.status?.type || params.turn?.status;
    if (owned) this.diagnosticsState.lastStatus = typeof nestedStatus === 'string' ? nestedStatus.slice(0, 40) : null;
    if (/item\/(started|completed)$/.test(method)) this.#observeItem(owned, method, params.item);
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
    if (['completed', 'failed', 'interrupted'].includes(kind)) owned.active = false;
    this.emit('task-event', { taskId: owned.taskId, kind, turnId, ...(text ? { summary: text } : {}), ...(['completed', 'failed', 'interrupted'].includes(kind) ? { executionEvidence: this.#finishEvidence(owned) } : {}) });
  }

  #newEvidence() { return { startedAt: Date.now(), tracked: new Map(), counts: Object.fromEntries([...EVIDENCE_TYPES, 'unknownItem'].map((type) => [type, { started: 0, completed: 0, failed: 0 }])), partial: false, partialReasons: [] }; }
  #observeItem(owned, method, item) {
    const type = typeof item?.type === 'string' ? item.type : '';
    if (NON_TOOL_ITEM_TYPES.has(type)) return;
    const bucket = EVIDENCE_TYPES.has(type) ? type : 'unknownItem';
    if (!EVIDENCE_TYPES.has(type)) { owned.evidence.partial = true; this.#reason(owned.evidence, 'unknown-item-type'); }
    const id = typeof item?.id === 'string' && item.id ? item.id : null;
    const started = method.endsWith('/started');
    if (!id) { owned.evidence.partial = true; this.#reason(owned.evidence, 'missing-item-id'); return; }
    if (owned.evidence.tracked.size >= EVIDENCE_LIMIT && !owned.evidence.tracked.has(id)) { owned.evidence.partial = true; this.#reason(owned.evidence, 'item-limit'); return; }
    if (started) {
      if (owned.evidence.tracked.has(id)) { owned.evidence.partial = true; this.#reason(owned.evidence, 'duplicate-item'); return; }
      owned.evidence.tracked.set(id, { bucket }); owned.evidence.counts[bucket].started++;
    } else {
      const record = owned.evidence.tracked.get(id);
      if (!record) { owned.evidence.partial = true; this.#reason(owned.evidence, 'unmatched-item'); return; }
      if (record.completed) { owned.evidence.partial = true; this.#reason(owned.evidence, 'duplicate-item'); return; }
      record.completed = true; const status = item?.status?.type || item?.status;
      if (status === 'failed' || status === 'error' || (record.bucket === 'commandExecution' && Number.isFinite(item?.exitCode) && item.exitCode !== 0)) owned.evidence.counts[record.bucket].failed++; else owned.evidence.counts[record.bucket].completed++;
    }
  }
  #reason(evidence, reason) { if (!evidence.partialReasons.includes(reason)) evidence.partialReasons.push(reason); }
  #finishEvidence(owned) {
    const evidence = owned.evidence; for (const record of evidence.tracked.values()) if (!record.completed) { evidence.partial = true; this.#reason(evidence, 'missing-completion'); }
    return { coverage: 'observed_events_only', observedWallMs: Math.max(0, Date.now() - evidence.startedAt), counts: evidence.counts, partial: evidence.partial, ...(evidence.partialReasons.length ? { partialReasons: evidence.partialReasons } : {}) };
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
