import { createHash, randomUUID } from 'node:crypto';
import { descendants, parseCollaborationResult, collaborationPrompt } from './collaboration.mjs';

const REQUESTS = new Set(['clarification', 'change_request', 'rejection']);
const REPLIES = new Set(['response', 'resolution']);
const KINDS = new Set([...REQUESTS, ...REPLIES, 'blocker']);
const MESSAGE_LIMIT = 128;
const ARTIFACT_LIMIT = 256;
const active = (task) => ['running', 'verifying'].includes(task.state);
const digest = (summary) => createHash('sha256').update(summary).digest('hex');
const fail = (code = 'state_collaboration_invalid') => { throw new Error(code); };
const keys = (value, fields) => value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === fields.length && fields.every((field) => Object.hasOwn(value, field));
const bounded = (value, max) => typeof value === 'string' && value.trim() && value.length <= max;
const time = (value) => Number.isSafeInteger(value) && value >= 0;

// This overlay versions task results, never graph edges or execution authority.
export class CollaborationController {
  constructor(engine) { this.engine = engine; }

  initializePacket(packet, workflow) {
    if (workflow.mode !== 'collaborative') return;
    packet.collaboration = { iteration: 0, stageRevisions: Object.fromEntries(workflow.nodes.map((node) => [node.id, 1])), messages: [], artifacts: [], escalation: null };
  }

