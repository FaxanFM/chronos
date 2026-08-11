# Field Report Ledger

This public ledger records sanitized, cause-level findings. It contains no
machine names, task IDs, usernames, local paths, prompts, source, raw state, or
diagnostic records. A report is not field validation until another installation
successfully exercises the candidate release from a fresh task.

## Confirmed Bugs

### Open task retains a removed versioned skill locator

- Affected context: an open task created with Chronos v0.6.1, after the local
  plugin cache was upgraded to v0.7.x.
- Reproduction scope: repeated on one installation and one existing task; not
  reproduced independently on both machines.
- Environment: upstream Codex task catalog and versioned plugin-cache lifecycle.
- Evidence: the task continued to advertise its captured v0.6.1 skill path,
  while the plugin manager retained only the newer installed version.
- Root cause: the open task's injected skill catalog did not refresh when the
  plugin manager replaced the cached version. This occurs before Chronos loads
  and is not a Chronos runtime or Governor-state failure.
- Safe response: fully close Codex for installation, then use a fresh task.
  Never disguise the mismatch by copying or linking newer code under an older
  version directory.
- Deterministic validation: start a task with version A, replace A with version
  B through the plugin manager, confirm the old task retains A's locator, then
  confirm a fresh task loads B. This upstream scenario remains reportable to
  the Codex plugin lifecycle owner.

### Governor status hid an independent-machine failure

- Affected version: v0.7.2.
- Reproduction scope: repeatable on one independent Windows installation; the
  same command succeeds in the development installation, so it is presently
  environment or persisted-state specific.
- Evidence: the documented `status` action launched the installed script and
  returned exit code 1 with only `error=internal_error`.
- Root cause: v0.7.2 allowed some parseable but structurally invalid state to
  reach migration or summary code, and its outer handler discarded the failure
  boundary and exception class. The independent machine's exact underlying
  exception cannot be claimed until the hardened result is exercised there.
- v0.7.3 correction: validate state maps and signed 64-bit revision boundaries;
  distinguish unreadable, failed, invalid-JSON, and invalid-schema state; and
  attach only privacy-safe stage and exception-class metadata to unknown errors.
- Regression: deterministic tests cover malformed JSON, non-map collections,
  an out-of-range revision, interrupted writes, and the unknown-error output
  contract. Existing state is preserved on every failure.
- Validation status: v0.7.3 Governor `status` succeeded from a fresh task on an
  independent Windows installation against a valid nested repository. It
  correctly reported three idle workers, no active workers, no pending plans,
  and disabled write delegation. v0.7.3 is field-validated for this path.

### Current approval schema was reported as unsupported

- Affected versions: v0.7.0 through v0.7.3.
- Reproduction scope: observed in independent field output and reproduced by a
  deterministic local fixture using the current structured rollout shape.
- Evidence: escalated `response_item/function_call` records were present while
  `approvalRequestObservation=unsupported_schema` and request counts were zero.
- Root cause: the inspector recognized legacy `event_msg` approval requests but
  did not register structured function calls whose categorical permission was
  `require_escalated`.
- v0.7.4 correction: count only the structured categorical request shape,
  correlate bounded terminal results by an ephemeral call-ID hash, and return
  schema, resolved/unresolved, and latency aggregates. Never return arguments,
  output, IDs, prefixes, or hashes; never infer a decision from tool completion.
- Regression: current-schema requests, one resolved result, one unresolved
  result, latency, repetition, and secret-bearing private fields are exercised.

### Partial rollout coverage permitted incomparable projections

- Affected versions: v0.7.0 through v0.7.3.
- Reproduction scope: repeated field observations and deterministic truncated
  tail fixtures.
- Evidence: selected cumulative snapshots and file-lifetime projections moved
  under capped or truncated coverage without corresponding interval semantics.
- Root cause: cumulative snapshots drove the frozen quota heuristic while file
  lifetime projection remained populated before continuity was classified.
