param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $repoRoot "scripts\build-release.ps1"
$manifestPath = Join-Path $repoRoot "plugins\chronos\.codex-plugin\plugin.json"
$releaseWorkflowPath = Join-Path $repoRoot ".github\workflows\release.yml"
$testWorkflowPath = Join-Path $repoRoot ".github\workflows\test.yml"
$readmePath = Join-Path $repoRoot "README.md"
$pluginReadmePath = Join-Path $repoRoot "plugins\chronos\README.md"
$coreSkillPath = Join-Path $repoRoot "plugins\chronos\skills\chronos\SKILL.md"
$operationsPath = Join-Path $repoRoot "docs\OPERATIONS.md"
$supervisionPath = Join-Path $repoRoot "docs\SUPERVISION.md"
$heartbeatPath = Join-Path $repoRoot "docs\HEARTBEATS.md"
$supportPath = Join-Path $repoRoot "SUPPORT.md"
$fieldReportsPath = Join-Path $repoRoot "docs\FIELD-REPORTS.md"
$submissionPacketPath = Join-Path $repoRoot "docs\PLUGIN-DIRECTORY-SUBMISSION.md"
$sanitizedResultPath = Join-Path $repoRoot ".github\ISSUE_TEMPLATE\sanitized-result.yml"
$version = [string](Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json).version
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$marketplace = Get-Content -Raw -LiteralPath (Join-Path $repoRoot ".agents\plugins\marketplace.json") | ConvertFrom-Json
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-release-tests-" + [guid]::NewGuid())
$supervisionTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Chronos\Supervision\release-tests-" + [guid]::NewGuid())
$first = Join-Path $testRoot "first"
$second = Join-Path $testRoot "second"
$windowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$heartbeatDefaultTestRoot = $null
$supervisionDefaultTestRoots = @()

