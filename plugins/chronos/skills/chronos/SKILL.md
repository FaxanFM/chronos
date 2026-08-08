---
name: chronos
description: Detect and mitigate Codex process, CPU, memory, handle, disk, diagnostic SQLite log, and token-quota degradation on Windows. Use when Codex or the PC is lagging, when logs_2.sqlite is growing or writing heavily, when token or quota use seems disproportionate, when several tasks or goals have run for hours or days, or before and after long-running parallel work.
---

# Chronos

Keep this skill lean and on-demand. Do not create a scheduler, daemon, recurring automation, telemetry file, or persistent log.

Before running Chronos, resolve `<skill-root>` to the directory containing this `SKILL.md`. Do not assume the user's workspace is the skill directory and do not search the whole disk.

## Run an inspection

Inspect only when lag is reported, before extending an already long-running session, or when long-running parallel work finishes:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action inspect
```

Return only the compact `CHRONOS` summary unless details are requested. Do not paste raw process tables into the conversation.

The inspection opens only the exact Codex `logs_2.sqlite` database in read-only
mode. It reports database size, reclaimable freelist space, WAL activity,
sequence movement, and the aggregate TRACE percentage from up to 2,000 recent
rows. It never reads log bodies.

It also scans only the tail of recent, known Codex `sandbox*.log` files for two
exact filesystem-helper failure markers. It returns aggregate booleans and
never returns log text or paths.

For quota diagnostics, it reads at most 2 MiB from each of up to eight rollout
files modified in the last six hours. It retains only structured token-count,
turn-context, compaction, approval-state, and worker-call fields. It counts an
automatic review only when a `turn_context` record reports
`model=codex-auto-review`; similarly named bookkeeping records do not count as
reviews. It never returns raw rollout lines, prompts, responses, tool arguments,
tool output, identifiers, or paths. It reports aggregate parser-integrity,
reviewer, safe categorical approval, lineage, fork-context, and exact
cross-rollout duplication counters. Structured proposed-prefix arrays and
approval identifiers may be hashed in memory for repetition and state-transition
analysis. The inspector never returns prefixes, hashes, rule text, identifiers,
or credential-shaped values. Ephemeral hashes are discarded when the process
exits. Those counters do not alter health thresholds or scoring.

The same on-demand inspection reads up to 32 supported files only from the known
Codex rules directory. It returns aggregate rule structure and secret-shape
counts, never rules, commands, assignments, paths, hashes, or values. It does not
edit a rule.

Use `machineHealth` for process, memory, handle, CPU, and disk pressure. The
leading `CHRONOS` level remains an aggregate advisory across machine,
filesystem-helper, and diagnostic-database conditions; do not present that
aggregate as proof that the PC is failing when `machineHealth=HEALTHY`.

Read `tokenCoverageWindowHours`, eligible and selected file counts,
`tokenCoverageCapped`, truncated tails, and `tokenCoverageContinuity` before
interpreting numeric totals. `tokenSpawnObservation` and
`tokenCompactionObservation` distinguish observed events, a complete
not-observed result, partial coverage, unsupported event formats, and
unavailable data. A zero with `partial`, `unsupported`, or `unavailable` is not
evidence that the event never occurred.

`approvalReviewTurnsObserved`, `approvalReviewerSessionsObserved`, review rate,
interval, burst, confidence, parent-link, source, repeat-class, allowed/denied,
inspection-shaped, boundary-cause, and persistence fields
are bounded observations, not account-wide billing totals. Check
`approvalReviewObservation`, `approvalReviewCoverage`, and
`approvalRequestObservation` before interpreting them. `unsupported_schema` or
`observed_insufficient_structure` means the rollout did not expose enough safe
categorical data; do not infer a cause from model names or unstructured text.
`metricSource=local_rollout`, `dashboardEquivalence=unsupported`, and
`billingInference=unsupported` are hard semantic boundaries. The inspector is
diagnostic-only: it never changes reviewer models, approval modes, or trusted
command rules.

Interpret approval problem classes independently:

- `persistence_runaway` requires a structured `ALLOW`, unresolved pending
  state, and equivalent regenerated request, or an explicit persistence failure.
  Recommend repairing approval persistence before changing reviewer cost.
- `rule_miss_amplification` means a structured proposed prefix repeated after
  independently resolved reviews. Review the exact operation manually before
  considering one narrow, reversible rule.
- `legitimate_or_diverse_boundary_volume` means the available evidence does not
  prove either defect. Do not weaken the sandbox.

`reviewerEscalationsObserved` means reviewer-originated escalation traffic. Do
not call it reviewer recursion unless `approvalRecursionRisk=observed`, which
also requires directly observed nested reviewer lineage.

Use the Rule Governor fields separately. `rule_secret_exposure` requires removal
of credential material and rotation if it may remain valid, but never repeat the
value. `rule_brittleness_warning` identifies literals longer than 256 characters.
`broad_interpreter_rule` identifies interpreter-wide trust. Never create or
recommend broad PowerShell, shell, Python, Node, curl, network, filesystem-write,
or outside-workspace rules.

Use `approvalModesObserved`, `reviewerControlCapability`, and
`reviewerCompatibility` as a capability probe. `supported` means only that the
runtime explicitly reported configurability; it does not prove a compatible
lightweight reviewer is advertised. `unsupported` or `unavailable` must remain
diagnostic-only.

`rolloutSelectedMiB`, growth, projection, lineage, replay, and compaction fields
describe only the bounded selected files. Growth and 24-hour projection use
file-lifetime metadata and are estimates, as declared by
`rolloutGrowthObservation`. Exact cross-file duplicates are a replay signal, not
proof of billed-token duplication. `tokenInheritedSnapshots` and
`tokenLineageDeltaFiles` show exact ancestor deltas that were removed;
non-exact history is not inferred. `tokenUsageScope` means the token total is not
a usage invoice and must not be presented as one.

Use task-age, top-lineage review share, fork, effort, and spawn-origin fields as
bounded efficiency observations. For simple work with
`spawnContextAmplification=observed`, recommend `fork_turns="none"` or the
smallest sufficient positive history. `nestedAgentObservation=not_observed`
must not be described as recursive fan-out. Surface a configured/effective
reviewer difference as a possible mapping or policy layer, not automatically a
defect. Do not rewrite the primary reasoning default.

Interpret the result:

- `HEALTHY`: continue normally.
- `WARNING`: recommend reducing concurrency when convenient.
- `CRITICAL`: recommend saving active work and restarting Codex at a convenient
  checkpoint.

Every status is advisory. After reporting it, continue the user's requested
work unless the user independently asks to pause. Never use a Chronos status to
refuse, suspend, cancel, or stop a Codex task.

Interpret the filesystem-helper fields separately:

- `fsHelper=WARNING`: warn that the helper is degrading and recommend saving
  work before relying on more sandboxed file operations.
- `fsHelper=CRITICAL` with `pcRestartAdvised=true`: advise a full Windows
  restart at a convenient checkpoint after work is saved. Continue the task if
  the user chooses not to restart yet.

Treat `logDb=WARNING` or `logDb=CRITICAL` as a product-level diagnostic-log
churn condition. Explain that sequence counts demonstrate row churn, not exact
physical SSD writes or confirmed drive damage. Report `logDbReasons` and keep
`logDbPerformanceImpact=not_measured` separate from `machineHealth`.

Interpret `quotaRisk` separately from the overall machine-health status:

- `LOW`: no current aggregate quota-amplification signal.
- `ELEVATED`: call out the reported contributors and recommend a clean
  checkpoint soon.
- `HIGH`: recommend the relevant `tokenAdvice` actions before extending the
  task substantially. Continue the user's requested work.
- `UNAVAILABLE`: no recent compatible rollout aggregate was found.

Report `tokenQuotaContributors` whenever quota risk is elevated or high. These
tags identify the already-measured threshold clauses responsible for the
classification; they are explanatory and do not change scoring. `tokenAdvice`
may still be `none` when no supported remediation tag matches; use
`tokenAdviceReason` to explain that case.

Apply the `tokenAdvice` tags:

- `lower-effort`: use Medium for routine stages; reserve High, Extra High, Max,
  and Ultra for bounded work that benefits from them.
- `fresh-task`: at the next clean milestone, start a focused new task instead
  of continuing to resend a large context.
- `bound-subagents`: avoid Ultra when quota constrained. If agents are needed,
  use `fork_turns="none"` or the smallest useful positive count and prefer
  Medium reasoning.
- `avoid-repeat-compaction`: repeated compaction is itself model work; prefer a
  focused new task after preserving the required handoff.
- `cache-write-risk`: GPT-5.6 cache writes can be more expensive than uncached
  input. Chronos can expose the volume but cannot patch Codex request fields.

When automatic review is materially active, remove pathological review
regeneration first, then reduce avoidable tool calls, then inspect rule quality,
then bound task and worker amplification. Make unavoidable reviews cheaper only
after those causes are addressed. Try operations expected to be sandbox-safe
before escalating; request escalation only after a real boundary is identified.

Do not describe a high `tokenCachedReadPct` as a leak or as equivalent spend.
Cache reads indicate reuse and are discounted, but they still contribute to
token-throughput limits. Treat `tokenCacheWriteObserved=false` as "no writes
reported," not proof that no writes occurred.

When the user requests durable quota tuning, recommend this conservative
starting point but do not edit configuration without an explicit request:

```toml
tool_output_token_limit = 4000
model_auto_compact_token_limit_scope = "body_after_prefix"

[agents]
max_concurrent_threads_per_session = 2
default_subagent_reasoning_effort = "medium"
```

## Legacy actions

Older Chronos versions exposed `plan` and `cleanup` actions. They remain
accepted for command compatibility, but they are advisory-only:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action plan
```

`plan` reports only a candidate count. `cleanup`, including `cleanup -Force`,
is disabled and always stops zero processes. Do not attempt an alternative
process-termination command.

## Safety

- Never block, pause, or end a Codex task based on a Chronos result.
- Never terminate any process.
- Never delete logs, caches, worktrees, or user data.
- Never create SQLite triggers, delete rows, checkpoint, vacuum, or otherwise
  modify Codex databases.
- Never change Codex reviewer configuration, approval mode, trusted-command
  rules, model catalogs, or sandbox permissions.
- Never expose usernames, local paths, prompts, responses, tool arguments,
  tool output, environment values, or unrelated process details.

Chronos mitigates symptoms; it cannot patch an internal Codex lifecycle defect. Restarting Codex remains the reliable recovery when app-owned helpers or handles remain elevated.
