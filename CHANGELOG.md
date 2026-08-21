# Changelog

## v0.9.2

- Mitigate one Windows lifecycle-hook non-execution path caused by Codex
  wrapping commands that contain embedded quotes at its `cmd.exe /C` boundary.
- Replace every Windows hook command with one constant quote-free
  `-EncodedCommand` launcher. The decoded PowerShell resolves `PLUGIN_ROOT`
  internally and invokes only Chronos's packaged session-registry script.
- Preserve the existing five-event design, asynchronous flags, synchronous
  `SessionEnd`, three-second host ceilings, silent output, and zero-model-turn
  behavior.
- Persist bounded terminal tombstones when `SessionEnd` or `SubagentStop`
  arrives before its asynchronous start record, and keep a delayed subagent
  start ended when its parent task has already ended.
- Add deterministic tests that run the exact manifest launcher through the
  Windows command boundary, including from an installed plugin path with
  spaces, and require a fresh registry counter and timestamp.
- Distinguish host-reported hook configuration or trust from observed command
  execution. Host task inventory remains the automatic liveness fallback until
  a fresh lifecycle event proves hook execution.
- Make one complete host inventory per Governor cycle the explicit autonomous
  task-discovery authority. Lifecycle hooks are optional accelerators because
  some current Windows Codex and `codex exec` paths do not dispatch them even
  when the host reports them active and trusted.
- Require a full Codex quit and reopen after installation or upgrade before a
  fresh task, because a running host can retain a removed versioned skill
  catalog.
- Add a complete-status skill contract that runs Inspector, supervision, and
  Heartbeat status without creating a Governor, recurrence, worker, event, or
  task wake.
- Retain v0.9.1's full-setup, diagnostic-status, and bounded-delegation starter
  prompts and their deterministic listing-quality gates.
- Move supervision state to a machine-and-Codex-home-scoped private v2 TEMP
  namespace. Treat inaccessible prior state as preserved read-only evidence
  instead of failing the new registry, and never attempt to modify it.
- Make recurrence eligibility an explicit postcondition of a successful
  initialization, readable supervision and Heartbeat state, verified Governor
  identity, and one complete host inventory that contains that Governor. A
  failed or partial setup creates no recurrence.
- Run Governor Git probes with the canonical repository explicitly marked safe
  for the subprocess. This preserves repository identity after a Codex restart
  changes the sandbox execution identity while ignoring global and system Git
  config files and without changing user Git config.
- Return an explicit retry contract for a unique Heartbeat cycle that overlaps
  the bounded state mutex wait. Do not silently discard the cycle.
- Snapshot all matching Governor recurrences, pause or remove them, and verify
  zero active matches before initialization. Any failed setup rechecks both
  pre-existing and newly created matches and never schedules its own recovery
  turn.
- Separate all same-name host observations from the verified current-installation
  mutation set. Foreign and unverified keys are never changed, a concurrent
  installer loser cannot delete the winner, and post-eligibility reconciliation
  failure returns the current-key recurrence count to zero.
- Bind concurrent-loser handling to the native
  `supervision_governor_conflict` error. Pre-mutation election losers skip
  initialization; both loser entries are no-mutation and cannot fall through to
  generic recurrence cleanup.

## v0.9.1

- Replace narrow first-use prompts with three distinct product actions: complete
  setup, separated full status, and bounded read-only Governor delegation.
- Make complete setup explicitly verify the installed source and native status,
  reuse or create one dedicated Governor, enable supervision and due Heartbeat
  evaluation in its single recurrence, and prove zero worker recurrences.
- Require a compact setup result instead of exposing unexplained internal state
  such as `governorClaimed`.
- Rewrite Directory descriptions and capabilities around the current product,
  including passive task discovery, actionable Heartbeats, exact-target
  intervention, Windows diagnostics, and bounded read-worker coordination.
- Add deterministic release tests for prompt count, uniqueness, length,
  semantic coverage, listing claims, and end-to-end public setup guidance.
- Correct the core skill text to describe all five monitoring hooks, including
  the asynchronous completed-turn signal and synchronous `SessionEnd`.

## v0.9.0

- Use supported asynchronous command hooks for `SessionStart`,
  `SubagentStart`, `SubagentStop`, and `Stop`. Keep `SessionEnd` synchronous as
  required by Codex.
