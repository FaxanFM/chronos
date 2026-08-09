# v0.7.0 Audit Response

This is the sanitized maintainer disposition for the static audit of Chronos
v0.6.1 at commit `d241cb974dc74fe47c6dbdac31a65e154348fafe`.
It contains no machine names, task IDs, paths, rollout content, credentials, or
private source.

`Fixed` means a deterministic regression exists in this repository. `Contained`
means the unsafe feature is disabled or the claim is removed. `Deferred` means
the finding requires a runtime or architecture boundary that a PowerShell
plugin cannot honestly simulate.

## Confirmed Bugs

| Cause | v0.7.0 disposition | Validation |
| --- | --- | --- |
| Shared-folder write delegation relied on worker-reachable state and final Git projections | **Contained:** write planning and legacy write leasing are disabled | Governor write-containment scenarios |
| Git checks could honor fsmonitor, textconv, external diff, hook, pager, trace, or environment configuration | **Fixed** for Governor-owned checks | Sanitized Git wrapper plus source assertions |
| Multi-Agent V2 received the removed `fork_context` contract | **Fixed:** plans emit `fork_turns=none` only | V2 contract regression |
| One worker ID could own multiple active leases | **Fixed** | Dual-lease rejection regression |
| Worker reuse omitted workspace and effort | **Fixed** | Exact reuse predicate |
| SQLite query failure could look healthy | **Fixed:** per-query availability and `query-unavailable` warning | Invalid SQLite regression |
| Top-line critical conflated diagnostic storage with live machine operability | **Fixed:** headline is machine health; resource and overall levels are separate | Live inspection plus fixture assertions |
| Line-oriented rule inspection missed multiline Starlark rules | **Fixed:** bounded balanced parser | Multiline and credential-shaped fixtures |
| Missing cache-write schema became a false zero | **Fixed:** `unsupported_schema` and unknown value | Missing-field regression |
| Exact replayed rollout events inflated aggregates | **Fixed** for exact record hashes | Fork/replay fixtures |
| Tail-only reads lost session metadata | **Fixed:** bounded metadata head plus bounded event tail | Large-rollout regression |
| Old sessions resumed recently were missed by date-folder search | **Fixed:** bounded modification-time inventory | Old-session fixture |
| Fingerprinting could load an unbounded binary patch | **Contained:** textconv/binary payload disabled and fingerprint input capped | Limit error path and Governor suite |
| Release verification began only after publication | **Fixed:** attestation is verified before draft creation; immutable release is verified after publication | Workflow-order regression |
| Desktop/helper process counts used case-insensitive equality | **Fixed:** ordinal process-name classification | Source validation and live output |
| Approval equivalence omitted prefix structure when categories existed | **Fixed:** categories and ephemeral prefix fingerprint are combined | Approval repetition fixtures |
| One persistence write error was called a runaway | **Fixed:** error and unresolved-allow retry sequences are separate | Persistence fixtures |
| A valid final JSONL record without a newline was dropped | **Fixed** | Newline-free JSONL regression |
| Review rate used event count rather than intervals | **Fixed:** `(N-1)/elapsed` | Rate fixtures |
| Optional SQLite query failure discarded all metrics | **Fixed:** page, sequence, and level queries report independently | SQLite fixtures |
| Lifecycle terminal states could be rewritten | **Fixed:** explicit transition rejection | Accepted-then-release regression |
| Plan/lease limits were caller-controlled on later actions | **Fixed for active lease policy:** policy snapshot is copied from plan | Governor policy regressions |
| Package input used directory enumeration | **Fixed:** tracked allowlist, untracked rejection, reparse ancestry checks, per-file hashes | Reproducible package suite |
| Mutable Actions and broad publication job | **Fixed:** commit pins, two Windows test labels, unprivileged tests, bounded privileged job | Workflow source gate |
| Fourth starter prompt was ignored | **Fixed:** manifest contains three prompts | Manifest validation |
| Security maintenance files were missing | **Fixed:** security policy, CODEOWNERS, and Dependabot configuration | Tracked release source review |

The above defects are source-level or fixture-reproducible and do not require
both field machines to demonstrate the same code path. Live diagnostic-label
behavior has been exercised on the development machine. Independent installer
validation remains required before the version is called field-validated.

## Heuristic / Tuning Issues

- Warning and critical thresholds, scoring weights, quota classifications, and
  predictive claims remain frozen.
- Diagnostic database size, reclaimable pages, sequence churn, WAL activity,
  and measured machine health remain separate. Database allocation is not
  described as physical SSD-write volume or proof of wear.
- Reviewer concurrency remains a `file_activity_span_estimate`; it is labeled
  and is not a precise active-worker timeline.
- Rollout rate remains a `file_lifetime_average_not_measured_delta`; the old
  growth wording is retained only for output compatibility.
- Mixed reviewer/primary token files are unclassified instead of assigning the
  entire cumulative total to the final turn role. These values remain
  unsupported as billing evidence.
- Global-maximum token snapshots, effort-by-turn summaries, helper event-family
  coverage, and false-positive marker calibration need more fixtures before
  further classification changes.
- No threshold or heuristic change is approved until the published calibration
  methodology has at least two weeks of labeled, sanitized observations.

## Feature / UX Improvements

Completed in v0.7.0:

- Explicit machine, resource, overall, quota, rule, coverage, continuity, and
  availability fields.
- Explicit advisory/security-boundary fields in Governor output.
- Unique plan IDs, exact worker reuse identity, immutable lease policy, and
  explicit lifecycle errors.
- Tracked release manifests with per-file hashes and sizes.
- Clear upgrade, rollback, security-reporting, and attestation instructions.

Deferred architecture:

- Coordinator-owned authenticated state broker with rollback protection.
- Disposable worker repository and object store.
- Patch or content-addressed result transport applied only by the coordinator.
- Runtime-signed worker identity, model identity, mutation evidence, and
  verification envelopes.
- Runtime-enforced child tool profile with agent spawning removed.
- Byte-safe NUL-delimited Git path handling and structured repeated scopes.
- Append-only plan/lease event retention and explicit plan cancellation.
- Cross-environment compression reproduction beyond the two Windows CI labels.

Write delegation must remain disabled until the broker, isolation, and trusted
result-evidence items are implemented and independently reviewed.
