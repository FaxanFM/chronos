import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { createPortal } from 'react-dom';
import { ReactFlow, Background, Controls, MiniMap, Handle, Position, applyNodeChanges, applyEdgeChanges } from '@xyflow/react';
import { Play, Pause, Power, Plug, Unplug, Plus, Save, Trash2, X, Check, RotateCcw, Square, ShieldCheck, GitBranch, Inbox, Activity, Copy, Archive, ArrowRight, Search, Settings2, MessageSquare, AlertTriangle, History, Pencil, LayoutGrid, Maximize2, Minimize2, Bot } from 'lucide-react';
import '@xyflow/react/dist/style.css';
import './styles.css';
import { autoLayout, snapPosition, isLayoutOnlyChange, hasWorkflowEdits } from './canvas-layout.mjs';
import { AgentPanel } from './agent-panel.jsx';

const fragment = new URLSearchParams(location.hash.slice(1));
const launchToken = fragment.get('token') || '';
const launchWorkflow = fragment.get('workflow') || '';
if (location.hash) history.replaceState(null, '', location.pathname + location.search);
const emptyPacket = () => ({ title: '', input: '', sourceThreadLink: '', sourceTaskIds: [], conversationMode: 'inherit', complexity: 'medium', relatedToProject: false });
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

function Tooltip({ label, children, disabled = false }) {
  if (!label || !React.isValidElement(children)) return children;
  return disabled ? <span className="tooltip-disabled" tabIndex={0} data-tooltip={label}>{children}</span> : React.cloneElement(children, { 'data-tooltip': label });
}
function Button({ icon: Icon, children, title, ...props }) {
  const childText = React.Children.toArray(children).filter((child) => typeof child === 'string').join(' ');
  const label = title || childText || props['aria-label'];
  const button = <button {...props}>{Icon && <Icon size={16} aria-hidden="true" />}{children}</button>;
  return <Tooltip label={label} disabled={props.disabled}>{button}</Tooltip>;
}
function Status({ value }) { return <Tooltip label={`Status: ${human(value)}. This is the latest reported state.`}><span tabIndex={0} className={`status status-${value}`}>{human(value)}</span></Tooltip>; }
function effortRecommendation(stage) {
  const text = `${stage?.title || ''} ${stage?.instruction || ''}`.toLowerCase();
  if (/security|threat|architecture|risk|deep verification|formal verification/.test(text)) return 'high';
  if (/implement|build|research|debug|design|test|code|review/.test(text)) return 'medium';
  if (/extract|extraction|route|routing|format|formatting|classif/.test(text)) return 'low';
  return 'medium';
}
function modelOptions(runtime) {
  return Array.isArray(runtime?.models) ? runtime.models : [];
}
function modelLabel(model) { return model?.displayName || model?.model || model?.id || 'Host model'; }
function selectedModel(stage, runtime) {
  const models = modelOptions(runtime);
  if (stage?.model) return models.find((item) => item.id === stage.model || item.model === stage.model);
  return models.find((item) => item.id === runtime?.defaultModel || item.model === runtime?.defaultModel);
}
function effortOptions(stage, runtime) {
  const model = selectedModel(stage, runtime);
  return Array.isArray(model?.supportedReasoningEfforts) ? model.supportedReasoningEfforts : [];
}
function effortName(item) { return item?.displayName || item?.reasoningEffort || 'Inherited'; }
function Stage({ data, selected }) {
  return <div className={`stage ${selected ? 'selected' : ''}`} data-tooltip={`${data.title}. This stage is a template; each dispatched attempt runs in a fresh managed Codex thread. ${data.policy === 'workspace-write' ? 'Isolated workspace write' : 'Read only'} stage. Select to edit its assignment, model and thinking level.`}>
    <Handle id="in-left" type="target" position={Position.Left} data-tooltip="Connect an upstream stage here. This stage receives accepted outputs according to its input-join setting." />
    <Handle id="in-top" type="target" position={Position.Top} data-tooltip="Connect an upstream stage here. Top anchor." />
    <Handle id="in-right" type="target" position={Position.Right} data-tooltip="Connect an upstream stage here. Right anchor." />
    <div className="stage-heading"><span className={`capability ${data.policy === 'workspace-write' ? 'write' : ''}`} /><strong>{data.title}</strong></div>
    <div className="stage-meta">{data.policy === 'workspace-write' ? 'Workspace write' : 'Read only'}<span>{data.slots} {data.slots === 1 ? 'slot' : 'slots'}</span></div>
    <div className="stage-counts"><span>{data.queue?.inbox.length || 0} in</span><span className={data.queue?.running ? 'working' : ''}>{data.queue?.running || 0} working</span><span>{data.queue?.outbox.length || 0} out</span></div>
    <footer>{data.routing === 'approval' ? 'Human acceptance' : 'Auto-route'}<span>{data.join === 'all' ? 'Join all' : 'First accepted'}</span></footer>
    <Handle id="in-bottom" type="target" position={Position.Bottom} data-tooltip="Connect an upstream stage here. Bottom anchor." />
    <Handle id="out-right" type="source" position={Position.Right} data-tooltip="Drag to another stage's input to route accepted output to that stage." />
    <Handle id="out-left" type="source" position={Position.Left} data-tooltip="Drag from this left anchor to route accepted output." />
    <Handle id="out-top" type="source" position={Position.Top} data-tooltip="Drag from this top anchor to route accepted output." />
    <Handle id="out-bottom" type="source" position={Position.Bottom} data-tooltip="Drag from this bottom anchor to route accepted output." />
  </div>;
}
const nodeTypes = { stage: Stage };

