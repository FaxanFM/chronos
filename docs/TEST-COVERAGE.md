# Test Coverage

Chronos uses executable PowerShell integration tests on Windows rather than a
line-count claim. The release gate requires all suites to pass.

## Critical Safety Threshold

Governor declares 36 critical controls in `tests/governor.tests.ps1`. A control
is registered only after its associated assertion succeeds. The suite fails
unless 36 of 36 controls, or 100 percent, are exercised.

Coverage includes runtime model discovery, requested-model validation,
inventory failure, canonical workspace identity, mutation attribution,
traversal, global locks, fencing, renewal, writer serialization, result
fingerprints, coordinator verification, read-only enforcement, scopes,
correction and expiry limits, detached `HEAD`, linked worktrees, equivalent
paths, reparse points, real concurrent writer processes, stale and live locks,
malformed and interrupted state, privacy, and custom-state bypass prevention.
It also covers state outside Git metadata, state-store preflight failure,
single-use plan tokens, canonical `/root/name` worker IDs, comma-flattened scope
arguments, and operation when the former `.git` state location is unavailable.
Inactive legacy-state migration, active-legacy fail-safe behavior, and exact
planned-versus-effective worker model binding are also exercised.

## Diagnostic Coverage

`tests/chronos.tests.ps1` covers read-only SQLite access, active WAL detection,
missing data, exact helper failures and recovery, false-positive marker text,
malformed/truncated/duplicate/out-of-order rollout records, token aggregation,
files larger than `Int32.MaxValue`, aggregate 64-bit overflow regressions, and
advisory-only cleanup compatibility. Coverage assertions distinguish complete,
partial, unsupported, and unavailable event observations and require quota-risk
contributors even when no advice tag applies.

The suite also proves schema-aware automatic-review counting with 590
`turn_context` records plus 589 similarly named bookkeeping records, ensuring
the result is 590 rather than a text-match total. It covers bounded review
coverage semantics, anonymized reviewer-session aggregates, safe approval
classes, denial records, lineage counts, exact ancestor-token deltas, and exact
cross-rollout duplicated-compaction detection. Governor coverage includes
complete runtime cost ranking plus deterministic unranked and partially ranked
fallback behavior without assuming a model name.

Machine 2 coverage adds allowed/denied decisions, allow rate, inspection-shaped
boundary attribution, configured/effective reviewer labels, burst confidence,
reviewer-originated escalation, nested-reviewer negative behavior, task age,
lineage concentration, `fork_turns`, worker effort, inherited turns, and
root/child spawn origin. Dedicated fixtures require:

- 590 reviewer turns and 581 allowed unresolved retries to classify as an
  approval-state persistence runaway;
- 307 allowed and resolved reviews of one prefix to classify as a repeated rule
  miss with zero persistence retries;
- synthetic long-literal, broad interpreter, narrow, and credential-shaped
  rules to produce named diagnoses without returning any value;
- a simple full-history worker to warn about context amplification while a
  root-only spawn topology remains explicitly non-recursive;
- short reviewer samples and partial token tails to remain low confidence and
  local token totals to remain unsupported as billing evidence.

## Release Coverage

`tests/release.tests.ps1` requires two identical package hashes, sorted entries,
fixed timestamps, required plugin files, repository-file exclusion, and matching
checksums. CI and tagged releases run all three suites on `windows-latest`.
