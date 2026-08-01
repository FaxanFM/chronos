# Privacy Policy

Effective August 1, 2026

Chronos is an on-demand plugin that runs locally on the user's Windows computer.

## Data handling

Chronos does not collect, transmit, sell, or share personal data. It does not use analytics, advertising, telemetry, cookies, remote APIs, or external storage.

When requested, Chronos reads local aggregate resource information needed to assess Codex health, such as process counts, memory use, CPU activity, handle counts, and available disk space. It also opens the known Codex diagnostic SQLite database in read-only mode to measure file allocation, reclaimable pages, WAL activity, insert-rate changes, and aggregate levels from up to 2,000 recent rows. Results remain in the active Codex task unless the user chooses to share them.

For token and quota diagnostics, Chronos reads at most 2 MiB from the tail of each of up to eight Codex rollout files modified in the previous six hours. It retains only structured aggregate token counts, model and reasoning-effort labels, context-window size, and counts of compactions and `spawn_agent` calls. It does not return or retain raw rollout lines, prompts, responses, tool arguments, tool output, usernames, or local paths.

Chronos does not read SQLite log bodies, process arguments, environment variables, user documents, browsing data, credentials, or unrelated file contents.

When the user explicitly invokes Chronos Governor, it stores limited local
coordination metadata beneath the current user's Windows temporary
application-data directory, keyed by a hash of Git's canonical common
directory. This may include
opaque task and worker identifiers, a hash of the repository location, a base
commit, repository-relative scopes, access mode, requested or reported model
labels, reasoning effort, status, counters, and timestamps. Governor state does
not contain assignment text, objectives, prompts, responses, source code, diffs,
commands, tool arguments, tool output, environment variables, credentials,
usernames, or absolute paths. It is not transmitted by Chronos.

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

For privacy questions, open an issue at https://github.com/FaxanFM/chronos/issues.