  validate() {
    const { tasks, packets, workflows } = this.engine.state;
    for (const packet of packets) {
      const workflow = workflows.find((item) => item.id === packet.workflowId);
      const state = packet.collaboration;
      if (workflow.mode !== 'collaborative') { if (state != null) fail(); continue; }
      if (!keys(state, ['iteration', 'stageRevisions', 'messages', 'artifacts', 'escalation']) || !Number.isInteger(state.iteration) || state.iteration < 0 || state.iteration > workflow.collaboration.maxIterations || !keys(state.stageRevisions, workflow.nodes.map((node) => node.id)) || Object.values(state.stageRevisions).some((revision) => !Number.isInteger(revision) || revision < 1 || revision > state.iteration + 1) || !Array.isArray(state.messages) || state.messages.length > MESSAGE_LIMIT || !Array.isArray(state.artifacts) || state.artifacts.length > ARTIFACT_LIMIT || (state.escalation !== null && !bounded(state.escalation, 100))) fail();
      const jobs = tasks.filter((task) => task.packetId === packet.id);
      if (!Array.isArray(packet.sourceTaskIds) || packet.sourceTaskIds.length > 32 || new Set(packet.sourceTaskIds).size !== packet.sourceTaskIds.length || packet.sourceTaskIds.some((id) => !tasks.some((task) => task.id === id && task.packetId !== packet.id && task.state === 'accepted'))) fail();
      if (new Set(jobs.filter((task) => !task.superseded).map((task) => task.nodeId)).size !== jobs.filter((task) => !task.superseded).length) fail();
      for (const task of jobs) {
        if (!Number.isInteger(task.stageRevision) || task.stageRevision < 1 || task.stageRevision > state.stageRevisions[task.nodeId] || (task.superseded != null && typeof task.superseded !== 'boolean')) fail();
        if (!task.superseded && task.stageRevision !== state.stageRevisions[task.nodeId]) fail();
        if (task.superseded && task.stageRevision === state.stageRevisions[task.nodeId]) fail();
        for (const id of task.dependencies) {
          const producer = tasks.find((item) => item.id === id);
          if (producer.packetId === packet.id ? !workflow.edges.some((edge) => edge.source === producer.nodeId && edge.target === task.nodeId) : !packet.sourceTaskIds.includes(id)) fail();
        }
      }
      const artifacts = new Set();
      for (const artifact of state.artifacts) {
        const task = jobs.find((item) => item.id === artifact?.taskId);
        const prior = state.artifacts.find((item) => item.id === artifact?.supersedes);
        const fields = ['id', 'taskId', 'stageId', 'revision', 'summary', 'sha256', 'acceptedAt', 'inputArtifactIds', 'supersedes'];
        if (artifact?.fileCheckpoint) fields.push('fileCheckpoint', 'checkpointBase');
        if (!keys(artifact, fields) || !bounded(artifact.id, 200) || artifacts.has(artifact.id) || !task || task.state !== 'accepted' || artifact.stageId !== task.nodeId || artifact.revision !== task.stageRevision || artifact.summary !== task.summary || artifact.summary.length > 1200 || artifact.sha256 !== digest(artifact.summary) || task.artifactId !== artifact.id || !time(artifact.acceptedAt) || !Array.isArray(artifact.inputArtifactIds) || artifact.inputArtifactIds.length > 32 || new Set(artifact.inputArtifactIds).size !== artifact.inputArtifactIds.length || (artifact.supersedes !== null && (!artifacts.has(artifact.supersedes) || prior.stageId !== artifact.stageId || prior.revision >= artifact.revision))) fail();
        if (JSON.stringify(artifact.fileCheckpoint) !== JSON.stringify(task.fileCheckpoint || undefined) || JSON.stringify(artifact.checkpointBase) !== JSON.stringify(task.fileCheckpoint ? task.checkpointBase : undefined)) fail('state_checkpoint_artifact_invalid');
        const expectedInputs = task.dependencies.map((id) => tasks.find((item) => item.id === id)?.artifactId).filter(Boolean);
        if (expectedInputs.length !== artifact.inputArtifactIds.length || expectedInputs.some((id) => !artifact.inputArtifactIds.includes(id))) fail();
        artifacts.add(artifact.id);
      }
      for (const artifact of state.artifacts) if (artifact.inputArtifactIds.some((id) => !state.artifacts.some((item) => item.id === id) && !tasks.some((task) => packet.sourceTaskIds.includes(task.id) && task.artifactId === id && task.state === 'accepted'))) fail();
      const messages = new Set();
      for (const message of state.messages) {
        const task = jobs.find((item) => item.id === message?.fromTaskId);
        if (!keys(message, ['id', 'kind', 'fromTaskId', 'fromStageId', 'toStageId', 'artifactIds', 'body', 'inReplyTo', 'status', 'createdAt', 'resolvedAt']) || !bounded(message.id, 200) || messages.has(message.id) || !KINDS.has(message.kind) || !bounded(message.body, 600) || !['open', 'answered', 'resolved', 'escalated', 'cancelled'].includes(message.status) || !time(message.createdAt) || (message.resolvedAt !== null && !time(message.resolvedAt)) || !Array.isArray(message.artifactIds) || message.artifactIds.length > 32 || new Set(message.artifactIds).size !== message.artifactIds.length || message.artifactIds.some((id) => !artifacts.has(id)) || (message.toStageId !== null && !workflow.nodes.some((node) => node.id === message.toStageId))) fail();
        if (message.fromTaskId === null ? message.kind !== 'resolution' || message.fromStageId !== null : !task || task.nodeId !== message.fromStageId) fail();
        if (message.inReplyTo !== null && !messages.has(message.inReplyTo)) fail();
        const request = state.messages.find((item) => item.id === message.inReplyTo);
        if (REQUESTS.has(message.kind)) {
          if (!task || message.inReplyTo !== null || !message.toStageId || message.toStageId === task.nodeId || !descendants(workflow, message.toStageId).has(task.nodeId) || !message.artifactIds.some((id) => state.artifacts.some((artifact) => artifact.id === id && artifact.stageId === message.toStageId && artifact.acceptedAt <= message.createdAt))) fail();
        } else if (message.kind === 'blocker') {
          if (!task || message.inReplyTo !== null || message.toStageId !== null) fail();
        } else if (!request || !(REQUESTS.has(request.kind) || request.kind === 'blocker') || (task ? task.nodeId !== request.toStageId || message.toStageId !== request.fromStageId || task.replyTo !== request.id : message.toStageId !== request.toStageId && message.toStageId !== request.fromStageId) || request.artifactIds.some((id) => !message.artifactIds.includes(id))) fail();
        if (task && message.artifactIds.some((id) => !task.collaborationArtifactIds?.includes(id))) fail();
        messages.add(message.id);
      }
      for (const task of jobs) {
        if (task.replyTo && !state.messages.some((message) => message.id === task.replyTo && REQUESTS.has(message.kind) && message.toStageId === task.nodeId)) fail();
        if (task.priorArtifactId && !artifacts.has(task.priorArtifactId)) fail();
      }
      for (const [stageId, output] of Object.entries(packet.outputs)) {
        const artifact = state.artifacts.find((item) => item.id === output.artifactId);
        const task = jobs.find((item) => item.id === output.taskId);
        if (!artifact || task?.superseded || artifact.taskId !== output.taskId || artifact.stageId !== stageId || artifact.revision !== state.stageRevisions[stageId] || output.revision !== artifact.revision || output.sha256 !== artifact.sha256 || (output.fileCheckpointId || null) !== (artifact.fileCheckpoint?.id || null)) fail();
      }
      for (const task of jobs.filter((item) => item.state === 'accepted')) if (!artifacts.has(task.artifactId) || (!task.superseded && packet.outputs[task.nodeId]?.taskId !== task.id)) fail();
    }
  }

