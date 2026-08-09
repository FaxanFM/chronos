# Security Policy

## Supported versions

Security fixes are applied to the latest published Chronos release. Upgrade to
the current release before reporting a result that may already be corrected.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature for this repository. Do
not open a public issue containing secrets, private paths, rollout content, or
working exploit details.

Include the Chronos version, Windows and PowerShell versions, the affected
action, minimal sanitized output, and a deterministic reproduction when
possible. Chronos has no remote telemetry, so maintainers cannot inspect a
machine or installation unless the reporter deliberately supplies evidence.

## Governor boundary

Chronos Governor is a local coordination aid, not a security sandbox. Shared
folder write delegation is disabled. Read delegation relies on the active
Codex sandbox and coordinator discipline; its Git-visible mutation check is
advisory and does not prove that no filesystem effects occurred.
