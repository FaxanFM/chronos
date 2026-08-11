# Efficiency Governor

Chronos 0.7.7 provides bounded, local observations for Codex approval review,
permission-rule quality, worker context, and rollout amplification. It is an
observer and advisor, not an approval-policy manager.

## What It Measures

During an on-demand inspection, Chronos reads at most 2 MiB from each of up to
eight rollout files selected by modification time in the last six hours. It retains only structured
aggregate fields.

- `approvalReviewTurnsObserved` counts only `turn_context` records whose model
  is exactly `codex-auto-review`.
- `approvalReviewerSessionsObserved` counts selected rollout files containing
  at least one such record. It does not expose session IDs.
- `approvalReviewsPerHour` is normalized only when at least two timestamped
  review turns are available. `approvalObservationSeconds`,
  `approvalRateNormalized`, and `approvalRateConfidence` prevent a short burst
  from being presented as a stable hourly rate.
- Average and median interval, peak and p95 reviews per minute, consecutive
  active minutes, and concurrent reviewer sessions describe bursts separately.
- `approvalParentLinksObserved`, `rolloutLineageLinksObserved`, and
  `rolloutForkFilesObserved` are counts only; Chronos never returns thread IDs.
- `approvalReviewerInputM`, `approvalPrimaryInputM`, and
  `approvalReviewerMainInputRatio` use the greatest valid selected-rollout
  snapshots after exact observed ancestor deltas. They are not account billing
  or a savings estimate.
- Allowed, denied, and unknown decisions, known-decision allow percentage,
  inspection-shaped requests,
  boundary causes, repeated prefix counts, and source classes require supported
  structured fields. `metricSource=local_rollout`,
  `dashboardEquivalence=unsupported`, and `billingInference=unsupported` keep
  local activity distinct from dashboard turns and account billing.
- Current `response_item/function_call` escalations are recognized only when a
  structured categorical permission says `require_escalated`. Terminal tool
  results provide resolved/unresolved and bounded latency aggregates; they do
  not imply allow or deny without a structured decision record. Commands,
  justifications, tool output, call IDs, prefixes, and hashes are never returned.
- `approval_state_persistence_runaway` requires an allowed request to remain
  pending and later repeat with the same ephemeral correlation or structural
  equivalence. Exact records and exact same-time cross-schema mirrors are
  deduplicated separately. An explicit persistence write error is a separate
  diagnosis. High review volume alone is not this defect.
- `repeated_rule_miss_candidate` requires at least two structurally equivalent,
  independently resolved allowed reviews without persistence-runaway evidence.
  Each request must contain its own explicit structured `ALLOW`, a terminal
  resolution, and a supported prefix fingerprint. Decisions are never inherited
  by later requests. Denied, unknown, mixed, prefix-unavailable, and unresolved
  volume cannot produce this advice. It remains an advisor, not proof that the
  original boundary was unnecessary.
- Reviewer tool calls and `require_escalated` traffic are counted separately.
  `approvalRecursionRisk=observed` requires both an escalation and directly
  observed nested reviewer lineage; escalation alone is not called recursion.
- `rolloutSelectedMiB` describes the selected files.
- `rolloutGrowthMiBPerHour` and `rolloutProjected24hMiB` are file-lifetime
  metadata estimates, explicitly labeled by `rolloutGrowthObservation`. They
  are not persisted time-series measurements and are suppressed whenever
  selected coverage is partial.
- `tokenSelectedCumulativeInputM` retains the existing frozen heuristic basis.
  `tokenInterval*` reports marginal deltas only between comparable timestamped
  snapshots in selected tails. Neither is billing telemetry.
- `rolloutCrossFileDuplicateRecords` and
  `rolloutCrossFileDuplicateCompactions` report exact matching structured
  records across different selected files. Duplicate bytes, replay percentage,
  unique compactions, and duplicated-compaction bytes are also reported. They
  are replay signals, not proof of duplicate billed usage.
- `tokenInheritedSnapshots` and `tokenLineageDeltaFiles` show when an exact
  copied ancestor snapshot was observed and removed from the child's cumulative
  total. Non-exact lineage is never guessed.
