# Field Report Ledger

This public ledger records sanitized, cause-level findings. It contains no
machine names, task IDs, usernames, local paths, prompts, source, raw state, or
diagnostic records. A report is not field validation until another installation
successfully exercises the candidate release from a fresh task.

## Confirmed Bugs

### Open task retains a removed versioned skill locator

- Affected context: an open task created with Chronos v0.6.1, after the local
  plugin cache was upgraded to v0.7.x.
- Reproduction scope: repeated on one installation and one existing task; not
  reproduced independently on both machines.
- Environment: upstream Codex task catalog and versioned plugin-cache lifecycle.
- Evidence: the task continued to advertise its captured v0.6.1 skill path,
  while the plugin manager retained only the newer installed version.
- Root cause: the open task's injected skill catalog did not refresh when the
  plugin manager replaced the cached version. This occurs before Chronos loads
  and is not a Chronos runtime or Governor-state failure.
- Safe response: fully close Codex for installation, then use a fresh task.
  Never disguise the mismatch by copying or linking newer code under an older
  version directory.
- Deterministic validation: start a task with version A, replace A with version
  B through the plugin manager, confirm the old task retains A's locator, then
  confirm a fresh task loads B. This upstream scenario remains reportable to
  the Codex plugin lifecycle owner.

### Governor status hid an independent-machine failure

- Affected version: v0.7.2.
- Reproduction scope: repeatable on one independent Windows installation; the
  same command succeeds in the development installation, so it is presently
  environment or persisted-state specific.
- Evidence: the documented `status` action launched the installed script and
  returned exit code 1 with only `error=internal_error`.
- Root cause: v0.7.2 allowed some parseable but structurally invalid state to
  reach migration or summary code, and its outer handler discarded the failure
  boundary and exception class. The independent machine's exact underlying
  exception cannot be claimed until the hardened result is exercised there.
- v0.7.3 correction: validate state maps and signed 64-bit revision boundaries;
  distinguish unreadable, failed, invalid-JSON, and invalid-schema state; and
  attach only privacy-safe stage and exception-class metadata to unknown errors.
- Regression: deterministic tests cover malformed JSON, non-map collections,
  an out-of-range revision, interrupted writes, and the unknown-error output
  contract. Existing state is preserved on every failure.
- Validation status: automated and installed-release checks pass locally;
  independent v0.7.3 fresh-task canary pending.

## Heuristic / Tuning Issues

No threshold, scoring, prediction, or calibration-sensitive change is included
in v0.7.3. Existing calibration work remains frozen pending labeled evidence.

## Feature / UX Improvements

- Make the fresh-task requirement explicit after every plugin install or
  upgrade.
- Explain that a missing old cache path can be stale task catalog state rather
  than a missing current installation.
- Return actionable, privacy-safe Governor recovery metadata without telemetry
  or local log collection.