function Get-TextHash {
  param([string]$Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

try {
  if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw "Release validation must run under inbox Windows PowerShell 5.1."
  }
  if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw "Inbox Windows PowerShell 5.1 was not found at its system path."
  }
  if ([string]$manifest.interface.displayName -ne 'Chronos for Codex' -or
      [string]$manifest.interface.displayName.Length -gt 30) {
    throw "Directory display name must be specific and at most 30 characters."
  }
  if ([string]$manifest.interface.shortDescription.Length -gt 30) {
    throw "Directory short description must be at most 30 characters."
  }
  $defaultPrompts = @($manifest.interface.defaultPrompt)
  if ($defaultPrompts.Count -ne 3) {
    throw "Directory defaultPrompt must contain exactly three distinct product actions."
  }
  if ($defaultPrompts.Count -ne @($defaultPrompts | Where-Object { $_ -is [string] -and $_.Trim() }).Count) {
    throw "Directory defaultPrompt entries must be non-empty strings."
  }
  if (@($defaultPrompts | Select-Object -Unique).Count -ne 3) {
    throw "Directory defaultPrompt entries must be unique."
  }
  foreach ($prompt in $defaultPrompts) {
    if ($prompt.Length -gt 128 -or $prompt.Contains("`r") -or $prompt.Contains("`n")) {
      throw "Directory defaultPrompt entries must be single-line and at most 128 characters: $prompt"
    }
  }
  $promptRequirements = @(
    @{ Index = 0; Terms = @('set up chronos', 'verify source', 'one governor', 'explain hooks', 'heartbeat coverage', 'zero worker recurrences') },
    @{ Index = 1; Terms = @('chronos health briefing', 'inspect pc', 'quota', 'reviews', 'rules', 'sqlite', 'heartbeat coverage', 'evidence', 'unknowns') },
    @{ Index = 2; Terms = @('chronos governor', 'repo review', 'bounded read tasks', 'verify each result', 'edits', 'decisions') }
  )
  foreach ($promptRequirement in $promptRequirements) {
    $promptIndex = [int]$promptRequirement.Index
    $normalizedPrompt = ([string]$defaultPrompts[$promptIndex]).ToLowerInvariant()
    foreach ($required in @($promptRequirement.Terms)) {
      if (-not $normalizedPrompt.Contains($required)) {
        throw "Directory prompt $($promptIndex + 1) is missing its product action: $required"
      }
    }
  }
  $listingCopy = (([string]$manifest.description) + ' ' +
    ([string]$manifest.interface.shortDescription) + ' ' +
    ([string]$manifest.interface.longDescription)).ToLowerInvariant()
  foreach ($required in @('one local codex governor', 'heartbeats', 'windows', 'read-only', 'no publisher telemetry')) {
    if (-not $listingCopy.Contains($required)) {
      throw "Directory listing copy is missing a core product value or boundary: $required"
    }
  }
  if ($manifest.interface.PSObject.Properties['screenshots']) {
    throw "Skills-only packages must not declare interface screenshots."
  }
  $upgradeBoundary = @(
    Get-Content -Raw -LiteralPath $readmePath
    Get-Content -Raw -LiteralPath $operationsPath
    Get-Content -Raw -LiteralPath $supportPath
  ) -join "`n"
  foreach ($required in @('fresh task', 'fully quit and reopen Codex', 'versioned plugin skill locator', 'Do not copy', 'stale task catalog state')) {
    if (-not $upgradeBoundary.Contains($required)) {
      throw "Public upgrade guidance is missing the stale task-locator boundary: $required"
    }
  }
  $supervisionContract = (Get-Content -Raw -LiteralPath $supervisionPath) -replace '\s+', ' '
  foreach ($required in @(
    'exactly one active',
    'chronos-supervision-v1',
    'at most three attempts',
    'cycles zero and one',
    'zero active duplicates',
    '60 minutes while monitored work is active and 360 minutes while idle',
    '336 cycles or 14 days',
    '-SupervisionConfirmRecurrenceStopped',
    '%TEMP%\Chronos-Supervision-v3-<scope-prefix>-<slot>\session-registry.json',
    'four bounded direct TEMP child slots',
    'deterministic host-and-Codex-home hash',
    'recurrenceEligible=true',
    'one compact complete current-host active-list call',
    'callerVisibility=excluded_by_host',
    'hostInventoryRawObserved',
    'gpt-5.6-terra',
    'configuration',
    'hookExecutionObservation=observed',
    'optional accelerator',
    'hookRequiredForAutonomy=false',
    'complete current-host active inventory',
    'before initialization',
    'pre-existing active recurrence',
    'prove zero active current-key recurrences',
    'Do not schedule a recovery recurrence',
    'fully quit and reopen Codex',
    'quote-free',
    'cmd.exe',
    'routine user action',
    'DPAPI does not protect against another process already running as that'
    'CODEX_HOME'
    'Separate homes remain isolated'
    'ancestor junction'
    'Unscoped v2, fixed-TEMP, and LocalAppData state predates'
    'recovered_v3_anchor'
  )) {
    if (-not $supervisionContract.Contains($required)) {
      throw "Public supervision contract is missing a release boundary: $required"
    }
  }
  $governorSkill = (Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'plugins\chronos\skills\chronos-governor\SKILL.md')) -replace '\s+', ' '
  foreach ($transportPreflightTerm in @(
    'Before calling Governor `status` or `plan`',
    'fork_turns="none"',
    'do not reserve a plan',
    'Do not create and cancel a plan merely to discover transport incompatibility'
  )) {
    if (-not $governorSkill.Contains($transportPreflightTerm)) {
      throw "Governor skill is missing the pre-plan V2 fallback boundary: $transportPreflightTerm"
    }
  }
  foreach ($collectorContractTerm in @(
    'Every Governor pulse starts by calling `-HeartbeatInterventionAction list`',
    'The host inventory proves discovery and liveness only',
    'Before creating the separate bounded Heartbeat collector file',
    '-HeartbeatCollectorAction reserve',
    'persists across Governor task or sandbox restarts',
    'each of the eight public families',
    'A plain `& $chronos -Action heartbeat` call reads prior state only',
    '`-HeartbeatInspectorAuthorized`',
    'task liveness cannot supply it'
  )) {
    if (-not $governorSkill.Contains($collectorContractTerm)) {
      throw "Governor skill is missing the collector evidence boundary: $collectorContractTerm"
    }
  }
  foreach ($hardGateTerm in @(
    '**Hard gate:**',
    'Do not create or enable any Governor recurrence until native initialization succeeds',
    'Any other result requires zero active current-key recurrences',
    'Never use a recurrence to retry, recover, or finish a failed setup'
  )) {
    $hardGateOffset = $governorSkill.IndexOf($hardGateTerm, [StringComparison]::Ordinal)
    $stepOneOffset = $governorSkill.IndexOf('1. Run `& $chronos -Action install-status`', [StringComparison]::Ordinal)
    if ($hardGateOffset -lt 0 -or $stepOneOffset -lt 0 -or $hardGateOffset -gt $stepOneOffset) {
      throw "Governor skill does not put the fail-closed recurrence gate before setup actions: $hardGateTerm"
    }
  }
  $orderedSetupTerms = @(
    'Collect one all-same-name observation set',
    'Derive a separate current-key mutation set',
    'Never mutate a same-name automation carrying a different key or an unverified key',
    'Only the first deterministic setup contender may proceed to recurrence mutation or initialization',
    'Before initializing the selected task',
    'Immediately before the first mutation',
    'repeat the all-same-name observation, current-key filtering',
    'repeat the deterministic setup-contender election',
    'prove that zero current-key recurrences are active',
    'Have only the elected selected task run `-SupervisionAction initialize`',
    'require the successful initialization payload',
    'recurrenceEligible=true',
    'Update the deterministic winner in place',
    'If any create, update, duplicate cleanup, or exact postcondition verification fails',
    'prove zero current-key recurrences are active'
  )
  $setupOffset = 0
  foreach ($term in $orderedSetupTerms) {
    $nextOffset = $governorSkill.IndexOf($term, $setupOffset, [StringComparison]::Ordinal)
    if ($nextOffset -lt 0) {
      throw "Governor setup contract is missing or misorders the recurrence fence: $term"
    }
    $setupOffset = $nextOffset + $term.Length
  }
  $preElectionLoserTerms = @(
    'the selected task is no longer first',
    'skip `-SupervisionAction initialize` entirely',
    'enter the loser-verification branch below'
  )
  $loserOffset = 0
  foreach ($term in $preElectionLoserTerms) {
    $nextOffset = $governorSkill.IndexOf($term, $loserOffset, [StringComparison]::Ordinal)
    if ($nextOffset -lt 0) {
      throw "Governor election-loser path is missing, fallthrough, or misordered: $term"
    }
    $loserOffset = $nextOffset + $term.Length
  }
  $conflictLoserTerms = @(
    'Have only the elected selected task run `-SupervisionAction initialize`',
    'error=supervision_governor_conflict',
    'do not execute the generic initialization-failure cleanup in step 7',
    'Enter the same loser-verification branch below',
    'Never fall through from this branch to step 7',
    'Except for the two non-fallthrough loser-verification entries above'
  )
  $conflictOffset = 0
  foreach ($term in $conflictLoserTerms) {
    $nextOffset = $governorSkill.IndexOf($term, $conflictOffset, [StringComparison]::Ordinal)
    if ($nextOffset -lt 0) {
      throw "Governor conflict-loser path is missing, fallthrough, or misordered: $term"
    }
    $conflictOffset = $nextOffset + $term.Length
  }
  $failureRows = @(
    'initialization failure',
    'supervision status unreadable',
    'Heartbeat status unreadable',
    'incomplete active inventory',
    'inventory missing Governor',
    'inventory contains Governor more than once',
    'post-eligibility recurrence reconciliation failure'
  )
  foreach ($failureRow in $failureRows) {
    $expectedRow = "| $failureRow | 0 | 0 | no |"
    if (-not $supervisionContract.Contains($expectedRow)) {
      throw "Supervision failure matrix does not fail closed for: $failureRow"
    }
  }
  if (-not $supervisionContract.Contains('| complete active inventory and `recurrenceEligible=true` | 1 | 0 | no |')) {
    throw 'Supervision success matrix does not activate exactly one Governor recurrence after eligibility.'
  }
  foreach ($required in @(
    'This branch has exactly two entries',
    'error=supervision_governor_conflict',
    'mutates no recurrence belonging to the verified winner',
    'exactly one current-key Governor recurrence'
  )) {
    if (-not $governorSkill.Contains($required)) {
      throw "Governor skill is missing the concurrent-installer safety contract: $required"
    }
  }
  foreach ($expectedRow in @(
    '| pre-initialization fence with one foreign-key recurrence | 0 | 1 | 0 | no |',
    '| two concurrent fresh installers after convergence | 1 | 0 | 0 | no |'
  )) {
    if (-not $supervisionContract.Contains($expectedRow)) {
      throw "Supervision isolation/concurrency matrix is missing: $expectedRow"
    }
  }
  $coreSkill = Get-Content -Raw -LiteralPath $coreSkillPath
  foreach ($required in @(
    '## Complete status request',
    'Inspector, supervision',
    'Heartbeat status',
    'status-only request must not create a',
    'configuration evidence, not proof that the command'
  )) {
    if (-not $coreSkill.Contains($required)) {
      throw "Core Chronos skill is missing the full-status or hook-observation contract: $required"
    }
  }
  $heartbeatContract = (Get-Content -Raw -LiteralPath $heartbeatPath) -replace '\s+', ' '
  foreach ($required in @(
    'one active intervention per target',
    'A send with an unknown outcome does not retry',
    'A task report is not proof of recovery',
    'same subject and observation window',
    'GovernorLocalAction',
    'acknowledges the event only after one active recurrence with that cadence is verified',
    'Chronos does not infer price, quota impact, or efficiency from a model name',
    'The initial attempt plus one retry is the hard limit'
    'CODEX_HOME'
    'fail closed'
  )) {
    if (-not $heartbeatContract.Contains($required)) {
      throw "Public Heartbeat contract is missing an autonomy boundary: $required"
    }
  }
  $heartbeatSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'plugins\chronos\skills\chronos\scripts\heartbeat.ps1')
  $supervisionSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'plugins\chronos\skills\chronos\scripts\session-registry.ps1')
  $wrapperSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'plugins\chronos\skills\chronos\scripts\chronos.ps1')
  foreach ($required in @('$env:CODEX_HOME', 'heartbeat_codex_home_invalid', 'heartbeat_codex_home_unavailable', 'codexHomeIdentity', 'AllowUnscopedLegacyMigration', 'Test-NoReparseAncestors $full')) {
    if (-not $heartbeatSource.Contains($required)) { throw "Heartbeat CODEX_HOME contract is missing: $required" }
  }
  foreach ($required in @('$env:CODEX_HOME', 'supervision_codex_home_invalid', 'supervision_codex_home_unavailable', 'registryMutexIdentity', 'AllowUnscopedLegacyMigration', 'Test-NoReparseAncestors $full')) {
    if (-not $supervisionSource.Contains($required)) { throw "Supervision CODEX_HOME contract is missing: $required" }
  }
  if (($wrapperSource -split "`n" | Where-Object { $_ -match "ContainsKey\('CodexHome'\)" }).Count -lt 2) {
    throw 'The public wrapper does not forward explicitly bound CODEX_HOME to both native modules.'
  }
  $publicReadmes = @(
    Get-Content -Raw -LiteralPath $readmePath
    Get-Content -Raw -LiteralPath $pluginReadmePath
  ) -join "`n"
  $publicReadmes = $publicReadmes -replace '\s+', ' '
  foreach ($required in @(
    'Set up Chronos: verify source, create one Governor, explain hooks, and prove Heartbeat coverage and zero worker recurrences.',
    'Run a Chronos health briefing: inspect PC, quota, reviews, rules, SQLite, Heartbeat coverage; separate evidence from unknowns.',
    'Use Chronos Governor to split this repo review into bounded read tasks, verify each result, and keep edits and decisions here.',
    'one dedicated Governor',
    'zero worker recurrences',
    'including one that existed before the attempt',
    'does not ask the user to relay routine remediation'
  )) {
    if (-not $publicReadmes.Contains($required)) {
      throw "Public first-use guidance is missing an end-to-end setup requirement: $required"
    }
  }
  foreach ($forbidden in @('self-service agents', 'paid for directly', 'Public runner links', 'managed engagement')) {
    if ($publicReadmes.Contains($forbidden)) {
      throw "Public plugin documentation contains a prohibited service promotion: $forbidden"
    }
  }
  $fieldReports = Get-Content -Raw -LiteralPath $fieldReportsPath
  foreach ($forbidden in @('DESKTOP-', 'C:\Users\', 'source_thread_id', 'session_id')) {
    if ($fieldReports.Contains($forbidden)) {
      throw "Sanitized field-report ledger contains an identifying marker: $forbidden"
    }
  }
  $sanitizedResult = Get-Content -Raw -LiteralPath $sanitizedResultPath
  if (-not $sanitizedResult.Contains("placeholder: $version")) {
    throw "Sanitized-result issue form is out of sync with plugin version $version."
  }
  foreach ($excluded in @('apps', 'mcpServers')) {
    if ($manifest.PSObject.Properties[$excluded]) {
      throw "Skills-only packages must not declare $excluded."
    }
  }
  $marketplacePlugin = @($marketplace.plugins | Where-Object { $_.name -eq $manifest.name })
  if ($marketplacePlugin.Count -ne 1 -or
      [string]$marketplacePlugin[0].category -ne [string]$manifest.interface.category -or
      [string]$marketplace.interface.displayName -ne [string]$manifest.interface.displayName) {
    throw "Marketplace discovery metadata must match the plugin manifest."
  }
  $releaseWorkflow = Get-Content -Raw -LiteralPath $releaseWorkflowPath
  $testWorkflow = Get-Content -Raw -LiteralPath $testWorkflowPath
  foreach ($required in @(
    'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09',
    'os: [windows-2022, windows-latest]',
    'timeout-minutes: 25',
    'Parse PowerShell sources',
    'Parse JSON manifests',
    'Test packaged Chronos Heartbeats',
    'Expand-Archive',
    '-PluginRoot $package',
    'Test Chronos Supervision'
  )) {
    if (-not $testWorkflow.Contains($required)) {
      throw "Ordinary CI is missing release-quality validation: $required"
    }
  }
  foreach ($required in @(
    'Require verified commit and annotated tag',
    'tagObject.verification.verified',
    'commit.commit.verification.verified',
    'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09',
    'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6',
    'Test packaged Chronos Heartbeats',
    'Expand-Archive',
    '-PluginRoot $package',
    'Test Chronos Supervision',
    'timeout-minutes:',
    'subject-path: dist/*',
    'gh attestation verify $Path --repo $env:GITHUB_REPOSITORY',
    '--draft',
    'gh release edit $env:GITHUB_REF_NAME --draft=false',
    'function Invoke-ReleaseVerification',
    'for ($attempt = 1; $attempt -le 12; $attempt++)',
    'Start-Sleep -Seconds 5',
    'gh release verify $env:GITHUB_REF_NAME',
    'gh release verify-asset $env:GITHUB_REF_NAME',
    'gh release download $env:GITHUB_REF_NAME',
    'Published asset bytes differ from the verified build',
    "'chronos@openai-curated-remote'"
  )) {
    if (-not $releaseWorkflow.Contains($required)) {
      throw "Release workflow is missing supply-chain control: $required"
    }
  }
  $draftIndex = $releaseWorkflow.IndexOf('gh release create')
  $publishIndex = $releaseWorkflow.IndexOf('gh release edit $env:GITHUB_REF_NAME --draft=false')
  $preVerifyIndex = $releaseWorkflow.IndexOf('gh attestation verify $Path --repo $env:GITHUB_REPOSITORY')
  $verifyIndex = $releaseWorkflow.IndexOf('gh release verify $env:GITHUB_REF_NAME')
  if ($preVerifyIndex -lt 0 -or $draftIndex -le $preVerifyIndex -or $publishIndex -le $draftIndex -or $verifyIndex -le $publishIndex) {
    throw "Release workflow must verify the attestation, create a draft, publish it, and then verify the immutable release in that order."
  }

  $firstOutput = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $builder -Version $version -OutputDirectory $first 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "First release build failed.`n$($firstOutput -join "`n")" }
  $secondOutput = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $builder -Version $version -OutputDirectory $second 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "Second release build failed.`n$($secondOutput -join "`n")" }

  $artifactName = "chronos-v$version.zip"
  $firstArtifact = Join-Path $first $artifactName
  $secondArtifact = Join-Path $second $artifactName
  $firstHash = (Get-FileHash -LiteralPath $firstArtifact -Algorithm SHA256).Hash
  $secondHash = (Get-FileHash -LiteralPath $secondArtifact -Algorithm SHA256).Hash
  if ($firstHash -ne $secondHash) { throw "Two clean release builds produced different SHA-256 hashes." }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($firstArtifact)
  try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    $sortedNames = @($names | Sort-Object)
    if (($names -join "`n") -ne ($sortedNames -join "`n")) { throw "Release entries are not deterministically ordered." }
    foreach ($entry in $archive.Entries) {
      if ($entry.LastWriteTime.DateTime -ne [DateTime]::new(1980, 1, 1, 0, 0, 0, [DateTimeKind]::Unspecified)) {
        throw "Release entry has a non-reproducible timestamp: $($entry.FullName)"
      }
      if ($entry.Name -eq 'LICENSE' -or [System.IO.Path]::GetExtension($entry.Name).ToLowerInvariant() -in @('.json', '.md', '.ps1', '.cmd', '.yaml', '.yml', '.txt')) {
        $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8)
        try { $entryText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($entryText.Contains("`r")) { throw "Packaged text is not normalized to LF: $($entry.FullName)" }
      }
    }
    foreach ($required in @('.codex-plugin/plugin.json', 'hooks/hooks.json', 'skills/chronos/SKILL.md', 'skills/chronos/scripts/chronos.cmd', 'skills/chronos/scripts/heartbeat.ps1', 'skills/chronos/scripts/hook-intake.ps1', 'skills/chronos/scripts/session-registry.ps1', 'skills/chronos-governor/SKILL.md')) {
      if ($names -notcontains $required) { throw "Release is missing $required." }
    }
    if ($names -contains '.gitignore' -or $names -match '^docs/' -or $names -match '^tests/') {
      throw "Release contains repository-only files."
    }
    if ($names -contains 'assets/chronos-proof-card.png') {
      throw "Skills-only package must not include the GitHub proof screenshot."
    }
  } finally {
    $archive.Dispose()
  }

  $installRoot = Join-Path $testRoot "installed plugin with spaces"
  [System.IO.Compression.ZipFile]::ExtractToDirectory($firstArtifact, $installRoot)
  $installedManifestPath = Join-Path $installRoot ".codex-plugin\plugin.json"
  $installedManifest = Get-Content -Raw -LiteralPath $installedManifestPath | ConvertFrom-Json
  if ([string]$installedManifest.version -ne $version) {
    throw "Extracted package version does not match $version."
  }
  $installedSkills = @(
    Get-ChildItem -LiteralPath (Join-Path $installRoot "skills") -Directory |
      Sort-Object Name |
      ForEach-Object { $_.Name }
  )
  if (($installedSkills -join "`n") -ne "chronos`nchronos-governor") {
    throw "Extracted package must contain exactly the chronos and chronos-governor skills."
  }

  $directoryCodexHome = Join-Path $testRoot 'directory-clean-home'
  $directoryInstallRoot = Join-Path $directoryCodexHome "plugins\cache\openai-curated-remote\chronos\$version"
  New-Item -ItemType Directory -Path $directoryInstallRoot -Force | Out-Null
  [System.IO.Compression.ZipFile]::ExtractToDirectory($firstArtifact, $directoryInstallRoot)
  $directoryLauncher = Join-Path $directoryInstallRoot 'skills\chronos\scripts\chronos.cmd'
  $directoryOutput = @(& $directoryLauncher -Action install-status -CodexHome $directoryCodexHome 2>&1)
  $directoryText = $directoryOutput -join "`n"
  if ($LASTEXITCODE -ne 0 -or
      $directoryText -notmatch ('pluginVersion=' + [regex]::Escape($version) + '\b') -or
      $directoryText -notmatch 'currentPluginIdentity=chronos@openai-curated-remote\b' -or
      $directoryText -notmatch 'canonicalPluginIdentity=chronos@openai-curated-remote\b' -or
      $directoryText -notmatch 'cachedSourceCount=1\b' -or
      $directoryText -notmatch 'sourceConflict=NONE\b') {
    throw "Canonical Directory clean-install discovery failed.`n$directoryText"
  }
  $installedHookText = Get-Content -Raw -LiteralPath (Join-Path $installRoot 'hooks\hooks.json')
  $installedHooks = $installedHookText | ConvertFrom-Json
  $installedEventNames = @($installedHooks.hooks.PSObject.Properties.Name | Sort-Object)
  if (($installedEventNames -join ',') -ne 'SessionEnd,SessionStart,Stop,SubagentStart,SubagentStop') {
    throw 'Extracted package does not contain the expected bounded monitoring hook set.'
  }
  if (([regex]::Matches($installedHookText, '"async"\s*:\s*true')).Count -ne 4) {
    throw 'Extracted package must run every non-terminal monitoring hook in the background.'
  }
  if (($installedHooks.hooks.SessionEnd[0].hooks[0].PSObject.Properties.Name) -contains 'async') {
    throw 'Extracted package must leave SessionEnd synchronous.'
  }
  if (([regex]::Matches($installedHookText, '"timeout"\s*:\s*3')).Count -ne 5) {
    throw 'Extracted package must cap every monitoring hook at three seconds.'
  }
  $installedWindowsCommands = @(
    $installedHooks.hooks.PSObject.Properties.Value |
      ForEach-Object { $_[0].hooks[0].commandWindows }
  )
  if (($installedWindowsCommands | Select-Object -Unique).Count -ne 1) {
    throw 'Extracted lifecycle events do not share one audited Windows launcher.'
  }
  $installedWindowsCommand = [string]$installedWindowsCommands[0]
  if ($installedWindowsCommand.Contains('"') -or $installedWindowsCommand -notmatch ' -EncodedCommand ([A-Za-z0-9+/=]+)$') {
    throw 'Extracted Windows hook launcher is not quote-free and encoded for the Codex cmd.exe boundary.'
  }
  $installedWindowsPayload = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))
  if ($installedWindowsPayload -ne "`$ProgressPreference='SilentlyContinue'; & (Join-Path `$env:PLUGIN_ROOT 'skills\chronos\scripts\hook-intake.ps1')") {
    throw 'Extracted Windows hook payload does not resolve PLUGIN_ROOT safely inside PowerShell.'
  }
  foreach ($installedScript in @(Get-ChildItem -LiteralPath $installRoot -Recurse -Filter *.ps1 -File)) {
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($installedScript.FullName, [ref]$null, [ref]$parseErrors) | Out-Null
    if ($parseErrors) { throw "Packaged script failed Windows PowerShell 5.1 parsing: $($installedScript.FullName)" }
  }
  $installedHeartbeat = Join-Path $installRoot "skills\chronos\scripts\chronos.ps1"
  $installedLauncher = Join-Path $installRoot "skills\chronos\scripts\chronos.cmd"
  $heartbeatTestRoot = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' ('release-smoke-' + [guid]::NewGuid().ToString('N')))
  New-Item -ItemType Directory -Path $heartbeatTestRoot -Force | Out-Null
  $installedState = Join-Path $heartbeatTestRoot "installed-heartbeat-state.json"
  $installedOutput = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $installedHeartbeat -Action heartbeat -HeartbeatStatePath $installedState `
    -HeartbeatScope "release-install-smoke" 2>&1)
  if ($LASTEXITCODE -ne 0 -or ($installedOutput -join "`n") -notmatch 'CHRONOS HEARTBEATS engine=uninitialized evaluation=unsupported activeTypes=8 statusMode=prior_state' -or ($installedOutput -join "`n") -notmatch 'coverageUnsupported=8') {
    throw "Extracted package Heartbeat status smoke test failed.`n$($installedOutput -join "`n")"
  }
  $launcherOutput = @(& $installedLauncher -Action heartbeat -HeartbeatStatePath $installedState `
    -HeartbeatScope "release-install-smoke" 2>&1)
  if ($LASTEXITCODE -ne 0 -or ($launcherOutput -join "`n") -notmatch 'CHRONOS HEARTBEATS engine=uninitialized evaluation=unsupported activeTypes=8 statusMode=prior_state' -or ($launcherOutput -join "`n") -notmatch 'coverageUnsupported=8') {
    throw "Extracted package launcher did not apply the supported Windows PowerShell invocation.`n$($launcherOutput -join "`n")"
  }
  $installedCustomCodexHome = Join-Path $testRoot 'custom installed codex home'
  New-Item -ItemType Directory -Path $installedCustomCodexHome -Force | Out-Null
  $installedCustomIdentity = ([IO.Path]::GetFullPath((Get-Item -LiteralPath $installedCustomCodexHome -Force).FullName)).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)).ToUpperInvariant()
  $installedCustomIdentityToken = (Get-TextHash $installedCustomIdentity).Substring(0, 16)
  $installedCustomHeartbeatIdentityToken = $installedCustomIdentityToken
  $installedCustomScopeHash = Get-TextHash ('{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), $installedCustomIdentity)
  $heartbeatDefaultTestRoot = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' $installedCustomScopeHash)
  $customHeartbeatOutput = @(& $installedLauncher -Action heartbeat -CodexHome $installedCustomCodexHome 2>&1)
  $customHeartbeatExitCode = $LASTEXITCODE
  $customHeartbeatText = $customHeartbeatOutput -join "`n"
  if ($customHeartbeatExitCode -ne 0 -or $customHeartbeatText -notmatch 'codexHomeSource=explicit\b' -or $customHeartbeatText -notmatch ('codexHomeIdentity=' + [regex]::Escape($installedCustomHeartbeatIdentityToken) + '\b')) {
    throw "Extracted package did not bind Heartbeat to explicit CODEX_HOME.`n$customHeartbeatText"
  }
  $supervisionScopeHash = Get-TextHash ('{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), $installedCustomIdentity)
  $supervisionDefaultTestRoots = @(0..3 | ForEach-Object { Join-Path ([IO.Path]::GetTempPath()) ('Chronos-Supervision-v3-{0}-{1}' -f $supervisionScopeHash.Substring(0, 24), $_) })
  $customSupervisionOutput = @(& $installedLauncher -Action supervise -SupervisionAction status -CodexHome $installedCustomCodexHome 2>&1)
  $customSupervisionExitCode = $LASTEXITCODE
  $customSupervisionText = $customSupervisionOutput -join "`n"
  if ($customSupervisionExitCode -ne 0 -or $customSupervisionText -notmatch '"codexHomeSource":"explicit"' -or $customSupervisionText -notmatch ('"codexHomeIdentity":"' + [regex]::Escape($installedCustomIdentityToken) + '"')) {
    throw "Extracted package did not bind supervision to explicit CODEX_HOME.`n$customSupervisionText"
  }
  $installedSupervisionState = Join-Path $supervisionTestRoot "installed-supervision-state.json"
  $installedSupervisionOutput = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $installedHeartbeat -Action supervise -SupervisionAction status `
    -SupervisionStatePath $installedSupervisionState 2>&1)
  if ($LASTEXITCODE -ne 0 -or ($installedSupervisionOutput -join "`n") -notmatch 'CHRONOS SUPERVISION .*"engine":"healthy"') {
    throw "Extracted package supervision status smoke test failed.`n$($installedSupervisionOutput -join "`n")"
  }
  $installedSupervisionLine = @($installedSupervisionOutput | Where-Object { $_ -like 'CHRONOS SUPERVISION *' } | Select-Object -Last 1)
  $installedSupervisionData = $installedSupervisionLine[0].Substring('CHRONOS SUPERVISION '.Length) | ConvertFrom-Json
  if ($installedSupervisionData.hostEquivalenceKey -notmatch '^chronos-supervision-v1:[a-f0-9]{32}$' -or
      $installedSupervisionData.equivalenceScope -ne 'installation' -or
      $installedSupervisionData.installationScopePersistence -ne 'state_root_anchor' -or
      $installedSupervisionData.installationScopeSource -ne 'state_root_anchor' -or
      $installedSupervisionData.hostReconcileAttemptLimit -ne 3 -or
      $installedSupervisionData.hostRecheckThroughCycle -ne 2 -or
      $installedSupervisionData.hostPostcondition -ne 'one_live_governor_one_active_recurrence_zero_duplicates') {
    throw 'Extracted package omitted deterministic host convergence controls.'
  }
  $installedRegistry = Join-Path $installRoot "skills\chronos\scripts\session-registry.ps1"
  $hookInfo = New-Object Diagnostics.ProcessStartInfo
  $hookInfo.FileName = $windowsPowerShell
  $hookInfo.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action hook -StatePath "{1}"' -f $installedRegistry, $installedSupervisionState
  $hookInfo.UseShellExecute = $false
  $hookInfo.CreateNoWindow = $true
  $hookInfo.RedirectStandardInput = $true
  $hookInfo.RedirectStandardOutput = $true
  $hookInfo.RedirectStandardError = $true
  $hookProcess = [Diagnostics.Process]::Start($hookInfo)
  $hookProcess.StandardInput.Write('{"session_id":"release-package-hook","cwd":"C:/release-fixture","hook_event_name":"SessionStart","source":"startup","model":"gpt-5.6-luna"}')
  $hookProcess.StandardInput.Close()
  if (-not $hookProcess.WaitForExit(10000)) { try { $hookProcess.Kill() } catch {}; throw "Packaged diagnostic hook exceeded its bounded release-test watchdog." }
  $hookStdout = $hookProcess.StandardOutput.ReadToEnd()
  $hookStderr = $hookProcess.StandardError.ReadToEnd()
  $hookExit = $hookProcess.ExitCode
  $hookProcess.Dispose()
  if ($hookExit -ne 0 -or $hookStdout -or $hookStderr) {
    throw "Packaged lifecycle hook was not silent and successful."
  }

  $configuredHookTemp = Join-Path $testRoot 'configured hook temp'
  New-Item -ItemType Directory -Path $configuredHookTemp -Force | Out-Null
  $configuredHookInfo = New-Object Diagnostics.ProcessStartInfo
  $configuredHookInfo.FileName = $env:ComSpec
  $configuredHookInfo.Arguments = '/D /S /C "' + $installedWindowsCommand + '"'
  $configuredHookInfo.UseShellExecute = $false
  $configuredHookInfo.CreateNoWindow = $true
  $configuredHookInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $configuredHookInfo.RedirectStandardInput = $true
  $configuredHookInfo.RedirectStandardOutput = $true
  $configuredHookInfo.RedirectStandardError = $true
  $configuredHookInfo.EnvironmentVariables['PLUGIN_ROOT'] = $installRoot
  $configuredHookInfo.EnvironmentVariables['TEMP'] = $configuredHookTemp
  $configuredHookInfo.EnvironmentVariables['TMP'] = $configuredHookTemp
  [void]$configuredHookInfo.EnvironmentVariables.Remove('CODEX_HOME')
  $configuredHookWatch = [Diagnostics.Stopwatch]::StartNew()
  $configuredHookProcess = [Diagnostics.Process]::Start($configuredHookInfo)
  $configuredHookProcess.StandardInput.Write('{"session_id":"release-configured-hook","cwd":"C:/release-fixture","hook_event_name":"SessionStart","source":"startup","model":"gpt-5.6-luna"}')
  $configuredHookProcess.StandardInput.Close()
  if (-not $configuredHookProcess.WaitForExit(30000)) {
    try { $configuredHookProcess.Kill() } catch {}
    throw ('Packaged configured lifecycle hook exceeded its bounded release-test watchdog. Elapsed={0}ms' -f $configuredHookWatch.ElapsedMilliseconds)
  }
  $configuredHookWatch.Stop()
  $configuredHookStdout = $configuredHookProcess.StandardOutput.ReadToEnd()
  $configuredHookStderr = $configuredHookProcess.StandardError.ReadToEnd()
  $configuredHookExit = $configuredHookProcess.ExitCode
  $configuredHookProcess.Dispose()
  if ($configuredHookExit -ne 0 -or $configuredHookStdout -or $configuredHookStderr) {
    throw 'Packaged configured lifecycle hook did not execute silently through the Codex cmd.exe boundary.'
  }
  $configuredCodexHomeIdentity = ([IO.Path]::GetFullPath((Join-Path $HOME '.codex'))).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)).ToUpperInvariant()
  $configuredScopeHash = Get-TextHash ('{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), $configuredCodexHomeIdentity)
  $configuredRegistryPath = Join-Path $configuredHookTemp (Join-Path ('Chronos-Supervision-v3-{0}-0' -f $configuredScopeHash.Substring(0, 24)) 'session-registry.json')
  $configuredInboxPath = Join-Path $configuredHookTemp ('Chronos-Supervision-Inbox-v1-{0}' -f $configuredScopeHash.Substring(0, 24))
  if (Test-Path -LiteralPath $configuredRegistryPath) {
    throw 'Packaged configured lifecycle hook performed synchronous registry work.'
  }
  $configuredInboxFiles = @(Get-ChildItem -LiteralPath $configuredInboxPath -File -Filter 'pending-slot-*.json')
  if ($configuredInboxFiles.Count -ne 1) {
    throw 'Packaged configured lifecycle hook did not persist exactly one inbox event.'
  }
  $configuredInboxRecord = Get-Content -Raw -LiteralPath $configuredInboxFiles[0].FullName | ConvertFrom-Json
  if ($configuredInboxRecord.event -ne 'SessionStart' -or
      [string]$configuredInboxRecord.protectedSessionId -match 'release-configured-hook') {
    throw 'Packaged configured lifecycle hook did not protect the queued identity.'
  }
  $configuredStatusInfo = New-Object Diagnostics.ProcessStartInfo
  $configuredStatusInfo.FileName = $windowsPowerShell
  $configuredStatusInfo.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action supervise -SupervisionAction status' -f $installedHeartbeat
  $configuredStatusInfo.UseShellExecute = $false
  $configuredStatusInfo.CreateNoWindow = $true
  $configuredStatusInfo.RedirectStandardOutput = $true
  $configuredStatusInfo.RedirectStandardError = $true
  $configuredStatusInfo.EnvironmentVariables['TEMP'] = $configuredHookTemp
  $configuredStatusInfo.EnvironmentVariables['TMP'] = $configuredHookTemp
  [void]$configuredStatusInfo.EnvironmentVariables.Remove('CODEX_HOME')
  $configuredStatusProcess = [Diagnostics.Process]::Start($configuredStatusInfo)
  if (-not $configuredStatusProcess.WaitForExit(30000)) {
    try { $configuredStatusProcess.Kill() } catch {}
    throw 'Packaged supervision status exceeded its bounded inbox-merge test.'
  }
  $configuredStatusStdout = $configuredStatusProcess.StandardOutput.ReadToEnd()
  $configuredStatusStderr = $configuredStatusProcess.StandardError.ReadToEnd()
  $configuredStatusExit = $configuredStatusProcess.ExitCode
  $configuredStatusProcess.Dispose()
  if ($configuredStatusExit -ne 0 -or $configuredStatusStderr -or $configuredStatusStdout -notmatch 'CHRONOS SUPERVISION .*"hookRuns":1') {
    throw "Packaged supervision status did not merge the configured hook inbox exactly once.`n$configuredStatusStdout`n$configuredStatusStderr"
  }
  if (-not (Test-Path -LiteralPath $configuredRegistryPath -PathType Leaf) -or
      @(Get-ChildItem -LiteralPath $configuredInboxPath -File -Filter 'pending-slot-*.json').Count -ne 0) {
    throw 'Packaged configured hook inbox was not consumed into the private registry.'
  }
  $configuredRegistry = Get-Content -Raw -LiteralPath $configuredRegistryPath | ConvertFrom-Json
  if ($configuredRegistry.health.hookRuns -ne 1 -or -not $configuredRegistry.health.lastHookUtc) {
    throw 'Packaged configured lifecycle hook did not record fresh lifecycle activity.'
  }

  $checksum = (Get-Content -Raw -LiteralPath (Join-Path $first "chronos-v$version.sha256")).Trim()
  if ($checksum -ne ($firstHash.ToLowerInvariant() + "  " + $artifactName)) { throw "Checksum file does not match the artifact." }
  $submissionPacket = Get-Content -Raw -LiteralPath $submissionPacketPath
  foreach ($required in @(
    "Version: ``$version``",
    "chronos-v$version.zip",
    "releases/tag/v$version",
    $firstHash.ToLowerInvariant()
  )) {
    if (-not $submissionPacket.Contains($required)) {
      throw "Plugin Directory submission packet is out of sync with the release: $required"
    }
  }
  $releaseManifest = Get-Content -Raw -LiteralPath (Join-Path $first "chronos-v$version.release.json") | ConvertFrom-Json
  if ($releaseManifest.schema_version -ne 3 -or @($releaseManifest.files).Count -ne $releaseManifest.packaged_files) {
    throw "Release manifest must contain a versioned per-file inventory."
  }
  if ([string]$releaseManifest.distribution.repository -ne 'FaxanFM/chronos' -or
      [string]$releaseManifest.distribution.canonical_identity -ne 'chronos@openai-curated-remote' -or
      [string]$releaseManifest.distribution.canonical_source -ne 'openai-curated-remote' -or
      [string]$releaseManifest.distribution.legacy_git_identity -ne 'chronos@chronos' -or
      [string]$releaseManifest.distribution.plugin_directory_listing -ne 'plugins_6a79c882cf488191b8f62ee20e0e2571') {
    throw 'Release manifest does not bind the public Directory and legacy Git identities.'
  }
  if (
    [long]$releaseManifest.packaged_bytes -gt [long]$releaseManifest.package_limits.package_bytes -or
    [int]$releaseManifest.packaged_files -gt [int]$releaseManifest.package_limits.files
  ) { throw "Release manifest violates its package limits." }
  $archive = [System.IO.Compression.ZipFile]::OpenRead($firstArtifact)
  try {
    foreach ($fileRecord in @($releaseManifest.files)) {
      $entry = $archive.GetEntry([string]$fileRecord.path)
      if (-not $entry) { throw "Release manifest references a missing entry: $($fileRecord.path)" }
      $sha = [System.Security.Cryptography.SHA256]::Create()
      $entryStream = $entry.Open()
      try {
        $entryHash = ([System.BitConverter]::ToString($sha.ComputeHash($entryStream))).Replace('-', '').ToLowerInvariant()
      } finally {
        $entryStream.Dispose()
        $sha.Dispose()
      }
      if ($entryHash -ne [string]$fileRecord.sha256 -or [long]$entry.Length -ne [long]$fileRecord.bytes) {
        throw "Release manifest hash or size mismatch: $($fileRecord.path)"
      }
    }
  } finally {
    $archive.Dispose()
  }
  Write-Output "Chronos release tests passed. Reproducibility: 2/2 identical builds."
} finally {
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
  $resolvedSupervisionTest = [System.IO.Path]::GetFullPath($supervisionTestRoot)
  $approvedSupervisionRoot = [System.IO.Path]::GetFullPath((Join-Path $resolvedTemp 'Chronos\Supervision'))
  if ($resolvedSupervisionTest.StartsWith($approvedSupervisionRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedSupervisionTest -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($heartbeatTestRoot) {
    $resolvedHeartbeatTest = [System.IO.Path]::GetFullPath($heartbeatTestRoot)
    $approvedHeartbeatRoot = [System.IO.Path]::GetFullPath((Join-Path $resolvedTemp 'Chronos\Heartbeat-v2'))
    if ($resolvedHeartbeatTest.StartsWith($approvedHeartbeatRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolvedHeartbeatTest -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  if ($heartbeatDefaultTestRoot) {
    Remove-Item -LiteralPath $heartbeatDefaultTestRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  foreach ($supervisionDefaultTestRoot in @($supervisionDefaultTestRoots)) {
    Remove-Item -LiteralPath $supervisionDefaultTestRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit 0
