# Chronos Supervision

Chronos supervision gives one dedicated Governor task a low-overhead view of active
Codex tasks. Worker tasks remain passive and can use any available model.
Chronos does not install a daemon, operating-system scheduler, network client,
or per-task model loop.

## Setup

After installing or upgrading Chronos, fully quit and reopen Codex. Then open a
fresh task and ask:

```text
Set up Chronos fully on this PC. Verify the installed source, enable
supervision and Heartbeats in one dedicated Governor, and confirm one Governor
recurrence with zero worker recurrences. Keep routine worker tasks passive and
do not ask me to relay routine findings.
```

This request opts in to one host-managed recurring Governor turn: at most 24
turns per day while monitored work is active and four per day while idle at the
default cadence. Worker tasks receive no recurring turns. Chronos requires a
fresh Governor or pauses after 336 cycles or 14 days, whichever comes first.

Codex requires a one-time review before a non-managed plugin hook can run. Use
`/hooks` to inspect and trust the exact Chronos lifecycle definition. Chronos
does not bypass this review. If hooks remain disabled or untrusted, the
Governor uses one compact host inventory as the deterministic fallback. It
does not ask the user to register tasks or relay routine findings.

The `/hooks` installed, active, and trusted labels describe host configuration.
They do not prove that Windows launched the command. Native status reports
`hookExecutionObservation=observed` only after `hookRuns` and `lastHookUtc`
advance. Until then it reports `not_observed` and keeps the complete host
inventory as the liveness authority. Hooks are an optional accelerator, not an
autonomy dependency. Current Windows Codex surfaces can show trusted hooks
without dispatching them, and `codex exec` can omit hook dispatch. A release
canary must record observed execution when the host provides it. When it does
not, the canary must identify the host limitation and prove that one complete
host inventory still discovers every live task without user registration,
routine wakes, or worker model turns.

Setup is complete only after Codex reports the active source, native status,
one live dedicated Governor, one active matching Governor recurrence, readable
Heartbeat status, and zero worker recurrences. An internal claim flag by itself
is not a successful setup result.

No worker prompt or worker-side script is required. The plugin registers only:

- `SessionStart`
- `SessionEnd`
- `SubagentStart`
- `SubagentStop`
- `Stop`

Start, subagent, and completed-turn handlers request asynchronous command
execution where the host supports it. `SessionEnd` is always synchronous in Codex. Every hook is headless,
has a three-second host timeout, exits without model-visible output, and never
runs for prompts, approvals, or tools. The `Stop` hook records only the task,
a hashed turn signal, safe model/workspace categories, counters, and timestamps.
On Windows, the configured command is quote-free at the Codex `cmd.exe`
boundary. Its constant UTF-16LE `-EncodedCommand` payload resolves
`PLUGIN_ROOT` inside PowerShell and invokes only
`skills\chronos\scripts\hook-intake.ps1`. This avoids the Codex Windows
outer-quote failure without accepting runtime script content or loading the full
supervision engine inside the three-second host window.

Intake strictly validates the bounded JSON event, protects task and agent IDs
with Windows DPAPI for the current user, hashes the normalized workspace and
completed-turn signal, and writes one physically flushed event to a private
inbox scoped by canonical `CODEX_HOME` and machine identity. It does not read or
write the main registry. The next supervision status or Governor cycle selects
the safe state slot, owns the registry mutex, merges each valid inbox event once,
persists a bounded SHA-256 receipt, and removes the merged file. A receipt stays
authoritative if Windows temporarily refuses deletion, so the same file cannot
change state or counters twice. DPAPI decoding and normalized-ID validation stay
inside the per-file boundary. Undecryptable or malformed entries increment the
dropped-entry counter once, change no task state, and are removed only after the
degraded state is saved.

Direct diagnostic use of `session-registry.ps1 -Action hook` retains the
mutex-bound path. `SessionEnd` mutex acquisition is capped at 250 ms;
asynchronous acquisition is capped at 100 ms. If the registry is busy or direct
persistence fails before commit, that path makes at most two bounded attempts
to write the same protected pending-event format. Diagnostic mode exposes a
failure when neither path is durable. Configured production hooks stay silent;
complete host inventory remains authoritative if intake cannot persist a hint.

## Governor Selection

The host uses this reconciliation order:

