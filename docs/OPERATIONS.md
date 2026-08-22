# Release, Upgrade, And Rollback

## Reproducible Build

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1
```

The builder packages only tracked plugin files, rejects untracked plugin input
and reparse ancestors, sorts entries, assigns a fixed ZIP timestamp, and writes
the ZIP, SHA-256 checksum, and a per-file hash/size manifest to `dist`.
`tests/release.tests.ps1` builds twice and requires identical artifact hashes.
This proves same-environment reproducibility for the tested Windows runtime. It
does not claim byte identity across arbitrary ZIP implementations or operating
systems.

Run the packaged Supervision and Release validation under inbox Windows
PowerShell 5.1, not PowerShell 7:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/supervision.tests.ps1
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/release.tests.ps1
```

The bounded default-slot fixtures use an explicit isolated `CODEX_HOME`. Live
legacy state from an installed plugin must not replace the slot-recovery
provenance that those fixtures are intended to verify.

The authoritative immutable v0.7.6 ZIP SHA-256 is
`e90c789d56e3b512109b467f116721c2fe948d66c89a77c624162ab538e88497`.
Different hashes recorded for attempted or pre-publication packages are not the
v0.7.6 release artifact. Do not rewrite its tag or immutable release to correct
an earlier working note; record the distinction as an erratum.

The authoritative immutable v0.7.7 ZIP SHA-256 is
`b74e3a595f218eedf70658edd63364827f861e75d377d9a286cbdc91f88076ee`.
It is identical to the independently audited and externally exercised release
candidate.

The authoritative immutable v0.8.0 ZIP SHA-256 is
`d6d28a0e0af2e188d2e17e08711023725c1e31931432ede687ebd0b5f8844039`.
It matches the independently audited candidate. The signed tag, two remote
Windows package-install checks, artifact attestation, immutable publication,
and post-publication asset verification all passed.

The authoritative immutable v0.8.5 ZIP SHA-256 is
`d4fe75f79acf8e5394497fe96f2a8ef9c2fa935052a268ee8ac0ed5a116761d2`.
It matches the independently audited and externally exercised release
candidate.

The authoritative immutable v0.8.6 ZIP SHA-256 is
`948fcc4bab8775791f7ec303dd8830aa08e2db2cf2ba9c0a41038351de4ae37e`.
It changes only Plugin Platform manifest compatibility and its release
regression coverage. The signed release and public Plugin Directory package
were published before the v0.8.7 audit-remediation work began.

The authoritative immutable v0.8.7 ZIP SHA-256 is
`580a64fb5f1393005c7fc314979a025f3d64137515a9bb70f41e1824ac60d640`.
The authoritative immutable v0.8.8 ZIP SHA-256 is
`686070c504e73fe5997cac754f801a3f55235d6b32b5bff761f59a210f2e2f50`.
The authoritative immutable v0.9.0 ZIP SHA-256 is
`52006ba07fa9ffef0705c0c65261134331a7e6c2543e6baf24210fa42871aa67`.
v0.8.8 is the current published Directory package. v0.9.2 replaces the failed
v0.9.0 Windows hook path and completes its audit and external-canary gates.

## Published Release

A `vX.Y.Z` tag must exactly match `.codex-plugin/plugin.json`. Before creating a
tag, enable **Release immutability** in the repository's GitHub settings. This
setting applies only to releases published after it is enabled.

