import { createHash, randomUUID } from 'node:crypto';
import { resolve, dirname, join } from 'node:path';
import { lstat, readdir } from 'node:fs/promises';

const fail = (code) => { throw new Error(code); };
const hash = (value) => createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
const pathKey = (value) => process.platform === 'win32' ? resolve(value).toLowerCase() : resolve(value);
const active = (task) => ['running', 'verifying'].includes(task.state);
const sessionStates = new Set(['creation-pending', 'idle', 'active', 'waiting', 'uncertain', 'cleanup-pending', 'archived', 'deleted']);
const bounded = (value, max) => typeof value === 'string' && value.trim() && value.length <= max;
export const AGENT_RETENTION = Object.freeze({ maxUnarchivedSessions: 64, maxSessionRecords: 256, maxLoadedSessions: 16, maxAuditEntries: 2000, maxLedgerEntries: 256, maxRetainedLocalBytes: 268435456 });
export const WORK_OUTCOME_SCHEMA = Object.freeze({ type: 'object', additionalProperties: false, required: ['status', 'summary', 'question'], properties: { status: { type: 'string', enum: ['needs-input', 'ready-for-review', 'completed', 'failed'] }, summary: { type: 'string', maxLength: 1800 }, question: { anyOf: [{ type: 'null' }, { type: 'object', additionalProperties: false, required: ['body', 'targetAgentId'], properties: { body: { type: 'string', maxLength: 600 }, targetAgentId: { anyOf: [{ type: 'null' }, { type: 'string', maxLength: 100 }] } } }] } } });

export function validateRetention(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw) || Object.keys(raw).some((key) => !Object.hasOwn(AGENT_RETENTION, key))) fail('agent_retention_invalid');
  const value = { ...AGENT_RETENTION, ...raw };
  for (const [key, max] of Object.entries({ maxUnarchivedSessions: 1024, maxSessionRecords: 4096, maxLoadedSessions: 64, maxAuditEntries: 20000, maxLedgerEntries: 2048, maxRetainedLocalBytes: 1073741824 })) {
    if (!Number.isSafeInteger(value[key]) || value[key] < 1 || value[key] > max) fail('agent_retention_invalid');
  }
  if (value.maxSessionRecords < value.maxUnarchivedSessions || value.maxRetainedLocalBytes < 1048576) fail('agent_retention_invalid');
  return value;
}

