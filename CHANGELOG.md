# Changelog

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
