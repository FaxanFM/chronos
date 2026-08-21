---
name: chronos-governor
description: Set up one dedicated Chronos Governor for passive supervision and Heartbeats, or coordinate bounded read tasks for low-complexity repository exploration, review, and verification with Codex native workers while limiting concurrency, context, attempts, health impact, and token use. Shared-folder write delegation is disabled.
---

# Chronos Governor

Delegate small read-only side tasks while the coordinator retains all edits,
architecture, safety decisions, verification, and acceptance. Use Codex native
workers only. Do not create a daemon, operating-system scheduler, external
service, or unbounded autonomous loop.

## Automatic Supervision Bootstrap

When the user asks to enable Chronos supervision, enable Heartbeats, or set up
Chronos fully, perform this setup once. The request authorizes one dedicated
Governor task and one host-owned recurrence for supervision and due Heartbeat
evaluation; it does not authorize an operating-system scheduler, service,
worker loop, or unbounded model use. Tell the user before creation that the
default cadence is at most one Governor turn per hour while work is active and
one every six hours while idle. Worker tasks receive no recurring turns.

**Hard gate:** Do not create or enable any Governor recurrence until native
initialization succeeds, supervision and Heartbeat status are readable, and one
complete host-inventory cycle contains the selected Governor exactly once and
returns `recurrenceEligible=true`. Any other result requires zero active
current-key recurrences, verified from fresh host state. Never use a recurrence
to retry, recover, or finish a failed setup.

Read `hostEquivalenceKey` from supervision status. It is
`chronos-supervision-v1:<opaque-installation-id>` and scopes the dedicated task,
its compact assignment, and the matching automation to one local Chronos
installation. Use the complete returned value; the prefix or exact automation
name alone is not an equivalence key. Never copy a key from another machine.

Native status also reports privacy-safe `codexHomeSource` and
`codexHomeIdentity` fields. A nonempty `CODEX_HOME` is authoritative; different
canonical Codex homes are different installations. Stop before host mutation
when the override is invalid, unavailable, or cannot be resolved consistently.
This includes a reparse point in any path component. Do not treat unscoped
legacy state as belonging to an explicit or environment-provided Codex home.

1. Run `chronos.cmd -Action install-status`, compact Inspector status, and
   Heartbeat status. A confirmed enabled-source conflict or unhealthy native
   state fails closed before host mutation. Cached copies alone are not proof
   of a conflict.
2. Reconcile host state before trusting local state or running initialization.
   Collect one all-same-name observation set containing every host
   automation named exactly `Chronos Governor pulse`, its immutable automation
   ID, creation time when available, target task, and equivalence key. Also run
   `chronos.cmd -Action supervise -SupervisionAction status`. Observation does
   not grant mutation authority.
3. Derive a separate current-key mutation set. Include only automations whose
   compact assignment contains the complete current `hostEquivalenceKey` and
   confirms the dedicated role. Never mutate a same-name automation carrying a
   different key or an unverified key. Build the host candidate set from live
   targets in the current-key mutation set. Sort valid
   automation candidates by creation time ascending, then immutable automation
   ID and target task ID using ordinal comparison; a missing creation time sorts
   after a present time. Every installer must select the first candidate. If no
   valid automation exists, apply the same creation-time and immutable-ID order
   to role-verified claimed Governor tasks. A name alone or a local claim alone
   is not proof of role compatibility. If several candidates exist and stable
   host IDs are unavailable, stop without creating another candidate or recovery
   turn.
4. If no valid Governor exists and the host exposes `create_thread`, create one
   fresh task titled `Chronos Governor`. Do not fork the current task or copy its
   history. Request `gpt-5.6-terra` with Medium reasoning only when the host
   advertises that exact task-model choice. Field validation requires reliable
   tool use and recovery judgment in the coordinator role. Never silently
   substitute another model. After any creation, re-list all live, role-verified
   current-key Governor tasks and apply the same stable creation-time and
   immutable-ID ordering. Only the first deterministic setup contender may
   proceed to recurrence mutation or initialization. Every other fresh-task
   contender performs no local or host recurrence mutation, verifies that no
   recurrence targets it, and stands down. If stable IDs are unavailable, no
   contender proceeds.
5. Before initializing the selected task, pause or delete every active
   recurrence from the current-key mutation set, including
   the deterministic winner from an earlier setup. Immediately before the first
   mutation, repeat the all-same-name observation, current-key filtering, and
   role-verified task listing in steps 2 and 3, then repeat the deterministic
   setup-contender election. If a new recurrence or task changes the winner, or
   the selected task is no longer first, skip `-SupervisionAction initialize`
   entirely and enter the loser-verification branch below. Otherwise re-list host
   state and prove
   that zero current-key recurrences are active. Recompute the mutation set after
   every host read or mutation and use at most three bounded mutation and
   verification attempts. Leave foreign-key and unverified-key observations
   unchanged. If zero cannot be proven, stop before initialization and create no
   additional task, recurrence, or recovery turn.