/** Durable project identities are independent of native execution conversations. */
export class AgentController {
  constructor(engine) { this.engine = engine; this.cleanupInFlight = new Set(); }
  get state() { return this.engine.state; }
  get now() { return this.engine.now(); }
  bootstrap(saved = null) {
    const workspace = pathKey(this.engine.adapter.cwd || process.cwd());
    const projectId = 'project-' + hash(workspace).slice(0, 24);
    if (saved?.schemaVersion === 5) {
      if (!saved.project || saved.project.id !== projectId || saved.project.workspace !== workspace || !['hybrid', 'persistent', 'one-off', 'legacy'].includes(saved.project.conversationDefault)) fail('agent_project_identity_invalid');
      for (const key of ['agents', 'sessions', 'agentMessages', 'agentQuestions', 'ledger', 'projectAudit']) if (!Array.isArray(saved[key])) fail('agent_state_invalid');
      this.state.project = { ...saved.project, retention: validateRetention(saved.project.retention) };
      for (const key of ['agents', 'sessions', 'agentMessages', 'agentQuestions', 'ledger', 'projectAudit']) this.state[key] = saved[key];
      this.state.archivedAssignments = Array.isArray(saved.archivedAssignments) ? saved.archivedAssignments : [];
      this.validate();
      for (const session of this.state.sessions) {
        if (['creation-pending', 'active', 'uncertain'].includes(session.state)) { session.state = 'uncertain'; session.recoveryRequired = true; }
        session.observedHostState = 'not_reconciled';
      }
    } else {
      this.state.project = { id: projectId, workspace, name: workspace.split(/[\\/]/).at(-1) || 'Project', conversationDefault: saved ? 'legacy' : 'hybrid', retention: { ...AGENT_RETENTION }, createdAt: this.now, migratedFrom: saved?.schemaVersion || null };
      for (const key of ['agents', 'sessions', 'agentMessages', 'agentQuestions', 'ledger', 'projectAudit']) this.state[key] = [];
      this.state.archivedAssignments = [];
    }
    this.ensureAgents();
  }
  validate() {
    const s = this.state, limits = s.project.retention;
    if (s.agents.length > 512 || s.sessions.length > limits.maxSessionRecords || s.ledger.length > limits.maxLedgerEntries || s.agentMessages.length > 1024 || s.agentQuestions.length > 256 || s.projectAudit.length > limits.maxAuditEntries + 256 || (s.archivedAssignments || []).length > limits.maxSessionRecords) fail('agent_state_capacity');
    for (const key of ['agents', 'sessions', 'agentMessages', 'agentQuestions', 'ledger']) if (new Set(s[key].map((item) => item?.id)).size !== s[key].length) fail('agent_state_duplicate');
    const agentIds = new Set(s.agents.map((agent) => agent.id));
    for (const agent of s.agents) {
      if (!bounded(agent.id, 100) || agent.projectId !== s.project.id || !bounded(agent.name, 120) || !Array.isArray(agent.instructions) || agent.instructions.length > 32 || !Array.isArray(agent.stageRefs) || !Array.isArray(agent.lineage) || !Array.isArray(agent.mailbox)) fail('agent_state_invalid');
      for (const item of agent.instructions) if (!Number.isSafeInteger(item.version) || !bounded(item.instruction, 12000) || item.sha256 !== hash(item.instruction)) fail('agent_instruction_invalid');
      if (agent.primarySessionId && !s.sessions.some((item) => item.id === agent.primarySessionId && item.agentId === agent.id && item.role === 'primary')) fail('agent_primary_reference_invalid');
    }
    for (const session of s.sessions) {
      if (!bounded(session.id, 100) || session.projectId !== s.project.id || !agentIds.has(session.agentId) || !sessionStates.has(session.state) || !['primary', 'worker'].includes(session.role) || !session.scope || session.scope.projectId !== s.project.id || session.scope.agentId !== session.agentId || !Number.isSafeInteger(session.generation) || session.generation < 1) fail('agent_session_invalid');
      if (session.turns != null && (!Number.isSafeInteger(session.turns) || session.turns < 0 || session.turns > 12) || session.attemptHistory != null && (!Array.isArray(session.attemptHistory) || session.attemptHistory.length > 12)) fail('agent_session_history_invalid');
      if (session.threadId && (!session.binding || session.binding.threadId !== session.threadId)) fail('agent_session_binding_invalid');
      if (session.currentRunKey && !s.tasks.some((task) => task.runKey === session.currentRunKey && task.sessionId === session.id)) fail('agent_session_attempt_invalid');
    }
    for (const message of s.agentMessages) if (!agentIds.has(message.agentId) || !['user', 'assistant'].includes(message.role) || !bounded(message.body, 12000)) fail('agent_message_invalid');
    for (const [index, entry] of s.ledger.entries()) {
      if (entry.projectId !== s.project.id || entry.revision !== index + 1 || !['human_decision', 'project_goal', 'project_constraint', 'agent_proposal', 'accepted_output', 'verified_result'].includes(entry.kind) || !bounded(entry.body, 1800)) fail('project_ledger_invalid');
      if (['accepted_output', 'verified_result'].includes(entry.kind)) {
        const source = s.tasks.find((task) => task.id === entry.sourceTaskId), archived = s.archivedAssignments.find((task) => task.taskId === entry.sourceTaskId);
        if (!source && !archived || source && hash(source.summary) !== entry.sha256 || archived && archived.summaryHash !== entry.sha256 || entry.checkpoint && JSON.stringify(entry.checkpoint) !== JSON.stringify(source?.fileCheckpoint || archived?.fileCheckpoint)) fail('project_ledger_provenance_invalid');
        if (entry.kind === 'verified_result' && entry.verification?.exitCode !== 0) fail('project_ledger_verification_invalid');
      }
    }
    for (const question of s.agentQuestions) if (!agentIds.has(question.agentId) || !s.tasks.some((task) => task.id === question.taskId) && !s.archivedAssignments.some((task) => task.taskId === question.taskId) || !['waiting', 'answered', 'escalated', 'cancelled'].includes(question.state) || !bounded(question.question, 600)) fail('agent_question_invalid');
    let previous = null;
    for (const entry of s.projectAudit) {
      const { sha256, ...body } = entry;
      if (body.previous !== previous || hash(body) !== sha256) fail('agent_audit_chain_invalid');
      previous = sha256;
    }
  }
  ensureAgents() {
    for (const workflow of this.state.workflows) for (const node of workflow.nodes) {
      const id = node.agentId || 'agent-' + hash(`${this.state.project.id}:${workflow.id}:${node.id}`).slice(0, 24);
      let agent = this.state.agents.find((item) => item.id === id);
      if (!agent) {
        if (this.state.agents.length >= 512) fail('agent_capacity');
        agent = { id, projectId: this.state.project.id, name: node.title, instructionVersion: 1, instructions: [], stageRefs: [], primarySessionId: null, lineage: [], mailbox: [], memoryRefs: [] };
        this.state.agents.push(agent);
      }
      const sha256 = hash(node.instruction);
      let version = agent.instructions.find((item) => item.sha256 === sha256);
      if (!version) {
        if (agent.instructions.length >= 32) fail('agent_instruction_version_capacity');
        version = { version: agent.instructions.length + 1, sha256, instruction: node.instruction, at: this.now };
        agent.instructions.push(version);
      }
      agent.instructionVersion = version.version;
      const ref = { workflowId: workflow.id, nodeId: node.id, instructionVersion: version.version };
      agent.stageRefs = [...agent.stageRefs.filter((item) => item.workflowId !== workflow.id || item.nodeId !== node.id), ref];
    }
  }
  agentFor(workflow, node) { return this.state.agents.find((item) => item.id === node?.agentId || item.stageRefs.some((ref) => ref.workflowId === workflow?.id && ref.nodeId === node?.id)); }
  async checkStorageBudget() {
    const limit = this.state.project.retention.maxRetainedLocalBytes;
    let bytes = Buffer.byteLength(JSON.stringify(this.state)), files = 0;
    const visit = async (path, depth = 0) => {
      if (depth > 40 || ++files > 20000) fail('agent_storage_inventory_capacity');
      const info = await lstat(path).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
      if (!info) return;
      if (info.isSymbolicLink()) fail('agent_storage_inventory_link_unsupported');
      if (info.isFile()) { bytes += info.size; if (bytes > limit) fail('agent_retained_data_capacity'); return; }
      if (!info.isDirectory()) fail('agent_storage_inventory_unsupported');
      for (const name of await readdir(path)) await visit(join(path, name), depth + 1);
    };
    if (this.engine.statePath) await visit(join(dirname(this.engine.statePath), 'workspaces'));
    this.state.project.storage = { at: this.now, bytes, entries: files, coverage: 'queue_and_owned_workspaces', nativeTranscripts: 'unsupported' };
    if (bytes > limit) fail('agent_retained_data_capacity');
  }
  audit(type, taskId, message) {
    if (!this.state.project) return;
    const entries = this.state.projectAudit, limit = this.state.project.retention.maxAuditEntries;
    if (entries.length >= limit) { this.state.mode = 'paused'; this.state.project.auditBlocked = true; }
    if (entries.length >= limit + 256) fail('project_audit_capacity');
    const body = { sequence: entries.length + 1, at: this.now, type, taskId: taskId || null, message: String(message).slice(0, 500), previous: entries.at(-1)?.sha256 || null };
    entries.push({ ...body, sha256: hash(body) });
  }
  describe(task, node, workflow, packet) {
    let mode = task.discussionAgentId ? 'persistent' : packet?.conversationMode && packet.conversationMode !== 'inherit' ? packet.conversationMode : node?.conversationMode && node.conversationMode !== 'inherit' ? node.conversationMode : workflow?.conversationDefault || 'legacy';
    if (mode === 'inherit') mode = this.state.project.conversationDefault;
    if (mode === 'legacy') return { mode, role: null, reason: 'Existing workflow keeps its previous session behavior.' };
    let role = mode === 'one-off' ? 'worker' : 'primary', reason = mode === 'one-off' ? 'Isolated work-item conversation.' : 'Explicit project conversation continuity.';
    if (mode === 'hybrid') {
      const independent = node?.independentReview === true || task.dependencies.some((id) => this.state.tasks.find((item) => item.id === id)?.fileCheckpoint);
      if (task.policy === 'workspace-write' || independent || packet?.relatedToProject !== true || task.sourceThreadId) { role = 'worker'; reason = task.policy === 'workspace-write' ? 'Writes require an isolated work-item session.' : independent ? 'Independent review receives exact artifacts in a separate session.' : task.sourceThreadId ? 'Selected source context stays isolated.' : 'Related-project context was not explicitly selected.'; }
      else reason = 'Compatible related serial analysis uses the primary conversation.';
    }
    return { mode, role, reason };
  }
  plan(task, node, workflow, packet) {
    const decision = this.describe(task, node, workflow, packet);
    task.dispatchDecision = decision;
    if (decision.mode === 'legacy') return null;
    const agent = task.discussionAgentId ? this.state.agents.find((item) => item.id === task.discussionAgentId) : this.agentFor(workflow, node);
    if (!agent) fail('agent_not_found');
    if (!this.engine.adapter.prepareSession || !this.engine.adapter.startSessionTurn) fail('managed_session_capability_unsupported');
    const capabilities = this.engine.adapter.diagnostics?.().sessionCapabilities;
    if (capabilities && (!capabilities.prepare || !capabilities.resume || !capabilities.turn)) fail('managed_session_capability_unsupported');
    const version = task.discussionAgentId ? agent.instructions.at(-1) : agent.instructions.find((item) => item.sha256 === hash(node.instruction));
    const scope = { projectId: this.state.project.id, agentId: agent.id, workItemId: decision.role === 'worker' ? `${task.packetId || task.id}:${task.nodeId || 'discussion'}` : null, cwd: pathKey(task.cwd || this.state.project.workspace), policy: task.policy || 'read-only', model: node?.model || task.model || null, reasoningEffort: node?.reasoningEffort || task.reasoningEffort || null, webSearch: node?.webSearch === true, instructionVersion: version.version, instructionsHash: version.sha256, runtime: this.engine.adapter.runtimeIdentity?.() || null, dataScope: decision.role === 'worker' ? hash({ source: task.sourceThreadId || null, inputs: task.dependencies.map((id) => { const t = this.state.tasks.find((item) => item.id === id); return [id, t?.stageRevision || 1, t?.fileCheckpoint?.id || null]; }) }) : this.state.project.id };
    if (task.sourceThreadId && node?.independentReview) fail('independent_review_source_context_forbidden');
    if (task.sourceThreadId) scope.sourceThreadId = task.sourceThreadId;
    const primary = this.state.sessions.find((item) => item.id === agent.primarySessionId) || this.state.sessions.findLast((item) => item.agentId === agent.id && item.role === 'primary' && ['creation-pending', 'active'].includes(item.state));
    if (task.discussionAgentId && primary && !agent.rotationIntent) {
      for (const key of ['model', 'reasoningEffort', 'webSearch']) scope[key] = primary.scope[key];
    }
    let session = decision.role === 'primary' && !agent.rotationIntent ? primary : this.state.sessions.findLast((item) => item.agentId === agent.id && item.role === 'worker' && item.scope.workItemId === scope.workItemId && ['idle', 'waiting'].includes(item.state) && JSON.stringify(item.scope) === JSON.stringify(scope));
    if (session && ['active', 'creation-pending', 'uncertain', 'cleanup-pending'].includes(session.state)) {
      if (decision.mode === 'hybrid' && decision.role === 'primary') {
        decision.role = 'worker';
        decision.reason = 'Primary agent is busy; Hybrid isolated this work item instead of queueing behind the primary turn.';
        scope.workItemId = `${task.packetId || task.id}:${task.nodeId || 'discussion'}`;
        session = this.state.sessions.findLast((item) => item.agentId === agent.id && item.role === 'worker' && item.scope.workItemId === scope.workItemId && ['idle', 'waiting'].includes(item.state) && JSON.stringify(item.scope) === JSON.stringify(scope));
      } else return { waiting: true, reason: 'primary_session_busy_or_uncertain' };
    }
    if (session?.state === 'waiting' && !task.continuationRequested) return { waiting: true, reason: 'primary_waiting_for_answer' };
    if (session && JSON.stringify(session.scope) !== JSON.stringify(scope)) {
      if (decision.mode === 'persistent') fail('persistent_session_scope_changed_rotate_required');
      decision.role = 'worker'; decision.reason = 'Primary context binding changed; isolate this assignment.'; scope.workItemId = `${task.packetId || task.id}:${task.nodeId || 'discussion'}`; session = null;
    }
    if (!session && decision.role === 'worker' && this.state.sessions.some((item) => item.agentId === agent.id && item.workItemId === scope.workItemId)) decision.reason = 'Work-item workspace, evidence or instruction binding changed; use a new isolated session.';
    if (decision.mode === 'persistent' && (task.policy === 'workspace-write' || node?.independentReview)) fail('persistent_isolated_work_required');
    // Check the bounded session turn budget before changing state. A rejected
    // dispatch must not create a session or increment a task's turn counter.
    if ((session?.turns || 0) >= 12) fail('work_item_turn_limit');
    if (this.engine.adapter.diagnostics?.().ownedTaskCount >= this.state.project.retention.maxLoadedSessions && !this.engine.adapter.isSessionLoaded?.(session?.threadId)) fail('agent_loaded_session_capacity_release_required');
    if (!session || ['archived', 'deleted'].includes(session.state)) {
      const limits = this.state.project.retention;
      if (this.state.project.auditBlocked || this.state.projectAudit.length >= limits.maxAuditEntries) fail('project_audit_capacity');
      if (this.state.sessions.length >= limits.maxSessionRecords || this.state.sessions.filter((item) => !['archived', 'deleted'].includes(item.state)).length >= limits.maxUnarchivedSessions) fail('agent_session_capacity_cleanup_required');
      const receiptBytes = [...this.state.tasks, ...this.state.archivedAssignments].reduce((total, t) => total + (t.fileCheckpoint?.bytes || 0) + (t.checkpointBase?.bytes || 0), 0);
      if (receiptBytes + Buffer.byteLength(JSON.stringify(this.state)) > limits.maxRetainedLocalBytes) fail('agent_retained_data_capacity');
      session = { id: randomUUID(), projectId: this.state.project.id, agentId: agent.id, workItemId: scope.workItemId, role: decision.role, generation: agent.lineage.length + 1, state: 'creation-pending', observedHostState: 'unknown', scope, binding: null, threadId: null, creationIntent: { id: randomUUID(), at: this.now }, createdAt: this.now, reason: decision.reason, predecessorId: decision.role === 'primary' ? agent.primarySessionId : null, rotationCheckpoint: decision.role === 'primary' ? agent.rotationIntent?.checkpoint || null : null };
      this.state.sessions.push(session);
    }
    session.state = session.threadId ? 'active' : 'creation-pending';
    session.currentTaskId = task.id; task.sessionId = session.id; task.agentId = agent.id;
    session.turns = (session.turns || 0) + 1;
    session.attemptHistory = [...(session.attemptHistory || []), { taskId: task.id, runKey: null, at: this.now, revision: task.stageRevision || 1 }];
    task.sessionTurn = session.turns;
    return { session, agent, scope, decision };
  }
  async start(task, args, plan) {
    const { session, scope, agent } = plan, runKey = task.runKey;
    const guard = () => !this.engine.closed && task.runKey === runKey && task.state === 'running';
    try {
      const prepared = await this.engine.adapter.prepareSession({ sessionId: session.id, stageId: agent.id, ...scope, ...(session.threadId ? { threadId: session.threadId, binding: session.binding } : {}) });
      let permitted = false;
      await this.engine.enqueue(async () => {
        if (!guard()) { session.state = 'uncertain'; session.recoveryRequired = true; await this.engine.save(); return; }
        if (!prepared?.threadId || !prepared.binding) fail('session_prepare_receipt_invalid');
        session.threadId = prepared.threadId; session.binding = prepared.binding; session.observedHostState = 'idle'; session.currentRunKey = runKey; session.state = 'active';
        task.threadId = prepared.threadId;
        task.runtimeGeneration = prepared.runtimeGeneration ?? null;
        if (session.role === 'primary' && agent.primarySessionId !== session.id) {
          const predecessor = this.state.sessions.find((item) => item.id === session.predecessorId);
          if (predecessor) predecessor.successorId = session.id;
          agent.primarySessionId = session.id; agent.lineage.push({ sessionId: session.id, generation: session.generation, predecessorId: session.predecessorId, at: this.now }); agent.rotationIntent = null;
        }
        this.engine.event('session_prepared', task.id, 'Verified managed session identity persisted before turn start.');
        await this.engine.save(); permitted = true;
      });
      if (!permitted) fail('session_dispatch_cancelled_before_turn');
      return await this.engine.adapter.startSessionTurn({ ...args, sessionId: session.id, attemptId: runKey, workItemRevision: task.stageRevision || 1, threadId: session.threadId, binding: session.binding, ...(!task.discussionAgentId && !args.collaborative ? { outputSchema: WORK_OUTCOME_SCHEMA } : {}) });
    } catch (error) {
      await this.engine.enqueue(async () => {
        if (!guard()) return;
        session.state = 'uncertain'; session.recoveryRequired = true; session.observedHostState = 'unknown';
        task.state = 'blocked'; task.blockReason = /^[a-z][a-z0-9_]{1,95}$/.test(error?.message || '') ? error.message : 'managed_session_outcome_uncertain'; task.error = task.blockReason; task.recoveryUnknown = true; this.state.mode = 'paused';
        this.engine.event('session_uncertain', task.id, 'Native operation outcome requires reconciliation; no replacement was created.'); await this.engine.save();
      });
      throw error;
    }
  }
  terminal(task, event) {
    const session = this.state.sessions.find((item) => item.id === task.sessionId);
    if (!session) return;
    if (session.currentRunKey && session.currentRunKey !== task.runKey || event.threadId && event.threadId !== session.threadId) fail('session_event_binding_invalid');
    session.currentRunKey = null; session.lastTurnId = event.turnId || task.turnId || null; session.state = 'idle'; session.observedHostState = 'idle'; session.lastTerminalAt = this.now;
    const attempt = session.attemptHistory?.at(-1);
    if (attempt?.runKey === task.runKey) Object.assign(attempt, { terminal: event.kind, turnId: session.lastTurnId, finishedAt: this.now });
  }
  outcome(task, event) {
    if (!task.sessionId || event.kind !== 'completed' || task.cancelRequested || task.stopReason) return null;
    if (task.discussionAgentId) {
      const body = String(event.summary || '').trim().slice(0, 2000) || 'No response text was returned.';
      this.message(task.agentId, 'assistant', body, task.id); task.summary = body; task.state = 'accepted'; task.finishedAt = this.now;
      this.engine.event('agent_replied', task.id, 'Agent discussion completed without changing project decisions or permissions.'); return 'handled';
    }
    const workflow = this.state.workflows.find((item) => item.id === task.workflowId);
    if (workflow?.mode === 'collaborative') return null;
    let result;
    try { result = JSON.parse(event.summary); } catch { fail('work_outcome_invalid'); }
    if (!result || Object.keys(result).sort().join('|') !== 'question|status|summary' || !['needs-input', 'ready-for-review', 'completed', 'failed'].includes(result.status) || !bounded(result.summary, 1800)) fail('work_outcome_invalid');
    task.summary = result.summary; task.workOutcome = result.status;
    if (result.status === 'needs-input') {
      const q = result.question;
      if (!q || Object.keys(q).sort().join('|') !== 'body|targetAgentId' || !bounded(q.body, 600) || q.targetAgentId != null && !this.state.agents.some((agent) => agent.id === q.targetAgentId)) fail('work_question_invalid');
      if (this.state.agentQuestions.length >= 256 || (task.questionRounds || 0) >= 3 || this.state.agentQuestions.some((entry) => entry.taskId === task.id && hash(entry.question) === hash(q.body))) fail('work_question_limit');
      const question = { id: randomUUID(), projectId: this.state.project.id, agentId: task.agentId, targetAgentId: q.targetAgentId || null, taskId: task.id, packetId: task.packetId || null, revision: task.stageRevision || 1, attemptId: task.runKey, sessionId: task.sessionId, question: q.body.trim(), state: 'waiting', at: this.now, deadline: this.now + 900000 };
      let target = question.targetAgentId; const seen = new Set([task.agentId]); let cyclic = false;
      while (target) {
        if (seen.has(target)) { cyclic = true; break; }
        seen.add(target);
        target = this.state.agentQuestions.find((item) => item.agentId === target && item.state === 'waiting')?.targetAgentId;
      }
      if (cyclic) { question.state = 'escalated'; question.escalation = 'circular_wait'; }
      this.state.agentQuestions.push(question); task.questionRounds = (task.questionRounds || 0) + 1; task.state = 'blocked'; task.blockReason = 'needs_input'; task.error = ''; task.finishedAt = this.now;
      if (cyclic) { task.blockReason = 'question_cycle'; task.error = 'A circular agent question needs a human decision.'; }
      this.state.sessions.find((item) => item.id === task.sessionId).state = 'waiting';
      if (q.targetAgentId) this.state.agents.find((item) => item.id === q.targetAgentId).mailbox.push(question.id);
      this.engine.event('agent_needs_input', task.id, 'Assignment is waiting for an answer; execution capacity is released.'); return 'handled';
    }
    if (result.question !== null) fail('work_outcome_invalid');
    if (result.status === 'failed') { task.state = 'failed'; task.error = result.summary || 'Agent reported failure.'; task.finishedAt = this.now; return 'handled'; }
    if (this.state.ledger.length >= this.state.project.retention.maxLedgerEntries) fail('project_ledger_capacity');
    this.state.ledger.push({ id: randomUUID(), projectId: this.state.project.id, agentId: task.agentId, revision: this.state.ledger.length + 1, kind: 'agent_proposal', body: result.summary, sourceTaskId: task.id, attemptId: task.runKey, stageRevision: task.stageRevision || 1, at: this.now });
    return result.summary;
  }
  message(agentId, role, body, taskId) {
    if (this.state.agentMessages.length >= 1024) fail('agent_message_capacity');
    this.state.agentMessages.push({ id: randomUUID(), agentId, role, body, taskId, at: this.now });
  }
  archiveTasks(tasks = []) {
    if (!Array.isArray(tasks) || tasks.length > 256) fail('agent_archive_invalid');
    if (!Array.isArray(this.state.archivedAssignments)) this.state.archivedAssignments = [];
    const managed = tasks.filter((task) => task?.agentId);
    if (this.state.archivedAssignments.length + managed.length > this.state.project.retention.maxSessionRecords) fail('agent_archive_capacity');
    if (managed.some((task) => this.state.agentQuestions.some((question) => question.taskId === task.id && ['waiting', 'escalated'].includes(question.state)))) fail('resolve_agent_questions_before_archive');
    for (const task of managed) {
      if (!task?.id || !task.agentId) continue;
      const questionIds = this.state.agentQuestions.filter((item) => item.taskId === task.id).map((item) => item.id);
      this.state.archivedAssignments.push({ id: randomUUID(), taskId: task.id, agentId: task.agentId, sessionId: task.sessionId || null, state: task.state, questionIds, summaryHash: hash(task.summary || ''), fileCheckpoint: task.fileCheckpoint || null, at: this.now, reason: 'queue_record_archived' });
    }
    return this.state.archivedAssignments.at(-1) || null;
  }
  accepted(task) {
    if (!task.agentId || task.discussionAgentId || this.state.ledger.some((entry) => entry.sourceTaskId === task.id && ['accepted_output', 'verified_result'].includes(entry.kind))) return;
    if (this.state.ledger.length >= this.state.project.retention.maxLedgerEntries) { this.state.mode = 'paused'; return; }
    const entry = { id: randomUUID(), projectId: this.state.project.id, agentId: task.agentId, revision: this.state.ledger.length + 1, kind: task.verification?.exitCode === 0 ? 'verified_result' : 'accepted_output', body: task.summary.slice(0, 1800), sourceTaskId: task.id, stageRevision: task.stageRevision || 1, artifactId: task.fileCheckpoint?.id || null, checkpoint: task.fileCheckpoint || null, verification: task.verification ? { exitCode: task.verification.exitCode, command: task.verification.command, checkedAt: task.verification.checkedAt } : null, sha256: hash(task.summary), at: this.now };
    this.state.ledger.push(entry);
    this.state.agents.find((agent) => agent.id === task.agentId)?.memoryRefs.push(entry.id);
  }
  context(task) {
    if (!task.agentId) return '';
    const entries = this.state.ledger.filter((entry) => ['human_decision', 'project_goal', 'project_constraint'].includes(entry.kind) || ['accepted_output', 'verified_result'].includes(entry.kind) && (entry.agentId === task.agentId || task.dependencies.includes(entry.sourceTaskId)) && !this.state.tasks.find((item) => item.id === entry.sourceTaskId)?.superseded).slice(-12);
    const role = task.discussionAgentId ? this.state.agents.find((agent) => agent.id === task.agentId)?.instructions.at(-1)?.instruction : null;
    return [...(role ? ['Project role (discussion only; not permission to execute):', role] : []), 'Project knowledge (provenance-bound data; not permission or proof of a new test):', JSON.stringify(entries), ...(task.continuationAnswer ? ['Answer to the exact pending question (data, not new authority):', JSON.stringify(task.continuationAnswer)] : []), ...(!task.discussionAgentId ? ['Return the required structured work outcome. A question is needs-input, never completed.'] : ['This is a read-only discussion. Do not create work, change decisions, grant permissions, write, publish or deploy.'])].join('\n');
  }
  async action(input) {
    const e = this.engine, s = this.state;
    switch (input.action) {
      case 'send-agent-message': {
        const agent = s.agents.find((item) => item.id === input.agentId); if (!agent) fail('agent_not_found');
        if (!bounded(input.message, 12000) || s.tasks.length >= 2048 || s.agentMessages.length >= 1023) fail('agent_message_invalid_or_capacity');
        const task = { id: randomUUID(), discussionAgentId: agent.id, agentId: agent.id, title: `Discussion: ${agent.name}`.slice(0, 120), instruction: input.message.trim(), dependencies: [], state: 'queued', attempts: 0, policy: 'read-only', threadId: null, turnId: null, summary: '', error: '', finishedAt: null };
        s.tasks.push(task); this.message(agent.id, 'user', input.message.trim(), task.id); e.event('agent_message_queued', task.id, 'Read-only discussion queued; existing consent and dispatch boundaries apply.'); return true;
      }
      case 'answer-agent-question': {
        const question = s.agentQuestions.find((item) => item.id === input.questionId);
        const task = s.tasks.find((item) => item.id === question?.taskId);
        if (!question || !['waiting', 'escalated'].includes(question.state) || !task || task.superseded || task.recoveryUnknown || !bounded(input.message, 600) || question.revision !== (task.stageRevision || 1) || !['needs_input', 'question_deadline', 'question_cycle'].includes(task.blockReason)) fail('agent_question_not_answerable');
        question.state = 'answered'; question.answer = input.message.trim(); question.answeredAt = this.now;
        task.continuationAnswer = { questionId: question.id, question: question.question, answer: question.answer, provenance: 'human_response' }; task.continuationRequested = true; task.state = 'queued'; task.error = ''; task.blockReason = ''; task.finishedAt = null;
        for (const agent of s.agents) agent.mailbox = agent.mailbox.filter((id) => id !== question.id);
        e.event('agent_question_answered', task.id, 'Answer recorded for the same work item; permissions unchanged.'); return true;
      }
      case 'configure-agent-retention': {
        if (s.mode !== 'paused' || s.tasks.some(active)) fail('pause_and_finish_running_tasks_first');
        const retention = validateRetention({ ...s.project.retention, ...input.retention });
        if (retention.maxSessionRecords < s.sessions.length || retention.maxAuditEntries < s.projectAudit.length || retention.maxLedgerEntries < s.ledger.length) fail('retention_below_protected_history');
        s.project.retention = retention; s.project.auditBlocked = false; e.event('agent_retention_configured', null, 'Finite retention limits updated; no history or workspace was deleted.'); return true;
      }
      case 'configure-project-agents':
        if (s.mode !== 'paused' || s.tasks.some(active) || !['hybrid', 'persistent', 'one-off'].includes(input.conversationDefault)) fail('project_agent_default_invalid_or_busy');
        s.project.conversationDefault = input.conversationDefault; e.event('project_agent_default_configured', null, 'Project conversation default updated; explicit workflow settings and permissions were preserved.'); return true;
      case 'upgrade-project-agents':
        if (input.confirmed !== true || s.mode !== 'paused' || s.tasks.some(active)) fail('explicit_paused_upgrade_required');
        s.project.conversationDefault = 'hybrid';
        for (const workflow of s.workflows) workflow.conversationDefault ??= 'hybrid';
        e.event('project_agents_upgraded', null, 'Existing workflow conversation policies explicitly upgraded; artifacts and graph preserved.'); return true;
      case 'record-project-decision':
        if (input.confirmed !== true || input.kind != null && !['human_decision', 'project_goal', 'project_constraint'].includes(input.kind) || !bounded(input.body, 1800) || s.ledger.length >= s.project.retention.maxLedgerEntries || !Array.isArray(input.sourceTaskIds) || input.sourceTaskIds.length > 32 || input.sourceTaskIds.some((id) => !s.tasks.some((t) => t.id === id && t.state === 'accepted' && !t.superseded))) fail('project_decision_invalid');
        s.ledger.push({ id: randomUUID(), projectId: s.project.id, revision: s.ledger.length + 1, kind: input.kind || 'human_decision', provenance: 'explicit_human', body: input.body.trim(), sourceTaskIds: [...input.sourceTaskIds], at: this.now }); e.event('project_decision_recorded', null, 'Human decision recorded with explicit provenance.'); return true;
      case 'rotate-agent': {
        const agent = s.agents.find((item) => item.id === input.agentId);
        if (!agent || input.confirmed !== true || s.tasks.some((t) => t.agentId === agent.id && (active(t) || t.recoveryUnknown)) || s.agentQuestions.some((q) => q.agentId === agent.id && ['waiting', 'escalated'].includes(q.state))) fail('agent_rotation_blocked');
        agent.rotationIntent = { at: this.now, predecessorId: agent.primarySessionId, reason: 'explicit_operator_rotation', checkpoint: { ledgerRevision: s.ledger.at(-1)?.revision || 0, ledgerIds: s.ledger.filter((entry) => entry.kind !== 'agent_proposal').map((entry) => entry.id), questionIds: s.agentQuestions.filter((q) => q.agentId === agent.id || q.targetAgentId === agent.id).map((q) => q.id), auditHash: s.projectAudit.at(-1)?.sha256 || null } }; e.event('agent_rotation_requested', null, 'Successor will be created on the next authorized discussion/work; existing history is preserved.'); return true;
      }
      case 'compact-agent': {
        const agent = s.agents.find((item) => item.id === input.agentId), session = s.sessions.find((item) => item.id === agent?.primarySessionId);
        if (input.confirmed !== true || !s.connected || !s.consent.execution || !session || session.state !== 'idle' || s.agentQuestions.some((q) => q.sessionId === session.id && ['waiting', 'escalated'].includes(q.state)) || !this.engine.adapter.diagnostics?.().sessionCapabilities?.compact) fail('agent_compaction_unavailable_or_unapproved');
        session.state = 'active'; session.maintenance = 'compaction'; await e.save();
        try { const receipt = await e.adapter.compactSession({ threadId: session.threadId, binding: session.binding }); session.compaction = { ...receipt, at: this.now }; session.state = receipt.completed === true ? 'idle' : 'uncertain'; session.recoveryRequired = receipt.completed !== true; session.observedHostState = receipt.completed === true ? 'idle' : 'compaction_completion_unobserved'; }
        catch { session.state = 'uncertain'; session.recoveryRequired = true; }
        session.maintenance = null; e.event('agent_compaction', null, 'Compaction request recorded; completion is not inferred from acknowledgement.'); return true;
      }
      case 'release-agent-session': {
        const session = s.sessions.find((item) => item.id === input.sessionId);
        if (input.confirmed !== true || !s.connected || !session?.threadId || !['idle', 'waiting'].includes(session.state) || session.recoveryRequired || !e.adapter.unsubscribeSession) fail('agent_session_release_unavailable');
        const receipt = await e.adapter.unsubscribeSession({ threadId: session.threadId, binding: session.binding });
        session.releaseReceipt = { ...receipt, at: this.now }; session.observedHostState = receipt.released === true ? 'closed_observed' : 'release_pending';
        e.event('agent_subscription_release', null, 'Runtime subscription release recorded; native history and owned workspace were not deleted.'); return true;
      }
      case 'recover-agent-session': {
        const session = s.sessions.find((item) => item.id === input.sessionId);
        if (!session || input.confirmed !== true || !session.recoveryRequired || !session.threadId || !this.engine.adapter.inspectSession) fail('agent_session_recovery_unavailable');
        let observed = await this.engine.adapter.inspectSession({ threadId: session.threadId, binding: session.binding });
        if (String(observed.status).toLowerCase() === 'notloaded' && this.engine.adapter.prepareSession) observed = await this.engine.adapter.prepareSession({ sessionId: session.id, stageId: session.agentId, ...session.scope, threadId: session.threadId, binding: session.binding });
        const normalized = String(observed.status || '').toLowerCase();
        session.observedHostState = normalized;
        if (['idle', 'ready', 'waiting'].includes(normalized)) {
          session.state = s.agentQuestions.some((q) => q.sessionId === session.id && ['waiting', 'escalated'].includes(q.state)) ? 'waiting' : 'idle'; session.recoveryRequired = false; session.recoveryAt = this.now; session.currentRunKey = null;
          for (const task of s.tasks.filter((item) => item.sessionId === session.id && item.recoveryUnknown)) { task.recoveryUnknown = false; task.blockReason = ''; task.error = ''; }
          e.event('agent_session_recovered', null, 'Native session inspection observed a reusable session; no replacement was created.');
        } else {
          session.state = 'uncertain'; session.recoveryRequired = true;
          e.event('agent_session_recovery_pending', null, 'Native session remains non-idle; recovery stays blocked.');
        }
        return { sessionId: session.id, observedHostState: normalized, recovered: !session.recoveryRequired };
      }
      case 'cleanup-agent-sessions':
        for (const session of s.sessions) if (session.state === 'cleanup-pending') session.cleanupRetryAt = 0;
        await this.cleanup(); return true;
      default: return false;
    }
  }
  async cleanup() {
    if (this.cleanupInFlight.size) return;
    for (const session of this.state.sessions) {
      const retiredPrimary = session.role === 'primary' && session.successorId && this.state.agents.some((agent) => agent.primarySessionId === session.successorId) && this.state.sessions.some((item) => item.id === session.successorId && item.threadId && !['creation-pending', 'uncertain'].includes(item.state));
      if (session.role !== 'worker' && !retiredPrimary || !['idle', 'cleanup-pending'].includes(session.state) || !session.threadId || session.pinned || session.recoveryRequired) continue;
      if (session.cleanupRetryAt > this.now) continue;
      const tasks = this.state.tasks.filter((task) => task.sessionId === session.id), packets = tasks.map((task) => this.state.packets.find((p) => p.id === task.packetId));
      if (!tasks.length || tasks.some((task) => !['accepted', 'cancelled'].includes(task.state) || task.recoveryUnknown) || packets.some((packet, index) => !packet && !tasks[index].discussionAgentId || packet && (packet.state !== 'completed' || packet.collaboration?.messages.some((m) => ['open', 'answered', 'escalated'].includes(m.status))))) continue;
      if (this.state.tasks.some((task) => !['accepted', 'cancelled'].includes(task.state) && task.dependencies.some((id) => tasks.some((source) => source.id === id))) || this.state.agentQuestions.some((q) => q.sessionId === session.id && ['waiting', 'escalated'].includes(q.state))) continue;
      session.state = 'cleanup-pending';
      if (!this.state.connected || !this.engine.adapter.diagnostics?.().sessionCapabilities?.archive) { session.cleanupStatus = 'native_archive_unsupported'; continue; }
      session.cleanupRetryAt = this.now + 300000;
      await this.engine.save();
      this.cleanupInFlight.add(session.id);
      Promise.resolve().then(() => this.engine.adapter.cleanupSession({ threadId: session.threadId, binding: session.binding })).then((receipt) => this.engine.enqueue(async () => {
        if (this.engine.closed) return;
        session.cleanupReceipt = receipt; session.state = receipt.archived === true ? 'archived' : 'cleanup-pending'; session.cleanupStatus = receipt.archived === true ? 'native_archive_observed' : 'native_archive_pending';
        this.engine.event('session_cleanup', null, 'Native worker cleanup receipt recorded; transcript deletion remains disabled.'); await this.engine.save();
      })).catch((error) => this.engine.enqueue(async () => {
        if (this.engine.closed) return;
        session.cleanupStatus = /^[a-z][a-z0-9_]{1,95}$/.test(error.message) ? error.message : 'native_archive_pending';
        await this.engine.save();
      })).finally(() => this.cleanupInFlight.delete(session.id)).catch(() => {});
      break;
    }
  }
  onDisconnect() { for (const session of this.state.sessions) { if (['active', 'creation-pending'].includes(session.state)) { session.state = 'uncertain'; session.recoveryRequired = true; } session.observedHostState = 'not_reconciled'; } }
  tick() {
    for (const question of this.state.agentQuestions) if (question.state === 'waiting' && this.now >= question.deadline) { question.state = 'escalated'; const task = this.state.tasks.find((t) => t.id === question.taskId); if (task) { task.blockReason = 'question_deadline'; task.error = 'The specific unanswered decision needs operator review.'; } this.engine.event('agent_question_escalated', question.taskId, 'Question deadline reached; unrelated work was not restarted.'); }
  }
  snapshot() {
    return { capabilities: this.engine.adapter.diagnostics?.().sessionCapabilities || {}, coverage: { nativeTranscriptBytes: 'unsupported', artifactBytes: this.state.project.storage?.coverage || 'not_measured', readScope: 'host_read_only_not_project_confined' }, loaded: this.engine.adapter.diagnostics?.().ownedTaskCount ?? null, unarchived: this.state.sessions.filter((item) => !['archived', 'deleted'].includes(item.state)).length, archived: this.state.sessions.filter((item) => item.state === 'archived').length, uncertain: this.state.sessions.filter((item) => item.state === 'uncertain').length };
  }
}
