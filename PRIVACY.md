# Privacy Policy

Effective August 11, 2026

Chronos is a local Windows plugin. Health inspection and Heartbeat evaluation
run on demand. Four reviewed lifecycle hooks can record bounded task and
subagent start or end hints after the user trusts their exact definition.
Dravara, LLC publishes Chronos through its `FaxanFM` GitHub project account.

## Data handling

Chronos does not use analytics, advertising, telemetry, cookies, remote APIs,
or publisher-operated external storage. The local scripts make no network
requests. Dravara, LLC does not receive, sell, or share data through the
plugin.

When requested, Chronos reads local aggregate resource information needed to assess Codex health, such as process counts, memory use, CPU activity, handle counts, and available disk space. It opens the known Codex diagnostic SQLite database in logical read-only mode to measure file allocation, reclaimable pages, WAL activity, insert-rate changes, and aggregate levels from up to 2,000 recent rows. It does not change rows or schemas. SQLite can create or update `-wal` or `-shm` coordination sidecars while opening a WAL-mode database, even with a read-only database handle. Chronos reports the open mode, journal mode, whether sidecar mutation was possible, and whether it observed such activity. Results remain in the active Codex task unless the user chooses to share them.

For token and quota diagnostics, Chronos traverses known session partitions
with a three-second target and a 20,000-entry hard cap, skips reparse points,
retains the eight newest files
modified within the previous six hours, and reads at most 2 MiB from each
selected tail. It reports when the inventory reaches the time or entry cap.
An individual Windows filesystem call can delay completion beyond the target.
It retains in
memory only structured
aggregate token counts, model and reasoning-effort labels, context-window size,
automatic-review counts, categorical approval fields, and counts or byte totals
for compactions, `spawn_agent` calls, lineage links, and exact cross-rollout
record hashes. For structured approval and worker records, Chronos may inspect
a bounded proposed-prefix array, approval correlation identifier,
sandbox-permission category, `fork_turns`, worker effort, and task-complexity
label. It converts prefixes and identifiers to ephemeral hashes and returns
only counts and safe categories. Ephemeral hashes are discarded when the
inspection exits. Chronos does not return or persist raw rollout lines, thread
IDs, approval IDs, prompts, responses, commands, prefixes, tool arguments, tool
output, usernames, or absolute paths.

Chronos also reads at most 2 MiB from each of up to 32 supported `.rules` or
`.toml` files in the known local Codex rules directory when an inspection is
requested. Reparse files are rejected. A bounded lexical parser identifies up
to 2,048 multiline rules across all selected files, ignores comments and quoted
examples, and reports incomplete coverage. Chronos counts rule
length, literal length, narrow-prefix structure, broad interpreter structure,
and credential-shaped patterns in memory. It never returns rule text, rule
hashes, command literals, environment assignments, or credential-shaped
values. This is detection only; Chronos never edits a rule or rotates a
credential.

Chronos does not read SQLite log bodies, process arguments, live environment variables, user documents, browsing data, or unrelated file contents. A credential-shaped value embedded in a Codex rule can be pattern-matched solely to return a count; the value is never displayed, persisted, or transmitted.

When the user explicitly invokes Chronos Governor, it stores limited, untrusted local
coordination metadata beneath the current user's Windows temporary
application-data directory, keyed by a hash of Git's canonical common
directory. This may include
opaque task and worker identifiers, a hash of the repository location, a base
commit, repository-relative scopes, access mode, requested or reported model
labels, reasoning effort, status, counters, and timestamps. Governor state does
not contain assignment text, objectives, prompts, responses, source code, diffs,
commands, tool arguments, tool output, environment variables, credentials,
usernames, or absolute paths. It is not transmitted by Chronos.
Governor verification may return repository-relative changed paths when its
advisory read-mutation check fails. Shared-folder write delegation is disabled.

When the user trusts the packaged Chronos lifecycle hooks, they run only when a
Codex task or subagent starts or ends. The hook receives the host event object
but does not read or retain its transcript path. It stores task and agent
identifiers protected with Windows DPAPI for the current user, SHA-256 indexes,
workspace hashes, safe model slugs, lifecycle state, counters, and timestamps
in a bounded file beneath the user's local application-data directory. DPAPI
protects the ciphertext for that Windows user; it is not a defense against a
different process already running as the same user. It does not store raw
workspace paths, prompts, responses, source code, diffs, commands, tool
arguments, tool output, credentials, or usernames. The local Governor can
decrypt an identifier for host task routing, so that ID can enter the Governor
task or host-tool context; Chronos does not transmit it to its publisher.

