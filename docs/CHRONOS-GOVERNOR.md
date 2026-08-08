# Chronos Governor

Chronos Governor is an optional, local coordination state machine for bounded
Codex worker delegation. The current coordinator retains architecture,
integration, verification, and acceptance. Governor is not a background
service, autonomous loop, source-control replacement, or merge system.

## Runtime Model Discovery

Governor has no preferred or hardcoded worker model. The coordinator reads the
models and reasoning efforts advertised by the active native worker runtime and
passes them in advertised order:

```text
model-a=low,medium,high;model-b=low,medium
```

Optional runtime-supplied cost rank uses:

```text
model-a=low,medium,high|cost=20;model-b=low,medium|cost=1
```

An explicitly requested model must be present and support the requested effort.
Without an explicit request, Governor selects the lowest compatible cost rank
only when every compatible entry carries verified ranking metadata. If ranking
is absent or partial, it preserves runtime inventory order. It returns the
inventory hash, selected index, optional cost rank, and reason so the choice is
deterministic and auditable. Chronos never infers cost from model names. Missing,
malformed, stale, or incompatible inventories return the work to the
coordinator.

## Identity Model

Governor canonicalizes Windows paths before hashing them.

- `repository_id` hashes the canonical Git common directory. Linked worktrees
  share this identity and therefore share writer serialization.
- `workspace_id` hashes the canonical worktree root plus common Git directory.
  Distinct worktrees have distinct workspace identities.
- Junction or equivalent paths that resolve to the same worktree produce the
  same workspace identity.

No absolute path is persisted. State is keyed by `repository_id` beneath the
current user's Windows temporary application-data directory, so linked
worktrees share serialization without requiring writes to `.git`. Custom state
paths are disabled because a second state file could bypass repository-wide
writer exclusion.

## Write Safety

A same-folder write lease is allowed only when all of these checks pass:

1. The current runtime model inventory is valid.
2. The expected workspace identity exactly matches the computed identity.
3. The runtime can bind every mutation to the supplied opaque attribution ID.
4. The tree is clean, `HEAD` is attached, and scopes are repository relative.
5. No writer is active anywhere in the repository's linked worktrees.
6. No scope targets a reparse point or coordinator-only global-lock file.

When runtime mutation attribution is unavailable, write work stays with the
coordinator. Read-only delegation remains available. Worker claims are never
treated as attribution evidence.

At `result`, Governor records a content fingerprint of `HEAD`, tracked changes,
and untracked file hashes. `verify` fails when anything changes after that
fingerprint, preventing a later coordinator or worker mutation from being
silently attributed to the result.

## Leases And Locks

```text
plan (persist token) -> lease (consume token) -> renew as needed -> result -> verify -> accept
                  |                         |
                  +-> correct once --------+
                  +-> retire or release
```

A delegating plan first acquires the state lock and atomically persists its
normalized scopes, model selection, workspace identity, and attribution state.
It returns a short-lived opaque token only after persistence succeeds. Lease
activation accepts that token and the runtime-issued worker ID, then consumes
the plan exactly once. This prevents command-line scope flattening or
plan-to-lease normalization drift.

When the runtime reports an effective worker model, lease binding and later
result reporting compare it with the persisted selected model. A difference
returns `model_plan_mismatch` before activation or result acceptance. Missing
runtime evidence remains explicitly unverified rather than guessed.

Every lease has an opaque lease ID, fencing token, expiry, repository identity,
workspace identity, base commit, scope, and attribution hash. Lifecycle actions
must present the matching lease ID and fencing token. An expired lease cannot be
renewed or used; the coordinator may explicitly release it without deleting any
workspace content.

State writes use an owner-identified lock directory and atomic file replacement.
A lock records the process ID, process start time, lock ID, and timestamp. A live
owner is never displaced. An old malformed or dead-owner lock is recovered only
after the stale interval and an atomic quarantine rename. Release removes a lock
only when its lock ID still matches, so an older process cannot delete a newer
owner's lock.

## Default Limits

| Control | Default |
| --- | --- |
| Active workers | 2 |
| Active writers per repository | 1 |
| Plan-token duration | 5 minutes |
| Lease duration | 30 minutes |
| Total attempts per task | 3 |
| Corrections per worker | 1 |
| Delegation depth | 1 |
| Full parent context inheritance | Disabled |
| Final coordinator verification | Required |
| Automatic merge or cleanup | Disabled |

Architecture, authentication, payments, migrations, dependency manifests, CI,
releases, deployment, destructive operations, and ambiguous work remain with
the coordinator.

## Troubleshooting

Run `governor.ps1 -Action status` to inspect opaque counts and identities.

- `model_inventory_unavailable`: refresh the active spawn tool metadata and
  pass its current inventory. Do not reuse a catalog from another task.
- `workspace_identity_unverified`: call `status` in the intended worktree and
  pass that exact workspace ID.
- `mutation_attribution_unverified`: keep the write with the coordinator unless
  the runtime exposes reliable attribution.
- `state_store_unwritable`: no worker was authorized because the local state
  location could not be written. Continue with the coordinator.
- `state_lock_unavailable`: another live state writer owns the lock. Wait
  briefly or continue with the coordinator. Do not
  delete it manually.
- `plan_token_required`, `plan_token_mismatch`, or `plan_expired`: discard the
  worker assignment, plan again, and do not bypass Governor.
- `invalid_worker_id`: use the exact runtime-issued ID. Canonical IDs such as
  `/root/name` are supported; malformed paths are rejected.
- `lease_expired`: explicitly release the abandoned lease with coordinator
  acceptance, then plan again.
- `state_invalid_json`: preserve the state file for diagnosis. Governor will not
  overwrite malformed state.
- `workspace_changed_after_result`: inspect all changes and take over locally;
  the original result can no longer be attributed safely.

Interrupted `.tmp-*` files do not replace valid state. Inactive version 1 or 2
state beneath Git metadata migrates to the per-user store. An active legacy
lease fails closed and must be finished with the previous release.

## State And Privacy

State lives at `Chronos/Governor/<repository-hash>/governor-state.json` beneath
the current user's Windows temporary application-data directory. It contains
only opaque IDs, hashes, base commits, relative scopes, model labels, counters,
status, and timestamps. It never stores prompts,
responses, objectives, source, diffs, commands, tool arguments, tool output,
credentials, usernames, environment values, or absolute paths. Chronos does not
transmit this state or create telemetry.

## Enforcement Boundary

The script enforces local leases, fencing, budgets, identity checks, state
integrity, Git scope validation, and explicit acceptance. Only the Codex runtime
can enforce worker tool permissions and report the worker's effective model.
Governor records an effective model as unverified when the runtime does not
report it and never invents that evidence.
