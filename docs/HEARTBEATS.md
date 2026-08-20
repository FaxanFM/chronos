# Chronos Heartbeats

Chronos Heartbeats is an opt-in action of the existing `chronos` skill. It is a
deterministic transition engine for long-running or asynchronous Codex work.
It is not a third skill, scheduler, service, model client, task transport, or
telemetry system.

The Codex host or another user-controlled collector supplies a bounded JSON
snapshot. Chronos validates the snapshot, evaluates only due collectors with
`observed` coverage, compares the values with compact local state, and emits a
structured event only when an actionable condition appears, resolves, or moves
to a higher severity. A normal cycle has no output.

## Supported topology

Run one host recurrence in a dedicated Governor task. That recurrence collects
one normalized snapshot across the monitored task set and invokes Heartbeats
once. Do not install or invoke Heartbeats inside every monitored task. The
default supervision schedule is one Governor turn per active hour or per six
idle hours, at most 24 or four turns per day. The host rotates or pauses the
Governor after 336 cycles or 14 days so recurring context cannot grow without a
bound.

The normal first-use request enables supervision and Heartbeats together:

```text
Set up Chronos fully on this PC. Verify the installed source, enable
supervision and Heartbeats in one dedicated Governor, and confirm one Governor
recurrence with zero worker recurrences. Keep routine worker tasks passive and
do not ask me to relay routine findings.
```

Do not create a separate Heartbeat task or recurrence. A complete setup result
must show readable Heartbeat status from the Governor and zero worker
recurrences.

The optional reviewed lifecycle hooks provide a passive candidate list when a
task or subagent starts or ends. The Governor reconciles that registry with
host task status before collection. The registry does not supply progress,
quota, test, Git, or machine evidence and cannot prove liveness. Worker tasks
need no prompt or recurrence. See [Supervision](SUPERVISION.md).

Monitored tasks can use different models and reasoning levels. The recommended
Governor configuration is `gpt-5.6-terra` with Medium reasoning when the host
advertises it. Field validation found that the Governor needs reliable tool use
and recovery judgment more than minimum model cost. The host must select this
setting. Chronos cannot select or enforce a task model. Chronos does not infer
price, quota impact, or efficiency from a model name.

## Command surface

Run a normalized cycle:

```powershell
"<skill-root>\scripts\chronos.cmd" -Action heartbeat -HeartbeatInputPath snapshot.json
```

Add a captured compact Inspector result when available:

```powershell
"<skill-root>\scripts\chronos.cmd" -Action heartbeat -HeartbeatInputPath snapshot.json -HeartbeatInspectorOutputPath inspector.txt
```

Show local Heartbeat status without running a collector:

```powershell
"<skill-root>\scripts\chronos.cmd" -Action heartbeat
```

After the host successfully deduplicates and delivers an event, acknowledge its
stable `EventId`:

```powershell
"<skill-root>\scripts\chronos.cmd" -Action heartbeat -HeartbeatAcknowledgeEventId <sha256-event-id>
```

The Inspector adapter accepts only compact lines beginning with `CHRONOS ` or
`CHRONOS EFFICIENCY `. It maps recognized review fields to Guardian input. It
marks token-window and local-version fields as partial because those fields do
not prove progress, account billing, fleet state, or installation intent. An
Inspector-only cycle has no source epoch or sequence, so it can open an absolute
Guardian condition but cannot resolve an existing condition. Supply a companion
normalized JSON snapshot when continuity is required.

## Host responsibilities

The host is responsible for:

- Creating the recurrence after the user asks for it.
- Reconciling one matching recurrence, stopping duplicates, and verifying the
  target task before setup succeeds.
- Collecting the normalized fields that the runtime exposes.
- Assigning privacy-safe opaque IDs and ownership hints.
- Running one Governor task for the monitored task set.
- Selecting `gpt-5.6-terra` with Medium reasoning for that Governor when available.
- Listing the scoped host tasks once per cycle and reconciling a bounded,
  privacy-safe inventory before it waits on the returned rotating batch.
