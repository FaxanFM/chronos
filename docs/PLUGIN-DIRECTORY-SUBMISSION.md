# OpenAI Plugin Directory Submission Packet

Status: package-ready for a publisher draft. The signed, immutable
[v0.7.6 release](https://github.com/FaxanFM/chronos/releases/tag/v0.7.6) is
published and its ZIP SHA-256 is
`d299682016ea0ee9957382240e3e2f25a9a31dbf35d2e900f3069aeefa3dbf3d`.
OpenAI review and publication have not occurred. Publisher identity and
organization permissions must be verified in the authenticated OpenAI
Platform.

Chronos remains installable from its public Codex marketplace while directory
review is pending.

## Official Submission Route

OpenAI's current submission instructions use the Platform portal, not the
public ChatGPT directory:

1. Open [organization roles](https://platform.openai.com/settings/organization/people/roles).
2. Confirm the submitter is an organization owner or has **Apps Management:
   Write**.
3. Open [organization general settings](https://platform.openai.com/settings/organization/general)
   and complete individual or business verification.
4. Open the [plugin submission portal](https://platform.openai.com/plugins).
5. Select **Create plugin**, choose **Skills only**, and upload the final
   `chronos-v0.7.6.zip` release asset.
6. Complete the listing, prompts, reviewer cases, availability, release notes,
   and policy attestations below.
7. Submit the draft for review. Approval does not publish automatically; after
   approval, publish the approved version from the portal.

Official references:

- [Submit plugins](https://developers.openai.com/plugins/deploy/submission)
- [Plugin submission errors](https://developers.openai.com/plugins/deploy/submission-errors)
- [Plugin guidelines](https://developers.openai.com/plugins/deploy/guidelines)

## Submission Type

- Type: **Skills only**
- Package name: `chronos`
- Version: `0.7.6`
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
> running long-lived or parallel Codex work on Windows. It separates current
> machine health from workflow, quota, rule, rollout, and diagnostic-database
> conditions; reports explicit evidence windows and unavailable data;
> recommends proportionate recovery; and coordinates bounded read tasks using
> advisory leases and final coordinator verification. Chronos does not modify
> Codex, terminate processes, stop tasks, alter SQLite, run in the background,
> or send telemetry. Governor is an advisory coordination aid, not a sandbox or
> filesystem security boundary.

Developer name: use the verified Platform identity that owns the submission.
Use `FaxanFM` only if that exact individual or business identity is verified.

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

Select only countries where the chosen verified publisher identity, support
process, privacy policy, and terms are ready. Do not claim global availability
by default. Record the selected countries in the draft before attesting.

Selected countries or regions: pending publisher decision

## Initial Release Notes

> Initial public-directory submission of Chronos for Codex v0.7.6. Chronos is
> a telemetry-free, on-demand Windows diagnostic and read-task coordination
> plugin. It reports Codex process, diagnostic SQLite, token/context, approval,
> rule, rollout, and helper evidence with explicit coverage boundaries.
> Governor coordinates bounded read tasks but is not a sandbox or security
> boundary. This skills-only package has no MCP server, UI, authentication,
> external API, background service, scheduler, or commerce.

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

Publisher organization: pending

Verified developer identity: pending

Apps Management write access: pending

Submission URL: pending

Submitted at: pending

Review status: not submitted

OpenAI reviewer notes: none
