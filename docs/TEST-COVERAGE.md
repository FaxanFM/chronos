# Test Coverage

Chronos uses executable PowerShell integration tests on Windows rather than a
line-count claim. The release gate requires all suites to pass.

## Critical Safety Threshold

Governor declares 35 critical controls in `tests/governor.tests.ps1`. A control
is registered only after its associated assertion succeeds. The suite fails
unless 35 of 35 controls, or 100 percent, are exercised.

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
Inactive legacy-state migration and active-legacy fail-safe behavior are also
exercised.

## Diagnostic Coverage

`tests/chronos.tests.ps1` covers read-only SQLite access, active WAL detection,
missing data, exact helper failures and recovery, false-positive marker text,
malformed/truncated/duplicate/out-of-order rollout records, token aggregation,
files larger than `Int32.MaxValue`, aggregate 64-bit overflow regressions, and
advisory-only cleanup compatibility. Coverage assertions distinguish complete,
partial, unsupported, and unavailable event observations and require quota-risk
contributors even when no advice tag applies.

## Release Coverage

`tests/release.tests.ps1` requires two identical package hashes, sorted entries,
fixed timestamps, required plugin files, repository-file exclusion, and matching
checksums. CI and tagged releases run all three suites on `windows-latest`.