- Add one silent completed-turn activity signal per main task. This lets a task
  first observed after installation register itself without a prompt, worker
  recurrence, model call, transcript read, or model-visible hook output.
- Deduplicate activity by a SHA-256 turn hash and persist only bounded counters,
  protected task IDs, safe categories, and timestamps. Prompt, response,
  transcript, tool, and raw turn data remain excluded.
- Keep the complete host task inventory as the liveness authority on each
  Governor cycle. Hooks reduce discovery delay; they do not wake tasks,
  authorize interventions, replace host reconciliation, or create model turns.
- Continue to exclude prompt and tool hooks. This avoids launching a process for
  each tool call and keeps routine monitoring overhead bounded to task
  lifecycle changes plus one short local process after a completed main turn.

## v0.8.9

- Make `supervise cycle` the only action that advances a Governor cycle. It
  requires one fresh, complete, bounded host inventory and atomically
  reconciles every listed task before returning the rotating check batch.
- Return one compact hash-only normalized status for every host-inventory task.
  Passive `discover` no longer advances cycle counters, and normal cycles state
  that a claimed Heartbeat intervention is required before any task wake.
- Remove the timing-sensitive wall-clock assertion from supervision tests.
  Mutex contention is validated by deterministic state, queue, silence, and
  cleanup postconditions while production hook timeouts remain fixed.
- Bind release records to the canonical Directory identity
  `chronos@openai-curated-remote`, attest all release assets, download every
  published asset for byte comparison, and verify the published record against
  the ZIP digest.
- Add a clean-install gate that extracts the exact ZIP beneath the canonical
  Directory cache identity and requires successful package discovery with no
  legacy Git conflict.

## v0.8.8

- Add a bounded `install-status` preflight that identifies valid cached Chronos
  sources without treating cache presence as proof that a source is enabled.
- Detect the common legacy Git marketplace plus OpenAI Plugins Directory
  duplicate, name `openai-curated-remote` as canonical, and require a fresh
  task after plugin-manager cleanup because loaded task catalogs cannot be
  changed by a skill.
- Surface install-source status in normal inspection output and update the
  first Directory prompt to check installation sources with resource health.
- Document the Directory-first install path and the narrow, user-approved
  migration from `chronos@chronos`. Chronos never edits plugin configuration or
  cache files directly.

## v0.8.7

- Remove background execution flags from packaged lifecycle hooks because
  current Windows Codex hosts can skip handlers marked `async`. Keep all four
  lifecycle-only handlers headless, silent, and bounded to three seconds.
- Fix Rule Governor false-safe classifications for interpreter options whose
  following value is not a fixed command or script payload. Unknown layouts
  now fail conservative; curl URL prefixes remain broad because trailing
  transfers are allowed; a recognized PowerShell `-File` operand remains constrained.
- Make supervision lifecycle transitions monotonic by timestamp and rank,
  persist host task generation, fail closed when the shared Global mutex is
  unavailable, atomically reserve bounded pending-event slots, verify forced
  Governor takeover, and durably write the installation-scope anchor.
- Bind Heartbeat conditions and interventions to task generation and compatible
  test environment/suite identity. Add bounded intervention list and expired
  claim reconciliation so one Governor can resume provably unsent work after
  interruption without waking unrelated tasks. Expired or legacy claimed sends
  become `delivery_unknown` and never retry without proof of a definite failure.
- Bind subject and owner generations separately so owner-targeted remediation
  cannot compare a parent task with its child's generation. Missing owner
  generation fails closed when subject generation is already known. Corrected
  or rotated owner evidence replaces the stale pending Governor envelope and
  re-arms the open condition without messaging the monitored task.
- Restrict public intervention verification to the correct lifecycle states
  and allowlisted host evidence. Internal detector recovery remains a native
  cycle-only transition.
- Bound and strictly validate Governor JSON, persist status migrations, and
  reject duplicate keys, unknown record fields, reparse ancestry, path escape,
  and hard-linked state files.
- Return an explicit retry contract when a unique Heartbeat cycle cannot obtain
  its mutex. Remove working-directory input from the default Heartbeat identity
  and apply strict JSON ambiguity checks to bounded rollout records and nested
  JSON-encoded function-call arguments.