- Delivering emitted events to the Governor inbox.
- Resolving one exact live target, coalescing events by target, and using the
  bounded intervention state machine before task delivery.
- Recording transport certainty, a categorical task response, and independent
  postcondition evidence.
- Rotating or pausing at the reported cycle or age bound and stopping the
  recurrence before local release.

The native PowerShell code does not contact another task.
`OwningSolThread` is always `governor`. The Codex-host Governor uses host task
tools to send one bounded intervention to the exact verified affected task.
`Owner`, `Subject`, and supplied task IDs are routing evidence, not authority by
themselves. Chronos never returns a broadcast route or wakes every monitored
task.

The deterministic cycle does not use model tokens. Monitored tasks can use
Luna, Terra, Sol, or a mix. The recommended host configuration is one Governor
task using `gpt-5.6-terra` with Medium reasoning when available. The host, not
Chronos, selects the model and reasoning effort. Chronos does not call a model,
change a task model, or treat a model label as trusted cost metadata.

## Top-level input

The input is JSON object schema version `1`. Chronos rejects duplicate or
case-colliding JSON keys before Windows PowerShell deserializes them. Unknown
fields, wrong types, secret-shaped keys or values, Windows or Unix
absolute-path-shaped identifiers,
oversized collections, invalid UTF-8, excessive nesting, and reparse-point
input paths fail closed.

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | Optional. The accepted value is `1`. |
| `capturedAtUtc` | ISO 8601 string | Collector timestamp. Out-of-order evidence is not evaluated and cannot block a due outbox retry. |
| `sourceEpoch` | opaque ID | Stable collector-process or source epoch. Required to prove continuity for resolution. |
| `sourceSequence` | integer | Monotonic sequence within `sourceEpoch`. Reuse or rollback fails closed. |
| `runId` | opaque ID | Optional. Repeated IDs are suppressed across processes. |
| `origin` | enum | `host`, `inspector`, `test`, `heartbeat`, or `heartbeat_notification`. Heartbeat-generated origins are ignored. |
| `collectorCoverage` | object | Per-family `observed`, `partial`, or `unsupported` labels. |
| `forceCadence` | Boolean | Explicitly bypasses cadence and backoff. Intended for controlled runs and tests. |
| `allowMachineDrift` | Boolean | Suppresses only fleet-wide identity comparison. Per-machine intended-state mismatches still apply. |

The allowed collector keys are `agents`, `guardian`, `usage`, `sessions`,
`tests`, `machines`, `tasks`, `git`, `build`, and `heartbeatActivity`.

`heartbeatActivity` accepts `schedulerDuplicates`, the legacy
`runtimeSeconds`, and the preferred `runtimeMilliseconds` plus
`runtimeBudgetMilliseconds`. The host must report its actual bounded cycle
budget when it has one. Chronos does not infer a smaller budget from elapsed
time.

## Coverage

Coverage is a control, not a display label.

- `observed`: Chronos can evaluate, update the previous-state baseline, or open
  a condition. Resolution also requires the `sourceEpoch` that originally
  opened that condition, a higher `sourceSequence`, monotonic counters where
  applicable, and fresh evidence for the same entity and detector reason. A
  replacement collector epoch can rebaseline but cannot close the old episode.
- `partial`: Chronos records the attempt and coverage label. It does not alert,
  replace the prior observed baseline, or resolve an open condition.
- `unsupported`: The runtime or collector does not expose the required data.
  Chronos does not convert this state to zero or healthy.

A supplied family without a matching coverage field is `unsupported`.

## Collector contract

IDs are opaque labels. Canonical Codex worker IDs under `/root`, such as
`/root/reviewer`, are accepted. Other slash-rooted values are rejected. Raw
prompts, commands, tool output, source, diffs, credentials, usernames,
secret-shaped values, and absolute paths are not accepted collector fields.

