<p align="center"><img src="assets/chronos-mark.png" width="180" alt="Chronos hourglass and process-tree mark"></p>

# Chronos for Codex - diagnostics, supervision, and read-task coordination

Chronos gives Windows Codex users one local Governor for passive task
supervision, actionable Heartbeats, exact-target intervention, and bounded
read-only worker coordination. It also diagnoses runaway auto-review, approval
loops, quota and context pressure, broken permission rules, rollout duplication,
diagnostic SQLite churn, and Windows process degradation. Routine worker tasks
stay passive. Chronos sends no publisher telemetry.

**[Install Chronos for Codex from the OpenAI Plugins Directory](https://chatgpt.com/plugins/plugins_6a79c882cf488191b8f62ee20e0e2571)**

Published by Dravara, LLC. The currently approved directory package is live for eligible
users, subject to region, supported surface, workspace controls, and role.
Directory publication is not an OpenAI endorsement. Use the Git marketplace
commands below only when the Directory is unavailable. Do not install both
sources: Codex treats `chronos@chronos` and
`chronos@openai-curated-remote` as separate source identities.

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
  outbox protect host delivery across restarts. One active intervention per
  target generation, compatible event coalescing, and a two-attempt limit prevent wake storms.
- Keeps isolated modest Governor-cycle overruns quiet. Only sustained or
  material runtime degradation backs off the collector, with the budget,
  baseline, overrun, classification, and decision exposed in compact status.
- Registers task activity and subagent lifecycle changes through five reviewed,
  headless hooks with no model-visible output or worker recurrence. Four run in
  the background; `SessionEnd` remains synchronous. Brief registry
  contention uses a bounded protected fallback that the next Governor status
  removes after merging.
- Reuses one host-verified Governor or creates one fresh history-free Governor
  task instead of automatically forking a working task.
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

Install from the Directory link above. As a fallback, install from Git:

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new Codex task after installation.

Chronos v0.9.1 checks valid cached source manifests on first use and separates
cached duplication from a confirmed enabled-source conflict. If it confirms
the running Directory package and enabled legacy Git source, remove the legacy
source through the Codex plugin manager, then start a fresh task:

```powershell
codex.cmd plugin remove chronos@chronos
codex.cmd plugin marketplace remove chronos
```

Chronos does not edit plugin configuration or cache files itself. A loaded task
catalog cannot be hot-swapped.

## Use

For complete setup, use the first starter prompt or ask:

```text
Set up Chronos fully on this PC. Verify the installed source, enable
supervision and Heartbeats in one dedicated Governor, and confirm one Governor
recurrence with zero worker recurrences. Keep routine worker tasks passive and
do not ask me to relay routine findings.
```

Chronos verifies the package source and native status, reuses or creates one
dedicated Governor, reconciles one host recurrence, enables due Heartbeat
evaluation there, and proves that worker tasks have no recurrence. Normal Codex
hook trust review is the only manual boundary. If hooks are not trusted, the
Governor still uses one complete host inventory as its safe discovery fallback.

For an on-demand diagnostic without enabling supervision, ask:

```text
Run a complete Chronos status. Separate machine health from workflow, quota,
approval, rule, SQLite, and supervision issues.
```

Review the packaged lifecycle hook once through Codex `/hooks`. Worker tasks
need no Chronos prompt and can use any runtime model. Setup explicitly enables
at most one Governor turn per hour while work is active and one every six hours
while idle. A stable random installation-scoped equivalence key, deterministic
winner order, and three-attempt reconciliation budget keep concurrent setups on
one PC on one Governor and one recurrence. Different PCs retain separate
Governors. Only its first two pulses repeat that scoped
check; normal cycles add no automation scan. Each cycle reconciles one compact
host task inventory, so disabled hooks do not require user registration or
message relay. The Governor rotates or pauses after 336 cycles or 14 days. See the
public [supervision contract](https://github.com/FaxanFM/chronos/blob/main/docs/SUPERVISION.md).

Heartbeats use the same Governor and recurrence created by full setup. See the
public [Heartbeat contract](https://github.com/FaxanFM/chronos/blob/main/docs/HEARTBEATS.md)
for the normalized collector schema, coverage rules, and host delivery contract.

The Codex host owns the recurring schedule, evaluator model, and delivery to the
Governor inbox. Chronos does not install a scheduler or service. Monitored tasks
can use any model and do not run Heartbeats. A cycle with no actionable
transition ends silently. For an actionable transition, the Governor verifies
one live affected task and sends one fixed, bounded instruction through host
task tools. It does not ask the user to relay routine remediation. The task's
reply does not resolve the event until independent evidence confirms the
postcondition. Governor self-usage changes only the Governor recurrence after
the host verifies the new cadence; it never creates a self-message or a routine
user chore. Chronos does not infer model cost or quota effect from a model name.

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
describe the current engineering controls and frozen calibration boundary.
The public [v0.7.0 audit response](https://github.com/FaxanFM/chronos/blob/main/docs/AUDIT-RESPONSE-2026-08-09.md)
separates fixed, contained, and deferred findings.
The public [v0.7.6 final audit response](https://github.com/FaxanFM/chronos/blob/main/docs/V0.7.6-FINAL-AUDIT-RESPONSE.md)
maps the focused v0.7.7 correctness repairs and validation boundary.

## Safety and privacy

- Inspector, Heartbeat, and Governor commands run when requested. After the
  user trusts the package, five silent hooks register task lifecycle,
  completed-turn activity, and subagent lifecycle.
- Does not transmit telemetry or retain raw prompts, responses, source, diffs,
  commands, tool output, credentials, usernames, or absolute paths. It retains
  only the bounded local pseudonymous coordination metadata described below.
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
- Creates no operating-system scheduled task, service, publisher telemetry, or
  persistent log. Five reviewed hooks write bounded lifecycle and
  completed-turn hints. The host creates one recurring Governor
  automation only after the user asks to enable supervision or Heartbeats.
  Setup reconciles duplicates, and release stops the recurrence before clearing
  local ownership.
- Stores lifecycle identifiers protected with current-user Windows DPAPI and
  does not store transcript or workspace paths. DPAPI does not isolate data from
  another process already running as that user. The temporary contention
  fallback uses the same protected or hashed metadata and no raw path.
- Stores one random, non-secret 128-bit installation ID with no machine-derived
  data so host reconciliation remains scoped to this PC after registry recovery.
- Heartbeat evaluation stores bounded per-scope transition, coverage, cadence,
  deduplication, hashed delivery/outbox, intervention, and health metadata. It does not persist raw snapshots,
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
