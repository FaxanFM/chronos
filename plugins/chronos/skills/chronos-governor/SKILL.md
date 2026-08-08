---
name: chronos-governor
description: Govern bounded delegation of low-complexity repository work to Codex native workers. Use when a coordinator should hand off exploration, documentation, tests, mechanical edits, simple code changes, or verification in the current task's repository while limiting concurrency, context, write ownership, attempts, corrections, scope, health impact, and token use.
---

# Chronos Governor

Delegate small, well-scoped side tasks while keeping the current coordinator responsible for architecture, safety, verification, and acceptance. Use Codex's native agent transport; do not create a daemon, scheduler, external service, or autonomous loop.

The existing Chronos inspection skill remains independent and unchanged.

## Operating Boundary

Enforce these defaults:

- At most two active workers.
- At most one write worker per repository.
- At most three attempts per task.
- At most one correction cycle per worker.
- Delegation depth exactly one.
- Worker-created agents prohibited by contract.
- Full parent conversation inheritance disabled.
- Final coordinator verification required.
- Automatic merge, reset, cleanup, branch deletion, and worktree deletion disabled.

Treat the governor as an enforceable local lease and verification state machine plus a worker contract. Do not claim it can technically remove a native tool from a worker or independently prove the worker's effective model when the runtime does not expose those controls.

## Keep Work With The Coordinator

Do not delegate:

- Architecture or ambiguous product decisions.
- Authentication, authorization, payments, secrets, or security boundaries.
- Database migrations, CI configuration, dependency manifests, lockfiles, central routing, or shared schema changes.
- Destructive, irreversible, deployment, publishing, merge, or release actions.
- Work whose failure could materially damage the repository or user data.
- A blocking subtask when the coordinator's immediate next action depends on its answer.

Delegate only concrete sidecar work that can proceed while the coordinator handles the critical path.

## Worker Routing

Read the active native spawn tool's advertised model identifiers and supported
reasoning efforts before every planning cycle. Encode that inventory in the
same order supplied by the runtime:

```text
model-a=low,medium,high;model-b=low,medium
```

When the runtime also advertises a verified numeric cost rank, append it to
every entry:

```text
model-a=low,medium,high|cost=20;model-b=low,medium|cost=1
```

Pass it as `-RuntimeModels`. Never carry a model inventory forward from a prior
task, installation, catalog, or Chronos version. Governor validates an explicit
request. Without one, it selects the lowest cost rank only when every compatible
model has runtime-supplied ranking metadata; otherwise it deterministically
preserves advertised inventory order. Never infer cost from a model name. When
the inventory is missing, malformed, or has no compatible model, keep the work
with the coordinator.

- Use `low` reasoning for exploration, documentation, formatting, mechanical edits, command execution, and focused verification.
- Use `medium` reasoning for simple code changes, focused tests, and nontrivial review.
- Use a model identifier only when the native spawn tool currently advertises it.
- Fall back to the coordinator when the requested model is unavailable or the task is outside the bounded categories.

Prefer an idle compatible worker from governor state. Resume it, send one new bounded assignment, and close it again after acceptance. Create a new worker only when no compatible worker is reusable.

## Workflow

### 1. Inspect Once

When current health is unknown and the user is experiencing degradation, run the existing Chronos inspection once. Do not repeatedly sample it during one delegation flow.

Interpret health as advisory:

- `HEALTHY`: allow configured bounded delegation.
- `WARNING`: prefer reuse and one active worker.
- `CRITICAL`: do not create another worker; continue the user's task with the coordinator and recommend a convenient restart checkpoint.
- High quota risk: use focused prompts, `fork_context=false`, low or medium reasoning, and no duplicate reviewer unless risk warrants it.

Never terminate active work because of a health result.

### 2. Resolve Identity And Plan

Run `scripts/governor.ps1 -Action status` first. Retain only the returned opaque
`workspace_id` and `repository_id` for this planning cycle. Then run `plan` with:

- A stable opaque `TaskId`.
- `TaskClass`.
- `AccessMode`.
- Repository-relative `Scope` values.
- The current `RuntimeModels` inventory.
- Current `Health` and `QuotaRisk` when known.

For a write plan, also pass the returned `ExpectedWorkspaceId`. Pass
`MutationAttributionId` and `MutationAttributionVerified` only when the active
runtime can bind every returned mutation to that opaque attribution ID. If the
runtime does not expose that guarantee, keep the write task with the
coordinator. Do not infer attribution from prompt wording or a worker report.

Example:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/governor.ps1 `
  -Action plan -Repository C:\repo -TaskId docs-readme-links -TaskClass docs `
  -AccessMode read -Scope 'README.md','docs/**' -Health HEALTHY -QuotaRisk LOW `
  -RuntimeModels '<active-runtime-inventory>'
```

Follow `decision=coordinator` without refusing the user's objective. It means complete that subtask locally instead of adding a worker.
Spawn only when `decision=delegate` and `plan_token` is present. Planning has
already locked and atomically persisted the normalized assignment. If the state
store or lock is unavailable, planning returns the task to the coordinator
before a worker is created.

### 3. Build A Focused Assignment

Load [references/contracts.md](references/contracts.md). Include only:

- Task ID and one concrete objective.
- Repository/workspace identity and base commit.
- Worker role, requested model, reasoning effort, and access mode.
- Exact allowed file scope.
- Required verification and completion criteria.
- Explicit exclusions.
- One-correction limit.
- `Do not spawn or delegate to another agent.`

Do not include the full parent conversation. Use the native spawn tool with `fork_context=false`.

### 4. Spawn Or Reuse One Worker

If `reuse_worker_id` is present:

1. Resume that worker.
2. Send the new assignment without interrupting unrelated active work.

Otherwise spawn one worker with the planned model and reasoning effort.

