# Architecture And Safety Model

Chronos has two independent, on-demand skills.

## Health Inspector

`chronos.ps1` takes one bounded snapshot of candidate Codex Windows processes,
filesystem-helper events, disk availability, and the known diagnostic SQLite
database. SQLite access is read-only. Rollout access is limited to 2 MiB tails
from at most eight files selected by recent modification time across the
bounded session inventory, including old sessions resumed recently.

The rollout parser retains only numeric token aggregates, effort labels,
structured automatic-review counts, compaction counts, spawn counts, bounded
rollout metadata, approval-state categories, and parser-integrity counters. It counts a review only from a
`turn_context` record whose model is exactly `codex-auto-review`; bookkeeping
records are not additional reviews. It retains a valid final JSONL record even
without a newline and ignores only a final record that fails strict parsing,
rejects invalid or negative counters, reports exact cross-file duplicates and
duplicated compactions separately, and chooses the greatest valid cumulative
token total per file. When a child contains an exact ancestor token snapshot,
the child contributes only the observed cumulative delta. Ephemeral hashes and
safe categorical approval classes exist only for the inspection process.
Structured prefix arrays and correlation identifiers may be converted to
ephemeral hashes for repetition and state-transition analysis. Raw lines,
prompts, responses, arguments, prefixes, hashes, output, identifiers, and paths
are never returned or persisted.

Every token metric reports its six-hour coverage window, eligible and selected
file counts, tail truncation, and continuity. Spawn and compaction counts also
report whether an event was observed, not observed in complete coverage,
outside partial coverage, or unsupported by the recognized runtime format.
Cache-write fields are `unsupported_schema` when the runtime does not expose
them; absence is never reported as a measured zero. Quota classifications list their contributing measured thresholds without
changing the frozen scoring rules.

Automatic-review counts, review rate, and reviewer-versus-primary aggregates
are bounded observations. The parser reports its coverage and labels token
totals as selected-rollout cumulative snapshots, never as account billing.
Request-level approval causes and structural equivalence are reported only when
the rollout schema exposes sufficient structured data. A persistence runaway
requires an allowed request, an unresolved pending state, and an equivalent
regenerated request; review volume alone is insufficient. Repeated prefixes,
inspection-shaped operations, reviewer-originated escalations, nested reviewer
lineage, worker fork history, worker effort, and root/child spawn origin remain
separate concepts. Chronos never modifies approval state, policies, reviewer
configuration, runtime model catalogs, or sandbox permissions.

The Rule Governor reads bounded supported files in the known Codex rules directory.
It uses a balanced, string-aware parser for multiline `prefix_rule` blocks,
calculates aggregate length and structure statistics, and detects
credential-shaped patterns in memory. It never returns rule contents, prefix
hashes, commands, assignments, or credential values and never edits rules.

Filesystem-helper detection parses a timestamped event envelope and compares
the complete event message against known failure forms. Marker text embedded in
an unrelated payload does not count.

## Governor

`governor.ps1` is a synchronous advisory read-coordination state machine. It has no
scheduler, daemon, network client, or independent worker transport.

The trust boundaries are:

- Runtime metadata supplies the current model inventory.
- Optional complete runtime cost ranks allow deterministic lightest-compatible
  selection; missing or partial ranks preserve inventory order.
- Canonical Git and filesystem identity supplies repository/workspace identity.
- Shared-folder write delegation is disabled.
- A bounded Git-visible fingerprint provides a warning check for read workers,
  not proof of filesystem read-only behavior.
- The coordinator performs semantic review and final acceptance.

Failure at any identity, lease, fencing, fingerprint, or
verification boundary returns work to the coordinator without deleting or
reverting files.

Governor temp state is worker-reachable and unauthenticated. Atomic replacement
and owner locks coordinate concurrent processes but do not establish state
integrity. Git invocations disable configured fsmonitor, textconv, external
diffs, hooks, pagers, and relevant environment overrides.

When the runtime exposes an effective worker model, binding and result reporting
must match the model persisted by `plan`. A difference fails with
`model_plan_mismatch`; absent runtime evidence remains `runtime_not_exposed`.

## Persistent Data

The inspector persists nothing. Governor persists only metadata beneath the
current user's temporary application-data directory, keyed by a hash of Git's
canonical common directory. No component sends telemetry, starts a service,
creates a scheduled task, modifies Codex databases, terminates processes, or
cleans worktrees.

## Calibration Boundary

Health thresholds and quota scoring are heuristic observations, not predictions
of failure. v0.7.0 deliberately changes parser observability without changing any
warning threshold, critical threshold, scoring weight, predictive claim, or
heuristic interpretation. See [Calibration Methodology](CALIBRATION-METHODOLOGY.md).
