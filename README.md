# Chronos for Codex - diagnostics and read-task coordination

[![Release](https://img.shields.io/github/v/release/FaxanFM/chronos?label=release)](https://github.com/FaxanFM/chronos/releases/latest)
[![Test](https://github.com/FaxanFM/chronos/actions/workflows/test.yml/badge.svg)](https://github.com/FaxanFM/chronos/actions/workflows/test.yml)
[![License](https://img.shields.io/github/license/FaxanFM/chronos)](LICENSE)
![No telemetry](https://img.shields.io/badge/telemetry-none-4ed7a0)

Detect runaway Codex auto-review, approval loops, quota and context
amplification, broken permission rules, rollout duplication, diagnostic SQLite
churn, and Windows process degradation. Chronos keeps machine health separate
from workflow diagnostics and coordinates bounded read tasks without
creating an autonomous agent loop.

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new Codex task, then ask: `Use Chronos to inspect current Codex health.`

<p align="center"><img src="assets/chronos-proof-card.png" width="500" alt="Sanitized example Chronos output separating healthy machine resources from runaway automatic review and approval persistence"></p>

The image is a synthetic, sanitized example. It contains no machine, account,
task, repository, or session identifiers.

## Share safely

Chronos has no install or usage telemetry. Public signals are always opt-in:

- [Star Chronos for Codex](https://github.com/FaxanFM/chronos)
- [Share the telemetry-free release on X](https://twitter.com/intent/tweet?text=Chronos%20for%20Codex%20diagnoses%20Windows%20slowdown%2C%20approval%20loops%2C%20quota%2Fcontext%20pressure%2C%20SQLite%20churn%2C%20and%20coordinates%20bounded%20read%20tasks.%20Local-only%2C%20on-demand%2C%20no%20telemetry.%20https%3A%2F%2Fgithub.com%2FFaxanFM%2Fchronos)
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
- Routes bounded exploration, review, and verification to read workers. Shared-folder write delegation is disabled.
- Discovers worker models from the active runtime instead of assuming a model.
- Coordinates canonical workspace identity, fenced expiring advisory leases,
  attempt budgets, Git-visible read-mutation checks, and final coordinator verification.

Chronos mitigates local symptoms; it does not modify the Codex application or
its SQLite databases, terminate processes, or block active work.

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

Official OpenAI Plugin Directory listing is pending. The public marketplace
commands above install the same public plugin without waiting for directory
review. See the [directory submission packet](docs/PLUGIN-DIRECTORY-SUBMISSION.md)
for current status and reviewer instructions.

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
See [Architecture](docs/ARCHITECTURE.md), [Test Coverage](docs/TEST-COVERAGE.md),
[Release Operations](docs/OPERATIONS.md), and
[Calibration Methodology](docs/CALIBRATION-METHODOLOGY.md) for the v0.7.1 safety
and release model.
See [v0.7.0 Audit Response](docs/AUDIT-RESPONSE-2026-08-09.md) for the sanitized
fixed, contained, and deferred finding disposition.
See [v0.7.1 Delta Audit Response](docs/V0.7.1-DELTA-AUDIT-RESPONSE.md) for the
follow-up security, parser, release, and discovery fixes.

## Planned self-service agents

Poe and Apify builds are planned as independently callable self-service agents:

- Poe provides a guided session-health assessment.
- Apify provides session analysis, sanitized incident reports, and Codex
  public-fix compatibility checks.

When published, each agent will be invoked and paid for directly through its platform. Chronos does
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
- Reads bounded 2 MiB tails of up to eight recently active rollout files selected by modification time for
  structured aggregate token, effort, automatic-review, compaction, subagent,
  rollout-duplication, and parser-integrity
  counts.
- Reads supported files only in the known Codex rules directory to return
  aggregate rule-health and secret-shape counts; rule text, prefixes, hashes,
  assignments, and values are never returned.
- Never returns prompts, responses, tool arguments, tool output, usernames, or
  absolute local paths. Governor verification may return repository-relative changed paths.
- Creates no recurring task, service, telemetry, or persistent log.
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
