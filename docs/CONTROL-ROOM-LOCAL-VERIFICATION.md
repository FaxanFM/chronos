# Control Room Local Verification

Tested October 18, 2026 (America/New_York), including runs after midnight UTC.
Scope: the separate open-source `experimental/orchestrator` Control Room 0.2.0.
No marketplace submission, main-branch release or signed plugin ZIP was replaced.

## Environment

- Windows, Node.js 24.15.0, Edge through Playwright.
- Installed Codex CLI `0.163.0-alpha.10.2`, normal ChatGPT login.
- Effective model `gpt-6.1-sol`, approvals `never`.
- Effective policies checked natively: `readOnly` and `workspaceWrite` with
  the explicit packet-owned root, shell network disabled.
- Disposable fixtures only. No external account action or local plugin install.

## Current Results

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Automated unit/regression suite | 54 passed | Adapter protocol fixtures, real disposable Git worktree tests, engine and HTTP boundaries; no model usage |
| Desktop/mobile workflow UI | PASS | Real browser, simulated model events; graph editing, stage settings, native check argv, linked intake, source-outbox selection, consent, execution, acceptance, archive, polling, reload and shutdown |
| Real four-stage engineering workflow | PASS | Four actual model turns: read intake, isolated implementation, independent read-only review and human-gated release handoff |
| Native test verification | PASS | App Server command/exec independently ran Node tests in the writer's worktree, exit 0, before accepting the build output |
| Source integrity | PASS | Writer changed only its isolated worktree; source fixture bytes remained unchanged |
| Human review gate | PASS | No handoff task existed until explicit review acceptance |
| Real execution through current UI | PASS | One actual shell-read task, session consent, acceptance, authenticated reload, mobile layout and shutdown |
| Native cancellation | PASS | Real shell command started; terminal interruption observed before capacity release |
| Process loss and restart | PASS | Owned runtime stopped during a real command; paused restore, revoked consent, unconfirmed retry rejection and explicit retry completion |
| Selected thread fork preflight | PASS | Actual native thread/fork; zero model tasks sent; original thread not resumed |
| Writable-root preflight | PASS | Actual isolated writer setup with effective root/policy checked; zero model tasks sent |
| External-tool isolation | PASS | Two disabled MCP metadata records, zero available external tools before execution |
| Dependency audit | PASS | npm audit --omit=dev reported zero known vulnerabilities at test time |

The failure/recovery suite requested five turns: normal work, a dependent, an
interrupted task, a lost-runtime attempt and its explicit retry. The four-stage
writable workflow requested four turns. The current browser UI requested one
additional real turn. Failure cases are intentional and are not counted as
successful independent jobs.

## Reproductions And Repairs

An initial writable run completed the code change and model-run tests, but the
separate native verifier rejected `outputBytesCap`: that field is unsupported
by this Windows sandbox. Chronos now omits it on Windows, preserves the sandbox
and 60-second timeout, and bounds retained output locally. The no-model command
probe and fresh four-stage run then passed. No failure receipt was relabeled.

Other verified boundaries:

- `runtimeWorkspaceRoots` requires the installed experimental protocol capability;
  setup explicitly opts into it and verifies the returned policy.
- Native goal continuation is disabled. A thread link forks stored context with
  deferred continuation; it never resumes or interrupts the original turn.
- Empty MCP configuration alone did not remove inherited servers. Each discovered
  name is explicitly disabled, then disabled/empty catalogs are checked natively.
- Acknowledged cancellation is not termination. Missing terminal evidence closes
  only the owned runtime and leaves uncertain work blocked for explicit recovery.
- A missing verifier cannot accept a stage that requires native checks. Failed
  checks trigger at most the configured repair attempts, never an accepted outbox.
- Same-packet writers cannot overlap readers or other writers. Independent packets
  have separate owned worktrees. Committed HEAD is the base; dirty source changes
  are not silently copied.
- Workflow definitions with work items are immutable. Packet outputs must match
  their accepted task on restore. Whole-item archive preserves the workspace.
- The launch fragment is removed immediately; an HttpOnly same-site cookie supports
  reload. Origin/Host checks, fixed static routes and bounded requests remain active.
- Polling cannot replace unsaved graph edits. The graph refits at mobile sizes,
  and stage settings remain available as a drawer rather than disappearing.

Private receipts and screenshots are ignored by Git:

- `dist/control-room-live-workflow-20261018-a/report.json`: retained initial failure.
- `dist/control-room-live-workflow-20261018-b/report.json`: repaired four-stage PASS.
- `dist/control-room-live-recovery-20261018-expanded/report.json`.
- `dist/control-room-live-browser-20261018-expanded/report.json`.
- `experimental/orchestrator/dist/control-room-browser-check/`.

Run the commands in the [Control Room README](../experimental/orchestrator/README.md).
Use a fresh output directory and explicitly opt into real model usage.

## Limits

These results establish the tested Windows path, not live compatibility with
every Codex build or OS. Graph limits permit 512 stage definitions, not hundreds
of simultaneous turns: concurrency defaults to one and is capped at 16, with
native CPU/memory-based ceilings. There is no monetary spending cap.

The native heartbeat observes the owned child process, managed queue and host
resource evidence. It does not evaluate other Desktop chats, approvals, quota,
context or all eight plugin Heartbeat families. No complete account inventory
is required or claimed. The app is local-browser UI, not an embedded Codex panel.

Automatic routing and model completion do not establish semantic correctness.
Native checks are optional author-configured commands; model review is not a
machine-enforced reviewer verdict. Human gates remain explicit. A release stage
prepares a handoff; it does not merge, publish, install or operate external accounts.

Chronos sends no publisher telemetry. Model/provider processing and the user's
allowance or billing apply. Queue files contain plaintext inputs and summaries;
keep them and private launch links out of support reports. Optional plugin hooks
are separate, opt-in, and neither installed nor needed by Control Room.
