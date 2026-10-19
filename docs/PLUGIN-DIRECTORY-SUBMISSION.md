# OpenAI Plugin Directory Published Listing Record

## v0.10.1 Published Release And Review Submission

Version: `0.10.1`.

The user chose to preserve the original v0.10.0 tag and release the public-support
metadata correction as v0.10.1. Version 1.0 remains a later milestone. The original
v0.10.0 tag object is `2f431005de342f388fe4badd923b10c320337cb9`, pointing to
`63399c5190dc2162c46d86aa021fbda3f9365a64`; it must not be replaced.

The patch adds the public support guide required by the live portal, plus explicit
source and Directory-package regressions. Runtime executable files are unchanged.
The plugin manifest and runtime payload version are 0.10.1.

Full edition: `chronos-v0.10.1.zip`, 31 files, five opt-in hooks, SHA-256
`bc59db98bfc3bdbf8ef9d5fd496bf5dda6054c7b41cb7e4e8385354429148daf`.
Directory edition: `chronos-v0.10.1-skills-only.zip`, 29 files, zero hooks, SHA-256
`ab1d1fb2f61f2c80c25a80e5dafee69e9958ec5f7f1fd4cfba033afc8132956d`.
Published immutable release: https://github.com/FaxanFM/chronos/releases/tag/v0.10.1.
Signed source commit: `9f3281c6151802be0c2816d444b1642420c8b4b9`.
Signed annotated tag object: `8b09a0bea198e8ae8f75c624a9c67a7b5c79d377`.
GitHub reports valid verified signatures for both. PR #5 merged with history
preserved; the signed release commit is an ancestor of main with the same tree.

Release workflow https://github.com/FaxanFM/chronos/actions/runs/39322224758 passed
on windows-2022 and windows-latest, including source and exact packaged native
suites, Governor scenarios, reproducibility, usability, lifecycle removal,
signature trust, and Directory contracts. The Control Room Node 22/24 matrices
passed on Windows and Linux. Publication produced six immutable assets: ZIP,
checksum, and per-file release record for each edition.

Independent post-publication verification downloaded both ZIPs, matched the hashes
above, verified immutable release/asset bindings, verified the published SSH signer
for tag and commit, and verified attestation bindings to the exact source digest,
tag, and release workflow with self-hosted runners denied. Both editions returned
PASS. Installed-state checks were explicitly skipped; no production installation
or hook-trust change was part of this publication. Local receipts are in
`dist/chronos-v0.10.1-verified-directory/` and `dist/chronos-v0.10.1-verified-full/`.

The existing OpenAI draft `appsub_6ad633c8ddac81919c18de8361e9fde8` was updated to
v0.10.1 using the exact published Directory ZIP. Metadata and all three skill
scans passed with no findings. After the publisher explicitly accepted the final
terms and compliance declarations, submission succeeded. OpenAI shows
**v0.10.1 In review**, receipt `pluginrel_70891ebf268081918c13ff6288846049`:
https://platform.openai.com/plugins/manage/plugins_6a79c882cf488191b8f62ee20e0e2571?version=pluginrel_70891ebf268081918c13ff6288846049.
The marketplace update is not approved or published; the live listing remains
0.9.2. Do not publish the older approved 0.9.4 package. The full hook-enabled
edition remains on GitHub; the submitted Directory edition contains no hooks.

## v0.10.0 Publication Metadata Correction

The first portal upload created draft `appsub_6ad633c8ddac81919c18de8361e9fde8`
on the existing Chronos listing. Its live metadata check requires a support URL,
even though the skills-only documentation does not require every MCP listing URL.
The manifest now includes the existing public `SUPPORT.md` guide, with source and
Directory-package regressions. No runtime, hooks, permissions or version changed.

Corrected full ZIP SHA-256:
`8bb96eff6694570cd9275d111c23898012bc5ca96fdf0726f7f87d43351142d5`.
Corrected Directory ZIP SHA-256:
`d1cc4615050e8de9604514c15031b794f288d9573034f0ff732305c092d389f6`.
Both are in `dist/chronos-v0.10.0-support-fix/` and supersede the earlier candidate
hashes below. The Directory build uses the release-tag policy URLs.

