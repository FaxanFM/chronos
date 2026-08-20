# Test Coverage

Chronos uses executable PowerShell integration tests on Windows. A named
scenario checklist is not a code-, branch-, mutation-, state-space-, or
security-coverage percentage, and the project does not describe it as one.

## Governor

`tests/governor.tests.ps1` currently runs 46 deterministic validations. They
cover runtime inventory selection, model binding, canonical worker IDs,
single-use plan tokens, V2 `fork_turns=none`, categorical write containment,
one active lease per worker, fencing, renewal, read-mutation detection,
terminal lifecycle transitions, expiry, detached `HEAD`, linked worktrees,
equivalent paths, stale and live locks, malformed and interrupted state,
unwritable state, privacy, legacy migration and write-lease quarantine,
clean-filter non-execution, pending-plan capacity, plan-to-lease workspace
mutation rejection, expired verified release, and custom-state rejection.

These tests validate modeled behavior. They do not turn Governor into a
security boundary. Write delegation remains disabled.

## Inspector

`tests/chronos.tests.ps1` covers logical read-only SQLite access, main-file
integrity, Windows WAL/SHM directory comparison and sidecar reporting, active WAL detection,
partial, unreadable, and missing databases, helper failure and recovery, false-positive
markers, 64-bit counter boundaries, malformed and out-of-order rollout data,
valid final JSONL records without newlines, timestamped and untimestamped exact duplicates, inherited token
deltas, modification-time discovery for old resumed sessions, absent
and partial cache-write schemas, automatic-review counting, explicit spawn
schema, V1 `fork_context=false` and missing-context semantics, low-confidence
rate labeling, approval persistence across regenerated and stable IDs,
cross-schema mirror deduplication, complete/partial/no resolution outcomes,
known-decision denominators, independent-ALLOW and prefix-required rule-miss
postconditions, denied/unresolved rule-miss prevention, escaped reparse paths,
streaming inventory source guards, large-rollout head timestamps, primary and
legacy process-exit isolation, and bounded structured permission-rule parsing
across single, double, raw, triple, nested-alternative, reordered, escaped, and
commented forms, including raw Windows paths, displaced arbitrary-code flags,
option-only prefixes, branch-specific missing operands, and scalar or
alternative fixed-script negative controls.

The tests require explicit coverage and availability fields. Local token and
approval aggregates remain unsupported as account billing evidence.

## Heartbeats

`tests/heartbeat.tests.ps1` exercises the native Heartbeat action through the
installed `chronos.cmd` and `chronos.ps1` command surfaces. Both Windows CI jobs build and extract
the release ZIP, then run this complete suite against that package. The same
suite accepts a source plugin root for local development. State-containment
cases use a path outside both approved roots and separately verify that
state-path rejection precedes malformed-input parsing regardless of the package
extraction folder. A separate regression rejects an unrelated TEMP sibling
without creating its directory or file. It covers normal and actionable paths
for all eight families, first observation and current-versus-previous deltas,
deduplication, material escalation, resolution, Governor-only routing with
preserved owner hints, silent normal cycles, recursion
suppression, per-family cadence and coverage, bounded persistence, malformed and
oversized input or state, duplicate and case-colliding JSON keys, strict Boolean
and integer handling, secret-shaped values, Windows and Unix absolute-path
identifiers, state replacement, duplicate scheduler execution, case-alias
cross-process serialization, cross-session mutex naming, hard-link rejection,
abandoned-mutex recovery, originating source-epoch binding, source sequence and
counter rollback, missing-entity and missing-source non-resolution, same-run
outbox retry, replayed-evidence wall-clock retry, acknowledgement,
reparse-point containment, out-of-order
timestamps, due replay after a newer evidence cycle, compact Inspector-field
adaptation, persisted-state privacy, legacy-to-schema-7 migration, denied
prior-state recovery when the Windows host enforces the simulated ACL even when
an older LocalAppData fallback is readable, prior-scope junction rejection,
read-only import when the ACL denial is not enforced, explicit no-prior-write
status, accessible empty-scope negative control, explicit busy-cycle retry, one
active record per target generation, compatible eight-event coalescing,
incompatible-contract deferral, higher-severity replacement, fixed action
contracts, self-target rejection, same-subject and same-window Governor-usage
corroboration, transport acceptance versus task acknowledgement, ambiguous-send
non-retry, two-attempt definite-failure retry, exact reporter and generation
binding, task-report non-resolution, wrong-state and public-engine verification
rejection, independent postcondition verification, bounded restart listing,
expired-claim reclaim, incompatible-environment non-resolution,
Governor status-counter exposure, success, duplicate, and failed-cycle
accounting, Governor supervision-counter progress, missing-counter containment,
Governor-local throttle and restore actions, isolated 6.3 percent runtime
variance, sustained modest overruns, material overruns, runtime recovery,
explainable compact backoff status, and PowerShell 5.1 compatibility.

