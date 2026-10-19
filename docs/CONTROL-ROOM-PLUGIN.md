# Control Room Plugin Setup

## Guided Setup In v0.10.2

Version 0.10.2 adds host-advertised Model and Thinking level
selectors, hover/focus tooltips, task-based effort suggestions, and chat-led setup
from a goal and selected framework files or folders. Both the full GitHub and
skills-only packages include these features. The immutable v0.10.1 release
remains unchanged; installing it does not include the v0.10.2 additions.

The setup chat prepares a versioned JSON plan and passes `--setup-plan` to the
packaged launcher. The room opens the prepared workflow, paused, with optional
initial work queued but not authorized to execute. Selected context is bounded
to the workspace; references cannot grant permissions. Existing work is preserved
and conflicting plans fail closed. See the skill's guided-setup reference for
the handoff schema.

Model and thinking options come from the connected Codex host, not a hard-coded
list. Low is a starting suggestion for simple extraction/routing/formatting,
Medium for ordinary implementation/research/review, and High for complex security
or architecture work. Suggestions require an explicit Apply action and are not
claims about cost, speed, or quality. Unsupported explicit choices are blocked.

Enable isolated writes only for build/edit work or native checks that may change
an owned worktree. Leave the checkbox off for research, planning and review.
This permission does not authorize changing the original source, installing
software, accessing other accounts, or deploying results.

## Release Status

Control Room is bundled in the **published GitHub v0.10.1 release**, not
retroactively added to v0.9.4. The v0.10.0 tag is retained as the original
candidate; v0.10.1 carries the support-metadata correction. The skills-only
Directory update has been submitted and is In review, but is not approved or
published in the store; the current store version remains v0.9.2. The
Directory edition includes no lifecycle hooks.

Marketplace review receipt: https://platform.openai.com/plugins/manage/plugins_6a79c882cf488191b8f62ee20e0e2571?version=pluginrel_70891ebf268081918c13ff6288846049

Published packages: [Full GitHub release](https://github.com/FaxanFM/chronos/releases/tag/v0.10.1) and
[skills-only package](https://github.com/FaxanFM/chronos/releases/download/v0.10.1/chronos-v0.10.1-skills-only.zip).

## One Prompt

After installing the published GitHub edition, or after the reviewed Directory
update is available, in a supported local Codex environment,
choose its setup starter or ask:

> Turn my goal and selected framework files into a ready-to-review Chronos Control Room workflow. Recommend models and thinking levels, explain permissions, and open it paused.

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