PR #4 was merged. The first signed v0.10.0 tag points to
`63399c5190dc2162c46d86aa021fbda3f9365a64`; its release workflow was stopped before
publication after the portal finding. No immutable v0.10.0 release asset exists
yet. Correcting that unpublished tag requires explicit user approval; do not
silently replace a public tag or describe this draft as submitted or published.
The original source remains in Git history. Version 1.0 is the next milestone,
not the current release.

## v0.10.0 Control Room Candidate (Prepared, Not Submitted)

Version: `0.10.0`. This is the prepared candidate on the `codex/chronos-control-room`
branch. It is not uploaded, submitted, approved, or published, and it does not replace
the immutable v0.9.2 listing. The candidate adds a packaged, one-prompt Control Room
onboarding skill. On a supported desktop host it discovers the authenticated local
Codex executable, starts a private loopback UI, and leaves the queue paused until the
user grants execution consent. No manual server command is required.

The packaged path requires the local executor, Node.js 22 or newer, an authenticated
Codex installation, and local Git when a workflow needs an isolated worktree. The
skills-only edition contains no lifecycle hooks, hosted service, MCP server, publisher
telemetry, or automatic model turns. The full hook-enabled source remains available on
GitHub as a separately documented, opt-in edition; it is not silently installed by the
Directory package.

Two optional learning templates, `outcome_learning` and `tool_call_review`, add bounded
read-only analysis stages. They summarize observed execution evidence and propose
workflow improvements; they do not train a model, alter permissions, or apply changes
automatically. The candidate has local evidence of 68 unit tests, usability PASS,
deterministic 29-file skills-only packaging with zero hooks, and an extracted ZIP launch
on the normal host with the software-factory workflow plus both learning templates,
paused state, zero active turns, and package/instance identity binding. A subsequent
clean local-catalog installation in an isolated Codex profile verified all 29 installed
file hashes, the installed launcher, paused Research plus both learning modules,
identity binding, stop and uninstall. No production profile or hook trust changed.
These are local candidate results, not public Directory or all-OS certification.

The next submission, if authorized after review, must use a freshly built
skills-only ZIP bound to verified signed source, with its own immutable hash and receipt.
Do not reuse historical hashes
below or upload this working candidate by implication.

