# Control Room Local Verification

Tested October 18, 2026 (America/New_York). Scope: the separate open-source
`experimental/orchestrator` source, based on reviewed ancestor `72778c0`.
No marketplace submission or signed release was replaced.

## Environment

- Windows; Node.js 24.15.0; Edge through Playwright.
- Installed Codex CLI `0.163.0-alpha.10.2`.
- Effective model: `gpt-6.1-sol`, using normal Codex authentication.
- Effective task policy: `readOnly` sandbox, `never` approvals.
- Disposable local workspace containing only a randomly generated text fixture.

## Evidence

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Adapter, queue and HTTP regression tests | 33 passed | Protocol fixtures, not inference |
| Desktop browser workflow | PASS, 1440x1000 | Simulated adapter, no model turns |
| Mobile browser workflow | PASS, 390x844 | No overflow or JavaScript errors |
| Reload, acceptance, cancellation, removal, shutdown UI | PASS | Simulated task events |
| Real browser execution | PASS | One actual Codex shell-read task through the UI, consent, acceptance, reload, mobile layout and shutdown; no fixture protocol |
| Real task execution | PASS | Codex read the random file marker |
| Acceptance/dependency gate | PASS | Dependent attempted zero turns until acceptance; then returned the accepted marker |
| Native cancellation | PASS | Waited for a real shell-command start; requested interruption; observed native terminal interruption before releasing the slot |
| Process-loss recovery | PASS | Stopped only the owned App Server while a shell command was active; restored paused without consent; unconfirmed retry rejected; explicit retry completed |
| Workspace integrity | PASS | Original fixture bytes and directory contents unchanged |
| External-tool isolation | PASS | Two explicitly disabled MCP metadata records; zero available tools; probe sent no model turn |

The final live suite requested five model turns: normal work, its dependent,
the interrupted task, the lost-runtime attempt and its explicit retry. This is
not a claim that five independent jobs all completed successfully; interruption
and process loss are intentional failure cases.

Private machine-local receipts are ignored by Git:

- `dist/control-room-live-final-20261018/report.json`
- `dist/control-room-live-browser-final-20261018/report.json`
- `experimental/orchestrator/dist/control-room-browser-check/desktop.png`
- `experimental/orchestrator/dist/control-room-browser-check/mobile.png`

Reproduce with the commands in the [Control Room README](../experimental/orchestrator/README.md).
Use a new live-test output directory and opt in to model usage explicitly.

## Repairs Verified

- Missing login fails before starting a task. An initial command-sandbox probe
  could not access the normal credential store; the authenticated local test ran
  outside that outer sandbox without copying credentials or weakening task policy.
- Every task checks the host's effective policy, not just the requested settings.
- An empty MCP table did not remove inherited servers. Chronos now discovers
  names in memory, disables each for the thread and verifies disabled/empty
  catalogs before dispatch. Hooks and other automation features are disabled in
  the owned process only.
- An interrupt acknowledgement cannot finish a task. Missing terminal evidence
  pauses work and triggers bounded owned-runtime shutdown, not automatic retry.
- A stale event cannot settle another attempt. Unknown workers block all new
  dispatch and require explicit stop confirmation.
- Restart requires new consent. Queue ownership is exclusive; explicit stale-lock
  recovery refuses a live or uncertain owner and concurrent recovery races.
- The launch token is removed from the URL; an HttpOnly same-site session cookie
  supports reloads. Host/origin checks and bounded requests protect the loopback API.

## Limits

These results certify the tested local path, not every Codex build or OS. The
Control Room manages its own read-only tasks, not existing Desktop chats. Model
completion does not verify answer quality; acceptance remains with the user.
The sandbox is not an offline guarantee or a selected-directory read boundary.
No real forbidden-write attempt was made; the effective policy and rejection
paths were checked instead. No monetary budget enforcement or native Codex UI
integration is claimed. Optional plugin hooks remain a separate opt-in product.

Chronos receives no publisher telemetry. Codex/provider processing and normal
allowance or billing still apply. Local queue files contain plaintext task
instructions and summaries and must not be uploaded with bug reports.
