import React, { useEffect, useState } from 'react';
import { Archive, ArrowRight, Bot, Check, ChevronRight, MessageSquare, RefreshCw, Save, Unplug } from 'lucide-react';

const human = (value) => String(value || 'unknown').replaceAll('_', ' ').replaceAll('-', ' ');
const time = (value) => value ? new Date(value).toLocaleString() : '';
function Command({ icon: Icon, children, title, ...props }) {
  return <button type="button" title={title} data-tooltip={title} {...props}>{Icon && <Icon size={15} />}{children}</button>;
}
const retentionLabels = {
  maxUnarchivedSessions: ['Unarchived sessions', 1024, 'Finite limit on native conversations that have not been archived.'],
  maxSessionRecords: ['Lifetime session records', 4096, 'Historical ownership and lineage records. Protected records are not silently discarded.'],
  maxLoadedSessions: ['Loaded sessions', 64, 'Separate from concurrency. Release idle subscriptions to free this capacity.'],
  maxAuditEntries: ['Audit entries', 20000, 'Durable hash-chained history, independent of the recent activity display.'],
  maxLedgerEntries: ['Knowledge entries', 2048, 'Decisions, proposals and accepted results retain their own provenance.'],
  maxRetainedLocalBytes: ['Owned local data (bytes)', 1073741824, 'Queue and owned workspace budget. Native transcript storage is reported separately as unsupported.']
};

