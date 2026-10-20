# Multi-Agent Orchestration Audit And Implementation Plan

Audit date: 2026-10-19. Baseline: Chronos v0.10.2, source
`55cd7ee5b459f35bc9bec25b917a8f0ad619baad`.
This is a source audit and staged engineering plan, not a release approval.

## Decision

The managed-runtime architecture can support this proposal. Preserve it. A
desktop-wide control API is not a prerequisite for independently executing
managed agents, clarification, bounded correction, or parallel read work.

The main product gap is durable revision-aware feedback, not a missing
scheduler. Existing accepted file outputs share a mutable packet worktree;
they are not immutable artifact checkpoints. Do not enable automatic backward
write rework until checkpoint isolation is implemented and verified.

## Baseline Requirement Map

Statuses below describe the audited baseline, before implementation.

| Requirement | Status | Evidence and remaining work |
| --- | --- | --- |
| Structured acyclic DAG, dependencies, joins and parallel slots | Implemented | `experimental/orchestrator/lib/workflow-contracts.mjs`, `engine.mjs`; cycles are rejected. |
| Collaborative execution mode | Missing | No feedback overlay or mode selector. |
| Six typed message kinds and exact work-item/stage/artifact references | Missing | Queue state has tasks, events, packets and workflows, but no message protocol. |
| Clarification, response and backward rejected-output routing | Missing | Forward routing only, one task per node. |
| Bounded attempts and task deadlines | Implemented | Engine attempt caps, interruption watchdog, timeout, native-check repair. |
| Feedback iteration budgets, request deadlines and escalation | Missing | Task retry caps do not bound cross-stage cycles. |
| Revision tracking and stale-output invalidation | Missing | Selected packet outputs contain task ID and summary only. |
| Preservation of prior accepted artifacts | Partial | Summaries and isolated files persist; files are mutable, not revision checkpoints. |
| Failure isolation and independent accepted branches | Partial | Dependencies fail closed; native checks repair locally. No typed upstream recovery. |
| Failure classification and actionable routing | Partial | Verification/start/restart/permission errors exist, but no unified recovery taxonomy. |
| Selected Desktop context inspection and managed fork | Implemented | `codex-adapter.mjs` uses `thread/read` and `thread/fork`; it does not control the original chat. |
| Live external Desktop send/events/ownership adapter | Capability-dependent | No verified production transport exposed to this runtime. Keep unavailable, not inferred from another app-server process. |
| Guided goal-to-plan setup, models and thinking levels | Implemented | `setup-plan.mjs`, setup skill, frontend stage editor. |
| Versioned remaining-plan proposals and authorization | Missing | Referenced workflows intentionally cannot be edited. |
| Durable queue/graph restoration | Implemented | Engine persists and validates state, takes exclusive lock, restores paused. |
| Safe interrupted/uncertain-task handling | Partial | Consent resets; uncertain workers require explicit stop confirmation. No independent reconciliation transport. |
| Durable messages, revisions and recovery checkpoints | Missing | No collaboration state exists to restore. |
| DAG, queues, review gates, models and runtime UI | Implemented | `frontend/main.jsx`, local authenticated `server.mjs`. |
| Feedback timeline, rework paths, stale markers and escalation UI | Missing | Needs additive collaboration panel and clear current/history distinction. |
| Attempts, native checks and observed execution aggregates | Implemented | Bounded native item-event counts, wall time and check receipts. |
| Wait/revision time and artifact producer/verifier lineage | Partial | Timestamps and dependencies exist; no complete revision lineage. |
| Authoritative token usage and monetary budgets | Missing | Current adapter does not collect token-usage events. Do not estimate from text or duration. |
| Bounded concurrency and capacity | Implemented | Maximum 16 turns, 2,048 task records and 512 stage definitions. These are limits, not measured large-scale performance. |
| Measured collaboration success and intervention reduction | Missing | Requires actual execution evidence and a predeclared comparison, not a prompt-only demonstration. |
| Skills-only compatibility, optional hooks and consent boundaries | Implemented | Control Room needs no hooks or recurrence. Managed runtime isolates account tools/hooks and checks policy. |

Relevant baseline tests: `workflow*.test.mjs`, `engine.test.mjs`,
`codex-adapter.test.mjs`, `setup-plan.test.mjs`, `runtime-health.test.mjs`.

