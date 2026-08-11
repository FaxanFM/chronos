<p align="center"><img src="assets/chronos-mark.png" width="180" alt="Chronos hourglass and process-tree mark"></p>

# Chronos for Codex - diagnostics, heartbeats, and read-task coordination

Detect runaway Codex auto-review, approval loops, quota and context
amplification, broken permission rules, rollout duplication, diagnostic SQLite
churn, and Windows process degradation. Chronos keeps machine health separate
from workflow diagnostics, detects meaningful changes during long-running work,
and coordinates bounded read tasks without creating an autonomous agent loop.

**[Install Chronos for Codex from the OpenAI Plugins Directory](https://chatgpt.com/plugins/plugins_6a79c882cf488191b8f62ee20e0e2571)**

Published by Dravara, LLC. The currently approved directory package is live for eligible
users, subject to region, supported surface, workspace controls, and role.
Directory publication is not an OpenAI endorsement. Use the public marketplace
commands below only as a fallback.

## What it does

- Reports machine health separately from resource, quota, rule, and overall diagnostic levels.
- Identifies resource accumulation associated with long-running Codex degradation.
- Detects high-frequency Codex SQLite log churn and unreclaimed database space.
- Warns when the Windows filesystem helper is degrading and advises a full PC
  restart when the helper becomes unusable.
- Separates cached reads from cache writes only when the runtime exposes that field and flags quota
  amplification from large contexts, high reasoning, subagents, and repeated
  compaction.
- Counts actual automatic-review turns from structured `turn_context` records,
  distinguishes them from bookkeeping, and reports only bounded aggregate review
  and rollout-growth observations.
- Separates approval persistence failures, repeated permission-rule misses, and
  legitimate boundary volume; reports reviewer escalations without calling them
  recursion unless nested reviewer lineage is directly observed.
- Audits brittle, overbroad, and credential-shaped Codex permission rules
  without returning rule text or values, and measures full-history worker forks,
  effort, task age, and lineage concentration.
- Recommends the safest next step for the current condition.
- Evaluates eight opt-in Heartbeat families and emits an event only for an
  actionable transition or material worsening. Stable event IDs and a bounded
  acknowledged outbox protect host delivery across restarts.
- Routes bounded exploration, review, and verification to read workers. Shared-folder write delegation is disabled.
- Discovers worker models from the active runtime instead of assuming a model.
- Coordinates canonical workspace identity, fenced expiring advisory leases,
  attempt budgets, Git-visible read-mutation checks, and final coordinator verification.

Chronos mitigates local symptoms. It does not change SQLite rows or schemas,
terminate Codex or unrelated user processes, or block active work. Governor can
stop only the bounded Git subprocess it started when fingerprinting exceeds its
time or byte limit. Its logical read-only SQLite
connection can create or update SQLite `-wal` or `-shm` coordination sidecars;
the result reports whether that activity was observed.

## Install in Codex

Install it from its public marketplace:

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new Codex task after installation.

## Use

Ask Codex:

```text
Use Chronos to inspect current Codex resource health.
```

Chronos reports the current condition and recommends a proportionate response.

For long-running or asynchronous work, ask:

```text
Enable Chronos Heartbeats in one Governor task using GPT-5.6 Luna with Medium reasoning.
Monitor the other tasks without waking them unless Governor decides intervention is needed.
```

See the public [Heartbeat contract](https://github.com/FaxanFM/chronos/blob/main/docs/HEARTBEATS.md)
for the normalized collector schema, coverage rules, and host delivery contract.

The Codex host owns the recurring schedule, evaluator model, and delivery to the
Governor inbox. Chronos does not install a scheduler or service. Monitored tasks
can use any model and do not run Heartbeats. A cycle with no actionable
transition ends silently. The host deduplicates and acknowledges emitted
`EventId` values. Any forwarding to an owner is an explicit host decision.

To delegate a small repository task, ask:

```text
Use Chronos Governor to delegate this bounded low-complexity task.
```

Governor validates the worker models advertised by the active runtime and
selects deterministically from that inventory. It sends focused read-only
assignments with `fork_turns=none`. It is a coordination aid, not a sandbox or
security boundary; all edits, integration, publishing, and final acceptance
remain with the coordinator.

See the public [Codex Token and Quota Findings](https://github.com/FaxanFM/chronos/blob/main/docs/TOKEN-QUOTA-FINDINGS.md)
for the source-backed GPT-5.6 findings and conservative local settings.
See the public [Efficiency Governor](https://github.com/FaxanFM/chronos/blob/main/docs/EFFICIENCY-GOVERNOR.md)
for bounded approval-review and rollout-amplification observations, their coverage
rules, and hard safety limits.
See the public [Builder Requirements](https://github.com/FaxanFM/chronos/blob/main/docs/BUILDER-REQUIREMENTS.md)
for the consolidated handoff ledger and explicit unavailable and calibration
boundaries.
See the public [Chronos Governor](https://github.com/FaxanFM/chronos/blob/main/docs/CHRONOS-GOVERNOR.md)
guide for routing, limits, contracts, state, and verification behavior.
The public [architecture](https://github.com/FaxanFM/chronos/blob/main/docs/ARCHITECTURE.md),
[test coverage](https://github.com/FaxanFM/chronos/blob/main/docs/TEST-COVERAGE.md),
[release operations](https://github.com/FaxanFM/chronos/blob/main/docs/OPERATIONS.md),
and [calibration methodology](https://github.com/FaxanFM/chronos/blob/main/docs/CALIBRATION-METHODOLOGY.md)
describe the v0.7.1 engineering controls.
The public [v0.7.0 audit response](https://github.com/FaxanFM/chronos/blob/main/docs/AUDIT-RESPONSE-2026-08-09.md)
separates fixed, contained, and deferred findings.
The public [v0.7.6 final audit response](https://github.com/FaxanFM/chronos/blob/main/docs/V0.7.6-FINAL-AUDIT-RESPONSE.md)
maps the focused v0.7.7 correctness repairs and validation boundary.

## Safety and privacy

- Runs only when requested.
- Does not collect, transmit, or retain prompts, responses, source, diffs,
  commands, tool output, credentials, usernames, absolute paths, or personal data.
- Never blocks, pauses, or ends a Codex task.
- Never terminates Codex or unrelated user processes and never deletes user
  files. Governor can stop only its own bounded Git fingerprint subprocess.
- Opens the known Codex diagnostic database in logical read-only mode and never
  installs triggers, deletes rows, checkpoints, or vacuums it. SQLite can still
  create or update `-wal` or `-shm` coordination sidecars, which Chronos reports.
- Reads bounded 2 MiB tails of up to eight recently active rollout files selected by modification time for
  structured aggregate token, effort, automatic-review, compaction, subagent,
  rollout-duplication, and parser-integrity
  counts.
- Reads supported files only in the known Codex rules directory to return
  aggregate rule-health and secret-shape counts; rule text, prefixes, hashes,
  assignments, and values are never returned.
- Never returns prompts, responses, tool arguments, tool output, usernames, or
  absolute local paths. Governor verification may return repository-relative changed paths.
- Creates no recurring task, service, publisher telemetry, or persistent log. The host
  creates a recurring automation only after the user asks for one.
- Heartbeat evaluation stores bounded per-scope transition, coverage, cadence,
  deduplication, hashed delivery/outbox, and health metadata. It does not persist raw snapshots,
  prompts, responses, commands, source, paths, credentials, or tool output.
- When Governor is invoked, stores only untrusted local coordination metadata beneath the
  current user's Windows temporary application-data directory: opaque IDs, identity hashes, base
  commit, relative scopes, model labels, lease fencing, counters, status, and
  timestamps.
- Governor shared-folder write delegation is disabled; read-only checks cover a
  Git-visible projection and do not prove that no other filesystem effect occurred.
- Never automatically merges, resets, cleans, deletes worktrees or branches, or
  accepts a worker result without coordinator verification.

See the public [Privacy](https://github.com/FaxanFM/chronos/blob/main/PRIVACY.md), [Terms](https://github.com/FaxanFM/chronos/blob/main/TERMS.md), and [Support](https://github.com/FaxanFM/chronos/blob/main/SUPPORT.md) pages.

## License

MIT