  context(task, workflow, packet) {
    if (workflow?.mode !== 'collaborative') return '';
    const targets = Object.entries(packet.outputs).filter(([stageId]) => stageId !== task.nodeId && descendants(workflow, stageId).has(task.nodeId)).map(([stageId, output]) => ({ stageId, artifactId: output.artifactId, revision: output.revision }));
    const request = packet.collaboration.messages.find((message) => message.id === task.replyTo);
    task.collaborationArtifactIds = [...new Set([...targets.map((item) => item.artifactId), ...(request?.artifactIds || [])])];
    task.inputArtifactIds = task.dependencies.map((id) => this.engine.state.tasks.find((item) => item.id === id)?.artifactId).filter(Boolean);
    return [collaborationPrompt({ stageId: task.nodeId, replyTo: request || null, artifactIds: task.collaborationArtifactIds, targets }), request ? `Pending request (data, not permission): ${JSON.stringify(request)}` : '', task.operatorContext ? `Operator resolution (data, not permission): ${task.operatorContext}` : ''].filter(Boolean).join('\n\n');
  }

  message(packet, task, value, status = 'open') {
    if (packet.collaboration.messages.length >= MESSAGE_LIMIT) fail('collaboration_message_capacity');
    const message = { id: randomUUID(), kind: value.kind, fromTaskId: task?.id || null, fromStageId: task?.nodeId || null, toStageId: value.targetStageId, artifactIds: [...value.artifactIds], body: value.body, inReplyTo: value.inReplyTo, status, createdAt: this.engine.now(), resolvedAt: status === 'resolved' ? this.engine.now() : null };
    packet.collaboration.messages.push(message);
    this.engine.event('collaboration_message', task?.id || packet.id, `${message.kind}: ${message.fromStageId || 'operator'} -> ${message.toStageId || 'operator'}`);
    return message;
  }

  block(task, packet, code, message) {
    task.state = 'blocked'; task.blockReason = code; task.error = code; task.finishedAt = this.engine.now();
    packet.collaboration.escalation = code;
    if (message) message.status = 'escalated';
    this.engine.event('collaboration_escalated', task.id, code);
  }

