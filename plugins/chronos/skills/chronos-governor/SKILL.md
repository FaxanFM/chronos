---
name: chronos-governor
description: Coordinate bounded read tasks for low-complexity repository exploration, review, and verification with Codex native workers while limiting concurrency, context, attempts, health impact, and token use. Shared-folder write delegation is disabled.
---

# Chronos Governor

Delegate small read-only side tasks while the coordinator retains all edits,
architecture, safety decisions, verification, and acceptance. Use Codex native
workers only. Do not create a daemon, operating-system scheduler, external
service, or unbounded autonomous loop.

## Automatic Supervision Bootstrap

When the user asks to enable Chronos supervision, perform this setup once. The
request authorizes one dedicated Governor task and one host-owned recurrence;
it does not authorize an operating-system scheduler, service, worker loop, or
unbounded model use. Tell the user before creation that the default cadence is
at most one Governor turn per hour while work is active and one every six hours
while idle. Worker tasks receive no recurring turns.

1. Reconcile host state before trusting local state. Inspect every host
   automation named exactly `Chronos Governor pulse` and its target task. Also
   run `chronos.ps1 -Action supervise -SupervisionAction status`.
2. Prefer the live target of an existing matching automation when its title and
   compact assignment confirm that it is a Chronos Governor. Otherwise reuse a
   locally claimed Governor only after the host task list confirms it is live,
   dedicated to this role, and not carrying unrelated work. A name alone is not
   proof of role compatibility.
3. If no valid Governor exists and the host exposes `create_thread`, create one
   fresh task titled `Chronos Governor`. Do not fork the current task or copy its
   history. Request `gpt-5.6-luna` with Medium reasoning only when the host
   advertises that exact task-model choice. Never silently substitute a more
   expensive model.
4. Have the selected task run `-SupervisionAction initialize`. The registry
   mutex is the ownership fence. If another task already won, the loser must
   stop, create no automation, and may be archived after host verification. Use
   `-Force` only after host task status proves the recorded owner is not live.
5. Reconcile all matching automations after the claim succeeds. Update one
   existing automation in place when possible, or create one when none exists.
   Attach it to the claimed task, pause or delete every duplicate, and re-list
   host state to verify exactly one active automation targets exactly one live
   Governor. Never rely on a create call alone as proof.
6. Use the cadence returned by supervision: 60 minutes with active monitored
   work and 360 minutes while idle. The setup is an explicit opt-in to those
   recurring model turns. A Governor is bounded to 336 cycles or 14 days. At the
   bound, perform a verified fresh-task handoff when host tools support it;
   otherwise pause the recurrence and send one action request.
7. If task creation is unavailable, use the current task only when the user's
   setup request is explicit. State that it is the fallback and do not duplicate
   the current conversation through `fork_thread`.

This order is also the recovery protocol. It converges after a crash between
task creation, claim, or automation creation; after a stale local claim; and
after local registry loss. Unclaimed extra tasks do not get a recurrence.
Duplicate recurrences are paused or removed before setup is reported complete.

The dedicated task should receive this compact, self-contained assignment:

```text
Act as the single Chronos Governor. Claim local Chronos supervision. Reconcile
the passive lifecycle registry with host task status, monitor active tasks from
this one inbox, and emit or forward only actionable transitions. Use compact
batched task waits when available. Do not edit repositories, read transcripts,
run checks inside worker tasks, create another Governor, or broadcast routine
status. Keep worker recurrence disabled.
```

Plugin lifecycle hooks register only `SessionStart`, `SessionEnd`,
`SubagentStart`, and `SubagentStop`. They run headless, return no model context,
and require the normal one-time Codex hook trust review. If hooks are disabled
or untrusted, continue with host task-list discovery and label registry coverage
unavailable. Never bypass hook trust.