### Agent stall

Required per record: `id`, `active`.

Supported fields: `generation`, `owner`, `ownerGeneration`, `owningSolThread`, `progressHash`, `lastToolHash`,
`lastCommandHash`, `lastFileChangeUtc`, `lastGitHash`, `lastTestHash`,
`repeatedEquivalentActions`, `minutesSinceMeaningfulChange`,
`tokensSinceMeaningfulChange`, `totalTokens`, `longRunningOperation`,
`operationClass`, and `status`.

Chronos compares the progress digest and token counter with the prior observed
record. Elapsed time alone is insufficient. A declared long-running operation
is excluded. Repetition or token growth without a progress delta opens a stall.

### Guardian and automatic review

Required: `reviewerSessionId`.

Supported fields: `parentThreadId`, `owner`, `owningSolThread`,
`reviewerModel`, `reviewCount`, `reviewsPerMinute`, `reviewsPerHour`,
`averageReviewIntervalSeconds`, `reviewerTokens`, `mainTokens`,
`reviewerUsageRatio`, `reviewerTurnShare`, `equivalentApprovalRequests`,
`approvalExecutionCount`, `allowedPendingPostconditionCount`,
`reviewAcceleration`, `reviewerRecursion`, and `progressHash`.

The detector uses review and equivalent-request deltas, velocity, share, and
postconditions. An allowed request that remains pending is actionable even when
the volume is small. Chronos does not change approval state or permission rules.

### Usage burn

Supported fields: `owner`, `dominantThread`, `owningSolThread`, `role`,
`totalTokens`, `windowTokens`, `windowMinutes`, `ratePerMinute`,
`baselineRatePerMinute`, `projectedExhaustionMinutes`, `reviewerShare`,
`meaningfulProgress`, `progressHash`, `completedCycles`, `stateChanges`,
`acknowledgedEvents`, `failedCycles`, and `duplicateRuns`.

High usage with progress does not alert. The detector requires abnormal
velocity or a materially earlier exhaustion projection and uses the supplied
progress signal. These values are operational observations, not account
billing totals. A Governor comparison requires the same five supervision
counters in both samples. Completed cycles, state changes, and acknowledged
events count as progress even when the repository did not change. Missing or
non-comparable Governor counters remain unsupported instead of producing a
false high-usage diagnosis.

The Governor obtains those counters from compact `chronos.cmd -Action
heartbeat` status: `completedCycles`, `stateChanges`, `acknowledgedEvents`,
`failedCycles`, and `duplicateRuns`. It copies them exactly into the normalized
usage record and combines them with the current compact Inspector usage fields.
It does not maintain a separate counter ledger or substitute zero for a missing
field.

### Session and context growth

Required per record: `id`.

Supported fields: `parentId`, `owner`, `owningSolThread`, `childCount`,
`forkDepth`, `contextOverlap`, `compactionCount`, `rolloutBytes`,
`storageGrowthBytesPerHour`, `childCreationRate`, `recursive`, and
`progressHash`.

The detector requires combined fork-count, depth, overlap, recursion, or growth
evidence. A child count by itself is not a session-explosion diagnosis.

### Test state

Required per record: `name`, `status`.

Supported fields: `generation`, `owner`, `ownerGeneration`, `owningSolThread`, `commit`, `repairAttempts`,
`failureCount`, `required`, `ran`, `environmentStatuses`, and `buildId`.

Chronos persists whether a regression became active. A known failing baseline
does not become a new regression. A persisted pass-to-fail transition does.
Unchanged failures are deduplicated. Additional failed repair attempts can
increase severity. Environment disagreement and missing required validation
use separate condition keys. Regression and recovery require the same task
generation, environment identity, and suite identity.

### Machine and installation drift

Required per record: `id`.

