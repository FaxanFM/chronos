import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ReactFlow, Background, Controls, MiniMap, Handle, Position, applyNodeChanges, applyEdgeChanges } from '@xyflow/react';
import { Play, Pause, Power, Plug, Unplug, Plus, Save, Trash2, X, Check, RotateCcw, Square, ShieldCheck, GitBranch, Inbox, Activity, Copy, Archive, ArrowRight, Search, Settings2 } from 'lucide-react';
import '@xyflow/react/dist/style.css';
import './styles.css';

const fragment = new URLSearchParams(location.hash.slice(1));
const launchToken = fragment.get('token') || '';
if (location.hash) history.replaceState(null, '', location.pathname + location.search);
const emptyPacket = () => ({ title: '', input: '', sourceThreadLink: '', sourceTaskIds: [] });
const uuid = () => crypto.randomUUID();
const bytes = (value) => Number.isFinite(value) ? `${(value / 1073741824).toFixed(1)} GB` : 'Unavailable';
const human = (value) => String(value || '').replaceAll('_', ' ');
const date = (value) => value ? new Date(value).toLocaleTimeString() : 'Not observed';
const errorText = {
  workflow_referenced: 'This workflow has work items. Duplicate it to change the process, or archive its items first.',
  pause_and_finish_running_tasks_first: 'Pause dispatch and wait for running work to finish before changing this setting.',
  confirm_previous_worker_stopped: 'Confirm that the previous worker has stopped before recovery.',
  execution_consent_required: 'Authorize this execution session before starting.',
  open_the_private_launch_link: 'Open the private launch link printed by the local server.',
  source_thread_link_invalid: 'Use a Codex thread link: codex://threads/<thread-id>.',
  task_has_dependents: 'Another work item uses this output. Archive its dependents first.',
  archive_work_item_instead: 'Archive the whole work item to preserve its stage and output history.'
};

function Button({ icon: Icon, children, title, ...props }) {
  return <button title={title || (typeof children === 'string' ? children : undefined)} {...props}>{Icon && <Icon size={16} aria-hidden="true" />}{children}</button>;
}
function Status({ value }) { return <span className={`status status-${value}`}>{human(value)}</span>; }
function Stage({ data, selected }) {
  return <div className={`stage ${selected ? 'selected' : ''}`}>
    <Handle type="target" position={Position.Left} />
    <div className="stage-heading"><span className={`capability ${data.policy === 'workspace-write' ? 'write' : ''}`} /><strong>{data.title}</strong></div>
    <div className="stage-meta">{data.policy === 'workspace-write' ? 'Workspace write' : 'Read only'}<span>{data.slots} {data.slots === 1 ? 'slot' : 'slots'}</span></div>
    <div className="stage-counts"><span>{data.queue?.inbox.length || 0} in</span><span className={data.queue?.running ? 'working' : ''}>{data.queue?.running || 0} working</span><span>{data.queue?.outbox.length || 0} out</span></div>
    <footer>{data.routing === 'approval' ? 'Human acceptance' : 'Auto-route'}<span>{data.join === 'all' ? 'Join all' : 'First accepted'}</span></footer>
    <Handle type="source" position={Position.Right} />
  </div>;
}
const nodeTypes = { stage: Stage };

