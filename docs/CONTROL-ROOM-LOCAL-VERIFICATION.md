# Control Room Local Verification

## v0.10.0 candidate verification boundary

This record covers the packaged Control Room candidate, not a marketplace submission.
The candidate was checked locally on Windows with Node.js 24, Edge, an authenticated
Codex CLI, and bundled Git. The current evidence is:

- 68/68 unit and regression tests passed, including the exact packaged entrypoint
  and native Git hook/filter isolation regressions.
- The browser bundle includes complete notices for all 18 bundled npm dependencies.
  The build discovers them from esbuild's input graph and fails if a license is
  missing. A source/runtime regression checks full MIT, ISC and BSD notices.
  Browser executable bytes are unchanged by this notice-only correction.
- The usability suite passed.
- The deterministic skills-only package contained 29 files and zero hooks.
- An extracted ZIP launched through the packaged onboarding entrypoint, discovered the
  normal host Codex login, created the software-factory queue, and loaded the optional
  `outcome_learning` and `tool_call_review` workflows. It returned a paused room with
  zero active turns and no model turn on launch.
- Reusing the same packaged command reused the existing instance; package and instance
  identity checks remained bound.
- Current desktop/mobile browser checks passed, including both opt-in learning
  templates, observed execution evidence, unchanged turn counts on template creation,
  consent, flow editing, queue acceptance and authenticated shutdown.
- Full and Directory release gates passed; both editions reproduced byte-for-byte.
  The current hashes are recorded in the submission packet, not the historical rows below.
- A clean local-catalog plugin-manager installation in an isolated `CODEX_HOME`
  installed version 0.10.0. All 29 installed files matched the exact Directory ZIP.
  The installed onboarding path and local-executor marker were preserved; no hooks
  were present. The installed launcher opened Research desk plus both learning
  modules, paused with zero active turns and no execution/write consent. Instance
  and package identities matched. Stop, plugin removal and catalog removal passed.
  This fixture did not use or copy the production login or change hook trust.
- The hardened replacement ZIP repeated that clean installation, all 29 file hashes,
  installed launcher, paused Research plus both learning templates, identity binding,
  stop and uninstall. Its hashes are the current ones in the submission packet.
- Native Git regression fixtures installed post-checkout, fsmonitor and filter
  marker commands. No marker ran during workspace setup, including when uncommitted
  attributes would select a clean filter. A committed filter blocked before packet
  workspace creation; the same packet succeeded after the fixture's reviewed repair.
  An unrelated `GIT_DIR` override could not redirect source selection.

This is local candidate evidence only. The clean installation used a local test
catalog, not the public OpenAI Directory. There has been no new marketplace
submission and no live certification on another OS.
The sandbox forward test that could not see the normal credential store is retained as
a boundary case; it must report a scoped authentication failure rather than claim the
host is logged out.

The host approval-review service recovered on October 19. A fresh normal-host run
of the exact installed package discovered the existing Codex login and opened
Research desk plus both learning workflows. It remained paused with zero active
turns, execution and write consent both false, and matching package/instance
identities. Authenticated shutdown passed. No credentials were copied.

A subsequent fresh four-stage engineering run against the hardened runtime passed
with four actual model turns. Native verification exited zero, the source fixture
remained unchanged, independent review completed, and downstream work stayed held
until human acceptance. These checks resolve the earlier execution blocker; they
do not themselves establish a GitHub CI result or Directory publication.

The first GitHub Windows run passed runtime, Inspector, Heartbeat, Supervision,
Governor, reproducibility and removal checks, then failed its signer-contract
step despite printing PASS. Its intentional wrong-trust probe left a nonzero
native exit status for GitHub's PowerShell wrapper. The test now clears that
status only after all assertions and cleanup succeed. The exact wrapper was
reproduced locally: trusted signature PASS, incorrect namespace rejected, exit
zero. Signature verification was never bypassed. Current-head CI results belong
to the PR receipt, not the earlier failed run.

An initial legacy native recheck interrupted Heartbeat after about seven minutes
without a verdict. The subsequent bounded rerun passed source and packaged
Heartbeat. Source Inspector, packaged Inspector, source Supervision and source
Governor have also passed in separate Windows PowerShell 5.1 processes.
Packaged Supervision and Governor passed as well; both Governor runs validated
49 scenarios. The earlier interruption was neither PASS nor an observed product
FAIL. All six native script files are byte-identical between the first and
hardened package records. Final native test processes exited with code zero.

Core live execution tested October 18, 2026 (America/New_York). The packaged
integration and 68-test/browser/package rerun continued on October 19.
Scope: the separate open-source `experimental/orchestrator` Control Room 0.2.0 and its
v0.10.0 packaged onboarding candidate.
No marketplace submission, main-branch release or signed plugin ZIP was replaced.

## Environment

- Windows, Node.js 24.15.0 for the initial runs and bundled Node.js 24.19.0 for
  the final authenticated package and live workflow checks; Edge through Playwright.
- Installed Codex CLI `0.163.0-alpha.10.2`, normal ChatGPT login.
- Effective model `gpt-6.1-sol`, approvals `never`.
- Effective policies checked natively: `readOnly` and `workspaceWrite` with
  the explicit packet-owned root, shell network disabled.
- Disposable workflow fixtures and an isolated local-catalog plugin installation
  only. No production plugin install, hook-trust change or marketplace account action.

## Prior Core Runtime Results

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
- `dist/control-room-final-live-20261019/report.json`: fresh hardened four-stage PASS.
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
