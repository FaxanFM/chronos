---
name: chronos
description: Fully set up Chronos supervision and Heartbeats in one local Governor, or detect and mitigate Codex process, CPU, memory, handle, disk, diagnostic SQLite log, and token-quota degradation on Windows. Use for first-use setup, long-running task monitoring, Codex or PC lag, logs_2.sqlite growth, disproportionate token or quota use, and before or after long-running parallel work.
---

# Chronos

## Installation preflight

Run this lightweight check once when Chronos is first used in a task:

```powershell
& "<skill-root>\scripts\chronos.cmd" -Action install-status
```

The launcher is not guaranteed to be on `PATH`. Invoke every Chronos command by
the installed skill-root path shown here.

`sourceObservation=cache_inventory_not_enabled_state` means the result shows
valid cached package sources; cache presence alone does not prove that a source
is enabled. `sourceConflict=CONFIRMED` requires the running Directory package
and an enabled legacy Git configuration. If both cached sources exist but that
proof is absent, report `POSSIBLE` and inspect the plugin manager before making
changes. Explain that Codex treats the Git marketplace and Plugins Directory as
separate sources. Prefer `openai-curated-remote`. For a confirmed conflict,
with narrow user approval,
remove the legacy source through the Codex plugin manager, never by editing
configuration or cache files directly:

```powershell
codex.cmd plugin remove chronos@chronos
codex.cmd plugin marketplace remove chronos
```

Then fully quit and reopen Codex before starting a fresh task. An existing
process or task's loaded skill catalog cannot be hot-swapped. Do not remove the
legacy source when the Directory source is
absent, and do not imply that Chronos changed the active task catalog.

Keep inspection and Heartbeat evaluation lean and on-demand. Do not create an
operating-system scheduler, daemon, service, telemetry file, or persistent log.
When trusted and dispatched by Codex, the plugin's five monitoring hooks write
protected task, subagent, and completed-turn events to a bounded local inbox.
The next status or Governor cycle merges them into the supervision registry
under its mutex. It validates DPAPI identities inside the per-file boundary and
persists bounded slot-and-content receipts before deletion. It scans both
bounded inboxes before pruning receipts and defers temporarily unreadable files,
so one bad, locked, or queued file cannot block or replay supervision. Four request
asynchronous execution where supported; `SessionEnd` remains synchronous. They do not run on tools, commands, approvals, or prompts and
return no model context. Direct diagnostic hooks use the same protected event
format if registry contention prevents an immediate write. On Windows, each
definition uses a quote-free encoded launcher
because Codex passes the configured command through `cmd.exe`; the decoded
payload only resolves the installed plugin root and invokes the small intake
script. Do not rewrite it as a quoted `-File` command or route configured hooks
through the full supervision engine.

## Full setup request

When the user asks to set up Chronos fully, treat the request as an explicit
request to verify the installed source, run compact native status, and apply the
`chronos-governor` skill's Automatic Supervision Bootstrap. That bootstrap must
reuse or create one dedicated Governor, enable one host recurrence for
supervision and due Heartbeat evaluation, and verify zero worker recurrences.
This is a hard gate, not a best-effort sequence: the host must create or enable
no recurrence until initialization succeeds, supervision and Heartbeat status
are readable, one complete caller-aware inventory of current-host active tasks
accounts for the selected Governor exactly once, and the cycle returns
`recurrenceEligible=true`. Any
earlier failure must end with zero active current-key recurrences and no recovery
recurrence.
Before any Governor task creation, claim, or convergence attempt, inspect the
host task contract. It must return the complete current-host active set directly,
or expose a broader same-runtime snapshot with a proof that every active task is
included. A same-host `thread/loaded/list`-equivalent snapshot with authoritative
runtime status is sufficient. Chronos does not require enumeration of inactive or historical
tasks. A capped `list_threads` contract that does not guarantee all active tasks
is unsupported. Return exactly
`host_inventory_completeness_unsupported`, skip partial reconciliation, enforce
zero current-key recurrences, and do not retry until the host contract changes.
Stored identity enumeration is neither required nor sufficient. Every status
must come from the current host runtime. A separate `codex app-server` process
reports process-local `notLoaded` states and must return
`host_inventory_liveness_unsupported`, not a supported `cursor_snapshot`.
Do not stop after an inspection or return setup instructions for the user to
relay. Never bypass or auto-approve Codex hook trust. If hooks remain untrusted,
complete setup through authoritative host inventory without asking the user to
register tasks only when host capability preflight proves complete active-set
coverage.
Otherwise return `host_inventory_completeness_unsupported` with zero recurrence.
On a supported host, state only that optional hook acceleration is pending trust. An installed, active, or
trusted `/hooks` entry is configuration evidence, not proof that the command
executed. Read `hookExecutionObservation`, `hookRuns`, and `lastHookUtc` from
native supervision status. Report `not_observed` until a fresh post-trust
lifecycle or completed-turn event advances those fields. Keep one complete
current-host active inventory per Governor cycle as the task-discovery and
liveness authority on a supported host whether hooks execute or not. Hooks are
an optional accelerator only.
`hookRequiredForAutonomy=false` must remain true, and a non-dispatching host
must not make setup fail after complete active inventory and topology postconditions
pass.

