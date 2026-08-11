# Changelog

## v0.7.7

- Remove unrelated commercial material from the public and packaged product
  documentation.
- Add a deterministic release check that keeps product documentation focused
  on the local Chronos plugin.
- Describe diagnostic SQLite access as logical read-only, disclose possible
  `-wal` and `-shm` coordination-sidecar activity, and report the open mode,
  journal mode, possible mutation, and observed mutation.
- Parse Starlark `prefix_rule` named arguments and single, double, raw, triple,
  escaped, reordered, commented, and nested literal forms. Preserve pattern
  positions, nested command alternatives, raw Windows paths, decision semantics,
  arbitrary-code flags in any later position, option-only prefixes, and missing
  operands across nested alternative branches; fail partial instead of
  false-safe.
- Distinguish exact record duplicates, exact cross-schema approval mirrors, and
  later same-ID requests. Count stable-correlation pending retries after
  structured `ALLOW` outcomes.
- Require at least two structurally equivalent requests with separate explicit
  `ALLOW` decisions, terminal resolutions, and supported prefixes before
  suggesting a repeated permission-rule miss. Denied, unknown, inherited,
  prefix-unavailable, mixed, and unresolved repetitions do not produce it.
- Correct Governor `capacity_reserved`, known-decision allow-rate denominators,
  complete approval-resolution reporting, large-rollout head timestamps, V1
  `fork_context=false`, and missing V1 fork semantics.
- Stream rollout inventory under a 20,000-entry cap and three-second target,
  disclose cap results, and isolate process property races with partial-sample
  confidence.
- Bind delegated plans to a pre-spawn Git-visible workspace fingerprint and
  reject lease activation after an intervening mutation; isolate process races
  in the legacy advisory candidate path as well.
- Align the manifest publisher with Dravara, LLC and replace obsolete pending
  directory copy with the verified public listing and explicit unknown dates
  and regions.
- Expand Windows regressions for SQLite sidecars, structured rules, stable-ID
  approvals, safe rule-miss postconditions, V1 fork data, rollout head age,
  inventory bounds, process sampling, and plan reservation reporting.

No warning threshold, critical threshold, scoring weight, predictive claim,
telemetry behavior, background behavior, or read-only Governor policy changed.

## v0.7.6

- Publish the v0.7.4 engineering changes through GitHub's required
  draft-upload-publish flow for repositories with automatic immutable releases.
  v0.7.4 and v0.7.5 remain immutable source-only records; v0.7.6 is the first
  packaged release in this series. Runtime behavior is unchanged.

No diagnostic threshold, score, prediction, telemetry, background behavior, or
Governor policy changed.

## v0.7.5

- Repackage the v0.7.4 engineering changes under a new immutable release after
  the v0.7.4 GitHub release was locked before its external assets were attached.
  Runtime behavior is otherwise identical to v0.7.4.

No diagnostic threshold, score, prediction, telemetry, background behavior, or
Governor policy changed.

## v0.7.4

- Recognize current structured `function_call` escalation requests without
  returning commands, justifications, tool output, IDs, prefixes, or hashes.
  Correlate terminal tool results to bounded resolved/unresolved and latency
  aggregates without inferring allow or deny decisions.
- Add marginal token deltas between comparable timestamped tail snapshots while
  retaining the existing cumulative input only as the frozen heuristic basis.
- Suppress file-growth and 24-hour projections whenever rollout coverage is
  partial, capped, truncated, malformed, duplicated, unreadable, or out of order.
- Expose unchanged machine-threshold contributors and state explicitly that UI
  responsiveness is not measured. Add privacy-safe rule ordinals, shape classes,
  and remediation confidence without returning rule text or values.
- Add token-authenticated `cancel-plan`, separate expired from pending plans,
  report the active manifest version at runtime, and document the atomic
  single-write lease transition.
- Record successful v0.7.3 Governor status validation from a fresh task on an
  independent Windows installation.

No warning threshold, critical threshold, scoring weight, predictive claim,
telemetry, background behavior, or write-delegation policy changed.

## v0.7.3

- Reject parseable Governor state whose collections are not maps or whose
  revision is outside the non-negative signed 64-bit range, preventing schema
  drift and numeric overflow from collapsing into an opaque failure.
- Distinguish unreadable state, failed state reads, invalid JSON, and invalid
  state schemas while preserving the original file and failing closed.
- Add privacy-safe `failure_stage`, `exception_type`, and recovery metadata to
  otherwise unknown Governor errors without returning exception text, paths,
  state content, or identifiers.