- Correct current documentation for the immutable v0.8.6 publication, opt-in
  automatic hooks and recurrence, and bounded local pseudonymous state.
- Discover the v0.8.6 CWD-derived default namespace during upgrade and import
  schema migration read-only. Prior source content and timestamps are preserved;
  only the new stable namespace receives the upgraded, rebound state.
- Keep inspector thresholds, scoring weights, predictive claims, telemetry
  policy, disabled shared-folder writes, and one-Governor topology unchanged.

## v0.8.6

- Limit `interface.defaultPrompt` to the three prompts accepted by the OpenAI
  Plugin Platform. Keep resource inspection, token and approval diagnosis, and
  dedicated-Governor supervision as the default entry points.
- Add a release regression that rejects more than three default prompts and
  rejects empty or non-string prompt entries before packaging.
- Keep Chronos runtime behavior, frozen diagnostic heuristics, local-only
  privacy model, and one-Governor topology unchanged from v0.8.5.

## v0.8.5

- Distinguish an inaccessible prior Heartbeat scope from absent prior state
  even when Windows normalizes the protected child lookup to `ObjectNotFound`.
  Chronos performs a bounded read-only directory probe and reports
  `prior_state_unavailable_new_root` when access is denied.
- Treat the prior TEMP scope as authoritative when it exists but is inaccessible
  or invalid. Chronos does not fall back to older LocalAppData state and import
  stale conditions, interventions, outbox records, or deduplication history.
- Reject reparse points in every ancestor of a prior-state candidate before
  probing or importing it. A junction at the hashed prior TEMP directory cannot
  redirect migration to state outside the approved namespace.
- Add `priorStateDisposition` and `priorStateWriteAttempted` to compact
  Heartbeat status. These fields state the migration code path and attest that
  Chronos did not attempt to write, rename, delete, take ownership of, or change
  permissions on prior state. They do not claim to verify unreadable contents
  or ACLs.
- Keep the v0.8.4 operational upgrade recovery, state-path containment, frozen
  diagnostic heuristics, and one-Governor topology unchanged.

## v0.8.4

- Recover safely when a prior Heartbeat state directory was created under a
  different Codex sandbox identity. Default Heartbeat state now uses the
  versioned `%TEMP%\Chronos\Heartbeat-v2` namespace.
- Import valid readable v0.8.2/v0.8.3 Heartbeat state without changing the old
  directory. If the prior state is inaccessible, start in the new namespace
  and report `prior_state_unavailable_new_root` instead of blocking status or a
  live cycle.
- Keep inherited current-user TEMP permissions for new Heartbeat and
  supervision state. This prevents a transient sandbox SID from locking a
  later Codex identity out while hashed metadata and DPAPI-protected task IDs
  retain the existing privacy boundaries.
- Add an installed-runtime regression for inaccessible prior Heartbeat state.
  It verifies successful status, successful live-cycle persistence in the new
  namespace, stable scope identity, and no ownership change to the old state.
- Restrict explicit Heartbeat state paths to the approved versioned TEMP or
  LocalAppData Heartbeat roots. A JSON path in an unrelated TEMP sibling now
  fails before creating a directory or file.
- Keep all v0.8.3 containment controls and frozen diagnostic heuristics
  unchanged.

## v0.8.3

- Fix the supervision state-store containment defect found by the external
  v0.8.2 canary. An explicit state path elsewhere under `%TEMP%` is now
  rejected; only `%TEMP%\Chronos\Supervision` and the private LocalAppData
  supervision root are accepted.
- Run supervision fixtures inside the approved private subtree and add a
  regression that rejects a sibling path under `%TEMP%`. This reproduces the
  installed-package geometry that the earlier repository-relative fixture
  missed.
- Keep the v0.8.2 autonomy behavior and frozen diagnostic heuristics unchanged.

## v0.8.2

- Move default Heartbeat and supervision state to the sandbox-writable Windows
  temporary directory. Preflight the store, reject unsafe ancestry, apply a
  current-user ACL when Windows permits it, and import valid legacy LocalAppData
  state without changing the installation identity.
- Add bounded host-inventory reconciliation. One Governor task can recover
  tasks missed by disabled or delayed hooks, reactivate host-verified tasks,
  and close absent tasks only from a fresh complete inventory. Workers remain
  passive and require no setup.
