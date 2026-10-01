# Local Harness Review

## v0.9.3 Local Installation

On 2026-10-01, the full v0.9.3 package was installed through the local Codex
plugin manager. Its 14 installed release files matched the per-file manifest;
ZIP SHA-256 is `2ba48cdde0dc9c718c6535abbd1743b1fffd6e042e18762f88fec2667724cac1`.
The manager reported `chronos@chronos`, version `0.9.3`, with one source and no
confirmed enabled-source conflict.

The installed-account harness passed on Codex 0.159.2. Five exact hook
definitions were trusted. A real local diagnostic model turn executed install,
supervision, and Heartbeat status. SessionStart, Stop, and SessionEnd completed;
SessionStart merged into the protected registry with zero drops. A negative
sandbox-account read returned the identity guard before authorized host-account
execution merged the preserved evidence. No broad trust bypass was used.
Subagent lifecycle dispatch was not exercised by that single diagnostic turn.

The first run did not observe the expected negative-test receipt; a bounded
rerun passed. This is not evidence that a full Desktop quit and reopen occurred,
or that existing loaded chats can hot-swap skill catalogs. The production
Governor recurrence was kept paused during readiness verification.

The scoped source and exact packaged regressions passed before the version
bump. The v0.9.3 reproducible release test also passed (2/2 identical builds).
Version-sensitive Heartbeat/Governor suites are rerun against source and package
before release. The earlier isolated real Desktop inventory smoke verified
schema-v3 `complete=false`, known in-scope activity, compact hash-only batches,
and recurrence eligibility without account-wide inventory claims.

The existing production Governor then executed the corrected installed protocol
on this Desktop host. Nonclaiming preflight, initialization, and one native
schema-v3 inventory cycle all returned `ok=true`; the cycle returned
`recurrenceEligible=true`. The raw and normalized inventory counts were both
11, with the caller included exactly once and two other in-scope active chats.
No unknown statuses were reported. The input was removed after use. The current
installation claim belongs to that Governor, with host role compatibility still
requiring host verification. The existing pulse stayed paused; zero worker
recurrences and zero intervention sends were reported. Heartbeat remained
prior-state with eight unsupported families. This verifies local bootstrap, not
scheduled execution or complete health coverage.

## Scope

This review uses the Codex Desktop runtime on this Windows machine. No remote
canary, other computer, scheduled worker, or publisher telemetry is required.
Source and extracted-package tests must use inbox Windows PowerShell 5.1.

## Current Plugin Rules

OpenAI now documents portable root `plugin.json`, bundled MCP servers, command
and MCP tool hooks, and synchronous Stop continuation. Installation still does
not grant hook trust. Background hooks cannot request continuation and can be
cancelled at session shutdown.

- https://developers.openai.com/plugins/build/plugins
- https://learn.chatgpt.com/docs/hooks
- https://learn.chatgpt.com/docs/app-server

Expanded packaging rules do not grant a plugin access to the Desktop process's
live thread registry. A local MCP process or a separate app-server cannot
substitute its own runtime inventory for the Desktop runtime inventory.

## Reproduced Integration Defects

On Desktop's bundled Codex 0.159.0, the old Windows hook launcher is evaluated
by PowerShell. Its `%SystemRoot%` token fails before the intake script runs.
On 0.159.2, starting a nested interpreter repeatedly exceeds SessionEnd's
three-second deadline. The revised launcher resolves `PLUGIN_ROOT` directly
inside Codex's existing PowerShell hook shell. The local installed-plugin
harness observes actual completion and a protected inbox event with this form.
Custom non-PowerShell Windows hook shells remain unverified.

Completion hooks now return neutral `{}` JSON. All five lifecycle handlers run
synchronously; this prevents background cancellation and permits hook run
notifications to provide actual dispatch evidence. These hooks do not create
model turns, approve actions, or inject context.

Local tests of a portable root manifest, with either an inline OpenAI extension
or a compatibility overlay, discover zero hooks on runtime 0.159.0 even though
the plugin is installed and enabled. The compatibility-only package discovers
all five. Do not add root `plugin.json` to the deployable package until the same
harness gate passes on the installed runtime. This is a measured compatibility
decision, not a rejection of the portable manifest standard.

The same inline-extension portable-manifest probe was repeated on 0.159.2:
installation succeeded, but `hooks/list` again returned zero Chronos hooks.
The compatibility package's five hooks were discovered and executed on that
same runtime. The release candidate therefore retains the supported legacy
layout rather than assuming that a documented new format already works here.

## Reproducible Local Test

`tests/harness.tests.ps1 -CodexPath <desktop-codex-executable>` installs through
the plugin manager into an isolated local CODEX_HOME, reviews exact hook hashes
through the supported config API, and observes an actual SessionEnd dispatch
notification plus protected inbox event. It uses no credentials, model turns,
trust bypass, or fabricated lifecycle input. A session that has never had a model
turn is not evidence for SessionStart or Stop dispatch.

