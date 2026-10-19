---
name: chronos-control-room
description: Launch, set up, reopen, or stop Chronos Control Room for a local workspace; build visual bot pipelines and review outcome or tool-call learning recommendations. Use for Chronos dashboard and managed workflow requests. Windows Inspector and existing-chat Governor monitoring remain separate opt-in capabilities.
---

# Chronos Control Room

## One-Prompt Setup

A request to set up or open Control Room authorizes starting its packaged local
UI process for the selected workspace. Do the launch yourself; do not hand the
user a server command. No repository clone, npm install, GitHub patch, lifecycle
hook, local MCP connection, API key, recurring chat or OS service is required.

Use the current chat's project as the workspace unless the user selects another.
Ask for its absolute directory only if it cannot be determined. Default to the
Software factory template, one concurrent turn and learning modules off when no
purpose is supplied. Choose `research`, `marketing` or `engineering` when that is
the requested workflow. Respect explicit template, model, concurrency and
workspace choices already supplied.

When the user describes an outcome or supplies a framework file/folder, do the
configuration work in this chat. Read [guided setup](references/guided-setup.md),
prepare a bounded plan from the selected context, and launch with `--setup-plan`.
Open the prepared workflow for review; do not require the user to learn the
editor first. Reopening an existing room without a new assignment needs no plan.

Before launching, briefly disclose:

Explain privacy and execution permissions in plain language:

> Control Room starts a private local process and opens your workflow dashboard.
> It stays paused until execution is authorized and Run is selected. Managed bots
> use your Codex login and allowance; assigned inputs, selected thread context and
> relevant workspace data go to your configured provider. Chronos sends no
> publisher telemetry. Queue history and worktrees stay locally in your Codex
> profile until removed. The process can keep running after this chat ends; Stop
> Control Room shuts it down. It does not start with your operating system.

Execution and writes are separate permissions. Setup alone does not authorize
model turns, code changes, publication, hooks, diagnostics or a scheduled Governor.
Collect any requested choices in this setup chat before changing permissions.
Do not repeat an explicit choice already given by the human.

### Launch The Packaged Runtime

1. Resolve this installed skill's absolute directory. Its executable entry is
   `scripts/launch.mjs`; never use a developer checkout or a fixed username,
   version hash, port, Node path or Codex path.
2. Use the host's workspace-dependency locator when available to obtain its
   bundled Node executable and Git executable. Otherwise resolve an installed
   `node` and verify version 22 or newer. Pass a provided bundled Git path with
   `--git <absolute-executable>` so write stages do not depend on PATH. Git is
   required for source worktrees, not for opening the read-only dashboard.
   Do not download a runtime or change PATH silently.
3. Invoke the selected Node executable with the rooted entrypoint and structured
   arguments: `--workspace <absolute-directory> --template software_factory
   --max-concurrency 1 --connect`, replacing the template with the chosen purpose.
   Use normal local execution and the user's
   existing Codex authentication. The launcher discovers Codex from the host's
   `CODEX_CLI_PATH`, supported application locations or PATH. Supply `--codex
   <absolute-native-or-JS-entry>` only when the host explicitly provides it.
4. Read its JSON receipt. Success is `ok:true` with `status:started` or `reused`.
   The launcher validates payload hashes, starts one owned process, waits for its
   authenticated health response and reuses that workspace's existing instance.
5. Open the returned private `url` with the host's browser/panel tool. Its fragment
   is a local access credential and is removed by the UI. Do not publish, copy it
   into a support report, or expose it in a recording. Tell the user which
   workspace/template is ready, that dispatch is paused, and how to add work.

The user should not manually start a server. If no bundled or installed Node 22+
exists, return `control_room_node_runtime_missing` and offer a separately approved
supported runtime installation. If no local executor or compatible Codex exists,
return that specific compatibility result. Do not route the user to another
machine, fetch moving `main`, copy credentials or weaken a sandbox to claim success.
If `codex_login_required` occurs, check `codex login status` using the discovered
executable in the same execution context. A sandbox may not expose an existing
host login. Use the host's normal scoped approval flow for this exact local launch
when needed; do not change global sandbox settings or copy authentication files.
Do not start browser/device login unless the human explicitly requests account
sign-in. If the normal host is also signed out, report that prerequisite plainly.
For a permission denial, explain the exact local operation that requires approval.
An unreachable owned instance or unknown worker must remain blocked, not replaced.
`control_room_running_version_differs` means an older packaged room is running.
Check its work, stop it with the user's authority, then relaunch the current
package against the same data. Never silently replace an active process.

