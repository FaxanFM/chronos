# Persistent Project Agents: Implementation Audit

Base commit: `55cd7ee5b459f35bc9bec25b917a8f0ad619baad`. The working tree also
contains the staged v0.11.0 checkpoint/UX/API candidate and unstaged, tested
read-only in-process chat reuse. All of that work is retained. Before this
enhancement, the local regression suite passed 169/169 tests.

Installed executable: `codex-cli 0.163.0-alpha.10.2`. Generated protocol schemas
are private local audit artifacts. Online documentation is explanatory, not a
substitute for the installed protocol: https://learn.chatgpt.com/docs/app-server.
The initial contract audit did not use model calls, native archival, or
transcript deletion. Later development evidence and bounded native receipts
are separated below; neither is a marketplace or cross-host certification.

| Brief requirement | Current status | Evidence / change boundary |
| --- | --- | --- |
| Project-scoped logical agents | Implemented | Schema-v5 registry persists project, agent, stage references and lineage. |
| Conversation modes / new Hybrid default | Implemented with legacy boundary | New/explicitly upgraded workflows use Hybrid; omitted existing fields remain legacy. |
| Durable primary and work-item mappings | Implemented, host-bound | Session bindings and work-item scopes persist; native identity remains host-dependent. |
| Direct agent conversation | Implemented, read-only | Agents view queues local discussion; it does not grant execution or writes. |
| Safe in-process reuse | Implemented with guards | Reuse requires owned idle compatible session; writes/reviews/unrelated work isolate. |
| Durable resumption | Partial / host-dependent | Restart marks sessions uncertain and requires authoritative inspection. |
| Bounded backward collaboration | Implemented, partial continuation | Typed feedback and needs-input continuation preserve the same item without acceptance. |
| File checkpoint isolation | Implemented | Preserve verified fresh workspaces and artifact hashes. |
| Native lifecycle cleanup | Partial / host-dependent | Native archive and lost-receipt inventory recovery observed on installed host; no deletion claim. |
| Bounded durable project audit | Implemented, bounded | Revisioned local audit is finite and capacity-protected; not publisher telemetry. |
| Project knowledge/decisions | Implemented, provenance-bound | Human decisions and accepted-result evidence are distinct from proposals. |
| Context rotation / compaction | Partial / host-dependent | Explicit rotation and capability-gated compaction preserve identity; no silent reset. |
| Uncertain creation/start recovery | Implemented, host-bound | Persisted intent and explicit reconciliation prevent blind replacement. |
| Storage/session retention controls | Implemented, bounded | Finite retention protects records; native disk bytes/deletion remain unsupported. |
| Consent and isolated writes | Implemented | Restart revokes permissions; no change to external-effect authority. |
| Existing workflow migration | Implemented with release evidence | Validate first, retain source backup, preserve legacy behavior; final verification is linked separately. |

Implementation order follows the supplied brief: migration and identity; modes;
resumption; lifecycle; clarification; rotation; recovery and verification. Each
new capability must have deterministic tests. Live inference tests and destructive
cleanup are not authorized by the document itself; they require a direct user
decision. No immutable release or installed plugin is rewritten by this work.
## Final implementation summary

The working tree now contains the schema-v5 agent contract and bounded
`AgentController`, including durable project, agent, session, message, question,
decision, and archived-assignment records; Hybrid dispatch decisions;
primary/worker lineage; needs-input continuation; explicit session recovery; and
retention validation. The Control Room Agents view provides queued read-only
discussion, questions, a decision ledger, lineage, and recovery inspection.
Coverage is in `experimental/orchestrator/tests/agent-state.test.mjs` and
`experimental/orchestrator/tests/persistent-engine.test.mjs`; final aggregate
verification is reported separately.

This source audit alone is not a live-inference claim. Native
resumption, compaction, and cleanup remain host-capability and explicit-consent
dependent. Existing queues preserve omitted conversation fields as legacy
behavior; migration validates before writing and retains a source backup. No
marketplace publication or unattended multi-agent run is claimed here.
## Evidence boundaries

The local host probe `.local/persistent-live-20261020.json` records a bounded
six-model-turn verification on Codex `0.163.0-alpha.10.2`: primary-session
marker retention, same-item needs-input/answer continuation, observed
cancellation terminal state, and primary reuse after restart. This is real local
host evidence for those cases only; it is not a cross-host certification, a
marketplace guarantee, or proof of unattended operation.

Native cleanup is **host-dependent**. The controller protects
active, pinned, dependent, unresolved-question, and recovery-unknown sessions;
it records cleanup-pending when native archive capability is unavailable. The
installed host produced native archive and subscription-release receipts. A
separate no-inference engine probe recovered a lost local receipt through exact
archived inventory, including Windows canonical-path matching. This does not
claim transcript deletion or cross-host support. No installed plugin,
marketplace publication, or external account action was performed by this audit.
## Final scope boundaries

Hybrid is the default only for new workflows and explicitly upgraded projects;
missing conversation fields in existing workflows remain legacy. Agent chat is
local, queued, read-only discussion. It cannot approve work, grant writes, or
replace existing execution consent. Restart/disconnect revokes consent and
marks active or uncertain native sessions for explicit reconciliation; no
outcome is auto-accepted or replayed.

The six-turn local probe was development evidence on the installed host, not
evidence from the final exact package and not a general Codex certification.
Rotation, compaction, and portions of recovery were also exercised with
deterministic controller tests; mocked adapter behavior is labeled as such.
Native archive completion was observed in the later bounded receipt, while
native disk-byte accounting, transcript deletion, and a universal cleanup
contract remain unsupported. Retention limits protect records and report
unsupported coverage rather than claiming deletion.

See [final verification](PERSISTENT-PROJECT-AGENTS-VERIFICATION.md) for exact
package hashes, current regression counts, responsive checks and remaining
release boundaries. Historical working-tree receipts are not promoted into
evidence from a later package.
