# Chronos: Installation And Video Guide

Audience: people installing Chronos for the first time on a local Windows Codex host.
Purpose: a walkthrough for the video creator. This document does not perform an installation.

## Before Recording

Record after review is complete and Chronos v0.9.4 or newer is **published and available to install**. An approved submission is not necessarily published. Do not film an older listing as v0.9.4.

For the optional hooks segment, also require a published, verified full GitHub release. Record its version, immutable tag, signed commit, ZIP SHA-256, and verified release attestation. Do not use a preview package, a moving `main` branch, or an unverified download.

There is no standalone hook-patch installer in v0.9.4. The supported documented approach is an independently authorized switch to the full GitHub edition. Do not describe it as a patch that the Directory edition silently installs.

Have these three reference pages ready:

1. [Chronos in the Plugin Directory](https://chatgpt.com/plugins/plugins_6a79c882cf488191b8f62ee20e0e2571).
2. [Chronos on GitHub](https://github.com/FaxanFM/chronos). Show its README, Releases, and [MIT license](https://github.com/FaxanFM/chronos/blob/main/LICENSE).
3. [Official hook review and trust documentation](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks).

Also prepare the Codex app for the install and Governor scenes. Keep the publisher management portal, account details, private chat titles, local paths, and identifiers out of the recording. Use a small, non-sensitive demonstration workspace.

## Scene 1: What Chronos Does

**Show:** the Chronos listing and product name.

**Say:**

> Chronos helps you keep track of active work in Codex. Its Governor coordinates the chats you choose, Heartbeat checks evaluate the evidence available, and Inspector provides a bounded diagnostic briefing when you ask for one. It is free and open source. You stay in control of recurring checks, optional hooks, and the work it can govern.

**Keep the scope accurate:** Chronos works with active chats in a visible local window of up to 50, plus explicitly selected chats. It does not promise to monitor every chat in an account, run while Codex is closed, or connect to another machine.

## Scene 2: Install From Nothing

**Show:** the local Windows app, then its plugin discovery interface.

1. Install or update the Windows app with local Codex support using [OpenAI's official Windows instructions](https://learn.chatgpt.com/docs/windows/windows-app). Sign in yourself. Chronos does not require a separate publisher account or an API key for this workflow.
2. Open local Codex and a demonstration workspace. Native Chronos scripts currently target Windows with inbox Windows PowerShell 5.1; do not present this walkthrough as validated on macOS or Linux.
3. Open the app's Plugins interface and search for **Chronos**.
4. Select the Chronos listing. Confirm the displayed version is **v0.9.4 or newer** and matches the intended published release. If it does not, stop the recording rather than substitute an older version.
5. Install through the normal plugin manager. Review the permissions the host presents. Do not edit plugin caches or configuration files to bypass installation controls.
6. Fully quit and reopen Codex when required to load the new catalog. Start a fresh chat so the walkthrough does not reuse an older skill location.

**Say:**

> Install Chronos through the plugin manager, then check the version. The Directory edition includes the Chronos and Chronos Governor skills. Optional lifecycle hooks are supplied separately in the full GitHub edition.

**Important:** do not claim hooks were installed, trusted, or executed just because the Directory installation succeeded. OpenAI's [submission rules](https://developers.openai.com/plugins/deploy/submission) currently exclude lifecycle hooks from uploaded plugin ZIPs.

## Scene 3: One Prompt Starts Onboarding

**Show:** a fresh local Codex chat. Select the installed Chronos skill if needed, then enter:

> Set up Chronos for my active chats: explain privacy, configure one Governor, and verify scope and Heartbeat coverage.

**Say:**

> Start with this prompt. Chronos explains its scope and data use, then asks for the choices that matter. You do not need to assemble a set of scripts or register each worker by hand.

Onboarding should ask one decision at a time. Answer in ordinary language:

| Choice | Suggested recording answer | What it means |
| --- | --- | --- |
| Scope | Govern these demonstration chats only. | No account-wide monitoring or implied permission for unrelated chats. |
| Recurring or on-demand | Enable recurring governance for this scope. | Authorizes one Governor recurrence after its native checks pass; zero worker recurrences. |
| Governor model | Use GPT-6 Sol with Medium reasoning if this host supports it. | A preference that must be verified, not a silent model change. GPT-6 Luna with Medium reasoning is an explicit alternative. |
| Automatic diagnostics | Keep diagnostics on request only for this demonstration. | No autonomous Inspector runs, even when health is unknown. |
| Optional hooks | Directory edition: show its hooks-absence disclosure. Full edition: review installed definitions first. | Review does not authorize trust. The Directory edition does not ask to trust missing hooks. |
| Diagnostic briefing | Run one bounded diagnostic briefing for this demonstration. | Authorizes one Inspector run, not a broad test suite or diagnostic upload. Skip this if no briefing is wanted. |

For recurring mode, the same Governor recurrence uses a 60-minute active cadence and a 360-minute idle cadence. This uses the user's Codex allowance. Do not claim measured token savings or guaranteed unattended operation.
All choices stay in this setup chat before Governor handoff. A one-off briefing
does not authorize future diagnostics. The Governor rotates after 336 cycles
or 14 days through a verified handoff, or pauses if that cannot be verified.

If the host cannot safely complete setup, show the compact blocker and next action. Do not narrate a pending, partial, or blocked result as success.

## Scene 4: Explain Privacy

**Show:** the Governor's privacy explanation and [repository privacy policy](https://github.com/FaxanFM/chronos/blob/main/PRIVACY.md).

**Say:**

> Chronos runtime scripts do not send telemetry to Dravara, LLC. They keep bounded metadata locally. Compact summaries and routing information can enter your Codex chat, where OpenAI's data controls apply. GitHub receives normal download requests, and any information you choose to post publicly. Setup does not upload a support report.

Do not shorten this to "no data is collected." Local metadata exists, and hashed identifiers are pseudonymous, not anonymous. Windows protection of hook identifiers does not protect against all software running as the same user.

## Scene 5: Show GitHub And The License

**Show:** the public repository, the matching release, its verified identity, and the MIT license.

**Say:**

> The source is public on GitHub. Chronos uses the MIT license, so you can use, modify, and distribute it, including commercially, while retaining the required copyright and permission notice. It is provided without warranty. You do not need to star the repository or sign up with us to use it.

Free Chronos does not mean free Codex usage. Model turns remain subject to the user's OpenAI plan and allowance.

## Scene 6: Explain The Optional Hooks

**Show:** the five hook definitions in the verified full release, followed by the official trust documentation.

**Say:**

> Hooks add local lifecycle evidence. They tell Chronos when sessions and turns finish, and when subagents start or stop. They do not read transcripts, grant permissions, or create model turns. They are optional; core governance can work without them, with its evidence limits clearly shown.

| Hook | Event it records |
| --- | --- |
| `SessionStart` | A session starts. |
| `SessionEnd` | A session ends. |
| `Stop` | The main agent turn finishes. |
| `SubagentStart` | A subagent starts. |
| `SubagentStop` | A subagent stops. |

The handlers retain protected identifiers, hashes, safe labels, timestamps, and bounded counters locally. They are evidence sources, not a replacement scheduler. Do not promise that adding hooks fixes every host scheduling issue.

## Scene 7: Optional Full GitHub Installation

**Show:** the Governor chat explaining the source change. Begin with this review prompt:

> I want to review the optional Chronos GitHub hooks. Explain what each hook does, what data stays local, and how the full GitHub edition differs from my Directory installation. Do not install anything or grant trust yet.

The Directory edition may return `marketplace_hook_install_unverified`. That is an honest boundary, not permission to patch its managed cache. Its onboarding can explain the separate GitHub edition, but it does not automate the source switch.

For an independent user-directed installation, use a fresh local installation
chat with no Chronos skill loaded and enter:

> Help me switch to the full GitHub edition of Chronos from a published v0.9.4-or-newer release. First verify and show the exact version, immutable tag, signed commit, ZIP SHA-256, release attestation, and five hook definitions. Explain the source change and preserve my existing Chronos state. Do not make changes until I approve that exact installation. Use only the supported plugin manager; do not patch caches, edit trust records, or run an unverified installer.

Then follow this sequence:

1. Review the verified identity and changes. Give explicit approval for that exact installation, including removal of the old edition if required.
2. Pause the existing scoped Governor recurrence before changing its source. Do not delete state or create a second Governor.
3. Use the supported plugin-manager procedure in the [installation documentation](https://github.com/FaxanFM/chronos/blob/main/docs/INSTALLATION.md). Keep only one Chronos source enabled. If the manager cannot preserve the verified identity, stop the optional installation.
4. Fully quit and reopen Codex as required. Start a fresh chat and load the new catalog.
5. Ask Chronos to verify the installed version and source, preserve its installation state, and reconcile the existing Governor before resuming the authorized recurrence.

**Say:**

> This is a deliberate source change, not a hidden post-install patch. Review the release first, approve the change, and keep one Chronos installation enabled.

## Scene 8: Review And Trust Hooks Yourself

**Show:** a fresh Chronos Governor chat, then the host's actual hook review controls.

> Walk me through reviewing the five hook definitions from my verified Chronos installation. Explain their commands and data use. I will grant trust myself through the host's supported controls. Do not write trust records or treat installation as proof of execution.

The Governor guides the review; **the user grants trust**. Show the exact definitions and source presented by the current host. Do not invent a desktop `/hooks` command: that command belongs to the CLI documentation. If this host does not expose the needed review controls, report that limit and leave hooks untrusted.

Trust applies to the current definitions. A changed definition may require a new review. Observe a fresh, ordinary host event afterward; an "enabled" or "trusted" label alone is not proof that a handler ran. Do not create artificial worker turns or unrelated wakes to manufacture proof.

## Scene 9: Show What Is Actually Verified

**Show:** the Governor's compact setup receipt. Ask:

> Verify this installation and my approved Governor scope. Show the current edition, version, and source; Governor ownership; active recurrence count; worker recurrence count; hook trust and observed execution; and Heartbeat coverage. Clearly separate verified results from pending, unsupported, and not-yet-observed results.

Successful setup should show one scoped Governor recurrence and zero worker recurrences when recurring mode was authorized. On-demand mode should not create a new recurrence.

Task inventory proves liveness only. It does not prove quota, resource, review, rule, or other Heartbeat health. Without compatible current collector or authorized Inspector evidence, coverage remains partial or unsupported. Eight unsupported families means **eight families were not evaluated**, not "all healthy."

A completed native cycle proves that cycle. It does not prove a future scheduled pulse will run correctly. If no unattended pulse has been observed, show `Scheduled execution: not_verified` and leave that claim out of the commercial.

**Say:**

> The receipt shows what Chronos has verified and what still needs evidence. Unknown is not healthy, and a configured timer is not proof that a scheduled check ran.

## Scene 10: Stop Or Remove Chronos

For full local metadata removal, use this separate prompt before uninstalling:

> Remove this Chronos installation and its owned local metadata. Explain the scope, stop and verify its exact recurrence, and verify hooks are off. Ask separately before disabling hooks globally. Show the native removal plan, include only repositories I select, obtain deletion confirmation, apply that exact plan and verify it is empty. Then uninstall through the supported manager. Preserve other installations, chats, logs and caches.

The removal plan contains private filesystem paths; do not include it in public
video footage. Film the human receipt instead. The tested Windows CLI 0.160.0
control is `features disable hooks`, which affects all plugins in that Codex
home, not only Chronos. Fully quit/reopen the desktop app and verify the effective
state before claiming off. See [the build-qualified procedure](INSTALLATION.md#hooks-off-build-qualified-control).

**Show:** the Governor chat and supported plugin controls.

To stop recurring checks:

> Pause the Chronos Governor recurrence for this installation. Verify that no current-key Governor recurrence remains active. Preserve my state and do not change other installations.

To remove the plugin:

> Help me uninstall this Chronos installation through the supported plugin manager. First identify its scoped recurrence and hooks, explain what will remain, and obtain confirmation for the necessary changes. Do not delete caches or local state by hand.

Pausing the recurrence and disabling hooks are separate actions. Uninstalling does not promise erasure of local metadata, chat history, or GitHub activity. A local-state cleanup request needs its own scoped verification.

## Closing Line

> Start with Chronos from the Plugin Directory. Choose the work it governs, review the optional GitHub hooks, and check the evidence before trusting the result. Free to use, open source, and built to keep you in control.

## Video Creator's Final Checklist

- The Directory version shown is published v0.9.4 or newer, not merely approved or in review.
- The optional full GitHub release is published and its exact identity is verified.
- Store and GitHub editions are clearly distinguished; no standalone hook patch is promised.
- Every installation, source change, recurrence, diagnostic run, and trust decision reflects actual user consent.
- Screens show real results. No illustrative receipt is presented as live verification.
- No account-wide coverage, universal platform support, guaranteed scheduler behavior, or unmeasured efficiency claim is made.
- Private paths, identifiers, account information, and unrelated chats are redacted.
- GitHub, MIT licensing, local metadata, provider processing, and stop controls are explained.

Technical background: [Chronos onboarding](ONBOARDING.md), [installation](INSTALLATION.md), [privacy](../PRIVACY.md), [license](../LICENSE), and [OpenAI plugin packaging](https://developers.openai.com/plugins/build/plugins).