Supported fields: `owner`, `owningSolThread`, `role`, `version`, `commit`,
`pluginVersion`, `marketplaceVersion`, `manifestVersion`, `skills`,
`missingSkills`, `mcpConfigured`, `testStatus`, `installStatus`,
`intendedVersion`, and `intendedCommit`.

Per-machine intended-state mismatches retain that machine's owner as a triage
hint and route to Governor. A fleet-wide comparison is separate and can be
disabled when version differences are intentional.

### Task dependency and zombie work

Required per record: `id`, `status`.

Supported fields: `generation`, `owner`, `ownerGeneration`, `owningSolThread`, `dependsOn`,
`dependencyStatus`, `ageHours`, `requiredCommit`, `requiredPush`,
`requiredValidation`, `validationStatus`, `acknowledgedBug`, `assigned`, and
`updatedAt`.

The actionable-task detector requires a persisted dependency transition from
incomplete to complete. A first snapshot that already says complete does not
wake an owner. Unassigned old work and incomplete release handoffs use separate
conditions. When the host provides `generation`, a reused task ID starts a new
condition identity and cannot resolve or coalesce the prior generation. For an
owner-targeted intervention, `ownerGeneration` identifies the owner's live host
generation separately from the child or test record's `generation`. If subject
generation is known but the distinct owner's generation is not, planning fails
closed until host discovery supplies it. A newly supplied or rotated owner
generation re-arms the open condition, replaces its stale pending Governor
envelope, and receives a new event identity. It does not send to the monitored
task until the replacement plan validates the target and generation.

### Git and build state

Git fields: `owner`, `owningSolThread`, `dirty`, `completedTaskIdle`,
`requiresCommit`, `requiresPush`, `idleMinutes`, `ahead`, `behind`,
`mergeConflict`, `branchChanged`, `destructiveOperation`,
`expectedCommitPushed`, and `conflictingScopes`.

Build fields: `owner`, `owningSolThread`, `status`, `artifactCommit`,
`expectedCommit`, `artifactVersion`, `expectedVersion`, `missingFiles`,
`missingFileCount`, `manifestMatches`, `packageSizeBytes`,
`previousPackageSizeBytes`, and `installerArtifactHashMatches`.

Routine dirty development is quiet. Completed idle work, conflicting repository
state, build failure, identity mismatch, missing content, checksum mismatch, or
a large package-size change can open a condition. The Heartbeat module does not
run Git, tests, or a build. The host supplies these normalized results.

## Cadence and state transitions

The initial advisory cadences are:

| Family | Minimum interval |
| --- | ---: |
| Agent stall | 5 minutes |
| Guardian | 5 minutes |
| Usage | 5 minutes |
| Task dependency | 5 minutes |
| Test state | 10 minutes |
| Git and build | 10 minutes |
| Session growth | 15 minutes |
| Machine drift | 30 minutes |

The host decides when to invoke Chronos. The engine also applies these minimum
intervals. A call made before a family is due does not update that family's
observed baseline and cannot resolve its open conditions.

Each condition stores first observed, last observed, occurrence count, episode,
severity, last notification, and resolution state. The state key contains a
SHA-256 hash, not the supplied subject or route. A condition emits when it is
new, reopens, or moves to a higher severity. Evidence changes at the same
severity remain quiet. A missing entity, collector restart, counter rollback,
partial sample, stale sequence, or unrelated Git/build source cannot resolve an
open condition. A resolution requires a due, observed, continuity-proven sample
for the same entity and detector reason.

## Event format

An actionable cycle writes one compact envelope:

```text
CHRONOS HEARTBEATS {"ok":true,"eventCount":1,"events":[...]}
```

Each event includes:

- `Event`: `HEARTBEAT_EVENT` or `HEARTBEAT_RESOLVED`.
- `EventId`: a stable SHA-256 delivery ID; hosts must deduplicate on this value.
- `Delivery`: `new` or `retry`.
- `Type` and `Severity`.
- `Owner` and `Subject` from supplied opaque IDs; `OwningSolThread` is always
  `governor`.