- v0.7.4 correction: add timestamped marginal interval deltas and suppress the
  projection after any partial-continuity condition. The frozen score still
  uses its existing cumulative basis and is labeled as such.
- Regression: two comparable token snapshots and an over-2-GiB truncated tail.

## Heuristic / Tuning Issues

No threshold, scoring, prediction, or calibration-sensitive change is included
in v0.7.4. Existing calibration work remains frozen pending labeled evidence.

## Feature / UX Improvements

- Make the fresh-task requirement explicit after every plugin install or
  upgrade.
- Explain that a missing old cache path can be stale task catalog state rather
  than a missing current installation.
- Return actionable, privacy-safe Governor recovery metadata without telemetry
  or local log collection.
- Report the active installed manifest version, plan cancellation, expired-plan
  capacity, threshold contributors, and privacy-safe rule candidate categories.

## v0.7.6 Release Verification

- Signed release commit and annotated tag verified with the configured ED25519
  signer; GitHub reports the commit signature as valid.
- Immutable GitHub release contains the ZIP, checksum, and per-file release
  manifest. The ZIP SHA-256 is
  `e90c789d56e3b512109b467f116721c2fe948d66c89a77c624162ab538e88497`.
- Two GitHub artifact attestations are published and every release/test workflow
  completed successfully.
- Local plugin replacement retained only cache version v0.7.6. Installed
  Governor `status` reported its manifest version, three idle workers, no active
  workers, no pending or expired plans, and disabled write delegation.
- An independent Windows installation loaded v0.7.6 from signed annotated tag
  object `1e9f4d6`, which resolves to release commit `6811cea`. Governor
  `status` returned `ok=true`, `plugin_version=0.7.6`, state version 4, no
  active workers, no pending plans, no stale or expired leases, two idle
  workers, and disabled write delegation. One expired plan remained as
  historical metadata and did not reserve capacity.
- This independently validates installation, version reporting, state loading,
  status, and expired-plan capacity semantics. It does not validate a complete
  `plan` to `lease` to `result` to `verify` to `accept` lifecycle.

## v0.7.7 Independent Canary

- Candidate commit: `db23dc0debb27317697f8b1e824dbaf59f3d3e39`.
- Candidate ZIP SHA-256:
  `b74e3a595f218eedf70658edd63364827f861e75d377d9a286cbdc91f88076ee`.
- An independent Windows installation refreshed the public Chronos marketplace,
  installed manifest version v0.7.7, opened a fresh Codex task, and exercised
  the requested canary procedure.
- The independent operator reported that v0.7.7 worked as expected. No failure,
  stale version path, or version-reporting mismatch was reported.
- This clears the independent-installation gate for publishing v0.7.7. The
  report is intentionally sanitized and does not record a machine name, user,
  workspace, repository, task, or session identifier.

## v0.7.7 Release Verification

- Signed annotated tag `v0.7.7` resolves to signed release commit
  `dbe5084442b1ca07989826495b97d6a11dcb8cf8`; GitHub reports both signatures as
  verified.
- The tag-triggered Test workflow passed on Windows Server 2022 and the current
  Windows runner. The Release workflow also passed both test jobs and its
  publication job.
- The GitHub release is immutable and marked Latest. It contains the ZIP,
  checksum, per-file release manifest, source archives, and release
  attestation. GitHub artifact attestation `40038741` was created by the release
  workflow, and the release page exposes attestation `40038775`.
- Published ZIP SHA-256:
  `b74e3a595f218eedf70658edd63364827f861e75d377d9a286cbdc91f88076ee`.
  This exactly matches the independently audited and externally exercised
  candidate.
- Local installation from the refreshed public marketplace reports v0.7.7.
  All ten installed package files match the release manifest hashes. Inspector
  completed with `machineHealth=HEALTHY`, and Governor `status` returned
  `ok=true`, no active or stale leases, and disabled shared-folder write
  delegation.