function ControlHelp() {
  const [tip, setTip] = useState(null);
  useEffect(() => {
    let active = null, previousDescription = null;
    const hints = {
      Model: 'Choose one of the connected Codex host models, or inherit your current Codex default.',
      'Thinking level': 'Choose an effort supported by this model. Higher is not always better; simple tasks can use a lower level.',
      'Stage name': 'A short name for this bot stage in the workflow.',
      Assignment: 'The bounded task, selected context and acceptance criteria for this work.',
      'Bot slots': 'Maximum concurrent turns for this stage, still bounded by the room limit.',
      'Max attempts': 'Maximum bounded attempts before the work requires your attention.',
      'Input join': 'Wait for all selected upstream outputs, or use the first accepted output.',
      'Output routing': 'Send a completed result onward automatically, or hold it for human acceptance.',
      'Native check': 'A JSON argument array such as ["node","--test"]. The command runs in the owned workspace; write-capable checks need separate consent.',
      'Source Codex thread': 'An optional Codex thread deep link. Chronos forks its context; it does not control the original chat.',
      'Allow isolated': 'Enable for implementation, document edits or tests in an owned worktree. Leave off for research, planning and review. No deployment permission is granted.',
      'Allow provider': 'Allow the configured model provider to search the web for this stage. Native shell network access remains off.',
      'Concurrent turns': 'The room-wide maximum. Start with one; capacity checks may reduce dispatch further.',
      'Selected workflow': 'Choose which saved process to view. This does not start its work.',
      'Create from template': 'Create another editable workflow without changing existing tasks.',
      'Workflow name': 'Rename this process, then save while dispatch is paused.',
      'Rename workflow': 'Save this display name without changing assignments, routing, queued work or history. Other unsaved edits stay in the editor.',
      'Save workflow': 'Save the process definition while paused. Referenced processes must be duplicated before changing their assignments or routing.',
      'Save canvas layout': 'Save positions and connection anchors only. Queued work, instructions and routing stay unchanged. Save a changed name separately.',
      'Auto-arrange stages': 'Arrange the current draft from upstream to downstream on the snap grid. Save to keep the layout.',
      'Duplicate workflow': 'Create an editable copy of the process. Its existing work items and results remain with the original workflow.',
      'Focus canvas': 'Give the workflow canvas the full window. Leave focus to return to queues, runtime and session controls.',
      'Leave canvas focus': 'Return to the full Control Room without changing or running work.',
      'Focus stage': 'Focus a stage and open its editor. A stage is a reusable assignment; each dispatched attempt creates its own managed chat.',
      'Search workflows': 'Filter saved workflow names. The currently selected workflow stays available.',
      'Needs review': 'Show current outputs that are waiting for human acceptance. This filter does not approve them.',
      Title: 'A short name for the work item moving through this workflow.',
      Connect: 'Connect the local managed Codex runtime. This does not grant execution or start work.',
      Disconnect: 'Pause dispatch and disconnect the managed runtime. Execution permission expires; queue records and files are preserved.',
      Permissions: 'Review this session\'s execution and isolated-write permissions, data use and limits.',
      Run: 'Dispatch eligible queued work within the configured limits. Separate session authorization is required.',
      Pause: 'Stop dispatching new work. Already-running work continues until it finishes or you cancel it.',
      'Stop Control Room': 'Stop this local room and its managed runtime. Queue records and workspace files are preserved.',
      'Add work item': 'Queue an assignment for the selected workflow. Adding it does not grant execution permission.',
      'Add stage': 'Add a bot stage, then set its assignment, access, model and output routing.',
      Save: 'Save workflow changes while dispatch is paused. Workflows with queued work must be duplicated to edit.',
      'Apply suggestion': 'Apply the suggested thinking level to this stage only. It does not start a model turn.',
      'Authorize session': 'Allow managed execution for this connection, with isolated writes only if you checked that option.',
      'Queue work item': 'Add this assignment and selected context to the workflow inbox.',
      'Accept output': 'Approve this result for downstream stages. This does not merge, publish or deploy files.',
      'Fit View': 'Fit all stages into the workflow canvas.',
      'Zoom In': 'Zoom in on the workflow canvas.',
      'Zoom Out': 'Zoom out on the workflow canvas.',
      Mode: 'Structured is the stable default. Collaborative adds bounded feedback, immutable revision history and checkpoint-backed workspace writes; explicit write consent still applies.',
      Iterations: 'Maximum collaborative feedback iterations for this workflow. This setting is applied only while dispatch is paused.',
      'Request timeout': 'Maximum time a collaborative request may remain open before escalation. This does not extend task execution deadlines.',
      Collaboration: 'View bounded feedback, immutable revisions, file checkpoints and escalation state. Operator resolution uses the existing Run and consent boundaries.',
      Resolve: 'Resolve an eligible blocked or replied message with an operator note. The action may queue bounded work under existing Run and consent; it does not accept output or grant permission.',
    };
    const hide = () => {
      if (active) {
        if (previousDescription) active.setAttribute('aria-describedby', previousDescription);
        else active.removeAttribute('aria-describedby');
      }
      active = null; previousDescription = null; setTip(null);
    };
    const show = (event) => {
      const target = event.target instanceof Element ? event.target : null;
      const control = target?.closest('[data-tooltip],button,input,select,textarea,a,[role="button"],.react-flow__handle');
      if (!control || control === active) return;
      hide();
      const label = control.closest('label');
      const labelText = label?.cloneNode(true);
      labelText?.querySelectorAll('input,select,textarea').forEach((item) => item.remove());
      const name = control.getAttribute('aria-label') || labelText?.textContent?.trim() || control.textContent?.trim() || '';
      const known = hints[name] || (control.matches('input,select,textarea') ? Object.entries(hints).find(([prefix]) => name.startsWith(prefix))?.[1] : null);
      const explicit = control.dataset.tooltip;
      const content = (explicit && explicit !== name ? explicit : null) || label?.dataset.tooltip || label?.getAttribute('title') || known || explicit || control.getAttribute('title') || name;
      if (!content) return;
      active = control; previousDescription = control.getAttribute('aria-describedby');
      control.setAttribute('aria-describedby', [previousDescription, 'chronos-control-help'].filter(Boolean).join(' '));
      const rect = control.getBoundingClientRect();
      const width = Math.min(280, window.innerWidth - 24);
      setTip({ content: content.slice(0, 700), left: Math.min(Math.max(12, rect.left + rect.width / 2 - width / 2), window.innerWidth - width - 12), width, top: rect.bottom + 7 > window.innerHeight - 120 ? Math.max(8, rect.top - 108) : rect.bottom + 7 });
    };
    const leave = (event) => { if (active && !(event.relatedTarget instanceof Node && active.contains(event.relatedTarget))) hide(); };
    const escape = (event) => { if (event.key === 'Escape') hide(); };
    document.addEventListener('pointerover', show); document.addEventListener('focusin', show);
    document.addEventListener('pointerout', leave); document.addEventListener('focusout', hide);
    document.addEventListener('keydown', escape); document.addEventListener('scroll', hide, true);
    window.addEventListener('resize', hide);
    return () => {
      hide(); document.removeEventListener('pointerover', show); document.removeEventListener('focusin', show);
      document.removeEventListener('pointerout', leave); document.removeEventListener('focusout', hide);
      document.removeEventListener('keydown', escape); document.removeEventListener('scroll', hide, true); window.removeEventListener('resize', hide);
    };
  }, []);
  return tip ? createPortal(<div id="chronos-control-help" role="tooltip" className="control-help" style={{ left: tip.left, top: tip.top, width: tip.width }}>{tip.content}</div>, document.body) : null;
}

