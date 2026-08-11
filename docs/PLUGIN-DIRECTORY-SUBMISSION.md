# OpenAI Plugin Directory Published Listing Record

Status: v0.7.7 is published in the OpenAI Plugins Directory. The focused
[v0.7.7 maintenance package](https://github.com/FaxanFM/chronos/releases/tag/v0.7.7)
is an immutable GitHub release and was submitted under the verified Dravara,
LLC business identity. Both OpenAI skill scans passed, OpenAI approved the
submission, and the public listing was verified at version 0.7.7. The
authoritative reproducible ZIP SHA-256 is
`b74e3a595f218eedf70658edd63364827f861e75d377d9a286cbdc91f88076ee`.

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
   `chronos-v0.7.7.zip` release asset.
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
- Version: `0.7.7`
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

Short description: `Diagnose Codex on Windows`

The display name is under the 30-character final limit. The short description
is one line and under the 30-character final limit.

Long description:

> Chronos is an on-demand local diagnostic and coordination plugin for people
> whose Codex sessions slow down after hours or days of work on Windows. It
> reports process pressure, diagnostic SQLite churn, token and context
> amplification, approval loops, permission-rule risks, rollout duplication,
> and filesystem-helper failures. It separates current machine health from
> other diagnostic conditions. It also marks missing or partial evidence.
> Chronos recommends proportionate recovery and coordinates bounded read tasks
> through Governor. It runs only when requested and sends no telemetry. It does
> not change SQLite rows or schemas, terminate Codex or unrelated user
> processes, or stop tasks. Governor can stop only its own bounded Git
> fingerprint subprocess. A
> logical read-only SQLite connection can create or update coordination
> sidecars, which Chronos reports. Governor
> is a coordination aid, not a sandbox or filesystem security boundary.

Developer name: `Dravara, LLC`

`FaxanFM` is the GitHub repository account, not the publisher identity.

Website: https://github.com/FaxanFM/chronos

Support: https://github.com/FaxanFM/chronos/blob/main/SUPPORT.md

Privacy: https://github.com/FaxanFM/chronos/blob/main/PRIVACY.md

Terms: https://github.com/FaxanFM/chronos/blob/main/TERMS.md

License: MIT

Supported platform: Windows with the Codex plugin runtime.

## Starter Prompts

1. `Use Chronos to inspect current Codex resource health.`
2. `Use Chronos to explain current token and approval pressure.`
3. `Use Chronos Governor to plan one bounded repository read task.`

All three are unique, single-line, under 128 characters, and contain no app
mention.

## Positive Reviewer Cases

### 1. On-demand health inspection

- Prompt: `Use Chronos to inspect current Codex resource health.`
- Expected behavior: run the installed inspection script once, on demand.
- Expected result: compact `CHRONOS` and `CHRONOS EFFICIENCY` summaries with
  machine health separated from diagnostic severity and explicit coverage.
- Fixture: Windows with Codex installed. Missing local evidence must produce an
  unavailable or partial observation rather than an invented healthy result.

### 2. Explain separated diagnostic levels

- Prompt: `Machine health is HEALTHY but logDb is CRITICAL. Explain this.`
- Expected behavior: explain that database size/reclaimable space is a separate
  diagnostic condition and is not proof of current machine failure, SSD wear,
  or repeated physical writes.
- Expected result: a concise explanation with proportionate next steps and no
  process termination or database mutation.
- Fixture: no local fixture required; the prompt supplies the observations.

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

### 5. Plan a bounded Governor read task

- Prompt: `Use Chronos Governor to plan one bounded repository read task.`
- Expected behavior: inspect Governor status, use only models advertised by the
  active runtime, request a repository-relative scope, and either return a
  bounded worker plan or keep the task with the coordinator.
- Expected result: JSON-prefixed `CHRONOS GOVERNOR` output. No project mutation,
  merge, commit, or claim of sandbox enforcement.
- Fixture: an ordinary local Git repository. No authentication or private test
  account is required.

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

## Availability

Selected countries or regions: **unknown**. The retained screenshots establish
that v0.7.6 is published and visible, but do not show the selected region list.
Do not infer worldwide availability from publication.

## Maintenance Release Notes

> Chronos for Codex v0.7.7 fixes diagnostic correctness without changing
> warning or critical thresholds. It reports SQLite logical read-only and
> possible sidecar activity, structurally parses Starlark rule patterns,
> detects stable-ID approval retries, requires resolved allowed outcomes before
> rule-miss advice, and corrects capacity, outcome, inventory, rollout-age,
> process-race, and V1 fork reporting. It also removes planned paid-service
> promotion. Telemetry, background behavior, and read-only Governor policy are
> unchanged.

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

Review status: **published**. Retained evidence confirms that v0.7.6 is visible
in the directory. It does not establish exact submission, approval, publication,
or region values.

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