- Report hook execution separately from hook trust. A missing lifecycle event is
  no longer presented as proof that hooks are trusted or working.
- Add `chronos.cmd` as the supported Windows launcher so every model and host
  invocation uses noninteractive Windows PowerShell 5.1 with per-call execution
  policy bypass.
- Recommend one Terra Medium Governor per machine. Monitored tasks keep their
  existing models and receive no recurrence.
- Require comparable Governor supervision counters before classifying its token
  use as no-progress burn. Completed cycles, state changes, and acknowledgements
  count as progress even when repository files do not change.
- Expose those five counters in compact Heartbeat status and migrate schema 4
  or 5 state to schema 6, so the Governor can build its own usage sample without
  a hidden host ledger or invented zero values.
- Replace fixed runtime-edge warnings with bounded adaptive self-health
  classification. Isolated modest overruns remain quiet, sustained or material
  degradation backs off, recovery clears the backoff, and compact status reports
  the budget, observation, overrun, baseline, rationale, and decision.
- Make confirmed Governor usage control local and deterministic. The host
  changes only the Governor recurrence to 360 minutes, verifies one active
  matching recurrence, and restores the active or idle supervision cadence on
  recovery. It does not message monitored tasks without independent
  same-subject and same-window evidence.
- Keep task discovery, transport, recurrence, and routine recovery failures in
  the Governor. Only a genuine user-authority boundary is returned to the user.
- Expand deterministic tests for state-store preflight, host reconciliation,
  missed hooks, stale inventories, Governor progress counters, local throttle
  and restore events, and packaged launcher behavior.

Existing Inspector warning and critical thresholds, quota scoring, predictive
claims, shared-folder write policy, and no-publisher-telemetry behavior are
unchanged.

## v0.8.1

- Add a bounded Governor-to-task intervention state machine. It separates event
  delivery, target resolution, send claims, transport certainty, task replies,
  and independent postcondition verification.
- Keep one active intervention per target. Coalesce simultaneous equal or lower
  severity events, replace an unsent record on material worsening, and permit at
  most one initial send plus one definite-failure retry.
- Treat an uncertain send as `delivery_unknown` and never retry it blindly.
  Transport acceptance is not task acknowledgement, and a task report is not
  proof of recovery.
- Bind replies to the exact hashed target, host generation, intervention ID, and
  version. Persist only hashes, allowlisted categories, counters, and timestamps.
- Add fixed safe intervention templates and fail closed for ambiguous targets,
  target-policy mismatches, unavailable transport, user-only authority,
  installs, permission or model changes, process termination, restarts,
  destructive Git, and publication.
- Forbid Governor self-targeting. Keep standalone Governor-origin usage local,
  require same-subject and same-window corroboration before an affected-task
  intervention, and keep token volume separate from unknown cost or quota impact.
- Remove routine user action requests from convergence, rotation, and
  intervention recovery. The Governor communicates directly with the exact
  affected task through host task tools; normal cycles remain silent.
- Add privacy-bounded lifecycle discovery for `SessionStart`, `SessionEnd`,
  `SubagentStart`, and `SubagentStop` through reviewed plugin hooks.
- Keep lifecycle hooks headless and off the turn, prompt, tool, and approval
  paths. They emit no model context and start no worker recurrence.
- Retain the empty bounded fallback directory after reconciliation so a
  concurrent lifecycle writer cannot lose an event to a parent-delete race.
- Run the complete Heartbeat suite against the built package in CI and make its
  validation-order boundary independent of the package extraction directory.
- Add one native `chronos.ps1 -Action supervise` command surface for compact
  status, Governor claim, active-task discovery, and release.
- Store task and agent identifiers with current-user Windows DPAPI, retain only
  hashes, safe model labels, lifecycle state, counters, and timestamps around
  them beneath local application data, and never persist transcript or workspace
  paths.
- Define deterministic Governor bootstrap order: reuse a host-verified
  Governor, otherwise create one fresh history-free task, and use the current
  task only as an explicit fallback. Never fork a working task automatically.
- Add a stable random installation-scoped host equivalence key, ordinal winner selection, a three-attempt
  reconciliation budget, and an exact one-Governor/one-recurrence/zero-duplicate
  postcondition for concurrent installers and recovery.