For each Governor cycle, run `-SupervisionAction discover`, then treat host task
tools as liveness authority. Prefer one `list_threads` call and compact
`wait_threads` snapshots from the rotating `checkBatch`, which contains at most
eight entries. If an ended registry entry is confirmed live by the host, use
`-SupervisionAction confirm-active -SupervisionSubjectId <id>`; an async start
hook cannot revive terminal state by itself. Do not repeatedly read full tasks
or transcripts. A normal cycle must end without messaging worker tasks. If
`rotationRequired=true`, reconcile a fresh Governor or pause the recurrence
before the current cycle ends. See the public
[supervision contract](https://github.com/FaxanFM/chronos/blob/main/docs/SUPERVISION.md).

To disable supervision, first call `release` without confirmation and follow
its host cleanup instruction. Pause or delete every matching recurrence, verify
that none remains active, then call `release` again with
`-SupervisionConfirmRecurrenceStopped`. Never clear the claim first.

## Boundary

Governor is an advisory coordination aid, not a sandbox or security boundary.
Its temporary state is worker-reachable, prompt restrictions are not runtime
permissions, and its Git-visible fingerprint cannot prove that no filesystem
effect occurred. Rely on the active Codex sandbox for actual permissions.

Defaults:

- At most two active read-task workers.
- Shared-folder write workers disabled.
- At most three attempts per task and one correction.
- Delegation depth one by coordinator policy.
- Worker-created agents prohibited by prompt contract, not runtime enforcement.
- Full parent history disabled with `fork_turns="none"` on Multi-Agent V2.
- Final coordinator verification required.
- Automatic merge, reset, cleanup, commit, and deletion disabled.
- Worker-task recurrence and per-turn monitoring disabled.

## Keep With The Coordinator

Do not delegate edits, architecture, authentication, authorization, payments,
secrets, security boundaries, migrations, CI, dependencies, lockfiles, central
routing, deployment, publishing, merge, release, destructive operations, or
ambiguous work. Delegate only a concrete read-only side task that can proceed
while the coordinator continues useful non-overlapping work.

## Runtime Routing

Read the active `spawn_agent` tool's advertised models and supported reasoning
efforts for this task. Encode that current inventory in runtime order:

```text
model-a=low,medium,high;model-b=low,medium
```

Include `|cost=N` only when the runtime itself advertises a numeric rank for
every compatible model. Pass the result as `-RuntimeModels`. Never infer cost
from a model name or reuse inventory from another task or installation.

Use low effort for exploration, documentation review, formatting review, and
focused verification. Use medium only for nontrivial code review or test
analysis. If inventory is missing, malformed, or incompatible, keep the work
with the coordinator.

## Workflow

### 1. Inspect Once When Needed

Use the Chronos inspector once when health is unknown and degradation matters.
Interpret `machineHealth` separately from `resourceDiagnosticLevel`,
`overallDiagnosticLevel`, and quota/rule findings. At machine `CRITICAL`, do not
create a worker. Never terminate work because of a Chronos result.

### 2. Plan A Read Task

Run `status`, then plan with an opaque task ID, a read access mode, intended
repository-relative scope, current runtime inventory, and current health when
known:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File scripts/governor.ps1 -Action plan -Repository C:\repo `
  -TaskId inspect-auth-tests -TaskClass review -AccessMode read `
  -Scope 'tests/auth/**' -RuntimeModels '<active-runtime-inventory>'
```

Follow `decision=coordinator` by completing the subtask locally. A write plan
always returns `reason=shared_folder_write_delegation_disabled`.

Spawn only when `decision=delegate` and `plan_token` is present. The state file
is untrusted coordination metadata; successful persistence is not an integrity
or authorization guarantee.

### 3. Send A Focused V2 Assignment

Load [references/contracts.md](references/contracts.md). Include only the opaque
task ID, one objective, workspace identity, base commit, intended read scope,
verification criteria, exclusions, and `Do not spawn or delegate to another
agent.` Do not include the parent conversation.

Use the current Multi-Agent V2 contract with `fork_turns="none"`. Do not send
the removed V1 `fork_context` field. If the active tool does not advertise that
contract, keep the work with the coordinator.

### 4. Bind The Worker

After obtaining the runtime worker ID:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File scripts/governor.ps1 -Action lease -Repository C:\repo `
  -TaskId inspect-auth-tests -WorkerId WORKER_ID -PlanToken PLAN_TOKEN
```

One worker ID may own only one active lease. When `reuse_worker_id` is returned,
reuse it only for the same workspace, role, model, effort, and access mode.
If the native spawn fails or the worker ID is unavailable, cancel the issued
plan exactly once with its original opaque token so it does not reserve pending
capacity:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File scripts/governor.ps1 -Action cancel-plan -Repository C:\repo `
  -TaskId inspect-auth-tests -PlanToken PLAN_TOKEN
```

Never delete or edit Governor state to recover capacity. `status` reports
unexpired `pending_plans`, separate `expired_plans`, and the active
`plugin_version` read from the installed manifest.

### 5. Record And Verify

Treat the worker report as untrusted. Record completion:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File scripts/governor.ps1 -Action result -Repository C:\repo `
  -TaskId inspect-auth-tests -WorkerId WORKER_ID `
  -LeaseId LEASE_ID -FencingToken FENCING_TOKEN
```

Independently check that the response answers the objective, cites evidence,
contains no requested edit, and did not leave a Git-visible repository change.
Then record verification:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File scripts/governor.ps1 -Action verify -Repository C:\repo `
  -TaskId inspect-auth-tests -WorkerId WORKER_ID `
  -LeaseId LEASE_ID -FencingToken FENCING_TOKEN -VerificationPassed
```

The `VerificationPassed` switch records the coordinator's decision; it does not
prove which tests or review were performed.

### 6. Accept Or Stop

Accept only after verification:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File scripts/governor.ps1 -Action accept -Repository C:\repo `
  -TaskId inspect-auth-tests -WorkerId WORKER_ID `
  -LeaseId LEASE_ID -FencingToken FENCING_TOKEN -CoordinatorAccepted
```

Use `correct` once for a focused correction, `retire` for failed active work,
or `release` for abandoned active work. Terminal leases cannot be rewritten.
Close the native worker after acceptance or retirement.

## State And Privacy

State lives at `Chronos/Governor/<repository-hash>/governor-state.json` beneath
the current user's Windows temporary directory. It contains only opaque IDs,
hashes, base commits, relative scopes, model labels, policy limits, counters,
status, and timestamps. It is not authenticated and can be tampered with by a
process that can reach the file. Never use it as an authorization record.

Governor does not store prompts, responses, objectives, source, diffs, commands,
tool arguments, output, credentials, usernames, environment values, or absolute
paths. It creates no telemetry and sends no state remotely.

## Common Results

- `shared_folder_write_delegation_disabled`: perform the edit as coordinator.
- `model_inventory_unavailable`: refresh the active tool inventory.
- `state_store_unwritable`: no worker was authorized; continue locally.
- `state_store_unreadable` or `state_read_failed`: continue locally and report
  the compact result; do not delete or edit state.
- `state_invalid_json` or `state_schema_invalid`: preserve the state and report
  the compact result; do not overwrite it to force recovery.
- `state_lock_unavailable`: wait briefly or continue locally; do not delete it.
- `worker_already_leased`: finish or release the worker's active lease.
- `plan_token_mismatch`, `plan_expired`, or `plan_already_consumed`: plan again.
- `cancel-plan` is terminal; a canceled token cannot later create a lease.
- `invalid_worker_id`: use the exact runtime ID; `/root/name` is supported.
- `workspace_fingerprint_limit_exceeded`: stop delegation and inspect locally.
- `read_worker_modified_workspace`: preserve and inspect the changes; do not
  attribute them automatically.
- `invalid_lifecycle_transition`: preserve the terminal record.
- `internal_error`: continue locally and report only the compact result. The
  privacy-safe `failure_stage` and `exception_type` identify the failing code
  boundary without including paths, exception text, or state content.

## Honest Limits

- Read-only is a requested access mode plus a Git-visible warning check, not a
  verified filesystem property.
- Delegation depth is policy, not a removed worker capability.
- Effective model identity is unverified unless the runtime exposes trusted
  evidence.
- No authenticated broker or disposable worker repository is included in this
  release. Those are prerequisites before write delegation can return.
