# Privacy Policy

Effective August 10, 2026

Chronos is an on-demand plugin that runs locally on the user's Windows computer.
Dravara, LLC publishes Chronos through its `FaxanFM` GitHub project account.

## Data handling

Chronos does not use analytics, advertising, telemetry, cookies, remote APIs,
or publisher-operated external storage. The local scripts make no network
requests. Dravara, LLC does not receive, sell, or share data through the
plugin.

When requested, Chronos reads local aggregate resource information needed to assess Codex health, such as process counts, memory use, CPU activity, handle counts, and available disk space. It also opens the known Codex diagnostic SQLite database in read-only mode to measure file allocation, reclaimable pages, WAL activity, insert-rate changes, and aggregate levels from up to 2,000 recent rows. Results remain in the active Codex task unless the user chooses to share them.

For token and quota diagnostics, Chronos traverses known session partitions for
at most three seconds, skips reparse points, retains the eight newest files
modified within the previous six hours, and reads at most 2 MiB from each
selected tail. It reports when the bounded inventory times out. It retains in
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

## Recipients

Chronos returns its compact summaries in the active Codex task. OpenAI may
process that task content under the terms and data controls for the user's
OpenAI account or workspace. Chronos does not send the underlying local files
or raw values to Dravara, LLC or another service.

If a user voluntarily opens a support issue, GitHub and the public repository
receive the information that the user chooses to post. The support instructions
tell users not to post raw records, credentials, source code, identifiers, or
local paths.

## User control

Health checks are read-only. Chronos does not create database triggers, delete
rows, run checkpoints, vacuum databases, or alter Codex state. Governor records
coordination status but never automatically merges, resets, cleans, deletes
worktrees or branches, closes Codex, terminates processes, or deletes user files.

## Retention

Chronos health inspection creates no persistent logs, user profiles, background
services, or scheduled tasks. Governor metadata remains local until the user or
Windows temporary-storage maintenance removes it. Chronos performs no automatic state or
workspace cleanup.

## Changes

Material changes to this policy will be published in this repository with a new effective date.

## Contact

Dravara, LLC is the publisher responsible for this policy. For privacy
questions, open an issue at https://github.com/FaxanFM/chronos/issues.