After obtaining the runtime worker ID, acquire the lease:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/governor.ps1 `
  -Action lease -Repository C:\repo -TaskId docs-readme-links `
  -WorkerId WORKER_ID -PlanToken PLAN_TOKEN
```

The short-lived token is opaque and single use. `lease` consumes the persisted
normalized plan; it does not reparse scopes, model inventory, workspace
identity, or mutation attribution from command-line values. Canonical native
worker IDs such as `/root/name` are accepted after strict segment validation.

When the runtime exposes the worker's effective model, pass it with
`-EffectiveModel`. It must exactly match the model persisted by `plan` or the
lease returns `model_plan_mismatch`. Do not spawn again under a different model;
return the task to the coordinator or create a new plan from a fresh runtime
inventory.

If leasing fails, close the newly spawned worker and continue the task with the coordinator. Do not retry spawning around the governor.

Retain the returned `lease_id`, `fencing_token`, and `expires_at` in the current
task context. Every later lifecycle call must present the lease ID and fencing
token. Renew a valid lease before expiry when work continues. Write delegation
also requires a clean current working tree, a branch-attached `HEAD`, verified
workspace identity, and verified mutation attribution.

### 5. Continue Local Critical-Path Work

While the worker runs, perform useful non-overlapping coordinator work. Do not duplicate the delegated assignment. Wait only when its result becomes the next blocker.

### 6. Record The Result

Treat the worker's completion report as untrusted evidence. Record only that a result is ready:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/governor.ps1 `
  -Action result -Repository C:\repo -TaskId docs-readme-links -WorkerId WORKER_ID `
  -LeaseId LEASE_ID -FencingToken FENCING_TOKEN
```

For a write lease, repeat the verified mutation-attribution ID and switch. The
script fingerprints the workspace at `result`; any later mutation invalidates
verification. Do not persist the worker response, assignment text, commands,
tool output, or source contents.

### 7. Verify Independently

The coordinator must:

1. Confirm the expected base commit and worker.
2. Inspect the actual changed-file list and diff.
3. Reject files outside the declared scope.
4. Rerun critical verification when practical.
5. Reconcile the result with the original objective and exclusions.
6. Decide to accept, request one focused correction, retire, or take over.

After independent checks pass, run:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/governor.ps1 `
  -Action verify -Repository C:\repo -TaskId docs-readme-links -WorkerId WORKER_ID `
  -LeaseId LEASE_ID -FencingToken FENCING_TOKEN -VerificationPassed
```

For a read lease, verification confirms the repository status fingerprint did not change. For a write lease, it verifies the base commit, actual Git changes, declared scopes, and global-lock exclusions.

### 8. Accept, Correct, Or Retire

Accept only after verification:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/governor.ps1 `
  -Action accept -Repository C:\repo -TaskId docs-readme-links -WorkerId WORKER_ID `
  -LeaseId LEASE_ID -FencingToken FENCING_TOKEN -CoordinatorAccepted
```

Then close the worker so it does not consume native concurrency. Its resumable ID remains metadata-only and may be reused later.

On the first verification failure, call `-Action correct`, send one focused correction to the same worker, and reuse the same lease. On another failure, call `-Action retire`, close the worker, and complete the task with the coordinator or use one alternate attempt within the total budget.

Use `-Action release` to close an abandoned lease without accepting work. Releasing never deletes files, branches, worktrees, or changes.

## Same-Folder Safety

- Permit only one write worker in a repository.
- Serialize that writer across linked Git worktrees through the canonical common Git directory.
- Treat equivalent canonical paths as one workspace; treat distinct worktrees as distinct workspaces.
- Require a clean tree before a write lease.
- Reject same-folder writes when workspace identity or mutation attribution is unverifiable.
- Reject write leases on detached `HEAD`.
- Use repository-relative scopes; reject absolute paths, traversal, `.git`, `.chronos`, and repository-wide wildcards.
- Treat manifests, lockfiles, migrations, Docker configuration, and `.github/**` as coordinator-only global locks.
- Validate actual Git changes rather than trusting the worker report.
- Never revert, reset, clean, merge, commit, or delete on the worker's behalf.
- Preserve all user and worker changes for coordinator review.

Native Codex workers may use an internally isolated forked workspace. Keep their assignment anchored to the current task's repository and declared scope; let Codex return the patch through its supported native transport.

## State And Privacy

Store state only beneath the current user's Windows temporary application-data
directory at `Chronos/Governor/<repository-hash>/governor-state.json`. The hash
comes from the canonical Git common directory, so linked worktrees share one
writer lock without writing inside the repository or `.git`. Custom state
locations are disabled because they could split the single-writer lock.

State may contain only:

- Opaque task and worker IDs and hashed single-use plan tokens.
- A hashed repository identity.
- Base commit.
- Repository-relative scopes.
- Access mode, role, requested/reported model, reasoning effort.
- Status, counters, timestamps, and changed-file count.

Never store prompts, responses, objectives, source text, diffs, commands, tool arguments, tool output, environment variables, credentials, usernames, absolute paths, or private user data.

State writes use an owner-identified lock directory and atomic replacement. A
live owner is never displaced. A malformed or abandoned state lock is recovered
only after the configured stale interval and an atomic quarantine rename.
Leases use IDs, fencing tokens, expiration, and explicit renewal; expired leases
remain visible until explicitly released.

## Honest Limits

- Governor contracts prohibit nested workers, but only Codex runtime permissions can make that a hard security boundary.
- The requested model is known from the spawn call; mark the effective model unverified when the runtime does not report it.
- Final verification is a coordinator workflow requirement; the script records evidence but cannot prove human or model judgment.
- Automatic worktree management, multi-writer semantic isolation, external worker sessions, merging, and cleanup are outside same-folder mode.