- Document the upstream Codex behavior where an open task retains its old
  versioned skill locator after a plugin upgrade. Require a fresh task and
  prohibit copies or links that would run newer code under an older version.
- Add a sanitized public field-report ledger and deterministic regression cases
  for supported-version state corruption and revision overflow.

The independent canary's original v0.7.2 exception remains unclaimed until it
returns the hardened diagnostic result. No warning threshold, critical
threshold, scoring weight, predictive claim, telemetry, or background behavior
changed in this release.

## v0.7.2

- Prepare the skills-only package for OpenAI Plugin Directory review under the
  specific public name `Chronos for Codex` and the Developer Tools category.
- Remove the manifest screenshot field because Chronos has no plugin UI; the
  synthetic proof card remains a clearly labeled GitHub discovery asset.
- Describe Governor as advisory coordination of bounded read tasks rather than
  implying that it enforces worker filesystem permissions.
- Correct the privacy policy to describe bounded all-partition inventory for
  older tasks resumed within the current six-hour observation window.
- Add the official publisher prerequisites and the required five positive and
  three negative reviewer cases to the submission packet.

No runtime diagnostic, Governor, threshold, scoring, telemetry, or background
behavior changed in this release.

## v0.7.1

- Replace working-tree `git diff` fingerprints with bounded raw file reads and
  safe Git metadata primitives so configured clean, textconv, and external-diff
  processes cannot execute during Governor verification.
- Migrate Governor state to version 4 and quarantine every active version-3
  write plan or lease. Legacy write lifecycle actions cannot fingerprint,
  integrate, or merge; only an explicit coordinator release or retirement is
  allowed.
- Make partial SQLite, cache-write, rule-parser, rollout-head, spawn-schema, and
  process-ownership coverage explicit instead of treating incomplete evidence
  as fully healthy or supported.
- Detect structurally equivalent approval persistence retries across regenerated
  correlation IDs and deduplicate exact untimestamped rollout records.
- Enforce canonical-root containment for every inspector file reader, reject
  escaped reparse paths, and discover recently modified sessions across all
  date partitions within a bounded traversal budget without order truncation.
- Reserve concurrency for issued delegation plans and allow coordinator cleanup
  of expired verified read leases.
- Pin ordinary CI actions, test two Windows runner labels, parse PowerShell and
  JSON in pull requests, and enforce package file and byte limits before release
  content is materialized.
- Replace the legacy GitHub positioning, put install commands in the first
  README viewport, add sanitized 9:16 proof and social-preview assets, add a
  privacy-gated issue form, and prepare the OpenAI Plugin Directory submission
  packet.

No warning threshold, critical threshold, scoring weight, predictive claim, or
calibration-sensitive heuristic changed in this release.

## v0.7.0

- Disable shared-folder Governor write delegation and reject legacy write plans.
  Governor read workers are now described as advisory coordination, not a
  security boundary or verified read-only property.
- Emit the current Multi-Agent V2 `fork_turns=none` contract, remove the V1
  `fork_context` instruction, bind worker reuse to workspace and effort, enforce
  one active lease per worker ID, persist lease policy, and prevent terminal
  lifecycle rewrites.
- Sanitize every Governor-owned Git invocation against fsmonitor, textconv,
  external diff, hook, pager, trace, and environment execution surfaces; cap
  workspace fingerprint input.
- Parse bounded multiline permission rules, distinguish unreadable SQLite
  queries from healthy data, discover old sessions resumed recently, retain
  complete JSONL records without trailing newlines, deduplicate exact replayed
  events, and label unavailable cache-write telemetry instead of reporting zero.
- Separate machine health from resource and overall diagnostic levels, use an
  interval-based review rate, include prefix structure in approval equivalence,
  and distinguish a persistence write error from a proven persistence runaway.
- Package only tracked plugin files, add per-file release hashes, pin Actions,
  split unprivileged tests from publication, verify attestations before release
  creation, and add security, ownership, and dependency-maintenance files.
- Replace the manually asserted 100 percent security-coverage claim with an
  honest deterministic-scenario report. Warning/critical thresholds, scoring
  weights, and predictive claims remain frozen.

## v0.6.1

- Add an explicit approval-state persistence-runaway diagnosis that requires a
  structured `ALLOW`, an unresolved pending state, and an equivalent regenerated
  request; explicit persistence-write failures are counted separately.
- Add allowed/denied decision totals, allow rate, inspection-shaped pressure,
  boundary-cause categories, three-way approval-problem classification, and
  source, dashboard-equivalence, billing, duration, and confidence semantics.
