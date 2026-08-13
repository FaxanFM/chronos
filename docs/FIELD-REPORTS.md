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

## v0.8.0 Release Verification

- Signed annotated tag `v0.8.0` resolves to signed release commit
  `9ce24fd83be9f174f196733d28467ba0a700b406`; GitHub reports the commit and tag
  signatures as valid.
- Published ZIP SHA-256:
  `d6d28a0e0af2e188d2e17e08711023725c1e31931432ede687ebd0b5f8844039`.
  This exactly matches the independently audited candidate.
- GitHub workflow `31526335415` passed the full inspector, Heartbeat, Governor,
  reproducibility, and fresh-package installation checks on Windows Server 2022
  and the current Windows runner. Each runner extracted the exact ZIP, verified
  version 0.8.0 and the two-skill inventory, and executed packaged Heartbeat
  status successfully.
- The immutable GitHub release contains the ZIP, checksum, and per-file release
  manifest. Its publication job verified the signed tag and commit, created and
  verified the artifact attestation, published once, and verified the immutable
  release and every asset.
- A separate isolated installed-package canary verified silent normal cycles,
  Governor-only routing despite conflicting owner hints, duplicate suppression,
  stable EventId retry after newer evidence, acknowledgement, and one-shot
  resolution. No suspicious behavior was observed.
- The supported topology uses one dedicated Governor task, recommended on
  `gpt-5.6-luna` with Medium reasoning. Monitored tasks can use Luna, Terra, Sol,
  or mixed models. They do not run Heartbeats, receive direct Heartbeat wakes,
  or install recurrences. Deterministic collection invokes no model.
- Local installation from the refreshed public marketplace reports v0.8.0.
  All 11 release files match the release manifest; the CLI adds only its local
  `.gitignore` cache marker. Installed Heartbeat status returned
  `engine=healthy`, eight active detector types, and exit code 0.
- OpenAI Plugin Directory version 0.7.7 remains published. v0.8.0 has not been
  submitted to the Directory.

## v0.8.1 Candidate Evidence

- Candidate ZIP SHA-256:
  `e64552de2295b3658d7f60986c34492c1c1c3fe62351141abc4fe8a41e1be745`.
  The deterministic package contains 13 files.
- Local Windows PowerShell 5.1 validation passed the Inspector suite, Heartbeat
  suite, 42-scenario Governor suite, hardened supervision suite, and two-build
  reproducibility and installed-package suite.
- Supervision validation includes delayed lifecycle ordering, a live mutex held
  beyond the synchronous deadline, eight concurrent hook processes, rotating
  coverage of 17 active tasks, two-phase release, host-confirmed reactivation,
  corrupt and ambiguous JSON, DPAPI validation, and a full 256-record capacity
  fixture without eviction.
- An independent Pro design audit changed its verdict from `HOLD` to
  `SHIP-CONTINGENT-ON-EXTERNAL-CANARY`. It found no additional source or package
  blocker in the supplied evidence.
- A second Windows machine installed the earlier v0.8.1 candidate at commit
  `5d85799a60b4a805a8e9e97317aebe463c70f0f3`. Its manifest, two-skill
  inventory, eight installed skill-file hashes, and full validation suite
  passed. After valid Git metadata was initialized in place, Governor status
  resolved repository identity. Supervision was not enabled, so this proves
  installation and compatibility only; it is not the required autonomy canary
  for the refreshed candidate above.
- The first full external autonomy canary correctly failed closed. Direct
  affected-task delivery, target isolation, intervention coalescing, retry
  limits, stale-reply rejection, independent resolution, normal-cycle silence,
  and one-Governor recurrence containment passed. The packaged full Heartbeat
  suite then found a release-blocking test portability defect: its supposed
  outside-root state path was derived from the repository root, but a package
  extracted below `%TEMP%` is inside an approved state root. The test therefore
  observed `heartbeat_input_invalid` from its deliberately malformed input
  instead of the expected `heartbeat_state_path_invalid`. The candidate was
  withheld, the one Governor was preserved with its recurrence paused, and no
  worker or duplicate recurrence remained. The corrected suite uses a genuinely
  forbidden state path, asserts validation order separately, and runs against
  the built ZIP in CI.
- The canary's attempted report delivery to a development task absent from that
  host registry was definitely rejected. It correctly performed no retry and
  did not convert the transport failure into a user-relay request.
- A follow-up external packaged-suite confirmation checked signed commit
  `72c0a4911dc70e599b6b5da801864c4d65f961c7` and reproduced ZIP SHA-256
  `e64552de2295b3658d7f60986c34492c1c1c3fe62351141abc4fe8a41e1be745`.
  The complete Heartbeat suite passed against the extracted package. A
  forbidden state path returned `heartbeat_state_path_invalid`, including when
  paired with malformed input, which proves the corrected validation-order
  contract. Together with the earlier autonomy canary, this clears the external
  v0.8.1 validation gate.
- This entry is sanitized. It records no machine, user, workspace, repository,
  task, session, or account identifier.
- Signed candidate source is public on the `main` branch pending the release tag.
  An earlier local Codex marketplace candidate installed manifest v0.8.1 and
  passed one real headless lifecycle-hook invocation with no output. The final
  refreshed artifact above passed isolated installed-package validation and
  two-build reproducibility. The external autonomy and packaged-suite gates
  have now passed.
