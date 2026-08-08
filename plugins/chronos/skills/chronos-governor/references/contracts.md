# Chronos Governor Contracts

These contracts define bounded delegation between a coordinator and a worker. The coordinator remains responsible for task decomposition, verification, acceptance, correction, retry, and integration.

## Assignment Contract

Every assignment must state:

- `task_id`: Stable identifier for the assignment.
- `objective`: One concrete outcome.
- `worker_role`: Named role such as implementation, analysis, or verification.
- `repository`: Repository identity.
- `base_commit`: Commit from which the work starts.
- `workspace`: Assigned checkout or worktree identity.
- `model_inventory_hash`, `model_inventory_index`, and optional
  `model_cost_rank`: Runtime discovery and selection evidence.
- `access_mode`: `read` or `write`.
- `allowed_scope`: Repository-relative file or component scope.
- `required_verification`: Checks the worker must perform.
- `explicit_exclusions`: Files, behavior, or operations that are out of bounds.
- `completion_criteria`: Conditions for reporting completion.
- `maximum_correction_cycles`: Number of permitted correction cycles.

Assignments without a bounded objective, scope, permission, exclusions, or completion criteria must be rejected or returned for clarification. A write assignment uses one writer across the repository's canonical Git common directory. It also requires verified workspace identity and runtime mutation attribution. Read-only workers may run concurrently when their work does not conflict.

## Worker Result Contract

The worker returns a structured report containing coordination metadata and evidence:

- `task_id`, `worker_id`, and `status`.
- `lease_id`, `fencing_token`, and the bound mutation-attribution ID.
- `requested_model`, `effective_model`, and `transport`, when available.
- `base_commit` and workspace or branch identity.
- `files_inspected` and `files_changed`.
- `commands_executed`, summarized as command names or purposes.
- `verification`, including pass or fail and a short summary.
- `assumptions` and `remaining_risks`.

The report is evidence, not acceptance. The coordinator must inspect the actual workspace, changed-file list, diff, tests, generated artifacts, and the Governor result fingerprint. Reports and coordination state must contain no prompts, responses, secrets, source contents, or raw tool output.

## Coordinator Verification Checklist

Before accepting a result, the coordinator must:

1. Confirm the expected repository, workspace, and base commit.
2. Confirm the worker, lease, fencing token, model-inventory evidence, and effective model when available.
3. Inspect every changed file and reject out-of-scope changes.
4. Inspect the actual diff for correctness and unintended behavior.
5. Review the worker's verification evidence.
6. Repeat critical checks when practical.
7. Compare the result with the original objective and exclusions.
8. Check integration conflicts and repository-wide impact.
9. Choose to accept, request one focused correction, retry with another worker, or take over.
10. Perform or explicitly authorize final integration.

## Worker Lifecycle

Workers move through these states:

`starting -> idle -> leased -> working -> awaiting_verification -> accepted`

Failure or retirement may occur from any active state:

`working -> needs_correction -> working`

`working -> failed -> retired`

`awaiting_verification -> rejected -> needs_correction`

A worker returns to `idle` only after the coordinator closes or accepts its assignment. Reuse is preferred when repository, workspace, role, effective model, permissions, task type, required tools, and health remain compatible. A worker should be retired when its context, failures, repository basis, model, or permissions no longer fit the assignment.

After a failed verification, allow at most the declared correction cycles. Do not repeatedly create workers for the same unresolved failure; escalate to an alternate worker or the coordinator.

## Strict Exclusions

The governor must not:

- Replace the coordinator as final decision-maker.
- Permit recursive worker delegation or worker-created agents.
- Permit overlapping write ownership in the same repository.
- Infer workspace identity or mutation attribution from a worker's prose report.
- Use a model absent from the active runtime inventory.
- Permit a worker to modify another worker's workspace or branch.
- Permit a worker to merge, integrate, reset, clean, or delete another worker's work.
- Accept a worker claim without independent verification.
- Store prompts, responses, secrets, source-code content, tool arguments, or tool output in persistent state.
- Automatically clean up workspaces, branches, or unmerged changes.
- Automatically merge branches or resolve semantic conflicts.
- Expand a task beyond its declared scope without a new assignment.

Completed workspaces remain available for manual review. Cleanup and merging require explicit coordinator or user authorization.
