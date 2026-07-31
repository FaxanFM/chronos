# Test Coverage

Chronos uses executable PowerShell integration tests on Windows rather than a
line-count claim. The release gate requires all suites to pass.

## Critical Safety Threshold

Governor declares 27 critical controls in `tests/governor.tests.ps1`. A control
is registered only after its associated assertion succeeds. The suite fails
unless 27 of 27 controls, or 100 percent, are exercised.

Coverage includes runtime model discovery, requested-model validation,
inventory failure, canonical workspace identity, mutation attribution,
traversal, global locks, fencing, renewal, writer serialization, result
fingerprints, coordinator verification, read-only enforcement, scopes,
correction and expiry limits, detached `HEAD`, linked worktrees, equivalent
paths, reparse points, real concurrent writer processes, stale and live locks,
malformed and interrupted state, privacy, and custom-state bypass prevention.

## Diagnostic Coverage

`tests/chronos.tests.ps1` covers read-only SQLite access, active WAL detection,
missing data, exact helper failures and recovery, false-positive marker text,
malformed/truncated/duplicate/out-of-order rollout records, token aggregation,
files larger than `Int32.MaxValue`, aggregate 64-bit overflow regressions, and
advisory-only cleanup compatibility.

## Release Coverage

`tests/release.tests.ps1` requires two identical package hashes, sorted entries,
fixed timestamps, required plugin files, repository-file exclusion, and matching
checksums. CI and tagged releases run all three suites on `windows-latest`.
