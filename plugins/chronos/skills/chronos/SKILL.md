---
name: chronos
description: Detect and mitigate Codex process, CPU, memory, handle, disk, diagnostic SQLite log, and token-quota degradation on Windows. Use when Codex or the PC is lagging, when logs_2.sqlite is growing or writing heavily, when token or quota use seems disproportionate, when several tasks or goals have run for hours or days, or before and after long-running parallel work.
---

# Chronos

Keep inspection and Heartbeat evaluation lean and on-demand. Do not create an
operating-system scheduler, daemon, service, telemetry file, or persistent log.
After normal Codex hook trust review, the plugin's four lifecycle hooks update a
bounded local supervision registry only when a task or subagent starts or ends.
They do not run on turns, tools, or prompts and return no model context. On
brief registry contention, a hook writes one bounded DPAPI-protected fallback
event; the next hook or Governor cycle merges and removes it.

## Supervision

`-Action supervise` exposes compact status and discovery for one host-managed
Governor task. Worker tasks do not invoke Chronos, run a recurrence, or receive
routine wakes. Their model choice is independent of Governor. The host should
reconcile an existing matching host recurrence, reuse a verified Governor, or
create one fresh task with no inherited history; never automatically fork a
working task. The default is at most one Governor turn per active hour or one
per six idle hours, with a 336-cycle or 14-day rotation bound. Host reconciliation
uses the complete scoped equivalence key returned by status, deterministic immutable-ID winner
ordering, at most three attempts, and the exact postcondition one live Governor,
one active recurrence, and zero active duplicates. Only Governor cycles zero and
one repeat the installation-scoped host convergence check; normal cycles do not rescan host
automations.

```powershell
"<skill-root>\scripts\chronos.cmd" -Action supervise -SupervisionAction status
```