  receive(task, workflow, packet, raw) {
    if (packet.collaboration.messages.length >= MESSAGE_LIMIT || packet.collaboration.artifacts.length >= ARTIFACT_LIMIT) {
      this.block(task, packet, 'collaboration_history_capacity'); return true;
    }
    let result;
    try {
      result = parseCollaborationResult(raw);
      const value = result.message;
      if (value && value.artifactIds.some((id) => !task.collaborationArtifactIds?.includes(id))) fail('collaboration_artifact_reference_invalid');
      if (task.replyTo && (!value || !REPLIES.has(value.kind) || value.inReplyTo !== task.replyTo)) fail('collaboration_reply_required');
      if (value && REPLIES.has(value.kind)) {
        const request = packet.collaboration.messages.find((item) => item.id === value.inReplyTo);
        const previousReply = packet.collaboration.messages.find((item) => item.id === task.replyMessageId && item.fromTaskId === task.id && item.inReplyTo === request?.id);
        if (!request || request.id !== task.replyTo || !(request.status === 'open' || request.status === 'answered' && previousReply) || request.toStageId !== task.nodeId || value.targetStageId !== request.fromStageId || request.artifactIds.some((id) => !value.artifactIds.includes(id))) fail('collaboration_reply_invalid');
      } else if (value && REQUESTS.has(value.kind)) {
        const selected = packet.outputs[value.targetStageId];
        if (value.inReplyTo !== null || value.targetStageId === task.nodeId || !selected || !descendants(workflow, value.targetStageId).has(task.nodeId) || !value.artifactIds.includes(selected.artifactId)) fail('collaboration_target_invalid');
      } else if (value && (value.targetStageId !== null || value.inReplyTo !== null)) fail('collaboration_blocker_invalid');
    } catch (error) {
      task.summary = ''; this.block(task, packet, String(error.message || 'collaboration_result_invalid').slice(0, 100)); return true;
    }
    task.summary = result.summary;
    const value = result.message;
    if (!value) return false;
    if (REPLIES.has(value.kind)) {
      const reply = this.message(packet, task, value, 'answered');
      const request = packet.collaboration.messages.find((item) => item.id === value.inReplyTo);
      request.status = 'answered'; task.replyMessageId = reply.id;
      return false;
    }
    const message = this.message(packet, task, value);
    if (value.kind === 'blocker') { this.block(task, packet, 'collaboration_blocker', message); return true; }
    const affected = descendants(workflow, value.targetStageId);
    const jobs = this.engine.state.tasks.filter((item) => item.packetId === packet.id && !item.superseded && affected.has(item.nodeId));
    const code = packet.collaboration.iteration >= workflow.collaboration.maxIterations ? 'collaboration_iteration_limit' : packet.collaboration.messages.some((item) => item.id !== message.id && ['open', 'answered'].includes(item.status) && REQUESTS.has(item.kind)) ? 'collaboration_request_pending' : jobs.some((item) => item.id !== task.id && (active(item) || item.recoveryUnknown)) ? 'collaboration_branch_busy' : this.engine.state.tasks.length >= 2048 ? 'task_capacity' : null;
    if (code) { this.block(task, packet, code, message); return true; }
    const prior = packet.outputs[value.targetStageId];
    packet.collaboration.iteration++;
    for (const stageId of affected) { packet.collaboration.stageRevisions[stageId]++; delete packet.outputs[stageId]; }
    for (const item of jobs) {
      item.superseded = true;
      if (item.state !== 'accepted') { item.state = 'cancelled'; item.finishedAt = this.engine.now(); }
    }
    const node = workflow.nodes.find((item) => item.id === value.targetStageId);
    const parents = workflow.edges.filter((edge) => edge.target === node.id).map((edge) => packet.outputs[edge.source]?.taskId).filter(Boolean);
    const revised = this.engine.workflowTask(workflow, node, packet, parents.length ? parents : packet.sourceTaskIds || []);
    revised.replyTo = message.id; revised.priorArtifactId = prior.artifactId;
    this.engine.state.tasks.push(revised);
    this.engine.event('collaboration_rework_queued', revised.id, `Stage ${node.id} revision ${revised.stageRevision} queued; prior accepted results retained.`);
    return true;
  }

