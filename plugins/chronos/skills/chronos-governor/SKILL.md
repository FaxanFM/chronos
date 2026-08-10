---
name: chronos-governor
description: Coordinate bounded read tasks for low-complexity repository exploration, review, and verification with Codex native workers while limiting concurrency, context, attempts, health impact, and token use. Shared-folder write delegation is disabled.
---

# Chronos Governor

Delegate small read-only side tasks while the coordinator retains all edits,
architecture, safety decisions, verification, and acceptance. Use Codex native
workers only. Do not create a daemon, scheduler, external service, or autonomous
loop.

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