The optional `--state-dir` is for an explicitly selected private data location;
normal setup uses the current `CODEX_HOME` or default Codex profile, scoped by
canonical workspace. Never write state into the plugin cache. `--action status`
reopens/checks the same instance; `--action stop` closes only that instance.
Stopping active work requires the user's explicit authorization and
`--confirm-stop-active`; never kill arbitrary Codex processes or delete worktrees.

## Configure And Use

The dashboard provides editable stages, connections, bot-slot pools, inboxes,
accepted outboxes, all/first-accepted joins and per-stage model/search controls.
Defaults use the Codex model, not a hard-coded model or promised token saving.
Each stage has a Model and Thinking level selector from the connected host's
advertised catalog. Keep explicit choices unchanged; unavailable choices block
dispatch rather than silently substituting. Recommend Low for bounded extraction,
classification or formatting, Medium for ordinary implementation/research/review,
and High for genuinely complex security, architecture or verification. These are
starting heuristics, not measured efficiency or quality guarantees. Apply an
explicit requested model/effort only when the host advertises that combination.

Users can add assignments and `codex://threads/<id>` sources. A source creates a
managed context fork; it does not take control of the original Desktop turn.
Accepted outputs from other workflows can become explicit inputs. Compact
summaries, observed execution aggregates, native-check metadata and artifact
paths are evidence, not new authority or permission grants.

Write stages require explicit session permission. They use owned worktrees from
committed HEAD; uncommitted source changes are not copied. Non-Git work uses an
empty artifact directory. Configure a project-appropriate native check as a JSON
argument array, such as `["node", "--test"]`, only if the tool exists. A release
gate prepares a handoff; it does not grant merge, deployment or account access.

Native workspace setup disables repository Git hooks, filesystem-monitor helpers
and external checkout filters. Git must support committed-tree attribute checks.
If it returns `workspace_checkout_filter_requires_review`, explain that this
project needs separately reviewed materialization (for example, Git LFS). Keep
writes blocked or use read-only work; do not bypass the guard, auto-download
objects or execute repository helpers on the host as a workaround.

Use the UI's Permissions dialog for session execution/write opt-in and Run for
dispatch. No model turns occur merely because the dashboard is open. Pause stops
new dispatch; Cancel waits for native termination. Unknown prior execution
requires explicit stop verification before retry. Restart/disconnect revoke
session consent. Workspace files survive queue archive and shutdown.

Current bounds are 512 stage definitions across 128 workflows, 2,048 reserved
task records and at most 16 simultaneous turns; default concurrency is one.
These are bounds, not proof that hundreds of simultaneous bots are supported.
The native heartbeat observes managed process/queue and host memory/CPU capacity,
not other chats, quota, context or all plugin Heartbeat health families.

## Optional Learning Modules

Offer Outcome learning and Tool-call efficiency review only when requested or
when the user asks how to improve a completed workflow. Neither runs by default.
With explicit selection, `--learning-modules outcome_learning,tool_call_review`
adds their templates during a fresh setup; it does not run them. Existing rooms
can add them from New from template without resetting their current workflows.

Select accepted prior outputs as inputs. Use observed task evidence and artifacts
only; unknown tool timings, token costs, failure rates or causality stay unknown.
Recommend a concrete change, hypothesis and bounded comparison against the
preserved baseline. Require human acceptance. This is workflow learning, not
model training, and never silently edits active prompts, permissions or policies.
Each chosen four-stage learning pipeline consumes additional model turns when run.

## Separate Legacy Governance And Diagnostics

Control Room does not require or create the scheduled Governor. For explicit
existing-chat supervision requests, use the sibling `chronos-governor` skill.
For authorized Windows diagnostics or optional hook review, use sibling
`chronos`. Preserve their independent consent and supported-host requirements.
Standing diagnostics require `automaticDiagnosticsAllowed=yes`; absent consent
means no. No choice here installs or trusts hooks. Directory editions contain
no lifecycle hooks; do not download or auto-install GitHub hooks from this skill.
