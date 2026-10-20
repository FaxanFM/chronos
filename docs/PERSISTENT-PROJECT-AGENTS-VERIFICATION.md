# Persistent Project Agents: Candidate Verification

Date: 2026-10-20. Status: locally verified release candidate; signing,
publication, submission and installation are separate receipts. Base commit:
`55cd7ee5b459f35bc9bec25b917a8f0ad619baad`, plus the
preserved working-tree checkpoint/UX/API work and this persistent-agent change.
The installed plugin remains v0.10.2. No immutable release was rewritten.

## Delivered

- Schema-v5 project agents, versioned instructions, primary/worker lineage,
  messages, correlated questions, provenance ledger and bounded audit history.
- Hybrid for new workflows, including API-created workflows with omitted mode.
  Existing omitted policies retain legacy behavior. Migrations validate first
  and preserve the exact original bytes in an exclusive checksum-named backup.
- Lazy native creation, durable creation intent before RPC, native binding saved
  before turn start, compatible resumption and isolated writers/reviewers.
- Same-item clarification without acceptance or a new attempt; ready-for-review
  cannot bypass a human gate. Unknown outcomes stop without blind replacement.
- Explicit rotation, capability-gated compaction, finite retention, subscription
  release and descendant-safe native archival with lost-receipt recovery.
- A responsive Agents view, direct read-only discussion, decision inbox,
  project knowledge, capacity controls and authenticated local API discovery.

Existing file checkpoints, isolated correction workspaces, workflow rename,
anchors, collaboration, model/thinking selection and guided onboarding remain.
Conversation handling and Structured/Collaborative graph routing are separate.

## Exact Draft Packages

Both editions contain the same 20-file runtime. Each ZIP was built twice with
identical bytes under inbox Windows PowerShell 5.1.

| Edition | Files | SHA-256 |
| --- | --- | --- |
| Full, five optional hooks | 39 | `9f7eca14d03476a7d0a9951626004f1b5d22e58a9818448ab5f2ae296678869e` |
| Directory, no hooks | 37 | `932491e89e6a28cf53aba19d92449e2ad97bf502df42a831c001f21c4d177409` |

Artifacts: `dist/v0.11.0-live-release/`. Repeated builds:
`dist/v0.11.0-live-release-repeat/`. The Directory archive is extracted
to `dist/v0.11.0-live-release-qa/`; backend tests are copied alongside it
without modifying packaged implementation files.

## Deterministic And Package Checks

- Source suite: **205/205 passed**, including correlated compaction and
  recoverable-maintenance regressions. Baseline before this enhancement: 169.
- Extracted Directory backend: **187/187 passed**, across 22 files.
- `tests/release.tests.ps1`: PASS, including two identical full builds and
  packaged native contract checks.
- `tests/directory-release.tests.ps1`: PASS, 37 files, zero hooks, reproducible;
  scoped native cycle/restart checks created zero model turns or recurrences.
  Eight unsupported health families remained unsupported; no live scheduler
  behavior was inferred from these checks.
- `tests/release-verification.tests.ps1`: PASS with local verification fixtures.
  Published-candidate signatures and attestations are unavailable before release.

The source suites cover migration backups, mode/default round trips, persisted
dispatch ordering, primary reuse, parallel isolation, question continuation,
stale-event rejection, scope changes, loaded/unarchived capacity, protection of
unresolved work, capability fallback and archive descendant guards. Protocol
fixtures also cover lost archive receipts and Windows canonical cwd filtering.
Mocked host responses are not evidence of actual Codex execution.

## Actual Local Host Evidence

Installed host: `codex-cli 0.163.0-alpha.10.2`. Protocol discovery used its
generated experimental schema, not assumptions about another Codex version.

The authorized six-model-turn development probe passed:

1. Create a primary conversation with a synthetic test marker.
2. Recall that marker in the same native conversation without repeating it.
3. Return a structured needs-input outcome without accepting the assignment.
4. Answer and continue the same one-off session and attempt.
5. Cancel and observe terminal completion before releasing capacity.
6. Restart and recall the marker through the same native primary conversation.

This probe preceded final hardening; it is not an exact-final-ZIP inference
replay. Its six-turn budget was exhausted. The user subsequently authorized
live compaction and rotation testing, reported below. No model turns were run
for packaging, archival, browser checks or cleanup recovery. The historical
probe's restart-consent label was narrower than its name suggested; immediate
consent revocation is established by deterministic restore tests and the final
paused API check, not retroactively attributed to that model probe.

Separate native checks observed archival and subscription release. A later
no-inference engine check recovered an already-archived worker's missing local
receipt through authoritative archived inventory and persisted
`archived_inventory_observed`. A native not-found error alone is never proof.

### Live Compaction And Rotation

The separately authorized lifecycle probe used one disposable local project and
four short read-only discussion turns across its initial and corrected runs.
Two native compactions were requested. The first revealed that the installed
host emits a `contextCompaction` item and completed maintenance turn rather than
the older standalone notification. Chronos now requires correlated item/turn
completion (or the supported legacy notification), never just the RPC response.
Unobserved maintenance exposes explicit recovery and remains blocked.

The corrected probe passed native compaction, same-thread marker recall,
lazy rotation, stable logical agent identity, predecessor/successor lineage,
preserved decision provenance, and resumption of the same successor after
restart. Restart consent was checked immediately before reauthorization.
Local receipts: `.local/persistent-lifecycle-live-final-20261020.json` and the
earlier failure receipt. These use the actual release implementation; they are
not mocked-host results or a cross-host guarantee.

## UI And API

The exact extracted runtime was opened locally and left paused. API discovery
advertised all 11 new agent actions; state reported Hybrid, zero active tasks,
execution/write consent false and the recovered archived worker.

Agents-view checks at 1920x1080, 1280x720, 960x540, 768x1024, 1024x768,
390x844, 844x390 and 320x568 found one Agents panel, no document/panel width
overflow and no missing images. Console errors: zero. The desktop CSS viewport
sizes include 100/150/200-percent-equivalent reflow; this is not physical-device
testing or automated native browser zoom. History selection, project-default
round trip, disabled Run and all six retention controls were inspected.

Private receipts and screenshots are under
`experimental/orchestrator/.local/persistent-*`. Raw native IDs, queue contents
and launch credentials are not publication artifacts.

## Boundaries

- Managed sessions do not attach to or control independently running Desktop
  chats. No periodic supervisor model turn is required to keep an agent present.
- Native lifecycle support depends on the installed schema and observed host
  behavior. Unsupported capabilities remain blocked/pending, never simulated.
- Creation uncertainty without a returned native identity remains blocked for
  recovery. There is no distributed exactly-once guarantee or blind retry.
- Session turns, loaded/unarchived sessions, history and owned storage are finite.
  Capacity pauses work rather than discarding protected records. Native transcript
  disk bytes and destructive transcript/workspace deletion remain unsupported.
- Read-only policy is not a promise of project-confined read access. Provider
  traffic follows Codex configuration; Chronos adds no publisher telemetry.
- Restart revokes execution/write permission. Discussion, source files, agent
  results and API authentication cannot grant human approval or publication.

See the [implementation audit](PERSISTENT-PROJECT-AGENTS-AUDIT.md),
[installed-host audit](PERSISTENT-AGENTS-HOST-AUDIT.md) and
[local API contract](CONTROL-ROOM-API.md). GitHub signing/publication and a new
Directory review submission are separate release steps, not claimed here.