- Keep different PCs on separate Governors for their separate local registries;
  the opaque installation anchor contains no machine, user, path, or workspace data.
- Recheck installation-scoped host convergence only during the first two Governor pulses so
  eventually visible concurrent candidates converge without a permanent scan.
- Make the dedicated Governor the only recurring model task. Request Luna
  Medium when the host offers it, leave monitored task models unchanged, use
  fair rotating host task batches, and end normal cycles silently. Default to
  at most 24 Governor turns per active day or four per idle day, with a
  336-cycle or 14-day rotation bound.
- Add atomic registry replacement, bounded retention, named-mutex concurrency,
  reparse containment, corrupt-state preservation, monotonic terminal lifecycle
  handling, host-confirmed reactivation, visible capacity pressure, two-phase
  release, crash-reconciling bootstrap instructions, and deterministic Windows
  supervision tests.
- Keep hook lock waits to 100 ms for start and subagent events and 250 ms for
  session-end events. On contention, queue one bounded DPAPI-protected event and
  merge it during the next hook or Governor status so burst starts are not lost.
- Decode hook standard input as strict UTF-8 with optional BOM detection so
  lifecycle registration behaves consistently in interactive Codex and hosted
  Windows process environments.

Existing Inspector thresholds, quota scoring, predictive claims, Heartbeat
detectors, shared-folder write policy, and no-publisher-telemetry behavior are
unchanged.

## v0.8.0

- Add Heartbeats as a native action of the existing Chronos inspector skill.
- Add deterministic transition detection for agent stalls, runaway automatic
  review, unusual usage burn, session growth, test regressions, cross-machine
  drift, task dependencies or zombie work, and Git or build-state changes.
- Add per-family cadence and coverage, bounded per-scope local state, stable
  deduplication, material severity escalation, resolution tracking, duplicate
  execution protection, source epoch/sequence continuity, strict duplicate-key
  JSON rejection, a restrictive cross-session mutex, and one Governor inbox.
- Add stable event IDs and a bounded acknowledged outbox. Pending events use
  at-least-once host delivery semantics and privacy-safe Governor retry,
  including recovery when a host retries the same run after an interrupted
  delivery. Retry cadence uses wall-clock delivery time rather than replayable
  snapshot evidence time, and due delivery precedes stale-evidence rejection.
- Bind recovery to the source epoch that opened each condition. Canonicalize
  Windows state identity across path-case aliases, reject hard-linked state
  files, and reject Windows or Unix path-shaped and secret-shaped event IDs.
- Keep scheduling, evaluator-model selection, semantic triage, and event
  delivery in the Codex host. Chronos does not install a scheduler, service,
  network client, or separate plugin.
- Keep monitored tasks model-agnostic and free of Heartbeat runs. Recommend one
  `gpt-5.6-luna` Medium Governor task, and retain owner IDs only as triage hints.
- End normal cycles silently. Persist no raw collector snapshots, prompts,
  responses, source, diffs, commands, tool output, credentials, usernames, or
  absolute paths.
- Add deterministic Windows tests for all detector families, state transitions,
  routing, deduplication, recursion protection, malformed inputs, persistence,
  delivery recovery, counter/source discontinuity, and concurrent execution.

Existing Inspector and Governor thresholds, quota scoring, predictive claims,
shared-folder write policy, and no-telemetry behavior are unchanged.

## v0.7.7

- Remove unrelated commercial material from the public and packaged product
  documentation.
- Add a deterministic release check that keeps product documentation focused
  on the local Chronos plugin.
- Describe diagnostic SQLite access as logical read-only, disclose possible
  `-wal` and `-shm` coordination-sidecar activity, and report the open mode,
  journal mode, possible mutation, and observed mutation.
- Parse Starlark `prefix_rule` named arguments and single, double, raw, triple,
  escaped, reordered, commented, and nested literal forms. Preserve pattern
  positions, nested command alternatives, raw Windows paths, decision semantics,
  arbitrary-code flags in any later position, option-only prefixes, and missing
  operands across nested alternative branches; fail partial instead of
  false-safe.
- Distinguish exact record duplicates, exact cross-schema approval mirrors, and
  later same-ID requests. Count stable-correlation pending retries after
  structured `ALLOW` outcomes.