1. Build an all-same-name observation set from every host automation named
   exactly `Chronos Governor pulse`, its
   immutable ID, creation time when available, target task, equivalence key,
   and compact local supervision status. Observation does not authorize mutation.
2. Read `hostEquivalenceKey` from status. Derive a separate current-key mutation
   set containing only automations whose task assignment carries that complete
   value and verifies the dedicated role. A different or unverified key is never
   mutated or counted in this installation's postcondition. Sort existing
   automation candidates by creation time ascending, then immutable automation
   ID and target task ID using ordinal comparison. Missing creation times sort
   after present times. Every installer selects the first candidate. With no
   valid automation, apply the same order to role-verified claimed tasks.
3. Otherwise create one fresh `Chronos Governor` task with no inherited chat
   history and include the complete returned equivalence key in its compact
   assignment. Re-list all live, role-verified current-key Governor tasks after
   any creation and apply the same stable ordering. Only the first deterministic
   setup contender can proceed to recurrence mutation or initialization. Other
   fresh contenders perform no local or recurrence mutation, prove no recurrence
   targets them, and stand down. Without stable IDs, no contender proceeds.
4. Before initialization, pause or remove every active recurrence in the
   current-key mutation set, including a winner retained from an earlier setup.
   Immediately before the first mutation, rebuild the all-same-name observation,
   current-key mutation set, and role-verified task list, then repeat the
   deterministic contender election. A new recurrence or task can therefore
   change the winner; a newly identified loser skips initialization and enters
   the no-mutation loser-verification branch. Otherwise re-list host state and
   prove zero active current-key recurrences. Recompute
   the mutation set after each host read or mutation for at most three attempts.
   Leave foreign and unverified keys unchanged. If zero cannot be proven, stop
   before initialization and schedule no recovery turn.
5. Let only the elected task claim the mutex-protected registry. This mutex fences
   one machine and state root only. Native `error=supervision_governor_conflict`
   is the other entry to the no-mutation loser-verification branch; it is not a
   generic initialization failure and must not run current-key cleanup. The loser
   re-reads native and host state, creates no recurrence, does not mutate the
   role-verified current-key winner, proves no recurrence targets the losing task,
   and stands down. If one live role-compatible current-key winner cannot be
   verified within three bounded reads, the loser stops with no recurrence
   mutation and no recovery turn. The winning setup owns convergence to exactly
   one current-key Governor recurrence and zero worker recurrences.
6. Require readable supervision and Heartbeat
   status, then run one complete caller-aware host inventory that accounts for
   that Governor exactly once. Continue only when the cycle returns
   `recurrenceEligible=true`.
7. Only after that gate succeeds, update or create the deterministic winning
   automation, pause or remove every non-winner, and re-list host state. Setup is
   complete only when exactly one active recurrence carrying the complete
   equivalence key targets exactly one claimed, live Governor and zero active
   duplicates remain. If create, update, duplicate cleanup, or postcondition
   verification fails after three attempts, pause or remove the recomputed
   current-key mutation set, re-list it, and prove zero active current-key
   recurrences. Schedule no recovery turn and never mutate a foreign or
   unverified key. Routine convergence failure must not become a user chore.
8. Repeat the same host-global winner and postcondition check before discovery
   on Governor cycles zero and one. This catches concurrently created state that
   was not yet visible during setup. A loser stops its own recurrence and stands
   down. A losing task clears only its own local claim, and only through
   two-phase release after its recurrence is proven absent. It never clears a
   winner's claim. Normal cycles after that do not rescan all automations unless claim
   loss, rotation, or recovery requires it.
9. Use the current task only when task creation is unavailable and the user
   explicitly requested setup.

Chronos never automatically forks a working task. A fork can duplicate a large
context and increase quota pressure, while a fresh dedicated task starts with a
small, auditable assignment. `-Force` takeover is permitted only after host task
status proves that the recorded Governor is no longer live.

The same order is used after a partial setup, stale claim, process failure, or
local registry loss. A host scan is authoritative for recurrence identity, so
clearing local state cannot justify creating a duplicate. A title alone is not
role verification. The equivalence key and deterministic host ordering are the
same-installation ownership fence. If competing candidates lack stable host IDs,
Chronos does not create another candidate automatically. Each installation gets
a 128-bit opaque ID stored separately from the session registry. New v3 state
derives it from a hash of the machine and Codex home; a readable earlier random
anchor is imported unchanged. Deleting only `session-registry.json` therefore
preserves recovery identity. Different PCs have different keys and separate
Governors because one Governor cannot read another PC's local registry.

