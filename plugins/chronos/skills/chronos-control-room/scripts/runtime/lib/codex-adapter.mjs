import { EventEmitter } from 'node:events';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { stat, realpath, mkdtemp, readFile, rm } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { isAbsolute, resolve, join, relative } from 'node:path';
import { tmpdir, homedir } from 'node:os';
import { StringDecoder } from 'node:string_decoder';
import { COLLABORATION_RESULT_SCHEMA, MAX_COLLABORATION_RESULT } from './collaboration.mjs';
import { protocolCapabilities } from './protocol-capabilities.mjs';

const MAX_TASKS = 2048 * 3;
const MAX_LINE = 1024 * 1024;
const MAX_SUMMARY = 2000;
const REQUEST_TIMEOUT = 10000;
const THREAD_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const pathKey = (value) => process.platform === 'win32' ? resolve(value).toLowerCase() : resolve(value);
const EVIDENCE_LIMIT = 256;
const EVIDENCE_TYPES = new Set(['commandExecution', 'webSearch', 'mcpToolCall', 'fileChange']);
const NON_TOOL_ITEM_TYPES = new Set(['agentMessage', 'userMessage', 'reasoning', 'plan', 'contextCompaction']);
const SESSION_SCHEMA_VERSION = 1;
const SESSION_IDENTITY_RE = /^[0-9a-f]{64}$/i;
const hashText = (value) => createHash('sha256').update(String(value), 'utf8').digest('hex');
const stableJson = (value) => JSON.stringify(value, Object.keys(value || {}).sort());
const activeThreadStatus = new Set(['active', 'running', 'inProgress', 'in_progress', 'turning']);
const resumableThreadStatus = new Set(['idle', 'waiting', 'completed', 'interrupted', 'failed', 'notLoaded', 'archived']);

export class CodexAdapter extends EventEmitter {
  constructor({ codexPath, cwd, codexHome, transportFactory, spawnProc = spawn, protocolSchema } = {}) {
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
    this.sessionCapabilities = protocolCapabilities(protocolSchema);
    this.protocolSchemaHash = protocolSchema ? hashText(JSON.stringify(protocolSchema)) : null;
    this.executableDigest = null;
    this.lifecycleWaiters = new Map();
    this.closedThreads = new Set();
  }

