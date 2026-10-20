# Chronos Control Room API

The Control Room exposes a private, authenticated HTTP API on `127.0.0.1` for local onboarding and automation. It is not a public service, MCP server, or remote worker endpoint. The launcher supplies a launch token in the private URL; the first authenticated request receives an HttpOnly, SameSite session cookie. The token remains valid for the lifetime of that room, but the client drops it after the cookie handoff. Subsequent requests must use that cookie and the exact same origin.

## Discovery

`GET /api/capabilities` returns the protocol version, instance and package identity, supported action names, and safety boundaries. `GET /api/state` returns the bounded room snapshot, including task inputs, results, workspace paths and history. It is sensitive local project data, not a telemetry feed. Both require the launch token or an established session cookie.

## Actions

`POST /api/actions` accepts one JSON action envelope. Authentication is only proof that a local process has the room secret; it is not proof of human intent. Agents and automation must obtain explicit user consent before `authorize`, `start`, or workspace writes, and must stop at human review/acceptance gates. The same engine validation used by the UI applies to API callers: execution consent, workspace-write consent, pause/running checks, native worker ownership, and human review gates cannot be bypassed. Use `rename-workflow` for a display-name change:

```json
{"action":"rename-workflow","workflowId":"software_factory-default","name":"Release triage"}
```

Renaming is metadata-only and preserves queued packets, task IDs, checkpoints, and execution history. Replacing a workflow definition still uses `save-workflow` and remains blocked while packet history references it.

Use `save-workflow-layout` to persist canvas positions and connection anchors without changing instructions, policies, stages, or routing semantics. The action requires one exact position for every node and one exact anchor for every edge; coordinates are bounded to +/-100,000 and handles must use the Control Room's `out-left|right|top|bottom` and `in-left|right|top|bottom` anchors. It is paused-only and safe for workflows with queued history.

The API is intentionally loopback-only and origin-bound. It does not provide network access, telemetry, or a remote orchestration surface. A future MCP adapter, if needed, should call this API rather than duplicate engine authority and must retain the same consent boundaries.

## Persistent Agents

Discover action availability through `/api/capabilities`; all requests still use
`POST /api/actions`. Schema-v5 state adds project-scoped agents, native session
lineage, messages, questions, a provenance ledger and bounded audit records.
New workflows default to Hybrid; omitted settings in migrated workflows remain
legacy. Merely configuring an agent never creates a native thread or model turn.

| Action | Inputs and authority |
| --- | --- |
| `configure-project-agents` | `conversationDefault`: `hybrid`, `persistent`, or `one-off`; explicit workflow settings remain unchanged. |
| `upgrade-project-agents` | `confirmed:true`; explicitly enables project-agent behavior for legacy workflows. |
| `send-agent-message` | `agentId`, `message`; queues read-only discussion, still requiring execution consent and Run. |
| `answer-agent-question` | `questionId`, `message`; resumes the same bounded work item/session, not an unrelated retry. |
| `record-project-decision` | `body`, optional `kind`, `sourceTaskIds`, `confirmed:true`; records a human decision/goal/constraint, not agent authority. |
| `configure-agent-retention` | `retention` with validated session, audit, ledger and owned-storage budgets. |
| `rotate-agent` | `agentId`, `confirmed:true`; checkpoints provenance and prepares lazy successor lineage. |
| `compact-agent` | `agentId`, `confirmed:true`; requires installed-host support and native completion evidence. |
| `recover-agent-session` | `sessionId`, `confirmed:true`; inspects the exact native binding; uncertainty never creates a blind replacement. |
| `release-agent-session` | `sessionId`, `confirmed:true`; releases an idle subscription only with observed native evidence. |
| `cleanup-agent-sessions` | Retries eligible terminal-session archival; active/pinned/dependent/unresolved sessions remain protected. |

Native archival is not transcript deletion. Unknown native byte usage remains
unsupported. Restart revokes execution/write consent; source or agent messages
cannot grant it. See the [implementation audit](PERSISTENT-PROJECT-AGENTS-AUDIT.md)
for binding, continuation and cleanup limits.

## Local Client

Import `ControlRoomClient` from the installed skill's
`scripts/runtime/lib/control-client.mjs`. Use the verified launch receipt; do not
discover another room by scanning ports, copy secrets into a prompt, or log the
receipt. A setup chat can configure a workflow through this API instead of mouse
automation. Read the current state before a mutation and preserve unrelated work.

```js
const client = new ControlRoomClient({
  origin: receipt.origin,
  token: new URL(receipt.url).hash.slice('#token='.length),
  expectedInstanceId: receipt.instanceId,
  expectedWorkspace: receipt.workspace
});
const capabilities = await client.capabilities();
const state = await client.state();
await client.action({
  action: 'rename-workflow',
  workflowId: state.workflows[0].id,
  name: 'Release triage'
});
```

The optional identity expectations are checked before mutations. The client
rejects non-loopback URLs and redirects, pins the exact Origin, and keeps the
token/cookie out of ordinary object serialization. Treat its state responses as
private. The UI picks up API changes while its editor is clean; an unsaved draft
is not overwritten by a polling refresh.

This interface is not a permission broker. Only send `authorize`, `start`,
`accept`, cancellation or shutdown when the user has authorized that specific
operation. A human acceptance gate remains a deliberate user decision; the
server cannot tell whether an authenticated caller represents a human or agent.
