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

It also scans only the tail of recent, known Codex `sandbox*.log` files for two
exact filesystem-helper failure markers. It returns aggregate booleans and
never returns log text or paths.

Interpret the result:

- `HEALTHY`: continue normally.
- `WARNING`: recommend reducing concurrency when convenient.
- `CRITICAL`: recommend saving active work and restarting Codex at a convenient
  checkpoint.

Every status is advisory. After reporting it, continue the user's requested
work unless the user independently asks to pause. Never use a Chronos status to
refuse, suspend, cancel, or stop a Codex task.

Interpret the filesystem-helper fields separately:

- `fsHelper=WARNING`: warn that the helper is degrading and recommend saving
  work before relying on more sandboxed file operations.
- `fsHelper=CRITICAL` with `pcRestartAdvised=true`: advise a full Windows
  restart at a convenient checkpoint after work is saved. Continue the task if
  the user chooses not to restart yet.

Treat `logDb=WARNING` or `logDb=CRITICAL` as a product-level diagnostic-log
churn condition. Explain that sequence counts demonstrate row churn, not exact
physical SSD writes or confirmed drive damage.

## Legacy actions

Older Chronos versions exposed `plan` and `cleanup` actions. They remain
accepted for command compatibility, but they are advisory-only:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<skill-root>\scripts\chronos.ps1" -Action plan
```

`plan` reports only a candidate count. `cleanup`, including `cleanup -Force`,
is disabled and always stops zero processes. Do not attempt an alternative
process-termination command.

## Safety

- Never block, pause, or end a Codex task based on a Chronos result.
- Never terminate any process.
- Never delete logs, caches, worktrees, or user data.
- Never create SQLite triggers, delete rows, checkpoint, vacuum, or otherwise
  modify Codex databases.
- Never expose usernames, local paths, arguments, environment values, or unrelated process details.

Chronos mitigates symptoms; it cannot patch an internal Codex lifecycle defect. Restarting Codex remains the reliable recovery when app-owned helpers or handles remain elevated.
