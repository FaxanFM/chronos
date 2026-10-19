# Control Room Plugin Setup

## Release Status

Control Room is bundled in the **v0.10.0 candidate**, not retroactively added to
v0.9.4. The candidate needs review before the marketplace version is updated.
Do not describe an upload, local candidate ZIP or GitHub source PR as a published
Directory release. The Directory edition includes no lifecycle hooks.

## One Prompt

After installing the reviewed version in a supported local Codex environment,
choose its setup starter or ask:

> Set up the Chronos Control Room for this workspace and template: explain privacy and permissions before starting.

Chronos selects the current project unless you choose another, starts its
packaged runtime and opens the dashboard. You do not start a server, clone the
repository, install npm dependencies or patch hooks. Repeating the request
reopens the same workspace instance rather than starting another copy.

The default Software factory has Intake, Build, Review and Release gate stages.
Execution is paused. Add a work item, choose execution/write permissions and
select Run. The initial prompt does not authorize arbitrary work or account
actions. A release gate prepares a handoff; it does not deploy externally.

## Requirements

The host must expose local execution, a compatible authenticated Codex runtime
and Node 22+. The setup skill prefers Codex's bundled Node and Git paths through
the host's dependency locator; otherwise it checks existing installations.
Git is needed for isolated source worktrees. No credentials are copied and no
runtime is downloaded silently. Missing prerequisites produce a specific
compatibility result with an optional separately approved setup path.

Native worktree setup suppresses repository Git hooks, filesystem-monitor helpers
and external filters. Git must support `check-attr --source` for committed-tree
checks. A committed checkout-filter attribute, such as Git LFS, returns
`workspace_checkout_filter_requires_review`: materialization needs separate
review and is not silently run outside the managed sandbox. Read-only workflows
remain available. Setup does not install dependencies or fetch LFS objects.

The source is portable and automated runtime tests cover Windows/Linux. Live
account execution has been tested on Windows; universal OS/build certification
is not claimed. Browser-only/cloud conversations cannot govern the user's local
machine without a local executor. Windows Inspector diagnostics remain separate.

OpenAI documents a `requires_local_executor` marker for these packages. A local
MCP submission is a different approval route; this launcher does not add MCP to
the existing skills-only plugin. See [desktop-only requirements](https://developers.openai.com/plugins/deploy/desktop-only)
and [plugin packaging](https://developers.openai.com/plugins/build/plugins).

## Learning Options

Add Outcome learning or Tool-call efficiency review from New from template,
then select accepted outputs from earlier work as inputs. They do not run merely
because installed. Each is a four-stage read-only pipeline with human acceptance.
They propose a change, evidence, hypothesis and bounded comparison; nothing is
applied automatically. Their model turns use your allowance.

Native counts and wall time are observed event aggregates, not a completeness,
token-cost, CPU-time or causality claim. Unavailable evidence stays unknown.
See [learning boundaries](CONTROL-ROOM-LEARNING.md).

## Privacy And Stop Controls

No publisher telemetry is sent. Your configured provider processes task inputs,
selected context and relevant workspace content. The local state directory holds
plaintext queue records, receipts, private session metadata and worktrees. Keep
launch credentials out of recordings/support reports. Read [Privacy](../PRIVACY.md).

The local runtime may continue after the setup chat ends. Use Stop Control Room,
or ask Chronos to stop the room for that workspace. Active work requires a clear
stop confirmation. No startup service or scheduled chat is installed. Restart
does not grant fresh execution consent. Unknown workers stay blocked for explicit
recovery. Worktrees survive shutdown and queue archive.