- `Detected`, concise `Changed` and `Evidence` arrays.
- `LikelyCause` and `RecommendedAction`.
- A privacy-safe stable `DedupKey` containing a subject hash.
- `InterventionClass`, `InterventionTemplate`, `TargetPolicy`, and
  `Postcondition` from a fixed allowlist.
- `Autonomous` and `SelfTargetAllowed`. Self-target is always false.
- `CostImpact` and `QuotaImpact`. These are `unknown` for usage events unless a
  future runtime supplies trusted metadata; Chronos does not infer them from a
  model name.
- `GovernorOrigin`, `CorroborationRequired`, and `CorroborationScope` for usage
  events. Governor-origin usage stays local unless a second event concerns the
  same subject and observation window.
- `GovernorLocalAction`, `GovernorCadenceMinutes`, `RequiredHostAction`,
  `MonitoredTaskMessage`, and `UserActionRequired`. These fields make a
  Governor-local cadence change deterministic and keep routine remediation off
  the user.

Chronos emits `INFO` for resolution. `ReleaseNoticeEligible=true` only when an
active intervention had a temporary restriction that the target acknowledged.
Other resolutions stay Governor-local.

Event delivery uses a bounded local outbox. Chronos
persists an event before writing it to stdout. An unacknowledged event becomes
eligible for one retry after 15 minutes with the same `EventId`. The initial
attempt plus one retry is the hard limit. An exhausted record remains visible
in compact status and does not produce more Governor wakes. A retry contains
only hashes and routes to Governor because Chronos does not persist raw owner,
task, or route IDs. New events also route to Governor. The host must deduplicate
the stable ID before delivery. `plan` or `fail-closed` consumes the native
outbox record atomically. Use `-HeartbeatAcknowledgeEventId` only when the
Governor records an event without opening an intervention. A crash can cause a
duplicate Governor-inbox attempt, but never an unbounded retry. Due outbox records are selected before duplicate-run
suppression, so repeating the same `runId` after a crash can drain the pending
event. Delivery attempts and retry eligibility use local wall-clock time, not
the replayable collector `capturedAtUtc` evidence timestamp. Due delivery and
duplicate-run recovery are evaluated before evidence-time ordering, so an old
serialized retry cannot be preempted by a newer collector cycle.

## Autonomous intervention state

The Governor first processes any `GovernorLocalAction`. For
`throttle_recurrence_to_idle_cadence`, it updates only its own recurrence to
the returned 360-minute cadence, re-reads the automation, and acknowledges the
event only after one active recurrence with that cadence is verified. A
Governor-origin resolution returns
`restore_supervision_recommended_cadence`; the Governor reconciles the current
60- or 360-minute supervision cadence and verifies the same one-recurrence
postcondition. It does not message a monitored task unless an independent event
concerns the same subject and observation window. A failed host mutation stays
Governor-local for the bounded retry and never becomes a routine user relay.

For task-directed events, the Governor must plan all events in a cycle before
it sends a task message.
Chronos permits one active intervention per target generation. Compatible equal
or lower severity events coalesce. An incompatible remediation contract remains
pending until the active contract is terminal. A higher severity event replaces
an unsent compatible version. If an
earlier version was already sent, only one escalation version is allowed.

The minimum flow is:

1. `list` persisted interventions for this Governor and follow only the returned
   bounded next action. Use `reclaim` only for an expired claimed send.
2. `plan` or `fail-closed` all new events.
3. Recheck the exact live target and host generation.
4. `claim` one send attempt.
5. Call `send_message_to_thread` with the fixed returned instruction.
6. Record `accepted`, `definite_failure`, or `unknown`.
7. Accept a bounded categorical reply only from the exact target and version.
8. Wait for an observed Heartbeat result or an allowed independent host check.
9. Mark `verified_resolved`, `active_violation`, or `remediation_failed`.

