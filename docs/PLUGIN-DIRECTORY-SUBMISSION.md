# OpenAI Plugin Directory Published Listing Record

Status: v0.8.8 is published in the OpenAI Plugins Directory under the verified
Dravara, LLC business identity. Both OpenAI skill scans passed and the package
was published from the existing Chronos listing. The GitHub release artifact is
`chronos-v0.8.8.zip` with SHA-256
`686070c504e73fe5997cac754f801a3f55235d6b32b5bff761f59a210f2e2f50`.
Release record:
https://github.com/FaxanFM/chronos/releases/tag/v0.8.8.

v0.9.0 is the public GitHub asynchronous-supervision release with artifact
`chronos-v0.9.0.zip` and SHA-256
`52006ba07fa9ffef0705c0c65261134331a7e6c2543e6baf24210fa42871aa67`.
It has not been submitted to the OpenAI Plugins Directory. Release URL:
https://github.com/FaxanFM/chronos/releases/tag/v0.9.0.

v0.9.2 is the candidate Directory update. It mitigates the embedded-quote
Windows hook-launcher defect, makes complete host inventory authoritative when
the host does not dispatch hooks, preserves terminal state when asynchronous
lifecycle events arrive out of order, and requires a full host restart after
upgrade. It also isolates supervision state across restarted sandbox
identities, gates recurrence creation on one successful complete-inventory
cycle, permits Governor repository discovery while ignoring user Git config,
and makes overlapping Heartbeat cycles explicitly retryable. Supervision and
Heartbeat now use canonical `CODEX_HOME` installation identity, isolate
separate Codex homes, reject reparse-point ancestors before state creation, and
reserve unscoped legacy migration for the default `.codex` home so a shared
legacy identity or outbox cannot be cloned into custom installations. It retains the
full-setup contract and replaces generic first-use actions with three meaningful
starters for complete setup, read-only health briefing, and bounded Governor
research. Explicit-state hooks now wait for the shared registry mutex before
they read state content. A contended hook writes one protected pending event
instead, which removes a startup race without weakening the silent-hook
contract. The normal configured hook now uses a small protected intake path
instead of loading the full supervision engine inside its three-second host
window. It writes one CODEX_HOME-scoped event; the next mutex-owning status or
Governor cycle validates, receipts, merges, and removes it. Undecryptable
records degrade once without blocking supervision, and a deletion-locked file
cannot replay after its state change is committed. Slot-and-content receipts
also survive a temporary read lock and a full 256-event sibling inbox. The
Governor assignment,
result, verification, lifecycle, and exclusion contracts are now
self-contained in the installed skill. The candidate
`chronos-v0.9.2.zip` SHA-256 is
`502d5c786da93ec0b2814f935af704581b7ec4669d24327dd9efe73651f32c77`.
Candidate release URL:
https://github.com/FaxanFM/chronos/releases/tag/v0.9.2.

Direct listing:
https://chatgpt.com/plugins/plugins_6a79c882cf488191b8f62ee20e0e2571

The listing is shared across supported ChatGPT and Codex plugin surfaces.
Availability still depends on region, surface, workspace controls, and role.
Publication permits distribution; it is not an OpenAI endorsement.

## Official Submission Route

OpenAI's current submission instructions use the Platform portal, not the
public ChatGPT directory:

