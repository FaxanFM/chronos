---
name: chronos
description: Detect and mitigate Codex process, CPU, memory, handle, disk, and diagnostic SQLite log degradation on Windows. Use when Codex or the PC is lagging, when logs_2.sqlite is growing or writing heavily, when several tasks or goals have run for hours or days, or before and after long-running parallel work.
---

# Chronos

Keep this skill lean and on-demand. Do not create a scheduler, daemon, recurring automation, telemetry file, or persistent log.

Before running Chronos, resolve `<skill-root>` to the directory containing this `SKILL.md`. Do not assume the user's workspace is the skill directory and do not search the whole disk.

## Run an inspection

Inspect only when lag is reported, before extending an already long-running session, or when long-running parallel work finishes:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action inspect
```

Return only the compact `CHRONOS` summary unless details are requested. Do not paste raw process tables into the conversation.

The inspection opens only the exact Codex `logs_2.sqlite` database in read-only
mode. It reports database size, reclaimable freelist space, WAL activity,
sequence movement, and the aggregate TRACE percentage from up to 2,000 recent
rows. It never reads log bodies.

Interpret the result:

- `HEALTHY`: continue normally.
- `WARNING`: reduce concurrency and avoid spawning more REPLs or command runners.
- `CRITICAL`: stop starting new work and recommend a Codex restart after active work is saved.

Treat `logDb=WARNING` or `logDb=CRITICAL` as a product-level diagnostic-log
churn condition. Explain that sequence counts demonstrate row churn, not exact
physical SSD writes or confirmed drive damage.

## Optional cleanup

First create a plan:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action plan
```

Candidates are limited to exact `node_repl` and `codex-command-runner-*` processes that are at least 60 minutes old and idle during a two-second sample. Never terminate `Codex`, `codex`, or unrelated processes.

Show the candidate count and ask for explicit approval. Only after approval run:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action cleanup -Force
```

Re-run `inspect` and report before/after totals. Do not loop cleanup attempts. If degradation remains, recommend restarting Codex.

## Safety

- Never clean up during an active tool call.
- Never terminate the Codex desktop process automatically.
- Never delete logs, caches, worktrees, or user data.
- Never create SQLite triggers, delete rows, checkpoint, vacuum, or otherwise
  modify Codex databases.
- Never expose usernames, local paths, arguments, environment values, or unrelated process details.

Chronos mitigates symptoms; it cannot patch an internal Codex lifecycle defect. Restarting Codex remains the reliable recovery when app-owned helpers or handles remain elevated.
