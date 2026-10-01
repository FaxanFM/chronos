param()

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') {
  throw 'Directory validation requires inbox Windows PowerShell 5.1.'
}
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path ([IO.Path]::GetTempPath()) ('chronos-directory-' + [guid]::NewGuid().ToString('N'))
$first = Join-Path $root 'first'
$second = Join-Path $root 'second'
$package = Join-Path $root 'package'
$fixtureHome = Join-Path $root 'codex-home'
$version = [string](Get-Content -Raw (Join-Path $repo 'plugins/chronos/.codex-plugin/plugin.json') | ConvertFrom-Json).version
$builder = Join-Path $repo 'scripts/build-release.ps1'
$priorHome = $env:CODEX_HOME
New-Item -ItemType Directory -Path $fixtureHome -Force | Out-Null

function Invoke-Native {
  param([string[]]$Arguments)
  $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper @Arguments)
  if ($LASTEXITCODE -ne 0) { throw ('Directory native action failed: ' + ($output -join "`n")) }
  return ($output -join "`n")
}

function Read-Supervision {
  param([string[]]$Arguments)
  $text = Invoke-Native (@('-Action', 'supervise', '-SupervisionStatePath', $state) + $Arguments)
  if (-not $text.StartsWith('CHRONOS SUPERVISION ')) { throw 'Missing compact supervision result.' }
  $payload = $text.Substring('CHRONOS SUPERVISION '.Length) | ConvertFrom-Json
  if (-not $payload.ok) { throw ('Directory supervision rejected: ' + $payload.error) }
  return $payload
}

