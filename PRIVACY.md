# Privacy Policy

Effective October 18, 2026, including the v0.10.0 candidate's Control Room.
See the README's Current Versions for edition availability.

Chronos includes a local Control Room; its legacy diagnostic components run on
Windows. Health inspection and Heartbeat evaluation
run when invoked with the user's authorization. Automatic Inspector diagnostics
require separate standing permission; a one-off briefing does not grant it.
Five reviewed monitoring hooks can record bounded task
lifecycle, completed-turn activity, and subagent lifecycle hints after the user
trusts their exact definition.
Dravara, LLC publishes Chronos through its `FaxanFM` GitHub project account.

## Data handling

Chronos uses no publisher analytics, advertising, telemetry or publisher-operated
external storage. Dravara, LLC does not receive, sell or share runtime data through
the plugin. The legacy native diagnostic scripts make no network requests.
Control Room uses loopback HTTP and a local session cookie; its Codex workers
use the configured model provider as described below.

### Control Room

Control Room starts a user-requested local process. Its private loopback URL
contains an access token, removed from browser history after opening. An
HttpOnly same-site cookie supports reloads. Session/launcher metadata and private
logs remain in the selected Codex profile or explicit local state directory;
do not share launch links or raw state. Same-user software may access these
files. No server command, hook patch or publisher account is required.

The local queue stores plaintext assignments, selected and managed thread IDs,
workspace paths, bounded result summaries, verification commands/receipts and
bounded native execution aggregates. Worktrees contain the work's actual files.
Execution aggregates include observed native item counts, explicit failure
signals and turn wall time, not captured command arguments, transcripts, model
costs or inferred token usage. Optional learning stages receive only the
accepted evidence/artifacts explicitly selected for their work.

When a managed task runs, its instructions, selected thread context and relevant
workspace data are processed by Codex's configured provider under the user's
account and policies. Provider web search is an optional per-stage capability;
model usage consumes the user's allowance or configured billing. Chronos does
not collect an API key or copy login credentials. Existing installed Codex
authentication is used by its local runtime.

Queue records, private metadata and worktrees remain until removed by the user
or operating system. Disconnect/restart revoke session execution permission.
Stop Control Room stops its owned runtime, not unrelated Codex processes. Queue
archive does not delete worktree files. Learning recommendations do not train
models or silently change active workflows or permissions.

### Legacy Windows Diagnostics

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
inspection exits. This Inspector diagnostic path does not return or persist raw rollout lines, thread
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

Chronos does not read SQLite log bodies, process arguments, other processes'
environment variables, user documents, browsing data, or unrelated file
contents. Its own process reads installation and temporary-directory settings
such as `CODEX_HOME` to resolve the local state boundary. A credential-shaped
value embedded in a Codex rule can be pattern-matched solely to return a count;
the value is never displayed, persisted, or transmitted.

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

When the user trusts the packaged Chronos hooks and Codex dispatches them, they
run when a task or subagent starts or ends and once after a main-task turn
completes. The hook
receives the host event object but does not read or retain its transcript path,
assistant message, prompt, or tool data. It stores task and agent
identifiers protected with Windows DPAPI for the current user, SHA-256 indexes,
workspace hashes, safe model slugs, lifecycle state, counters, and timestamps
in a bounded file beneath the user's Windows temporary Chronos directory. A
valid legacy LocalAppData registry and installation-scope anchor can be imported
during an upgrade. DPAPI
protects the ciphertext for that Windows user; it is not a defense against a
different process already running as the same user. It does not store raw
workspace paths, prompts, responses, source code, diffs, commands, tool
arguments, tool output, credentials, or usernames. The local Governor can
decrypt an identifier for host task routing, so that ID can enter the Governor
task or host-tool context; Chronos does not transmit it to its publisher.

Hook metadata includes unsalted SHA-256 hashes of the Windows account SID and
workspace path. Someone who can guess a value can test it against the hash;
these values are pseudonymous, not anonymous. No raw SID or workspace path is
stored in the hook record.

Supervision also stores `installation-scope.json`, containing only schema
version `1` and one 128-bit lowercase hexadecimal ID. A new v3 installation
derives the ID from a SHA-256 hash of the local machine name and canonical Codex
home. A readable earlier random anchor is imported unchanged so an upgrade does
not orphan its Governor. The raw machine name and Codex-home path are not stored.
Chronos uses a nonempty `CODEX_HOME` when supplied and otherwise uses the
current user's `.codex` directory. It exposes only a truncated hash of that
canonical identity in status. An invalid or inaccessible override is rejected
before any registry, Heartbeat state, claim, or mutex-owned record is created.

### Local State Locations

`T` is the Windows process temporary directory; `L` is Windows LocalAppData.
Supervision `H` is SHA-256 of uppercase machine name, `|`, and uppercase
canonical Codex home. Heartbeat `B` hashes the JSON-serialized equivalent
scope string. Repository `R` hashes Git's canonical common directory in lowercase.