- Require at least two structurally equivalent requests with separate explicit
  `ALLOW` decisions, terminal resolutions, and supported prefixes before
  suggesting a repeated permission-rule miss. Denied, unknown, inherited,
  prefix-unavailable, mixed, and unresolved repetitions do not produce it.
- Correct Governor `capacity_reserved`, known-decision allow-rate denominators,
  complete approval-resolution reporting, large-rollout head timestamps, V1
  `fork_context=false`, and missing V1 fork semantics.
- Stream rollout inventory under a 20,000-entry cap and three-second target,
  disclose cap results, and isolate process property races with partial-sample
  confidence.
- Bind delegated plans to a pre-spawn Git-visible workspace fingerprint and
  reject lease activation after an intervening mutation; isolate process races
  in the legacy advisory candidate path as well.
- Align the manifest publisher with Dravara, LLC and replace obsolete pending
  directory copy with the verified public listing and explicit unknown dates
  and regions.
- Expand Windows regressions for SQLite sidecars, structured rules, stable-ID
  approvals, safe rule-miss postconditions, V1 fork data, rollout head age,
  inventory bounds, process sampling, and plan reservation reporting.

No warning threshold, critical threshold, scoring weight, predictive claim,
telemetry behavior, background behavior, or read-only Governor policy changed.

## v0.7.6

- Publish the v0.7.4 engineering changes through GitHub's required
  draft-upload-publish flow for repositories with automatic immutable releases.
  v0.7.4 and v0.7.5 remain immutable source-only records; v0.7.6 is the first
  packaged release in this series. Runtime behavior is unchanged.

No diagnostic threshold, score, prediction, telemetry, background behavior, or
Governor policy changed.

## v0.7.5

- Repackage the v0.7.4 engineering changes under a new immutable release after
  the v0.7.4 GitHub release was locked before its external assets were attached.
  Runtime behavior is otherwise identical to v0.7.4.

No diagnostic threshold, score, prediction, telemetry, background behavior, or
Governor policy changed.

## v0.7.4

- Recognize current structured `function_call` escalation requests without
  returning commands, justifications, tool output, IDs, prefixes, or hashes.
  Correlate terminal tool results to bounded resolved/unresolved and latency
  aggregates without inferring allow or deny decisions.
- Add marginal token deltas between comparable timestamped tail snapshots while
  retaining the existing cumulative input only as the frozen heuristic basis.
- Suppress file-growth and 24-hour projections whenever rollout coverage is
  partial, capped, truncated, malformed, duplicated, unreadable, or out of order.
- Expose unchanged machine-threshold contributors and state explicitly that UI
  responsiveness is not measured. Add privacy-safe rule ordinals, shape classes,
  and remediation confidence without returning rule text or values.
- Add token-authenticated `cancel-plan`, separate expired from pending plans,
  report the active manifest version at runtime, and document the atomic
  single-write lease transition.
- Record successful v0.7.3 Governor status validation from a fresh task on an
  independent Windows installation.

No warning threshold, critical threshold, scoring weight, predictive claim,
telemetry, background behavior, or write-delegation policy changed.

## v0.7.3

- Reject parseable Governor state whose collections are not maps or whose
  revision is outside the non-negative signed 64-bit range, preventing schema
  drift and numeric overflow from collapsing into an opaque failure.
- Distinguish unreadable state, failed state reads, invalid JSON, and invalid
  state schemas while preserving the original file and failing closed.
- Add privacy-safe `failure_stage`, `exception_type`, and recovery metadata to
  otherwise unknown Governor errors without returning exception text, paths,
  state content, or identifiers.
- Document the upstream Codex behavior where an open task retains its old
  versioned skill locator after a plugin upgrade. Require a fresh task and
  prohibit copies or links that would run newer code under an older version.
- Add a sanitized public field-report ledger and deterministic regression cases
  for supported-version state corruption and revision overflow.

The independent canary's original v0.7.2 exception remains unclaimed until it
returns the hardened diagnostic result. No warning threshold, critical
threshold, scoring weight, predictive claim, telemetry, or background behavior
changed in this release.

## v0.7.2

