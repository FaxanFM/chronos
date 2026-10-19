# Chronos Onboarding And Consent

See [Current Versions](../README.md#current-versions) for publication records.
Source changes here do not update an installed or submitted package.

## Control Room Setup In v0.10.2

The v0.10.2 candidate uses this primary setup starter for both editions:

> Set up Control Room from my goal and framework. Suggest models and thinking. Explain privacy and permissions; open paused.

The packaged onboarding skill is `chronos-control-room`. It uses the current
workspace and selected framework files or folders to prepare a paused workflow,
with suggested host-supported models and thinking levels. Without a custom
plan, it uses the Software factory template and one execution slot unless the
user chooses otherwise. It resolves bundled or installed Node 22+ and local Codex,
launches the included runtime, verifies its private health response and opens
the dashboard. Users do not copy a command or manually keep a server terminal
open. A repeat request reuses the same workspace instance. A different running
payload is reported rather than silently claiming the upgrade loaded.

Setup is not execution consent. Explain provider processing, normal Codex
allowance, plaintext local queue/workspace state and the private session cookie.
The publisher receives no runtime telemetry. Run, workspace-write permission,
learning pipelines, Windows diagnostics and existing-chat monitoring remain
independent opt-ins. No hooks or scheduled Governor are required for this UI.
The process can continue after the setup chat ends; Stop Control Room closes
only its owned runtime. It is not registered as a startup service.

See [Control Room plugin setup](CONTROL-ROOM-PLUGIN.md) for the current release
gate, prerequisites, privacy and optional learning workflow.

## Legacy Governor Entry Prompt

The separate [installation guide](INSTALLATION.md) covers pinned GitHub
installation, the recommended optional hooks, restart, verification, and
uninstall. The prompt below begins onboarding after the correct skill catalog
has loaded; it is not a pre-install executable or an automatic trust grant.

> Set up Chronos for my active chats: explain privacy, offer optional hooks,
> configure one Governor, and verify what is running.

The Directory skills-only starter is:

> Set up Chronos for my active chats: explain privacy, configure one Governor, and verify scope and Heartbeat coverage.

It gives one hooks-absence disclosure, not a trust question for missing hooks.

Earlier packages pointed `extensions.com.openai.onboardingSkill` at `chronos`.
The v0.10.0 candidate adds the visible Control Room skill and changes that
onboarding entrypoint. The legacy Governor uses the same separate contract
when it receives a completed user-authorized setup. All decisions remain in
the setup chat before handoff. It does not send consent reminders
from scheduled pulses or require the user to relay technical commands between
chats. Before handoff, the setup chat identifies the elected Governor and
passes only approved choices, not the user's conversation history.

## The Conversation

First explain the working set: active chats in a visible local window of up to
50, plus explicitly selected chats. Not every active chat in the account.
Explain evidence limits: task activity is not proof of resource, quota, review,
rule, or other Heartbeat health.

Then explain privacy in plain terms. Chronos runtime scripts do not send data
to Dravara, LLC. They do retain bounded local metadata. Compact summaries and
routing handles can enter Codex chat context; OpenAI's controls apply there.
GitHub receives ordinary release-download requests and anything the user elects
to post publicly. Local-state hashes are pseudonymous, not anonymous. DPAPI
protects hook identifiers for the Windows user, not against other software
already running as that user. No support report is uploaded during setup.

Ask one decision at a time. Skip decisions the human has already answered
explicitly for this scope/version; do not treat another agent's report, a
default selection, or silence as consent.

| Decision | What the user gets | What is authorized |
| --- | --- | --- |
| Recurring Governor | Up to one Governor model turn per active hour or six idle hours; verified exact-target interventions when needed | One scoped Governor and one host recurrence after native gates pass; zero worker recurrences; model usage counts against Codex allowance |
| On-demand only | Compact checks when requested; no monitoring between requests | No new Governor claim, task, or recurrence; an existing recurrence is disclosed and needs scoped pause authorization |
| Review GitHub hooks | Explanation and inspection of five short lifecycle handlers | Review only; installation of an exact version/source change and hook trust are separate decisions |
| Keep hooks off | Core governance without new lifecycle evidence | No hook install or auto-trust; existing trusted hooks must be disclosed and disabled through supported controls with scoped confirmation |
| Decide later | Core setup can continue | No additional hook permission; preserve and disclose existing hook state |
| Allow automatic diagnostics | Bounded diagnostics when qualifying work or degradation needs evidence | Standing Inspector permission, passed as automaticDiagnosticsAllowed=yes; not every pulse |
| On request only | No autonomous Inspector runs | automaticDiagnosticsAllowed=no, including when health is unknown |
| Run briefing | Bounded Windows and compatible Codex health diagnostics | Inspector once; not standing permission, no broad validation suite or upload |
| Skip briefing | Core task checks without a new briefing | With on-request-only permission, subsequent unknown-health pulses do not run Inspector |

The Governor prefers GPT-6 Sol (`gpt-6-sol`) with Medium reasoning when the
current host advertises it. GPT-6 Luna (`gpt-6-luna`) with Medium reasoning is
available only as an explicit user-selected alternative. Verify the effective
host choice; a native recommendation is not a model-setting change or a token
savings measurement. Existing Governor and worker models are not silently changed.
Ask the model question after recurring consent. If Sol is not advertised, show
supported alternatives and let the user choose, or offer on-demand checks.
The Governor rotates after 336 cycles or 14 days through a verified handoff;
otherwise it pauses. Show its chat and how to ask for status or pause.

The five hooks are `SessionStart`, `SessionEnd`, `Stop` (main turn completed),
`SubagentStart`, and `SubagentStop`. They record protected identifiers, hashes,
safe labels, timestamps, and bounded counters locally. They do not inspect
transcripts, grant permissions, intercept prompts/tools, or start model turns.
They are optional evidence sources, not an independent scheduler.

## GitHub Edition Boundary

The current [submission documentation](https://developers.openai.com/plugins/deploy/submission)
excludes lifecycle hooks from uploaded plugin ZIPs. That page does not establish
that a Directory skill may automate a post-install GitHub hook installation.
Until that route is clarified, the Directory onboarding reports
`marketplace_hook_install_unverified`, offers core setup, and can link the
separate community-distributed GitHub edition. It does not automate the source
switch or treat opt-in as an exemption from platform/workspace policy.

An independent user-directed installation on a supported local host must
identify the exact repository, immutable release/tag, signed commit, ZIP hash,
hook definition, and source changes before installation consent. Verify assets,
signature bindings, and attestation first. Use a supported plugin-manager path
that preserves the verified identity, never a moving `main`/`latest` installer.
If that guarantee is unavailable, stop the optional branch. No marketplace cache
patch, hidden user-hook install, direct config edit, or download-and-run fallback.

Do not leave two Chronos identities enabled. Obtain authorization before
removing a working edition, preserve existing state, and stop on an unsafe source
switch. Show the exact installed version and source after the change. A
publisher signature proves source identity, not OpenAI approval or hook trust.

[Codex hook documentation](https://developers.openai.com/plugins/build/plugins)
requires explicit trust of the current hook definition. Onboarding must use the
host's real review controls, not write trust records or suggest a nonexistent
`/hooks` desktop command; the documented browser is CLI-only. Required full quit/reopen and fresh-chat steps remain visible.
Chronos does not close Codex automatically. If execution has not been observed
after trust, the receipt says so; no forced workers or routine wakes are created
to manufacture an event.

## Setup Receipt

Return a compact receipt from fresh observations, not the following illustrative
values. Keep it in the user's chat, not a telemetry file:

```text
Installation: <edition, verified version and source, or unresolved>
Work covered: <visible/selected scope and count; not account-wide>
Governor: <chat, approved model, recurrence active/paused/absent/unverified>
Native check: <actual result, or not run>
Scheduled checks: <observed execution, or not yet verified>
Hooks: <not included/off confirmed via host control/cannot confirm on this build>;
       trust=<review result>; execution=<fresh event observed/not observed>
Health evidence: <observed, partial and unsupported counts out of 8>
Diagnostics: automatic=<allowed/on request only>; briefing=<run/skipped/pending>
Data: bounded local state; Codex chat processing; no publisher runtime telemetry
Setup: <ready/restart needed/choice pending/blocked>
Next step: <only a real pending action, or none>
Check or pause: <Governor chat; ask for status or pause recurring checks>
```

One native cycle proves that cycle, not an unattended scheduled pulse. A
recurrence existing proves scheduling, not that the scheduler executed the
protocol. Without a current collector snapshot, Heartbeat status is prior-state
inspection; eight unsupported families mean eight not evaluated.

Waiting for a user decision does not create a timer. On resume, verify current
source/version and installation key, reuse explicit choices, and continue the
first unfinished step. Renew consent only for a material change such as a new
hook definition, edition, governed scope, or permission. Never claim that a
receipt is an enforceable native permission ledger: runtime/host approval
boundaries remain authoritative.

## Stop And Data Controls

For explicit full metadata removal, use the native `data-plan`/`data-remove`
protocol before uninstalling. Select the Codex home and repositories, verify
zero current-key recurrences and disabled hooks, obtain deletion consent, then
verify an empty plan. See [the complete procedure](INSTALLATION.md#full-local-metadata-removal).
No promise to erase chats, logs, caches, trust records or unknown old scopes.
The tested CLI hooks-off setting is global: it affects other plugins too and
requires separate consent, a full desktop restart and same-context verification.

Pausing the scoped Governor recurrence stops scheduled model turns. Disabling
hooks stops new hook events. These are separate controls. Use the plugin manager
to uninstall; do not delete caches by hand. Disabling or uninstalling does not
promise erasure of existing local metadata, Codex chat history, or GitHub activity.
An explicit local-state cleanup request requires stopping the relevant hooks
and recurrences and verifying the exact installation scope first. Never clear
another installation's state or a foreign-key Governor.

Full local retention, Inspector boundaries, DPAPI limitations, and provider
recipients are in [PRIVACY.md](../PRIVACY.md). Public support sharing is always
optional. Never post raw rollouts, SQLite files, state, credentials, paths,
identifiers, prompts, commands, or private source.

## Draft Validation

Validated on this Windows machine on 2026-10-01:

- Both modified skills pass the skill-creator frontmatter validator.
- Inbox Windows PowerShell 5.1 release tests pass, including two identical
  builds, the declared packaged onboarding entrypoint, and configured hook
  intake. The package retains 14 files and two skills.
- An isolated Codex 0.159.2 plugin-manager/app-server harness accepts the full
  draft manifest, discovers five hooks, and observes SessionEnd completion and
  its local inbox receipt. It runs zero model turns. SessionStart, Stop,
  production inventory, and scheduled execution are not evaluated by this run.
- An independent read-only policy review walks six consent/restart/coverage
  scenarios and finds no material contradiction. This is modeled behavior,
  not an end-to-end live onboarding test.

This validation does not prove marketplace acceptance, Directory-to-GitHub
installation permission, production onboarding after a restart, or autonomous
scheduled execution. No production plugin, hook trust, Governor recurrence,
marketplace listing, or release tag was changed by this draft's tests.
