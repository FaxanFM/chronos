# Chronos v0.9.3

Govern the work in front of you.

Chronos now works with up to 50 visible local Codex chats, plus chats you
explicitly select. Only active members are governed. No account-history scan,
pagination requirement, or fabricated completeness claim stands between setup
and your current work.

## What Changed

- Scoped Governor bootstrap and schema-v3 inventory with `complete=false`.
- Clear working-set counts, active status, and bounded hash-only cycle results.
- Safe restart persistence; leaving the window does not mean a chat ended.
- Windows hook intake without a nested interpreter, plus identity-bound
  protected evidence that survives a mismatched sandbox-account read.
- Version-aware tests and separate source/exact-package Windows PowerShell 5.1
  gates, with two deterministic release builds.

## What Chronos Does

One local Governor supervises active work. Evidence-bound Heartbeats evaluate
what the host can actually observe. Windows diagnostics separate machine health
from quota pressure, review/approval loops, rule issues, rollout growth, and
SQLite churn. Bounded read-task coordination keeps edits and decisions with
the coordinator. No publisher telemetry.

Five optional lifecycle hooks add evidence without model turns. They do not
replace current-host liveness, expand governance scope, or make missing
Heartbeat/Inspector evidence healthy. One Governor recurrence and zero worker
recurrences remain the supported topology; host scheduling must execute the
native protocol before a scheduled pulse is considered verified.

## Installation And Distribution

Use the full GitHub edition for optional bundled hooks. After upgrading, fully
quit and reopen Codex, then start a fresh chat with the setup starter. Existing
loaded chats cannot hot-swap their skill catalog. Do not enable both Git and
OpenAI Directory identities at once.

OpenAI's published listing is still v0.9.2 until a reviewed update is published.
Current portal documentation excludes lifecycle hooks from submitted ZIPs.
This full hook-enabled ZIP is not presented as an approved marketplace update.
An explicitly labeled skills-only edition needs separate validation and review.

Custom MCP Apps dashboards are a supported extension path in compatible hosts,
but this release adds no dashboard or hosted MCP service. Native Codex UI
rendering is not inferred from ChatGPT UI documentation.