| Location | Contents and ownership boundary |
| --- | --- |
| `T\Chronos-Supervision-v3-<first24 H>-<0..3>\` | Current bounded recovery slots: registry, installation anchor, pending subdirectory |
| `T\Chronos-Supervision-Inbox-v1-<first24 H>\` | Current home's pending hook receipts |
| `T\Chronos\Supervision-v2\<prior H>\` | Earlier machine/home casing, registry and anchor |
| `T\Chronos\Supervision\`, `L\Chronos\Supervision\` | Pre-home-isolation legacy registry/anchor; selected only for the actual default home |
| `T\Chronos\Heartbeat-v2\<B>\` | Current Heartbeat evaluation, delivery and collector metadata |
| `T\Chronos\Heartbeat\<prior B>\`, `L\Chronos\Heartbeat\<prior B>\`, prior v2 hashes | Legacy default-home scopes, including original CWD where applicable |
| `T\Chronos\Governor\<R>\` | Repository lease state and backup; explicit repository selection required |
| `<Git common directory>\chronos\` | Legacy repository lease state; explicit repository selection required |

An explicit full-removal request may erase only selected Chronos metadata with
the native `data-plan`/`data-remove` protocol before plugin-manager uninstall.
Unknown entries, links, changed plans and active leases fail closed. Other homes
and repositories remain untouched. Old CWD scopes require that original working
directory; unknown historical scopes are retained, not falsely reported erased.
Chat history, Codex logs, plugin-manager/trust records and downloaded release
archives are not erased by this command. Local removal plans contain paths and
file hashes for private review; do not post them in public support reports.
The validation rejects a reparse point in any path component, including an
ancestor junction. Unscoped legacy state and installation anchors are eligible
only for the default `.codex` home. Explicit or environment-provided homes do
not import them; separate homes cannot clone one legacy identity or pending
Heartbeat outbox. Eligible imports read the source without modifying it.
The pseudonymous ID scopes one Governor to one local installation and remains
stable when Chronos selects another bounded writable state slot after a sandbox
restart. It is not a secret. It contains no raw hostname, username, Windows SID,
machine GUID, path, task ID, or workspace data. The complete scoped key can enter
the Governor assignment and host automation metadata so simultaneous setup
attempts on that installation agree.

Chronos does not install prompt, permission, or tool hooks. All five configured
handlers finish synchronously with a three-second host timeout. The `Stop`
handler records only a SHA-256 turn hash and bounded activity counters
after each completed main-task turn. The hooks return no model-visible output,
make no network request, and do not start a model turn. If a hook is
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
delivery/outbox, intervention, and engine-health metadata in a per-scope file beneath the user's Windows temporary Chronos
directory. New state retains the current user's inherited TEMP permissions;
Chronos does not bind the directory to a transient sandbox identity. Valid
readable prior state can be imported during an upgrade. Inaccessible prior state
is left unchanged while Chronos starts in its new versioned namespace. Raw
collector snapshots, prompts, responses, source
code, diffs, commands, tool arguments, tool output, credentials, usernames, and
absolute paths are not persisted.
Compact migration status can report that a prior scoped directory was
unavailable and preserved and that Chronos attempted no prior-state write. It
does not expose the path, owner, ACL, file names, or contents and does not claim
independent verification of data it could not read.

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

Installing or updating the separate GitHub edition requires network requests
to GitHub through the user's browser or plugin manager. GitHub can process
request metadata under its own privacy policy. This is distribution traffic,
not a Chronos runtime telemetry channel. A public repository does not give its
publisher a feed of users' local installs, task identifiers, chats, or diagnostic
records through Chronos. The publisher can see information users voluntarily
make public, such as issues or stars, and any aggregate repository statistics
GitHub provides. Do not interpret "no publisher telemetry" as "no provider
processes data."

## Onboarding choices

The setup conversation explains scope, local storage, provider processing,
and recurring model usage before asking for monitoring consent. Recurring
governance, optional GitHub hooks, and a diagnostic briefing are distinct choices.
Declining hooks or diagnostics does not prevent supported core governance.
Choices and a compact setup receipt remain in the user's Codex conversation;
Chronos creates no separate consent analytics log or publisher-side profile.
Hook review is not install consent, and installation is not hook trust. Codex
requires the user to review and trust the current hook definition. A material
definition change can require renewed trust. Missing execution evidence remains
unobserved. Marketplace approval for a skills-only package does not cover an
independent GitHub hook installation; an unverified marketplace install route
is not automated by onboarding.

## User control

Users can choose on-demand checks, pause an identified Governor recurrence,
disable optional hooks through Codex's controls, or uninstall through the plugin
manager. Pausing a recurrence stops scheduled Governor turns, not hooks;
disabling hooks stops new hook evidence, not a previously enabled recurrence.
Uninstalling or disabling does not promise deletion of existing local metadata,
Codex conversations, or GitHub activity. Local-state removal is a separate
explicit request, performed only after relevant recurrences and hooks are stopped
and the exact installation scope is verified. Users retain control of support
sharing; onboarding never uploads a report automatically.

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
services, or operating-system scheduled tasks. Governor, passive-supervision,
and Heartbeat transition metadata remain in the current user's Windows
temporary Chronos directory until the user or operating-system temporary-file
maintenance removes them. Chronos performs no automatic workspace cleanup. The plugin does not
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
