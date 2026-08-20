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

Read `hostEquivalenceKey` from supervision status. It is
`chronos-supervision-v1:<opaque-installation-id>` and scopes the dedicated task,
its compact assignment, and the matching automation to one local Chronos
installation. Use the complete returned value; the prefix or exact automation
name alone is not an equivalence key. Never copy a key from another machine.

1. Reconcile host state before trusting local state. Inspect every host
   automation named exactly `Chronos Governor pulse`, its immutable automation
   ID, creation time when available, target task, and equivalence key. Also run
   `chronos.cmd -Action supervise -SupervisionAction status`.
2. Build one host candidate set. Keep only live targets whose compact assignment
   contains the complete current `hostEquivalenceKey` and confirms the dedicated role. Sort valid
   automation candidates by creation time ascending, then immutable automation
   ID and target task ID using ordinal comparison; a missing creation time sorts
   after a present time. Every installer must select the first candidate. If no
   valid automation exists, apply the same creation-time and immutable-ID order
   to role-verified claimed Governor tasks. A name alone or a local claim alone
   is not proof of role compatibility. If several candidates exist and stable
   host IDs are unavailable, stop without creating another candidate. Preserve
   the candidate state and retry on the next setup pulse.
3. If no valid Governor exists and the host exposes `create_thread`, create one
   fresh task titled `Chronos Governor`. Do not fork the current task or copy its
   history. Request `gpt-5.6-terra` with Medium reasoning only when the host
   advertises that exact task-model choice. Field validation requires reliable
   tool use and recovery judgment in the coordinator role. Never silently
   substitute another model.
4. Have the selected task run `-SupervisionAction initialize`. The registry
   mutex fences only one machine and state root. If another local task already
   won, the loser must stop, create no automation, and may be archived after host
   verification. Use `-Force` only after host task status proves the recorded
   owner is not live.
5. Reconcile all matching automations after the claim succeeds. Update the
   deterministic winner in place when possible, or create one when none exists.
   Attach it to the selected task, pause or delete every non-winner, then re-list
   host state. Recompute the same winner after every mutation. Use at most three
   reconciliation attempts in one setup turn. Success requires this exact
   postcondition: one live dedicated Governor, one active automation carrying
   the complete current equivalence key, and zero active duplicates. On the third
   failure, stop all further setup retries in that pulse. Preserve the candidate
   state and retry later; never turn routine convergence failure into a user
   chore or rely on a create or allow result alone as proof.
6. Before `discover` on Governor cycles zero and one, repeat the host candidate
   scan and exact postcondition check. This catches a concurrently created
   recurrence that was not visible during setup. A non-winning Governor must
   pause or delete its own recurrence, verify that the deterministic winner
   remains active, and stand down. If the losing task itself owns the local
   claim, use the normal two-phase release only after its recurrence is proven
   absent; otherwise do not mutate the local claim. Never clear another task's
   claim. After cycle one, do not rescan all host
   automations during normal cycles unless claim loss, rotation, or recovery
   requires reconciliation.
7. Use the cadence returned by supervision: 60 minutes with active monitored
   work and 360 minutes while idle. The setup is an explicit opt-in to those
   recurring model turns. A Governor is bounded to 336 cycles or 14 days. At the
   bound, perform a verified fresh-task handoff when host tools support it;
   otherwise pause the recurrence and retain the reason in Governor-local state.
8. If task creation is unavailable, use the current task only when the user's
   setup request is explicit. State that it is the fallback and do not duplicate
   the current conversation through `fork_thread`.

This order is also the recovery protocol. It converges after a crash between
task creation, claim, or automation creation; after a stale local claim; and
after local registry loss. Unclaimed extra tasks do not get a recurrence.
Duplicate recurrences are paused or removed before setup is reported complete.
The scoped host equivalence key and stable ordering are the same-installation
ownership fence; the local mutex is not. Different machines have different
opaque keys and therefore retain separate Governors for their separate local
registries.

The dedicated task should receive this compact, self-contained assignment:

```text
Chronos equivalence key: <complete hostEquivalenceKey from status>. Act as the
single Chronos Governor. Claim local Chronos supervision. Reconcile the passive
lifecycle registry with one compact host task inventory and monitor active tasks
from this one inbox. On a new, materially worse, or eligible resolution
transition, use the bounded Chronos intervention state machine. Apply a returned
Governor-local recurrence action yourself and verify its postcondition. Contact
only the exact verified affected task. Use compact batched task waits when
available. Do not edit repositories, read transcripts, run checks inside worker
tasks, create another Governor, broadcast routine status, or assign remediation
to the user. Keep worker recurrence disabled.
```

Plugin monitoring hooks register `SessionStart`, `SessionEnd`,
`SubagentStart`, `SubagentStop`, and one `Stop` signal after each completed main
turn. All non-terminal handlers run asynchronously; `SessionEnd` is
synchronous. They run headless, return no model context, create no model turn,
and require the normal one-time Codex hook trust review. If hooks are disabled
or untrusted, continue with one compact host task-list inventory and reconcile
it through `-SupervisionAction cycle`; do not ask the user to register
or relay tasks. Brief registry contention uses a bounded protected fallback event;
`status` and `discover` reconcile and remove it under the registry lock. Never
bypass hook trust.

