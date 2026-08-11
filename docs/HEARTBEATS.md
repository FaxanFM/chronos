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
once. Do not install or invoke Heartbeats inside every monitored task.

Monitored tasks can use different models and reasoning levels. The recommended
Governor configuration is `gpt-5.6-luna` with Medium reasoning because the
Governor performs bounded, repeated triage. OpenAI describes Luna as the
[efficient high-volume GPT-5.6 tier](https://developers.openai.com/api/docs/guides/latest-model).
The host must select this setting. Chronos cannot select or enforce a task model.

## Command surface

Run a normalized cycle:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action heartbeat -HeartbeatInputPath snapshot.json
```

Add a captured compact Inspector result when available:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action heartbeat -HeartbeatInputPath snapshot.json -HeartbeatInspectorOutputPath inspector.txt
```

Show local Heartbeat status without running a collector:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action heartbeat
```

After the host successfully deduplicates and delivers an event, acknowledge its
stable `EventId`:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action heartbeat -HeartbeatAcknowledgeEventId <sha256-event-id>
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
- Collecting the normalized fields that the runtime exposes.
- Assigning privacy-safe opaque IDs and ownership hints.
- Running one Governor task for the monitored task set.
- Selecting `gpt-5.6-luna` with Medium reasoning for that Governor when available.
- Delivering emitted events to the Governor inbox.
- Deduplicating delivery by `EventId` and acknowledging successful delivery.
- Recording whether remediation occurred.

Chronos does not contact another task. `OwningSolThread` is always `governor`.
`Owner`, `Subject`, and supplied thread IDs are evidence for Governor triage;
they are not direct-delivery instructions. The host can choose to forward an
event after Governor review. Chronos never returns a broadcast route or wakes
each monitored task.

The deterministic cycle does not use model tokens. Monitored tasks can use
Luna, Terra, Sol, or a mix. The recommended host configuration is one Governor
task using `gpt-5.6-luna` with Medium reasoning. The host, not Chronos, selects
the model and reasoning effort. Chronos does not call a model or change a task's
model setting.

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

Supported fields: `owner`, `owningSolThread`, `progressHash`, `lastToolHash`,
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

Supported fields: `owner`, `dominantThread`, `owningSolThread`, `totalTokens`,
`windowTokens`, `windowMinutes`, `ratePerMinute`, `baselineRatePerMinute`,
`projectedExhaustionMinutes`, `reviewerShare`, `meaningfulProgress`, and
`progressHash`.

High usage with progress does not alert. The detector requires abnormal
velocity or a materially earlier exhaustion projection and uses the supplied
progress signal. These values are operational observations, not account
billing totals.

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

Supported fields: `owner`, `owningSolThread`, `commit`, `repairAttempts`,
`failureCount`, `required`, `ran`, `environmentStatuses`, and `buildId`.

Chronos persists whether a regression became active. A known failing baseline
does not become a new regression. A persisted pass-to-fail transition does.
Unchanged failures are deduplicated. Additional failed repair attempts can
increase severity. Environment disagreement and missing required validation
use separate condition keys.

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

Supported fields: `owner`, `owningSolThread`, `dependsOn`,
`dependencyStatus`, `ageHours`, `requiredCommit`, `requiredPush`,
`requiredValidation`, `validationStatus`, `acknowledgedBug`, `assigned`, and
`updatedAt`.

The actionable-task detector requires a persisted dependency transition from
incomplete to complete. A first snapshot that already says complete does not
wake an owner. Unassigned old work and incomplete release handoffs use separate
conditions.

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

Chronos emits `INFO` for resolution. A host can record that event without
waking an expensive reasoning task.

Event delivery uses a bounded local outbox with at-least-once semantics. Chronos
persists an event before writing it to stdout. An unacknowledged event becomes
eligible for retry after 15 minutes with the same `EventId`. A retry contains
only hashes and routes to Governor because Chronos does not persist raw owner,
task, or route IDs. New events also route to Governor. The host must deduplicate
the stable ID before delivery and
acknowledge only after delivery succeeds. A crash can therefore cause a safe
duplicate attempt, but it cannot permanently suppress a transition that was
persisted before stdout. Due outbox records are selected before duplicate-run
suppression, so repeating the same `runId` after a crash can drain the pending
event. Delivery attempts and retry eligibility use local wall-clock time, not
the replayable collector `capturedAtUtc` evidence timestamp. Due delivery and
duplicate-run recovery are evaluated before evidence-time ordering, so an old
serialized retry cannot be preempted by a newer collector cycle.

## Persistence and concurrency

Default state is stored at:

```text
%LOCALAPPDATA%\Chronos\Heartbeat\<scope-sha256>\heartbeat-state.json
```

The default scope combines the machine, Codex home, and current workspace only
to create the hash. Those values are not stored in the file. A host can supply
`-HeartbeatScope` for a stable explicit scope.

The state file contains only bounded hashed identity, normalized counters,
statuses, timestamps, cadence, coverage, condition state, compact event
metadata, delivery metadata, and engine health. It retains at most 256
conditions, 50 compact event records, 64 unacknowledged outbox records, and 32
run-ID hashes. The file is limited to 256 KiB. Active conditions are never
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
duplicate schedulers and cycle runtime. An abnormal self-health condition routes
once to Governor and backs off that collector for 15 minutes. Other families
continue to run.

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
owning coordinator must investigate and accept any remediation.

Heartbeat sends no publisher telemetry and makes no network or model calls. It
emits a bounded local event to the invoking host. Any host delivery is controlled
by that host and can be processed under the user's OpenAI account or workspace.