The optional `-InstalledAccountRoot <existing-CODEX_HOME> -RunModelTurn` runs one
explicit local diagnostic turn against the installed Chronos package with
`gpt-6.1-sol`. It verifies SessionStart and Stop notifications and archives only
the test thread. Credentials are not copied to the fixture. Hook trust updates
are limited to Chronos definitions the caller has authorized and reviewed.

Neither mode certifies account-wide active coverage. That is no longer required
for the user-authorized visible-or-specified working set. The current-host
`list_threads` window is sufficient for bounded selection; native schema-v3
input keeps `complete=false`. Standalone app-server identity enumeration still
cannot establish Desktop liveness. Hooks add evidence but cannot expand scope.
Unknown Heartbeat families remain unsupported, not healthy.

## Verified Local Progress

On 2026-09-30, the corrected installed package passed a local Codex 0.159.2
diagnostic turn using `gpt-6.1-sol`. The native output receipts confirm actual
execution of install status, supervision status, and Heartbeat status. Runtime
notifications confirm SessionStart, Stop, and SessionEnd completion; protected
Stop and SessionEnd inbox events were observed. A stronger consumer check then
identified that sandbox-account status calls cannot decrypt the host account's
DPAPI event. Scoped native-command execution merged SessionStart with zero
dropped entries. The current source adds a schema-v3 identity guard that
preserves evidence on a mismatched-account read. The earlier 14-file installed
package matched the local ZIP with SHA-256
`659862e86a828f47e7829c79102b66742dc0a16ad868bb7e377db45175cdd357`.

The identity-guard revision was rebuilt and installed through the plugin manager
with 14 release files and ZIP SHA-256
`8d7955fd1c6180c771665d1816898316a2f236f8e58e5d37bedba6bfbfbba576`.
The strengthened local harness passed: a real sandboxed native command returned
`supervision_hook_identity_mismatch`, then scoped host-account execution merged
the preserved SessionStart event with zero drops. Stop and SessionEnd persisted
their protected events. SessionEnd completed in 2088 ms. The harness accepted
no broad trust or permission bypass; its approval handler permits only the three
exact authorized diagnostic commands, and never writes an exec-policy rule.

Source and extracted-package regression suites remain separate release gates.
Hook dispatch and lossless event merge alone are not a full Governor certificate.

### Regression Gates

The identity-guard source passed the Inspector, Heartbeat, and Supervision
deterministic suites, Governor's 49 scenarios, and Release's two reproducible
build validations under separate Windows PowerShell 5.1 processes. The same
14-file extracted ZIP passed Inspector, Heartbeat, Supervision, and Governor's
49 scenarios in separate Windows PowerShell 5.1 processes. Installed-cache and
extracted-package verification found zero mismatches against the release
manifest's 14 file hashes. Source content also matched after applying the
release builder's deterministic UTF-8/LF normalization; one source YAML file
uses CRLF before packaging.

The subsequent CI review found two missing lanes: source Heartbeat validation
and extracted-package Inspector validation. Both ordinary and tagged workflows
now require them alongside source/package Supervision and Governor. The serial
validation-job budget is 120 minutes; production hook deadlines remain three
seconds. Release validation was rerun after these workflow and gate assertions
changed and passed with two identical builds. These are local results, not a
claim that an unpublished workflow has already passed GitHub Actions.

### Current Desktop Diagnostics

The installed package also ran through this Desktop chat's shell tool under the
authorized hook-owning Windows account, outside the isolated app-server fixture.
Installation status reported one cached source and no source conflict.
Supervision observed five hook events, zero dropped entries, and no claimed
Governor; recurrence eligibility remained false. Supervision and Heartbeat both
returned the same default Codex-home identity, `3f77781cee604dd9`.

Heartbeat status returned `statusMode=prior_state`, `evaluation=unsupported`,
and `coverageUnsupported=8`. Those eight families were not evaluated. Inspector
executed successfully and reported healthy machine operability separately from
critical diagnostic-log churn and high quota pressure. Rollout/review coverage
was partial (8 selected files out of 13 eligible), so its figures are bounded
observations, not account-wide totals. SQLite was opened logically read-only;
no sidecar mutation was observed. These diagnostics created no recurrence,
worker, intervention, or task wake.

Before the scope correction, installed preflight returned `host_inventory_completeness_unsupported`,
`governorClaimed=false`, `recurrenceEligible=false`, and
`inventoryReconcile=skipped`. Its former retry policy was
`none_until_host_contract_changes`. The existing Chronos Governor pulse was
confirmed paused; no new recurrence was created. This is a verified safe
capability rejection, not a successful autonomous-Governor bootstrap.

This is a local development package, not a replacement for the immutable public
v0.9.2 release. Subagent hooks have not been observed in a real model turn in
this harness. The current Desktop host rejects `list_threads` limits above 50
and returns no completeness metadata. That no longer blocks the explicitly
bounded scope; installed bootstrap still needs verification before the existing
paused recurrence is enabled. Hook dispatch success does not by itself authorize bootstrap or imply
healthy coverage for unevaluated families.
