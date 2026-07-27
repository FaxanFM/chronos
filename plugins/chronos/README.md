<p align="center"><img src="assets/chronos-mark.png" width="180" alt="Chronos hourglass and process-tree mark"></p>

# Chronos

Chronos is a lean, on-demand Codex plugin for Windows sessions that become slow after hours or days of parallel work.

It checks current resource and diagnostic-log health, explains signs of degradation, and offers conservative recovery steps without continuous monitoring.

## What it does

- Reports a clear `HEALTHY`, `WARNING`, or `CRITICAL` status.
- Identifies resource accumulation associated with long-running Codex degradation.
- Detects high-frequency Codex SQLite log churn and unreclaimed database space.
- Recommends the safest next step for the current condition.
- Offers user-approved cleanup of stale helpers when appropriate.

Chronos mitigates local symptoms; it does not modify the Codex application or
its SQLite databases.

## Install in Codex

Until Chronos is listed in the Plugins Directory, install it from its public marketplace:

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

## Managed Chronos services

FaxanFM offers optional managed services for teams and power users who want
help beyond the local plugin:

- Guided session-health assessments.
- Before-and-after remediation analysis.
- Sanitized, support-ready incident reports.
- Codex version and public-fix compatibility reviews.

The local Chronos plugin remains free, private, and independently usable.
Contact [FaxanFM on GitHub](https://github.com/FaxanFM) for service availability
and pricing.

## Safety and privacy

- Runs only when requested.
- Does not collect, transmit, or retain personal data.
- Requires confirmation before cleanup.
- Never automatically closes the Codex desktop application or deletes user files.
- Opens the known Codex diagnostic database read-only and never installs
  triggers, deletes rows, checkpoints, or vacuums it.
- Creates no recurring task, service, telemetry, or persistent log.

See the public [Privacy](https://github.com/FaxanFM/chronos/blob/main/PRIVACY.md), [Terms](https://github.com/FaxanFM/chronos/blob/main/TERMS.md), and [Support](https://github.com/FaxanFM/chronos/blob/main/SUPPORT.md) pages.

## License

MIT
