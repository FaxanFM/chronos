# Chronos Onboarding And Consent

Status: v0.9.4 source draft. Not installed, submitted, or published. The
hook-enabled v0.9.3 candidate remains a separate artifact; this draft does not
change its signed commit, tag, ZIP, or installed package.

## One Entry Prompt

> Set up Chronos for my active chats: explain privacy, offer optional hooks,
> configure one Governor, and verify what is running.

The packaged `extensions.com.openai.onboardingSkill` points to the existing
`chronos` skill. No third skill, hidden installer, account signup, or new
background service is added. The Governor uses the same onboarding contract
when it takes over a user-authorized setup. It does not send consent reminders
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
| Run briefing | Bounded Windows and compatible Codex health diagnostics | Inspector once for the requested briefing; no broad validation suite or automatic diagnostic upload |
| Skip briefing | Core task checks without Inspector evidence | No new Inspector run; unavailable health coverage stays unsupported |

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
`/hooks` command. Required full quit/reopen and fresh-chat steps remain visible.
Chronos does not close Codex automatically. If execution has not been observed
after trust, the receipt says so; no forced workers or routine wakes are created
to manufacture an event.

## Setup Receipt

Return a compact receipt from fresh observations, not the following illustrative
values. Keep it in the user's chat, not a telemetry file:

```text
Edition/version/source: <verified installation or unresolved>
Scope: visible_or_specified; <working-set count>; account-wide=false
Recurring consent: <yes/no/pending>
Governor/recurrence: <verified owner and active/paused/absent/unverified>
Native cycle: <actual result or not_run>
Scheduled execution: <verified/not_verified; actual pulse evidence required>
Hooks: choice=<decision>; trust=<host observation>; execution=<fresh observation>
Heartbeats: observed=<n>; partial=<n>; unsupported=<n>; mode=<actual mode>
Diagnostic briefing: <chosen/skipped/pending>; evidence=<actual coverage>
Data: bounded local state; Codex chat processing; no publisher runtime telemetry
Setup: <core_ready/restart_required/awaiting_consent/blocked>
Next step: <only a real pending action, or none>
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