## Reuse And Regression Risks

Reuse the serial engine action queue, validated DAG, adapter-owned event stream,
native verification, dependency handoff, isolated workspace manager, model
catalog, authenticated local API, ReactFlow editor and immutable workflow rule.
Do not replace Governor, Heartbeat, the launcher or the working managed executor.

High-risk boundaries:

- A successful model turn is not necessarily an accepted deliverable.
- A delayed completion must not replace a newer revision.
- A second feedback request must not create an unbounded or concurrent loop.
- Current selection must be distinct from immutable accepted history.
- Rework must invalidate consumers, not unrelated successful branches.
- Restart must not restore execution consent or silently resume uncertain work.
- A native-check command, dependency result or agent message is data, not an
  authorization to expand tools, permissions or deployment scope.
- File checkpoint creation must reject symlinks, junctions and hooks/filters,
  have size limits and avoid hidden broad Git commits or external effects.

## Scoped Implementation

### A. Read-Only Collaborative Core

Implement an opt-in Collaborative mode beside the unchanged Structured default.
First support read-only stages only, with a specific compatibility error for
workspace-write stages. This makes accepted textual artifacts immutable and
keeps existing write workflows fully usable in Structured mode.

1. Add a strict, versioned result envelope and the six typed message kinds:
   clarification, response, change_request, rejection, blocker, resolution.
   The engine stamps sender, packet and stage identity; agents cannot supply
   authority or arbitrary target task IDs. Validate exact artifact references.
2. Add persisted per-packet revision selections, accepted history and messages.
   Preserve old accepted summaries and hashes. Mark stale/superseded tasks
   explicitly; never overwrite prior accepted work.
3. Permit backward requests only to an accepted ancestor within the same
   packet. Queue a new task revision, not a graph edge or an unrestricted loop.
   Invalidate only its downstream branch. Bound iterations, request time and
   total tasks/messages. Related active/uncertain work must block rework.
4. Require replies to the exact pending request. Preserve human approval gates
   for revised results. Block malformed/unsupported agent output explicitly.
5. Add mode controls, revision labels and a message/escalation timeline to the
   existing UI. Operator resolution is bounded context, not a permission grant.
6. Restore collaboration state paused; validate all references and hashes.

Acceptance: reviewer requests an upstream correction, one new revision is
created, exact reply resolves it, affected dependents are re-evaluated,
independent accepted work remains selected, limits escalate, stale events are
ignored and restart never duplicates execution or restores consent.

### B. Immutable File Artifacts And Recovery

Introduce bounded owned artifact checkpoints before enabling collaborative
workspace writes. Bind every revision to its producer, input revisions,
manifest hashes, workspace identity and native-check receipt. Materialize
rework in a separate owned workspace. Retain prior accepted files. Classify
infrastructure/check/rejection/context/unrecoverable failures and expose
branch-local recovery with explicit uncertain-worker reconciliation.

Acceptance: deliberately incorrect implementation is repaired without changing
the accepted independent branch or prior file checkpoint; interrupted work
requires renewed consent and verified stop before an authorized retry.

### C. Adaptive Plans And Observability

Add immutable plan versions, proposed diffs of remaining work and explicit
authorization for changed permissions, turn budgets or external effects.
Collect authoritative token-usage events where available; otherwise show
unavailable. Add waiting/rework timings and bounded history export. Compare a
fixed Structured baseline and Collaborative variant on declared outcomes.

### D. Optional Desktop Adapter

Probe a supported, explicitly authorized transport for the selected original
Desktop session. Require verified target identity, ownership, send capability
and response events. If absent, keep inspect/fork-only context support and all
managed execution working. Do not scrape internal Desktop databases or treat
a new process's loaded threads as another process's live inventory.

