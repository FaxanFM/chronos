# Architecture And Safety Model

Chronos has two installed skills. Heartbeats is a native action of the existing
health-inspector skill, not a third skill, service, or application.

## Health Inspector

`chronos.ps1` takes one bounded snapshot of candidate Codex Windows processes,
filesystem-helper events, disk availability, and the known diagnostic SQLite
database. SQLite content access is logical read-only: Chronos does not change
rows or schemas, but SQLite can create or update `-wal` or `-shm` coordination
sidecars for a WAL-mode database. The inspector exposes the open mode, journal
mode, possible-sidecar flag, and observed-sidecar flag. Rollout access is limited to 2 MiB tails
from at most eight files selected by recent modification time from the session
date partitions overlapping the six-hour window, including old sessions
resumed recently. Session inventory streams filesystem entries under a
three-second target and a 20,000-entry hard cap. One filesystem call can exceed
the target; timeout and entry-cap results remain explicit.

The rollout parser retains only numeric token aggregates, effort labels,
structured automatic-review counts, compaction counts, spawn counts, bounded
rollout metadata, approval-state categories, and parser-integrity counters. It counts a review only from a
`turn_context` record whose model is exactly `codex-auto-review`; bookkeeping
records are not additional reviews. It retains a valid final JSONL record even
without a newline and ignores only a final record that fails strict parsing,
rejects invalid or negative counters, reports exact cross-file duplicates and
duplicated compactions separately, and chooses the greatest valid cumulative
token total per file. When a child contains an exact ancestor token snapshot,
the child contributes only the observed cumulative delta. Ephemeral hashes and
safe categorical approval classes exist only for the inspection process.
Structured prefix arrays and correlation identifiers may be converted to
ephemeral hashes for repetition and state-transition analysis. Raw lines,
prompts, responses, arguments, prefixes, hashes, output, identifiers, and paths
are never returned or persisted.

Every token metric reports its six-hour coverage window, eligible and selected
file counts, tail truncation, and continuity. Spawn and compaction counts also
report whether an event was observed, not observed in complete coverage,
outside partial coverage, or unsupported by the recognized runtime format.
Cache-write fields are `unsupported_schema` when the runtime does not expose
them; absence is never reported as a measured zero. Quota classifications list their contributing measured thresholds without
changing the frozen scoring rules.

Automatic-review counts, review rate, and reviewer-versus-primary aggregates
are bounded observations. The parser reports its coverage and labels token
totals as selected-rollout cumulative snapshots, never as account billing.
Request-level approval causes and structural equivalence are reported only when
the rollout schema exposes sufficient structured data. A persistence runaway
requires an allowed request, an unresolved pending state, and a later equivalent
request, including a repeated stable correlation identifier. Exact record
duplicates and exact same-time cross-schema mirrors are suppressed separately.
A rule-miss candidate requires at least two structurally equivalent,
independently resolved allowed reviews; denied, unknown, mixed, or unresolved
volume is insufficient. Repeated prefixes,
inspection-shaped operations, reviewer-originated escalations, nested reviewer
lineage, worker fork history, worker effort, and root/child spawn origin remain
separate concepts. Chronos never modifies approval state, policies, reviewer
configuration, runtime model catalogs, or sandbox permissions.

The Rule Governor reads bounded supported files in the known Codex rules directory.
It uses a bounded lexical parser for multiline `prefix_rule` blocks and parses
named arguments plus single-, double-, raw-, triple-, nested-, and escaped-string
literals. It classifies the `pattern` argument itself, calculates aggregate
length and structure statistics, and detects
credential-shaped patterns in memory. It never returns rule contents, prefix
hashes, commands, assignments, or credential values and never edits rules.

Filesystem-helper detection parses a timestamped event envelope and compares
the complete event message against known failure forms. Marker text embedded in
an unrelated payload does not count.

## Heartbeat Engine

`chronos.ps1 -Action heartbeat` invokes an internal deterministic transition
engine. The Codex host supplies one bounded normalized snapshot across the
monitored task set and chooses the recurring cadence. The recommended topology
uses one Governor task on `gpt-5.6-luna` with Medium reasoning. Monitored tasks
remain model-agnostic and do not run Heartbeats. Chronos does not create the
recurring automation, call a model, contact a task, or make a network request.

The engine supports eight families: agent stall, Guardian or automatic-review
runaway, usage burn, session or context explosion, test regression,
cross-machine drift, task dependency or zombie work, and Git or build state.
Each collector reports observed, partial, or unsupported coverage. Missing
fields do not become numeric zero or proof that a condition is absent.

Each cycle compares the current allowlisted aggregates with the previous
persisted aggregates. Stable condition keys, semantic severity escalation,
per-family cadence, condition-origin epoch binding, source sequence continuity,
and a restrictive canonical-state global per-user execution lock prevent
unchanged conditions, Windows path aliases, or duplicate scheduler runs from
repeatedly waking a coordinator. A bounded acknowledged outbox gives events
stable IDs and at-least-once host delivery semantics, including a repeated host
run after an interrupted delivery. A normal cycle with
no transition or pending delivery produces no output. Event records contain
concise evidence, ownership hints, and one Governor target. They never broadcast
to or directly wake monitored tasks. A host can forward a reviewed event under
an explicit policy.

