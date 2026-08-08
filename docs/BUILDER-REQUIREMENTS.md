# Consolidated Builder Requirements

This ledger maps the consolidated 0.6.0 builder handoff to shipped behavior.
"Unavailable" is an implemented result state when the bounded local schema does
not expose enough evidence. It is not converted to zero or inferred from text.

| Area | 0.6.0 disposition |
| --- | --- |
| Reviewer discovery and exact turn counting | Implemented from exact `turn_context` model records; bookkeeping is excluded. |
| Reviewer identity and parent lineage | Sanitized counts implemented; raw session and parent IDs are intentionally not returned. |
| Review rate, interval, peak, concurrency, model, version, provider | Implemented when structured values and timestamps are present. |
| Reviewer versus primary token aggregates | Implemented as bounded lineage-delta snapshots, never described as billing. |
| Denied review activity | Implemented only for structured response records; otherwise unavailable. |
| Runaway reviewer warning | Existing quota contributors remain frozen; raw review measurements are exposed without adding an uncalibrated severity threshold. |
| Fork and lineage governor | Parent/fork counts, selected bytes, size clusters, exact replay bytes, and replay percentage are implemented without returning IDs. |
| Inherited history | Exact copied records and exact ancestor token snapshots are detected; child totals use the observed delta. Non-exact inheritance is unavailable rather than guessed. |
| Rollout growth and projection | Implemented as explicitly labeled file-lifetime metadata estimates. No background history is created. |
| Compaction amplification | Unique exact snapshots, duplicated snapshots, and duplicated bytes are implemented. |
| Approval source analysis | Implemented for structured shell, filesystem, network, and unknown request types. |
| Repeated approval classes | Implemented only from whitelisted categorical fields. Commands, arguments, prompts, and paths are not fingerprints. |
| Approval optimization | Diagnostic advice is implemented; any narrow rule remains manual, explicit, reversible, and user-reviewed. |
| Reviewer-model compatibility | Governor accepts runtime-advertised models and optional complete numeric cost ranks. It never assumes Luna or edits Codex catalogs. |
| Native automatic-review override | Reported as unsupported or unavailable unless Codex exposes a supported mechanism. Chronos never patches the harness. |
| Main versus infrastructure efficiency | Reviewer/primary ratio, spawn, compaction, replay, and storage observations are implemented with coverage fields. No savings claim is made. |
| Coverage and zero semantics | Complete, partial, unavailable, unsupported, and not-observed states are implemented. |
| Diagnostic database explanation | Contributing clauses and `not_measured` performance impact are separate from machine health. Sequence movement is not SSD-write volume. |
| Governor lease reliability | Implemented in 0.5.4 with writable per-user state, opaque plan tokens, explicit failures, and coordinator fallback. |
| Same-folder write safety | Implemented with canonical identity, attribution, fencing, one writer, scopes, fingerprints, and verification. |
| Runtime worker selection | Complete cost metadata selects the lowest compatible rank; absent or partial metadata preserves runtime order. |
| Safety and privacy | Inspector is read-only and ephemeral; no telemetry, scheduler, process termination, database mutation, approval mutation, or raw content output. |
| Token-savings validation | Protocol is documented; savings claims remain disabled until matched observations exist. |
| Threshold calibration | Frozen. A separate release requires the predeclared 14-day labeled study in `CALIBRATION-METHODOLOGY.md`. |

## Release Acceptance

The release gate requires diagnostics tests, 35 of 35 Governor safety controls,
plugin and skill validation, two byte-identical release builds, a signed release
commit, a signed annotated tag, GitHub verification, artifact attestation, and
immutable release verification.