A nonempty `CODEX_HOME` is authoritative; the current user's `.codex`
directory is used only as the fallback. Chronos canonicalizes the directory and
hashes it before deriving the state slot, installation key, and registry mutex.
The same Codex home converges across sandbox `HOME` changes and path aliases.
Separate homes remain isolated. Invalid or inaccessible overrides fail closed
without creating state or a Governor claim. A reparse point in any path
component, including an ancestor junction, is invalid.

Unscoped v2, fixed-TEMP, and LocalAppData state predates `CODEX_HOME` identity.
Chronos considers those sources only when it is using the default `.codex`
home. An explicit or environment-provided home can import only its own
home-scoped prior-v2 state. Sequential and concurrent first use by separate
custom homes therefore cannot clone one legacy installation key or registry.
All legacy sources remain read-only during this decision.

The two initial convergence rechecks are bounded host reads inside the existing
Governor turns. They create no worker turn and no permanent per-cycle scan.

The status key has format `chronos-supervision-v1:<32 lowercase hexadecimal
characters>`. It contains no raw hostname, username, path, machine GUID, task ID,
or workspace data. It is a persistent pseudonymous installation identifier,
not a secret or authentication credential.

The host requests `gpt-5.6-terra` with Medium reasoning when that exact choice is
available. Chronos cannot change a task's model itself and does not silently
substitute another model. This preference applies only to the Governor;
monitored tasks remain model-agnostic. Chronos does not infer cost, quota impact,
or efficiency from a model name.

## Runtime Contract

The installed command surface is:

```powershell
# Compact state only
chronos.cmd -Action supervise -SupervisionAction status

# Run only inside the selected Governor task
chronos.cmd -Action supervise -SupervisionAction initialize

# Passive registry read; this does not advance the Governor cycle
chronos.cmd -Action supervise -SupervisionAction discover

# After one compact complete host task-list call, run one Governor cycle
chronos.cmd -Action supervise -SupervisionAction cycle `
  -SupervisionHostInventoryPath <temporary-inventory.json>

# Only after host liveness verifies an ended entry is active again
chronos.cmd -Action supervise -SupervisionAction confirm-active `
  -SupervisionSubjectId <task-or-agent-id>

# First returns the required host cleanup action; it does not clear ownership
chronos.cmd -Action supervise -SupervisionAction release

# Run only after all matching recurrences are stopped and verified absent
chronos.cmd -Action supervise -SupervisionAction release `
  -SupervisionConfirmRecurrenceStopped