Only the Governor task runs `-SupervisionAction initialize`, `reconcile-host`,
and `discover`. The `.cmd` launcher always applies the required noninteractive
Windows PowerShell 5.1 execution-policy flags.
Host task tools remain the authority for whether a task is live. The registry
is a privacy-bounded discovery hint, not a task transport or security boundary.
See the public [supervision contract](https://github.com/FaxanFM/chronos/blob/main/docs/SUPERVISION.md).

## Heartbeats

Heartbeat evaluation is an opt-in action of this installed Chronos skill, not a
separate product. A host-side collector supplies a privacy-safe normalized JSON
snapshot; Chronos persists compact transition and dedupe state, then routes only
meaningful changes to one Governor inbox. Monitored tasks can use any model and
do not run Heartbeats. The recommended host configuration is one Governor task
using `gpt-5.6-terra` with Medium reasoning. The host selects that model; Chronos
cannot change a task's model setting.

`OwningSolThread` is always `governor`. `Owner` and `Subject` are compact routing
hints, not authority by themselves. The native script never sends a message or
starts another task. The Codex-host Governor may use `send_message_to_thread`
for one fixed-template intervention after it verifies exactly one live affected
task. It never broadcasts or gives monitored tasks a recurrence. The host supplies collector coverage
and chooses when to invoke the action. The engine enforces its registered
minimum cadence for each observed family. Supply a stable
`sourceEpoch` and increasing `sourceSequence`; without continuity proof, Chronos
can open a condition but will not resolve one.

```powershell
"<skill-root>\scripts\chronos.cmd" -Action heartbeat -HeartbeatInputPath snapshot.json
```

Use `-HeartbeatStatePath` only for controlled test or host-managed state. The
default state is
`%TEMP%\Chronos\Heartbeat-v2\<scope-sha256>\heartbeat-state.json`.
Explicit state paths are accepted only beneath that versioned TEMP root or the
LocalAppData Heartbeat root.
Chronos imports readable prior state without modifying its source directory. If
the prior sandbox-owned directory is inaccessible, it starts safely in the new
namespace and reports that migration result in compact status.
Run the same action without an input path to show compact Heartbeat status.
After the host deduplicates and successfully delivers an event, pass its stable
ID with `-HeartbeatAcknowledgeEventId <event-id>`. Unacknowledged events remain
in a bounded local outbox and receive at most one retry after 15 minutes with the
same ID. `plan` and `fail-closed` consume actionable events atomically.
Use `-HeartbeatInspectorOutputPath` only with captured compact `CHRONOS` and
`CHRONOS EFFICIENCY` lines. See the public
[Heartbeat contract](https://github.com/FaxanFM/chronos/blob/main/docs/HEARTBEATS.md)
for the strict normalized input contract and coverage limits.

Only the dedicated Governor uses `-HeartbeatInterventionAction`. It must plan
all events before sending, keep one active intervention per target, recheck the
target generation before claiming a send, and use fixed returned instructions.
Transport acceptance is not task acknowledgement. A task response is not proof
of recovery; a later observed Heartbeat cycle or allowed independent host check
must verify the postcondition. Unknown delivery never retries. Definite failure
gets one retry. Governor/self-origin events never target the Governor.

Token volume is not price. Do not infer cost, quota impact, or efficiency from a
model name. Governor-origin `USAGE_BURN` remains Governor-local unless a second
same-subject, same-window event independently shows stall, review amplification,
or machine degradation. When it returns `GovernorLocalAction`, update only the
Governor recurrence, verify one active recurrence at the returned cadence, and
acknowledge the event only after that postcondition holds. Do not message a
monitored task or turn routine findings into user chores.

Before running Chronos, resolve `<skill-root>` to the directory containing this `SKILL.md`. Do not assume the user's workspace is the skill directory and do not search the whole disk.

## Run an inspection

Inspect only when lag is reported, before extending an already long-running session, or when long-running parallel work finishes:

```powershell
"<skill-root>\scripts\chronos.cmd" -Action inspect
```

Return only the compact `CHRONOS` summary unless details are requested. Do not paste raw process tables into the conversation.

The inspection opens only the exact Codex `logs_2.sqlite` database in logical
read-only mode. It does not change rows or schemas. SQLite can create or update
`-wal` or `-shm` coordination sidecars while opening a WAL-mode database, so
read `sqliteOpenMode`, `sqliteJournalMode`,
`sqliteSidecarMutationPossible`, and `sqliteSidecarMutationObserved`. It reports
database size, reclaimable freelist space, WAL activity, sequence movement, and
the aggregate TRACE percentage from up to 2,000 recent rows. It never reads log
bodies.

It also scans only the tail of recent, known Codex `sandbox*.log` files for two
exact filesystem-helper failure markers. It returns aggregate booleans and
never returns log text or paths.

For quota diagnostics, it streams at most 20,000 session inventory entries
under a three-second target, then reads at most 2 MiB from each of up to eight
rollout files modified in the last six hours. One filesystem call can exceed
the target. It retains only structured token-count,
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

Use `machineHealth` and the leading `CHRONOS` level for process, memory, handle,
CPU, disk, and filesystem-helper operability. Read `resourceDiagnosticLevel`
for the separate diagnostic-database condition and `overallDiagnosticLevel`
for the most severe observed diagnostic domain. Do not present storage or rule
hygiene as current machine failure when `machineHealth=HEALTHY`.

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
Current structured escalation calls are counted without returning commands,
justifications, tool output, call IDs, prefixes, or hashes. Read
`approvalRequestSchemas`, resolved/unresolved request counts,
`approvalResolutionObservation`, and latency sample fields together. A function
call output proves only that a request reached a terminal tool result; it does
not prove an allow or deny decision without an explicit structured decision.
`metricSource=local_rollout`, `dashboardEquivalence=unsupported`, and
`billingInference=unsupported` are hard semantic boundaries. The inspector is
diagnostic-only: it never changes reviewer models, approval modes, or trusted
command rules.

Interpret approval problem classes independently:

- `persistence_runaway` requires a structured `ALLOW`, unresolved pending
  state, and a later equivalent request. An explicit persistence failure is
  reported separately and does not by itself establish a runaway.
  Recommend repairing approval persistence before changing reviewer cost.
- `rule_miss_amplification` means one structural equivalence repeated across at
  least two independently resolved `ALLOW` reviews. Denied, unknown, mixed, or
  unresolved repetition is not a rule miss. Review the exact operation manually before
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
`ruleSecretCandidateOrdinals`, `ruleSecretCandidateClasses`, and
`ruleSecretConfidence` identify only the bounded local rule order and safe shape
category. Use an ordinal for local follow-up; never paste the rule or value.

`machineHealthContributors` names the unchanged threshold clauses that produced
the process diagnosis. `machineHealthConfidence=threshold_observation_only` and
`responsivenessObservation=not_measured` mean the result is resource pressure,
not a measured UI-latency or freeze prediction.

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
`tokenSelectedCumulativeInputM` retains the frozen cumulative heuristic input.
Use `tokenIntervalInputM` and the other `tokenInterval*` fields for the marginal
difference between comparable timestamped snapshots in the selected tails.
`rolloutProjectionComparable=false` or
`rolloutGrowthObservation=suppressed_partial_coverage` means no 24-hour
projection should be quoted. `quotaRiskBasis=frozen_selected_cumulative_heuristic`
confirms that this engineering release did not recalibrate scoring.

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
token-throughput limits. Interpret `cacheWriteObservation=unsupported_schema`
as unavailable telemetry. Only interpret `tokenCacheWriteObserved=false` as a
measured zero when `cacheWriteObservation=observed`; neither proves that no
upstream cache activity occurred.

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
"<skill-root>\scripts\chronos.cmd" -Action plan
```

`plan` reports only a candidate count. `cleanup`, including `cleanup -Force`,
is disabled and always stops zero processes. Do not attempt an alternative
process-termination command.

## Safety

- Never block, pause, or end a Codex task based on a Chronos result.
- This Inspector skill never terminates a process. Governor can stop only the
  bounded Git subprocess it started when fingerprinting exceeds its time or
  byte limit; it does not terminate Codex or unrelated user processes.
- Never delete logs, caches, worktrees, or user data.
- Never create SQLite triggers, delete rows, change schemas, checkpoint, or
  vacuum Codex databases. SQLite coordination-sidecar activity remains possible
  under the documented logical read-only connection.
- Never change Codex reviewer configuration, approval mode, trusted-command
  rules, model catalogs, or sandbox permissions.
- Never expose usernames, local paths, prompts, responses, tool arguments,
  tool output, environment values, or unrelated process details.

Chronos mitigates symptoms; it cannot patch an internal Codex lifecycle defect. Restarting Codex remains the reliable recovery when app-owned helpers or handles remain elevated.
