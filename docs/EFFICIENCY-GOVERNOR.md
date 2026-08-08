# Efficiency Governor

Chronos 0.6.0 adds bounded, local observations for Codex approval-review and
rollout amplification. It is an observer and advisor, not an approval-policy
manager.

## What It Measures

During an on-demand inspection, Chronos reads at most 2 MiB from each of up to
eight rollout files modified in the last six hours. It retains only structured
aggregate fields.

- `approvalReviewTurnsObserved` counts only `turn_context` records whose model
  is exactly `codex-auto-review`.
- `approvalReviewerSessionsObserved` counts selected rollout files containing
  at least one such record. It does not expose session IDs.
- `approvalReviewsPerHour` is calculated only when at least two timestamped
  observed review turns are available.
- `approvalAverageIntervalSeconds`, `approvalPeakPerMinute`, and
  `approvalConcurrentPeak` describe the selected reviewer intervals.
- `approvalParentLinksObserved`, `rolloutLineageLinksObserved`, and
  `rolloutForkFilesObserved` are counts only; Chronos never returns thread IDs.
- `approvalReviewerInputM`, `approvalPrimaryInputM`, and
  `approvalReviewerMainInputRatio` use the greatest valid selected-rollout
  snapshots after exact observed ancestor deltas. They are not account billing
  or a savings estimate.
- `approvalRequestsObserved`, `approvalUniqueClasses`,
  `approvalRepeatedRequests`, and `approvalSources` are emitted only from
  whitelisted categorical request fields. Chronos does not read command text to
  create a class.
- `approvalDeniedObserved` is emitted only from a structured response record.
- `rolloutSelectedMiB` describes the selected files.
- `rolloutGrowthMiBPerHour` and `rolloutProjected24hMiB` are file-lifetime
  metadata estimates, explicitly labeled by `rolloutGrowthObservation`. They
  are not persisted time-series measurements.
- `rolloutCrossFileDuplicateRecords` and
  `rolloutCrossFileDuplicateCompactions` report exact matching structured
  records across different selected files. Duplicate bytes, replay percentage,
  unique compactions, and duplicated-compaction bytes are also reported. They
  are replay signals, not proof of duplicate billed usage.
- `tokenInheritedSnapshots` and `tokenLineageDeltaFiles` show when an exact
  copied ancestor snapshot was observed and removed from the child's cumulative
  total. Non-exact lineage is never guessed.

Every interpretation must consider the coverage fields. A partial tail, capped
selection, unreadable file, malformed record, or out-of-order record means the
observation is incomplete.

## What It Does Not Infer

Chronos reports `approvalRequestObservation=unsupported_schema` unless the
runtime exposes structured request-level approval data. If a request exists but
lacks enough safe categorical fields, it reports
`observed_insufficient_structure`. It does not guess an approval cause from
command text, model names, or the number of reviews.

It also does not infer account billing, future token savings, reviewer
compatibility, a Luna override, identifiable session lineage, or non-exact
copied history from file size alone. It reports sanitized Codex-version and
provider labels only when they are present and match a strict categorical form.
`approvalModesObserved`, `reviewerControlCapability`, and
`reviewerCompatibility` report only structured runtime metadata; unavailable
metadata remains unavailable.

Governor can consume optional runtime-supplied numeric cost ranks. It selects
the lowest compatible rank only when every compatible advertised model is
ranked. Otherwise it preserves runtime inventory order. A model name, including
Luna, is never treated as proof of cost or compatibility.

## Safe Response Order

1. Reduce repeated, avoidable tool calls in the active task.
2. Review the exact repeated operation and, only with explicit user approval,
   consider one narrow, reversible permission rule.
3. Use a lighter reviewer only when the active Codex runtime exposes a supported
   configuration mechanism and advertises it as compatible.
4. Leave low-volume, varied, or security-sensitive review activity unchanged.

Chronos never creates trusted rules, changes reviewer models, patches Codex,
modifies sandbox permissions, or edits model catalogs. Broad approvals for
PowerShell, shell interpreters, arbitrary paths, network access, or filesystem
writes are never a recommended remediation.

## Validation Boundary

The diagnostics test suite includes a regression fixture with 590
`turn_context` reviewer records plus 589 similarly named bookkeeping records.
The required result is 590 observed review turns. It also checks sanitized
approval classes and denial records, parent-link counts, exact cross-rollout
duplicates, duplicated compactions, exact ancestor-token deltas, and ranked and
unranked runtime model selection. Thresholds, scoring weights, predictive
claims, and calibration-sensitive behavior remain unchanged in 0.6.0.