  async connect() {
    if (this.connected) return this;
    if (this.shutdownUnverified) throw new Error('codex_previous_runtime_stop_unverified');
    const generation = ++this.generation;
    this.runtimeHomePath = await realpath(resolve(this.codexHome || process.env.CODEX_HOME || join(homedir(), '.codex'))).catch(() => resolve(this.codexHome || process.env.CODEX_HOME || join(homedir(), '.codex')));
    if (!this.protocolSchemaHash && this.codexPath) await this.#negotiateProtocolSchema();
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
    const expectedType = policy === 'workspace-write' ? 'workspaceWrite' : 'readOnly';
    // Only an idle thread that this adapter created in the current process can be
    // reused. User-selected threads remain fork-only so Control Room never takes
    // over a Desktop chat, and write/source/model/search tasks always get fresh
    // isolated context.
    const reuseKey = typeof task.reuseKey === 'string' && task.reuseKey.length > 0 && task.reuseKey.length <= 200 &&
      !sourceThreadId && policy === 'read-only' && task.model == null && task.webSearch !== true ? task.reuseKey : null;
    const reusable = reuseKey && [...this.owned.entries()].find(([, owned]) => !owned.active && owned.reuseKey === reuseKey && owned.policy === expectedType && owned.cwd === pathKey(cwd) && owned.collaborative === (task.collaborative === true));
    let threadId;
    let reusedThread = false;
    if (reusable) {
      [threadId] = reusable;
      const owned = this.owned.get(threadId);
      await this.#verifyIsolation(threadId);
      // Register before turn/start so an immediate notification cannot race ownership.
      Object.assign(owned, { taskId: task.id || threadId, turnId: null, active: true, evidence: this.#newEvidence() });
      reusedThread = true;
    } else {
      if (this.owned.size >= MAX_TASKS) throw new Error('adapter_task_limit');
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
    const extraWriteRoots = policy === 'workspace-write' && (!Array.isArray(started?.sandbox?.writableRoots) || started.sandbox.writableRoots.length !== 1 || started.sandbox.writableRoots.some((root) => typeof root !== 'string' || pathKey(root) !== pathKey(cwd)));
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
      threadId = started?.thread?.id || started?.threadId;
      if (typeof threadId !== 'string' || !threadId) throw new Error('thread_start_missing_id');
      await this.#verifyIsolation(threadId);
      // Register before turn/start so an immediate notification cannot race ownership.
      this.owned.set(threadId, { taskId: task.id || threadId, turnId: null, active: true, policy: expectedType, cwd: pathKey(cwd), reuseKey, collaborative: task.collaborative === true, evidence: this.#newEvidence() });
    }
    try {
      const turn = await this.#request('turn/start', { threadId, cwd, approvalPolicy: 'never', sandboxPolicy: this.sandboxPolicy(cwd, policy), ...(task.reasoningEffort ? { effort: task.reasoningEffort } : {}), ...(task.collaborative === true ? { outputSchema: COLLABORATION_RESULT_SCHEMA } : {}), input: [{ type: 'text', text: task.instruction }] });
      const turnId = turn?.turn?.id || turn?.turnId;
      if (typeof turnId !== 'string' || !turnId) throw new Error('turn_start_missing_id');
      this.owned.get(threadId).turnId = turnId;
      return { threadId, turnId, reusedThread };
    } catch (error) {
      await this.close();
      throw error;
    }
  }

  // Durable project agents use a two-phase lifecycle. The thread is created and
  // validated here; the caller persists the returned binding before it can send
  // a turn through startSessionTurn. This preserves the thread identity across
  // a process restart without letting a caller attach an arbitrary Desktop chat.
  async prepareSession(spec = {}) {
    if (!this.connected) throw new Error('adapter_not_connected');
    if (!this.sessionCapabilities.prepare) throw new Error('persistent_session_unsupported');
    if (spec.threadId && (spec.binding || spec.sessionBinding)) {
      const binding = spec.binding || spec.sessionBinding;
      const requested = { ...binding, ...spec, stageId: spec.stageId || binding.stageId || binding.agentId || spec.sessionId || binding.sessionId };
      const normalized = this.#sessionSpec(requested);
      for (const key of ['stageId', 'projectId', 'agentId', 'workItemId', 'instructionVersion', 'dataScope', 'sourceThreadId', 'webSearch', 'policy', 'cwd', 'model', 'reasoningEffort', 'instructionsHash']) if ((normalized[key] ?? null) !== (binding[key] ?? null)) throw new Error('session_binding_scope_mismatch');
      return this.resumeSession({ threadId: spec.threadId, binding });
    }
    if (spec.binding && !spec.instructionsHash) spec = { ...spec, ...spec.binding, stageId: spec.stageId || spec.binding.agentId || spec.sessionId || spec.binding.sessionId };
    const normalized = this.#sessionSpec(spec);
    if (normalized.sourceThreadId && !this.sessionCapabilities.fork) throw new Error('session_source_fork_unsupported');
    const started = await this.#request(normalized.sourceThreadId ? 'thread/fork' : 'thread/start', {
      ...(normalized.sourceThreadId ? { threadId: normalized.sourceThreadId, excludeTurns: true, deferGoalContinuation: true } : {}),
      cwd: normalized.cwd,
      approvalPolicy: 'never',
      sandbox: normalized.policy,
      runtimeWorkspaceRoots: normalized.policy === 'workspace-write' ? [normalized.cwd] : [],
      config: {
        mcp_servers: this.configuredMcpServers,
        features: { goals: false, multi_agent: false, multi_agent_v2: false, hooks: false, apps: false, plugins: false },
        web_search: normalized.webSearch ? 'live' : 'disabled',
        sandbox_workspace_write: { writable_roots: [], network_access: false, exclude_tmpdir_env_var: true, exclude_slash_tmp: true }
      },
      ...(normalized.model ? { model: normalized.model } : {})
    });
    const threadId = started?.thread?.id || started?.threadId;
    if (typeof threadId !== 'string' || !THREAD_ID.test(threadId)) throw new Error('session_prepare_missing_id');
    const expectedType = normalized.policy === 'workspace-write' ? 'workspaceWrite' : 'readOnly';
    if (started?.approvalPolicy !== 'never' || started?.sandbox?.type !== expectedType || started?.sandbox?.networkAccess !== false || (started.cwd && pathKey(started.cwd) !== pathKey(normalized.cwd)) || normalized.policy === 'workspace-write' && (!Array.isArray(started.sandbox.writableRoots) || started.sandbox.writableRoots.length !== 1 || pathKey(started.sandbox.writableRoots[0]) !== pathKey(normalized.cwd))) {
      await this.close();
      throw new Error('codex_policy_mismatch');
    }
    await this.#verifyIsolation(threadId);
    const runtimeIdentity = this.#runtimeIdentity();
    const binding = this.#sessionBinding({ ...normalized, threadId, runtimeIdentity, effectiveModel: started.model || normalized.model || null, effectiveReasoningEffort: started.reasoningEffort || normalized.reasoningEffort || null });
    this.owned.set(threadId, {
      taskId: `session:${normalized.stageId}`,
      turnId: null,
      active: false,
      policy: expectedType,
      cwd: pathKey(normalized.cwd),
      reuseKey: null,
      collaborative: false,
      session: true,
      sessionBinding: binding,
      evidence: this.#newEvidence()
    });
    this.closedThreads.delete(threadId);
    return { threadId, sourceThreadLink: `codex://threads/${threadId}`, binding, runtimeGeneration: this.generation };
  }

  async resumeSession(session = {}) {
    if (!this.connected) throw new Error('adapter_not_connected');
    if (!this.sessionCapabilities.resume) throw new Error('persistent_session_resume_unsupported');
    const binding = session.binding || session;
    const threadId = session.threadId || binding.threadId;
    if (!THREAD_ID.test(String(threadId || ''))) throw new Error('session_thread_id_invalid');
    this.#validateBinding(binding, threadId);
    if (binding.policy === 'workspace-write' && !this.writeRoots.has(pathKey(binding.cwd))) throw new Error('workspace_write_root_not_registered');
    const result = await this.#request('thread/resume', {
      threadId,
      cwd: binding.cwd,
      excludeTurns: true,
      approvalPolicy: 'never',
      sandbox: binding.policy === 'workspace-write' ? 'workspace-write' : 'read-only',
      runtimeWorkspaceRoots: binding.policy === 'workspace-write' ? [binding.cwd] : [],
      config: { mcp_servers: this.configuredMcpServers, features: { goals: false, multi_agent: false, multi_agent_v2: false, hooks: false, apps: false, plugins: false }, web_search: binding.webSearch ? 'live' : 'disabled', sandbox_workspace_write: { writable_roots: [], network_access: false, exclude_tmpdir_env_var: true, exclude_slash_tmp: true } },
      ...(binding.effectiveModel || binding.model ? { model: binding.effectiveModel || binding.model } : {})
    });
    const thread = result?.thread;
    if (!thread || thread.id !== threadId) throw new Error('session_thread_unavailable');
    const status = thread.status?.type || thread.status;
    if (activeThreadStatus.has(status)) throw new Error('session_thread_active');
    if (typeof status !== 'string' || !resumableThreadStatus.has(status)) throw new Error('session_thread_status_unknown');
    const cwd = typeof thread.cwd === 'string' ? resolve(thread.cwd) : null;
    if (!cwd || pathKey(cwd) !== pathKey(binding.cwd)) throw new Error('session_binding_cwd_mismatch');
    if (binding.model && thread.model && binding.model !== thread.model) throw new Error('session_binding_model_mismatch');
    if (binding.effectiveModel && result.model !== binding.effectiveModel) throw new Error('session_binding_model_mismatch');
    const expectedSandbox = binding.policy === 'workspace-write' ? 'workspaceWrite' : 'readOnly';
    if (result?.approvalPolicy !== 'never') throw new Error('codex_policy_mismatch');
    if (result?.sandbox?.type !== expectedSandbox || result.sandbox.networkAccess !== false) throw new Error('codex_policy_mismatch');
    if (binding.policy === 'workspace-write' && (!Array.isArray(result?.sandbox?.writableRoots) || result.sandbox.writableRoots.length !== 1 || pathKey(result.sandbox.writableRoots[0]) !== pathKey(binding.cwd))) throw new Error('codex_policy_mismatch');
    await this.#verifyIsolation(threadId);
    const owned = this.owned.get(threadId);
    if (owned?.active) throw new Error('session_turn_active');
    this.owned.set(threadId, {
      taskId: `session:${binding.stageId}`,
      turnId: null,
      active: false,
      policy: binding.policy === 'workspace-write' ? 'workspaceWrite' : 'readOnly',
      cwd: pathKey(binding.cwd),
      reuseKey: null,
      collaborative: false,
      session: true,
      sessionBinding: binding,
      evidence: this.#newEvidence()
    });
    this.closedThreads.delete(threadId);
    return { threadId, sourceThreadLink: `codex://threads/${threadId}`, status, binding, runtimeGeneration: this.generation };
  }