The [official App Server documentation](https://learn.chatgpt.com/docs/app-server)
documents thread start/resume/fork, loaded-thread events and token-usage events.
It does not establish universal control of a separately running Desktop chat.
That boundary remains capability-dependent rather than a product prerequisite.

## Validation And Release Gates

Run the existing Node suite before changes. Add deterministic protocol, branch,
restart, stale-event, consent, capacity and timeout tests; then run actual local
managed turns for clarification/rejection/resolution and independent parallel
work. Simulated transport tests prove contracts, not live model execution.
Verify desktop/mobile UI states and permission tooltips. Rebuild and verify the
packaged payload only after source checks pass. Retain a skills-only edition and
separate optional hook edition. No marketplace submission, installed-plugin
replacement, GitHub release or acceptance of the PUPMKT workflow is implied by
this implementation work.

## Implementation Receipt

Milestone A is implemented as an unreleased, read-only Collaborative beta.
The baseline requirement map above is intentionally retained as the pre-change
audit. This is not completion of milestones B-D or the entire proposal.

Delivered:

- Strict native structured-output envelope with all six message kinds. Sender
  identity comes from the engine-owned task, not agent-supplied authority.
- Accepted-ancestor targeting, exact artifact references and request-bound
  replies. Duplicate/stale completions cannot overwrite a newer revision.
- Bounded per-packet backward rework, affected-branch invalidation and preserved
  accepted text history with SHA-256 identities and producer/input lineage.
- Request deadlines, iteration escalation, bounded operator resolution and
  cancellation containment. Answered requests do not expire while waiting for
  human acceptance. Cancelling a rework worker closes its request only after
  observed termination or explicit stopped-worker recovery.
- Schema-v3 collaboration persistence with adversarial reference/hash checks.
  Existing structured v1/v2 queues remain supported. Older runtimes cannot load
  the new v3 state; keep the original runtime/state boundary when downgrading.
- Segmented mode control, feedback limits, message timeline, current/history
  labels and preserved human review gates. Structured remains the default.
- Complete packaged module inclusion and relative-import integrity test. The
  development payload has 16 runtime files; it does not replace published
  v0.10.2 assets or change the installed plugin.

Native checks remain deliverable gates: a clarification/rejection is a request,
not a clean deliverable, and may route without accepting the requesting stage.
A completed answer/deliverable must still pass its configured native check and
its configured automatic or human acceptance rule. Text hashes verify accepted
response text only, not files, factual correctness or independent approval.

### Verified Results

- Existing baseline: 90/90 Node tests passed before implementation.
- Final source and packaged runtime checks: 117/117 Node tests passed.
- Real local native Codex proof: PASS, five actual model turns, maximum two
  managed-active tasks, six completed native commands, one typed clarification
  and one exact reply. A synthetic legacy rate of 0.5 was deliberately supplied
  as an unverified fault-injection fixture; the corrected rate was 120/60 = 2
  events per second. This is a controlled execution test, not a claim of measured
  production success or reduced token cost.
- The independent branch executed once and remained selected. The earlier
  accepted analyst response stayed in history. Revised review stopped at the
  human gate and was not accepted.
- Actual proof-room shutdown/reopen retained messages and revisions, restored
  paused/disconnected with Run disabled, and did not launch new model turns.
- Browser QA: desktop 1365x900 and mobile 390x844, no page-width or text overflow;
  Structured duplication, collaborative-write rejection, saving a read-only
  Collaborative template and changing/saving feedback limits all passed.
- Token usage and monetary cost remain unavailable; no estimates were invented.

Reproduction from `experimental/orchestrator` using a supported Node runtime:

```powershell
node --test 'tests/*.test.mjs'
node tests/live-collaboration-check.mjs --confirm-live-model-turns `
  --codex $env:CODEX_CLI_PATH --output .local/collaboration-proof
```

The second command intentionally consumes Codex allowance. Its five-turn,
read-only synthetic fixture does not accept the final human review gate.
Private queue and aggregate receipts are retained locally under `.local/` and
are not included in the plugin package.

### Milestone B Implementation Receipt

The v0.11.0 unpublished candidate now implements immutable file checkpoints and
bounded collaborative write rework. The earlier Milestone A results above are
historical; its read-only restriction and 16-file payload are superseded in this
candidate, not retroactively changed in a published release.

- Content-addressed file blobs and strict manifests bind producer, source,
  workspace, input revisions and native-check evidence. Hash verification is
  enforced before materialization, recovery, review and acceptance.
- Each write/repair attempt and file-consuming reviewer gets a fresh private
  directory. Three-way joins preserve unchanged paths and deletions; divergent
  changes, unsafe paths and case/prefix collisions block explicitly.
- Earlier accepted file snapshots remain intact. Native-check failures may
  create bounded unaccepted repair checkpoints; interrupted partial writes are
  never adopted on restart. Schema-v4 restores paused/disconnected, revokes both
  permissions and requires explicit unknown-worker stop confirmation.
- Root `.git` alone is excluded. Snapshot caps are 4,096 files / 64 MiB. Links,
  hardlinks, missing/altered objects, owner/source mismatches and changing trees
  fail closed. This is hash-verified append-only history, not OS write-once
  protection against an administrator or a same-user process.
- Windows native checks exposed a 268-character generated-CWD defect. Compact
  24-hex workspace names and a preflight limit fix it without changing the
  sandbox. Explicit JSON stage/artifact bindings replaced ambiguous routing
  labels after a real reviewer returned an invalid route.

Verified locally for the checkpoint-engine candidate, before the UX/API follow-up:

- Source Node suite: 156/156 PASS. Extracted skills-only runtime backend suite:
  91/91 PASS against unchanged packaged modules. The payload has 17 runtime files.
- Inbox Windows PowerShell 5.1 source Inspector, Heartbeat, Supervision and
  Governor gates PASS; Governor validated 49 declared scenarios. The release
  gate passed with 2/2 byte-identical builds. Counts are checks, not a security
  coverage percentage or all-OS certification.
- Real native Codex write/rejection/correction/restart proof: PASS, six dispatched
  turns, one typed rejection and a valid request-bound resolution. The initial
  `Math.abs` implementation was deliberate fault injection; real review found
  the negative-number/invalid-value defect, and real correction passed checks.
- The correction's first attempt was stopped in its owned runtime. Restored
  execution stayed paused with permissions revoked and required confirmed stop
  before retry. Recovery used a fresh directory. Original source and the prior
  bad checkpoint remained unchanged; the independent branch executed once.
- The revised reviewer ran a native check successfully and remained at human
  review, unaccepted. No install, hook trust change, recurrence, deployment,
  external Desktop control or PUPMKT acceptance occurred.
- Both native check scripts in both accepted build revisions matched their
  verified committed-seed hashes (four comparisons); neither worker weakened
  the checks. Comparison uses the seed's actual checkout bytes, not uncommitted
  source bytes subject to Git's platform line-ending conversion.
- The extracted skills-only dashboard reopened the actual proof state, paused,
  zero active turns, Run disabled. Desktop and 390x844 mobile review layouts
  showed the verified file receipt and history without document-width overflow.

Reproduction and privacy/retention limits are in
[the checkpoint contract](COLLABORATIVE-WRITE-CHECKPOINTS.md). Private aggregate
receipt: `experimental/orchestrator/.local/write-proof-e/report.json`; raw test
queues, model results and screenshots remain local and are not packaged.

### Remaining Scope

General infrastructure recovery and automatic worker reconciliation remain
partial. Versioned replanning, authoritative token budgets, comparative autonomy
evaluation and external Desktop coordination are not delivered. Preparing the
v0.11.0 full and skills-only ZIPs does not publish GitHub assets or submit to the
Directory. Existing immutable releases remain unchanged.

### Workflow UX/API Follow-Up

The subsequent candidate adds display-name/layout-only saves for referenced
workflows, eight named anchors, touch selectors, search/filter controls, stage
duplication and focus, responsive canvas mode and a private API client. The API
uses the existing authority boundary; authentication does not prove human intent.
Dirty drafts survive name changes and external polling updates.

Current source suite: 167/167 PASS. Exact extracted skills-only backend: 118/118
PASS. Both editions built twice identically, with 18 runtime files. Browser checks
covered 23 phone/tablet/monitor and zoom-equivalent CSS layouts, plus live API/UI
rename, anchor persistence, keyboard dialogs and focus mode. Native browser zoom,
physical devices and a new real model execution were not exercised in this pass.
See [current receipts](RELEASE-v0.11.0-CANDIDATE.md) and
[local API](CONTROL-ROOM-API.md). The prior native fault-injection proof remains
historical evidence for the unchanged dispatch/checkpoint behavior, not a new
native PASS for the current ZIP identity.