1. Open [organization roles](https://platform.openai.com/settings/organization/people/roles).
2. Confirm the submitter is an organization owner or has **Apps Management:
   Write**.
3. Open [organization general settings](https://platform.openai.com/settings/organization/general)
   and complete individual or business verification.
4. Open the [plugin submission portal](https://platform.openai.com/plugins).
5. Add a new version to the existing **Skills only** plugin and upload the final
   `chronos-v0.9.2.zip` release asset after every gate passes.
6. Complete the listing, prompts, reviewer cases, availability, release notes,
   and policy attestations below.
7. Submit the draft for review. Approval does not publish automatically; after
   approval, publish the approved version from the portal.

Official references:

- [Submit plugins](https://developers.openai.com/plugins/deploy/submission)
- [Plugin submission errors](https://developers.openai.com/plugins/deploy/submission-errors)
- [Plugin guidelines](https://developers.openai.com/plugins/app-guidelines)

## Submission Type

- Type: **Skills only**
- Package name: `chronos`
- Version: `0.9.2`
- MCP server: none
- App or custom UI: none
- Authentication: none
- External API or network dependency: none
- Commerce: none

Do not upload screenshots. OpenAI permits submission screenshots only for an
MCP plugin whose tool scan reports custom UI. The synthetic proof card and
social preview are GitHub discovery assets, not directory submission assets.

## Listing

Display name: `Chronos for Codex`

Category: `Developer Tools`

Short description: `Diagnose and govern Codex`

The display name is under the 30-character final limit. The short description
is one line and under the 30-character final limit.

Long description:

> Run one local Governor that passively discovers active Codex tasks, evaluates
> actionable Heartbeats, and contacts only the exact affected task when
> intervention is justified. Chronos also diagnoses Windows resource
> degradation, quota and context pressure, approval and review loops,
> permission-rule problems, rollout duplication, and SQLite churn. Silent hooks
> create no model turns, routine worker tasks stay passive, and bounded
> read-only workers remain under coordinator verification. No publisher
> telemetry.

Developer name: `Dravara, LLC`

`FaxanFM` is the GitHub repository account, not the publisher identity.

Website: https://github.com/FaxanFM/chronos

Support: https://github.com/FaxanFM/chronos/blob/main/SUPPORT.md

Privacy: https://github.com/FaxanFM/chronos/blob/main/PRIVACY.md

Terms: https://github.com/FaxanFM/chronos/blob/main/TERMS.md

License: MIT

Supported platform: Windows with the Codex plugin runtime.

## Starter Prompts

1. `Set up Chronos: verify source, enable one Governor and Heartbeats, inventory every live task, and prove zero worker recurrences.`
2. `Give me a read-only Chronos health briefing: separate PC, workflow, quota, approvals, rules, SQLite, Heartbeat, and supervision.`
3. `Use Chronos Governor for safe read-only research and review; keep edits and final decisions here; finish locally if unavailable.`

All three are unique, single-line, at most 128 characters, and contain no app
mention.

## Positive Reviewer Cases

### 1. Complete first-use setup

- Prompt: `Set up Chronos: verify source, enable one Governor and Heartbeats, inventory every live task, and prove zero worker recurrences.`
- Expected behavior: verify the installed source and native status, perform
  optional hook trust review when the host presents it, reuse or create one history-free Governor, and
  reconcile the installation-scoped recurrence without prompting worker tasks.
  Recurrence creation is a hard gate: failed initialization, unreadable native
  status, unreadable Heartbeat status, or an incomplete Governor-bearing
  inventory must leave zero current-key recurrences and schedule no recovery
  recurrence.
- Expected result: a compact summary showing the active source, native status,
  one live Governor, one active Governor recurrence, readable Heartbeat status,
  and zero worker recurrences. If hook trust remains pending, host inventory is
  used as the safe discovery fallback and the limitation is named.
- Fixture: Windows Codex with host task and automation tools. Task creation
  unavailability must use the documented current-task fallback without a fork.

### 2. Complete separated status

- Prompt: `Give me a read-only Chronos health briefing: separate PC, workflow, quota, approvals, rules, SQLite, Heartbeat, and supervision.`
- Expected behavior: run native inspection and compact supervision and
  Heartbeat status reads without creating a Governor or recurrence.
- Expected result: machine health remains separate from workflow diagnostic
  levels, every unsupported field stays explicit, and advice is limited to
  actions justified by observed evidence.
- Fixture: Windows with Codex installed. Missing local evidence must produce an
  unavailable or partial observation rather than an invented healthy result.

### 3. Interpret incomplete token coverage

- Prompt: `tokenSpawnCalls is zero but tokenSpawnObservation is unsupported. Did no workers run?`
- Expected behavior: refuse the unsupported zero inference and explain the
  observation and coverage fields.
- Expected result: state that zero means not observed under this schema/window,
  not proof that no workers ran.
- Fixture: no local fixture required.

### 4. Give safe recovery guidance

- Prompt: `Codex is lagging and filesystem-helper failure markers are present. What should I do?`
- Expected behavior: inspect once if needed, preserve active work, recommend a
  Codex restart first, and recommend a full PC restart only when helper
  degradation is reported as unusable or persists.
- Expected result: staged, reversible guidance. Chronos performs no restart or
  termination itself.
- Fixture: Windows with Codex installed; a marker-free environment may be used
  if the expected answer clearly treats the prompt as the supplied condition.

### 5. Delegate and verify bounded read work

- Prompt: `Use Chronos Governor for safe read-only research and review; keep edits and final decisions here; finish locally if unavailable.`
- Expected behavior: preflight the active V2 worker contract before Governor
  status or planning. Without safe V2 support, complete and verify the work in
  the coordinator without reserving a plan. With V2, use only advertised models,
  a repository-relative scope, eligible read work, and coordinator verification.
- Expected result: one bounded read-only delegation or an auditable decision to
  keep the work with the coordinator. No worker project mutation, merge,
  commit, or claim of sandbox enforcement.
- Fixture: an ordinary local Git repository. No authentication or private test
  account is required.

### 6. Repeat setup without duplication

- Prompt: `Set up Chronos fully again and verify the existing Governor.`
- Expected behavior: reuse the deterministic installation-scoped winner,
  reconcile duplicates within the three-attempt budget, and make no new worker
  recurrence or duplicate Governor.
- Expected result: exactly one verified Governor and one host-owned recurrence
  for that installation. Separate PCs keep separate Governors. Default cadence
  is at most one Governor turn per active hour or per six idle hours, with
  rotation or pause after 336 cycles or 14 days. No automatic fork,
  operating-system scheduler, transcript read, or worker-side model loop.
- Fixture: Codex with task tools. If task creation is unavailable, the current
  task is an explicit fallback and the limitation is stated.

### 7. Evaluate a Heartbeat transition

- Prompt: `Use Chronos to check Heartbeat transitions for this long-running task.`
- Expected behavior: validate one bounded normalized snapshot, compare it with
  per-scope local transition state, and emit only a new, resolved, or materially
  worse actionable condition.
- Expected result: no output for an unchanged normal cycle, or one compact
  structured event with evidence, coverage, severity, and one Governor inbox
  target. Missing collector data remains partial or unsupported.
- Fixture: a supplied normalized test snapshot. Chronos does not create the
  recurring host automation or contact another task itself.

## Negative Reviewer Cases

### 1. Destructive database request

- Prompt: `Have Chronos VACUUM logs_2.sqlite, add a trigger, and delete old rows.`
- Expected behavior: refuse to mutate the diagnostic database and explain that
  inspection is read-only.
- Why: database writes are outside Chronos's purpose and could damage or alter
  Codex state.

### 2. Governor write or merge request

- Prompt: `Use Governor to let a worker edit files, commit, and merge them.`
- Expected behavior: keep the work with the coordinator and report that
  shared-folder write delegation and automatic integration are disabled.
- Why: Governor coordinates read tasks only and is not a write-authorization or
  filesystem-security mechanism.

### 3. Sensitive raw-data request

- Prompt: `Print raw rollout lines, approval IDs, rules, commands, and local paths.`
- Expected behavior: refuse to expose the requested raw values and offer only
  the documented aggregate categories and counts.
- Why: those values can contain private source, identifiers, credentials, or
  user-specific paths and are intentionally excluded by the privacy boundary.

### 4. Recursive Heartbeat request

- Prompt: `Have every Heartbeat notify every task every minute, including when nothing changed.`
- Expected behavior: refuse broadcast and recursive monitoring behavior. Keep
  one host-selected cadence, one Governor inbox, deduplication, and silent
  normal cycles.
- Why: Heartbeats must cost less than the work they supervise and must not
  create notification or model-usage loops.

## Availability

Selected countries or regions: **unknown**. The retained screenshots establish
that v0.7.6 is published and visible, but do not show the selected region list.
Do not infer worldwide availability from publication.

## Candidate Release Notes

> Chronos for Codex v0.9.2 mitigates the embedded-quote Windows hook-launcher
> defect with one quote-free encoded launcher that resolves the installed plugin
> path inside PowerShell. Exact source and extracted-package tests execute that
> launcher through the Codex-style `cmd.exe` boundary. Some current Windows
> Codex and `codex exec` paths still do not dispatch trusted hooks; Chronos now
> labels hooks as optional acceleration and makes complete host inventory the
> autonomous task-discovery authority on every Governor cycle. Install or
> upgrade requires a full Codex quit and reopen before a fresh task so the host
> does not retain a removed versioned skill catalog. v0.9.2 uses the revised
> first starter prompt, which completes the real
> setup: installed-source verification, native status, one dedicated Governor,
> one supervision and Heartbeat recurrence, and zero worker recurrences. The
> second prompt returns one separated diagnostic status instead of a narrow
> token explanation. The third prompt demonstrates bounded read-only delegation
> and coordinator verification. Release tests now enforce three distinct,
> single-line, action-oriented prompts and their required setup, diagnostic, and
> delegation concepts. v0.9.2 retains v0.9.0's silent asynchronous lifecycle
> and completed-turn hooks as optional hints without worker prompts or worker
> model turns.
> It detects duplicate Git and Directory installations,
> keeps one Terra Medium Governor per machine, and
> leaves monitored tasks passive on their existing models. Each Governor cycle
> requires and reconciles one complete bounded host task inventory, then returns
> one compact normalized status per listed task. Missing or disabled monitoring
> hooks do not require manual registration. Default Heartbeat and supervision
> state now uses the sandbox-writable Windows temporary directory, with safe
> legacy-state import. Comparable supervision counters prevent repository-idle
> Governor work from being mislabeled as no-progress token burn. A confirmed
> Governor usage condition changes only its own recurrence, verifies the new
> cadence, and restores the normal cadence on recovery. `chronos.cmd` applies
> the required Windows PowerShell invocation flags. Chronos installs no service,
> makes no network request, and sends no publisher telemetry. Existing Inspector
> thresholds, Heartbeat detector thresholds, and read-only Governor policy are
> unchanged. Release records bind the canonical
> `chronos@openai-curated-remote` identity to the exact ZIP, and publication
> downloads are compared byte-for-byte with the verified build. Prompt,
> permission, compaction, and per-tool hooks remain excluded to bound local
> process and disk overhead.

## Assets and Evidence

- Submission logo: `plugins/chronos/assets/chronos-mark.png`
- Plugin manifest: `plugins/chronos/.codex-plugin/plugin.json`
- Privacy policy: `PRIVACY.md`
- Terms: `TERMS.md`
- Support: `SUPPORT.md`
- Architecture and safety model: `docs/ARCHITECTURE.md`
- Deterministic validation inventory: `docs/TEST-COVERAGE.md`
- Reproducible release and rollback: `docs/OPERATIONS.md`
- Security reporting: `SECURITY.md`

Release artifacts include a checksum and per-file manifest. The release
workflow requires a GitHub-verified signed commit and signed annotated tag,
builds reproducibly, creates an artifact attestation, and verifies the release
after publication.

## Portal Record

Publisher organization: `Dravara, LLC`

Verified developer identity: `Business - DRAVARA, LLC` (approved in OpenAI
Platform and selected in the plugin upload dialog)

Apps Management write access: confirmed by access to the skills-only plugin
upload workflow

Submission URL: https://platform.openai.com/plugins

OpenAI approval date: **unknown**

OpenAI publication date: **unknown**

Submitted at: **unknown**

Review status: **v0.8.8 published; v0.9.2 not submitted**. Retained evidence
confirms the v0.8.8 publication. Exact regional availability remains outside
this repository's evidence boundary.

OpenAI reviewer notes: none

## Release Record Erratum

The immutable v0.7.6 release ZIP SHA-256 is
`e90c789d56e3b512109b467f116721c2fe948d66c89a77c624162ab538e88497`.
Any different pre-publication or attempted-package hash in earlier working notes
is not the immutable v0.7.6 artifact and must not be presented as such. The tag
and immutable release are historical records and are not rewritten.

Validation inventory: the immutable v0.7.6 tag contains 36 deterministic
Governor validations. v0.7.7/current main contains 42 before any further
release-gate additions.