6. Have only the elected selected task run `-SupervisionAction initialize`. The
   registry mutex fences only one machine and state root. If native initialization
   returns `error=supervision_governor_conflict`, do not execute the generic
   initialization-failure cleanup in step 7 and do not retry initialization.
   Enter the same loser-verification branch below. Any other initialization error
   proceeds to the fail-closed current-key cleanup in step 7. Use `-Force` only
   after host task status proves the recorded owner is not live.

   **Loser verification:** This branch has exactly two entries: pre-mutation
   election loss in step 5, which skips initialization, or the literal native
   `error=supervision_governor_conflict` in step 6. Re-read native status and host
   state without recurrence mutation. Only when they identify one live,
   role-verified winner with the complete current key may the loser stand down.
   The loser creates no automation, mutates no recurrence belonging to the
   verified winner, verifies that no recurrence targets the losing task and no
   worker recurrence exists, and may be archived. The winning setup alone owns
   recurrence convergence; after at most three bounded reads, final converged
   state is exactly one current-key Governor recurrence. If the winner cannot be
   verified within the bound, stop with no recurrence mutation and no recovery
   turn. Never fall through from this branch to step 7.
7. Before creating or enabling any recurrence, require the successful
   initialization payload, re-read supervision and Heartbeat status, and run one
   complete host-inventory `cycle` that contains the selected Governor exactly
   once. Continue only when native state is writable, Heartbeat is readable,
   the cycle returns `recurrenceEligible=true`, and its compact status includes
   the selected Governor. Except for the two non-fallthrough loser-verification
   entries above, if initialization, status, Heartbeat, or the complete
   cycle fails, create no recurrence. Pause or delete every recurrence
   in the current-key mutation set, including a pre-existing active recurrence,
   then re-list host state and prove that zero current-key recurrences are
   active. Leave foreign-key and unverified-key observations unchanged. Use at
   most three bounded mutation and verification attempts. Retain only bounded
   local recovery state. Do not schedule a recovery turn.
8. Reconcile only current-key automations after the claim and complete inventory
   cycle succeed. Update the
   deterministic winner in place when possible, or create one when none exists.
   Attach it to the selected task, pause or delete every non-winner, then re-list
   host state. Recompute the same winner after every mutation. Use at most three
   reconciliation attempts in one setup turn. Success requires this exact
   postcondition: one live dedicated Governor, one active automation carrying
   the complete current equivalence key, and zero active duplicates. On the third
   failure, stop all further retries in that setup attempt. If any create, update,
   duplicate cleanup, or exact postcondition verification fails, pause or delete
   every recurrence in the recomputed current-key mutation set, re-list host
   state, and prove zero current-key recurrences are active within three bounded
   attempts. Schedule no recovery turn. Never mutate a foreign or unverified key,
   turn routine convergence failure into a user chore, or rely on a create or
   allow result alone as proof.
9. Before `discover` on Governor cycles zero and one, repeat the host candidate
   scan and exact postcondition check. This catches a concurrently created
   recurrence that was not visible during setup. A non-winning Governor must
   pause or delete its own recurrence, verify that the deterministic winner
   remains active, and stand down. If the losing task itself owns the local
   claim, use the normal two-phase release only after its recurrence is proven
   absent; otherwise do not mutate the local claim. Never clear another task's
   claim. After cycle one, do not rescan all host
   automations during normal cycles unless claim loss, rotation, or recovery
   requires reconciliation.
10. Use the cadence returned by supervision: 60 minutes with active monitored
   work and 360 minutes while idle. The setup is an explicit opt-in to those
   recurring model turns. A Governor is bounded to 336 cycles or 14 days. At the
   bound, perform a verified fresh-task handoff when host tools support it;
   otherwise pause the recurrence and retain the reason in Governor-local state.
11. If task creation is unavailable, use the current task only when the user's
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
from this one inbox. Evaluate due Heartbeat families once per Governor cycle
using only available normalized host evidence; mark unavailable evidence partial
or unsupported. On a new, materially worse, or eligible resolution transition,
use the bounded Chronos intervention state machine. Apply a returned Governor-
local recurrence action yourself and verify its postcondition. Contact only the
exact verified affected task. Use compact batched task waits when available. Do
not edit repositories, read transcripts, run checks inside worker tasks, create
another Governor, broadcast routine status, or assign remediation to the user.
Keep worker recurrence disabled.
```

Do not report full setup complete until all observable postconditions hold:
the expected installed source is active, native status is healthy or explicitly
degraded, exactly one live dedicated Governor owns exactly one active matching
recurrence, Heartbeat status is readable from that Governor, and no worker task
has a recurrence. Return a compact setup summary with those fields. Do not make
the user infer success from `governorClaimed` or another internal state name.
Initialization, status, Heartbeat, or inventory failure is a hard zero-recurrence
postcondition. It applies to matching recurrences that predate the setup attempt
as well as any created during it; it is not a reason to schedule a retrying
Governor.

Plugin monitoring hooks register `SessionStart`, `SessionEnd`,
`SubagentStart`, `SubagentStop`, and one `Stop` signal after each completed main
turn. Non-terminal handlers request asynchronous execution where the host
supports it; `SessionEnd` is synchronous. When Codex dispatches them, they run
headless, return no model context, and create no model turn. Hook trust is
optional acceleration and must never block setup. If hooks are disabled,
untrusted, or not dispatched, continue with one complete compact host task-list inventory and reconcile
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
its host cleanup instruction. Pause or delete every verified current-key
recurrence, leave foreign and unverified keys unchanged, verify that no
current-key recurrence remains active, then call `release` again with
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