```

The Governor calls the host task list once, writes only opaque task IDs, safe
status categories, optional opaque generations, a capture time, and a
`complete=true` flag to a bounded temporary JSON file, then calls `cycle`.
Schema v1 means the host list includes its caller and therefore requires the
Governor exactly once in `tasks`. Schema v2 adds `callerVisibility`. Use
`callerVisibility=included` under the same rule, or
`callerVisibility=excluded_by_host` only when the host list omits the current
caller; in that case `tasks` must omit the Governor and Chronos adds only the
registry-verified cycle caller during normalization. It never infers omission or
makes a second status call. The result reports `hostInventoryRawObserved`,
`hostInventoryObserved`, `hostInventoryCallerVisibility`, and
`hostInventoryGovernorSource` so the one-call boundary is auditable.
Missing or incomplete inventory fails closed and does not advance the cycle.
Host task state is the liveness authority. The native action
adds tasks missed by hooks, reactivates verified live tasks, and closes absent
tasks. It returns one hash-only normalized status for every inventory task and the rotating
`checkBatch`, which contains at most eight entries and covers larger registries
fairly over successive cycles. Inventory or transport failure remains
Governor-local; the routine user action is none.
Terminal hook state has precedence: a delayed start event cannot revive
an ended task or agent. A terminal event received before its asynchronous start
creates a bounded ended tombstone, and a subagent start received after its
parent ended remains ended. Only `confirm-active`, after host verification, can
reactivate a task. Do not poll full transcripts, repeatedly read unchanged tasks, or send
routine messages to monitored tasks.

The Governor owns the only model recurrence. A normal cycle reports
`taskWakePolicy=intervention_claim_required`; only the bounded Heartbeat
plan-and-claim state machine can authorize a task message. When the user enables recurring
supervision, reconcile one host Heartbeat automation attached to the dedicated
task. Use 60 minutes while monitored work is active and 360 minutes while idle.
A normal cycle ends silently. A new, materially worse, or eligible resolution
transition can open one bounded intervention for one exact affected task. The
Governor plans all events before it sends, coalesces compatible work by target
generation, and never
broadcasts. This bounds scheduled Governor turns to 24 per
active day or four per idle day; provider billing and caching remain host
concerns and Chronos makes no cost claim.

The registry reports `rotationRequired=true` after 336 cycles or 14 days. The
host must then perform a verified fresh-task handoff, preserving one recurrence,
or pause the recurrence and retain the reason locally. It must not continue adding
unbounded history to the same Governor task. Release is two phase: stop and
verify every current-key recurrence first, leave foreign and unverified keys
unchanged, then confirm local release. A failure before confirmation preserves
the claim so the next setup can reconcile it.

The PowerShell module does not create that automation or contact a task. It
returns local routing metadata for the Codex host to use.

## Task communication

The Governor, not each monitored task, owns monitoring. Workers remain passive
until one event requires a bounded action. The Governor then uses the host task
transport to contact the exact verified affected task. It does not tell the user
to relay the message.

Before sending, the Governor must:

1. Reconcile current host liveness and generation.
2. Plan every event in the current cycle.
3. Keep only one active intervention for each target.
4. Recheck the target immediately before it claims the send.
5. Send one fixed-template instruction and fixed categorical reply format.

An accepted host send advances to `awaiting_task_ack`. A timeout or uncertain
result advances to `delivery_unknown` and does not retry. A definite rejection
can retry once. Only the exact target and version can report an outcome. The
outcome advances to independent verification; it does not resolve the detector
condition. See [Heartbeats](HEARTBEATS.md) for the full state machine.

Governor usage alone stays Governor-local and never creates a self-message. A
Governor usage comparison is valid only when both samples include completed
cycle, state-change, acknowledgement, failure, and duplicate-run counters.
Completed supervision work counts as progress even when the repository does not
change. A verified HIGH Governor-local condition returns a fixed instruction to
change only the Governor recurrence to 360 minutes and verify that one active
recurrence remains. A later comparable recovery returns the normal cadence
reconciliation action. It can support an affected-task intervention only when a
second observation covers the same task and time window. Ambiguous targets and
unavailable transport stay Governor-local; only genuine user authority is
surfaced to the user.

## Local State

The default registry is:

```text
%TEMP%\Chronos-Supervision-v3-<scope-prefix>-<slot>\session-registry.json
```

Chronos selects the first writable non-reparse location from four bounded direct
TEMP child slots. This avoids inheriting an inaccessible shared `Chronos`
ancestor left by an earlier sandbox identity. The directory retains the current
user's inherited TEMP permissions. Task and agent identifiers remain protected
by Windows DPAPI. A fresh v3 installation uses a deterministic host-and-Codex-home
hash for its opaque identity, so selecting a recovery slot cannot create a
second Governor identity. When a structurally valid v3 state is readable but its
protected IDs belong to an unavailable sandbox identity, Chronos preserves that
state, selects the next bounded slot, and copies only the validated installation
anchor with `installationScopeSource=recovered_v3_anchor` so recurrence identity
stays stable. An explicit state path still fails
closed. No raw machine name or Codex-home path is stored. On first
use after an upgrade, Chronos imports a readable prior installation anchor and
state without changing the v2, fixed-TEMP, or LocalAppData source. This preserves
the existing Governor equivalence key for the eligible default home. Custom
homes do not claim these unscoped sources. An inaccessible prior root is left unchanged
and reported as `prior_state_unavailable_new_root` with
`priorStateWriteAttempted=false`; authoritative host inventory rebuilds the
advisory registry. Chronos reports only the selected slot number, a short state
identity hash, anchor persistence and provenance category, write preflight,
protection mode, migration result, and prior-state disposition. It does not
return a path.

Initialization alone never authorizes a recurrence. The first complete host
inventory cycle must account for the selected Governor exactly once under the
caller-visibility contract and return `recurrenceEligible=true`. Pre-mutation
election loss skips initialization.
Native `error=supervision_governor_conflict` enters the same no-mutation loser
branch and is explicitly excluded from generic failure cleanup. Except for those
two non-fallthrough cases, a failed initialization, unreadable status, missing Governor,
or failed inventory cycle requires pausing or removing every current-key
recurrence, including a pre-existing active recurrence. Re-list host state and
prove zero active current-key recurrences within three bounded mutation and
verification attempts. Do not schedule a recovery recurrence. A different or
unverified installation key is observation only and remains unchanged.

The deterministic setup regression matrix is:

| Injected result | Active Governor recurrences | Active worker recurrences | Recovery turn scheduled |
| --- | ---: | ---: | --- |
| initialization failure | 0 | 0 | no |
| supervision status unreadable | 0 | 0 | no |
| Heartbeat status unreadable | 0 | 0 | no |
| incomplete inventory | 0 | 0 | no |
| inventory missing Governor | 0 | 0 | no |
| inventory contains Governor more than once | 0 | 0 | no |
| post-eligibility recurrence reconciliation failure | 0 | 0 | no |
| complete inventory and `recurrenceEligible=true` | 1 | 0 | no |

The isolation and concurrency regression matrix is:

| Scenario | Current-key Governor recurrences | Foreign-key Governor recurrences | Worker recurrences | Losing installer mutates winner |
| --- | ---: | ---: | ---: | --- |
| pre-initialization fence with one foreign-key recurrence | 0 | 1 | 0 | no |
| two concurrent fresh installers after convergence | 1 | 0 | 0 | no |

The registry is capped at 256 KiB and 256 retained records. Task and agent identifiers are
encrypted with Windows DPAPI for the current Windows user and indexed by
SHA-256. DPAPI does not protect against another process already running as that
same user. The file can also contain pseudonymous workspace hashes, safe model
slugs, lifecycle state, counters, and timestamps. It does not contain prompts,
responses, transcript paths, source code, commands, tool arguments, tool output,
credentials, usernames, or absolute workspace paths.

Raw task IDs are decrypted only for local supervision status or Governor
discovery and may then enter the Governor task or host-tool context. Chronos does not send them to its
publisher. The state is advisory and unauthenticated; it does not authorize task
access or prove task liveness. At capacity Chronos retains existing records,
marks the engine degraded, and exposes `registryCapacity=exhausted` instead of
silently evicting active work. Atomic replacement, a named mutex, strict size
limits, reparse-point checks, retention limits, and safe failure protect the
local coordination path.

Configured hooks write to an installation-scoped inbox. Direct registry
contention can also create a sibling fallback directory. Each entry is at most
4 KiB and contains only an event category, DPAPI-protected task or agent IDs, a
workspace hash, safe labels, and a timestamp. Chronos reads at most 256 entries
across both locations per merge. The next status or Governor cycle merges valid
events, removes their files, and records malformed entries in a degraded
counter. Empty directories remain so a concurrent writer cannot lose an event
while the registry merges earlier entries. The direct fallback writer has a
two-attempt local retry budget. Neither queue is a transcript, diagnostic log,
or telemetry transport.

## Usage Boundary

Supervision adds one short local PowerShell process at task or subagent start
and end, plus one background process after each completed main-task turn. It
adds no hook-generated model turn, model-visible context, or worker recurrence. Only the
dedicated Governor uses a model on the disclosed bounded host cadence. The
deterministic supervision engine is model-agnostic; the bootstrap policy alone
prefers Terra Medium. `hookExecutionObservation`, `lastHookUtc`, and
`hookTrustObservation` distinguish observed execution from the host-only trust
state. The trust field remains `host_verification_required`; Chronos does not
infer it from local registry data. A disabled, untrusted, or non-executing hook
produces no registry event and does not block host inventory reconciliation.
Native status reports `hookRole=optional_acceleration`,
`hookRequiredForAutonomy=false`, and
`taskDiscoveryAuthority=complete_host_inventory_each_governor_cycle`.

Chronos intentionally does not register `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `PermissionRequest`, `PreCompact`, or `PostCompact`. This avoids
prompt inspection, model steering, and a process launch for every tool call.
The completed-turn signal improves discovery and recent-activity evidence; one
complete host inventory per Governor cycle remains the task-liveness authority
and includes both explicitly targeted and automatically discovered live tasks.

Official Codex hook behavior, plugin hook discovery, trust review, asynchronous
execution, and event fields are documented in [OpenAI Hooks](https://learn.chatgpt.com/docs/hooks).