Supervision also stores `installation-scope.json`, containing only schema
version `1` and one random 128-bit lowercase hexadecimal ID. The ID scopes one
Governor to one local installation and survives deletion of the session
registry. It is a persistent pseudonymous identifier, not a secret. It contains
no hostname, username, Windows SID, machine GUID, path, task ID, or workspace
data. The complete scoped key can enter the Governor assignment and host
automation metadata so simultaneous setup attempts on that installation agree.
Different installations generate different IDs.

Lifecycle hooks do not run for every turn, prompt, tool call, or approval. They
return no model-visible output and make no network request. If a hook is
disabled, untrusted, malformed, or unable to write, it exits without blocking
the Codex task. Brief registry contention can create one temporary fallback
entry with the same DPAPI-protected identifiers, hashed workspace, safe labels,
event category, and timestamp. Each entry is limited to 4 KiB and the queue to
256 entries. The next hook or Governor status merges valid entries and removes
them. No entry contains a raw path, transcript, prompt, response, or source
content.

When the user explicitly enables or runs Chronos Heartbeats, the Codex host can
supply a bounded normalized snapshot containing safe counters, status values,
timestamps, coverage labels, and opaque task, machine, agent, or route
identifiers. The local Heartbeat engine validates and compares that snapshot. It
rejects credential-shaped values, Windows or Unix absolute-path identifiers,
and slash-rooted identifiers outside the canonical `/root` Codex worker form. It
persists only bounded transition, cadence, coverage, deduplication,
delivery/outbox, intervention, and engine-health metadata in a per-scope file beneath the user's local Chronos
application-data directory. Raw collector snapshots, prompts, responses, source
code, diffs, commands, tool arguments, tool output, credentials, usernames, and
absolute paths are not persisted.

The Heartbeat PowerShell code does not create a scheduler, call a model, send a
message, or make a network request. It sends no publisher telemetry. It emits a
concise event to one Governor inbox only when an actionable condition appears,
resolves, or worsens materially. The Codex-host Governor can use host task tools
to send one fixed-template intervention to one exact verified affected task.
It does not broadcast or give every task a recurrence. That direct message and
the task's reply exist in the Governor and affected task contexts under the
user's OpenAI account or workspace controls; they are not sent to the publisher.
A cycle with no actionable transition ends without output.
Stable SHA-256 identifiers in local state are pseudonymous metadata, not
anonymous data. Unacknowledged event records contain hashes, type, severity,
timestamps, delivery attempts, and route class; they do not contain raw owner,
task, subject, or route IDs.
Intervention records contain hashed target and generation identifiers, event and
condition hashes, allowlisted state and action categories, attempt counters, and
timestamps. Claim tokens are stored only as hashes. Raw task IDs are transient
host routing handles and are not written to Heartbeat state. Task replies are
reduced to bounded categories; free-form reply text is not persisted.

## Recipients

Chronos returns its compact summaries in the active Codex task. The supported
Heartbeat topology returns events in the dedicated Governor task. When a fixed
intervention is required, the host also delivers it to the exact affected task.
OpenAI may process that task content, the intervention, its categorical reply,
and any host-delivered follow-up under
the terms and data controls for the user's OpenAI account or workspace. Chronos
does not send the underlying local files or raw values to Dravara, LLC or
another service.

If a user voluntarily opens a support issue, GitHub and the public repository
receive the information that the user chooses to post. The support instructions
tell users not to post raw records, credentials, source code, identifiers, or
local paths.

## User control

Health checks are logical read-only with respect to SQLite content. Chronos does
not create database triggers, delete rows, run checkpoints, vacuum databases,
or alter Codex application records. SQLite coordination sidecars can still be
created or updated as described above. Governor records
coordination status but never automatically merges, resets, cleans, deletes
worktrees or branches, closes Codex, terminates Codex or unrelated user
processes, or deletes user files. Governor can terminate only the Git subprocess
it started when bounded fingerprinting exceeds its time or byte limit.

## Retention

Chronos health inspection creates no persistent logs, user profiles, background
services, or operating-system scheduled tasks. Governor and passive-supervision
metadata remain local until the user removes them or local application-data
maintenance does so. Heartbeat transition state
remains local until the user removes it or local application-data maintenance
does so. Chronos performs no automatic workspace cleanup. The plugin does not
create or retain a host automation when Heartbeats are not explicitly enabled.
When enabled, the Codex host reconciles one named Governor recurrence. The
default is at most 24 Governor turns per active day or four per idle day. It is
rotated or paused after 336 cycles or 14 days. Worker tasks receive no recurring
turns. Release stops and verifies the recurrence before local ownership clears.

## Changes

Material changes to this policy will be published in this repository with a new effective date.

## Contact

Dravara, LLC is the publisher responsible for this policy. For privacy
questions, open an issue at https://github.com/FaxanFM/chronos/issues.
