# Architecture And Safety Model

Chronos has two independent, on-demand skills.

## Health Inspector

`chronos.ps1` takes one bounded snapshot of Codex-owned Windows processes,
filesystem-helper events, disk availability, and the known diagnostic SQLite
database. SQLite access is read-only. Rollout access is limited to 2 MiB tails
from at most eight recently active files.

The rollout parser retains only numeric token aggregates, effort labels,
compaction counts, spawn counts, and parser-integrity counters. It ignores a
partially written final record, rejects invalid or negative counters, ignores
exact timestamped duplicates, reports out-of-order records, and chooses the
greatest valid cumulative token total per file. Raw lines, prompts, responses,
arguments, output, and paths are never returned or persisted.

Every token metric reports its six-hour coverage window, eligible and selected
file counts, tail truncation, and continuity. Spawn and compaction counts also
report whether an event was observed, not observed in complete coverage,
outside partial coverage, or unsupported by the recognized runtime format.
Quota classifications list their contributing measured thresholds without
changing the frozen scoring rules.

Filesystem-helper detection parses a timestamped event envelope and compares
the complete event message against known failure forms. Marker text embedded in
an unrelated payload does not count.

## Governor

`governor.ps1` is a synchronous lease and verification state machine. It has no
scheduler, daemon, network client, or independent worker transport.

The trust boundaries are:

- Runtime metadata supplies the current model inventory.
- Canonical Git and filesystem identity supplies repository/workspace identity.
- Runtime-provided attribution, when available, binds a write to a worker.
- Git state and content fingerprints provide independent mutation evidence.
- The coordinator performs semantic review and final acceptance.

Failure at any identity, attribution, scope, lease, fencing, fingerprint, or
verification boundary returns work to the coordinator without deleting or
reverting files.

## Persistent Data

The inspector persists nothing. Governor persists only metadata beneath the
current user's temporary application-data directory, keyed by a hash of Git's
canonical common directory. No component sends telemetry, starts a service,
creates a scheduled task, modifies Codex databases, terminates processes, or
cleans worktrees.

## Calibration Boundary

Health thresholds and quota scoring are heuristic observations, not predictions
of failure. v0.5.4 deliberately changes parser observability without changing any
warning threshold, critical threshold, scoring weight, predictive claim, or
heuristic interpretation. See [Calibration Methodology](CALIBRATION-METHODOLOGY.md).
