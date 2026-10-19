# Chronos Control Room

## Packaged v0.10.1 release

The published v0.10.1 plugin packages this Control Room as the
`chronos-control-room` onboarding skill. Users can ask Chronos to set up the room in
one prompt; the skill launches the bundled runtime, discovers the authenticated local
Codex executable, and returns a private loopback link. There is no separate server
command for normal onboarding. The room starts paused and disconnected, with execution
and workspace-write consent still explicit.

The packaged desktop path requires the local executor, Node.js 22+, an authenticated
Codex installation, and local Git for worktree-backed stages. It is tested locally on
Windows with Node.js 24, Edge and Codex CLI 0.163.0-alpha.10.2. This is not a claim of
compatibility with every Codex build or operating system. The package does not include
hooks, an MCP server, a hosted dashboard, or publisher telemetry. The full source
edition may include separately documented, opt-in hooks.

The onboarding can select the software-factory, research, engineering, or marketing
templates. `outcome_learning` and `tool_call_review` are optional read-only templates:
they inspect bounded native execution evidence and produce recommendations without
training models, changing permissions, or applying workflow changes automatically.
Their timing, token and cost fields remain unknown when the host does not expose them.

An open-source, opt-in local task queue with a browser control room. It is not included in the signed v0.9.4
ZIP. Both the full and skills-only v0.10.1 editions include Control Room; only the full edition includes
optional hooks. Both packages are available in the
[v0.10.1 GitHub release](https://github.com/FaxanFM/chronos/releases/tag/v0.10.1).
It does not attach to existing desktop chats. It creates its own managed tasks
through an installed Codex App Server using local stdio, not recurring prompts.

## Run Locally

Requires Node.js 22 or newer, an authenticated installed Codex executable and a local
workspace. No npm installation or API key collection is required. Authenticate
through Codex's normal supported flow if needed.

Locally tested on Windows with Node.js 24.15.0, Edge, and Codex CLI
`0.163.0-alpha.10.2`. Other hosts/builds must pass the same compatibility gates;
this is not a claim of platform-wide certification. Chronos is MIT licensed.

From the repository root, replace these paths with your actual selections:

```powershell
node .\experimental\orchestrator\server.mjs `
  --codex 'C:\absolute\path\to\codex.exe' `
  --cwd 'C:\your\workspace'
```

Open the private loopback link printed in the terminal. It contains a temporary
access token: keep it local. Optional `--state` chooses an explicit queue file;
the default is `experimental/orchestrator/.local/queue.json`, ignored by Git.
Optional `--codex-home` selects a different Codex home that must already have
its own supported authentication. Chronos never copies credentials. Optional
`--port` chooses a local port, otherwise a free port is used. The launch link
establishes a session cookie for reloads; a new server needs its new launch link.

Connect the dedicated runtime, add a work item, then authorize the session and
start dispatch. Use **Permissions**, **Authorize session**, **Run** and
**Add work item**; stage controls include accept, cancel, retry and archive.
Defaults are disconnected, paused and without execution permission. A restart
requires fresh consent. Model turns use your normal Codex allowance/provider
billing.

Stages configured for human acceptance wait for **Accept output**. Automatic
stages route only after native turn completion and their configured check, if any.
Neither automatic routing nor model completion proves that an answer is correct.
Concurrency is one by default and configurable up to 16, subject to the native
CPU/memory health ceiling. The contract allows 128 workflows, 512 nodes across
them, 2,048 reserved stage-task records and 16 slots per stage. Stages support `join: all` and
`join: any`, with accepted source task IDs bounded to 32. Attempts are limited
to three. Failed native checks may trigger bounded repair up to the stage's
attempt limit; other failures require explicit retry. Task time is bounded to ten minutes. Pause stops new
dispatch, not an already-running task; Cancel requests an interruption and
waits for its actual terminal event.

Remove finished or unwanted tasks to reclaim queue capacity. Dependency targets
cannot be removed until their dependent tasks are removed. Result summaries are
bounded to 2,000 characters; review the evidence before accepting them. The
ten-minute limit and concurrency limit are not a monetary spending cap.

## Design A Workflow

Choose **New from template** for software delivery, research, engineering or
marketing/SEO, or start blank. Drag stage connectors to form a directed acyclic
graph. Select a stage to set its assignment, model, workspace access, bot slots,
input join and output gate. Save before queueing work. A workflow with existing
work items is immutable: duplicate it to change the process without rewriting
history. Delete a selected connection with the graph's delete control/key.

**Add work item** accepts a bounded assignment, an optional
`codex://threads/<thread-id>` link and up to 32 accepted outbox inputs from any
workflow. The link is checked through the supported native API; dispatch creates
a new managed fork of its stored context, not control of its original Desktop
turn. No full account inventory or task-list completeness assertion is needed.

Each stage has an inbox, a bounded pool of execution slots and an accepted
outbox. `all` joins wait for every incoming stage; `any` joins run once after the
first accepted input and do not later rerun when other inputs arrive. Multiple
independent work items can advance asynchronously. A packet's writers are
serialized against all of its readers/writers; separate packets get separate
workspaces. Accepted outputs passed between stages are compact 2,000-character
summaries, native verification metadata and accepted artifact-workspace paths.
For larger artifacts, later stages must inspect those files; there is no hidden
full-report copy or cross-packet file merge. A large join is still subject to the
selected model's context limit; use intermediate synthesis stages for large flows.

Configure a native check as an argument array, for example
`["node", "--test"]`, using tools already installed on the machine. It runs in
the same sandbox and workspace, without an extra model turn, with a 60-second
command limit. Windows uses the host's output cap; Chronos bounds stored
receipts. A failed check never opens the accepted outbox. The templates do not
invent a universal test command for every project.

Use **Queues** to inspect receipts and accept, cancel or retry tasks. Archive a
whole work item to remove its stage history; its worktree and branch are kept.
Accepted outputs with dependent work items cannot be archived until those
dependents are archived. Release gates produce handoff material, not automatic
merges, deployments or external-account publishing.

**Runtime** shows the owned process, active turns, host free/total memory, CPU
count, server RSS and dispatch limits. The native 15-second heartbeat does not
call a model or require a scheduled chat. Low memory reduces dispatch capacity;
below 256 MiB free, new work waits. These observations do not certify other
Desktop chats, approvals, quota, context or all eight plugin Heartbeat families.

Hundreds of stage definitions are supported; hundreds of simultaneous model
workers are not claimed. The current hard execution ceiling is 16 and the
default is one. Provider limits, costs and available machine resources still
matter. Per-stage provider web search is opt-in; research/SEO templates select
it visibly in their editable stage settings. Shell network access remains off.

Results are not independently verified simply because the model finished.
Stages may be read-only or workspace-write. Writable stages use an owned
isolated Git worktree from committed `HEAD`; uncommitted changes are not copied.
Non-Git sources use an empty owned artifact directory. Native verification is
optional and configured by the workflow author; automatic output is not
semantic proof. The dedicated process disables hooks, plugins, apps, browser
automation and multi-agent features. External MCP accounts/apps are never
approved; inherited MCP metadata is disabled and checked before model turns.

Read-only does not mean offline or limited to reading the selected directory.
Codex controls the filesystem sandbox; model traffic still goes to its provider.
Choose a workspace and instructions appropriate for your account and data policy.
Do not paste secrets into task instructions.

## Stop And Recover

Use **Disconnect** to stop the owned runtime and revoke session execution
permission while keeping the dashboard open. Use **Stop Control Room** or Ctrl+C to close
the Control Room. Shutdown stops only the Codex subprocess this
control room created, not your Desktop app or unrelated tasks. The queue is
preserved locally and restores paused with execution permission revoked.
Uncertain tasks require confirming that their previous worker stopped before
retrying; never guess or replay automatically.

An exclusive `.lock` file prevents another process from using the same queue.
After a crash, use the same launch command with `--recover-stale-lock` only when
you intend recovery. It checks the recorded owner's PID and refuses live,
malformed or uncertain ownership; it never takes over a live process. This
proves only the queue owner stopped, not every old worker. Uncertain tasks still
block all new dispatch until you explicitly confirm that their worker stopped
and retry, cancel or remove them. A damaged lock or interrupted lock-recovery
operation requires manual inspection; do not delete locks blindly.

Remove the selected queue file only when you
explicitly want to erase its local instructions/results. No hooks, services,
recurrences, plugin installations or account settings are created by this app.

To remove the experiment, shut it down, then remove its selected private queue
and the `experimental/orchestrator` folder. Keep the queue instead if you need
its task history. There is no global service, scheduled task or hook to uninstall.

## Verify Without Spending Model Turns

```powershell
node --test .\experimental\orchestrator\tests\*.test.mjs
```

The browser fixture additionally needs a locally available Playwright package
and browser. Set `CHRONOS_TEST_DEPS` to its `node_modules` directory, optionally
`CHRONOS_BROWSER_CHANNEL=msedge`, then run:

```powershell
node .\experimental\orchestrator\tests\browser-check.mjs
```

Fixtures simulate model events; they do not claim live inference or unattended
desktop behavior. Screenshots go into ignored `dist/control-room-browser-check`.

The committed frontend bundle makes normal use independent of npm. To change
the ReactFlow UI as a developer, run `npm ci --prefix experimental/orchestrator`
then `npm --prefix experimental/orchestrator run build`. ReactFlow owns the
graph interaction; the native engine validates every saved DAG again.

## Verify Real Execution

The isolation probe checks permissions and external-tool inventories, but
hard-blocks `turn/start` so it sends no model task:

```powershell
node .\experimental\orchestrator\tests\isolation-check.mjs `
  --codex 'C:\absolute\path\to\codex.exe' --cwd 'C:\your\workspace'
```

The following **uses your Codex allowance**. It creates a disposable fixture
workspace under ignored `dist/` and runs the real four-stage writable workflow:
read intake -> isolated workspace-write build with native verification ->
independent read-only review with human approval -> release handoff with human
approval. The source checkout remains unchanged:

```powershell
node .\experimental\orchestrator\tests\live-workflow-check.mjs `
  --confirm-live-model-turns `
  --codex 'C:\absolute\path\to\codex.exe' `
  --output '.\dist\control-room-live-check'
```

Use a new output directory for each run. Read `report.json` there for results.
Normal Codex authentication must be available to the process. A command sandbox
that cannot access the normal credential store cannot validate live execution;
do not fix that by copying auth files or weakening task permissions.

With the same Playwright environment used for the fixture, the live browser
check runs one real file-reading task through the actual UI, then verifies
acceptance, authenticated reload, mobile layout and shutdown:

```powershell
node .\experimental\orchestrator\tests\live-browser-check.mjs `
  --confirm-live-model-turns `
  --codex 'C:\absolute\path\to\codex.exe' `
  --output '.\dist\control-room-live-browser-check'
```

See the [local verification record](../../docs/CONTROL-ROOM-LOCAL-VERIFICATION.md)
and [product decision](../../docs/ORCHESTRATOR-DECISION-2026-10-18.md) for evidence,
platform limits and the separate optional-hooks policy.