- Prepare the skills-only package for OpenAI Plugin Directory review under the
  specific public name `Chronos for Codex` and the Developer Tools category.
- Remove the manifest screenshot field because Chronos has no plugin UI; the
  synthetic proof card remains a clearly labeled GitHub discovery asset.
- Describe Governor as advisory coordination of bounded read tasks rather than
  implying that it enforces worker filesystem permissions.
- Correct the privacy policy to describe bounded all-partition inventory for
  older tasks resumed within the current six-hour observation window.
- Add the official publisher prerequisites and the required five positive and
  three negative reviewer cases to the submission packet.

No runtime diagnostic, Governor, threshold, scoring, telemetry, or background
behavior changed in this release.

## v0.7.1

- Replace working-tree `git diff` fingerprints with bounded raw file reads and
  safe Git metadata primitives so configured clean, textconv, and external-diff
  processes cannot execute during Governor verification.
- Migrate Governor state to version 4 and quarantine every active version-3
  write plan or lease. Legacy write lifecycle actions cannot fingerprint,
  integrate, or merge; only an explicit coordinator release or retirement is
  allowed.
- Make partial SQLite, cache-write, rule-parser, rollout-head, spawn-schema, and
  process-ownership coverage explicit instead of treating incomplete evidence
  as fully healthy or supported.
- Detect structurally equivalent approval persistence retries across regenerated
  correlation IDs and deduplicate exact untimestamped rollout records.
- Enforce canonical-root containment for every inspector file reader, reject
  escaped reparse paths, and discover recently modified sessions across all
  date partitions within a bounded traversal budget without order truncation.
- Reserve concurrency for issued delegation plans and allow coordinator cleanup
  of expired verified read leases.
- Pin ordinary CI actions, test two Windows runner labels, parse PowerShell and
  JSON in pull requests, and enforce package file and byte limits before release
  content is materialized.
- Replace the legacy GitHub positioning, put install commands in the first
  README viewport, add sanitized 9:16 proof and social-preview assets, add a
  privacy-gated issue form, and prepare the OpenAI Plugin Directory submission
  packet.

No warning threshold, critical threshold, scoring weight, predictive claim, or
calibration-sensitive heuristic changed in this release.

## v0.7.0

- Disable shared-folder Governor write delegation and reject legacy write plans.
  Governor read workers are now described as advisory coordination, not a
  security boundary or verified read-only property.
- Emit the current Multi-Agent V2 `fork_turns=none` contract, remove the V1
  `fork_context` instruction, bind worker reuse to workspace and effort, enforce
  one active lease per worker ID, persist lease policy, and prevent terminal
  lifecycle rewrites.
- Sanitize every Governor-owned Git invocation against fsmonitor, textconv,
  external diff, hook, pager, trace, and environment execution surfaces; cap
  workspace fingerprint input.
- Parse bounded multiline permission rules, distinguish unreadable SQLite
  queries from healthy data, discover old sessions resumed recently, retain
  complete JSONL records without trailing newlines, deduplicate exact replayed
  events, and label unavailable cache-write telemetry instead of reporting zero.
- Separate machine health from resource and overall diagnostic levels, use an
  interval-based review rate, include prefix structure in approval equivalence,
  and distinguish a persistence write error from a proven persistence runaway.
- Package only tracked plugin files, add per-file release hashes, pin Actions,
  split unprivileged tests from publication, verify attestations before release
  creation, and add security, ownership, and dependency-maintenance files.
- Replace the manually asserted 100 percent security-coverage claim with an
  honest deterministic-scenario report. Warning/critical thresholds, scoring
  weights, and predictive claims remain frozen.

## v0.6.1

- Add an explicit approval-state persistence-runaway diagnosis that requires a
  structured `ALLOW`, an unresolved pending state, and an equivalent regenerated
  request; explicit persistence-write failures are counted separately.
- Add allowed/denied decision totals, allow rate, inspection-shaped pressure,
  boundary-cause categories, three-way approval-problem classification, and
  source, dashboard-equivalence, billing, duration, and confidence semantics.
- Add an on-demand Rule Governor for brittle monolithic rules, narrow reusable
  rules, overbroad interpreter rules, and credential-shaped rules. Rule text and
  credential values are never returned, persisted, or transmitted.
