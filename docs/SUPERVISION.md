# Chronos Supervision

Chronos supervision gives one dedicated Governor task a low-cost view of active
Codex tasks. Worker tasks remain passive and can use any available model.
Chronos does not install a daemon, operating-system scheduler, network client,
or per-task model loop.

## Setup

After installing or upgrading Chronos, open a fresh Codex task and ask:

```text
Enable Chronos supervision. Reuse a verified Chronos Governor or create one
fresh dedicated task. Use GPT-5.6 Luna with Medium reasoning if available.
```

This request opts in to one host-managed recurring Governor turn: at most 24
turns per day while monitored work is active and four per day while idle at the
default cadence. Worker tasks receive no recurring turns. Chronos requires a
fresh Governor or pauses after 336 cycles or 14 days, whichever comes first.

Codex requires a one-time review before a non-managed plugin hook can run. Use
`/hooks` to inspect and trust the exact Chronos lifecycle definition. Chronos
does not bypass this review. If hooks remain disabled or untrusted, the
Governor can still use host task tools, but automatic local discovery is
unavailable.

No worker prompt or worker-side script is required. The plugin registers only:

- `SessionStart`
- `SessionEnd`
- `SubagentStart`
- `SubagentStop`

The start and subagent hooks run asynchronously. `SessionEnd` follows the Codex
synchronous event contract. Every hook is headless, has a three-second host
timeout, exits without model-visible output, and never runs for prompts, turns,
approvals, or tools. Synchronous mutex acquisition is capped at 250 ms; failure
leaves prior state unchanged and exits zero.

## Governor Selection

The host uses this reconciliation order:

1. Inspect every host automation named exactly `Chronos Governor pulse`, its
   immutable ID, creation time when available, target task, equivalence key,
   and compact local supervision status.
2. Read `hostEquivalenceKey` from status. Accept only candidates whose task
   assignment carries that complete value and verifies the dedicated role. Sort existing
   automation candidates by creation time ascending, then immutable automation
   ID and target task ID using ordinal comparison. Missing creation times sort
   after present times. Every installer selects the first candidate. With no
   valid automation, apply the same order to role-verified claimed tasks.
3. Otherwise create one fresh `Chronos Governor` task with no inherited chat
   history and include the complete returned equivalence key in its compact assignment.
4. Let that task claim the mutex-protected registry. This mutex fences one
   machine and state root only. Any concurrent local loser must stop and must
   not create a recurrence.
5. Update or create the deterministic winning automation, pause or remove every
   non-winner, and re-list host state. Recompute the winner after each mutation
   for at most three attempts. Setup is complete only when exactly one active
   recurrence carrying the complete equivalence key targets exactly one claimed,
   live Governor and zero active duplicates remain. After three failed attempts,
   stop retrying and request one user action.
6. Repeat the same host-global winner and postcondition check before discovery
   on Governor cycles zero and one. This catches concurrently created state that
   was not yet visible during setup. A loser stops its own recurrence and stands
   down. Normal cycles after that do not rescan all automations unless claim
   loss, rotation, or recovery requires it.
7. Use the current task only when task creation is unavailable and the user
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
a random 128-bit opaque ID stored separately from the session registry. Deleting
only `session-registry.json` therefore preserves recovery identity. Different
PCs have different keys and separate Governors because one Governor cannot read
another PC's local registry.

The two initial convergence rechecks are bounded host reads inside the existing
Governor turns. They create no worker turn and no permanent per-cycle scan.

The status key has format `chronos-supervision-v1:<32 lowercase hexadecimal
characters>`. It contains no hostname, username, path, machine GUID, task ID, or
workspace data. It is a persistent random pseudonymous installation identifier,
not a secret or authentication credential.

The host requests `gpt-5.6-luna` with Medium reasoning when that exact choice is
available. Chronos cannot change a task's model itself and does not silently
substitute a higher-cost model. This preference applies only to the Governor;
monitored tasks remain model-agnostic.

## Runtime Contract

The installed command surface is:

```powershell
# Compact state only
chronos.ps1 -Action supervise -SupervisionAction status

# Run only inside the selected Governor task
chronos.ps1 -Action supervise -SupervisionAction initialize
chronos.ps1 -Action supervise -SupervisionAction discover

# Only after host liveness verifies an ended entry is active again
chronos.ps1 -Action supervise -SupervisionAction confirm-active `
  -SupervisionSubjectId <task-or-agent-id>

# First returns the required host cleanup action; it does not clear ownership
chronos.ps1 -Action supervise -SupervisionAction release

# Run only after all matching recurrences are stopped and verified absent
chronos.ps1 -Action supervise -SupervisionAction release `
  -SupervisionConfirmRecurrenceStopped
```

The Governor reconciles `discover` results with host task tools. Host task state
is the liveness authority. Use the rotating `checkBatch`, which returns at most
eight entries and covers larger registries fairly over successive cycles.
Terminal hook state has precedence: a delayed asynchronous start cannot revive
an ended task or agent. Only `confirm-active`, after host verification, can do
that. Do not poll full transcripts, repeatedly read unchanged tasks, or send
routine messages to workers.

The Governor owns the only model recurrence. When the user enables recurring
supervision, reconcile one host Heartbeat automation attached to the dedicated
task. Use 60 minutes while monitored work is active and 360 minutes while idle.
A normal cycle ends silently. This bounds scheduled Governor turns to 24 per
active day or four per idle day; provider billing and caching remain host
concerns and Chronos makes no cost claim.

The registry reports `rotationRequired=true` after 336 cycles or 14 days. The
host must then perform a verified fresh-task handoff, preserving one recurrence,
or pause the recurrence and notify the user once. It must not continue adding
unbounded history to the same Governor task. Release is two phase: stop and
verify every matching recurrence first, then confirm local release. A failure
before confirmation preserves the claim so the next setup can reconcile it.

The PowerShell module does not create that automation or contact a task. It
returns local routing metadata for the Codex host to use.

## Local State

The default registry is:

```text
%LOCALAPPDATA%\Chronos\Supervision\session-registry.json
```

It is capped at 256 KiB and 256 retained records. Task and agent identifiers are
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

## Usage Boundary

Supervision adds one short local PowerShell process at task or subagent start
and end. It adds no per-turn model tokens and no worker recurrence. Only the
dedicated Governor uses a model on the disclosed bounded host cadence. The
deterministic supervision engine is model-agnostic; the bootstrap policy alone
prefers Luna Medium. A disabled or untrusted hook produces no registry event and
does not block work.

Official Codex hook behavior, plugin hook discovery, trust review, asynchronous
execution, and event fields are documented in [OpenAI Hooks](https://learn.chatgpt.com/docs/hooks).
