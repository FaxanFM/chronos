# Chronos Governor

Chronos Governor coordinates small read-only Codex worker tasks. It is a local
workflow aid, not an authorization service, security sandbox, or proof of
filesystem isolation.

## v0.7.0 Safety Decision

Shared-folder write delegation is disabled. A write `plan` returns:

```text
decision=coordinator reason=shared_folder_write_delegation_disabled
```

`lease` also rejects a legacy write plan. Chronos will not restore write
delegation until workers run in disposable isolated repositories, return a
patch or content-addressed result, and authoritative state and result evidence
are protected by a coordinator-owned broker or equivalent runtime boundary.

The change is intentional. The previous design could coordinate writers but
could not prove exact mutation scope, prevent temporary Git-object leakage, or
protect its JSON state from a worker that could reach the same temporary path.

## Read Coordination

Eligible tasks include repository exploration, bounded review, documentation
analysis, test analysis, and focused verification that does not edit files.
Architecture, security, dependencies, CI, deployment, releases, destructive
work, and every edit remain with the coordinator.

The normal lifecycle is:

```text
plan -> spawn with fork_turns=none -> lease -> result -> verify -> accept
                                      |                    |
                                      +-> renew            +-> correct once
                                      +-> release          +-> retire
```

Plans select only models advertised by the active runtime. Missing or malformed
inventory returns the work to the coordinator. Selection is deterministic:
complete runtime cost ranks are honored; otherwise runtime inventory order is
preserved. A worker ID can own only one active lease.

The current Codex Multi-Agent V2 contract uses `fork_turns="none"`. Governor
does not emit the removed V1 `fork_context` field. Worker-created agents are
prohibited by assignment policy, but Governor cannot remove that runtime tool.

## Advisory Mutation Check

Governor records a bounded Git-visible fingerprint before a read lease and at
result. Git runs with fsmonitor, text conversion, external diffs, hooks, pagers,
and relevant environment overrides disabled. Fingerprint input is capped.

This detects useful classes of accidental repository edits. It does not cover
every ignored file, Git metadata effect, alternate data stream, ACL, timestamp,
hard link, transient mutation, or filesystem alias. A passing check is not a
verified read-only property. The active Codex sandbox remains the permission
boundary.

## State

State is stored beneath the current user's temporary directory at:

```text
Chronos/Governor/<repository-hash>/governor-state.json
```

It contains opaque coordination metadata only. It is atomically replaced and
protected against concurrent writers by an owner-identified lock, but it is not
authenticated or isolated from every worker. A process that can reach the file
can alter or delete it. Therefore the state is never presented as authorization
or integrity evidence.

Linked worktrees share `repository_id`; each worktree has a distinct
`workspace_id`. Worker reuse additionally requires the exact workspace, role,
model, reasoning effort, and access mode. Policy limits are copied from plan to
lease. Terminal lifecycle transitions cannot be rewritten.

## Privacy

Governor stores no prompts, responses, objectives, source, diffs, commands,
tool arguments, output, credentials, usernames, environment values, or absolute
paths. It has no network client or telemetry. Verification may return
repository-relative changed paths so the coordinator can inspect a failed read
check.

## Troubleshooting

- `shared_folder_write_delegation_disabled`: perform the edit as coordinator.
- `state_store_unwritable`: continue locally; no worker was authorized.
- `state_lock_unavailable`: wait briefly or continue locally; do not delete it.
- `worker_already_leased`: finish or release the worker's current lease.
- `workspace_fingerprint_limit_exceeded`: stop delegation and inspect locally.
- `read_worker_modified_workspace`: preserve and review the changes.
- `invalid_lifecycle_transition`: preserve the terminal record.

See the installed Governor skill for the command contract and
[Architecture](ARCHITECTURE.md) for the wider trust model.