- Add an on-demand Rule Governor for brittle monolithic rules, narrow reusable
  rules, overbroad interpreter rules, and credential-shaped rules. Rule text and
  credential values are never returned, persisted, or transmitted.
- Add reviewer-originated escalation, burst, nested-reviewer, configured versus
  effective reviewer, primary reasoning-default, task-age, dominant-lineage,
  `fork_turns`, worker-effort, inherited-turn, and root/child spawn observations.
- Reject a reported worker model that differs from the persisted Governor plan
  with the explicit `model_plan_mismatch` error at binding or result reporting.
- Add regressions for 590 review turns with 581 unresolved retries, 307 resolved
  repeated-prefix reviews, synthetic secret-shaped rules, inspection causes,
  reviewer escalations, full-history workers, root-only spawning, short-rate
  confidence, partial quota confidence, and exact/mismatched Governor leases.

Chronos remains advisory and does not alter approval state, reviewer settings,
permission rules, sandbox policy, or model configuration. Bounded fail-closed
handling after an approval persistence failure remains an upstream Codex runtime
requirement. No existing warning threshold, critical threshold, scoring weight,
quota heuristic, or predictive claim changed in this release.

## v0.6.0

- Add exact, schema-aware `codex-auto-review` turn counting that excludes
  similarly named bookkeeping records.
- Add reviewer-session, review-rate, reviewer-versus-primary aggregate, and
  review-coverage fields without exposing identifiers, prompts, commands, or
  raw rollout content.
- Add bounded rollout storage, explicitly estimated growth and projection,
  lineage counts, exact replay bytes, near-size clusters, and compaction
  duplication observations.
- Deduplicate exact inherited token snapshots by observed lineage delta while
  labeling non-exact totals as selected-rollout snapshots rather than billing.
- Classify structured approval sources and repeated request classes from safe
  categorical fields, with unavailable states when the schema is insufficient.
- Select a compatible worker by runtime-supplied cost rank only when ranking
  metadata is complete; otherwise preserve deterministic runtime order.
- Add 590-turn reviewer, approval-class, lineage-delta, privacy, ranked-model,
  and duplicate-compaction regressions.

No warning threshold, critical threshold, scoring weight, approval rule,
predictive claim, or calibration-sensitive behavior changed in this release.

## v0.5.4

- Move Governor runtime state out of Git metadata into a sandbox-writable,
  per-user location keyed by canonical repository identity.
- Make delegation plans persist normalized inputs and return short-lived,
  single-use tokens that leases consume after a native worker is created.
- Accept strictly validated canonical worker IDs, normalize comma-flattened
  scopes, and return explicit state-store and state-lock decisions.
- Add coverage-window, continuity, event-observation, machine-health, and quota
  contributor fields to diagnostic output so zeros and risk levels are
  explainable.
- Add Windows regressions for read-only Git metadata, preflight failures, plan
  token replay, canonical worker IDs, flattened scopes, and coverage semantics.

No warning threshold, critical threshold, scoring weight, predictive claim, or
calibration-sensitive behavior changed in this release.

## v0.5.3

- Require GitHub-verified cryptographic signatures on both the release commit
  and the signed annotated release tag.
- Upload every release asset to a draft before publishing it once under
  repository release immutability.
- Verify the published immutable release and each attached asset in the release
  workflow.
- Document the separate guarantees provided by signatures, artifact
  attestations, checksums, reproducible builds, and immutable releases.

No runtime behavior, warning threshold, critical threshold, scoring weight,
predictive claim, or calibration-sensitive behavior changed in this release.

## v0.5.2

- Discover and validate worker models from the active runtime inventory.
- Canonicalize repository and workspace identity across equivalent paths and
  linked Git worktrees.
- Add mutation-attributed writes, expiring fenced leases, renewal, owner-safe
  stale-lock recovery, and post-result content fingerprints.
- Fail closed for unverifiable same-folder writes, detached `HEAD`, reparse
  scopes, malformed state, and incompatible model inventories.
- Harden rollout parsing for malformed, partial, duplicate, and out-of-order
  records and eliminate substring-based filesystem-helper false positives.
- Add 100 percent critical safety-control coverage, real concurrent writer
  tests, reproducible packages, SHA-256 manifests, and GitHub artifact
  attestations.
- Document architecture, lease semantics, troubleshooting, calibration freeze,
  release verification, upgrade, and rollback.

No warning threshold, critical threshold, scoring weight, predictive claim, or
calibration-sensitive behavior changed in this release.
