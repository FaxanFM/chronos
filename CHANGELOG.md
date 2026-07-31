# Changelog

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
