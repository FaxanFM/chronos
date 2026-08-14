param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $repoRoot "scripts\build-release.ps1"
$manifestPath = Join-Path $repoRoot "plugins\chronos\.codex-plugin\plugin.json"
$releaseWorkflowPath = Join-Path $repoRoot ".github\workflows\release.yml"
$testWorkflowPath = Join-Path $repoRoot ".github\workflows\test.yml"
$readmePath = Join-Path $repoRoot "README.md"
$pluginReadmePath = Join-Path $repoRoot "plugins\chronos\README.md"
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
  if ($defaultPrompts.Count -gt 3) {
    throw "Directory defaultPrompt must contain at most three prompts."
  }
  if ($defaultPrompts.Count -ne @($defaultPrompts | Where-Object { $_ -is [string] -and $_.Trim() }).Count) {
    throw "Directory defaultPrompt entries must be non-empty strings."
  }
  if ($manifest.interface.PSObject.Properties['screenshots']) {
    throw "Skills-only packages must not declare interface screenshots."
  }
  $upgradeBoundary = @(
    Get-Content -Raw -LiteralPath $readmePath
    Get-Content -Raw -LiteralPath $operationsPath
    Get-Content -Raw -LiteralPath $supportPath
  ) -join "`n"
  foreach ($required in @('fresh task', 'versioned plugin skill locator', 'Do not copy', 'stale task catalog state')) {
    if (-not $upgradeBoundary.Contains($required)) {
      throw "Public upgrade guidance is missing the stale task-locator boundary: $required"
    }
  }
  $supervisionContract = Get-Content -Raw -LiteralPath $supervisionPath
  foreach ($required in @(
    'exactly one active',
    'chronos-supervision-v1',
    'at most three attempts',
    'cycles zero and one',
    'zero active duplicates',
    '60 minutes while monitored work is active and 360 minutes while idle',
    '336 cycles or 14 days',
    '-SupervisionConfirmRecurrenceStopped',
    '%TEMP%\Chronos\Supervision\session-registry.json',
    'one compact host task-list call',
    'gpt-5.6-terra',
    'routine user action',
    'DPAPI does not protect against another process already running as that'
  )) {
    if (-not $supervisionContract.Contains($required)) {
      throw "Public supervision contract is missing a release boundary: $required"
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
  )) {
    if (-not $heartbeatContract.Contains($required)) {
      throw "Public Heartbeat contract is missing an autonomy boundary: $required"
    }
  }
  $publicReadmes = @(
    Get-Content -Raw -LiteralPath $readmePath
    Get-Content -Raw -LiteralPath $pluginReadmePath
  ) -join "`n"
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
    'gh attestation verify $Path --repo $env:GITHUB_REPOSITORY',
    '--draft',
    'gh release edit $env:GITHUB_REF_NAME --draft=false',
    'function Invoke-ReleaseVerification',
    'for ($attempt = 1; $attempt -le 12; $attempt++)',
    'Start-Sleep -Seconds 5',
    'gh release verify $env:GITHUB_REF_NAME',
    'gh release verify-asset $env:GITHUB_REF_NAME'
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
    foreach ($required in @('.codex-plugin/plugin.json', 'hooks/hooks.json', 'skills/chronos/SKILL.md', 'skills/chronos/scripts/chronos.cmd', 'skills/chronos/scripts/heartbeat.ps1', 'skills/chronos/scripts/session-registry.ps1', 'skills/chronos-governor/SKILL.md')) {
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

  $installRoot = Join-Path $testRoot "installed"
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
  $installedHookText = Get-Content -Raw -LiteralPath (Join-Path $installRoot 'hooks\hooks.json')
  if ($installedHookText.Contains('"async"')) {
    throw 'Extracted package requests background hooks that the target Codex host skips.'
  }
  if (([regex]::Matches($installedHookText, '"timeout"\s*:\s*3')).Count -ne 4) {
    throw 'Extracted package must cap every lifecycle hook at three seconds.'
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
  if ($LASTEXITCODE -ne 0 -or ($installedOutput -join "`n") -notmatch 'CHRONOS HEARTBEATS engine=healthy activeTypes=8') {
    throw "Extracted package Heartbeat status smoke test failed.`n$($installedOutput -join "`n")"
  }
  $launcherOutput = @(& $installedLauncher -Action heartbeat -HeartbeatStatePath $installedState `
    -HeartbeatScope "release-install-smoke" 2>&1)
  if ($LASTEXITCODE -ne 0 -or ($launcherOutput -join "`n") -notmatch 'CHRONOS HEARTBEATS engine=healthy activeTypes=8') {
    throw "Extracted package launcher did not apply the supported Windows PowerShell invocation.`n$($launcherOutput -join "`n")"
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
  if (-not $hookProcess.WaitForExit(3000)) { try { $hookProcess.Kill() } catch {}; throw "Packaged lifecycle hook exceeded its host timeout." }
  $hookStdout = $hookProcess.StandardOutput.ReadToEnd()
  $hookStderr = $hookProcess.StandardError.ReadToEnd()
  $hookExit = $hookProcess.ExitCode
  $hookProcess.Dispose()
  if ($hookExit -ne 0 -or $hookStdout -or $hookStderr) {
    throw "Packaged lifecycle hook was not silent and successful."
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
  if ($releaseManifest.schema_version -ne 2 -or @($releaseManifest.files).Count -ne $releaseManifest.packaged_files) {
    throw "Release manifest must contain a versioned per-file inventory."
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
}

exit 0