Signed package-source commit:
[`86d5b174bc8397461580d348ea5d114cbbc79233`](https://github.com/FaxanFM/chronos/commit/86d5b174bc8397461580d348ea5d114cbbc79233).
Its SSH signature verifies against `docs/security/allowed_signers`. Documentation-only
commits may follow on the same branch without changing the packaged source files.

Prepared artifacts in `dist/chronos-v0.10.0-final/`:
`chronos-v0.10.0.zip` (31 files), SHA-256
`03ab01788154a8f0b0a9b802caf95c925dda8f02620caea1369bb9ffe6842b07`;
`chronos-v0.10.0-skills-only.zip` (29 files, no hooks), SHA-256
`1dc88c3b16b78171eb8c0bc96801b58ef2fe191a6804723323d130561a6f4b9a`.
Only the skills-only ZIP is the prepared Directory upload. Its policy URLs and
`policy_source_ref` bind to the signed commit above, not a future release tag.
The neighboring `.sha256` and `.release.json` files bind the artifact and each
packaged/source file hash. The ZIP itself has no separate detached signature.
The full ZIP retains the default future-tag policy URLs and is not upload-ready
until a separately authorized release creates that tag. Neither artifact is a
published release asset.

Rebuild the prepared Directory bytes from this source history with Windows
PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1 -Version 0.10.0 -Edition Directory -PolicyCommit 86d5b174bc8397461580d348ea5d114cbbc79233 -OutputDirectory dist/chronos-v0.10.0-final
```

The execution-policy flag applies only to that build process; it does not change
the user's saved PowerShell policy or grant Control Room execution consent.
Reserved release URL: https://github.com/FaxanFM/chronos/releases/tag/v0.10.0
(not published). Source is under review in https://github.com/FaxanFM/chronos/pull/4.

Native worktree setup also disables repository Git hooks, filesystem-monitor
helpers and configured external filter commands. Committed checkout filters
require separate review before writable materialization; no LFS download or
repository helper is implicitly authorized. Marker regressions cover these
guards and retry after a reviewed repository repair.

The final bundle also includes complete license notices for all 18 bundled npm
dependencies. This notice-only change leaves executable browser bytes unchanged
but supersedes earlier v0.10.0 artifact hashes. The Windows signer test's expected
bad-trust probe no longer leaks its failure code into the successful host wrapper;
actual trust assertions remain enforced. Current-head CI must pass after both
corrections; do not use the earlier red run as a release receipt.

Before submission:

1. Local native verification and the final authenticated packaged launch passed.
   A fresh hardened four-stage workflow also passed with four actual model turns,
   native verification exit zero, unchanged source and a held human gate. No
   credentials were copied and the production profile was not changed.
2. Verify the signed source commit and the existing Control Room PR's current
   head. Require passing Windows and Control Room CI results for that head;
   historical green checks are not approval of a later commit.
3. Rebuild the Directory edition with the exact `PolicyCommit` above and confirm
   its ZIP hash reproduces. Review the signed commit and source/file-hash bindings.
4. Obtain release approval before merging, tagging or publishing immutable assets.
   The final Directory package must pin privacy/terms to public signed source;
   a reserved, nonexistent release tag is not an upload-ready policy URL.
5. Submit only the skills-only edition after explicit marketplace-update
   authorization. Retain the full edition on GitHub; do not auto-patch hooks.

## Local Usability Remediation Build - Not Submitted

October 6, 2026, after code-review corrections: the new local candidate adds native scoped removal, a tested
global hooks feature-control procedure and public signing trust/verification.
Full ZIP SHA-256 `02cadf9e23f489329268055ff211621970a607362884efb8f1e0034561281d42`
(14 files); Directory ZIP SHA-256
`c51e02198f00c95c8449c8608cfc6cadc2ce06d8e054f84eeb5f381f3f0c9402`
(12 files, no hooks). These bytes are not uploaded or published. Local removal,
Inspector, Heartbeat, Supervision, Governor (49 scenarios), reproducibility,
Directory contracts, hook configuration control and signing-trust checks pass.
Compatibility evidence for unchanged module hashes is detailed in the audit
response. The maintainer code review caught and corrected an unresolved-lease
removal guard, stale-backup precedence and the distinction between source and
packaged file hashes.
This is not an independent external audit or live desktop certification; do not use
the October 1 review receipt as approval of these different bytes.

October 5, 2026: the modified working tree builds a different full
`chronos-v0.9.4.zip`, SHA-256
`7738563b03186cdf82ca4ab62fb67cd002d0ee90a98c234b8a645d4e69b6ba9b`.
Two local builds matched. This is not the signed source pin or uploaded package
recorded below. It has not been installed, signed as a new candidate, uploaded,
or published. Release remains HOLD under
[the usability response](V0.9.4-USABILITY-AUDIT-RESPONSE.md).
Keep the previous submission receipt and hashes as historical evidence; a new
candidate needs its own signed identity, gates, review and submission.

## v0.9.4 Submission Candidate

Version: `0.9.4`

Local full draft: `chronos-v0.9.4.zip`, SHA-256
`8ede0807119bf2c25a6432acc80ba8137d315bd3fec3d11391a898d95c1114ae`.
It retains 14 release files and five optional hooks. Reserved future release
destination: https://github.com/FaxanFM/chronos/releases/tag/v0.9.4 (not published).

The separately labeled Directory ZIP is `chronos-v0.9.4-skills-only.zip`, SHA-256
`c734284e71bc84da12f30566ed09af8fa8548d6deea76496a32c3d0913c17bbb`.
It contains 12 release files, both skills, and no lifecycle hook configuration
or hook-intake launcher. Its manifest, skill notices, and README disclose the
skills-only edition. It does not auto-install GitHub hooks or patch managed caches.
Both artifacts prefer GPT-6 Sol with Medium reasoning; GPT-6 Luna is an
explicit supported choice, not a silent fallback or measured token-saving claim.

Uploaded to the existing Dravara, LLC listing on October 1, 2026 as draft
`appsub_6abed40a3b14819199513100bddb7e69`. Metadata and both skill checks passed.
The user accepted the submission terms and declarations, and the portal
confirmed **In review** under release record
`pluginrel_48e56ed7ffe08191be06cf0a5ab40871` on October 1, 2026.
Review receipt: https://platform.openai.com/plugins/manage/plugins_6a79c882cf488191b8f62ee20e0e2571?version=pluginrel_48e56ed7ffe08191be06cf0a5ab40871.
The public listing remains v0.9.2. This candidate is not installed in the
production account or published. It adds a packaged onboarding
entrypoint to the existing core skill, separate consent decisions, verified
setup receipts, and explicit local/publisher/provider data disclosures. See
[ONBOARDING.md](ONBOARDING.md). It changes no v0.9.3 release identity.

The full hook-enabled source still cannot be uploaded under the documented
hook exclusion. Optional GitHub hooks must not be installed covertly after a
skills-only review. The Directory-to-GitHub automation route is unverified;
the candidate reports that boundary and offers useful core setup instead. The
skills-only artifact has deterministic-build, edition-disclosure, hook-exclusion,
native scoped-cycle, process-restart, and unsupported-coverage checks. These
fixture checks do not establish live unattended scheduled execution.

## v0.9.3 Release Candidate

Version: `0.9.3`

The local full package is `chronos-v0.9.3.zip`, SHA-256
`2ba48cdde0dc9c718c6535abbd1743b1fffd6e042e18762f88fec2667724cac1`.
It contains 14 release files, including five optional lifecycle hooks.
New release destination: https://github.com/FaxanFM/chronos/releases/tag/v0.9.3.
This is a candidate until installed validation and release verification finish;
it is not a claim of publication or marketplace approval.

The current OpenAI submission documentation explicitly rejects ZIPs containing
lifecycle hooks or app references. Do not upload the full package to the portal
as if it meets that rule. A separately labeled skills-only edition requires its
own deterministic artifact, tests, disclosure, and submission receipt. Do not
remove hooks silently or change the prior published package in place.

Official UI guidance allows optional MCP Apps dashboards, explicitly describing
ChatGPT rendering and tool-only fallback. This release adds no dashboard, hosted
MCP service, telemetry, or assumption of native Codex component rendering.
Those require a separately tested integration and must not delay the scoped
governance correction.

The existing Platform listing was inspected on 2026-10-01 and reports v0.9.2
Published, both skill checks passed, and no metadata/skill issues. Its old
complete-host-inventory description needs the scoped correction. It has not
been replaced with this candidate.

## Historical Publication Records

Status at the earlier publication: v0.8.8 was published in the OpenAI Plugins Directory under the verified
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

The following record describes the earlier v0.9.2 development tree.
It is not authorized to replace an existing immutable GitHub release or the
published Directory package. It uses one bounded visible-or-specified current-host inventory as the liveness authority within that working set. It does not
enumerate inactive task history. It treats health evidence
as a separate contract. A schema-v2 collector snapshot carries a stable source
epoch, an increasing source sequence, and an explicit coverage label for each
of the eight public Heartbeat families. Missing evidence stays `partial` or
`unsupported`; it cannot become a clean result. Inspector aggregates are
accepted only after an authorized, compatible Inspector run produced them.

Governor bootstrap uses non-claiming preflight with `visible_or_specified` and
`current_host_runtime`. It governs at most 50 visible chats plus explicitly
selected chats, and only when they are active. Schema-v3 inventory declares
`scope=visible_or_specified` and `complete=false`. No pagination or account-wide
completeness proof is required. Missing current-host status authority still
fails closed. A separately spawned app-server is not Desktop liveness evidence.
Omission leaves scope without asserting a lifecycle end; hooks cannot add
governance membership. Known active titles and scope counts make selection clear.

The Governor resumes native intervention state before it evaluates new
transitions. Only native plan, claim, send, and record actions can wake one
verified task with the fixed message template. The scheduler stays at one
Governor recurrence and zero worker recurrences. That same recurrence uses the
verified 60-minute active cadence or 360-minute idle cadence.

The release also mitigates the embedded-quote Windows hook-launcher defect,
preserves terminal state when asynchronous lifecycle events arrive out of
order, and requires a full host restart after upgrade. It isolates supervision
state across restarted sandbox identities, gates recurrence creation on one
successful scoped-inventory cycle, permits Governor repository discovery
while ignoring user Git config, and makes overlapping Heartbeat cycles
explicitly retryable. Supervision and Heartbeat use canonical `CODEX_HOME`
installation identity, isolate separate Codex homes, reject reparse-point
ancestors before state creation, and reserve unscoped legacy migration for the
default `.codex` home.

Three first-use starters now lead to complete setup, an evidence-bound health
briefing, or bounded Governor research. Optional hooks use a small protected
intake path instead of loading the full supervision engine inside the
three-second host window. The next mutex-owning status or Governor cycle
validates, receipts, merges, and removes each accepted event. The Governor
assignment, result, verification, lifecycle, and exclusion contracts are
self-contained in the installed skill. The earlier, superseded local
`chronos-v0.9.2.zip` reconciliation package had SHA-256
`966098ada69f3ff54ccec06f81b0d1476647981d739e7be6a63a1a9f6e209a20`.
This is an unpublished local reconciliation repair, not a replacement for an
existing immutable release or an installed Directory package. It prioritizes
current work over ended-task history, handles newer inactive generations,
persists cycle retention cleanup, and blocks recurrence eligibility when
reconciliation cannot account for current work.
Existing release URL, not a destination for overwriting development artifacts:
https://github.com/FaxanFM/chronos/releases/tag/v0.9.2.

## Current Local Development Package

Status: local testing only, not submitted or published.

- Manifest compatibility version: `0.9.2`
- Artifact: `chronos-v0.9.2.zip`
- SHA-256: `0261f0685cf7b67231ddac5619786ba30fed4ae3a29cf753fdea68a5fd6744ff`
- Release files: 14
- Verified local runtime: Codex 0.159.2, Windows PowerShell 5.1

This revision removes nested PowerShell startup from the hook path, returns
neutral completion JSON, and binds schema-v3 inbox events to a hashed Windows
producer identity. A sandbox-account read fails with
`supervision_hook_identity_mismatch` while preserving the event. Scoped
host-account execution then merges it without loss. Real local hook dispatch
and native diagnostic execution passed; full regression gates are separate.

The former global-completeness requirement is superseded by the user's explicit
visible-or-specified scope. Local scoped regression and installed runtime
verification are required before claiming the updated Governor works. Do not
submit an unverified development ZIP, overwrite v0.9.2, or infer healthy coverage
from hooks. A public update requires a fresh version and verified release identity.

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
5. Add a fresh version to the existing **Skills only** plugin and upload only
   that version's verified immutable release asset after every gate passes.
   The local development `chronos-v0.9.2.zip` above is not a submission asset.
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

1. `Set up Chronos: verify source, create one Governor, explain hooks, and prove Heartbeat coverage and zero worker recurrences.`
2. `Run a Chronos health briefing: inspect PC, quota, reviews, rules, SQLite, Heartbeat coverage; separate evidence from unknowns.`
3. `Use Chronos Governor to split this repo review into bounded read tasks, verify each result, and keep edits and decisions here.`

All three are unique, single-line, at most 128 characters, and contain no app
mention.

## Positive Reviewer Cases

### 1. Complete first-use setup

- Prompt: `Set up Chronos: verify source, create one Governor, explain hooks, and prove Heartbeat coverage and zero worker recurrences.`
- Expected behavior: verify the installed source and native status, perform
  optional hook trust review when the host presents it, reuse or create one history-free Governor, and
  reconcile the installation-scoped recurrence without prompting worker tasks.
  Recurrence creation is a hard gate: failed initialization, unreadable native
  status, unreadable Heartbeat status, or an incomplete Governor-bearing
  inventory must leave zero current-key recurrences and schedule no recovery
  recurrence.
- Expected result: a compact summary showing the active source, native status,
  one live Governor, one active Governor recurrence, Heartbeat evaluation as
  observed, partial, or unsupported, and zero worker recurrences. Unsupported
  families are named and never summarized as healthy. If hook trust remains
  pending, current-host active inventory is used as the safe discovery fallback
  and the limitation is named.
- Fixture: Windows Codex with host task and automation tools. Task creation
  unavailability must use the documented current-task fallback without a fork.

### 2. Complete separated status

- Prompt: `Run a Chronos health briefing: inspect PC, quota, reviews, rules, SQLite, Heartbeat coverage; separate evidence from unknowns.`
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

- Prompt: `Use Chronos Governor to split this repo review into bounded read tasks, verify each result, and keep edits and decisions here.`
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
> labels hooks as optional acceleration and makes complete current-host active
> inventory the autonomous task-discovery authority on every Governor cycle.
> Install or
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
> requires and reconciles one scoped bounded host task inventory, then returns
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