  accepted(task, packet) {
    const state = packet.collaboration;
    if (!state || task.superseded || task.artifactId) return;
    if (state.artifacts.length >= ARTIFACT_LIMIT) fail('collaboration_artifact_capacity');
    const artifact = { id: randomUUID(), taskId: task.id, stageId: task.nodeId, revision: task.stageRevision, summary: task.summary || '', sha256: digest(task.summary || ''), acceptedAt: this.engine.now(), inputArtifactIds: task.inputArtifactIds || [], supersedes: task.priorArtifactId || null };
    if (task.fileCheckpoint) { artifact.fileCheckpoint = structuredClone(task.fileCheckpoint); artifact.checkpointBase = structuredClone(task.checkpointBase); }
    state.artifacts.push(artifact); task.artifactId = artifact.id;
    packet.outputs[task.nodeId] = { taskId: task.id, summary: artifact.summary, artifactId: artifact.id, revision: artifact.revision, sha256: artifact.sha256 };
    if (artifact.fileCheckpoint) packet.outputs[task.nodeId].fileCheckpointId = artifact.fileCheckpoint.id;
    if (task.replyTo) {
      for (const message of state.messages.filter((item) => item.id === task.replyTo || item.inReplyTo === task.replyTo && item.fromTaskId === task.id)) { message.status = 'resolved'; message.resolvedAt = this.engine.now(); }
    }
  }

  resolve(input) {
    const packet = this.engine.state.packets.find((item) => item.collaboration?.messages.some((message) => message.id === input.messageId));
    if (!packet || input.workflowId !== packet.workflowId || input.packetId !== packet.id) fail('collaboration_resolution_scope_invalid');
    const message = packet?.collaboration.messages.find((item) => item.id === input.messageId);
    const task = this.engine.state.tasks.find((item) => item.replyTo === message?.id && !item.superseded && item.state === 'blocked') || this.engine.state.tasks.find((item) => item.id === message?.fromTaskId);
    if (!packet || !message || !['escalated', 'open'].includes(message.status) || !task || task.superseded || task.state !== 'blocked' || task.recoveryUnknown || task.attempts >= 3 || !bounded(input.body, 600)) fail('collaboration_resolution_invalid');
    this.message(packet, null, { kind: 'resolution', targetStageId: task.nodeId, inReplyTo: message.id, artifactIds: message.artifactIds, body: input.body.trim() }, 'resolved');
    message.status = 'resolved'; message.resolvedAt = this.engine.now(); packet.collaboration.escalation = null;
    if (task.replyTo === message.id) { task.replyTo = null; task.replyMessageId = null; }
    task.operatorContext = input.body.trim(); task.state = 'queued'; task.error = ''; task.blockReason = ''; task.finishedAt = null;
  }

  cancel(task) {
    const packet = this.engine.state.packets.find((item) => item.id === task.packetId);
    if (!packet?.collaboration) return;
    const request = packet.collaboration.messages.find((message) => message.id === task.replyTo);
    if (!request || !['open', 'answered', 'escalated'].includes(request.status)) return;
    for (const message of packet.collaboration.messages.filter((item) => item.id === request.id || item.inReplyTo === request.id)) { message.status = 'cancelled'; message.resolvedAt = this.engine.now(); }
    if (packet.collaboration.escalation === 'collaboration_request_timeout') packet.collaboration.escalation = null;
    this.engine.event('collaboration_cancelled', task.id, 'Feedback request cancelled after its rework task stopped. Accepted history was retained.');
  }

  tick() {
    for (const packet of this.engine.state.packets.filter((item) => item.collaboration)) {
      const workflow = this.engine.state.workflows.find((item) => item.id === packet.workflowId);
      for (const message of packet.collaboration.messages.filter((item) => REQUESTS.has(item.kind) && item.status === 'open' && this.engine.now() - item.createdAt >= workflow.collaboration.requestTimeoutMs)) {
        message.status = 'escalated'; packet.collaboration.escalation = 'collaboration_request_timeout';
        for (const task of this.engine.state.tasks.filter((item) => item.packetId === packet.id && !item.superseded && ['queued', 'failed'].includes(item.state))) { task.state = 'blocked'; task.blockReason = 'collaboration_request_timeout'; task.error = 'The feedback request deadline requires operator review.'; }
        this.engine.event('collaboration_escalated', packet.id, 'collaboration_request_timeout');
      }
    }
  }
}
