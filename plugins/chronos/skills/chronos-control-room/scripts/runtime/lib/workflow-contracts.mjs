const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const identifier = (value) => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,100}$/.test(value) && !['__proto__', 'constructor', 'prototype'].includes(value);
const bounded = (value, limit) => typeof value === 'string' && value.trim().length > 0 && value.length <= limit;
const collaborationModes = new Set(['collaborative']);
const conversationModes = new Set(['inherit', 'persistent', 'one-off', 'hybrid']);
const taskComplexities = new Set(['low', 'medium', 'high']);
const sourceHandles = new Set(['out-left', 'out-right', 'out-top', 'out-bottom']);
const targetHandles = new Set(['in-left', 'in-right', 'in-top', 'in-bottom']);
export function parseThreadLink(value) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || !value.startsWith('codex://threads/')) throw new Error('source_thread_link_invalid');
  const id = value.slice('codex://threads/'.length);
  if (!UUID.test(id)) throw new Error('source_thread_link_invalid');
  return value;
}
export function validateWorkflow(workflow) {
  if (!workflow || typeof workflow !== 'object' || !identifier(workflow.id) || !bounded(workflow.name, 120) || !Array.isArray(workflow.nodes) || !Array.isArray(workflow.edges)) throw new Error('workflow_invalid');
  if (workflow.nodes.length > (workflow.mode === 'collaborative' ? 32 : 512) || workflow.edges.length > 4096) throw new Error('workflow_capacity');
  const ids = new Set();
  const collaborative = workflow.mode === 'collaborative';
  if (workflow.mode != null && workflow.mode !== 'structured' && !collaborationModes.has(workflow.mode)) throw new Error('collaboration_mode_invalid');
  if (!collaborative && workflow.collaboration != null) throw new Error('collaboration_config_invalid');
  if (workflow.config != null && (!workflow.config || typeof workflow.config !== 'object' || Array.isArray(workflow.config))) throw new Error('collaboration_config_invalid');
  if (workflow.conversationDefault != null && !conversationModes.has(workflow.conversationDefault)) throw new Error('conversation_mode_invalid');
  const collaboration = collaborative ? normalizeCollaboration(workflow) : null;
  const nodes = workflow.nodes.map((node, index) => {
    if (!node || !identifier(node.id) || ids.has(node.id) || !bounded(node.title, 120) || !bounded(node.instruction, 12000) || (node.kind != null && node.kind !== 'task')) throw new Error('workflow_node_invalid');
    const policy = node.policy ?? 'read-only', slots = node.slots ?? 1, routing = node.routing ?? 'auto', join = node.join ?? 'all', maxAttempts = node.maxAttempts ?? 1;
    const verificationCommand = node.verificationCommand ?? [];
    if (!['read-only', 'workspace-write'].includes(policy) || !Number.isInteger(slots) || slots < 1 || slots > 16 || !['auto', 'approval'].includes(routing) || !['any', 'all'].includes(join) || !Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 3 || !Array.isArray(verificationCommand) || verificationCommand.length > 32 || verificationCommand.some((arg) => !bounded(arg, 2000))) throw new Error('workflow_node_invalid');
    if (node.model != null && !bounded(node.model, 120)) throw new Error('workflow_model_invalid');
    if (node.reasoningEffort != null && !bounded(node.reasoningEffort, 80)) throw new Error('workflow_reasoning_effort_invalid');
    if (node.conversationMode != null && !conversationModes.has(node.conversationMode)) throw new Error('conversation_mode_invalid');
    if (node.agentId != null && !identifier(node.agentId)) throw new Error('agent_reference_invalid');
    if (node.complexity != null && !taskComplexities.has(node.complexity)) throw new Error('task_complexity_invalid');
    if (node.independentReview != null && typeof node.independentReview !== 'boolean') throw new Error('workflow_node_invalid');
    if (node.webSearch != null && typeof node.webSearch !== 'boolean') throw new Error('workflow_node_invalid');
    const position = node.position ?? { x: 80 + (index % 5) * 300, y: 120 + Math.floor(index / 5) * 200 };
    if (!position || !Number.isFinite(position.x) || !Number.isFinite(position.y) || Math.abs(position.x) > 100000 || Math.abs(position.y) > 100000) throw new Error('workflow_position_invalid');
    ids.add(node.id);
    return { id: node.id, title: node.title.trim(), kind: 'task', instruction: node.instruction.trim(), policy, slots, routing, join, maxAttempts, model: node.model || null, reasoningEffort: node.reasoningEffort || null, webSearch: node.webSearch === true, verificationCommand: [...verificationCommand], position: { x: position.x, y: position.y }, ...(node.conversationMode != null ? { conversationMode: node.conversationMode } : {}), ...(node.agentId != null ? { agentId: node.agentId } : {}), ...(node.complexity != null ? { complexity: node.complexity } : {}), ...(node.independentReview != null ? { independentReview: node.independentReview } : {}) };
  });
  const indegree = new Map([...ids].map((id) => [id, 0]));
  const edges = new Set(); const pairs = new Set();
  for (const edge of workflow.edges) {
    if (!edge || !identifier(edge.id) || !ids.has(edge.source) || !ids.has(edge.target) || edge.source === edge.target || edges.has(edge.id) || pairs.has(`${edge.source}->${edge.target}`)) throw new Error('workflow_edge_invalid');
    if ((edge.sourceHandle != null && !sourceHandles.has(edge.sourceHandle)) || (edge.targetHandle != null && !targetHandles.has(edge.targetHandle))) throw new Error('workflow_edge_handle_invalid');
    edges.add(edge.id); indegree.set(edge.target, indegree.get(edge.target) + 1);
    pairs.add(`${edge.source}->${edge.target}`);
  }
  const queue = [...indegree].filter(([, n]) => n === 0).map(([id]) => id); let seen = 0;
  while (queue.length) { const id = queue.shift(); seen++; for (const edge of workflow.edges.filter((e) => e.source === id)) { indegree.set(edge.target, indegree.get(edge.target) - 1); if (!indegree.get(edge.target)) queue.push(edge.target); } }
  if (seen !== ids.size) throw new Error('workflow_cycle');
  const normalized = { id: workflow.id, name: workflow.name.trim(), nodes, edges: workflow.edges.map((edge) => ({ id: edge.id, source: edge.source, target: edge.target, ...(edge.sourceHandle != null ? { sourceHandle: edge.sourceHandle } : {}), ...(edge.targetHandle != null ? { targetHandle: edge.targetHandle } : {}) })) };
  // Omitted policy is intentionally preserved for legacy workflows. New setup/templates
  // supply `hybrid` explicitly so migration never changes existing behavior.
  if (workflow.conversationDefault != null) normalized.conversationDefault = workflow.conversationDefault;
  if (collaborative) { normalized.mode = 'collaborative'; normalized.collaboration = collaboration; }
  return normalized;
}

const collabConfigKeys = new Set(['maxIterations', 'requestTimeoutMs']);
const collabDefault = { maxIterations: 2, requestTimeoutMs: 900000 };
const integerBound = (value, min, max) => Number.isInteger(value) && value >= min && value <= max;

export function normalizeCollaboration(workflow) {
  if (!workflow || typeof workflow !== 'object') throw new Error('collaboration_config_invalid');
  if (workflow.mode == null) return null;
  if (workflow.mode !== 'collaborative') throw new Error('collaboration_mode_invalid');
  const raw = workflow.collaboration ?? workflow.config?.collaboration ?? {};
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('collaboration_config_invalid');
  if (Object.keys(raw).some((key) => !collabConfigKeys.has(key))) throw new Error('collaboration_config_invalid');
  const maxIterations = raw.maxIterations ?? collabDefault.maxIterations;
  const requestTimeoutMs = raw.requestTimeoutMs ?? collabDefault.requestTimeoutMs;
  if (!integerBound(maxIterations, 1, 5) || !integerBound(requestTimeoutMs, 1000, 3600000)) throw new Error('collaboration_config_invalid');
  return { maxIterations, requestTimeoutMs };
}