try {
  & $builder -Version $version -Edition Directory -OutputDirectory $first
  & $builder -Version $version -Edition Directory -OutputDirectory $second
  $name = "chronos-v$version-skills-only"
  foreach ($extension in @('zip', 'sha256', 'release.json')) {
    if ((Get-FileHash (Join-Path $first "$name.$extension")).Hash -ne
        (Get-FileHash (Join-Path $second "$name.$extension")).Hash) { throw "Directory artifact is not reproducible: $extension" }
  }
  Expand-Archive -LiteralPath (Join-Path $first "$name.zip") -DestinationPath $package
  $manifest = Get-Content -Raw (Join-Path $package '.codex-plugin/plugin.json') | ConvertFrom-Json
  if ($manifest.PSObject.Properties['hooks'] -or $manifest.PSObject.Properties['apps'] -or
      (Test-Path (Join-Path $package 'hooks')) -or
      (Test-Path (Join-Path $package 'skills/chronos/scripts/hook-intake.ps1'))) {
    throw 'Directory package contains excluded lifecycle hooks or app references.'
  }
  $skills = @(Get-ChildItem -LiteralPath (Join-Path $package 'skills') -Directory | Select-Object -ExpandProperty Name)
  if (($skills | Sort-Object) -join ',' -ne 'chronos,chronos-governor') { throw 'Directory package lost a core skill.' }
  foreach ($skill in $skills) {
    $text = Get-Content -Raw (Join-Path $package "skills/$skill/SKILL.md")
    if (-not $text.Contains('**Installed edition: skills-only.**') -or
        -not $text.Contains('Do not download or auto-install GitHub hooks')) { throw 'Directory skill lost edition disclosure.' }
  }
  if (-not $manifest.interface.longDescription.Contains('Lifecycle hooks are not included or auto-installed') -or
      -not $manifest.description.StartsWith('Skills-only edition:') -or
      $manifest.extensions.'com.openai'.onboardingSkill -ne './skills/chronos/SKILL.md') {
    throw 'Directory listing or onboarding does not match the edition.'
  }
  foreach ($prompt in $manifest.interface.defaultPrompt) {
    if ($prompt.Length -gt 128 -or $prompt.Contains("`n")) { throw 'Directory starter exceeds submission limits.' }
  }
  $record = Get-Content -Raw (Join-Path $first "$name.release.json") | ConvertFrom-Json
  if ($record.edition -ne 'skills_only' -or $record.lifecycle_hooks_included -or $record.packaged_files -ne 12) {
    throw 'Directory release record does not bind its edition and 12-file package.'
  }
  foreach ($file in $record.files) {
    if ((Get-FileHash (Join-Path $package $file.path)).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Directory file hash mismatch: $($file.path)" }
  }

  # No real account state, hook trust, recurrence, or model turn is involved.
  $env:CODEX_HOME = $fixtureHome
  $wrapper = Join-Path $package 'skills/chronos/scripts/chronos.ps1'
  $stateRoot = Join-Path ([IO.Path]::GetTempPath()) ('Chronos/Supervision/directory-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  $state = Join-Path $stateRoot 'session-registry.json'
  $empty = Read-Supervision @('-SupervisionAction', 'status')
  if ($empty.recommendedGovernorModel -ne 'gpt-6-sol' -or $empty.recommendedGovernorReasoningEffort -ne 'medium') {
    throw 'Directory native model recommendation is stale.'
  }
  $preflight = Read-Supervision @('-SupervisionAction', 'preflight', '-SupervisionHostInventoryCompleteness', 'visible_or_specified',
    '-SupervisionHostInventoryStatusAuthority', 'current_host_runtime')
  if ($preflight.recurrenceEligible) { throw 'Non-claiming preflight scheduled early.' }
  $initialized = Read-Supervision @('-SupervisionAction', 'initialize', '-SupervisionSessionId', 'directory-governor',
    '-SupervisionHostInventoryCompleteness', 'visible_or_specified', '-SupervisionHostInventoryStatusAuthority', 'current_host_runtime')
  if ($initialized.recurrenceEligible) { throw 'Directory initialization scheduled before inventory.' }
  $inventory = Join-Path $root 'inventory.json'
  [IO.File]::WriteAllText($inventory, ([ordered]@{
    schemaVersion = 3; capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o'); complete = $false
    callerVisibility = 'excluded_by_host'; scope = 'visible_or_specified'
    tasks = @([ordered]@{ id = 'directory-active'; status = 'running'; generation = $null; selection = 'visible' })
  } | ConvertTo-Json -Depth 5 -Compress), [Text.UTF8Encoding]::new($false))
  $cycle = Read-Supervision @('-SupervisionAction', 'cycle', '-SupervisionSessionId', 'directory-governor', '-SupervisionHostInventoryPath', $inventory,
    '-SupervisionHostInventoryStatusAuthority', 'current_host_runtime')
  if (-not $cycle.recurrenceEligible -or $cycle.activeTasks -ne 1 -or $cycle.workerRecurrence -ne 'disabled' -or
      $cycle.hostInventoryRawObserved -ne 1 -or $cycle.hostInventoryObserved -ne 2 -or $cycle.hostInventoryComplete) {
    throw 'Hook-free package failed the bounded caller-aware native cycle.'
  }
  $restart = Read-Supervision @('-SupervisionAction', 'status')
  if (-not $restart.recurrenceEligible -or $restart.recommendedGovernorModel -ne 'gpt-6-sol') { throw 'Directory state did not survive a new process.' }
  $heartbeatRoot = Join-Path ([IO.Path]::GetTempPath()) ('Chronos/Heartbeat-v2/directory-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $heartbeatRoot -Force | Out-Null
  $heartbeat = Invoke-Native @('-Action', 'heartbeat', '-HeartbeatStatePath', (Join-Path $heartbeatRoot 'heartbeat.json'))
  if ($heartbeat -notmatch 'evaluation=unsupported' -or $heartbeat -notmatch 'coverageUnsupported=8') {
    throw 'No collector evidence was misrepresented as healthy.'
  }
  [ordered]@{ result = 'PASS'; edition = 'skills_only'; files = 12; hooks = 0; model = 'gpt-6-sol'; effort = 'medium'
    reproducible = $true; nativeScopedCycle = 'PASS'; restart = 'PASS'; coverageUnsupported = 8
    modelTurns = 0; recurrencesCreated = 0; liveScheduledExecution = 'not_evaluated' } | ConvertTo-Json -Compress
} finally {
  $env:CODEX_HOME = $priorHome
}
