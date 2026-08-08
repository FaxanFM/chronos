<p align="center"><img src="assets/chronos-mark.png" width="180" alt="Chronos hourglass and process-tree mark"></p>

# Chronos

Chronos is a lean, on-demand Codex plugin for Windows sessions that become slow after hours or days of parallel work. Its optional Governor delegates bounded low-complexity repository work without turning Chronos into an autonomous agent loop.

It checks current resource and diagnostic-log health, explains signs of degradation, and offers conservative recovery steps without continuous monitoring.

## What it does

- Reports a clear `HEALTHY`, `WARNING`, or `CRITICAL` status.
- Identifies resource accumulation associated with long-running Codex degradation.
- Detects high-frequency Codex SQLite log churn and unreclaimed database space.
- Warns when the Windows filesystem helper is degrading and advises a full PC
  restart when the helper becomes unusable.
- Separates cached reads from observed GPT-5.6 cache writes and flags quota
  amplification from large contexts, high reasoning, subagents, and repeated
  compaction.
- Counts actual automatic-review turns from structured `turn_context` records,
  distinguishes them from bookkeeping, and reports only bounded aggregate review
  and rollout-growth observations.
- Recommends the safest next step for the current condition.
- Routes exploration, documentation, tests, mechanical edits, simple code, and
  focused verification to bounded Codex workers.
- Discovers worker models from the active runtime instead of assuming a model.
- Enforces canonical workspace identity, one writer across linked worktrees,
  fenced expiring leases, mutation attribution, exact scopes, result
  fingerprints, attempt budgets, and final coordinator verification.

Chronos mitigates local symptoms; it does not modify the Codex application or
its SQLite databases, terminate processes, or block active work.

## Install in Codex

Until Chronos is listed in the Plugins Directory, ask Codex to:

> **Analyze and install [FaxanFM/chronos](https://github.com/FaxanFM/chronos), then use Chronos Governor for appropriate low-complexity repository tasks.**

Or install it manually from its public marketplace:

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

To delegate a small repository task, ask:

```text
Use Chronos Governor to delegate this bounded low-complexity task.
```

Governor validates the worker models advertised by the active runtime and
selects deterministically from that inventory. It sends focused assignments
without the full parent conversation and keeps architecture, security-sensitive
work, unverifiable writes, integration, publishing, and final acceptance with
the coordinator.

See [Codex Token and Quota Findings](docs/TOKEN-QUOTA-FINDINGS.md) for the
source-backed GPT-5.6 findings and conservative local settings.
See [Efficiency Governor](docs/EFFICIENCY-GOVERNOR.md) for bounded approval-review
and rollout-amplification observations, their coverage rules, and hard safety
limits.
See [Builder Requirements](docs/BUILDER-REQUIREMENTS.md) for the consolidated
handoff ledger and explicit unavailable and calibration boundaries.
See [Chronos Governor](docs/CHRONOS-GOVERNOR.md) for routing, limits, contracts,
state, and verification behavior.
See [Architecture](docs/ARCHITECTURE.md), [Test Coverage](docs/TEST-COVERAGE.md),
[Release Operations](docs/OPERATIONS.md), and
[Calibration Methodology](docs/CALIBRATION-METHODOLOGY.md) for the v0.6.0 safety
and release model.

## Self-service agents

Chronos extends to Poe and Apify as independently callable self-service agents:

- Poe provides a guided session-health assessment.
- Apify provides session analysis, sanitized incident reports, and Codex
  public-fix compatibility checks.

Each agent is invoked and paid for directly through its platform. Chronos does
not require a managed engagement or contacting FaxanFM. Public runner links
will be added here as each agent is published.

## Safety and privacy

- Runs only when requested.
- Does not collect, transmit, or retain prompts, responses, source, diffs,
  commands, tool output, credentials, usernames, absolute paths, or personal data.
- Never blocks, pauses, or ends a Codex task.
- Never terminates a process or deletes user files.
- Opens the known Codex diagnostic database read-only and never installs
  triggers, deletes rows, checkpoints, or vacuums it.
- Reads only bounded 2 MiB tails of up to eight recently active rollout files for
  structured aggregate token, effort, automatic-review, compaction, subagent,
  rollout-duplication, and parser-integrity
  counts.
- Never returns prompts, responses, tool arguments, tool output, usernames, or
  local paths.
- Creates no recurring task, service, telemetry, or persistent log.
- When Governor is invoked, stores only local coordination metadata beneath the
  current user's Windows temporary application-data directory: opaque IDs, identity hashes, base
  commit, relative scopes, model labels, lease fencing, counters, status, and
  timestamps.
- Never automatically merges, resets, cleans, deletes worktrees or branches, or
  accepts a worker result without coordinator verification.

See [Privacy](PRIVACY.md), [Terms](TERMS.md), and [Support](SUPPORT.md).

## License

MIT
