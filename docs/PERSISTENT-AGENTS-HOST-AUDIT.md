# Persistent project agents: host audit

The installed Codex app-server schema was generated locally from the configured
executable. It exposes `thread/start`, `thread/resume`, `thread/read`,
`turn/start`, `thread/compact/start`, `thread/unsubscribe`, and
`thread/archive`. Chronos uses a two-phase session API: `prepareSession` creates
and validates a thread, then the caller persists the returned binding before
`startSessionTurn` is allowed to send work.

Bindings include the stage identifier, thread ID, policy, canonical workspace,
model, reasoning level, instruction hash, runtime identity, and a binding hash.
Resume re-reads the actual host thread and verifies status, workspace, model,
runtime identity, and isolation. A label alone is never sufficient. Active,
unknown, external, or mismatched threads fail closed. A turn-start timeout is
reported as `session_turn_start_uncertain`; Chronos does not silently create a
replacement thread.

Archive is available only when the installed schema advertises both
`thread/archive` and cursor-based `thread/list`, including `parentThreadId`,
`nextCursor`, and the complete `ThreadSourceKind` enum. Chronos enumerates both
archived and unarchived pages with every source kind, using the negotiated
ancestor filter where available (otherwise bounded full traversal), then rejects
archive if a descendant is found, a page is malformed, or enumeration times out. There is no
caller-supplied boolean bypass and no destructive delete path in the adapter.

The generated schema is an audit artifact under
`experimental/orchestrator/.local/persistent-protocol` and is not a publication
or telemetry channel. It may be regenerated when the installed host changes.

The archive receipt is bounded evidence for the installed host and run only. It
does not establish transcript deletion, native disk-byte accounting, or a
cross-host cleanup guarantee. If enumeration, capability discovery, or the
close/release receipt is unavailable, Chronos must retain the session record
and report cleanup as pending/unsupported. Controller tests cover rotation,
retention protection, question/dependent guards, and recovery with mocked
adapter responses; those tests are not native host evidence.

The installed Windows host was also checked for a lost local archive receipt.
Chronos observed the exact archived thread in native inventory and persisted
`archived_inventory_observed` plus subscription-release evidence through the
engine, without inference or consent restoration. The native cwd filter is
case-sensitive, so reconciliation checks both the persisted binding path and
its realpath canonical spelling. A native "not found" error alone is never
treated as proof of archival.

Live compaction and rotation subsequently passed on the installed host. Its
current compaction completion consists of a `contextCompaction` item and the
same maintenance turn's successful terminal event. Chronos correlates thread,
turn and item identities before recording completion, also retaining legacy
notification support. An acknowledged but unobserved operation remains
uncertain and exposes recovery. The corrected probe recalled prior context,
rotated lazily with durable decision provenance, and resumed the successor
after restart without changing logical agent identity.
