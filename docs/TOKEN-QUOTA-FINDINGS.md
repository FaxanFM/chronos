# Codex Token and Quota Findings

Reviewed against OpenAI Codex commit
[`d06c7ac`](https://github.com/openai/codex/commit/d06c7ac055920c7cb140c25ebda3f3db20197b45)
and the OpenAI GPT-5.6 documentation on July 29, 2026.

## What an 80% cached-input share means

A high cached-input share is not itself a leak. It usually means a long,
append-only task is reusing most of its prompt prefix successfully. Cache reads
are discounted, but OpenAI states that cached prompt tokens still contribute to
tokens-per-minute rate limits. A 200,000-token active context can therefore
consume roughly 200,000 input tokens again at every model sampling step, even
when most of that input is read from cache.

GPT-5.6 changes the cost side: cache writes are reported separately and billed
at 1.25 times the uncached input rate. Cache reads and cache writes must be
measured separately.

Official references:

- [Prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching)
- [GPT-5.6 model guidance](https://developers.openai.com/api/docs/guides/latest-model)
- [Reasoning models](https://developers.openai.com/api/docs/guides/reasoning)

## Confirmed implementation gaps

### 1. Codex cannot express GPT-5.6 explicit cache breakpoints

The Responses request has `prompt_cache_key`, but no `prompt_cache_options`.
The content model has text and image fields, but no
`prompt_cache_breakpoint`.

- [`ResponsesApiRequest`](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/codex-api/src/common.rs#L251-L275)
- [`ContentItem`](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/protocol/src/models.rs#L711-L729)

Impact: Codex cannot pin a breakpoint after its large stable startup prefix.
Independent requests with a changing tail can rewrite cacheable input instead
of reading it. This matters more on GPT-5.6 because cache writes are billable.

This must be fixed upstream. Chronos can detect reported cache-write volume and
call it out, but it cannot add fields to Codex's internal API request.

### 2. Prompt-cache routing is scoped to the session

Codex defaults `prompt_cache_key` to the response metadata's session ID.

- [`prompt_cache_key`](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/core/src/client.rs#L475-L487)

Impact: fresh tasks and spawned agents with byte-identical startup context use
different keys. That limits reliable cross-task cache reuse and compounds the
missing-breakpoint problem.

An upstream fix should use a stable, privacy-preserving namespace for invariant
startup context while retaining per-thread isolation for changing history.

### 3. User-facing token totals omit material GPT-5.6 usage

Core protocol data includes `cache_write_input_tokens`, and app-server v2
propagates it. The terminal UI's local token model does not include that field.
Its displayed `total` is non-cached input plus output, excluding cached reads.

- [Core token fields](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/protocol/src/protocol.rs#L2057-L2072)
- [App-server cache-write propagation](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L1541-L1569)
- [TUI token model and blended total](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/tui/src/token_usage.rs#L11-L35)

Impact: the visible total is neither raw token throughput nor GPT-5.6-equivalent
cost. It can substantially understate quota pressure and omit expensive cache
writes.

## Confirmed amplification paths

These are not all defects, but they can multiply usage dramatically.

### Ultra and full-history subagents

Codex maps `ultra` to `max` for a model request. Multi-agent v2 defaults an
omitted `fork_turns` value to `all`, copying the full parent history. The
default permits four concurrent spawned-agent threads.

- [Ultra maps to Max](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/core/src/client.rs#L176-L180)
- [`fork_turns` defaults to all](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/core/src/tools/handlers/multi_agents_v2/spawn.rs#L194-L227)
- [Default multi-agent concurrency](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/core/src/config/mod.rs#L209-L221)

One large parent context can therefore be sampled by the root and several
high-effort children. Each child also receives a distinct session cache key.

### Retries can replay a full sampling request

The defaults allow four request retries and five stream retries. Codex hides
the first WebSocket retry in release builds, and transport fallback resets the
stream retry counter.

- [Retry defaults](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/model-provider-info/src/lib.rs#L26-L28)
- [Retry and fallback behavior](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/core/src/responses_retry.rs#L20-L73)

If a disconnect happens after backend work has begun, retries can consume
additional quota even when the user sees only one logical turn. Whether a
failed attempt is billed is backend-dependent, so retry count is evidence of
risk rather than proof of duplicate billing.

### Compaction inherits the active reasoning effort

Remote compaction sends the current turn's reasoning effort and has its own
retry loop.

- [Compaction request effort and retries](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/core/src/compact_remote_v2.rs#L330-L375)

Repeated compactions in a High, Extra High, Max, or Ultra task are therefore
not free housekeeping. Starting a focused new task at a clean milestone can be
more quota-efficient.

### Large tool output expands every later sample

Codex's unified execution path defaults to a 10,000-token output allowance per
tool call. A user override can lower the model-visible truncation budget.

- [Default tool-output allowance](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/core/src/unified_exec/mod.rs#L64-L72)
- [Config override application](https://github.com/openai/codex/blob/d06c7ac055920c7cb140c25ebda3f3db20197b45/codex-rs/models-manager/src/model_info.rs#L25-L49)

## Local remediation

Use the lowest reasoning effort that meets the task. Reserve Extra High, Max,
and Ultra for bounded work with a measurable quality benefit.

When quota matters, tell Codex:

```text
Keep this run quota-efficient. Do not use Ultra or spawn subagents unless the
work clearly divides. When spawning, use fork_turns="none" or the smallest
useful positive turn count and use medium reasoning unless deeper effort is
necessary. Summarize tool output before returning it to the main task. Start a
fresh task at the next clean milestone instead of repeatedly compacting.
```

Conservative global starting points:

```toml
tool_output_token_limit = 4000
model_auto_compact_token_limit_scope = "body_after_prefix"

[agents]
max_concurrent_threads_per_session = 2
default_subagent_reasoning_effort = "medium"
```

These settings trade some inherited context and raw tool detail for lower
repeat-input pressure. Validate them on representative work before applying
them organization-wide.

## What Chronos adds

Chronos reads bounded 2 MiB tails from up to eight recently active local rollout
files and reports only aggregate fields:

- cached-read percentage and observed cache-write volume
- reasoning share
- maximum active-context pressure
- High, Extra High, Max, and Ultra task counts
- subagent spawn and compaction counts
- a compact quota-risk level and action tags

Chronos never changes model settings, request bodies, tasks, or quota. It
creates no telemetry or persistent log and does not return prompts, responses,
tool arguments, tool output, usernames, or local paths.
