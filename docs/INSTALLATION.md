# Install Chronos For Codex

## Readiness And Edition

Updated October 1, 2026. This guide covers the full Windows GitHub edition,
including both skills and all five optional lifecycle hooks.

The guided onboarding source is **v0.9.4 preview**, not a published production
release or marketplace-approved update. Its signed source commit is
[`77ff0666c451e7ca6b81d4a0e9a598e057106afd`](https://github.com/FaxanFM/chronos/commit/77ff0666c451e7ca6b81d4a0e9a598e057106afd).
GitHub verified that signature as valid. Its deterministic local ZIP SHA-256 is
`8dcb909cff11a4ffb69467d831121f9e5d106331e3b92db2cae1b1b2c1efb031`.
This preview has no published release attestation; a source install is not a
release-asset install. Use it only when you explicitly choose preview testing.

The preview's exact pinned GitHub install and uninstall commands have passed on
this Windows machine in an isolated account, with 14 normalized release files
matching the local build and five hook definitions. This does not prove a
complete live onboarding conversation or an unattended scheduled Governor.
The local v0.9.3 Governor bootstrap previously passed; scheduled execution is
still unverified. The v0.9.3 release workflow's first attempt lost communication
with its Windows 2022 runner and was retried without changing the candidate.
Do not describe either preview as a fully released, always-running product.

The [OpenAI Directory listing](https://chatgpt.com/plugins/plugins_6a79c882cf488191b8f62ee20e0e2571)
was last checked as v0.9.2. It does not contain this new onboarding draft. The
current [submission documentation](https://developers.openai.com/plugins/deploy/submission)
excludes lifecycle hooks from submitted ZIPs. A Directory-to-GitHub automatic
hook installation is not established as an approved route. This guide is a
separate, explicit user-directed GitHub installation, not a hidden Directory
upgrade. Do not install both source identities.

For an ordinary customer installation, wait for a verified published release
with its exact commit, ZIP/checksum, and attestation. Do not substitute moving
`main`, `latest`, or the draft branch for that identity.

## Requirements

- Windows with inbox Windows PowerShell 5.1. Other operating systems are not
  validated for these Windows diagnostics, protected state, and hook scripts.
- Codex desktop with a supported local plugin manager and authoritative
  current-host chat statuses. The installation commands were tested with the
  desktop's Codex CLI 0.159.2; that is a tested build, not a universal minimum.
- Permission under your workspace's plugin and hook policy. A prompt does not
  override an administrator's restrictions.
- GitHub access for installation. No publisher account, API key, signup, star,
  or diagnostic upload is required.

Use the same Windows account and existing `CODEX_HOME` as Codex. Do not change
homes, install another runtime, copy credentials, or use another machine to
make setup pass. The Governor manages active work on this local host.

## Recommended Optional Hooks

We recommend reviewing the five hooks for fresher lifecycle evidence on a
supported host. They are **optional**, not a requirement for core governance:

| Hook | Evidence added |
| --- | --- |
| `SessionStart` | A session started or resumed |
| `SessionEnd` | A session ended |
| `Stop` | A main-task turn completed; bounded activity counters |
| `SubagentStart` | A subagent started |
| `SubagentStop` | A subagent stopped |

These short native commands retain protected identifiers, hashes, safe labels,
timestamps, and bounded counters locally. They do not read transcripts, intercept
prompts/tools/approvals, start model turns, or create worker recurrences. They
cannot make missing Heartbeat evidence healthy or widen the governed working set.
Installing the full edition makes the definitions available; it does not grant
trust or prove dispatch. You can decline them and continue supported core setup.

## Prompt-Led Installation

If a Chronos Governor chat already exists, send the following there. If Chronos
has been uninstalled, it has no newly loaded plugin skill; use a fresh local
Codex chat to do the initial plugin-manager install. After restart, start the
onboarding prompt below and let it reuse or create one verified Governor.
An old Governor chat name alone does not prove ownership or current guidance.

For this **preview walkthrough**, use:

```text
Help me install the full Chronos v0.9.4 GitHub preview on this Windows Codex
host, including the optional but recommended lifecycle hook definitions.
Use FaxanFM/chronos at exact signed commit
77ff0666c451e7ca6b81d4a0e9a598e057106afd, not main or latest.

Explain the preview status, what core governance and the five hooks do, local
storage, OpenAI chat processing, GitHub download requests, and that Chronos
sends no publisher runtime telemetry. Verify GitHub's valid commit signature
and the pinned source identity before installing. This is an explicit preview
source install, not a published or attested release. Ask me to confirm this
preview and any exact existing-source removal before those changes.

Use the supported plugin manager. Keep only one enabled Chronos source,
preserve local state, and leave unrelated plugins and recurrences untouched.
Do not patch caches or config, download-and-run an installer, auto-trust hooks,
or create a recovery/onboarding timer. Explain any actual blocker.

After installation, verify version 0.9.4, both skills, and five hook definitions.
Guide me through full quit/reopen and a fresh chat, then continue onboarding.
Ask separately about recurring model usage, hook review/trust, and a diagnostic
briefing. Require actual native and scheduled evidence before claiming success.
```

The prompt initiates the work; it does not auto-submit consent. The Governor
cannot click its own hook trust approval. It may pause for a real user decision
or restart, but it must not ask you to relay routine technical commands between
chats or start a recurrence merely to finish installation.

For a published release, replace the preview identity with that release's
verified immutable identity and require checksum and attestation verification.
Do not use this preview prompt as a production-release claim.

## Manual Preview Install

Use these steps only after choosing the separate GitHub preview above. Codex can
execute the commands for you through its supported local shell tools. Do not run
them from a Directory skill as a covert post-review upgrade.

1. Inspect the signed commit linked above and confirm you are choosing v0.9.4
   preview. Check Codex's installed plugins and marketplaces. Pause the exact
   verified Chronos Governor recurrence before replacing an installed edition;
   do not touch foreign or unverified keys. Obtain authorization to remove the
   exact conflicting Chronos source. Do not remove unrelated marketplaces.
2. Resolve the desktop's actual CLI executable once. `codex` may already be on
   PATH; if not, ask Codex to locate its desktop CLI. Do not assume a copied
   versioned path from someone else's machine. Commands below use `$codex`:

   ```powershell
   $codex = (Get-Command codex -ErrorAction Stop).Source
   & $codex --version
   if ($LASTEXITCODE -ne 0) { throw 'Codex CLI check failed.' }
   & $codex plugin marketplace add --help
   if ($LASTEXITCODE -ne 0) { throw 'This CLI does not expose the required plugin manager.' }
   & $codex plugin list --json
   & $codex plugin marketplace list --json
   ```

3. If an old Git Chronos install and its Chronos-only catalog need removal,
   and you have approved that exact change, use the manager:

   ```powershell
   & $codex plugin remove chronos@chronos --json
   if ($LASTEXITCODE -ne 0) { throw 'Chronos removal failed; stop before switching sources.' }
   & $codex plugin marketplace remove chronos --json
   if ($LASTEXITCODE -ne 0) { throw 'Chronos catalog removal failed.' }
   ```

   If the conflict is a Directory install, remove it using its supported plugin
   controls instead. `chronos@openai-curated-remote` and `chronos@chronos` are
   different identities. Do not delete caches or assume uninstalling one removes
   the other. A retained catalog can otherwise make a same-name add fail.
4. Add the exact GitHub source and install the full plugin:

   ```powershell
   $commit = '77ff0666c451e7ca6b81d4a0e9a598e057106afd'
   & $codex plugin marketplace add FaxanFM/chronos --ref $commit --json
   if ($LASTEXITCODE -ne 0) { throw 'Pinned Chronos source installation failed.' }
   & $codex plugin add chronos@chronos --json
   if ($LASTEXITCODE -ne 0) { throw 'Chronos plugin installation failed.' }
   ```

   Stop on any failed command. Do not retry against `main` or silently install
   a different version. The catalog in this repository includes both skills and
   the five hook definitions, so there is no separate script-copy step.
5. Verify the configured catalog checkout and enabled identity:

   ```powershell
   $catalogs = & $codex plugin marketplace list --json | ConvertFrom-Json
   if ($LASTEXITCODE -ne 0) { throw 'Could not verify marketplace state.' }
   $catalog = @($catalogs.marketplaces | Where-Object { $_.name -eq 'chronos' })
   if ($catalog.Count -ne 1) { throw 'Expected one Chronos source.' }
   $actual = (& git -C $catalog[0].root rev-parse HEAD | Out-String).Trim()
   if ($actual -ne $commit) { throw 'Chronos source does not match the approved commit.' }
   $plugins = & $codex plugin list --json | ConvertFrom-Json
   if ($LASTEXITCODE -ne 0) { throw 'Could not verify installed plugin state.' }
   $chronos = @($plugins.installed | Where-Object { $_.name -eq 'chronos' })
   if ($chronos.Count -ne 1 -or $chronos[0].version -ne '0.9.4' -or -not $chronos[0].enabled) {
     throw 'Expected only Chronos v0.9.4 enabled.'
   }
   $chronos | Select-Object pluginId,version,enabled
   ```

   Verify the installed manifest, both skill folders, and exactly five hook
   definitions as well. The tested cache layout is
   `<CODEX_HOME>\plugins\cache\chronos\chronos\0.9.4`; use the manager's actual
   root if your build differs. A source-only `.gitignore` is not a release file.
6. Fully quit and reopen Codex. Then open a fresh chat. Loaded conversations can
   retain old versioned skill locators; a plugin-manager success does not hot-swap
   them. Do not manually copy missing scripts into an old cache location.

## Start Guided Onboarding

In a fresh chat with the installed v0.9.4 skills, send:

> Set up Chronos for my active chats: explain privacy, offer optional hooks,
> configure one Governor, and verify what is running.

The setup explains the visible-or-specified scope and asks:

1. **Recurring Governor or on-demand only?** Recurring governance uses at most
   one Governor model turn per active hour or six idle hours. It uses your Codex
   allowance. No worker gets a recurrence. The Governor has a 336-cycle or
   14-day rotation bound. On-demand checks do not monitor between requests.
2. **Review optional GitHub hooks, keep them off, or decide later?** On the
   already installed full edition, review the current definition, not another
   install. Trust only through Codex's real hook review controls. Desktop UI can
   differ by build; do not assume a `/hooks` desktop command. The official
   [hook guide](https://learn.chatgpt.com/docs/hooks) describes exact-definition
   trust and the CLI hook browser. If controls are unavailable, report that
   limitation; never edit trust records to bypass it.
3. **Run a diagnostic briefing or skip it?** Inspector checks bounded Windows
   resource and compatible Codex evidence. It does not edit database rows or
   rules; SQLite can update coordination sidecars with a read-only handle.

The selected Governor can lead remaining questions after a named handoff. The
user does not manually register worker chats or run broad release tests. A
declined optional feature must not prevent otherwise supported core governance.
If hooks were already trusted, an off choice needs verified disablement; do not
claim they are off merely because you declined an installation question.

## Verify The Result

Expect a compact receipt with source/version, scope count, recurring consent,
native cycle result, one verified Governor and its exact recurrence state,
zero worker recurrences, hook choice/trust/execution separately, and Heartbeat
observed/partial/unsupported counts. The scope is up to 50 visible local chats
plus explicit selections, not all chats in an account.

For a bounded status check, resolve the installed core skill root and use:

```powershell
$chronos = Join-Path '<installed chronos skill root>' 'scripts\chronos.cmd'
& $chronos -Action install-status
& $chronos -Action supervise -SupervisionAction status
& $chronos -Action heartbeat
```

The placeholder must be replaced with the manager-verified installed skill
root, not a guessed path. Chronos is not guaranteed to be on PATH. Supervision
must use Codex's Windows user when DPAPI-protected hook evidence is read; use
only scoped host-account approval if needed, never a blanket sandbox bypass.

Fresh hook counters prove observed events, not all five handlers. Do not create
subagents or routine wakes to manufacture a demonstration. A scheduled recurrence
proves scheduling, not execution: unattended operation requires an actual
scheduled pulse to run the native protocol. Until then the receipt says
`scheduled_execution=not_verified`. Eight unsupported Heartbeat families mean
eight were not evaluated; task liveness and trusted hooks are not a clean health
report. See [the complete onboarding contract](ONBOARDING.md).

## Uninstall Or Pause

Prompt the verified Governor before removing its plugin:

```text
Stop my Chronos monitoring and uninstall the identified Chronos plugin through
the supported manager. Verify the exact installation key and pause its
recurrence first. Leave unrelated or foreign-key automations untouched. Keep
my local Chronos metadata and chat history. Confirm that no Chronos plugin
identity remains installed, and explain the required full quit/reopen.
```

For the Git edition, after verifying the recurrence is stopped, the manager
commands are:

```powershell
& $codex plugin remove chronos@chronos --json
& $codex plugin marketplace remove chronos --json
```

Remove the Chronos-only catalog only if it is no longer needed. Directory
installs use their supported remove controls. Verify plugin-manager state,
then fully quit/reopen. Previously loaded chats may still show stale skill
references until that restart. Do not delete other plugin caches.

Pausing the Governor stops scheduled turns, not hooks. Disabling hooks stops
new hook events, not an existing recurrence. Uninstalling does not promise
erasure of local metadata, OpenAI chat history, or GitHub activity. Data cleanup
is a separate explicit request after scope and stopped-state checks.

## Data And Recording A Walkthrough

Chronos runtime scripts send no publisher telemetry. They retain bounded local
metadata and protected identifiers. Compact results and routing handles can
enter OpenAI chat context; downloads and voluntary public issues reach GitHub.
DPAPI is not protection against other software running as the same Windows
user. No public support upload is required. See [PRIVACY.md](../PRIVACY.md).

For an installation video, show the preview label, exact signed identity,
privacy explanation, installation receipt, restart, separate choices, hook
review, and honest final status. Hide private chat titles, paths, identifiers,
credentials, and diagnostic source records. Do not advertise the preview as
marketplace-approved, always-on, or fully healthy without the corresponding
evidence. The first filmed live onboarding remains an acceptance test, not an
already completed validation claim.