For each Governor cycle, apply the bounded cycle-zero/one host convergence check
when required, then call the host task list exactly once. The inventory must be
complete for the cycle to advance. Write only opaque task
IDs, safe status categories, optional opaque generations, capture time, and a
completeness flag to a bounded JSON file under `%TEMP%`; never write titles,
paths, or transcript content. Run `-SupervisionAction cycle` with that file,
remove the file, and treat the returned inventory as liveness authority. Verify
that `hostInventoryCycle` advanced once and that `hostTaskStatuses` contains one
hash-only normalized entry for every listed task.
Use compact `wait_threads` snapshots from the rotating `checkBatch`, which
contains at most eight entries. If host inventory is unavailable, fail closed
for task-directed sends, retain pending state, and retry next cycle without a
user handoff. If an ended registry entry is confirmed live by the host, use
`-SupervisionAction confirm-active -SupervisionSubjectId <id>`; a delayed start
hook cannot revive terminal state by itself. Do not repeatedly read full tasks
or transcripts. A normal cycle must end without messaging monitored tasks;
`taskWakePolicy=intervention_claim_required` is the native postcondition. If
`rotationRequired=true`, reconcile a fresh Governor or pause the recurrence
before the current cycle ends. See the public
[supervision contract](https://github.com/FaxanFM/chronos/blob/main/docs/SUPERVISION.md).

Before building a Governor `usage` record, run `chronos.cmd -Action heartbeat`
once and copy its five named counters exactly: `completedCycles`,
`stateChanges`, `acknowledgedEvents`, `failedCycles`, and `duplicateRuns`.
Combine them only with the current compact Inspector usage fields for this
Governor. Never synthesize a missing counter as zero. If any counter or usage
field is unavailable, mark usage coverage `partial` or `unsupported` and do not
open or resolve a Governor usage condition. This compact status read uses no
model call and replaces host-maintained progress bookkeeping.

## Autonomous Intervention

The PowerShell engine emits events and maintains bounded state. The Codex host
provides task discovery and `send_message_to_thread`. Do not claim that the
script sends a message itself.

For one Governor cycle:

1. Resume persisted work first. Call `-HeartbeatInterventionAction list` with
   this Governor ID. Follow only each returned `permittedNextAction`. Reclaim a
   `send_claimed` record only after Chronos reports its claim expired. The list
   returns opaque IDs and hash prefixes, never raw task IDs.
2. Collect all due Heartbeat events before sending any task message. Process a
   returned `GovernorLocalAction` first. Update only this Governor's recurrence,
   re-list it, and acknowledge the event only after exactly one active matching
   recurrence has the returned cadence. If the update cannot be verified, leave
   the event pending for its bounded retry and do not ask the user to relay it.
3. Resolve each event against current host task inventory. Follow the event's
   `TargetPolicy`. Require exactly one live, authorized target and its current
   host generation. Never target the Governor, a self-origin run, an unrelated
   owner fallback, or a task whose generation changed.
4. Call `-HeartbeatInterventionAction plan` for every event. Plan all events
   before claiming one. Chronos retains at most one active intervention per
   target, coalesces equal or lower severity events, and replaces an unsent
   record when a higher severity event arrives. Native planning also binds the
   requested target hash to the fixed subject or owner policy and returns
   `target_policy_mismatch` on redirection.
5. Immediately recheck the target and generation. Call
   `-HeartbeatInterventionAction claim` only for the final queued record. The
   returned claim token authorizes one bounded host send attempt.
6. Send one fixed-template message to the exact target with
   `send_message_to_thread`. Include only the opaque intervention ID, version,
   categorical instruction, fixed safety limits, postcondition name, and fixed
   reply format returned by Chronos. Do not interpolate detector prose, task
   titles, paths, test names, tool output, or other untrusted content.
7. Record `accepted` only when the host tool definitely accepts the send.
   Record `definite_failure` only when it definitely rejects or never attempts
   the send. Record `unknown` after a timeout or indeterminate result. Never
   retry `unknown` unless host evidence confirms that the first send did not
   occur. A definite failure permits one retry; the total is two attempts.
8. A reply advances state only when the exact target and generation return the
   matching intervention ID and version. Reduce the reply to one allowed
   category before calling `-HeartbeatInterventionAction response`. A task
   report is not proof that recovery occurred.
9. Resolve only after a later observed Heartbeat cycle or an allowed independent
   host check confirms the named postcondition. Use
   `-HeartbeatInterventionAction verify` for host inventory, narrow test, or Git
   evidence. A stale reply cannot resolve a newer version.

Do not acknowledge a native event separately after `plan` or `fail-closed`;
those actions consume its Governor-inbox outbox record atomically. A resolution
message is allowed only when `ReleaseNoticeEligible=true`, which means the task
acknowledged a temporary restriction that must now be lifted. Other resolutions
stay Governor-local.

Use only the fixed safe actions returned by Chronos: stop creating new workers,
reduce task-controlled parallel work, checkpoint, return completed workers,
prepare a fresh-task handoff, reconcile an owned child, or run one already known
narrow validation. Never request secrets, bypass approval, change reviewer or
sandbox settings, infer model cost, change a task model, kill Codex, restart the
PC, or reset, clean, merge, push, publish, or delete repository data.

`USAGE_BURN` reports token volume, not price. Keep `CostImpact` and
`QuotaImpact` as `unknown` without trusted runtime metadata. A Governor-origin
usage event stays Governor-local. It may target another task only when a second
event proves stall, review amplification, or machine degradation for the same
subject within the same observation window. It can never target the Governor.
`throttle_recurrence_to_idle_cadence` means set only the Governor recurrence to
360 minutes and verify the one-recurrence postcondition. On
`restore_supervision_recommended_cadence`, reconcile the 60-minute active or
360-minute idle cadence and verify it before closing the local action.

When ownership is ambiguous, the target is not live, transport is unavailable,
or user authority is required, call `-HeartbeatInterventionAction fail-closed`.
Do not broadcast, choose an arbitrary target, or manufacture a user action.

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