- Add reviewer-originated escalation, burst, nested-reviewer, configured versus
  effective reviewer, primary reasoning-default, task-age, dominant-lineage,
  `fork_turns`, worker-effort, inherited-turn, and root/child spawn observations.
- Reject a reported worker model that differs from the persisted Governor plan
  with the explicit `model_plan_mismatch` error at binding or result reporting.
- Add regressions for 590 review turns with 581 unresolved retries, 307 resolved
  repeated-prefix reviews, synthetic secret-shaped rules, inspection causes,
  reviewer escalations, full-history workers, root-only spawning, short-rate
  confidence, partial quota confidence, and exact/mismatched Governor leases.

Chronos remains advisory and does not alter approval state, reviewer settings,
permission rules, sandbox policy, or model configuration. Bounded fail-closed
handling after an approval persistence failure remains an upstream Codex runtime
requirement. No existing warning threshold, critical threshold, scoring weight,
quota heuristic, or predictive claim changed in this release.

## v0.6.0

- Add exact, schema-aware `codex-auto-review` turn counting that excludes
  similarly named bookkeeping records.
- Add reviewer-session, review-rate, reviewer-versus-primary aggregate, and
  review-coverage fields without exposing identifiers, prompts, commands, or
  raw rollout content.
- Add bounded rollout storage, explicitly estimated growth and projection,
  lineage counts, exact replay bytes, near-size clusters, and compaction
  duplication observations.
- Deduplicate exact inherited token snapshots by observed lineage delta while
  labeling non-exact totals as selected-rollout snapshots rather than billing.
- Classify structured approval sources and repeated request classes from safe
  categorical fields, with unavailable states when the schema is insufficient.
- Select a compatible worker by runtime-supplied cost rank only when ranking
  metadata is complete; otherwise preserve deterministic runtime order.
- Add 590-turn reviewer, approval-class, lineage-delta, privacy, ranked-model,
  and duplicate-compaction regressions.

No warning threshold, critical threshold, scoring weight, approval rule,
predictive claim, or calibration-sensitive behavior changed in this release.

## v0.5.4

- Move Governor runtime state out of Git metadata into a sandbox-writable,
  per-user location keyed by canonical repository identity.
- Make delegation plans persist normalized inputs and return short-lived,
  single-use tokens that leases consume after a native worker is created.
- Accept strictly validated canonical worker IDs, normalize comma-flattened
  scopes, and return explicit state-store and state-lock decisions.
- Add coverage-window, continuity, event-observation, machine-health, and quota
  contributor fields to diagnostic output so zeros and risk levels are
  explainable.
- Add Windows regressions for read-only Git metadata, preflight failures, plan
  token replay, canonical worker IDs, flattened scopes, and coverage semantics.

No warning threshold, critical threshold, scoring weight, predictive claim, or
calibration-sensitive behavior changed in this release.

## v0.5.3

- Require GitHub-verified cryptographic signatures on both the release commit
  and the signed annotated release tag.
- Upload every release asset to a draft before publishing it once under
  repository release immutability.
- Verify the published immutable release and each attached asset in the release
  workflow.
- Document the separate guarantees provided by signatures, artifact
  attestations, checksums, reproducible builds, and immutable releases.

No runtime behavior, warning threshold, critical threshold, scoring weight,
predictive claim, or calibration-sensitive behavior changed in this release.

## v0.5.2

- Discover and validate worker models from the active runtime inventory.
- Canonicalize repository and workspace identity across equivalent paths and
  linked Git worktrees.
- Add mutation-attributed writes, expiring fenced leases, renewal, owner-safe
  stale-lock recovery, and post-result content fingerprints.
- Fail closed for unverifiable same-folder writes, detached `HEAD`, reparse
  scopes, malformed state, and incompatible model inventories.
- Harden rollout parsing for malformed, partial, duplicate, and out-of-order
  records and eliminate substring-based filesystem-helper false positives.
- Add 100 percent critical safety-control coverage, real concurrent writer
  tests, reproducible packages, SHA-256 manifests, and GitHub artifact
  attestations.
- Document architecture, lease semantics, troubleshooting, calibration freeze,
  release verification, upgrade, and rollback.

No warning threshold, critical threshold, scoring weight, predictive claim, or
calibration-sensitive behavior changed in this release.
