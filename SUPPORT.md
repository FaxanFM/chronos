# Support

Use the public issue tracker for Chronos support:

https://github.com/FaxanFM/chronos/issues

Include:

- Your Windows version.
- Your Codex version.
- The compact `CHRONOS` summary.
- For Governor issues, the action and compact `CHRONOS GOVERNOR` result.
- Whether Codex was fully closed and a fresh task was opened after the latest
  plugin installation or upgrade.
- What you were doing when degradation appeared.

Do not include Governor state files, worker assignments or replies, raw SQLite
rows, log bodies, usernames, local paths, command arguments, environment values,
credentials, source code, or unrelated process details.

If an open task points to a missing older version beneath the Codex plugin
cache, confirm the installed version with the plugin manager and retry from a
fresh task. Do not copy, rename, junction, or link the installed version into
the missing directory. A skill cannot repair a stale locator before it loads.

For an unexplained Governor `internal_error`, include its `failure_stage`,
`exception_type`, and `recovery` values. These fields are deliberately limited
to code-boundary metadata and do not contain local paths or exception text.

Chronos is an independent community plugin and is not supported by OpenAI.