These tests validate deterministic transition, Governor-inbox, and intervention
state decisions. They do not prove that the host collected complete evidence,
called `send_message_to_thread`, delivered an event to the correct installed
task, or configured the recommended Terra Medium Governor. Missing host data
remains partial or unsupported. An external autonomy canary must prove one exact
target wake, no unrelated wake, ambiguous-send containment, duplicate
suppression, task-to-Governor response, independent recovery, Governor self-loop
prevention, subject-only, owner-only, and subject-or-owner target binding, and
silent normal cycles.

## Passive Supervision

`tests/supervision.tests.ps1` exercises the packaged hook schema, native
`chronos.cmd` and `chronos.ps1 -Action supervise` wrappers, empty status,
lifecycle start and end,
asynchronous completed-turn activity, duplicate turn-signal deduplication,
mid-session self-discovery,
strict UTF-8 and BOM-framed hook input,
Governor claim and conflict, revision cursors, duplicate events, active-agent
discovery, rotating eight-entry batches across 17 tasks, bounded idle and active
cadence, stable and isolated opaque installation equivalence keys, malformed
scope rejection, reconciliation retry budget and postcondition,
cycle and age limits, mandatory complete per-cycle host inventory
reconciliation, one hash-only normalized status per inventory task, passive
non-advancing discovery, missed-hook task recovery, absent-task closure, stale inventory
rejection, state-store preflight, current-user protected identifiers, transcript
and workspace-path non-persistence, malformed and oversized hook input,
duplicate and case-colliding JSON keys, corrupt-state preservation, custom-state
containment, concurrent cross-process writes, monotonic host timestamp/rank
ordering, task generation changes, delayed starts after terminal events,
host-confirmed reactivation, forced-takeover postconditions, two-phase release,
live mutex contention with deterministic state and queue postconditions, atomic bounded fallback slots, stale reservation
recovery, protected fallback contents, reconciliation and
entry removal after contention, prevention of fallback parent-directory races,
full 256-record capacity behavior, silent hook output,
headless Windows commands, the exact quote-free manifest command through the
Codex-style `cmd.exe /D /S /C` boundary, a plugin root containing spaces,
fresh `hookRuns` and `lastHookUtc` evidence, bounded event coverage, correct asynchronous flags
with synchronous `SessionEnd`, absence of high-frequency prompt/tool hooks, and
absence of scheduler, process-launch, and network primitives.

The suite does not use an elapsed-time threshold as a correctness assertion;
the production hook ceiling and fixed mutex waits are validated structurally,
while process timeouts only stop a hung test. These tests validate local discovery and persistence. They do not prove that a
user trusted the hook, that host task and automation tools are available, that
a task remains live, that a host reconciled exactly one recurrence, or that the
host selected Terra Medium. Those behaviors require an installed-package host
canary. The registry remains advisory.

## Release

`tests/release.tests.ps1` requires exactly three unique, single-line Directory
starter prompts under 128 characters. It enforces separate semantic coverage
for complete setup, separated full status, and bounded read-only delegation,
plus current listing values and end-to-end public setup guidance. It then builds
twice and requires identical ZIP hashes,
tracked-file-only packaging, sorted entries, fixed timestamps, LF text,
per-file manifest hashes and sizes, canonical Directory distribution identity, pre-materialization package limits, required
plugin files, repository-file exclusion, and a matching artifact checksum. It
also extracts the exact ZIP as a fresh `chronos@openai-curated-remote` cache
install, verifies canonical registry discovery, the two-skill inventory and version, and runs the packaged `.cmd` Heartbeat and supervision status
commands so execution-policy handling is part of the release gate. The release
suite also executes the installed package's exact Windows hook definition
through `cmd.exe` from a path containing spaces and requires silent registry
activity. This prevents a scan-valid hook definition from passing while its
payload never starts.

Tagged CI runs inspector, Heartbeat, supervision, Governor, and release tests on two Windows runner
labels. Privileged publication is a separate job. Actions are pinned, the
artifact attestation for every release asset is verified before a draft is
created. After publication, the workflow verifies the immutable release and
assets, downloads every asset, compares its bytes with the verified build, and
checks that the published release record binds the canonical identity to the
ZIP digest.