`plan` hashes the requested target and enforces the fixed event-class policy
against the persisted subject and owner hashes. A subject-only event cannot be
redirected to its owner, and an owner-only event cannot be redirected to its
subject. A mismatch returns `target_policy_mismatch` and consumes the event as
a fail-closed intervention.

Transport acceptance is not task acknowledgement. A task report is not proof
of recovery. A send with an unknown outcome does not retry. Only a definite
failure permits one retry. State keys combine the event occurrence,
intervention version, target hash, and target-generation hash.

List recoverable work after a Governor restart:

```powershell
chronos.cmd -Action heartbeat -HeartbeatInterventionAction list `
  -HeartbeatGovernorId <governor-task-id>
```

The list is bounded to 16 active records and returns opaque intervention IDs,
versions, states, target and generation hash prefixes, fixed templates,
postconditions, attempt counts, timestamps, and `permittedNextAction`. For an
expired `send_claimed` record, call `reclaim` with its opaque ID, version, and
the same Governor ID. Reclaim converts the record to `delivery_unknown`; it
does not retry because the host send might already have succeeded. Only an
explicitly recorded definite transport failure can consume the second attempt.
During schema-6 migration, provably unsent queued work is visible to the one
current Governor and can be adopted only after its target and generation match.
A legacy claimed send becomes visible `delivery_unknown` and is never retried.

Plan an event:

```powershell
chronos.cmd -Action heartbeat -HeartbeatInterventionAction plan `
  -HeartbeatEventId <event-id> -HeartbeatTargetId <live-task-id> `
  -HeartbeatTargetGeneration <host-generation> `
  -HeartbeatGovernorId <governor-task-id>
```

For Governor-origin `USAGE_BURN`, also pass a same-subject, same-window stall,
Guardian, or machine event with `-HeartbeatCorroboratingEventId`. Without that
evidence, planning returns `governor_usage_uncorroborated` and stays local.

Claim only after all events for the cycle are planned and the target is checked
again:

```powershell
chronos.cmd -Action heartbeat -HeartbeatInterventionAction claim `
  -HeartbeatInterventionId <intervention-id> `
  -HeartbeatInterventionVersion <version> `
  -HeartbeatTargetId <live-task-id> `
  -HeartbeatTargetGeneration <host-generation> `
  -HeartbeatGovernorId <governor-task-id>