The engine is not a scheduler, task transport, security boundary, telemetry
client, or general transcript store. Semantic interpretation and event delivery
remain host responsibilities. See [Heartbeats](HEARTBEATS.md).

## Governor

`governor.ps1` is a synchronous advisory read-coordination state machine. It has no
scheduler, daemon, network client, or independent worker transport.

The trust boundaries are:

- Runtime metadata supplies the current model inventory.
- Optional complete runtime cost ranks allow deterministic lightest-compatible
  selection; missing or partial ranks preserve inventory order.
- Canonical Git and filesystem identity supplies repository/workspace identity.
- Shared-folder write delegation is disabled.
- A bounded Git-visible fingerprint provides a warning check for read workers,
  not proof of filesystem read-only behavior.
- The coordinator performs semantic review and final acceptance.

Failure at any identity, lease, fencing, fingerprint, or
verification boundary returns work to the coordinator without deleting or
reverting files.

Governor temp state is worker-reachable and unauthenticated. Atomic replacement
and owner locks coordinate concurrent processes but do not establish state
integrity. Workspace fingerprints use bounded raw file reads and Git metadata
primitives; they never invoke working-tree conversion, `git diff`, textconv,
clean filters, external diffs, hooks, or pagers. Relevant Git override
environment variables are cleared around each invocation.

When the runtime exposes an effective worker model, binding and result reporting
must match the model persisted by `plan`. A difference fails with
`model_plan_mismatch`; absent runtime evidence remains `runtime_not_exposed`.

## Passive Supervision

The installed plugin bundles four lifecycle hooks: `SessionStart`,
`SessionEnd`, `SubagentStart`, and `SubagentStop`. Codex applies its normal
hash-based trust review before these non-managed hooks can run. Start and
subagent hooks are asynchronous; the host requires `SessionEnd` to be
synchronous. All return exit zero without output so they add no model context
and never block work on a registry failure.

The hooks invoke the internal `session-registry.ps1` module. It maintains a
bounded local discovery index with current-user Windows DPAPI protected task
and agent IDs, workspace hashes, safe model slugs, lifecycle state, counters,
and timestamps. It does not read the transcript path supplied by the host and
does not persist raw workspace paths. Atomic replacement, a named mutex,
reparse containment, size limits, and retention limits protect the write path.

A separate minimal `installation-scope.json` anchor stores a random 128-bit
opaque ID. It contains no machine-derived value and is not a credential. The
host uses the resulting scoped equivalence key to reconcile one Governor per
installation. This is necessary because a Governor on one PC cannot consume
another PC's local registry. The anchor survives session-registry recovery.

`chronos.ps1 -Action supervise` exposes status, single-Governor claim,
discovery, host-confirmed reactivation, and two-phase release. Registry liveness
is advisory; host task status is authoritative. Terminal lifecycle state has
precedence over delayed asynchronous starts. Bootstrap reconciles matching host
automations first, reuses a role-verified Governor, otherwise creates one fresh
task without inherited history, and uses a mutex-protected claim as the
same-machine ownership fence. A scoped host equivalence key, stable host-ID
ordering, a three-attempt budget, an exact postcondition, and two initial
convergence rechecks handle competing setup tasks. It does not automatically
fork a working task. The host owns
task creation, Luna Medium selection, one optional recurrence, compact rotating
task batches, and delivery. Worker tasks run no Chronos model cycle. The
recurrence is bounded to 336 cycles or 14 days. See
[Supervision](SUPERVISION.md).

## Persistent Data

The inspector persists nothing. Governor persists only coordination metadata
beneath the current user's temporary application-data directory, keyed by a
hash of Git's canonical common directory. An invoked Heartbeat cycle persists
bounded per-scope transition, cadence, coverage, deduplication, and engine-health
metadata plus a hashed, bounded delivery outbox beneath the user's local Chronos
application-data directory. It does not persist the raw collector snapshot or
raw route, subject, or owner IDs.

Passive supervision persists one bounded registry beneath the current user's
local application-data directory. Raw task and agent IDs are DPAPI protected
for that user; workspace identity is hashed. DPAPI does not defend against a
different process already running as the same user. Decrypted IDs are returned
only by local supervision status or Governor discovery for host routing and can enter that
task or host-tool context. The registry contains no transcript path, prompt,
response, source, command, tool argument, tool output, credential, username, or
absolute workspace path.

No component sends telemetry, starts a service, creates an operating-system scheduled task,
changes Codex database rows or schemas, terminates Codex or unrelated user
processes, or cleans worktrees. A user can separately ask the Codex host to
schedule Heartbeat evaluation. Governor can stop only the Git subprocess it
started when fingerprinting exceeds its time or byte limit.

## Calibration Boundary

Health thresholds and quota scoring are heuristic observations, not predictions
of failure. v0.8.1 does not change the existing inspector warning thresholds,
critical thresholds, scoring weights, or predictive claims. Heartbeat transition
rules are a separate engineering subsystem and must retain explicit coverage and
evidence. See [Calibration Methodology](CALIBRATION-METHODOLOGY.md).
