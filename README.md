# Chronos for Codex - diagnostics, supervision, and read-task coordination

[![Release](https://img.shields.io/github/v/release/FaxanFM/chronos?label=release)](https://github.com/FaxanFM/chronos/releases/latest)
[![Test](https://github.com/FaxanFM/chronos/actions/workflows/test.yml/badge.svg)](https://github.com/FaxanFM/chronos/actions/workflows/test.yml)
[![License](https://img.shields.io/github/license/FaxanFM/chronos)](LICENSE)
![No publisher telemetry](https://img.shields.io/badge/publisher_telemetry-none-4ed7a0)

Detect runaway Codex auto-review, approval loops, quota and context
amplification, broken permission rules, rollout duplication, diagnostic SQLite
churn, and Windows process degradation. Chronos keeps machine health separate
from workflow diagnostics, detects meaningful changes during long-running work,
and coordinates bounded read tasks without creating an autonomous agent loop.

Chronos is published by Dravara, LLC. `FaxanFM` is the GitHub project account
used to develop and distribute it.

**[Install Chronos for Codex from the OpenAI Plugins Directory](https://chatgpt.com/plugins/plugins_6a79c882cf488191b8f62ee20e0e2571)**

The currently approved directory package is live. Chronos is available to eligible users
across plans, including Free, subject to region, supported surface, workspace
controls, and role. Directory publication permits distribution; it is not an
OpenAI endorsement or support commitment.

Manual marketplace fallback:

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new Codex task, then ask: `Use Chronos to inspect current Codex health.`

<p align="center"><img src="assets/chronos-proof-card.png" width="500" alt="Sanitized example Chronos output separating healthy machine resources from runaway automatic review and approval persistence"></p>

The image is a synthetic, sanitized example. It contains no machine, account,
task, repository, or session identifiers.

## Share safely

Chronos sends no install, usage, or diagnostic telemetry to its publisher or a
third party. Its bounded local state is described below. Public signals are
always opt-in:

- [Star Chronos for Codex](https://github.com/FaxanFM/chronos)
- [Share the local-only release on X](https://twitter.com/intent/tweet?text=Chronos%20for%20Codex%20diagnoses%20Windows%20slowdown%2C%20approval%20loops%2C%20quota%2Fcontext%20pressure%2C%20SQLite%20churn%2C%20and%20coordinates%20bounded%20read%20tasks.%20Local-only%2C%20no%20publisher%20telemetry.%20https%3A%2F%2Fgithub.com%2FFaxanFM%2Fchronos)
- [Share a sanitized result](https://github.com/FaxanFM/chronos/issues/new?template=sanitized-result.yml)

Projects that use Chronos can link back with this optional badge:

```markdown
[![Chronos for Codex](https://img.shields.io/badge/Codex-Chronos_for_Codex-D64045)](https://github.com/FaxanFM/chronos)
```

Never publish raw diagnostic files, Governor state, rollout data, SQLite files,
paths, identifiers, prompts, commands, credentials, or private source.

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
- Evaluates eight opt-in Heartbeat families for agent stalls, runaway review,
  unusual usage burn, session growth, test regressions, machine drift, task
  dependencies, and Git or build-state changes.
- Suppresses unchanged Heartbeat conditions and sends only new, resolved, or
  materially worse transitions to one Governor inbox. Monitored tasks remain
  model-agnostic and are not woken by Chronos. Stable event IDs and a bounded
  acknowledged outbox protect host delivery across restarts.
- Passively registers task and subagent lifecycle changes through four reviewed,
  headless hooks. No per-turn hook, worker recurrence, transcript read, or
  model-visible hook output is used.
- Reuses one host-verified Chronos Governor or creates a fresh history-free
  Governor task. It never automatically forks a large working task.
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

Ask Codex to:

> **Analyze and install [FaxanFM/chronos](https://github.com/FaxanFM/chronos), then use Chronos Governor for appropriate low-complexity repository tasks.**

Or install it manually from its public marketplace:

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new Codex task after installation or upgrade. Codex tasks can retain the
versioned plugin skill locator captured when they started. An older open task
may therefore advertise a cache path removed by the upgrade even though the new
version is installed correctly. Do not copy or link new plugin files into an
old version directory; use a fresh task and verify the installed version.

Chronos is published in the shared OpenAI Plugins Directory for ChatGPT and
Codex. The marketplace commands are a fallback for environments where the
directory listing is not available. See the
[published listing record](docs/PLUGIN-DIRECTORY-SUBMISSION.md) for the verified
and unknown publication facts.

## Use

Ask Codex:

```text
Use Chronos to inspect current Codex resource health.
```

Chronos reports the current condition and recommends a proportionate response.

To set up low-overhead monitoring, ask once:

```text
Enable Chronos supervision. Reuse a verified Chronos Governor or create one
fresh dedicated task. Use GPT-5.6 Luna with Medium reasoning if available.
```

Review and trust the packaged lifecycle hook once through Codex `/hooks`.
Worker tasks need no script or prompt and can use Luna, Terra, Sol, or another
runtime model. Setup explicitly enables at most one Governor turn per hour
while work is active and one every six hours while idle. The Governor rotates
or pauses after 336 cycles or 14 days. A stable `chronos-supervision-v1`
equivalence key, deterministic winner order, and three-attempt reconciliation
budget keep simultaneous installers converged on one task and one recurrence.
Only the first two Governor pulses repeat that check; normal cycles do not.
Only that task owns host recurrence. It discovers
task and subagent starts or stops from a small encrypted local registry, then
uses host task status as the liveness authority. If hooks are disabled, it
falls back to host task discovery without blocking work. See
[Supervision](docs/SUPERVISION.md) for setup, routing, usage, and privacy limits.

For long-running or asynchronous work, ask:

```text
Enable Chronos Heartbeats in one Governor task using GPT-5.6 Luna with Medium reasoning.
Monitor the other tasks without waking them unless Governor decides intervention is needed.
```

The Codex host owns the recurring schedule and model choice. Chronos does not
install a service or scheduler. Monitored tasks can use any model and do not
run Heartbeats. Each due cycle compares one bounded normalized snapshot with
compact local state. A cycle with no actionable transition ends silently. All
events enter one Governor inbox; owner IDs are triage hints. The host deduplicates
and acknowledges emitted `EventId` values. See
[Heartbeats](docs/HEARTBEATS.md) for the collector contract, coverage limits,
routing, delivery, deduplication, and stored fields.

To delegate a small repository task, ask:

```text
Use Chronos Governor to delegate this bounded low-complexity task.
```

Governor validates the worker models advertised by the active runtime and
selects deterministically from that inventory. It sends focused read-only
assignments with `fork_turns=none`. It is a coordination aid, not a sandbox or
security boundary; all edits, integration, publishing, and final acceptance
remain with the coordinator.

See [Codex Token and Quota Findings](docs/TOKEN-QUOTA-FINDINGS.md) for the
source-backed GPT-5.6 findings and conservative local settings.
See [Efficiency Governor](docs/EFFICIENCY-GOVERNOR.md) for bounded approval-review
and rollout-amplification observations, their coverage rules, and hard safety
limits.
See [Builder Requirements](docs/BUILDER-REQUIREMENTS.md) for the consolidated
handoff ledger and explicit unavailable and calibration boundaries.
See [Chronos Governor](docs/CHRONOS-GOVERNOR.md) for routing, limits, contracts,
state, and verification behavior.
See [Supervision](docs/SUPERVISION.md) for passive task discovery and the
single-Governor bootstrap contract.
See [Architecture](docs/ARCHITECTURE.md), [Test Coverage](docs/TEST-COVERAGE.md),
[Release Operations](docs/OPERATIONS.md), and
[Calibration Methodology](docs/CALIBRATION-METHODOLOGY.md) for the current
safety and release model.
See [v0.7.0 Audit Response](docs/AUDIT-RESPONSE-2026-08-09.md) for the sanitized
fixed, contained, and deferred finding disposition.
See [v0.7.1 Delta Audit Response](docs/V0.7.1-DELTA-AUDIT-RESPONSE.md) for the
follow-up security, parser, release, and discovery fixes.
See [v0.7.6 Final Audit Response](docs/V0.7.6-FINAL-AUDIT-RESPONSE.md) for the
focused v0.7.7 correctness repairs and validation boundary.

## Safety and privacy

- Runs only when requested.
- Does not collect, transmit, or retain prompts, responses, source, diffs,
  commands, tool output, credentials, usernames, absolute paths, or personal data.
- Never blocks, pauses, or ends a Codex task.
- Never terminates Codex or unrelated user processes and never deletes user
  files. Governor can stop only its own bounded Git fingerprint subprocess.
- Opens the known Codex diagnostic database in logical read-only mode and never
  installs triggers, deletes rows, checkpoints, or vacuums it. SQLite can still
  create or update `-wal` or `-shm` coordination sidecars; Chronos reports the
  open mode, journal mode, whether sidecar mutation was possible, and whether it
  was observed.
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
  persistent log. Four reviewed plugin hooks store bounded task lifecycle hints
  only at start and end. A recurring Codex automation exists only when the user
  explicitly enables supervision or Heartbeats through the host. Setup
  reconciles duplicates, and release stops the recurrence before clearing local
  ownership.
- Stores lifecycle task and agent IDs encrypted for the current Windows user;
  raw transcripts and workspace paths are never stored. DPAPI does not isolate
  data from another process already running as that user. Host task tools remain
  the liveness authority.
- An invoked Heartbeat cycle stores bounded per-scope transition, coverage,
  cadence, deduplication, hashed delivery/outbox, and health metadata in the user's local Chronos
  application-data directory. It does not persist raw snapshots, prompts,
  responses, commands, source, paths, credentials, or tool output.
- When Governor is invoked, stores only untrusted local coordination metadata beneath the
  current user's Windows temporary application-data directory: opaque IDs, identity hashes, base
  commit, relative scopes, model labels, lease fencing, counters, status, and
  timestamps.
- Governor shared-folder write delegation is disabled; read-only checks cover a
  Git-visible projection and do not prove that no other filesystem effect occurred.
- Never automatically merges, resets, cleans, deletes worktrees or branches, or
  accepts a worker result without coordinator verification.

See [Privacy](PRIVACY.md), [Terms](TERMS.md), and [Support](SUPPORT.md).

## License

MIT
