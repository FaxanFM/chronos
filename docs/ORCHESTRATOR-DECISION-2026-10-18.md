# Chronos Orchestration Decision

Decision date: October 18, 2026. Reviewed source: `72778c0` plus the separate
`experimental/orchestrator` prototype. This is a product decision, not a new
release or marketplace approval. The local verification below now includes real
model execution; it does not claim unattended control of existing Desktop chats.

## Decision

**Keep Chronos. Rebuild the orchestration path around a user-started local
runtime, and hold universal/autonomous orchestration claims.** Do not ship another
scheduled Governor prompt as proof that an orchestrator works.

There are two distinct products to validate:

- The existing plugin: selected/visible desktop-chat workflows, evidence-bound
  diagnostics, and bounded read-worker coordination through available host tools.
- The proposed Control Room: a local task queue whose own Codex App Server runs
  managed read-only tasks. Completion events advance the queue; accepted results
  release dependencies. It does not secretly attach to the Desktop app.

This is feasible, but it is not yet a full replacement for a human coordinator
or an automatically installed, account-wide Codex control plane. If release
claims cannot state this distinction plainly, do not publish those claims.

## Current Platform Evidence

The [plugin architecture](https://developers.openai.com/plugins/concepts/plugins)
supports skills, MCP tools, and optional UI. This is an integration model, not a
grant of access to every existing Codex conversation.

[MCP App UI](https://developers.openai.com/plugins/build/chatgpt-ui) renders in
compatible hosts, with ChatGPT documented explicitly. Native Codex sidebar
rendering is not established by that documentation. Keep the tools usable
without UI. A local browser control room is a concrete, testable alternative.

The [App Server](https://learn.chatgpt.com/docs/app-server) documents local stdio
transport, thread/turn operations, notifications, approval flows, and version-
generated schemas. The experimental WebSocket warning must not be generalized
to claim the documented local stdio transport does not exist. A new stdio
process owns a separate runtime; no supported automatic attachment to the
already-running Desktop app was established in this review.

The installed CLI exposes `thread/loaded/list`, runtime status notifications and
paginated `thread/list`. That does not make its own process's loaded threads an
inventory of another process. Chronos's 50-visible-plus-selected policy can
remain bounded without fabricating account completeness or treating unloaded
threads as live.

[Public submission rules](https://developers.openai.com/plugins/deploy/submission)
still exclude lifecycle hooks. The
[desktop-only route](https://developers.openai.com/plugins/deploy/desktop-only)
allows local stdio MCP submissions only for approved, allowlisted partners; it
is not an automatic distribution entitlement or hook exception. Dravara's local
MCP submission eligibility has not been established.

## Hooks Decision

Hooks remain optional and separately consented. A reviewed GitHub hook companion
may improve lifecycle evidence. It must not be a hidden store-package patch,
trust-store edit, execution-policy bypass, or automatic approval.

No standalone hook-patch installer was added in this pass. The existing manual
full-edition route remains separate. Before adding a patch, require an immutable
signed release, verified bytes, exact five-event definitions, narrow installation
scope, user review/trust through supported controls, rollback, and observed
execution. A user opt-in does not override marketplace or workspace policy.

Hooks cannot start an idle model on a timer simply by existing. Lifecycle
continuations can extend a running turn, but must be bounded and must not be
sold as an always-on scheduler. The new queue does not require hooks.

## Prototype Built In This Pass

The separate `experimental/orchestrator` uses Node built-ins and an installed
Codex executable. It adds no package files or manifest changes to v0.9.4.

- A working local control-room UI, not a screenshot or embedded-Codex UI claim.
- Explicit session execution opt-in, initially disconnected and paused.
- Up to 64 task records, concurrency one or two, at most three explicit attempts.
- A dependency graph: completion means ready for review, not accepted.
- Verified read-only task sessions, no approval escalation, no automatic publication,
  installation, hook trust, arbitrary-thread takeover, or worker spawning.
- Terminal-event validation; tool/item completion cannot finish the whole task.
- Pause stops new dispatch. Cancel waits for termination; acknowledgement alone
  does not release capacity. A bounded interruption failure closes only the
  runtime this process started and requires explicit recovery.
- A ten-minute task budget and fifteen-second cancellation grace period.
- Private loopback API with a per-process random token, origin/Host validation,
  strict static routes, bounded bodies, and no third-party frontend downloads.
- Local queue persistence, one writer, no auto-resume after restart, and no
  automatic replay of uncertain work. Unknown state remains blocked.
- Per-process hooks/apps/plugins/browser/multi-agent restrictions, explicit
  per-thread disabling of inherited MCP servers, and a pre-turn inventory gate
  requiring no available external tools. Disabled metadata is not an active tool.
- Explicit owner-lock recovery only after a dead-PID check. Uncertain old workers
  block all replacement dispatch until the operator confirms they stopped.

The model remains responsible for the quality of a report; the queue cannot
prove that an LLM's answer is correct. Human acceptance is an explicit gate.
Read-only execution is intentionally retained. Safe parallel edits, isolated
worktrees, merge verification, spending controls and richer model selection
require additional work before broad distribution.

## Privacy And Cost

The publisher receives no runtime telemetry. This is not a claim that nothing
leaves the computer: when a task runs, its instruction, relevant workspace
context and results are processed by Codex's configured provider under the
user's account and policies. Those turns consume the user's allowance or
configured provider billing. An authenticated Codex install is required.

The queue file contains task instructions, result summaries and managed runtime
identifiers in plaintext locally. Keep it private. The launch fragment is an
ephemeral local API credential; do not share it, record it in a video or include
it in support reports. An HttpOnly same-site session cookie permits reloads;
restarting the server requires its new private launch link. Nothing reads raw chat logs, databases or credentials
to discover arbitrary tasks. The companion invokes the installed Codex process,
which loads its own normal authentication. Configuration restrictions are
process/thread overrides, not edits to the user's normal profile. Configured
MCP server names are inspected in memory only to disable them; config values,
server names and account details are not exposed in the queue or diagnostics.

## Evidence And Release Gate

Result: **33 automated tests passed**, plus the simulated browser workflow at
1440x1000 and 390x844 with no horizontal overflow or JavaScript errors. The browser
fixture also covers reload authentication, acceptance, cancellation, removal
and shutdown. These browser events remain explicitly simulated.

The final real local suite used five requested Codex turns on Windows with CLI
`0.163.0-alpha.10.2` and effective `gpt-6.1-sol`, `readOnly`, `never` policy. It
passed file reading, explicit acceptance before dependent dispatch, native
cancellation after shell execution started, runtime-process loss, paused restore,
fresh consent and explicit retry. The disposable workspace stayed unchanged.
A separate no-model probe verified two disabled MCP metadata records and zero
available external tools. No hooks, recurrences, plugin installations or account
settings were changed. See the [verification record](CONTROL-ROOM-LOCAL-VERIFICATION.md).

One additional real task passed through the browser UI itself, including the
consent dialog, effective-policy display, file result, acceptance, authenticated
reload, mobile layout and shutdown. This is separate from the simulated browser
suite and the five-turn runtime failure/recovery suite.

This supports publishing experimental source with these exact boundaries.
Read-only configuration was verified through returned policy and protocol
regression tests, not a real forbidden-write attempt. Cross-platform certification, autonomous
edits, spending limits, native embedded UI and marketplace packaging remain
separate gates. Do not change the submitted v0.9.4 artifact or announce the
Control Room as already available in the store.

**Go:** develop the user-started local orchestrator and optional UI integration.
**No-go:** claim every Codex user gets universal background governance or a native
Codex dashboard merely by installing today's skills-only store package.
