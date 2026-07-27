# Privacy Policy

Effective July 27, 2026

Chronos is an on-demand plugin that runs locally on the user's Windows computer.

## Data handling

Chronos does not collect, transmit, sell, or share personal data. It does not use analytics, advertising, telemetry, cookies, remote APIs, or external storage.

When requested, Chronos reads local aggregate resource information needed to assess Codex health, such as process counts, memory use, CPU activity, handle counts, and available disk space. It also opens the known Codex diagnostic SQLite database in read-only mode to measure file allocation, reclaimable pages, WAL activity, insert-rate changes, and aggregate levels from up to 2,000 recent rows. Results remain in the active Codex task unless the user chooses to share them.

Chronos does not read SQLite log bodies, prompts, responses, tool output, process arguments, environment variables, user documents, browsing data, credentials, or unrelated file contents.

## User control

Health checks are read-only. Chronos does not create database triggers, delete rows, run checkpoints, vacuum databases, or alter Codex state. Any optional process cleanup requires clear user confirmation before it runs. Chronos does not automatically close the Codex desktop application or delete user files.

## Retention

Chronos creates no persistent logs, user profiles, background services, or scheduled tasks.

## Changes

Material changes to this policy will be published in this repository with a new effective date.

## Contact

For privacy questions, open an issue at https://github.com/FaxanFM/chronos/issues.