- Spawn diagnostics distinguish explicit `fork_turns=all`, V1 or V2 `none`,
  bounded history, unknown or malformed context, worker effort, inherited turns, and root versus child
  origin. Context amplification is reported only when a structured low/simple
  task label is paired with full-history delegation.
- Task age and top-one/top-three reviewer concentration are derived from the
  selected lineage graph. They do not identify the task or claim account-wide
  completeness.

## Rule Governor

Chronos inspects supported files only in the known Codex rules directory and
returns aggregate rule health:

The bounded parser reads named Starlark arguments and preserves top-level
`pattern` positions and nested command alternatives across single, double, raw,
triple, escaped, reordered, and commented literal forms. Raw Windows
backslashes remain intact. A parse failure is partial coverage, not a safe rule.

- literals longer than 256 characters are `rule_brittleness_warning`;
- interpreter-only PowerShell, Cmd, POSIX shell, WSL, Python, Node, script-host,
  or curl allow rules are `broad_interpreter_rule`; arbitrary-code prefixes such
  as PowerShell `-Command`, shell `-c`, and Cmd `/c` receive the same diagnosis,
  including when the command position contains alternatives or ordinary options
  appear before the execution flag. Option-only prefixes and operand-taking
  forms such as PowerShell `-File` without a fixed operand are also broad. A
  nested-alternative position counts as a fixed operand only when every branch
  supplies one;
- constrained forms such as an interpreter alternative followed by `-File` and
  a fixed script remain distinguishable, and prompt or forbidden decisions are
  not described as broad trust;
- credential-shaped assignments or token forms are `rule_secret_exposure`;
- other bounded rules are counted as reusable narrow candidates.

Rule text, prefixes, environment assignments, and credential values are never
returned. A credential-shaped result should lead the user to remove the value
from the rule and rotate it if it may still be valid. Chronos never performs
either action automatically.
Bounded rule ordinals, safe shape classes, and confidence make the finding
locally actionable without returning paths, rule text, fingerprints, or values.

Every interpretation must consider the coverage fields. A partial tail, capped
selection, unreadable file, malformed record, or out-of-order record means the
observation is incomplete.

## What It Does Not Infer

Chronos reports `approvalRequestObservation=unsupported_schema` unless the
runtime exposes a supported structured request shape. If a request exists but
lacks enough safe categorical fields, it reports
`observed_insufficient_structure`. It does not guess an approval cause from
command text, model names, or the number of reviews. It may hash a structured
proposed-prefix array in memory and derive an allowlisted operation class, but
it never returns that prefix or hash.

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

1. Repair an observed approval-state persistence runaway or write failure before optimizing the
   reviewer model or permission rule.
2. Reduce repeated, avoidable tool calls and try an expected sandbox-safe
   operation before requesting escalation.
3. Review the exact repeated operation and, only with explicit user approval,
   consider one narrow, reversible permission rule.
4. Checkpoint long lineages and use `fork_turns=none` or the minimum required
   bounded history for simple workers.
5. Use a lighter reviewer only when the active Codex runtime exposes a supported
   configuration mechanism and advertises it as compatible.
6. Leave low-volume, varied, or security-sensitive review activity unchanged.

Chronos never creates trusted rules, changes reviewer models, patches Codex,
modifies sandbox permissions, or edits model catalogs. Broad approvals for
PowerShell, shell interpreters, arbitrary paths, network access, or filesystem
writes are never a recommended remediation.

## Validation Boundary

The diagnostics suite includes 590 exact reviewer turns with 581 unresolved
allowed retries, 307 independently resolved reviews of one structured prefix,
synthetic brittle and secret-shaped rules, inspection causes, reviewer
escalations, full-history worker delegation, and root-only negative recursion.
Governor rejects planned/effective model drift with `model_plan_mismatch` while
preserving an exact-model lease. Existing thresholds, scoring weights, quota
heuristics, predictive claims, and calibration-sensitive behavior remain
unchanged in 0.7.1.