Treat a nonempty `CODEX_HOME` as the installation boundary. Otherwise use the
current user's `.codex` directory. The native modules canonicalize and hash this
value; they never return the raw path. Invalid or inaccessible overrides fail
closed before state, claim, or recurrence eligibility can exist. Reject a
reparse point in any path component, including an ancestor junction. Consider
unscoped state from older releases only for the default `.codex` home; an
explicit or environment-provided home must not import it.
## Complete status request

When the user asks for a complete Chronos status, run the Inspector, supervision
status, and Heartbeat status. Present machine health separately from workflow,
quota, approval, rule, SQLite, and supervision conditions. A numeric zero is
not evidence of absence when coverage is partial, unsupported, outside the
window, or discontinuous; preserve those coverage labels. Report hook trust and
observed hook execution separately. This status-only request must not create a
Governor task, recurrence, worker, Heartbeat event, or task wake.
Heartbeat status without an input snapshot is prior-state inspection. Report its
`statusMode=prior_state` and its `evaluation` field as `observed`, `partial`, or
`unsupported`; do not call unsupported coverage healthy. A new partial or
unsupported family label replaces prior observed coverage and breaks continuity.

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
& "<skill-root>\scripts\chronos.cmd" -Action supervise -SupervisionAction status
```

Only the Governor task runs `-SupervisionAction initialize`, `cycle`,
`reconcile-host`, and `discover`. Every Governor recurrence must use `cycle`
with one fresh, host-proven complete current-host active inventory. Use
`active_snapshot` when the same host directly returns every active task and its
runtime status. A capped task list that does not guarantee the full active set is
an unsupported bootstrap capability. Do not create a fabricated partial
inventory or repeatedly call `reconcile-host`; stop with
`host_inventory_completeness_unsupported` and
zero current-key recurrences. A stored identity list without current-host
runtime status stops with `host_inventory_liveness_unsupported` under the same
zero-recurrence rule. `reconcile-host` is retained only for bounded
diagnostic use with an independently supplied partial inventory. From the
authoritative current host, `idle`, `ready`, and `notLoaded` normalize to
`inactive` and are not governed. `systemError` is also non-active and normalizes
to `inactive`. Schema v1 requires the Governor in the
raw list. Schema v2 may declare `callerVisibility=excluded_by_host`, omit only
the current Governor, and let the same cycle account for that registry-verified
caller without a second host query. Passive `discover` does not increment
the Governor cycle counter. The `.cmd` launcher always applies the required noninteractive
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
minimum cadence for each observed family. First run `-HeartbeatCollectorAction
reserve`, then copy its native, restart-persistent `sourceEpoch` and
`sourceSequence` into one snapshot. Never invent or locally increment them;
without continuity proof, Chronos
can open a condition but will not resolve one. Governor-generated snapshots use
schema v2 and include all eight public family coverage labels. Every accepted
schema-v2 snapshot advances the source watermark before family cadence is
checked, including partial, unsupported, and cadence-skipped snapshots. Host inventory is
the liveness authority, but it is not a substitute for this collector snapshot.

```powershell
& "<skill-root>\scripts\chronos.cmd" -Action heartbeat -HeartbeatInputPath snapshot.json
```

Use `-HeartbeatStatePath` only for controlled test or host-managed state. The
default state is
`%TEMP%\Chronos\Heartbeat-v2\<scope-sha256>\heartbeat-state.json`.
Explicit state paths are accepted only beneath that versioned TEMP root or the
LocalAppData Heartbeat root.
Chronos imports readable prior state without modifying its source directory. If
the prior sandbox-owned directory is inaccessible, it starts safely in the new
namespace and reports that migration result in compact status.
`priorStateDisposition=unavailable_preserved` and
`priorStateWriteAttempted=false` mean Chronos made no write or ownership-change
attempt against that prior state; they do not claim access to protected data.
Run the same action without an input path to show compact Heartbeat status.
After the host deduplicates and successfully delivers an event, pass its stable
ID with `-HeartbeatAcknowledgeEventId <event-id>`. Unacknowledged events remain
in a bounded local outbox and receive at most one retry after 15 minutes with the
same ID. `plan` and `fail-closed` consume actionable events atomically.
Use `-HeartbeatInspectorOutputPath` only with captured compact `CHRONOS` and
`CHRONOS EFFICIENCY` lines from a policy-authorized Inspector run. Pass
`-HeartbeatInspectorAuthorized` with the schema-v2 companion snapshot. The
adapter rejects missing, incompatible, or stale provenance. See the public
[Heartbeat contract](https://github.com/FaxanFM/chronos/blob/main/docs/HEARTBEATS.md)
for the strict normalized input contract and coverage limits. Complete Guardian
coverage also requires every required Inspector metric to parse and pass its
range check. Malformed complete evidence fails closed; it is never converted to
an observed result or a zero.

Only the dedicated Governor uses `-HeartbeatInterventionAction`. It must plan
all events before sending, keep one active intervention per target generation, recheck the
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
& "<skill-root>\scripts\chronos.cmd" -Action inspect
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
& "<skill-root>\scripts\chronos.cmd" -Action plan
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
