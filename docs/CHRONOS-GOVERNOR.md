# Chronos Governor

Chronos Governor is an optional companion to Chronos health inspection. It lets
the current Codex coordinator hand off a small repository task to a native worker
while retaining control of scope, concurrency, verification, and acceptance.

It is not a background service, unrestricted autonomous loop, source-control
replacement, or automatic merge system.

## Good Worker Tasks

- Repository exploration and reference finding.
- Documentation and formatting changes.
- Focused test creation or execution.
- Mechanical refactoring.
- Small localized code changes with clear interfaces.
- Independent review of a bounded change.

Architecture, security-sensitive work, payments, authentication, migrations,
dependency manifests, CI, releases, deployment, and irreversible operations
remain with the coordinator.

## Default Limits

| Control | Default |
| --- | --- |
| Active workers | 2 |
| Active writers per repository | 1 |
| Total attempts per task | 3 |
| Corrections per worker | 1 |
| Delegation depth | 1 |
| Full parent context inheritance | Disabled |
| Final coordinator verification | Required |
| Automatic merge or cleanup | Disabled |

Governor prefers a native `gpt-5.6-luna` worker. Low reasoning is used for
mechanical work, documentation, exploration, and command execution. Medium is
used for simple code, focused tests, and substantial review. A model is used only
when the current native worker runtime advertises it.

## Same-Repository Writer

Write delegation requires a clean current working tree and an exact
repository-relative scope. Governor rejects absolute paths, traversal, `.git`,
`.chronos`, repository-wide wildcards, and a second active writer.

Dependency manifests, lockfiles, migrations, Docker configuration, and
`.github/**` are global locks and stay with the coordinator. After a worker
returns, Governor checks the actual Git changes against the stored base commit
and declared scope. Worker claims alone are never accepted.

Native Codex may isolate a worker in an internal forked workspace. Governor does
not build a competing checkout system and does not merge or delete that work.

## Lifecycle

```text
plan -> spawn or resume -> lease -> work -> result -> verify -> accept
                                      |                 |
                                      +-> correct once -+
                                      +-> retire
```

If planning recommends `coordinator`, the user's objective continues locally;
Governor does not block the task. Critical health advises against adding a new
worker but never terminates active work.

Completed native workers should be closed to release concurrency. Their
resumable IDs may remain idle in metadata and can be resumed for a compatible
future task.

## State And Privacy

State defaults to Git's private metadata path:

```text
.git/chronos/governor-state.json
```

Linked worktrees resolve through Git's own metadata path. The file is written
under a short exclusive lock and replaced atomically.

State contains only opaque task and worker IDs, a repository hash, base commit,
relative scopes, role, access mode, model labels, reasoning effort, status,
counters, timestamps, and changed-file count.

It never contains prompts, responses, objectives, source, diffs, commands, tool
arguments, tool output, credentials, usernames, environment values, absolute
paths, or personal data. Chronos does not transmit it or clean it automatically.

## Honest Enforcement Boundary

The PowerShell governor enforces local leases, budgets, state integrity, Git
scope validation, and explicit acceptance. The companion skill controls how the
coordinator invokes native Codex workers.

Only Codex's runtime can technically remove tools from a worker. Governor places
`Do not spawn or delegate to another agent` in every assignment, fixes depth at
one, and requires the coordinator to reject violations, but it does not present
that prompt contract as a security sandbox.

Requested model identity comes from the spawn request. When the runtime does not
report the effective model, Governor marks it unverified instead of guessing.
