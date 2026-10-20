# Chronos v0.11.0 Candidate Handoff

**Superseded package record:** the UX/checkpoint candidate described below is
retained as historical evidence. The current persistent-agent candidate and
verification are documented in
[PERSISTENT-PROJECT-AGENTS-VERIFICATION.md](PERSISTENT-PROJECT-AGENTS-VERIFICATION.md).
Its new workflows use Hybrid conversation routing; existing omitted settings
retain legacy behavior until explicitly upgraded.

**Status:** prepared for review; not committed, published, submitted, or marketplace-approved.

This candidate packages the bounded orchestration work that is ready for an auditable release review. It does not claim adaptive planning, desktop control, token-budget management, remote execution, MCP/account provisioning, or automatic authorization.

## Delivered scope

- Typed, bounded collaboration feedback with explicit rejection, response, blocker, and human-resolution states.
- Immutable, hash-verified file checkpoints with protected manifests and content blobs.
- Fresh private workspaces for correction attempts; accepted work and prior snapshots remain preserved.
- Configured human review gates prevent routing until the user accepts; explicit automatic stages still require their configured native checks.
- Structured workflows remain the default and keep their existing behavior.
- Explicit execution and write consent; restart recovery revokes consent and requires confirmation before retry.
- Fail-closed behavior when checkpoint evidence is missing, tampered, unavailable, or unverifiable.
- Rename referenced workflows and save presentation-only layouts without changing queued work.
- Eight connection anchors, auto-arrange/snap, stage duplication and selection,
  task/workflow search, review/history filters and responsive canvas focus.
- Authenticated local API discovery/client, instance/workspace checks and live
  clean-editor updates that preserve unsaved drafts. No MCP registration.

The contract and limits are documented in [COLLABORATIVE-WRITE-CHECKPOINTS.md](COLLABORATIVE-WRITE-CHECKPOINTS.md). The new integration coverage is in `experimental/orchestrator/tests/collaborative-write.test.mjs`; the existing collaboration suite covers typed feedback, human review, cancellation, restart, and native verification repair.

## Editions

The full GitHub edition may include the five optional lifecycle hooks. Hooks are opt-in, local, and separate from the managed Governor and Control Room; they do not provide telemetry or remote access. The skills-only Directory edition contains the same guided setup, Governor, diagnostics, Control Room, collaboration, checkpoint, consent, and recovery features, but no lifecycle hooks. Hook installation is not silently performed by a starter prompt.

The local executor and an existing authenticated Codex login are required. No MCP server, new account connection or separate API key is added. A user still explicitly approves execution, workspace writes, and any optional hook trust in the host UI.

## Local Receipts

- Source runtime: 167/167 Node tests passed.
- Exact extracted skills-only backend: 118/118 tests passed across 13 suites.
- Both current editions built twice under inbox Windows PowerShell 5.1 with
  byte-identical ZIP hashes. Each extracted runtime import is self-contained.
- Browser checks: 23 layouts across Workflow, Queues, Collaboration and Runtime;
  no document-width overflow or off-screen tested action controls. Phone portrait,
  landscape, tablet and monitor checks include 100/150/200-percent-equivalent CSS
  viewport reflow, not automated native browser zoom or physical-device testing.
- Real API/UI renaming, saved anchors, focus mode, stage selection and dialog
  keyboard containment were checked locally. All remained paused with consent off.
- Earlier checkpoint-engine candidate's real local native proof: PASS; six
  dispatched turns, one rejection, one
  request-bound resolution, interrupted correction, verified runtime shutdown,
  explicit stop confirmation, revoked/re-granted consent, fresh recovery folder,
  unchanged source/prior snapshot and independent branch execution count one.
- Corrected review ran a native check with exit code zero and remains unaccepted.
- Earlier checkpoint-engine candidate's Windows PowerShell 5.1 release gate:
  PASS, two byte-identical builds. Separate source gates: Inspector, Heartbeat,
  Supervision and Governor PASS. Governor validated 49 declared scenarios;
  this is not a security-coverage percentage.
- The current exact skills-only ZIP launched through its packaged one-prompt
  launcher and restored the UI test queue paused, disconnected, with consent off.
  No new model turns were dispatched during this workflow-UX pass.

Current tag-form candidates are in `dist/v0.11.0-workflow-qol-candidate/`:

| Edition | ZIP | Files | SHA-256 |
| --- | --- | --- | --- |
| Full GitHub | `chronos-v0.11.0.zip` | 37 | `c5432a785e69dc452797c7ba494c1d9a15143e5655721a4916124a0076b240aa` |
| Skills-only Directory | `chronos-v0.11.0-skills-only.zip` | 35 | `a0e1a810f542fd951124b2535d443a56c2b2b6a6633f78b6b21ca3d55faff186` |

Each ZIP has a checksum and per-file release manifest. Both contain the same
18-file runtime. Policy URLs target the future v0.11.0 tag: publish the reviewed
GitHub release before uploading to the Directory. Earlier policy-commit-pinned
local preview builds in `dist/v0.11.0-candidate/` and the earlier checkpoint-engine
artifacts in `dist/v0.11.0-release-tag-candidate/` are superseded by this UX/API
candidate. No remote signature/attestation or immutability check is
claimed before an authorized signed publication.

`validation.json` in the same candidate directory records the local environment,
gate results, exact ZIP identities and the hash of the private aggregate native
proof receipt. The source changeset is staged but uncommitted. The installed
plugin remains unchanged; the open UX preview runs the current extracted
candidate, while the earlier native proof room and its results are preserved.

## Review steps

1. Run normal guided setup in a compatible local executor and confirm a paused room, privacy explanation, and no scheduled Governor or hook installation.
2. Run a bounded collaborative write fixture: accepted build, typed review rejection, fresh correction workspace, preserved prior files, and final human review.
3. Verify explicit consent, cancellation, restart recovery, and the requirement to confirm that a previous worker stopped before retry.
4. Verify that a missing or tampered checkpoint fails closed and that a write workflow without a checkpoint manager produces no model turn.
5. Confirm the skills-only package has no hooks and that the full GitHub package lists hooks as optional rather than required.

## Candidate release sequence

After independent review signs off the exact source and deterministic package, use the repository's existing release/build and verification scripts. Preserve the commit history, create the signed annotated version tag, build the skills-only and full GitHub artifacts from the reviewed source, and verify manifests, hashes, signatures, attestations, and immutable release assets before publication. Do not invent asset hashes or native PASS receipts in this document; attach the final generated receipts to the release record.

GitHub publication and marketplace submission are separate operations. A GitHub release does not make the Directory listing approved or live. Marketplace submission must use the existing listing and its current review workflow; it still requires a fresh authorized submission action and acceptance of any applicable declarations. This handoff does not perform either action.