  async startSessionTurn(session = {}) {
    if (!this.connected) throw new Error('adapter_not_connected');
    if (!this.sessionCapabilities.turn) throw new Error('persistent_session_turn_unsupported');
    const threadId = session.threadId || session.binding?.threadId;
    const owned = this.owned.get(threadId);
    if (!owned?.session) throw new Error('session_not_prepared');
    if (owned.active || owned.turnId) throw new Error('session_turn_active');
    if (session.binding) this.#validateBinding(session.binding, threadId);
    if (session.binding && session.binding.bindingHash !== owned.sessionBinding.bindingHash) throw new Error('session_binding_scope_mismatch');
    if (typeof session.instruction !== 'string' || !session.instruction.trim()) throw new Error('session_instruction_required');
    owned.taskId = session.runKey || session.id || owned.taskId;
    owned.active = true;
    owned.turnId = null;
    owned.awaitingStart = true;
    owned.pendingNotifications = [];
    owned.summary = '';
    owned.collaborative = session.collaborative === true;
    owned.evidence = this.#newEvidence();
    const turn = await this.#request('turn/start', {
      threadId,
      cwd: owned.sessionBinding.cwd,
      approvalPolicy: 'never',
      sandboxPolicy: this.sandboxPolicy(owned.sessionBinding.cwd, owned.sessionBinding.policy),
      ...(owned.sessionBinding.reasoningEffort || owned.sessionBinding.effectiveReasoningEffort ? { effort: owned.sessionBinding.reasoningEffort || owned.sessionBinding.effectiveReasoningEffort } : {}),
      ...(session.outputSchema ? { outputSchema: session.outputSchema } : (session.collaborative === true ? { outputSchema: COLLABORATION_RESULT_SCHEMA } : {})),
      config: { web_search: session.webSearch === true ? 'live' : 'disabled' },
      input: [{ type: 'text', text: session.instruction }]
    }).catch((error) => {
      if (String(error?.message || '').includes('codex_request_timeout:turn/start')) throw new Error('session_turn_start_uncertain', { cause: error });
      throw error;
    });
    const turnId = turn?.turn?.id || turn?.turnId;
    if (typeof turnId !== 'string' || !turnId) throw new Error('session_turn_missing_id');
    // The host can emit completion before the request response. Do not
    // resurrect a completed turn after that race.
    owned.turnId = turnId;
    owned.awaitingStart = false;
    const notifications = owned.pendingNotifications; owned.pendingNotifications = [];
    for (const notification of notifications) this.#message(notification);
    return { threadId, turnId, binding: owned.sessionBinding };
  }

  async cleanupSession(session = {}) { return this.archiveSession(session); }
  isSessionLoaded(threadId) { return this.owned.has(threadId) && !this.closedThreads.has(threadId); }

  runtimeIdentity() {
    return Object.freeze({ homeIdentity: hashText(pathKey(this.runtimeHomePath || this.codexHome || process.env.CODEX_HOME || join(homedir(), '.codex'))), executableIdentity: this.executableDigest || hashText(this.codexPath ? pathKey(this.codexPath) : 'transport-factory'), protocolVersion: this.protocolSchemaHash || 'unnegotiated' });
  }

  async inspectSession(session = {}) {
    const threadId = session.threadId || session.binding?.threadId;
    const binding = session.binding || this.owned.get(threadId)?.sessionBinding;
    this.#validateBinding(binding, threadId);
    const result = await this.#request('thread/read', { threadId, includeTurns: false });
    const thread = result?.thread;
    if (!thread || thread.id !== threadId) throw new Error('session_thread_unavailable');
    return { threadId, status: thread.status?.type || thread.status || 'unknown', cwd: thread.cwd || null, model: thread.model || null };
  }

  async unsubscribeSession(session = {}) {
    const threadId = session.threadId || session.binding?.threadId;
    const binding = session.binding || this.owned.get(threadId)?.sessionBinding;
    this.#validateBinding(binding, threadId);
    if (!this.sessionCapabilities.unsubscribe) return { threadId, released: false, status: 'unsupported' };
    if (this.owned.get(threadId)?.active) throw new Error('session_turn_active');
    const observed = this.#waitLifecycle(threadId, 'thread/closed', 3000);
    const result = await this.#request('thread/unsubscribe', { threadId });
    const released = this.closedThreads.has(threadId) || result?.status === 'notLoaded' || await observed;
    if (released) this.owned.delete(threadId);
    return { threadId, released, status: released ? 'closed_observed' : result?.status || 'release_pending' };
  }

  async compactSession(session = {}) {
    const threadId = session.threadId || session.binding?.threadId;
    const binding = session.binding || this.owned.get(threadId)?.sessionBinding;
    this.#validateBinding(binding, threadId);
    if (!this.sessionCapabilities.compact) throw new Error('session_compaction_unsupported');
    await this.resumeSession({ threadId, binding });
    const owned = this.owned.get(threadId);
    if (owned?.active) throw new Error('session_turn_active');
    owned.active = true; owned.maintenance = 'compaction';
    owned.compaction = { turnId: null, itemId: null, itemCompleted: false, evidence: null };
    const observed = this.#waitLifecycle(threadId, 'thread/compacted', 120000);
    try {
      await this.#request('thread/compact/start', { threadId });
      const completed = await observed;
      const proof = owned.compaction;
      if (completed) { owned.active = false; owned.maintenance = null; owned.turnId = null; owned.compaction = null; }
      return { threadId, accepted: true, completed, evidence: completed ? proof?.evidence || 'thread_compacted_notification' : 'completion_unobserved' };
    } catch (error) { owned.maintenance = null; throw error; }
  }

  async archiveSession(session = {}) {
    const threadId = session.threadId || session.binding?.threadId;
    const binding = session.binding || this.owned.get(threadId)?.sessionBinding;
    this.#validateBinding(binding, threadId);
    if (!this.sessionCapabilities.archive) throw new Error('session_archive_descendants_unproven');
    if (!(await this.#proveNoDescendants(threadId))) throw new Error('session_archive_descendants_unproven');
    if (this.owned.get(threadId)?.active) throw new Error('session_turn_active');
    if (this.archiveProofTargetAlreadyArchived || await this.#archivedSessionObserved(threadId, binding.cwd)) {
      const release = await this.unsubscribeSession({ threadId, binding }).catch(() => ({ released: false }));
      return { threadId, archived: true, evidence: 'archived_inventory_observed', subscriptionReleased: release.released };
    }
    const observed = this.#waitLifecycle(threadId, 'thread/archived', 3000);
    await this.#request('thread/archive', { threadId });
    const notificationObserved = await observed;
    const release = await this.unsubscribeSession({ threadId, binding }).catch(() => ({ released: false }));
    return { threadId, archived: true, notificationObserved, evidence: notificationObserved ? 'native_archive_notification' : 'native_archive_rpc_completed', subscriptionReleased: release.released };
  }

  #waitLifecycle(threadId, method, timeout) {
    const key = `${threadId}:${method}`;
    return new Promise((done) => {
      const finish = (observed) => { clearTimeout(timer); this.lifecycleWaiters.delete(key); done(observed); };
      const timer = setTimeout(() => finish(false), timeout);
      this.lifecycleWaiters.set(key, { observed: () => finish(true), cancel: () => finish(false) });
    });
  }

  async #archivedSessionObserved(threadId, cwd) {
    const canonical = await realpath(cwd).catch(() => cwd);
    for (const workspace of new Set([cwd, canonical])) {
      let cursor = null; const seen = new Set();
      for (let page = 0; page < 32; page++) {
      let result;
      try { result = await this.#request('thread/list', { archived: true, cwd: workspace, cursor, limit: 100, sourceKinds: this.sessionCapabilities.listSourceKinds, modelProviders: [] }, 3000); }
      catch { return false; }
      if (!Array.isArray(result?.data)) return false;
      if (result.data.some((row) => row?.id === threadId)) return true;
      if (result.nextCursor == null) break;
      if (typeof result.nextCursor !== 'string' || !result.nextCursor || seen.has(result.nextCursor)) return false;
      seen.add(result.nextCursor); cursor = result.nextCursor;
      }
    }
    return false;
  }

  #runtimeIdentity() { return hashText(JSON.stringify(this.runtimeIdentity())); }
  async #negotiateProtocolSchema() {
    const source = resolve(this.codexPath);
    const executable = /\.(?:js|mjs|cjs)$/i.test(source) ? process.execPath : source;
    const args = /\.(?:js|mjs|cjs)$/i.test(source) ? [source, 'app-server', 'generate-json-schema', '--experimental'] : ['app-server', 'generate-json-schema', '--experimental'];
    let dir;
    try {
      dir = await mkdtemp(join(tmpdir(), 'chronos-protocol-'));
      const result = await new Promise((resolveResult) => {
        const child = this.spawnProc(executable, [...args, '--out', dir], { cwd: resolve(this.cwd || process.cwd()), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let settled = false; const finish = (value) => { if (!settled) { settled = true; resolveResult(value); } };
        const timer = setTimeout(() => { try { child.kill(); } catch {} finish({ ok: false }); }, 10000);
        child.on('error', () => { clearTimeout(timer); finish({ ok: false }); }); child.on('close', (code) => { clearTimeout(timer); finish({ ok: code === 0 }); });
        child.stdout?.resume(); child.stderr?.resume();
      });
      if (!result.ok) return;
      const sourceInfo = await stat(source);
      if (sourceInfo.size > 1073741824) return;
      const executableHash = createHash('sha256');
      for await (const chunk of createReadStream(source)) executableHash.update(chunk);
      this.executableDigest = executableHash.digest('hex');
      const schema = JSON.parse(await readFile(join(dir, 'ClientRequest.json'), 'utf8'));
      try {
        const listResponse = JSON.parse(await readFile(join(dir, 'v2', 'ThreadListResponse.json'), 'utf8'));
        const listParams = JSON.parse(await readFile(join(dir, 'v2', 'ThreadListParams.json'), 'utf8'));
        schema.lifecycleContract = { sourceKinds: listParams.definitions?.ThreadSourceKind?.enum, thread: listResponse.definitions?.Thread?.properties, listResponse: listResponse.properties, ancestorFilter: Boolean(listParams.properties?.ancestorThreadId), omittedCursorIsEnd: !listResponse.required?.includes('nextCursor') && listResponse.properties?.nextCursor?.type?.includes('null') && /no more items/i.test(listResponse.properties?.nextCursor?.description || '') };
      } catch { /* Older hosts can expose resumption without safe archival. */ }
      this.sessionCapabilities = protocolCapabilities(schema);
      const { omittedCursorIsEnd, ancestorFilter, ...contract } = schema.lifecycleContract || {};
      this.protocolSchemaHash = hashText(JSON.stringify(schema.lifecycleContract ? { ...schema, lifecycleContract: contract } : schema));
    } catch {
      this.sessionCapabilities = protocolCapabilities(null);
    } finally {
      if (dir && relative(resolve(tmpdir()), resolve(dir)).startsWith('chronos-protocol-') && !relative(resolve(tmpdir()), resolve(dir)).includes('..')) await rm(resolve(dir), { recursive: true, force: true }).catch(() => {});
    }
  }
  async #proveNoDescendants(threadId) {
    const failed = (reason) => { this.archiveProofStatus = reason; return false; };
    const deadline = Date.now() + 60000;
    this.archiveProofTargetAlreadyArchived = false;
    if (!this.sessionCapabilities.listDescendants || !this.sessionCapabilities.listSourceKinds?.length) return failed('schema_contract_unavailable');
    for (const archived of [false, true]) {
      let cursor = null; const seen = new Set();
      for (let page = 0; page < 32; page++) {
        let result;
        if (Date.now() >= deadline) return failed('inventory_time_budget');
        try { result = await this.#request('thread/list', { cursor, limit: 100, archived, ...(this.sessionCapabilities.ancestorFilter ? { ancestorThreadId: threadId } : {}), sourceKinds: this.sessionCapabilities.listSourceKinds, modelProviders: [] }, Math.min(30000, deadline - Date.now())); }
        catch (error) { this.archiveProofError = String(error?.message || '').slice(0, 100); this.archiveProofDetail = error?.cause?.message ? String(error.cause.message).slice(0, 300) : null; return failed('inventory_request_unavailable'); }
        if (!result || !Array.isArray(result.data) || !Object.hasOwn(result, 'nextCursor') && !this.sessionCapabilities.omittedCursorIsEnd) return failed('inventory_shape_unproven');
        for (const row of result.data) {
          if (!row || !THREAD_ID.test(String(row.id || '')) || row.parentThreadId != null && !THREAD_ID.test(String(row.parentThreadId))) return failed('inventory_row_invalid');
          if (row.parentThreadId === threadId) return failed('descendant_present');
          if (this.sessionCapabilities.ancestorFilter) return failed('descendant_present');
          if (row.id === threadId && activeThreadStatus.has(row.status?.type || row.status)) return failed('target_active');
          if (archived && row.id === threadId) this.archiveProofTargetAlreadyArchived = true;
        }
        const next = result.nextCursor;
        if (next == null) break;
        if (typeof next !== 'string' || !next || seen.has(next)) return failed('inventory_cursor_invalid');
        seen.add(next); cursor = next;
      }
      if (cursor && seen.size >= 32) return failed('inventory_capacity');
    }
    this.archiveProofStatus = 'no_descendants_observed_complete_contract';
    return true;
  }
  #sessionSpec(spec) {
    const stageId = spec?.stageId || spec?.agentId || spec?.sessionId;
    if (!spec || typeof stageId !== 'string' || !stageId.trim() || stageId.length > 200) throw new Error('session_stage_id_invalid');
    const policy = spec.policy || 'read-only';
    if (!['read-only', 'workspace-write'].includes(policy)) throw new Error('task_policy_invalid');
    const cwd = resolve(spec.cwd || this.cwd || process.cwd());
    if (policy === 'workspace-write' && !this.writeRoots.has(pathKey(cwd))) throw new Error('workspace_write_root_not_registered');
    let model = typeof spec.model === 'string' && spec.model ? spec.model : null;
    const reasoningEffort = typeof spec.reasoningEffort === 'string' ? spec.reasoningEffort : null;
    if (model || reasoningEffort) {
      if (this.modelCatalogStatus !== 'available') throw new Error('model_catalog_unavailable');
      const choice = this.modelCatalog.find((entry) => entry.id === (model || this.defaultModel) || entry.model === (model || this.defaultModel));
      if (!choice) throw new Error('model_not_advertised');
      if (reasoningEffort && !choice.supportedReasoningEfforts.some((entry) => entry.reasoningEffort === reasoningEffort)) throw new Error('reasoning_effort_not_advertised');
      model = choice.model;
    }
    const instructionsHash = typeof (spec.instructionsHash || spec.instructionHash) === 'string' && SESSION_IDENTITY_RE.test(spec.instructionsHash || spec.instructionHash) ? (spec.instructionsHash || spec.instructionHash).toLowerCase() : null;
    if (!instructionsHash) throw new Error('session_instructions_hash_required');
    const scope = {};
    for (const key of ['projectId', 'agentId', 'workItemId', 'dataScope', 'sourceThreadId']) {
      if (spec[key] != null && (typeof spec[key] !== 'string' || !spec[key].trim() || spec[key].length > 200)) throw new Error(`session_${key}_invalid`);
      if (spec[key] != null) scope[key] = spec[key].trim();
    }
    if (scope.sourceThreadId && !THREAD_ID.test(scope.sourceThreadId)) throw new Error('source_thread_link_invalid');
    if (spec.instructionVersion != null && (!Number.isSafeInteger(spec.instructionVersion) || spec.instructionVersion < 1)) throw new Error('session_instruction_version_invalid');
    return { stageId: stageId.trim(), sessionId: typeof spec.sessionId === 'string' ? spec.sessionId : null, ...scope, instructionVersion: spec.instructionVersion || null, webSearch: spec.webSearch === true, policy, cwd, model, reasoningEffort, instructionsHash };
  }
  #sessionBinding({ stageId, sessionId, projectId, agentId, workItemId, instructionVersion, dataScope, sourceThreadId, webSearch, policy, cwd, model, reasoningEffort, effectiveModel, effectiveReasoningEffort, instructionsHash, threadId, runtimeIdentity }) {
    const binding = { schemaVersion: SESSION_SCHEMA_VERSION, stageId, sessionId, projectId: projectId || null, agentId: agentId || null, workItemId: workItemId || null, instructionVersion, dataScope: dataScope || null, sourceThreadId: sourceThreadId || null, webSearch, threadId, policy, cwd, model, reasoningEffort, effectiveModel, effectiveReasoningEffort, instructionsHash, runtimeIdentity };
    return { ...binding, bindingHash: hashText(stableJson(binding)) };
  }
  #validateBinding(binding, threadId) {
    if (!binding || binding.schemaVersion !== SESSION_SCHEMA_VERSION || binding.threadId !== threadId || !THREAD_ID.test(String(threadId || '')) || !SESSION_IDENTITY_RE.test(binding.instructionsHash || '') || !SESSION_IDENTITY_RE.test(binding.runtimeIdentity || '') || !SESSION_IDENTITY_RE.test(binding.bindingHash || '')) throw new Error('session_binding_invalid');
    const { bindingHash, ...unsigned } = binding;
    if (hashText(stableJson(unsigned)) !== bindingHash) throw new Error('session_binding_hash_mismatch');
    if (binding.runtimeIdentity !== this.#runtimeIdentity()) throw new Error('session_runtime_identity_mismatch');
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
    for (const waiter of this.lifecycleWaiters.values()) waiter.cancel();
    this.lifecycleWaiters.clear(); this.closedThreads.clear();
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
      sessionCapabilities: this.sessionCapabilities,
      protocolSchemaHash: this.protocolSchemaHash,
      archiveProofStatus: this.archiveProofStatus || 'not_checked',
      archiveProofError: this.archiveProofError || null,
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
      if (message.error) { this.diagnosticsState.errors++; this.diagnosticsState.lastErrorCode = String(message.error.code || 'unknown').slice(0, 80); entry.reject(new Error(`codex_request_failed:${this.diagnosticsState.lastErrorCode}`, { cause: message.error })); } else entry.resolve(message.result);
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
    const lifecycle = this.lifecycleWaiters.get(`${params.threadId}:${method}`);
    if (lifecycle) lifecycle.observed();
    if (method === 'thread/closed' && (this.owned.has(params.threadId) || lifecycle)) this.closedThreads.add(params.threadId);
    if (/approval|permission|elicitation|user.?input/i.test(method) || message?.id !== undefined) {
      if (message.id !== undefined) this.transport?.send?.({ jsonrpc: '2.0', id: message.id, error: { code: -32001, message: 'Chronos adapter denies approval requests' } });
      const owned = this.owned.get(params.threadId); if (owned) this.#emitTask(params.threadId, 'approval-required', params.turnId);
      return;
    }
    const owned = this.owned.get(params.threadId);
    if (owned?.maintenance === 'compaction') {
      const proof = owned.compaction;
      const turnId = params.turnId || params.turn?.id || params.item?.turnId;
      if (!proof || typeof turnId !== 'string' || !turnId) return;
      if (method === 'turn/started' && !proof.turnId) proof.turnId = turnId;
      if (method === 'item/started' && params.item?.type === 'contextCompaction' && typeof params.item.id === 'string' && params.item.id && (!proof.turnId || proof.turnId === turnId)) {
        proof.turnId = turnId; proof.itemId = params.item.id;
      }
      if (turnId !== proof.turnId) return;
      if (method === 'item/completed' && params.item?.type === 'contextCompaction' && params.item.id === proof.itemId) proof.itemCompleted = true;
      if (method === 'turn/completed') {
        const status = params.turn?.status?.type || params.turn?.status;
        const waiter = this.lifecycleWaiters.get(`${params.threadId}:thread/compacted`);
        if (status === 'completed' && proof.itemCompleted) { proof.evidence = 'context_compaction_item_and_turn_completed'; waiter?.observed(); }
        else if (['failed', 'error', 'interrupted'].includes(status)) waiter?.cancel();
      }
      return;
    }
    if (owned?.session && owned.awaitingStart && /^(?:turn|item)\//.test(method)) {
      if (owned.pendingNotifications.length >= 512) { this.#fail(new Error('session_start_event_capacity')); return; }
      owned.pendingNotifications.push(message); return;
    }
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
      owned.summary = this.#agentMessageText(params.item, owned.collaborative ? MAX_COLLABORATION_RESULT + 1 : owned.session ? 4096 : MAX_SUMMARY);
      this.#emitTask(params.threadId, 'progress', turnId);
    }
    else if (/turn.*started|item.*started|delta|progress/i.test(method)) this.#emitTask(params.threadId, 'progress', turnId);
  }

  #emitTask(threadId, kind, turnId, text) {
    const owned = this.owned.get(threadId); if (!owned) return;
    if (['completed', 'failed', 'interrupted'].includes(kind)) owned.active = false;
    this.emit('task-event', { taskId: owned.taskId, threadId, runtimeGeneration: this.generation, kind, turnId, ...(text ? { summary: text } : {}), ...(['completed', 'failed', 'interrupted'].includes(kind) ? { executionEvidence: this.#finishEvidence(owned) } : {}) });
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

  #agentMessageText(item, limit = MAX_SUMMARY) {
    return typeof item.text === 'string' ? item.text.slice(0, limit) : '';
  }

  #fail(error) {
    for (const entry of this.pending.values()) { clearTimeout(entry.timer); entry.reject(error); }
    this.pending.clear();
    this.connected = false;
    if (this.listenerCount('error') > 0) this.emit('error', error);
  }
}