See GitHub's [immutable-release settings](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes)
and [immutable-release model](https://docs.github.com/en/enterprise-cloud@latest/code-security/concepts/supply-chain-security/immutable-releases)
for the repository control and its guarantees.

The release commit and annotated tag must both carry cryptographic signatures
that GitHub reports as `Verified`. The tag workflow rejects lightweight tags,
unverified tag signatures, and unverified release commits. Verify locally before
pushing when the signer's public key is available:

```powershell
git verify-commit HEAD
git verify-tag v0.9.2
```

See GitHub's [commit and tag signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
for supported signing formats and the meaning of `Verified`.

The workflow runs every test on two Windows runner labels in an unprivileged
job. A separate publication job rebuilds the package, creates an official
GitHub artifact attestation with a commit-pinned action, and verifies that
attestation before creating a draft release. It publishes the complete draft
once, verifies the immutable release and each asset, downloads every published
asset, and compares its bytes with the verified build. Release immutability then
prevents its tag or assets from being moved, modified, or deleted while the
release exists. A failed signature check, test, version check, reproducibility
check, or attestation prevents publication.

See GitHub's [artifact-attestation documentation](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
for the provenance and verification model.

Verify a downloaded artifact:

```powershell
Get-FileHash .\chronos-v0.9.2.zip -Algorithm SHA256
gh attestation verify .\chronos-v0.9.2.zip -R FaxanFM/chronos
gh release verify v0.9.2 -R FaxanFM/chronos
gh release verify-asset v0.9.2 .\chronos-v0.9.2.zip -R FaxanFM/chronos
```

The `gh release` checks follow GitHub's [release-integrity verification](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/verify-release-integrity)
procedure.

Compare the first command with `chronos-v0.9.2.sha256`. These controls prove
different things: commit and tag signatures identify the signer; reproducible
builds and checksums bind source to bytes; artifact attestations record the
GitHub Actions build provenance; and release immutability binds the published
tag, commit, and assets. None replaces local source review.

## Upgrade

Fully close Codex before replacing an installed plugin. The normal public source
is the OpenAI Plugins Directory identity `chronos@openai-curated-remote`; install
or update Chronos through the Directory listing. Use the Git marketplace only
as a fallback when the Directory is unavailable:

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new task and confirm that the installed plugin reports the expected
version. Open tasks can retain the versioned skill locator captured when the
task started. If an older task reports that its former cache path is missing,
that is stale task catalog state rather than evidence that the newly listed
version is absent. Chronos cannot repair this from inside a skill that did not
load. Do not create a compatibility copy, junction, or symbolic link under the
old version because that would execute newer code under a false version label.

v0.9.2 retains disabled shared-folder write delegation. Inactive Governor
version 1 or 2 state can migrate from Git
metadata into its sandbox-writable per-user state store. It fails closed when
legacy state contains an active lease; finish or release that work with the
previous version before retrying.

If Governor returns `state_store_unreadable`, `state_read_failed`,
`state_invalid_json`, or `state_schema_invalid`, preserve its state and continue
the task as coordinator. Do not delete or edit state to force recovery. Report
the compact result only. An `internal_error` now includes a privacy-safe
`failure_stage` and exception class, but never the exception message, local
path, or state content.

### Directory migration

The Git marketplace identity `chronos@chronos` and Plugins Directory identity
`chronos@openai-curated-remote` are separate Codex sources. Installing the
Directory package does not remove the Git source or rewrite an already loaded
task catalog. Check the bounded cache inventory with:

```powershell
chronos.cmd -Action install-status
```

When Chronos confirms that the Directory package is running and the legacy Git
source remains enabled, remove
the legacy source through `codex.cmd plugin remove chronos@chronos` followed by
`codex.cmd plugin marketplace remove chronos`, then fully quit and reopen Codex
before starting a fresh task. Obtain
user approval before changing plugin-manager state. Never delete cache folders
or edit `config.toml` directly. Cache presence is not proof that a source is
enabled; the status output states this limitation.

## Supervision Recovery

After upgrading, fully quit and reopen Codex before opening a fresh task. This
is required because a running host can retain a removed versioned skill
locator. Then review the exact Chronos lifecycle hook through `/hooks`. Hook
trust is bound to the definition hash and cannot be
bypassed by the plugin. Then ask Codex to enable Chronos supervision once.

The `/hooks` installed, active, and trusted labels do not prove the command ran.
Check `hookExecutionObservation`, `hookRuns`, and `lastHookUtc` in supervision
status. Where the host dispatches hooks, capture the baseline and prove those
values advance. Some current Windows Codex and `codex exec` paths can omit hook
dispatch even while `/hooks` reports active and trusted. Chronos therefore uses
one complete host inventory per Governor cycle as its autonomous discovery
authority. v0.9.2 keeps the Windows launcher quote-free because Codex passes it
through an outer `cmd.exe` command boundary.

First inspect all host automations named `Chronos Governor pulse`, but derive
mutation authority only from the complete current installation key. Reuse a live
target only after its title and assignment confirm the dedicated role. Otherwise
reuse a claimed Governor after the same check, or create one fresh task without
inherited history. Do not automatically fork a working task. Elect one contender,
fence current-key recurrences to zero, initialize, require readable status and a
complete Governor-bearing inventory, then reconcile one current-key automation.
Use `chronos.cmd -Action supervise -SupervisionAction status` for compact registry
health.

`supervision_governor_conflict` means another record owns the role. It enters the
non-fallthrough, no-mutation loser-verification branch and never runs generic
initialization-failure recurrence cleanup. Do not use `-Force` unless host task
status proves that task is no longer live.
`supervision_state_invalid`, `supervision_state_path_invalid`,
`supervision_mutex_busy`, and `supervision_crypto_unavailable` preserve or skip
local state and never justify deleting a task or workspace file. Worker tasks
need no setup and must not receive a recurring automation.

`status` and `discover` automatically merge bounded fallback events left by
brief hook contention. Do not edit or delete the fallback directory. A malformed
entry is removed and increments the degraded counter; capacity pressure is
reported without evicting the committed registry.

The default registry is
`%TEMP%\Chronos-Supervision-v3-<scope-prefix>-<slot>\session-registry.json`.
Chronos probes four bounded direct TEMP child slots and selects the first
writable non-reparse slot. The sibling `installation-scope.json` contains only
a schema number and an opaque installation identity. A new v3 identity uses the
deterministic host-and-Codex-home fallback. A slot change therefore does not
change the installation key or authorize a second Governor. On first use, a readable v2, fixed-TEMP, or LocalAppData
installation anchor is imported with its state, preserving the existing key
without changing the prior source. If a prior root is inaccessible,
Chronos preserves it, initializes the writable v3 slot, and rebuilds from
complete host inventory. Loss of the registry disables the discovery hint but
does not affect Codex tasks. Reconcile existing host automations before
recreating a claim so registry loss cannot justify a duplicate task or
recurrence. `engine=degraded` with `registryCapacity=exhausted` means Chronos
retained the existing 256 records and refused a new hint; use host task tools as
authority.

`CODEX_HOME` defines the installation boundary when it is nonempty; otherwise
Chronos uses the current user's `.codex` directory. Status returns only
`codexHomeSource`, a truncated `codexHomeIdentity` hash, and the hashed mutex
identity. Missing, inaccessible, file-valued, or reparse-point overrides fail
closed before state creation. The check includes every path component, so an
ancestor junction also fails closed. Do not redirect two installations into
one state root. Unscoped legacy state is considered only for the default
`.codex` home. An explicit or environment-provided home never imports it.

Never create or enable a Governor recurrence after initialization alone. First
require readable supervision and Heartbeat status and one successful complete
host-inventory cycle that contains the Governor exactly once and returns
`recurrenceEligible=true`. Before initialization, observe all same-name host
recurrences but derive mutation authority only for the complete current
installation key. Pause or remove that current-key set, including a pre-existing
recurrence, and re-list host state to verify zero active current-key recurrences.
Foreign and unverified keys remain untouched. This zero-recurrence fence is
verified before initialization begins. A verified concurrent loser leaves the
winner unchanged and stands down. Any post-eligibility reconciliation failure
also returns the current-key set to zero. Never use a recurrence to recover from
failed setup.

Delayed start events cannot revive terminal records. After host task
status proves that an ended task is active again, the Governor can use
`-SupervisionAction confirm-active -SupervisionSubjectId <id>`. To disable
supervision, call `release`, stop and verify all current-key host recurrences, then
call `release -SupervisionConfirmRecurrenceStopped`. Clearing local ownership
first can orphan a recurrence and is prohibited. See [Supervision](SUPERVISION.md).

## Heartbeat Recovery

Use one recurring Governor task for the monitored task set. Configure that task
with `gpt-5.6-terra` and Medium reasoning when the host offers it. The default is
60 minutes while work is active and 360 minutes while idle, at most 24 or four
Governor turns per day. Rotate or pause after 336 cycles or 14 days. Do not
create a recurrence in every monitored task. Monitored tasks can use any
available model.
Chronos emits only to the Governor inbox. `Owner` and `Subject` are routing
evidence, not authority. The Governor can use the host task transport for one
fixed-template intervention to one exact verified affected task.

Run `chronos.cmd -Action heartbeat` without an input path to inspect compact
Heartbeat health. `outboxPending` counts transitions that the host has not yet
acknowledged. `outboxExhausted` counts records that used the initial attempt and
one retry. Deduplicate each event by `EventId`. Use `plan` or `fail-closed` for
an actionable event; either command consumes that outbox entry atomically. Use
`-HeartbeatAcknowledgeEventId` only when the Governor records an event without
opening an intervention. If delivery is interrupted after state persistence, the host
can safely replay the same `runId`; due outbox events are returned before that
run is suppressed. The retry window uses local wall-clock delivery time, so a
replayed `capturedAtUtc` cannot postpone an already-due event. Due delivery is
also evaluated before evidence-time ordering, so a newer intervening collector
cycle cannot preempt replay of the old serialized run.

Plan every event in a cycle before claiming any send. Then recheck the target
and its host generation. Keep one active intervention per target. Record host
transport as `accepted`, `definite_failure`, or `unknown`. Never retry an
unknown result. A definite failure gets one retry. Accept a response only from
the exact target, intervention ID, version, and generation. Treat
`outcome_reported` as pending verification, not recovery. Resolve only from a
later observed Heartbeat cycle or an allowed independent host inventory, narrow
test, or Git check. `target_policy_mismatch` means the requested task did not
match the event class's persisted subject or owner hash; keep it failed closed.

Never target the Governor. Governor-origin token volume is comparable only when
both samples include the five supervision progress counters. A confirmed local
condition changes only the Governor recurrence to 360 minutes. Re-list the
automation and acknowledge the event only after one matching active recurrence
has that cadence. A later comparable resolution restores the current active or
idle supervision cadence. A monitored-task message still requires a second
event concerning the same affected task and observation window. Chronos does
not infer model price or quota effect. When a target is ambiguous, transport is
unavailable, or routine remediation fails, keep it Governor-local; do not
broadcast or assign the action to the user. Surface only genuine user authority.

Default Heartbeat state is under
`%TEMP%\Chronos\Heartbeat-v2\<scope-sha256>\heartbeat-state.json`. Valid
readable state from the prior TEMP namespace or legacy LocalAppData location is
imported on first use only when Chronos uses the default `.codex` home. A
custom `CODEX_HOME` does not import those unscoped sources or their pending
outbox records. If prior state belongs to an inaccessible sandbox
identity, Chronos leaves it unchanged, starts in the versioned namespace, and
reports `prior_state_unavailable_new_root`. When a host supplies
`-HeartbeatStatePath`, it must also supply the same stable
`-HeartbeatScope` from every working directory and Windows session. The default
path and scope need no manual configuration. Explicit state must remain beneath
the versioned TEMP Heartbeat root or the LocalAppData Heartbeat root; unrelated
TEMP siblings fail closed before directory creation.

The default scope uses the same canonical `CODEX_HOME` resolution as
supervision. A sandbox `HOME` change does not split state when `CODEX_HOME`
remains the same; separate Codex homes do not share Heartbeat state.

For an inaccessible prior scope, require compact status to show
`priorStateDisposition=unavailable_preserved` and
`priorStateWriteAttempted=false`. This attests only to the Chronos migration
code path. Compare host-visible before/after metadata when available; do not
take ownership or weaken permissions to inspect protected contents.

Preserve a state file that returns `heartbeat_state_invalid`,
`heartbeat_source_out_of_order`, `heartbeat_outbox_capacity`, or
`heartbeat_condition_capacity`. Do not delete or edit it to manufacture a
healthy result. Stop duplicate schedulers, verify the collector epoch and
sequence, and report the privacy-safe error code. Chronos reopens and validates
authoritative state after an abandoned mutex; stale temporary files do not
replace the committed state. State-path case aliases use the same canonical
mutex. Chronos rejects hard-linked state files instead of permitting two names
for one writable state object.

## Rollback

Fully close Codex. Install the desired prior tagged release or restore the prior
plugin cache, then open a new task. Do not edit Governor state to force a
rollback. v0.5.4 state is version 3 and older Governor versions may not
understand it; preserve it for audit and begin delegation only after confirming
the selected version's state behavior. Rollback never requires changing the
Codex diagnostic SQLite database or deleting user work.