```

Record the host send result with `-HeartbeatInterventionAction transport` and
the returned `-HeartbeatClaimToken`. Record a task reply with
`-HeartbeatInterventionAction response`, the exact target and generation, and
one allowed `-HeartbeatTaskResponse`. Record independent evidence with
`-HeartbeatInterventionAction verify`, an allowed verification source, and a
categorical result. These commands persist hashes, enums, counters, and
timestamps only.

The fixed autonomous actions can ask an affected task to stop new worker
creation, reduce its own parallel work, checkpoint, return completed workers,
prepare a fresh-task handoff, reconcile a child it owns, or run one known narrow
validation. They cannot expand the task's user-authorized assignment. Chronos
fails closed for installs, model or reviewer changes, permissions, secrets,
process termination, PC restarts, broad commands, destructive Git actions,
publishing, ambiguous ownership, unavailable transport, or user-only authority.

## Persistence and concurrency

Default state is stored at:

```text
%TEMP%\Chronos\Heartbeat-v2\<scope-sha256>\heartbeat-state.json
```

The default scope combines the machine and Codex home only to create the hash.
The current workspace is not part of the default identity, so a Governor
working-directory change does not split Heartbeat state. Those values are not stored in the file. The default state
directory retains the current user's inherited TEMP permissions; Chronos does
not replace them with a transient sandbox identity. On first use after an
upgrade, Chronos first checks the v0.8.6 CWD-derived default namespace for the
current working directory, then the prior TEMP namespace and legacy
LocalAppData location. A valid source is read and upgraded in memory, rebound
only in the new destination, and never modified in place. If prior state is inaccessible, Chronos does not
take ownership or change its permissions. It starts in the versioned namespace
and reports `prior_state_unavailable_new_root`. Compact status reports the
state-store mode, write preflight, protection mode, and migration result without
returning a path. A host can supply
`-HeartbeatScope` for a stable explicit scope.
Compact status also reports `priorStateDisposition` and
`priorStateWriteAttempted`. `unavailable_preserved` with `false` means Chronos
detected an inaccessible prior scope and made no migration write, rename,
delete, ownership, or permission-change attempt. It does not claim that Chronos
read or independently verified the protected file contents or ACL.
An explicit `-HeartbeatStatePath` must stay beneath the versioned TEMP root or
the LocalAppData Heartbeat root. A sibling elsewhere under TEMP is rejected
before Chronos creates a directory or file.

The state file uses schema `7` and contains only bounded hashed identity, normalized counters,
statuses, timestamps, cadence, coverage, condition state, compact event
metadata, delivery metadata, and engine health. It retains at most 256
conditions, 50 compact event records, 64 unacknowledged outbox records, 64
intervention records, and 32 run-ID hashes. Intervention records contain hashes,
enums, counters, and timestamps only. The file is limited to 256 KiB. Active conditions are never
silently evicted; the cycle fails closed if their capacity is exhausted.

A restrictive per-user `Global\` named mutex serializes every Windows process
that can reach the same state. Its name is derived from the canonical directory
handle path with case folded, so Windows case aliases share one lock. A state
file with more than one hard-link name is rejected. Same-directory temporary
files, write-through flush, and atomic replacement protect the committed state.
Repeated run IDs and concurrent duplicate scheduler calls do not emit duplicate
events. After an abandoned mutex, Chronos reopens and fully validates the
authoritative state before any detector runs. Reparse-point input or state
ancestry is rejected.

## Recursion and self-health

Snapshots with `origin=heartbeat`, `origin=heartbeat_notification`, or
`isHeartbeatGenerated=true` are ignored. `heartbeatActivity` can report
duplicate schedulers, cycle runtime, and the host's configured runtime budget.
Chronos keeps a bounded recent successful-runtime baseline. A single modest
overrun within the larger of 1 second, 10 percent of the configured budget, or
25 percent above that baseline is `normal_variance`: it remains quiet and does
not back off. Three consecutive overruns are `sustained_overrun`; a runtime at
least 50 percent above both the budget and baseline is `material_overrun` and
does not wait for persistence. Duplicate schedulers, sustained overruns, and
material overruns route once to the Governor inbox and back off only that
collector for 15 minutes. A subsequent healthy forced cycle clears the backoff
and emits the normal resolution transition. Heartbeat never opens a task
intervention against the Governor. Other families continue to run.

Compact status reports `runtimeBudgetMs`, `runtimeObservedMs`,
`runtimeOverrunMs`, `runtimeOverrunPercent`, `runtimeBaselineMs`,
`runtimeClassification`, `runtimeOverrunStreak`, `runtimeBackoffApplied`, and
`backoffUntil`. This makes the classification and backoff decision auditable
without retaining raw task content.

## Limits

Chronos cannot infer evidence that the host does not expose. The local Inspector
does not provide a complete owner graph, task dependency graph, per-agent tool
progress, cross-machine installation inventory, artifact provenance, or proof
that another task received an event. Those fields remain partial or unsupported
until the host supplies them.

Heartbeat state is local and unauthenticated. Atomic writes coordinate local
processes but do not make the file a security boundary. SHA-256 identifiers are
pseudonymous metadata, not anonymous data. The engine does not prove that a
worker is safe, that an artifact is correct, or that a route was delivered. The
Governor must verify the named postcondition independently before it records
recovery.

Heartbeat sends no publisher telemetry and makes no network or model calls. It
emits a bounded local event to the invoking host. Any host delivery is controlled
by that host and can be processed under the user's OpenAI account or workspace.
