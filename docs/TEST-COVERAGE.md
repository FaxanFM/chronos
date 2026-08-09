# Test Coverage

Chronos uses executable PowerShell integration tests on Windows. A named
scenario checklist is not a code-, branch-, mutation-, state-space-, or
security-coverage percentage, and the project does not describe it as one.

## Governor

`tests/governor.tests.ps1` currently runs 32 deterministic validations. They
cover runtime inventory selection, model binding, canonical worker IDs,
single-use plan tokens, V2 `fork_turns=none`, categorical write containment,
one active lease per worker, fencing, renewal, read-mutation detection,
terminal lifecycle transitions, expiry, detached `HEAD`, linked worktrees,
equivalent paths, stale and live locks, malformed and interrupted state,
unwritable state, privacy, legacy migration, and custom-state rejection.

These tests validate modeled behavior. They do not turn Governor into a
security boundary. Write delegation remains disabled.

## Inspector

`tests/chronos.tests.ps1` covers read-only SQLite access, active WAL detection,
unreadable and missing databases, helper failure and recovery, false-positive
markers, 64-bit counter boundaries, malformed and out-of-order rollout data,
valid final JSONL records without newlines, exact duplicates, inherited token
deltas, modification-time discovery for old resumed sessions, absent
cache-write schema, automatic-review counting, low-confidence rate labeling,
approval persistence sequences, and bounded multiline permission rules.

The tests require explicit coverage and availability fields. Local token and
approval aggregates remain unsupported as account billing evidence.

## Release

`tests/release.tests.ps1` builds twice and requires identical ZIP hashes,
tracked-file-only packaging, sorted entries, fixed timestamps, LF text,
per-file manifest hashes and sizes, required plugin files, repository-file
exclusion, and a matching artifact checksum.

Tagged CI runs inspector, Governor, and release tests on two Windows runner
labels. Privileged publication is a separate job. Actions are pinned, the
artifact attestation is verified before a draft is created, and the immutable
release and assets are verified again after publication.
