# Chronos Control Room

An open-source, opt-in local task queue with a browser control room. It is not included in the signed v0.9.4
ZIP, installed into your Codex profile, or submitted to the Plugin Directory.
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

Connect the dedicated runtime, add a bounded read task, then authorize execution
and start dispatch. Defaults are disconnected, paused and without execution
permission. Model choice follows the host default; model turns use your normal
Codex allowance/provider billing. Tasks and relevant workspace context go to
Codex's configured provider, not to the Chronos publisher.

Completed tasks wait for **Accept result**. Dependencies run only after acceptance.
Concurrency is one by default, at most two. Attempts are limited to three and
retries are explicit. Task time is bounded to ten minutes. Pause stops new
dispatch, not an already-running task; Cancel requests an interruption and
waits for its actual terminal event.

Remove finished or unwanted tasks to reclaim queue capacity. Dependency targets
cannot be removed until their dependent tasks are removed. Result summaries are
bounded to 2,000 characters; review the evidence before accepting them. The
ten-minute limit and concurrency limit are not a monetary spending cap.

Results are not independently verified simply because the model finished.
This edition supports read-only work, not autonomous code changes. Every new
thread must confirm the effective `readOnly` sandbox and `never` approval policy.
The dedicated process disables hooks, plugins, apps, browser automation and
multi-agent features. Inherited MCP servers are explicitly disabled and checked
before any model turn; only disabled metadata with empty catalogs is accepted.
Chronos never automatically approves permission requests. These restrictions
affect only its owned process, not your normal Desktop setup.

Read-only does not mean offline or limited to reading the selected directory.
Codex controls the filesystem sandbox; model traffic still goes to its provider.
Choose a workspace and instructions appropriate for your account and data policy.
Do not paste secrets into task instructions.

## Stop And Recover

Use **Disconnect** to stop the owned runtime and revoke session execution
permission while keeping the dashboard open. Use **Shut down** or Ctrl+C to close
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

## Verify Real Execution

The isolation probe checks permissions and external-tool inventories, but
hard-blocks `turn/start` so it sends no model task:

```powershell
node .\experimental\orchestrator\tests\isolation-check.mjs `
  --codex 'C:\absolute\path\to\codex.exe' --cwd 'C:\your\workspace'
```

The following **uses your Codex allowance**. It creates a disposable fixture
workspace under ignored `dist/`, runs real tasks, waits for human-acceptance
gating, interrupts a task after its shell command starts, stops only its own
runtime during another command, restores paused and explicitly retries:

```powershell
node .\experimental\orchestrator\tests\live-check.mjs `
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
