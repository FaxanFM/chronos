# Control Room Learning Modules

Chronos Control Room provides two **opt-in** learning templates:

- `outcome_learning` reviews accepted prior-queue inputs, native verification metadata and artifact paths to produce an outcome retrospective and one bounded improvement hypothesis.
- `tool_call_review` reviews those same explicitly supplied artifacts for redundant, failed or repeated tool-call patterns and proposes one reversible workflow improvement.

Neither template runs by default, adds an extra turn to another pipeline, or changes the active workflow when created. Both are read-only, inherit the configured model, disable web search, allow one attempt by default, and finish in human approval routing.

The modules produce recommendation packages, not automatic adaptation. A package must distinguish observed evidence from interpretation and include a concrete proposed change, hypothesis, preserved baseline, bounded evaluation, success and failure criteria, run limit and stop condition. Missing measurements remain unknown: the modules must not claim timings, token metrics, costs or provider behavior without observed evidence. They do not read raw secrets or harvest logs, perform fake model training, or alter policy, permissions, routing, provider settings or accounts.

Human acceptance is required before any separately authorized follow-up. Rejected, unproven or incomplete recommendations remain unapplied.