export function AgentPanel({ snapshot, busy, act }) {
  const [selectedId, select] = useState('');
  const [body, setBody] = useState('');
  const [decision, setDecision] = useState('');
  const [decisionKind, setDecisionKind] = useState('human_decision');
  const [retention, setRetention] = useState(snapshot.project?.retention || {});
  const retentionKey = JSON.stringify(snapshot.project?.retention || {});
  useEffect(() => setRetention(JSON.parse(retentionKey)), [retentionKey]);
  const agents = snapshot.agents || [], sessions = snapshot.sessions || [];
  const agent = agents.find((item) => item.id === selectedId) || agents[0];
  const primary = sessions.find((item) => item.id === agent?.primarySessionId);
  const agentSessions = sessions.filter((item) => item.agentId === agent?.id);
  const messages = (snapshot.agentMessages || []).filter((item) => item.agentId === agent?.id);
  const questions = (snapshot.agentQuestions || []).filter((item) => (item.agentId === agent?.id || item.targetAgentId === agent?.id) && ['waiting', 'escalated'].includes(item.state));
  const work = snapshot.tasks.filter((item) => item.agentId === agent?.id && !item.discussionAgentId && !item.superseded);
  const runtime = snapshot.agentRuntime || {}, capabilities = runtime.capabilities || {};
  const canConfigure = !busy && snapshot.mode === 'paused' && snapshot.activeCount === 0;
  const confirmAction = async (message, action) => { if (window.confirm(message)) await act(action); };
  async function send(event) {
    event.preventDefault();
    if (!agent || !body.trim()) return;
    if (await act({ action: 'send-agent-message', agentId: agent.id, message: body.trim() })) setBody('');
  }
  async function answer(question) {
    const message = window.prompt(question.question + '\n\nAnswer this specific question. Existing execution permissions remain unchanged.');
    if (message?.trim()) await act({ action: 'answer-agent-question', questionId: question.id, message: message.trim() });
  }
  return <section className="agents-view">
    <div className="runtime-heading"><div><h1>Project agents</h1><p>{snapshot.project?.name}</p></div><span className="status">{human(snapshot.mode)}</span></div>
    <div className="agent-policy-bar">
      <label>Project default<select aria-label="Project conversation default" value={snapshot.project?.conversationDefault || 'legacy'} disabled={!canConfigure} title="Applies to inherited conversation policies. Explicit workflow settings remain unchanged." onChange={(event) => act({ action: 'configure-project-agents', conversationDefault: event.target.value })}>
        {snapshot.project?.conversationDefault === 'legacy' && <option value="legacy">Legacy (unchanged)</option>}<option value="hybrid">Hybrid</option><option value="persistent">Persistent</option><option value="one-off">One-off</option>
      </select></label>
      <dl className="agent-counters"><div title="Host-observed owned runtime subscriptions"><dt>Loaded</dt><dd>{runtime.loaded ?? 'Unknown'}</dd></div><div title="Native conversations not yet archived"><dt>Unarchived</dt><dd>{runtime.unarchived ?? 0}</dd></div><div><dt>Archived</dt><dd>{runtime.archived ?? 0}</dd></div><div><dt>Uncertain</dt><dd>{runtime.uncertain ?? 0}</dd></div></dl>
      <Command icon={Archive} disabled={busy || !snapshot.connected} title="Request reversible archival of eligible resolved workers. Never deletes transcripts or workspaces." onClick={() => confirmAction('Archive eligible resolved worker conversations? Protected and uncertain sessions remain untouched.', { action: 'cleanup-agent-sessions' })}>Archive eligible</Command>
      {snapshot.project?.conversationDefault === 'legacy' && <Command icon={RefreshCw} disabled={!canConfigure} title="Explicitly upgrade old workflow conversation policies to Hybrid. Artifacts and permissions stay unchanged." onClick={() => confirmAction('Upgrade existing workflows without an explicit conversation policy to Hybrid?', { action: 'upgrade-project-agents', confirmed: true })}>Upgrade to Hybrid</Command>}
    </div>
    <div className="agents-workspace">
      <aside className="agent-list" aria-label="Project agents">{agents.map((item) => {
        const session = sessions.find((candidate) => candidate.id === item.primarySessionId);
        return <button key={item.id} title={`Open ${item.name} chat and inbox`} className={item.id === agent?.id ? 'agent-list-row active' : 'agent-list-row'} onClick={() => select(item.id)}><span><Bot size={16} /><strong>{item.name}</strong></span><span className="status">{human(session?.state || 'not created')}</span><small>{item.stageRefs.length} stage role(s) / {item.mailbox.length} inbox</small></button>;
      })}</aside>
      <section className="agent-chat" aria-label="Agent conversation">{agent ? <>
        <div className="panel-heading"><div><h2><Bot size={18} />{agent.name}</h2><small>Instruction version {agent.instructionVersion} / {primary ? `Primary generation ${primary.generation}` : 'No primary session yet'}</small></div><div className="agent-chat-actions">
          <Command icon={RefreshCw} disabled={busy} title="Record a controlled rotation. The successor is created lazily on the next authorized message or assignment." onClick={() => confirmAction('Rotate the primary conversation while preserving this agent and its history?', { action: 'rotate-agent', agentId: agent.id, confirmed: true })}>Rotate</Command>
          <Command icon={Archive} disabled={busy || !snapshot.connected || !snapshot.consent.execution || primary?.state !== 'idle' || !capabilities.compact} title="Request host-supported context compaction. Consumes model allowance; completion must be observed. Does not delete history." onClick={() => confirmAction('Compact this primary conversation? This can consume model allowance; project records remain authoritative.', { action: 'compact-agent', agentId: agent.id, confirmed: true })}>Compact</Command>
        </div></div>
        {agent.rotationIntent && <div className="agent-notice">Successor pending / identity and history preserved</div>}
        <div className="agent-history" aria-live="polite">{messages.length ? messages.map((entry) => <article className={`agent-message ${entry.role}`} key={entry.id}><strong>{entry.role === 'user' ? 'You' : agent.name}</strong><time>{time(entry.at)}</time><p>{entry.body}</p></article>) : <div className="empty-state"><MessageSquare size={24} /><h3>No messages yet</h3></div>}</div>
        <form className="agent-composer" onSubmit={send}><textarea aria-label={`Message ${agent.name}`} rows={3} maxLength={4000} placeholder="Discuss this project..." value={body} onChange={(event) => setBody(event.target.value)} /><button className="primary" type="submit" disabled={busy || !body.trim()} title="Queue a read-only discussion under the current Run permission. This grants no writes or deployment permission."><ArrowRight size={16} />Queue message</button></form>
        {questions.length > 0 && <div className="agent-questions"><h3>Decision inbox</h3>{questions.map((question) => <article key={question.id}><strong>{question.question}</strong><small>{human(question.state)} / revision {question.revision} / {time(question.deadline)}</small><Command icon={MessageSquare} disabled={busy} title="Answer the correlated question and continue its existing work item with unchanged permissions." onClick={() => answer(question)}>Answer</Command></article>)}</div>}
        <details className="agent-work-list"><summary>{work.length} work items</summary>{work.slice(-30).reverse().map((item) => <div key={item.id}><strong>{item.title}</strong><span>{human(item.state)}</span><small>{item.dispatchDecision?.reason}</small></div>)}</details>
        <div className="agent-sessions"><div className="panel-heading"><h3>Conversation lineage</h3><span>{agentSessions.length} records</span></div>{agentSessions.map((session) => <div className="agent-session-row" key={session.id}>
          <strong>{human(session.role)} / {session.generation}</strong><span className="status">{human(session.state)}</span><span title={session.threadId || session.creationIntent?.id}>{session.threadId ? session.threadId.slice(0, 8) : 'Creation intent'} / {session.turns || 0} turns</span><small>{session.reason}</small><small>{human(session.cleanupStatus || session.observedHostState)}</small>
          <div className="agent-session-actions">{session.recoveryRequired && <Command icon={RefreshCw} disabled={busy || !snapshot.connected || !session.threadId} title={session.threadId ? 'Inspect authoritative native state before allowing reuse. Never accepts an unknown outcome.' : 'The creation outcome has no native identity. It remains blocked; no replacement is created.'} onClick={() => confirmAction('Inspect this uncertain native conversation? No replacement or result acceptance will occur.', { action: 'recover-agent-session', sessionId: session.id, confirmed: true })}>Inspect recovery</Command>}
            {['idle', 'waiting'].includes(session.state) && session.threadId && <Command icon={Unplug} disabled={busy || !snapshot.connected || !capabilities.unsubscribe} title="Release this idle runtime subscription. Closure must be observed; history and workspace remain intact." onClick={() => confirmAction('Release the idle subscription, without archiving or deleting the conversation?', { action: 'release-agent-session', sessionId: session.id, confirmed: true })}>Release</Command>}
          </div>
        </div>)}{!agentSessions.length && <p className="muted">No native conversations</p>}</div>
      </> : <div className="empty-state"><Bot size={28} /><h3>No configured agents</h3></div>}</section>
    </div>
    <section className="agent-decisions"><div className="panel-heading"><h2>Project knowledge</h2><span>{snapshot.ledger?.length || 0} records</span></div>
      <form className="decision-entry" onSubmit={async (event) => { event.preventDefault(); if (await act({ action: 'record-project-decision', body: decision.trim(), kind: decisionKind, sourceTaskIds: [], confirmed: true })) setDecision(''); }}>
        <select aria-label="Knowledge record type" value={decisionKind} onChange={(event) => setDecisionKind(event.target.value)}><option value="human_decision">Human decision</option><option value="project_goal">Project goal</option><option value="project_constraint">Constraint</option></select>
        <textarea aria-label="Project knowledge record" rows={2} maxLength={1800} placeholder="Record an accepted decision, goal or constraint..." value={decision} onChange={(event) => setDecision(event.target.value)} /><button type="submit" disabled={busy || !decision.trim()} title="Record explicit human provenance. Does not grant execution permission."><Check size={16} />Record</button>
      </form>
      {(snapshot.ledger || []).slice(-16).reverse().map((entry) => <div className="ledger-row" key={entry.id}><strong>{human(entry.kind)}</strong><span>{entry.body}</span><small>{entry.sourceTaskId ? 'Task evidence' : 'Human'} / revision {entry.revision}</small></div>)}
    </section>
    <details className="agent-retention"><summary><ChevronRight size={16} />Retention and capacity</summary><form onSubmit={(event) => { event.preventDefault(); act({ action: 'configure-agent-retention', retention }); }}>
      <div className="retention-grid">{Object.entries(retentionLabels).map(([key, [label, max, title]]) => <label key={key} title={title}>{label}<input aria-label={label} type="number" step="1" min={key === 'maxRetainedLocalBytes' ? 1048576 : 1} max={max} required value={retention[key] || ''} onChange={(event) => setRetention((current) => ({ ...current, [key]: Number(event.target.value) }))} /></label>)}</div>
      <Command type="submit" icon={Save} disabled={!canConfigure} title="Save finite capacity limits while paused. Does not remove protected history or files.">Save limits</Command><small>{snapshot.project?.storage ? `${snapshot.project.storage.bytes.toLocaleString()} bytes / queue and owned workspaces` : 'Owned storage not measured yet'} / native transcript bytes unsupported</small>
    </form></details>
  </section>;
}
