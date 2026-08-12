# Test Coverage

Chronos uses executable PowerShell integration tests on Windows. A named
scenario checklist is not a code-, branch-, mutation-, state-space-, or
security-coverage percentage, and the project does not describe it as one.

## Governor

`tests/governor.tests.ps1` currently runs 42 deterministic validations. They
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
installed `chronos.ps1` command surface. It covers normal and actionable paths
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
adaptation, persisted-state privacy, and
PowerShell 5.1 compatibility.

These tests validate deterministic transition and Governor-inbox decisions.
They do not prove that the host collected complete evidence, delivered an
event, or configured the recommended Luna Medium Governor. Missing host data
remains partial or unsupported.

## Passive Supervision

`tests/supervision.tests.ps1` exercises the packaged hook schema, native
`chronos.ps1 -Action supervise` wrapper, empty status, lifecycle start and end,
strict UTF-8 and BOM-framed hook input,
Governor claim and conflict, revision cursors, duplicate events, active-agent
discovery, rotating eight-entry batches across 17 tasks, bounded idle and active
cadence, host equivalence key, reconciliation retry budget and postcondition,
cycle and age limits, current-user protected identifiers, transcript
and workspace-path non-persistence, malformed and oversized hook input,
duplicate and case-colliding JSON keys, corrupt-state preservation, custom-state
containment, concurrent cross-process writes, delayed starts after terminal
events, host-confirmed reactivation, two-phase release, live mutex contention,
full 256-record capacity behavior, silent hook output, headless Windows commands,
lifecycle-only event coverage, and absence of scheduler, process-launch, and
network primitives.

These tests validate local discovery and persistence. They do not prove that a
user trusted the hook, that host task and automation tools are available, that
a task remains live, that a host reconciled exactly one recurrence, or that the
host selected Luna Medium. Those behaviors require an installed-package host
canary. The registry remains advisory.

## Release

`tests/release.tests.ps1` builds twice and requires identical ZIP hashes,
tracked-file-only packaging, sorted entries, fixed timestamps, LF text,
per-file manifest hashes and sizes, pre-materialization package limits, required
plugin files, repository-file exclusion, and a matching artifact checksum. It
also extracts the exact ZIP as a fresh install, verifies the two-skill inventory
and version, and runs the packaged Heartbeat and supervision status commands.

Tagged CI runs inspector, Heartbeat, supervision, Governor, and release tests on two Windows runner
labels. Privileged publication is a separate job. Actions are pinned, the
artifact attestation is verified before a draft is created, and the immutable
release and assets are verified again after publication.
