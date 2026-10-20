// Pure canvas helpers. Positions are UI metadata only; execution follows the validated DAG.
export const SNAP_GRID = 24;

export function snapPosition(position, grid = SNAP_GRID) {
  const x = Number.isFinite(position?.x) ? position.x : 0;
  const y = Number.isFinite(position?.y) ? position.y : 0;
  return { x: Math.round(x / grid) * grid, y: Math.round(y / grid) * grid };
}

// Compare workflow meaning while ignoring canvas-only metadata.
export function workflowSemanticView(workflow) {
  if (!workflow) return null;
  const { name, nodes = [], edges = [], ...rest } = workflow;
  return {
    ...rest,
    nodes: nodes.map(({ position, ...node }) => node),
    edges: edges.map(({ sourceHandle, targetHandle, ...edge }) => edge)
  };
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.keys(value).sort().reduce((result, key) => { result[key] = canonical(value[key]); return result; }, {});
  return value;
}

export function isLayoutOnlyChange(draft, saved) {
  return Boolean(draft && saved && JSON.stringify(canonical(workflowSemanticView(draft))) === JSON.stringify(canonical(workflowSemanticView(saved))));
}

export function hasWorkflowEdits(draft, saved) {
  const normalized = (workflow) => ({
    ...workflow,
    edges: workflow.edges.map((edge) => ({ ...edge, sourceHandle: edge.sourceHandle || 'out-right', targetHandle: edge.targetHandle || 'in-left' }))
  });
  return JSON.stringify(canonical(normalized(draft))) !== JSON.stringify(canonical(normalized(saved)));
}

export function autoLayout(nodes, edges, options = {}) {
  const columnGap = options.columnGap || 300;
  const rowGap = options.rowGap || 192;
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const incoming = new Map(nodes.map((node) => [node.id, 0]));
  const outgoing = new Map(nodes.map((node) => [node.id, []]));
  for (const edge of edges) {
    if (!byId.has(edge.source) || !byId.has(edge.target) || edge.source === edge.target) continue;
    outgoing.get(edge.source).push(edge.target);
    incoming.set(edge.target, (incoming.get(edge.target) || 0) + 1);
  }
  const queue = nodes.filter((node) => !incoming.get(node.id)).map((node) => node.id);
  const level = new Map(queue.map((id) => [id, 0]));
  const seen = new Set();
  while (queue.length) {
    const id = queue.shift();
    if (seen.has(id)) continue;
    seen.add(id);
    for (const target of outgoing.get(id) || []) {
      level.set(target, Math.max(level.get(target) || 0, (level.get(id) || 0) + 1));
      incoming.set(target, incoming.get(target) - 1);
      if (incoming.get(target) === 0) queue.push(target);
    }
  }
  // Cyclic/invalid drafts stay visible and deterministic instead of disappearing.
  nodes.forEach((node, index) => { if (!level.has(node.id)) level.set(node.id, Math.max(0, Math.floor(index / 4))); });
  const rows = new Map();
  return nodes.map((node) => {
    const column = level.get(node.id) || 0;
    const row = rows.get(column) || 0;
    rows.set(column, row + 1);
    return { ...node, position: snapPosition({ x: 48 + column * columnGap, y: 48 + row * rowGap }) };
  });
}
