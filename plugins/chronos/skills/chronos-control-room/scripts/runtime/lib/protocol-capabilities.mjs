// Host capabilities are deliberately explicit. Unknown capabilities are never
// treated as permission to attach, mutate, or clean up a thread.
export function protocolMethods(schema) {
  const methods = new Set();
  const visit = (value) => {
    if (!value || typeof value !== 'object') return;
    if (value.method && Array.isArray(value.method.enum)) for (const method of value.method.enum) if (typeof method === 'string') methods.add(method);
    for (const child of Object.values(value)) visit(child);
  };
  visit(typeof schema === 'string' ? JSON.parse(schema) : schema);
  return methods;
}

export function protocolCapabilities(schema) {
  const methods = protocolMethods(schema);
  const root = typeof schema === 'string' ? JSON.parse(schema) : schema;
  const sourceKinds = root?.lifecycleContract?.sourceKinds || root?.definitions?.v2?.ThreadSourceKind?.enum || root?.definitions?.ThreadSourceKind?.enum;
  const thread = root?.lifecycleContract?.thread || root?.definitions?.v2?.Thread?.properties || root?.definitions?.Thread?.properties;
  const listResponse = root?.lifecycleContract?.listResponse || root?.definitions?.v2?.ThreadListResponse?.properties || root?.definitions?.ThreadListResponse?.properties;
  const listContract = Array.isArray(sourceKinds) && sourceKinds.length > 0 && Boolean(thread?.parentThreadId) && Boolean(listResponse?.nextCursor);
  const has = (method) => methods.has(method);
  return Object.freeze({
    prepare: has('thread/start'),
    fork: has('thread/fork'),
    resume: has('thread/resume'),
    inspect: has('thread/read'),
    turn: has('turn/start'),
    compact: has('thread/compact/start'),
    unsubscribe: has('thread/unsubscribe'),
    listDescendants: has('thread/list') && listContract,
    archive: has('thread/archive') && has('thread/list') && listContract,
    delete: false,
    archiveReason: has('thread/archive') && has('thread/list') && listContract ? null : 'installed schema lacks archive plus complete thread/list metadata',
    listSourceKinds: listContract ? [...sourceKinds] : []
    , omittedCursorIsEnd: listContract && root?.lifecycleContract?.omittedCursorIsEnd === true
    , ancestorFilter: listContract && root?.lifecycleContract?.ancestorFilter === true
  });
}