function App() {
  const [snapshot, setSnapshot] = useState(null);
  const [selectedId, setSelectedId] = useState('');
  const selectedRef = useRef('');
  const receivedRevision = useRef(-1);
  const [nodes, setNodes] = useState([]), [edges, setEdges] = useState([]), [name, setName] = useState('');
  const [dirty, setDirty] = useState(false), [nodeId, setNodeId] = useState('');
  const [view, setView] = useState('flow'), [inspector, setInspector] = useState(false);
  const [modal, setModal] = useState(null), [packet, setPacket] = useState(emptyPacket);
  const [allowWrites, setAllowWrites] = useState(false), [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(''), [stopped, setStopped] = useState(false), [taskId, setTaskId] = useState('');
  const [taskFilter, setTaskFilter] = useState('all'), [threadInfo, setThreadInfo] = useState(null);
  const [verifyDraft, setVerifyDraft] = useState('[]'), [verifyError, setVerifyError] = useState('');
  const [concurrency, setConcurrency] = useState(1);
  const stoppedRef = useRef(false);
  const graphRef = useRef(null), flowRef = useRef(null);
  const selectWorkflow = (workflow) => {
    selectedRef.current = workflow.id; setSelectedId(workflow.id); setName(workflow.name);
    setNodes(workflow.nodes.map((node) => ({ id: node.id, type: 'stage', position: node.position, data: { ...node } })));
    setEdges(workflow.edges.map((edge) => ({ ...edge }))); setDirty(false); setNodeId(''); setInspector(false);
  };
  const receive = (data) => {
    if (data.revision < receivedRevision.current) return;
    receivedRevision.current = data.revision;
    setSnapshot(data);
    if (!selectedRef.current || !data.workflows.some((workflow) => workflow.id === selectedRef.current)) {
      if (data.workflows[0]) selectWorkflow(data.workflows[0]);
    }
  };
  async function request(action) {
    const response = await fetch(action ? '/api/actions' : '/api/state', {
      method: action ? 'POST' : 'GET', headers: { ...(launchToken ? { 'x-chronos-token': launchToken } : {}), ...(action ? { 'Content-Type': 'application/json' } : {}) },
      ...(action ? { body: JSON.stringify(action) } : {})
    });
    const data = await response.json();
    if (!response.ok) throw new Error(errorText[data.error] || human(data.error));
    return data;
  }
  async function act(action) {
    setBusy(true); setMessage('');
    try {
      const data = await request(action);
      if (data.stopped) { stoppedRef.current = true; setStopped(true); }
      else if (data.workflows) receive(data);
      return data;
    } catch (error) { setMessage(error.message || 'The local server is unavailable.'); return null; }
    finally { setBusy(false); }
  }
  useEffect(() => {
    let alive = true;
    const poll = async () => { if (stoppedRef.current) return; try { const data = await request(); if (alive) receive(data); } catch (error) { if (alive) setMessage(error.message || 'The local server is unavailable.'); } };
    poll(); const timer = setInterval(poll, 2000);
    return () => { alive = false; clearInterval(timer); };
  }, []);
  useEffect(() => { const node = nodes.find((candidate) => candidate.id === nodeId); setVerifyDraft(JSON.stringify(node?.data.verificationCommand || [])); setVerifyError(''); }, [nodeId]);
  useEffect(() => {
    if (view !== 'flow' || !graphRef.current) return;
    let frame;
    const fit = () => { cancelAnimationFrame(frame); frame = requestAnimationFrame(() => flowRef.current?.fitView({ padding: 0.25, maxZoom: 1, duration: 0 })); };
    const observer = new ResizeObserver(fit); observer.observe(graphRef.current); fit();
    return () => { observer.disconnect(); cancelAnimationFrame(frame); };
  }, [view, selectedId, nodes.length, inspector]);
  const node = nodes.find((candidate) => candidate.id === nodeId);
  const workflow = snapshot?.workflows.find((item) => item.id === selectedId);
  const tasks = snapshot?.tasks || [], packets = snapshot?.packets || [];
  const selectedTask = tasks.find((task) => task.id === taskId);
  const heartbeat = snapshot?.heartbeat;
  const changeNode = (update) => { setNodes((current) => current.map((candidate) => candidate.id === nodeId ? { ...candidate, data: { ...candidate.data, ...update } } : candidate)); setDirty(true); };
  const switchWorkflow = (id) => { if (dirty && !confirm('Discard unsaved workflow changes?')) return; const target = snapshot.workflows.find((item) => item.id === id); if (target) selectWorkflow(target); };
  const serialize = (id = selectedId) => ({ id, name, nodes: nodes.map(({ data, position }) => { const { queue, ...fields } = data; return { ...fields, position }; }), edges: edges.map(({ id, source, target }) => ({ id, source, target })) });
  async function saveWorkflow(copy = false) {
    if (verifyError) { setMessage(verifyError); return; }
    const data = serialize(copy ? uuid() : selectedId); if (copy) data.name = `${name} copy`.slice(0, 120);
    const result = await act({ action: 'save-workflow', workflow: data });
    if (result) selectWorkflow(result.workflows.find((item) => item.id === data.id));
  }
  async function template(templateId) {
    if (!templateId || (dirty && !confirm('Discard unsaved workflow changes?'))) return;
    const result = await act({ action: 'apply-template', templateId }); if (result) selectWorkflow(result.workflows.at(-1));
  }
  function addStage() {
    const id = uuid(), data = { id, title: 'New stage', kind: 'task', instruction: 'Complete the assigned work item and report evidence.', policy: 'read-only', slots: 1, routing: 'auto', join: 'all', maxAttempts: 1, model: null, webSearch: false, verificationCommand: [] };
    setNodes((current) => [...current, { id, type: 'stage', position: { x: 100 + (current.length % 4) * 290, y: 100 + Math.floor(current.length / 4) * 220 }, data }]); setNodeId(id); setInspector(true); setDirty(true);
  }
  function verify(value) {
    setVerifyDraft(value);
    try { const command = JSON.parse(value); if (!Array.isArray(command) || command.some((part) => typeof part !== 'string' || !part.trim())) throw new Error(); changeNode({ verificationCommand: command }); setVerifyError(''); }
    catch { setVerifyError('Enter a JSON array of command arguments, or [] for no native check.'); }
  }
  async function taskAction(action, task) {
    const confirmedStopped = task.recoveryUnknown ? confirm('Have you verified that the previous worker and its commands have stopped? Only confirm after checking the managed runtime.') : false;
    if (task.recoveryUnknown && !confirmedStopped) return;
    if (action === 'remove-task' && !confirm('Remove this queue record? Workspace files will not be deleted.')) return;
    const result = await act({ action, taskId: task.id, confirmedStopped }); if (result && action === 'remove-task') setTaskId('');
  }
  const graphNodes = nodes.map((item) => ({ ...item, selected: item.id === nodeId, data: { ...item.data, queue: snapshot?.stageQueues.find((queue) => queue.workflowId === selectedId && queue.nodeId === item.id) } }));
  if (stopped) return <main className="end-state"><img src="/assets/chronos-mark.png" alt="" /><h1>Control Room stopped</h1><p>Managed execution is paused. Work items and workspace files are preserved.</p></main>;
  return <div className="room">
    <header className="topbar"><div className="brand"><img src="/assets/chronos-mark.png" alt="Chronos" /><div><strong>CHRONOS</strong><span>Control Room <small>Experimental</small></span></div></div>
      <div className="session"><Status value={snapshot?.mode || 'loading'} /><span>{snapshot?.activeCount || 0} / {snapshot?.maxConcurrency || 1} working</span></div>
      <div className="top-actions">
        <Button icon={snapshot?.connected ? Unplug : Plug} disabled={busy} onClick={() => act({ action: snapshot?.connected ? 'disconnect' : 'connect' })}>{snapshot?.connected ? 'Disconnect' : 'Connect'}</Button>
        <Button icon={ShieldCheck} onClick={() => { setAllowWrites(snapshot?.consent.writes || false); setModal('consent'); }}>Permissions</Button>
        <Button className="primary" icon={snapshot?.mode === 'running' ? Pause : Play} disabled={busy || !snapshot?.connected} onClick={() => snapshot?.mode === 'running' ? act({ action: 'pause' }) : snapshot?.consent.execution ? act({ action: 'start' }) : setModal('consent')}>{snapshot?.mode === 'running' ? 'Pause' : 'Run'}</Button>
        <Button icon={Power} aria-label="Stop Control Room" disabled={busy} onClick={() => confirm('Stop Control Room and its managed runtime? Files and queue records will be preserved.') && act({ action: 'shutdown' })} />
      </div>
    </header>
    <nav className="main-nav" aria-label="Views">{[['flow', GitBranch, 'Workflow'], ['queues', Inbox, 'Queues'], ['runtime', Activity, 'Runtime']].map(([id, Icon, label]) => <Button key={id} icon={Icon} className={view === id ? 'active' : ''} onClick={() => setView(id)}>{label}{id === 'queues' && <span className="count">{tasks.filter((task) => task.state === 'review').length}</span>}</Button>)}<span className="nav-spacer" /><span className="local-label">LOCAL WORKSPACE</span></nav>
    {message && !modal && <div className="notice" role="alert"><span>{message}</span><Button icon={X} aria-label="Dismiss notice" onClick={() => setMessage('')} /></div>}
    {!snapshot ? <div className="loading">Connecting to the local Control Room...</div> : <>
      <section className="workspace-bar"><label className="workflow-select"><span>Workflow</span><select aria-label="Selected workflow" value={selectedId} onChange={(event) => switchWorkflow(event.target.value)}>{snapshot.workflows.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
        <span className="workflow-stats">{nodes.length} stages <span>/</span> {packets.filter((item) => item.workflowId === selectedId).length} work items</span><div className="bar-actions"><Button className="primary" icon={Plus} disabled={!workflow || !workflow.nodes.length || dirty} onClick={() => { setPacket(emptyPacket()); setThreadInfo(null); setModal('packet'); }}>Add work item</Button></div>
      </section>
      {view === 'flow' && <div className={`flow-layout ${inspector && node ? 'inspector-open' : ''}`}>
        <div className="canvas-area"><div className="canvas-toolbar">
          <input aria-label="Workflow name" value={name} maxLength={120} onChange={(event) => { setName(event.target.value); setDirty(true); }} />
          <span className="save-state">{dirty ? 'Unsaved' : 'Saved'}</span>
          <div className="toolbar-actions">
            <Button icon={Plus} onClick={addStage}>Add stage</Button>
            <Button icon={Save} disabled={busy || !dirty || !!verifyError} onClick={() => saveWorkflow()}>Save</Button>
            <Button icon={Copy} title="Duplicate workflow" aria-label="Duplicate workflow" disabled={busy} onClick={() => saveWorkflow(true)} />
            <Button icon={Trash2} title="Delete selected connections" aria-label="Delete selected connections" disabled={!edges.some((edge) => edge.selected)} onClick={() => { setEdges((current) => current.filter((edge) => !edge.selected)); setDirty(true); }} />
            <select aria-label="Create from template" value="" disabled={snapshot.mode !== 'paused' || busy} onChange={(event) => template(event.target.value)}><option value="">New from template</option>{snapshot.templates.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
          </div></div>
          <div className="graph" ref={graphRef}><ReactFlow onInit={(instance) => { flowRef.current = instance; }} nodes={graphNodes} edges={edges} nodeTypes={nodeTypes} onNodesChange={(changes) => { setNodes((current) => applyNodeChanges(changes, current)); if (changes.some((change) => change.type !== 'select' && change.type !== 'dimensions')) setDirty(true); }} onEdgesChange={(changes) => { setEdges((current) => applyEdgeChanges(changes, current)); if (changes.some((change) => change.type !== 'select')) setDirty(true); }} onConnect={({ source, target }) => { setEdges((current) => [...current, { id: uuid(), source, target }]); setDirty(true); }} onNodeClick={(_, item) => { setNodeId(item.id); setInspector(true); }} onPaneClick={() => setInspector(false)} fitView fitViewOptions={{ padding: 0.25, maxZoom: 1 }} minZoom={0.08} maxZoom={2} deleteKeyCode={['Backspace', 'Delete']}><Background gap={24} color="#d9dfe2" /><Controls showInteractive={false} /><MiniMap pannable zoomable nodeColor={(item) => item.data.policy === 'workspace-write' ? '#e55751' : '#668a9d'} /></ReactFlow></div>
          <footer className="canvas-footer"><span>{dirty ? 'Save changes before adding work.' : 'Dispatch follows accepted outputs.'}</span><span>{snapshot.mode === 'paused' ? 'Dispatch paused' : 'Dispatch active'}</span></footer>
        </div>
        {inspector && node && <aside className="inspector"><div className="panel-heading"><h2>Stage settings</h2><Button icon={X} aria-label="Close stage settings" onClick={() => setInspector(false)} /></div>
          <label>Stage name<input value={node.data.title} maxLength={120} onChange={(event) => changeNode({ title: event.target.value })} /></label>
          <label>Assignment<textarea aria-label="Assignment" rows={6} value={node.data.instruction} maxLength={12000} onChange={(event) => changeNode({ instruction: event.target.value })} /></label>
          <label>Workspace access<select value={node.data.policy} onChange={(event) => changeNode({ policy: event.target.value })}><option value="read-only">Read only</option><option value="workspace-write">Isolated workspace write</option></select></label>
          <div className="field-pair"><label>Bot slots<input type="number" min="1" max="16" value={node.data.slots} onChange={(event) => changeNode({ slots: Number(event.target.value) })} /></label><label>Max attempts<input type="number" min="1" max="3" value={node.data.maxAttempts} onChange={(event) => changeNode({ maxAttempts: Number(event.target.value) })} /></label></div>
          <label>Output routing<select value={node.data.routing} onChange={(event) => changeNode({ routing: event.target.value })}><option value="auto">Automatic after completion</option><option value="approval">Require human acceptance</option></select></label>
          <label>Input join<select value={node.data.join} onChange={(event) => changeNode({ join: event.target.value })}><option value="all">Wait for all input stages</option><option value="any">First accepted input</option></select></label>
          <fieldset className="stage-inputs"><legend>Input stages</legend>
            {edges.filter((edge) => edge.target === nodeId).map((edge) => <div key={edge.id}><span>{nodes.find((item) => item.id === edge.source)?.data.title}</span><Button icon={X} title="Remove input connection" aria-label={`Remove input ${edge.source}`} onClick={() => { setEdges((current) => current.filter((item) => item.id !== edge.id)); setDirty(true); }} /></div>)}
            <select aria-label="Add input stage" value="" onChange={(event) => { if (event.target.value) { setEdges((current) => [...current, { id: uuid(), source: event.target.value, target: nodeId }]); setDirty(true); } }}><option value="">Add input stage</option>{nodes.filter((item) => item.id !== nodeId && !edges.some((edge) => edge.source === item.id && edge.target === nodeId)).map((item) => <option key={item.id} value={item.id}>{item.data.title}</option>)}</select>
          </fieldset>
          <label>Model<input value={node.data.model || ''} placeholder="Codex default" maxLength={120} onChange={(event) => changeNode({ model: event.target.value || null })} /></label>
          <label className="check-label"><input type="checkbox" checked={node.data.webSearch} onChange={(event) => changeNode({ webSearch: event.target.checked })} />Allow provider web search</label>
          <label>Native check: JSON command arguments<textarea aria-label="Native check: JSON command arguments" className="code-input" rows={3} value={verifyDraft} placeholder={'["node", "--test"]'} onChange={(event) => verify(event.target.value)} /></label>{verifyError && <p className="field-error">{verifyError}</p>}
          <Button className="danger-text" icon={Trash2} onClick={() => { setNodes((current) => current.filter((item) => item.id !== nodeId)); setEdges((current) => current.filter((edge) => edge.source !== nodeId && edge.target !== nodeId)); setNodeId(''); setDirty(true); }}>Delete stage</Button>
        </aside>}
      </div>}
      {view === 'queues' && <section className="queues-view">
        <div className="queue-summary">{(workflow?.nodes || []).map((item) => { const queue = snapshot.stageQueues.find((entry) => entry.workflowId === selectedId && entry.nodeId === item.id); return <button key={item.id} className={taskFilter === item.id ? 'queue-stage active' : 'queue-stage'} onClick={() => setTaskFilter(taskFilter === item.id ? 'all' : item.id)}><strong>{item.title}</strong><span>{queue?.inbox.length || 0} inbox <ArrowRight size={12} /> {queue?.outbox.length || 0} outbox</span><small>{queue?.running || 0} working / {queue?.review || 0} review</small></button>; })}</div>
        <div className="queue-body"><div className="task-list"><div className="panel-heading"><h2>Managed tasks</h2><Button onClick={() => setTaskFilter('all')}>All stages</Button></div>
          {tasks.filter((task) => task.workflowId === selectedId && (taskFilter === 'all' || task.nodeId === taskFilter)).map((task) => <button key={task.id} className={`task-row ${task.id === taskId ? 'selected' : ''}`} onClick={() => setTaskId(task.id)}><span><strong>{task.title}</strong><small>{workflow?.nodes.find((item) => item.id === task.nodeId)?.title || 'Standalone'} / attempt {task.attempts}</small></span><Status value={task.state} /></button>)}
          {!tasks.some((task) => task.workflowId === selectedId) && <div className="empty-state"><Inbox size={28} /><h3>The inbox is clear</h3><p>Add a work item to queue this workflow.</p></div>}
          <div className="packet-list"><h2>Work items</h2>{packets.filter((item) => item.workflowId === selectedId).map((item) => <div className="packet-row" key={item.id}><span><strong>{item.title}</strong><small>{human(item.state)}</small></span><Button icon={Archive} aria-label={`Archive ${item.title}`} disabled={busy || tasks.some((task) => task.packetId === item.id && (['running', 'verifying'].includes(task.state) || task.recoveryUnknown))} onClick={() => confirm('Archive this work item from the queue? Workspace files are preserved.') && act({ action: 'archive-packet', packetId: item.id })} /></div>)}</div>
        </div><aside className="task-detail">{selectedTask ? <>
          <div className="panel-heading"><h2>Task detail</h2><Status value={selectedTask.state} /></div><h3>{selectedTask.title}</h3>
          <div className="task-actions">{selectedTask.state === 'review' && <Button className="primary" icon={Check} disabled={busy} onClick={() => taskAction('accept', selectedTask)}>Accept output</Button>}{['blocked', 'failed'].includes(selectedTask.state) && <Button icon={RotateCcw} disabled={busy || selectedTask.attempts >= 3} onClick={() => taskAction('retry', selectedTask)}>Retry</Button>}{!['accepted', 'failed', 'cancelled'].includes(selectedTask.state) && <Button icon={Square} disabled={busy || selectedTask.cancelRequested} onClick={() => taskAction('cancel', selectedTask)}>{selectedTask.cancelRequested ? 'Stopping' : 'Cancel'}</Button>}{!['running', 'verifying'].includes(selectedTask.state) && <Button icon={Trash2} title="Remove queue record" aria-label="Remove queue record" disabled={busy} onClick={() => taskAction('remove-task', selectedTask)} />}</div>
          {selectedTask.recoveryUnknown && <div className="warning">Previous execution is unverified. Recovery requires confirmation that its worker and commands have stopped.</div>}
          {selectedTask.error && <div className="warning">{selectedTask.error}</div>}
          <dl><dt>Access</dt><dd>{selectedTask.policy || 'read-only'}</dd><dt>Workspace</dt><dd>{selectedTask.cwd || 'Not prepared'}</dd><dt>Base</dt><dd>{selectedTask.workspace?.base || 'Source read only'}</dd><dt>Thread</dt><dd>{selectedTask.threadId ? <a href={`codex://threads/${selectedTask.threadId}`}>Open managed thread</a> : 'Not started'}</dd></dl>
          {selectedTask.workspace?.sourceDirty && <div className="warning">The source had uncommitted changes. They were not copied into this worktree.</div>}
          <h4>Result</h4><pre className="result">{selectedTask.summary || 'No completed output yet.'}</pre>
          {selectedTask.verification && <><h4>Native verification <Status value={selectedTask.verification.exitCode === 0 ? 'accepted' : 'failed'} /></h4><pre className="result">{JSON.stringify(selectedTask.verification.command)}{'\n'}Exit {selectedTask.verification.exitCode}{'\n'}{selectedTask.verification.stdout}{'\n'}{selectedTask.verification.stderr}</pre></>}
        </> : <div className="empty-state"><Settings2 size={28} /><h3>Select a task</h3></div>}</aside></div>
      </section>}
      {view === 'runtime' && <section className="runtime-view"><div className="runtime-heading"><div><h1>Managed runtime</h1><p>{snapshot.workspace.sourceRoot}</p></div><Status value={heartbeat?.health || 'unavailable'} /></div>
        <div className="metrics"><div><span>Active turns</span><strong>{heartbeat?.ownedRuntime.activeTurns ?? 0}</strong><small>Chronos-owned runtime only</small></div><div><span>Free memory</span><strong>{bytes(heartbeat?.host.freeMemoryBytes)}</strong><small>of {bytes(heartbeat?.host.totalMemoryBytes)}</small></div><div><span>CPU capacity</span><strong>{heartbeat?.host.cpuCount || 'Unknown'}</strong><small>Logical processors, not CPU load</small></div><div><span>Control Room memory</span><strong>{heartbeat?.host.processMemoryBytes ? `${Math.round(heartbeat.host.processMemoryBytes / 1048576)} MB` : 'Unknown'}</strong><small>Node server RSS, not worker RSS</small></div></div>
        <div className="runtime-columns"><section><h2>Dispatch limits</h2><div className="limit-control"><label>Concurrent turns<input type="number" min="1" max="16" value={concurrency} onChange={(event) => setConcurrency(Number(event.target.value))} /></label><Button icon={Check} disabled={busy || snapshot.mode !== 'paused' || snapshot.activeCount > 0} onClick={() => act({ action: 'configure', maxConcurrency: concurrency })}>Apply</Button></div><dl><dt>Configured limit</dt><dd>{snapshot.maxConcurrency}</dd><dt>Resource ceiling</dt><dd>{heartbeat?.recommendedConcurrency || 1}</dd><dt>Owned process</dt><dd>{heartbeat?.ownedRuntime.pid || 'Not connected'}</dd><dt>Last protocol activity</dt><dd>{date(heartbeat?.ownedRuntime.lastProtocolAt)}</dd><dt>Health sampled</dt><dd>{date(heartbeat?.sampledAt)}</dd><dt>Scheduler</dt><dd>Not required</dd><dt>Hooks</dt><dd>Not installed by Control Room</dd></dl><p className="muted">Resource checks apply to this runtime and host memory. Other Codex chats, approvals, quota and context health are not evaluated.</p></section>
          <section><h2>Activity</h2><div className="events">{snapshot.events.slice(-30).reverse().map((event, index) => <div key={`${event.at}-${index}`}><time>{date(event.at)}</time><span>{event.message}</span></div>)}</div></section></div>
      </section>}
    </>}
    {modal && <div className="modal-backdrop"><section className="dialog" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><div className="panel-heading"><h2 id="dialog-title">{modal === 'packet' ? 'New work item' : 'Execution permissions'}</h2><Button icon={X} aria-label="Close dialog" onClick={() => setModal(null)} /></div>
      {message && <div className="warning" role="alert">{message}</div>}
      {modal === 'packet' ? <form onSubmit={async (event) => { event.preventDefault(); const result = await act({ action: 'add-packet', workflowId: selectedId, ...packet }); if (result) { setModal(null); setView('queues'); setTaskId(result.tasks.find((task) => task.packetId === result.packets.at(-1)?.id)?.id || ''); } }}>
        <label>Title<input id="packet-title" required maxLength={120} value={packet.title} onChange={(event) => setPacket({ ...packet, title: event.target.value })} /></label>
        <label>Assignment<textarea id="packet-input" required rows={5} maxLength={12000} value={packet.input} onChange={(event) => setPacket({ ...packet, input: event.target.value })} /></label>
        <label>Source Codex thread link (optional)<input id="packet-link" value={packet.sourceThreadLink} placeholder="codex://threads/..." onChange={(event) => { setPacket({ ...packet, sourceThreadLink: event.target.value }); setThreadInfo(null); }} /></label>
        <div className="inline-info"><span>Runs in a managed fork. The original chat is unchanged.</span><Button type="button" icon={Search} disabled={busy || !packet.sourceThreadLink || !snapshot.connected} onClick={async () => { const data = await act({ action: 'inspect-thread', sourceThreadLink: packet.sourceThreadLink }); if (data) setThreadInfo(data); }}>Check link</Button></div>{threadInfo && <div className="confirmed">Thread available: {threadInfo.name || threadInfo.title || threadInfo.id || 'verified'}</div>}
        <fieldset><legend>Accepted outbox inputs (optional)</legend><div className="source-options">{tasks.filter((task) => task.state === 'accepted').map((task) => <label className="check-label" key={task.id}><input type="checkbox" checked={packet.sourceTaskIds.includes(task.id)} onChange={(event) => setPacket({ ...packet, sourceTaskIds: event.target.checked ? [...packet.sourceTaskIds, task.id] : packet.sourceTaskIds.filter((id) => id !== task.id) })} />{task.title}</label>)}{!tasks.some((task) => task.state === 'accepted') && <span className="muted">No accepted outputs yet.</span>}</div></fieldset>
        <p className="muted">Write stages create an isolated worktree from committed HEAD. Uncommitted source changes are not copied. Native checks run only when configured on the stage.</p>
        <div className="dialog-actions"><Button type="button" onClick={() => setModal(null)}>Cancel</Button><Button type="submit" className="primary" icon={Plus} disabled={busy}>Queue work item</Button></div>
      </form> : <><p>Managed bots use your existing Codex login and allowance. Work item inputs, selected thread history and workspace context may be processed by your configured model provider under its terms.</p><p>Chronos sends no publisher telemetry. Queue state, workspaces and results stay on this machine unless you share or publish them. External account tools, hooks and worker-created agents are disabled.</p><label className="check-label permission"><input id="write-consent" type="checkbox" checked={allowWrites} onChange={(event) => setAllowWrites(event.target.checked)} /><span><strong>Allow isolated workspace writes and native checks</strong><small>Commands can change the packet-owned workspace. Shell network access stays off. Read-only stages stay read only.</small></span></label><p className="muted">Permission expires when Control Room restarts or disconnects. Publication, installation and access to other accounts are not included.</p><div className="dialog-actions"><Button onClick={() => setModal(null)}>Cancel</Button><Button className="primary" icon={ShieldCheck} disabled={busy} onClick={async () => { const result = await act({ action: 'authorize', confirmed: true, allowWrites }); if (result) setModal(null); }}>Authorize session</Button></div></>}
    </section></div>}
  </div>;
}

createRoot(document.getElementById('root')).render(<App />);
