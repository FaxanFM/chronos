# Consolidated Builder Requirements

This ledger maps the consolidated Machine 1 and Machine 2 builder handoffs to
shipped behavior through 0.7.4.
"Unavailable" is an implemented result state when the bounded local schema does
not expose enough evidence. It is not converted to zero or inferred from text.

| Area | 0.7.4 disposition |
| --- | --- |
| Reviewer discovery and exact turn counting | Implemented from exact `turn_context` model records; bookkeeping is excluded. |
| Reviewer identity and parent lineage | Sanitized counts implemented; raw session and parent IDs are intentionally not returned. |
| Review rate, interval, peak, concurrency, model, version, provider | Implemented when structured values and timestamps are present. |
| Reviewer versus primary token aggregates | Experimental bounded estimates, never described as billing or trusted attribution. |
| Denied review activity | Implemented only for structured response records; otherwise unavailable. |
| Runaway reviewer warning | Existing quota contributors remain frozen; raw review measurements are exposed without adding an uncalibrated severity threshold. |
| Fork and lineage governor | Parent/fork counts, selected bytes, size clusters, exact replay bytes, and replay percentage are implemented without returning IDs. |
| Inherited history | Exact copied records and exact ancestor token snapshots are detected; child totals use the observed delta. Non-exact inheritance is unavailable rather than guessed. |
| Rollout growth and projection | File-lifetime estimates are suppressed under partial coverage; comparable timestamped tails also report marginal token deltas. No background history is created. |
| Compaction amplification | Unique exact snapshots, duplicated snapshots, and duplicated bytes are implemented. |
| Approval source analysis | Implemented for structured shell, filesystem, network, and unknown request types. |
| Repeated approval classes | Uses whitelisted categories plus an ephemeral hash of bounded structured prefix tokens. Raw commands, arguments, prompts, and paths are never returned. |
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
| Machine-count comparability | Machine, date range, schema, source, coverage, and continuity remain distinct. Local rollout counts are explicitly not dashboard-equivalent. |
| Allowed decision and approval share | Structured allowed/denied totals, allow percentage, comparable primary/reviewer turn share, duration, normalization, and confidence are implemented. |
| Approval persistence runaway | Implemented only for the strong `ALLOW` plus unresolved pending plus equivalent regenerated request pattern or an explicit persistence-write failure. |
| Fail closed after upstream approval persistence failure | Not enforceable by a diagnostic plugin. Chronos identifies the defect and recommends bounded fail-closed handling; Codex owns approval persistence and review regeneration. |
| Three approval problem classes | Persistence runaway, repeated rule-miss amplification, and legitimate/diverse boundary volume are reported separately. |
| Inspection-shaped approval pressure | Implemented from structured operation/prefix fields with actual boundary-cause categories when present. Read-only shape is never treated as proof that review was unnecessary. |
| Permission Rule Governor | Implemented for rule counts, long literals, brittle monolithic rules, reusable narrow candidates, broad interpreter rules, and secret-shaped structures. No rule is changed. |
| Credential-shaped rule safety | Counts plus bounded ordinal, safe shape category, and confidence are returned. Values, rule text, prefixes, hashes, assignments, and paths are never returned. |
| Current approval request schema | Structured `function_call` escalations are counted and terminal outputs are correlated ephemerally; commands, justification, output, IDs, and decisions not explicitly observed remain unavailable. |
| Governor abandoned plan recovery | Opaque-token `cancel-plan` is terminal; status separates unexpired pending plans from expired issued plans. |
| Repeated prefix rule miss | Implemented from ephemeral structured prefix hashes; exact prefix recommendations require later explicit user review and are never auto-created. |
| Reviewer-originated escalation | Tool calls, escalated calls, unique/repeated prefix counts, and largest repeat are implemented separately from nested reviewer evidence. |
| Reviewer recursion | Reported only when escalation and directly observed nested reviewer lineage coexist. Reviewer escalation alone is not called recursion. |
| Long lineage and concentration | Selected-window maximum task age and top-one/top-three reviewer share are implemented without returning lineage identity. |
| Fork context and worker effort | Explicit/defaulted full history, none, bounded history, inherited turns, high/max effort, and root/child spawn origin are implemented. Context amplification requires an explicit low/simple task label. |
| Infinite child fan-out negative case | Root-only spawning produces `nestedAgentObservation=not_observed`; it is not mislabeled as recursion. |
| Configured/effective reviewer | Safe labels are reported separately; a difference is `different_labels_mapping_possible`, not automatically a configuration defect. |
| Primary reasoning default | A safe configured effort label is reported for manual audit. Chronos never rewrites it. |
| Local token billing | Always `billingInference=unsupported`; partial rollout coverage produces low quota confidence. |
| Governor model contract | A reported effective model must equal the persisted planned model at binding and result reporting or return `model_plan_mismatch`. |

## Release Acceptance

The release gate requires diagnostics tests, all 41 Governor safety scenarios,
plugin and skill validation, two byte-identical release builds, a signed release
commit, a signed annotated tag, GitHub verification, artifact attestation, and
immutable release verification.