function App() {
  const [snapshot, setSnapshot] = useState(null);
  const [selectedId, setSelectedId] = useState('');
  const selectedRef = useRef('');
  const displayedWorkflow = useRef(null), dirtyRef = useRef(false);
  const receivedRevision = useRef(-1);
  const [nodes, setNodes] = useState([]), [edges, setEdges] = useState([]), [name, setName] = useState('');
  const [workflowModeDraft, setWorkflowModeDraft] = useState('structured');
  const [conversationDefaultDraft, setConversationDefaultDraft] = useState(null);
  const [collaborationDraft, setCollaborationDraft] = useState({ maxIterations: 2, requestTimeoutMs: 900000 });
  const [dirty, setDirty] = useState(false), [nodeId, setNodeId] = useState('');
  const [view, setView] = useState('flow'), [inspector, setInspector] = useState(false);
  const [canvasFocused, setCanvasFocused] = useState(false);
  const [modal, setModal] = useState(null), [packet, setPacket] = useState(emptyPacket);
  const [allowWrites, setAllowWrites] = useState(false), [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(''), [stopped, setStopped] = useState(false), [taskId, setTaskId] = useState('');
  const [taskFilter, setTaskFilter] = useState('all'), [queueView, setQueueView] = useState('all'), [threadInfo, setThreadInfo] = useState(null);
  const [workflowSearch, setWorkflowSearch] = useState(''), [queueSearch, setQueueSearch] = useState('');
  const [collabNote, setCollabNote] = useState('');
  const [collabMessageId, setCollabMessageId] = useState('');
  const [agentId, setAgentId] = useState('');
  const [agentMessage, setAgentMessage] = useState('');
  const [agentDecision, setAgentDecision] = useState('');
  const [verifyDraft, setVerifyDraft] = useState('[]'), [verifyError, setVerifyError] = useState('');
  const [concurrency, setConcurrency] = useState(1);
  const stoppedRef = useRef(false);
  const graphRef = useRef(null), flowRef = useRef(null);
  const selectWorkflow = (workflow) => {
    displayedWorkflow.current = workflow;
    selectedRef.current = workflow.id; setSelectedId(workflow.id); setName(workflow.name);
    setWorkflowModeDraft(workflow.mode || 'structured'); setConversationDefaultDraft(workflow.conversationDefault ?? null); setCollaborationDraft({ maxIterations: workflow.collaboration?.maxIterations || 2, requestTimeoutMs: workflow.collaboration?.requestTimeoutMs || 900000 });
    setNodes(workflow.nodes.map((node) => ({ id: node.id, type: 'stage', position: node.position, data: { ...node } })));
    setEdges(workflow.edges.map((edge) => ({ ...edge, sourceHandle: edge.sourceHandle || 'out-right', targetHandle: edge.targetHandle || 'in-left' }))); setDirty(false); setNodeId(''); setInspector(false);
  };
  const receive = (data) => {
    if (data.revision < receivedRevision.current) return;
    receivedRevision.current = data.revision;
    setSnapshot(data);
    if (!selectedRef.current || !data.workflows.some((workflow) => workflow.id === selectedRef.current)) {
      const initial = launchWorkflow && data.workflows.find((workflow) => workflow.id === launchWorkflow);
      if (initial || data.workflows[0]) selectWorkflow(initial || data.workflows[0]);
    } else {
      const current = data.workflows.find((item) => item.id === selectedRef.current);
      if (!dirtyRef.current && JSON.stringify(current) !== JSON.stringify(displayedWorkflow.current)) {
        displayedWorkflow.current = current;
        setName(current.name); setWorkflowModeDraft(current.mode || 'structured'); setConversationDefaultDraft(current.conversationDefault ?? null);
        setCollaborationDraft({ maxIterations: current.collaboration?.maxIterations || 2, requestTimeoutMs: current.collaboration?.requestTimeoutMs || 900000 });
        setNodes(current.nodes.map((item) => ({ id: item.id, type: 'stage', position: item.position, data: { ...item } })));
        setEdges(current.edges.map((edge) => ({ ...edge, sourceHandle: edge.sourceHandle || 'out-right', targetHandle: edge.targetHandle || 'in-left' })));
        setNodeId((id) => current.nodes.some((item) => item.id === id) ? id : '');
      }
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
  useEffect(() => { dirtyRef.current = dirty; }, [dirty]);
  useEffect(() => { const node = nodes.find((candidate) => candidate.id === nodeId); setVerifyDraft(JSON.stringify(node?.data.verificationCommand || [])); setVerifyError(''); }, [nodeId]);
  useEffect(() => {
    if (!modal) return;
    const previous = document.activeElement;
    const dialog = document.querySelector('[role="dialog"]');
    const controls = () => [...dialog.querySelectorAll('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href]')].filter((item) => item.getClientRects().length);
    controls()[0]?.focus();
    const keydown = (event) => {
      if (event.key === 'Escape') { event.preventDefault(); setModal(null); }
      if (event.key !== 'Tab') return;
      const items = controls(), first = items[0], last = items.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    };
    document.addEventListener('keydown', keydown);
    return () => { document.removeEventListener('keydown', keydown); previous?.focus(); };
  }, [modal]);
  useEffect(() => {
    const close = (event) => {
      if (event.key !== 'Escape' || modal) return;
      if (inspector) setInspector(false);
      else setCanvasFocused(false);
    };
    document.addEventListener('keydown', close);
    return () => document.removeEventListener('keydown', close);
  }, [modal, inspector]);
  useEffect(() => {
    if (view !== 'flow' || !graphRef.current) return;
    let frame;
    const fit = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const narrow = graphRef.current?.clientWidth < 600 || graphRef.current?.clientHeight < 300;
        const focus = nodes.find((item) => item.id === nodeId) || nodes[0];
        flowRef.current?.fitView({ padding: 0.2, minZoom: narrow ? 0.85 : 0.08, maxZoom: 1, duration: 0, ...(narrow && focus ? { nodes: [{ id: focus.id }] } : {}) });
      });
    };
    const observer = new ResizeObserver(fit); observer.observe(graphRef.current); fit();
    return () => { observer.disconnect(); cancelAnimationFrame(frame); };
  }, [view, selectedId, nodes.length, nodeId, inspector]);
  const node = nodes.find((candidate) => candidate.id === nodeId);
  const workflow = snapshot?.workflows.find((item) => item.id === selectedId);
  const tasks = snapshot?.tasks || [], packets = snapshot?.packets || [];
  const selectedTask = tasks.find((task) => task.id === taskId);
  const workflowMode = workflowModeDraft;
  const collaboration = collaborationDraft;
  const workflowPackets = packets.filter((item) => item.workflowId === selectedId);
  const collaborationPackets = workflowPackets.filter((item) => item.collaboration || item.packet?.collaboration);
  const collaborationMessages = collaborationPackets.flatMap((item) => (item.collaboration?.messages || item.packet?.collaboration?.messages || []).map((message) => ({ ...message, packetTitle: item.title, packetId: item.id }))).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
  const collaborationArtifacts = collaborationPackets.flatMap((item) => item.collaboration?.artifacts || item.packet?.collaboration?.artifacts || []);
  const artifactPacket = (artifact) => collaborationPackets.find((item) => item.id === artifact.packetId || item.collaboration?.artifacts?.some((candidate) => candidate.id === artifact.id) || item.packet?.collaboration?.artifacts?.some((candidate) => candidate.id === artifact.id));
  const artifactIsCurrent = (artifact) => { const packet = artifactPacket(artifact); return packet?.outputs?.[artifact.stageId]?.artifactId === artifact.id; };
  const canResolveMessage = (entry) => {
    if (entry.superseded || entry.recoveryUnknown || !['open', 'escalated', 'blocked'].includes(entry.status)) return false;
    const target = tasks.find((task) => task.replyTo === entry.id && !task.superseded) || tasks.find((task) => task.id === entry.fromTaskId && !task.superseded);
    return Boolean(target && target.state === 'blocked' && !target.recoveryUnknown && target.attempts < 3);
  };
  const hasWriteStages = nodes.some((item) => item.data.policy === 'workspace-write');
  const workflowHasReferences = workflowPackets.length > 0 || tasks.some((task) => task.workflowId === selectedId);
  const canEditWorkflowSettings = snapshot?.mode === 'paused' && snapshot?.activeCount === 0 && !workflowHasReferences;
  const heartbeat = snapshot?.heartbeat;
  const agentRuntime = snapshot?.agentRuntime || { capabilities: {}, loaded: 0, unarchived: 0, archived: 0, uncertain: 0, coverage: {} };
  const changeNode = (update) => { setNodes((current) => current.map((candidate) => candidate.id === nodeId ? { ...candidate, data: { ...candidate.data, ...update } } : candidate)); setDirty(true); };
  const switchWorkflow = (id) => { if (dirty && !confirm('Discard unsaved workflow changes?')) return; const target = snapshot.workflows.find((item) => item.id === id); if (target) selectWorkflow(target); };
  const serialize = (id = selectedId) => ({ id, name, ...(conversationDefaultDraft ? { conversationDefault: conversationDefaultDraft } : {}), ...(workflowMode === 'collaborative' ? { mode: 'collaborative', collaboration: { maxIterations: Number(collaboration.maxIterations) || 2, requestTimeoutMs: Number(collaboration.requestTimeoutMs) || 900000 } } : {}), nodes: nodes.map(({ data, position }) => { const { queue, ...fields } = data; return { ...fields, position }; }), edges: edges.map(({ id, source, target, sourceHandle, targetHandle }) => ({ id, source, target, ...(sourceHandle ? { sourceHandle } : {}), ...(targetHandle ? { targetHandle } : {}) })) });
  const setMode = (mode) => { setWorkflowModeDraft(mode); setDirty(true); };
  const setCollaboration = (update) => { setCollaborationDraft((current) => ({ ...current, ...update })); setDirty(true); };
  async function resolveCollaboration(messageId, body) {
    if (!body.trim() || body.trim().length > 600) { setMessage('Operator note is required and must be 600 characters or fewer.'); return; }
    const packetId = collaborationMessages.find((entry) => entry.id === messageId)?.packetId;
    await act({ action: 'resolve-collaboration', workflowId: selectedId, packetId, messageId, body: body.trim() });
    setCollabNote(''); setCollabMessageId('');
  }
  async function sendAgentMessage() {
    const body = agentMessage.trim();
    if (!agentId || !body || body.length > 4000) { setMessage('Select an agent and enter a message up to 4,000 characters.'); return; }
    const result = await act({ action: 'send-agent-message', agentId, message: body });
    if (result) setAgentMessage('');
  }
  async function answerAgentQuestion(question) {
    const body = window.prompt('Answer this agent question. This queues a continuation and does not grant write permission:', '');
    if (!body?.trim()) return;
    await act({ action: 'answer-agent-question', questionId: question.id, message: body.trim() });
  }
  async function recordDecision() {
    const body = agentDecision.trim();
    if (!body || body.length > 1200) { setMessage('Enter a project decision up to 1,200 characters.'); return; }
    const result = await act({ action: 'record-project-decision', body, sourceTaskIds: [], confirmed: true });
    if (result) setAgentDecision('');
  }
  async function rotateAgent(agent) {
    if (!agent || !confirm(`Rotate ${agent.name || agent.id}'s primary conversation? Chronos will preserve the agent identity and lineage.`)) return;
    await act({ action: 'rotate-agent', agentId: agent.id, confirmed: true });
  }
  async function compactAgent(agent) {
    if (!agent || !confirm('Request supported context compaction? This consumes model allowance and requires the host capability.')) return;
    await act({ action: 'compact-agent', agentId: agent.id, confirmed: true });
  }
  async function cleanupAgentSessions() {
    if (!confirm('Archive only eligible completed worker sessions? Active, uncertain and protected evidence remain untouched.')) return;
    await act({ action: 'cleanup-agent-sessions' });
  }
  async function recoverAgentSession(session) {
    if (!session?.id || !confirm('Inspect this native session before reuse? Chronos will not replace it or accept its outcome.')) return;
    await act({ action: 'recover-agent-session', sessionId: session.id, confirmed: true });
  }
  async function releaseAgentSession(session) {
    if (!session?.id || !['idle', 'waiting'].includes(session.state) || !session.threadId) { setMessage('Only an idle or waiting bound session can be released.'); return; }
    if (!confirm('Release this managed session after the host confirms it is closed or not loaded? Chronos will not delete its transcript or workspace.')) return;
    await act({ action: 'release-agent-session', sessionId: session.id, confirmed: true });
  }
  async function saveWorkflow(copy = false) {
    if (verifyError) { setMessage(verifyError); return; }
    const data = serialize(copy ? uuid() : selectedId); if (copy) data.name = `${name} copy`.slice(0, 120);
    const result = await act({ action: 'save-workflow', workflow: data });
    if (result) selectWorkflow(result.workflows.find((item) => item.id === data.id));
  }
  async function renameWorkflow() {
    const next = name.trim();
    if (!next || next.length > 120 || next === workflow?.name) return;
    if (snapshot?.mode !== 'paused') { setMessage('Pause dispatch before renaming a workflow.'); return; }
    const result = await act({ action: 'rename-workflow', workflowId: selectedId, name: next });
    if (result) {
      const draft = { ...serialize(selectedId), name: next };
      const saved = result.workflows.find((item) => item.id === selectedId);
      const structuralDirty = Boolean(saved && hasWorkflowEdits(draft, saved));
      setName(next);
      setDirty(structuralDirty);
    }
  }
  function layoutOnlyDraft() {
    if (!workflow) return false;
    const draft = serialize(selectedId);
    return isLayoutOnlyChange(draft, workflow);
  }
  async function saveLayout() {
    if (!workflowHasReferences || snapshot?.mode !== 'paused' || snapshot?.activeCount > 0 || !layoutOnlyDraft()) return;
    const result = await act({ action: 'save-workflow-layout', workflowId: selectedId, positions: nodes.map(({ id, position }) => ({ id, x: position.x, y: position.y })), anchors: edges.map(({ id, sourceHandle, targetHandle }) => ({ id, sourceHandle: sourceHandle || 'out-right', targetHandle: targetHandle || 'in-left' })) });
    if (result) setDirty(name !== result.workflows.find((item) => item.id === selectedId)?.name);
  }
  async function template(templateId) {
    if (!templateId || (dirty && !confirm('Discard unsaved workflow changes?'))) return;
    const result = await act({ action: 'apply-template', templateId }); if (result) selectWorkflow(result.workflows.at(-1));
  }
  function addStage() {
    const id = uuid(), data = { id, title: 'New stage', kind: 'task', instruction: 'Complete the assigned work item and report evidence.', policy: 'read-only', slots: 1, routing: 'auto', join: 'all', maxAttempts: 1, model: null, reasoningEffort: null, complexity: 'medium', conversationMode: 'inherit', webSearch: false, verificationCommand: [] };
    setNodes((current) => [...current, { id, type: 'stage', position: { x: 100 + (current.length % 4) * 290, y: 100 + Math.floor(current.length / 4) * 220 }, data }]); setNodeId(id); setInspector(true); setDirty(true);
  }
  function duplicateStage() {
    if (!node) return;
    const id = uuid();
    const copy = { ...node.data, id, title: `${node.data.title} copy`.slice(0, 120) };
    setNodes((current) => [...current, { id, type: 'stage', position: snapPosition({ x: node.position.x + 48, y: node.position.y + 48 }), data: copy }]);
    setNodeId(id); setDirty(true);
  }
  function arrangeCanvas() { setNodes((current) => autoLayout(current, edges)); setDirty(true); }
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
  return <div className={`room ${canvasFocused ? 'canvas-focused' : ''}`}><ControlHelp />
    <header className="topbar"><div className="brand"><img src="/assets/chronos-mark.png" alt="Chronos" /><div><strong>CHRONOS</strong><span>Control Room <small>Experimental</small></span></div></div>
      <div className="session"><Status value={snapshot?.mode || 'loading'} /><span>{snapshot?.activeCount || 0} / {snapshot?.maxConcurrency || 1} working</span></div>
      <div className="top-actions">
        <Button icon={snapshot?.connected ? Unplug : Plug} disabled={busy} onClick={() => act({ action: snapshot?.connected ? 'disconnect' : 'connect' })}>{snapshot?.connected ? 'Disconnect' : 'Connect'}</Button>
        <Button icon={ShieldCheck} onClick={() => { setAllowWrites(snapshot?.consent.writes || false); setModal('consent'); }}>Permissions</Button>
        <Button className="primary" icon={snapshot?.mode === 'running' ? Pause : Play} disabled={busy || !snapshot?.connected} onClick={() => snapshot?.mode === 'running' ? act({ action: 'pause' }) : snapshot?.consent.execution ? act({ action: 'start' }) : setModal('consent')}>{snapshot?.mode === 'running' ? 'Pause' : 'Run'}</Button>
        <Button icon={Power} aria-label="Stop Control Room" disabled={busy} onClick={() => confirm('Stop Control Room and its managed runtime? Files and queue records will be preserved.') && act({ action: 'shutdown' })} />
      </div>
    </header>
    <nav className="main-nav" aria-label="Views">{[['flow', GitBranch, 'Workflow'], ['queues', Inbox, 'Queues'], ['collaboration', MessageSquare, 'Collaboration'], ['agents', Bot, 'Agents'], ['runtime', Activity, 'Runtime']].map(([id, Icon, label]) => <Button key={id} icon={Icon} title={label === 'Collaboration' ? 'Collaboration' : undefined} className={view === id ? 'active' : ''} onClick={() => setView(id)}>{label}{id === 'queues' && <span className="count">{tasks.filter((task) => task.state === 'review').length}</span>}{id === 'collaboration' && collaborationMessages.some((message) => ['open', 'escalated'].includes(message.status)) && <span className="count">{collaborationMessages.filter((message) => ['open', 'escalated'].includes(message.status)).length}</span>}</Button>)}<span className="nav-spacer" /><span className="local-label">LOCAL WORKSPACE</span></nav>
    {message && !modal && <div className="notice" role="alert"><span>{message}</span><Button icon={X} aria-label="Dismiss notice" onClick={() => setMessage('')} /></div>}
    {!snapshot ? <div className="loading">Connecting to the local Control Room...</div> : <>
      <section className="workspace-bar"><label className="workflow-select"><span>Workflow</span><input className="workflow-search" aria-label="Search workflows" placeholder="Search workflows" value={workflowSearch} onChange={(event) => setWorkflowSearch(event.target.value)} /><select aria-label="Selected workflow" value={selectedId} onChange={(event) => switchWorkflow(event.target.value)}>{snapshot.workflows.filter((item) => item.id === selectedId || !workflowSearch.trim() || item.name.toLowerCase().includes(workflowSearch.trim().toLowerCase())).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}{workflowSearch.trim() && !snapshot.workflows.some((item) => item.name.toLowerCase().includes(workflowSearch.trim().toLowerCase())) && <option value="" disabled>No matching workflows</option>}</select></label>
        <span className="workflow-stats">{nodes.length} stages <span>/</span> {workflowPackets.length} work items</span><div className="workflow-mode" data-tooltip="Structured is stable. Collaborative adds bounded feedback and immutable checkpoint history. Mode changes are available only before work is queued."><span>Mode</span><div className="mode-segment" role="group" aria-label="Workflow mode"><Button type="button" className={workflowMode === 'structured' ? 'active' : ''} disabled={!canEditWorkflowSettings} onClick={() => setMode('structured')}>Structured</Button><Button type="button" className={workflowMode === 'collaborative' ? 'active' : ''} disabled={!canEditWorkflowSettings} onClick={() => setMode('collaborative')}>Collaborative</Button></div></div><label className="conversation-default" data-tooltip="Default conversation policy for newly created stages and work items. Legacy workflows keep their prior behavior until explicitly upgraded.">Agent sessions<select aria-label="Agent session default" value={conversationDefaultDraft || 'legacy'} disabled={!canEditWorkflowSettings} onChange={(event) => { const value = event.target.value; setConversationDefaultDraft(value === 'legacy' ? null : value); setDirty(true); }}><option value="legacy">Legacy (unchanged)</option><option value="hybrid">Hybrid (recommended)</option><option value="persistent">Persistent primary</option><option value="one-off">One-off worker</option></select></label><div className="bar-actions"><Button className="primary" icon={Plus} disabled={!workflow || !workflow.nodes.length || dirty} onClick={() => { setPacket(emptyPacket()); setThreadInfo(null); setModal('packet'); }}>Add work item</Button></div>
      </section>
      {view === 'flow' && <div className={`flow-layout ${inspector && node ? 'inspector-open' : ''}`}>
        <div className="canvas-area"><div className="canvas-toolbar">
          <input aria-label="Workflow name" value={name} maxLength={120} onChange={(event) => { setName(event.target.value); setDirty(true); }} />
          <span className="save-state">{dirty ? 'Unsaved' : 'Saved'}</span>
          <div className="toolbar-actions">
            <Button icon={Plus} aria-label="Add stage" onClick={addStage}><span className="stage-add-label">Add stage</span></Button><Button icon={LayoutGrid} title="Auto-arrange stages" aria-label="Auto-arrange stages" onClick={arrangeCanvas} disabled={nodes.length < 2} />
            {workflowHasReferences ? <Button icon={Save} title="Save canvas layout" aria-label="Save canvas layout" disabled={busy || !dirty || snapshot.mode !== 'paused' || snapshot.activeCount > 0 || !layoutOnlyDraft()} onClick={saveLayout} /> : <Button icon={Save} title="Save workflow" aria-label="Save workflow" disabled={busy || !dirty || !!verifyError} onClick={() => saveWorkflow()} />}
            <Button icon={Pencil} title="Rename workflow" aria-label="Rename workflow" disabled={busy || !name.trim() || name.trim() === workflow?.name || snapshot.mode !== 'paused'} onClick={renameWorkflow} />
            <Button icon={Copy} title="Duplicate workflow" aria-label="Duplicate workflow" disabled={busy} onClick={() => saveWorkflow(true)} />
            <Button icon={Trash2} title="Delete selected connections" aria-label="Delete selected connections" disabled={!edges.some((edge) => edge.selected)} onClick={() => { setEdges((current) => current.filter((edge) => !edge.selected)); setDirty(true); }} />
            <Button icon={canvasFocused ? Minimize2 : Maximize2} title={canvasFocused ? 'Leave canvas focus' : 'Focus canvas'} aria-label={canvasFocused ? 'Leave canvas focus' : 'Focus canvas'} onClick={() => setCanvasFocused((current) => !current)} />
            <select aria-label="Create from template" value="" disabled={snapshot.mode !== 'paused' || busy} onChange={(event) => template(event.target.value)}><option value="">New from template</option>{snapshot.templates.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
          </div></div>
          <div className="graph" ref={graphRef}><ReactFlow onInit={(instance) => { flowRef.current = instance; }} nodes={graphNodes} edges={edges} nodeTypes={nodeTypes} snapToGrid snapGrid={[24, 24]} onNodesChange={(changes) => { setNodes((current) => applyNodeChanges(changes, current)); if (changes.some((change) => change.type !== 'select' && change.type !== 'dimensions')) setDirty(true); }} onEdgesChange={(changes) => { setEdges((current) => applyEdgeChanges(changes, current)); if (changes.some((change) => change.type !== 'select')) setDirty(true); }} onConnect={({ source, target, sourceHandle, targetHandle }) => { setEdges((current) => [...current, { id: uuid(), source, target, sourceHandle, targetHandle }]); setDirty(true); }} onNodeClick={(_, item) => { setNodeId(item.id); setInspector(true); }} onPaneClick={() => setInspector(false)} fitView fitViewOptions={{ padding: 0.25, maxZoom: 1 }} minZoom={0.08} maxZoom={2} deleteKeyCode={['Backspace', 'Delete']}><Background gap={24} color="#d9dfe2" /><Controls showInteractive={false} /><MiniMap pannable zoomable nodeColor={(item) => item.data.policy === 'workspace-write' ? '#e55751' : '#668a9d'} /></ReactFlow></div>
          <footer className="canvas-footer"><span>{dirty ? 'Save changes before adding work.' : 'Dispatch follows accepted outputs.'}</span><select className="stage-jump" aria-label="Focus stage" value={nodeId} onChange={(event) => { setNodeId(event.target.value); setInspector(true); }}><option value="" disabled>Choose stage</option>{nodes.map((item) => <option value={item.id} key={item.id}>{item.data.title}</option>)}</select><span>{snapshot.mode === 'paused' ? 'Dispatch paused' : 'Dispatch active'}</span></footer>
        </div>
        {inspector && node && <aside className="inspector"><div className="panel-heading"><h2>Stage settings</h2><Button icon={X} aria-label="Close stage settings" onClick={() => setInspector(false)} /></div>
          <label>Stage name<input value={node.data.title} maxLength={120} onChange={(event) => changeNode({ title: event.target.value })} /></label>
          <label>Assignment<textarea aria-label="Assignment" rows={6} value={node.data.instruction} maxLength={12000} onChange={(event) => changeNode({ instruction: event.target.value })} /></label>
          <label data-tooltip="Read-only stages can inspect inputs. Isolated workspace writes are used for implementation, document edits, tests, and native checks in a packet-owned worktree.">Workspace access<select value={node.data.policy} onChange={(event) => changeNode({ policy: event.target.value })}><option value="read-only">Read only</option><option value="workspace-write">Isolated workspace write</option></select></label>
          <div className="field-pair"><label data-tooltip="Persistent keeps compatible serial work with the stage agent. One-off isolates each work item. Hybrid keeps a primary agent while isolating writes and parallel review.">Conversation mode<select value={node.data.conversationMode || 'inherit'} onChange={(event) => changeNode({ conversationMode: event.target.value })}><option value="inherit">Inherit workflow default</option><option value="hybrid">Hybrid</option><option value="persistent">Persistent primary</option><option value="one-off">One-off worker</option></select></label><label data-tooltip="Complexity sizes the dispatch budget separately from model reasoning effort.">Task complexity<select value={node.data.complexity || 'medium'} onChange={(event) => changeNode({ complexity: event.target.value })}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option></select></label></div>
          <div className="field-pair"><label>Bot slots<input type="number" min="1" max="16" value={node.data.slots} onChange={(event) => changeNode({ slots: Number(event.target.value) })} /></label><label>Max attempts<input type="number" min="1" max="3" value={node.data.maxAttempts} onChange={(event) => changeNode({ maxAttempts: Number(event.target.value) })} /></label></div>
          <label data-tooltip="Automatic routes accepted results. Human decision / acceptance pauses the stage for your explicit review before downstream routing.">Output routing<select value={node.data.routing} onChange={(event) => changeNode({ routing: event.target.value })}><option value="auto">Automatic after completion</option><option value="approval">Human decision / acceptance</option></select></label>
          <Button icon={Copy} title="Duplicate stage" aria-label="Duplicate stage" onClick={duplicateStage}>Duplicate stage</Button>
          <label>Input join<select value={node.data.join} onChange={(event) => changeNode({ join: event.target.value })}><option value="all">Wait for all input stages</option><option value="any">First accepted input</option></select></label>
          <fieldset className="stage-inputs"><legend>Input stages</legend>
            {edges.filter((edge) => edge.target === nodeId).map((edge) => <div key={edge.id}><span>{nodes.find((item) => item.id === edge.source)?.data.title}</span><select aria-label={`Source anchor ${edge.id}`} value={edge.sourceHandle || 'out-right'} onChange={(event) => { setEdges((current) => current.map((item) => item.id === edge.id ? { ...item, sourceHandle: event.target.value } : item)); setDirty(true); }}><option value="out-right">Right</option><option value="out-left">Left</option><option value="out-top">Top</option><option value="out-bottom">Bottom</option></select><select aria-label={`Target anchor ${edge.id}`} value={edge.targetHandle || 'in-left'} onChange={(event) => { setEdges((current) => current.map((item) => item.id === edge.id ? { ...item, targetHandle: event.target.value } : item)); setDirty(true); }}><option value="in-left">Left</option><option value="in-right">Right</option><option value="in-top">Top</option><option value="in-bottom">Bottom</option></select><Button icon={X} title="Remove input connection" aria-label={`Remove input ${edge.source}`} onClick={() => { setEdges((current) => current.filter((item) => item.id !== edge.id)); setDirty(true); }} /></div>)}
            <select aria-label="Add input stage" value="" onChange={(event) => { if (event.target.value) { setEdges((current) => [...current, { id: uuid(), source: event.target.value, target: nodeId, sourceHandle: 'out-right', targetHandle: 'in-left' }]); setDirty(true); } }}><option value="">Add input stage</option>{nodes.filter((item) => item.id !== nodeId && !edges.some((edge) => edge.source === item.id && edge.target === nodeId)).map((item) => <option key={item.id} value={item.id}>{item.data.title}</option>)}</select>
          </fieldset>
          <label data-tooltip="Choose a model exposed by the connected Codex host. Inherit host default keeps the workflow portable.">Model<select value={node.data.model || ''} disabled={!snapshot?.connected || !modelOptions(snapshot?.runtime).length} onChange={(event) => changeNode({ model: event.target.value || null })}><option value="">Inherit host default{snapshot?.runtime?.defaultModel ? ` (${snapshot.runtime.defaultModel})` : ''}</option>{node.data.model && !modelOptions(snapshot?.runtime).some((model) => (model.id || model.model) === node.data.model) && <option value={node.data.model}>Unavailable legacy choice: {node.data.model}</option>}{modelOptions(snapshot?.runtime).map((model) => <option key={model.id || model.model} value={model.id || model.model}>{modelLabel(model)}{model.isDefault ? ' (default)' : ''}</option>)}</select></label>
          {!snapshot?.connected && <p className="field-hint">Connect Control Room to load the host model catalog.</p>}
          {snapshot?.connected && !modelOptions(snapshot?.runtime).length && <p className="field-hint">The host did not expose a model catalog. Existing explicit choices remain unchanged.</p>}
          <label data-tooltip="Choose a thinking level supported by this model. Inherit uses its host default. A lower level can suit simple tasks; recommendations are not quality guarantees.">Thinking level<select value={node.data.reasoningEffort || ''} disabled={!snapshot?.connected || !effortOptions(node.data, snapshot?.runtime).length} onChange={(event) => changeNode({ reasoningEffort: event.target.value || null })}><option value="">Inherit model default{selectedModel(node.data, snapshot?.runtime)?.defaultReasoningEffort ? ` (${selectedModel(node.data, snapshot?.runtime).defaultReasoningEffort})` : ''}</option>{node.data.reasoningEffort && !effortOptions(node.data, snapshot?.runtime).some((item) => item.reasoningEffort === node.data.reasoningEffort) && <option value={node.data.reasoningEffort}>Unavailable legacy choice: {node.data.reasoningEffort}</option>}{effortOptions(node.data, snapshot?.runtime).map((effort) => <option key={effort.reasoningEffort} value={effort.reasoningEffort}>{effortName(effort)}{effort.description ? ` - ${effort.description}` : ''}</option>)}</select></label>
          {node.data.reasoningEffort !== effortRecommendation(node.data) && effortOptions(node.data, snapshot?.runtime).some((item) => item.reasoningEffort === effortRecommendation(node.data)) && <div className="recommendation" title="Heuristic based on the stage title and assignment; it is never applied automatically.">Suggested for this stage: <strong>{effortRecommendation(node.data)}</strong><Button type="button" onClick={() => changeNode({ reasoningEffort: effortRecommendation(node.data) })}>Apply suggestion</Button></div>}
          <label className="check-label"><input type="checkbox" checked={node.data.webSearch} onChange={(event) => changeNode({ webSearch: event.target.checked })} />Allow provider web search</label>
          <label>Native check: JSON command arguments<textarea aria-label="Native check: JSON command arguments" className="code-input" rows={3} value={verifyDraft} placeholder={'["node", "--test"]'} onChange={(event) => verify(event.target.value)} /></label>{verifyError && <p className="field-error">{verifyError}</p>}
          <Button className="danger-text" icon={Trash2} onClick={() => { setNodes((current) => current.filter((item) => item.id !== nodeId)); setEdges((current) => current.filter((edge) => edge.source !== nodeId && edge.target !== nodeId)); setNodeId(''); setDirty(true); }}>Delete stage</Button>
        </aside>}
      </div>}
          {view === 'queues' && <section className="queues-view">
        <div className="queue-summary">{(workflow?.nodes || []).map((item) => { const queue = snapshot.stageQueues.find((entry) => entry.workflowId === selectedId && entry.nodeId === item.id); return <Tooltip key={item.id} label={`Filter managed tasks for ${item.title}. ${queue?.running || 0} currently working.`}><button className={taskFilter === item.id ? 'queue-stage active' : 'queue-stage'} onClick={() => setTaskFilter(taskFilter === item.id ? 'all' : item.id)}><strong>{item.title}</strong><span>{queue?.inbox.length || 0} inbox <ArrowRight size={12} /> {queue?.outbox.length || 0} outbox</span><small>{queue?.running || 0} working / {queue?.review || 0} review</small></button></Tooltip>; })}</div>
        <div className="queue-body"><div className="task-list"><div className="panel-heading"><h2>Managed tasks</h2><Button onClick={() => setTaskFilter('all')}>All stages</Button></div>
          <div className="queue-filters" role="group" aria-label="Task filters"><Button className={queueView === 'all' ? 'active' : ''} onClick={() => setQueueView('all')}>All</Button><Button className={queueView === 'review' ? 'active' : ''} onClick={() => setQueueView('review')}>Needs review</Button><Button className={queueView === 'current' ? 'active' : ''} onClick={() => setQueueView('current')}>Current</Button><Button className={queueView === 'history' ? 'active' : ''} onClick={() => setQueueView('history')}>History</Button></div>
          <label className="task-search"><Search size={14} /><input aria-label="Search managed tasks" placeholder="Search tasks" value={queueSearch} onChange={(event) => setQueueSearch(event.target.value)} /></label>
          {tasks.filter((task) => task.workflowId === selectedId && (taskFilter === 'all' || task.nodeId === taskFilter) && (queueView === 'all' || (queueView === 'review' && task.state === 'review') || (queueView === 'history' && task.superseded) || (queueView === 'current' && !task.superseded)) && (!queueSearch.trim() || `${task.title} ${task.instruction || ''}`.toLowerCase().includes(queueSearch.trim().toLowerCase()))).map((task) => <button key={task.id} className={`task-row ${task.id === taskId ? 'selected' : ''} ${task.superseded ? 'superseded-task' : ''}`} onClick={() => setTaskId(task.id)}><span><strong>{task.title}{task.superseded && <span className="history-marker" title="Superseded revision; retained for history">History</span>}</strong><small>{workflow?.nodes.find((item) => item.id === task.nodeId)?.title || 'Standalone'} / attempt {task.attempts}{task.stageRevision ? ` / revision ${task.stageRevision}` : ''}</small></span><Status value={task.state} /></button>)}
          {!tasks.some((task) => task.workflowId === selectedId) && <div className="empty-state"><Inbox size={28} /><h3>The inbox is clear</h3><p>Add a work item to queue this workflow.</p></div>}
          <div className="packet-list"><h2>Work items</h2>{packets.filter((item) => item.workflowId === selectedId).map((item) => <div className="packet-row" key={item.id}><span><strong>{item.title}</strong><small>{human(item.state)}</small></span><Button icon={Archive} aria-label={`Archive ${item.title}`} disabled={busy || tasks.some((task) => task.packetId === item.id && (['running', 'verifying'].includes(task.state) || task.recoveryUnknown))} onClick={() => confirm('Archive this work item from the queue? Workspace files are preserved.') && act({ action: 'archive-packet', packetId: item.id })} /></div>)}</div>
        </div><aside className="task-detail">{selectedTask ? <>
          <div className="panel-heading"><h2>Task detail</h2><Status value={selectedTask.state} /></div><h3>{selectedTask.title}</h3>
          <div className="task-actions">{selectedTask.superseded && <div className="warning"><History size={15} /> Superseded revision retained for history. Accept and Retry are disabled.</div>}{selectedTask.state === 'review' && <Button className="primary" icon={Check} disabled={busy || selectedTask.superseded} onClick={() => taskAction('accept', selectedTask)}>Accept output</Button>}{['blocked', 'failed'].includes(selectedTask.state) && <Button icon={RotateCcw} disabled={busy || selectedTask.superseded || selectedTask.attempts >= 3} onClick={() => taskAction('retry', selectedTask)}>Retry</Button>}{!['accepted', 'failed', 'cancelled'].includes(selectedTask.state) && <Button icon={Square} disabled={busy || selectedTask.cancelRequested} onClick={() => taskAction('cancel', selectedTask)}>{selectedTask.cancelRequested ? 'Stopping' : 'Cancel'}</Button>}{!['running', 'verifying'].includes(selectedTask.state) && <Button icon={Trash2} title={selectedTask.packetId ? 'Archive the work item to preserve its queue history' : 'Remove queue record'} aria-label={selectedTask.packetId ? 'Archive work item' : 'Remove queue record'} disabled={busy || Boolean(selectedTask.packetId)} onClick={() => taskAction('remove-task', selectedTask)} />}</div>
          {selectedTask.recoveryUnknown && <div className="warning">Previous execution is unverified. Recovery requires confirmation that its worker and commands have stopped.</div>}
          {selectedTask.error && <div className="warning">{selectedTask.error}</div>}
          <dl><dt>Access</dt><dd>{selectedTask.policy || 'read-only'}</dd><dt>Workspace</dt><dd>{selectedTask.cwd || 'Not prepared'}</dd><dt>Base</dt><dd>{selectedTask.workspace?.base || 'Source read only'}</dd><dt>Thread</dt><dd>{selectedTask.threadId ? <a href={`codex://threads/${selectedTask.threadId}`}>Open managed thread</a> : 'Not started'}</dd></dl>
          {selectedTask.fileCheckpoint ? <div className="checkpoint-summary"><strong>Immutable file checkpoint</strong><small>{selectedTask.fileCheckpoint.fileCount} files / {selectedTask.fileCheckpoint.bytes} bytes</small><small>manifest {String(selectedTask.fileCheckpoint.manifestSha256 || '').slice(0, 12)}...</small></div> : selectedTask.checkpointError ? <div className="warning">File checkpoint unavailable: {selectedTask.checkpointError}</div> : null}
          {selectedTask.workspace?.sourceDirty && <div className="warning">The source had uncommitted changes. They were not copied into this worktree.</div>}
          <h4>Result</h4><pre className="result">{selectedTask.summary || 'No completed output yet.'}</pre>
          <h4>Observed execution evidence</h4>{selectedTask.executionEvidence ? <><p className="muted">{(selectedTask.executionEvidence.observedWallMs / 1000).toFixed(1)} seconds of observed turn wall time. {selectedTask.executionEvidence.partial ? 'Partial item coverage.' : 'Observed native item events only; completeness is not guaranteed.'} No token, cost or CPU-time estimate.</p><pre className="result">{JSON.stringify(selectedTask.executionEvidence.counts, null, 2)}</pre></> : <p className="muted">No compatible execution evidence was recorded.</p>}
          {selectedTask.verification && <><h4>Native verification <Status value={selectedTask.verification.exitCode === 0 ? 'accepted' : 'failed'} /></h4><pre className="result">{JSON.stringify(selectedTask.verification.command)}{'\n'}Exit {selectedTask.verification.exitCode}{'\n'}{selectedTask.verification.stdout}{'\n'}{selectedTask.verification.stderr}</pre></>}
        </> : <div className="empty-state"><Settings2 size={28} /><h3>Select a task</h3></div>}</aside></div>
      </section>}
      {view === 'collaboration' && <section className="collaboration-view">
        <div className="runtime-heading"><div><h1 data-tooltip="Read-only beta feedback for the selected workflow. Accepted history remains immutable.">Collaboration</h1></div><Status value={workflowMode === 'collaborative' ? 'available' : 'paused'} /></div>
        <div className="collaboration-toolbar"><div className="collab-setting" data-tooltip="Maximum bounded feedback iterations for this packet. Native backward execution remains bounded by this limit."><label>Iterations<input type="number" min="1" max="5" value={collaboration.maxIterations ?? 2} disabled={!canEditWorkflowSettings} onChange={(event) => setCollaboration({ maxIterations: Math.max(1, Math.min(5, Number(event.target.value) || 1)) })} /></label></div><div className="collab-setting" data-tooltip="Request deadline for an open collaboration message, from 1 to 60 minutes."><label>Request timeout (minutes)<input type="number" min="1" max="60" value={Math.max(1, Math.round((collaboration.requestTimeoutMs || 900000) / 60000))} disabled={!canEditWorkflowSettings} onChange={(event) => setCollaboration({ requestTimeoutMs: Math.max(1000, Math.min(3600000, (Number(event.target.value) || 1) * 60000)) })} /></label></div><span className="collab-scope"><ShieldCheck size={15} /> Managed-only scope</span></div>
        <div className="collaboration-grid"><section className="collaboration-timeline"><div className="panel-heading"><h2><MessageSquare size={15} /> Message timeline</h2><span className="muted">{collaborationMessages.length} messages</span></div>{collaborationMessages.length ? collaborationMessages.map((entry) => <article className={`collab-message ${entry.status}`} key={entry.id}><div className="collab-message-head"><strong>{human(entry.kind)}</strong><Status value={entry.status} /><time>{date(entry.createdAt)}</time></div><p>{entry.body || 'No message body.'}</p><small>{entry.fromStageId || entry.fromTaskId || 'Managed stage'} -&gt; {entry.toStageId || 'Coordinator'} {entry.inReplyTo ? `(reply to ${entry.inReplyTo})` : ''}</small>{canResolveMessage(entry) && <div className="collab-resolve"><Button icon={Check} title="Resolve" onClick={() => setCollabMessageId(entry.id)}>Resolve</Button>{collabMessageId === entry.id && <div className="collab-note"><textarea maxLength={600} rows={2} placeholder="Required operator note" value={collabNote} onChange={(event) => setCollabNote(event.target.value)} /><Button className="primary" onClick={() => resolveCollaboration(entry.id, collabNote)}>Submit resolution</Button></div>}</div>}</article>) : <div className="empty-state"><MessageSquare size={20} /><h3>No messages</h3></div>}</section><aside className="collaboration-side"><section><div className="panel-heading"><h2><History size={15} /> Revisions</h2></div>{collaborationArtifacts.length ? collaborationArtifacts.map((artifact) => { const current = artifactIsCurrent(artifact); return <div className={`revision-row ${current ? '' : 'superseded'}`} key={artifact.id}><strong>{artifact.stageId || 'Stage'} - Revision {artifact.revision}</strong><span>{artifact.summary || 'Artifact'} {current ? '(selected)' : '(superseded history)'}</span><small>{artifact.sha256 ? `sha256:${artifact.sha256.slice(0, 12)}...` : 'Hash unavailable'}{artifact.taskId ? ` / task ${artifact.taskId}` : ''}</small></div>; }) : <p className="muted">No accepted text revisions.</p>}</section><section className="escalation"><h2>Escalation</h2><p>{workflowPackets.find((item) => item.collaboration?.escalation)?.collaboration?.escalation || 'None recorded.'}</p><small>Resolution uses existing Run and consent boundaries; it does not accept output or grant permission.</small></section></aside></div>
      </section>}
      {view === 'agents' && <AgentPanel snapshot={snapshot} busy={busy} act={act} />}
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
      </form> : <><p>Managed bots use your existing Codex login and allowance. Work item inputs, selected thread history and workspace context may be processed by your configured model provider under its terms.</p><p>Chronos sends no publisher telemetry. Queue state, workspaces and results stay on this machine unless you share or publish them. External account tools, hooks and worker-created agents are disabled.</p><label className="check-label permission"><input id="write-consent" type="checkbox" checked={allowWrites} onChange={(event) => setAllowWrites(event.target.checked)} /><span><strong>Allow isolated workspace writes and native checks</strong><small>Use this for implementation, editing documents, running tests, or native checks inside an isolated packet-owned worktree. Leave it off for research, planning, review, or read-only work. Your original workspace remains untouched until you review and transfer changes.</small></span></label><p className="muted">Permission expires when Control Room restarts or disconnects. It does not grant deployment, publication, installation, account access, or permission to change the original workspace.</p><div className="dialog-actions"><Button onClick={() => setModal(null)}>Cancel</Button><Button className="primary" icon={ShieldCheck} disabled={busy} onClick={async () => { const result = await act({ action: 'authorize', confirmed: true, allowWrites }); if (result) setModal(null); }}>Authorize session</Button></div></>}
    </section></div>}
  </div>;
}

createRoot(document.getElementById('root')).render(<App />);
