param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$module = Join-Path $repo 'plugins\chronos\skills\chronos\scripts\session-registry.ps1'
$wrapper = Join-Path $repo 'plugins\chronos\skills\chronos\scripts\chronos.ps1'
$hooksPath = Join-Path $repo 'plugins\chronos\hooks\hooks.json'
$governorSkillPath = Join-Path $repo 'plugins\chronos\skills\chronos-governor\SKILL.md'
$approvedTempRoot = Join-Path ([IO.Path]::GetTempPath()) 'Chronos\Supervision'
$root = Join-Path $approvedTempRoot ('tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Get-TestHash {
  param([string]$Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Get-Payload {
  param($Result)
  $line = @($Result.Output | Where-Object { $_ -like 'CHRONOS SUPERVISION *' } | Select-Object -Last 1)
  if ($line.Count -ne 1) { throw "Expected one supervision payload.`n$($Result.Text)" }
  $line[0].Substring('CHRONOS SUPERVISION '.Length) | ConvertFrom-Json
}

function Invoke-Supervision {
  param(
    [string]$State,
    [string]$Action = 'status',
    [string]$Session = '',
    [long]$SinceRevision = 0,
    [string]$Subject = '',
    [string]$HostInventory = '',
    [switch]$ConfirmRecurrenceStopped,
    [switch]$Force
  )
  $arguments = @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $wrapper,
    '-Action', 'supervise', '-SupervisionAction', $Action,
    '-SupervisionStatePath', $State, '-SupervisionSinceRevision', [string]$SinceRevision
  )
  if ($Session) { $arguments += @('-SupervisionSessionId', $Session) }
  if ($Subject) { $arguments += @('-SupervisionSubjectId', $Subject) }
  if ($HostInventory) { $arguments += @('-SupervisionHostInventoryPath', $HostInventory) }
  if ($ConfirmRecurrenceStopped) { $arguments += '-SupervisionConfirmRecurrenceStopped' }
  if ($Force) { $arguments += '-Force' }
  $output = @(& powershell.exe @arguments 2>&1)
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output; Text = ($output -join "`n") }
}

function Start-HookProcess {
  param(
    [string]$State,
    [string]$Json,
    [string]$ObservedAtUtc = '',
    [switch]$Diagnostic,
    [switch]$Utf8Bom
  )
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = 'powershell.exe'
  $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action hook -StatePath "{1}"' -f $module, $State
  if ($ObservedAtUtc) { $info.Arguments += ' -ObservedAtUtc "{0}"' -f $ObservedAtUtc }
  if ($Diagnostic) { $info.Arguments += ' -Diagnostic' }
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $process = [Diagnostics.Process]::Start($info)
  if ($Utf8Bom) {
    $bytes = [Text.Encoding]::UTF8.GetPreamble() + [Text.Encoding]::UTF8.GetBytes($Json)
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.BaseStream.Close()
  } else {
    $process.StandardInput.Write($Json)
    $process.StandardInput.Close()
  }
  $stage = 'unparsed-hook'
  try {
    $stageData = $Json | ConvertFrom-Json -ErrorAction Stop
    $stage = '{0}:{1}' -f [string]$stageData.hook_event_name, [string]$stageData.session_id
  } catch {}
  [pscustomobject]@{ Process = $process; State = $State; Stage = $stage }
}

function Start-SupervisionStatusProcess {
  param([string]$State)
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = 'powershell.exe'
  $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action supervise -SupervisionAction status -SupervisionStatePath "{1}"' -f $wrapper, $State
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  [pscustomobject]@{ Process = [Diagnostics.Process]::Start($info); State = $State }
}

function Complete-HookProcess {
  param($Invocation, [int]$TimeoutMilliseconds = 10000)
  if (-not $Invocation.Process.WaitForExit($TimeoutMilliseconds)) {
    try { $Invocation.Process.Kill() } catch {}
    throw ('Lifecycle hook exceeded its bounded test timeout: ' + [string]$Invocation.Stage)
  }
  $result = [pscustomobject]@{
    ExitCode = $Invocation.Process.ExitCode
    Output = $Invocation.Process.StandardOutput.ReadToEnd()
    Error = $Invocation.Process.StandardError.ReadToEnd()
  }
  $Invocation.Process.Dispose()
  $result
}

function Invoke-Hook {
  param([string]$State, $Data, [string]$ObservedAtUtc = '')
  Complete-HookProcess (Start-HookProcess $State ($Data | ConvertTo-Json -Compress -Depth 8) $ObservedAtUtc)
}

function Invoke-ConfiguredWindowsHook {
  param([string]$Command, [string]$PluginRoot, [string]$TempRoot, [string]$Json)
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = $env:ComSpec
  $info.Arguments = '/D /S /C "' + $Command + '"'
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.EnvironmentVariables['PLUGIN_ROOT'] = $PluginRoot
  $info.EnvironmentVariables['TEMP'] = $TempRoot
  $info.EnvironmentVariables['TMP'] = $TempRoot
  $process = [Diagnostics.Process]::Start($info)
  $process.StandardInput.Write($Json)
  $process.StandardInput.Close()
  if (-not $process.WaitForExit(5000)) {
    try { $process.Kill() } catch {}
    throw 'Configured Windows lifecycle hook exceeded its bounded test timeout.'
  }
  $result = [pscustomobject]@{
    ExitCode = $process.ExitCode
    Output = $process.StandardOutput.ReadToEnd()
    Error = $process.StandardError.ReadToEnd()
  }
  $process.Dispose()
  $result
}

function Invoke-SupervisionInTempRoot {
  param([string]$TempRoot, [string]$State = '')
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = 'powershell.exe'
  $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action supervise -SupervisionAction status' -f $wrapper
  if ($State) { $info.Arguments += ' -SupervisionStatePath "{0}"' -f $State }
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.EnvironmentVariables['TEMP'] = $TempRoot
  $info.EnvironmentVariables['TMP'] = $TempRoot
  $process = [Diagnostics.Process]::Start($info)
  if (-not $process.WaitForExit(10000)) {
    try { $process.Kill() } catch {}
    throw 'TEMP-scoped supervision status exceeded its bounded test timeout.'
  }
  $output = $process.StandardOutput.ReadToEnd()
  $errorOutput = $process.StandardError.ReadToEnd()
  $result = [pscustomobject]@{
    ExitCode = $process.ExitCode
    Output = @($output -split "`r?`n" | Where-Object { $_ })
    Text = (($output + $errorOutput).Trim())
  }
  $process.Dispose()
  $result
}

try {
  foreach ($file in @($module, $wrapper)) {
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors) | Out-Null
    if ($errors) { throw ($errors | ForEach-Object ToString | Out-String) }
  }

  $hooks = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
  $eventNames = @($hooks.hooks.PSObject.Properties.Name | Sort-Object)
  Assert-True (($eventNames -join ',') -eq 'SessionEnd,SessionStart,Stop,SubagentStart,SubagentStop') 'Hooks must contain the bounded lifecycle and completed-turn events only.'
  $hookText = Get-Content -Raw -LiteralPath $hooksPath
  foreach ($forbidden in @('PreToolUse', 'PostToolUse', 'UserPromptSubmit', 'PermissionRequest', 'PreCompact', 'PostCompact')) {
    Assert-True (-not $hookText.Contains($forbidden)) "High-frequency or model-steering hook was present: $forbidden"
  }
  Assert-True ($hookText.Contains('-WindowStyle Hidden')) 'Windows hook commands must be headless.'
  Assert-True ($hookText.Contains('%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe')) 'Windows hooks must use the system PowerShell path.'
  $windowsCommands = @(
    $hooks.hooks.PSObject.Properties.Value |
      ForEach-Object { $_[0].hooks[0].commandWindows }
  )
  Assert-True (($windowsCommands | Select-Object -Unique).Count -eq 1) 'Every lifecycle event must use the same audited Windows launcher.'
  $windowsCommand = [string]$windowsCommands[0]
  Assert-True (-not $windowsCommand.Contains('"')) 'Windows hook launcher must remain quote-free for the Codex cmd.exe outer-quote boundary.'
  Assert-True ($windowsCommand -match ' -EncodedCommand ([A-Za-z0-9+/=]+)$') 'Windows hook launcher must move path-sensitive logic into an encoded PowerShell payload.'
  $decodedWindowsPayload = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))
  Assert-True ($decodedWindowsPayload -eq "`$ProgressPreference='SilentlyContinue'; & (Join-Path `$env:PLUGIN_ROOT 'skills\chronos\scripts\session-registry.ps1') -Action hook") 'Windows hook payload did not suppress host noise and resolve the installed plugin path inside PowerShell.'
  Assert-True (([regex]::Matches($hookText, '"async"\s*:\s*true')).Count -eq 4) 'Every non-terminal hook must use supported background execution.'
  Assert-True (([regex]::Matches($hookText, '"timeout"\s*:\s*3')).Count -eq 5) 'Every packaged hook must retain the three-second host ceiling.'
  Assert-True (-not (($hooks.hooks.SessionEnd[0].hooks[0].PSObject.Properties.Name) -contains 'async')) 'SessionEnd must remain explicitly synchronous.'
  Assert-True (-not $hookText.Contains('additionalContext')) 'Lifecycle hooks must not add model context.'
  Assert-True (-not $hookText.Contains('-Diagnostic')) 'Production hook definitions must not expose diagnostic output.'

  $configuredHookTemp = Join-Path $root 'configured hook temp'
  New-Item -ItemType Directory -Path $configuredHookTemp -Force | Out-Null
  $configuredPayload = @{
    session_id = 'thread-configured-windows-hook'
    cwd = $repo
    hook_event_name = 'SessionStart'
    source = 'startup'
    model = 'gpt-5.6-terra'
  } | ConvertTo-Json -Compress
  $configuredHook = Invoke-ConfiguredWindowsHook $windowsCommand (Join-Path $repo 'plugins\chronos') $configuredHookTemp $configuredPayload
  Assert-True ($configuredHook.ExitCode -eq 0 -and -not $configuredHook.Output -and -not $configuredHook.Error) 'Configured Windows hook did not execute silently through the Codex cmd.exe command boundary.'
  $configuredScopeHash = Get-TestHash ('{0}|{1}' -f $env:COMPUTERNAME, ([IO.Path]::GetFullPath((Join-Path $HOME '.codex'))))
  $configuredStatePath = Join-Path $configuredHookTemp (Join-Path 'Chronos\Supervision-v2' (Join-Path $configuredScopeHash 'session-registry.json'))
  Assert-True (Test-Path -LiteralPath $configuredStatePath -PathType Leaf) 'Configured Windows hook reported success without reaching the registry script.'
  $configuredState = Get-Content -Raw -LiteralPath $configuredStatePath | ConvertFrom-Json
  Assert-True ($configuredState.health.hookRuns -eq 1 -and $configuredState.health.lastHookUtc) 'Configured Windows hook did not record fresh lifecycle activity.'

  # A prior fixed TEMP registry that the restarted host cannot read must never
  # block the private v2 namespace or be modified during the transition.
  $upgradeTemp = Join-Path $root 'upgrade temp'
  $priorUpgradeDirectory = Join-Path $upgradeTemp 'Chronos\Supervision'
  $priorUpgradeState = Join-Path $priorUpgradeDirectory 'session-registry.json'
  New-Item -ItemType Directory -Path $priorUpgradeDirectory -Force | Out-Null
  $priorSeed = Invoke-Supervision $priorUpgradeState 'initialize' 'prior-upgrade-seed'
  Assert-True ($priorSeed.ExitCode -eq 0 -and (Test-Path -LiteralPath $priorUpgradeState -PathType Leaf)) 'Could not seed the prior fixed TEMP supervision registry.'
  Remove-Item -LiteralPath (Join-Path $upgradeTemp 'Chronos\Supervision-v2') -Recurse -Force -ErrorAction SilentlyContinue
  $priorWriteTime = (Get-Item -LiteralPath $priorUpgradeState -Force).LastWriteTimeUtc
  $priorAcl = Get-Acl -LiteralPath $priorUpgradeDirectory
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
  $denyRights = [Security.AccessControl.FileSystemRights]::ReadData -bor [Security.AccessControl.FileSystemRights]::WriteData -bor [Security.AccessControl.FileSystemRights]::AppendData
  $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  $denyRule = New-Object Security.AccessControl.FileSystemAccessRule($sid, $denyRights, $inheritance, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Deny)
  $restrictedAcl = Get-Acl -LiteralPath $priorUpgradeDirectory
  [void]$restrictedAcl.AddAccessRule($denyRule)
  Set-Acl -LiteralPath $priorUpgradeDirectory -AclObject $restrictedAcl
  $denyEffective = $false
  try {
    $accessProbe = New-Object IO.FileStream($priorUpgradeState, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $accessProbe.Dispose()
  } catch { $denyEffective = $true }
  try {
    $upgradeStatus = Invoke-SupervisionInTempRoot $upgradeTemp
    Assert-True ($upgradeStatus.ExitCode -eq 0) 'Inaccessible prior supervision state blocked the private v2 registry.'
    $upgradePayload = Get-Payload $upgradeStatus
    $expectedMigration = if ($denyEffective) { 'prior_state_unavailable_new_root' } else { 'prior_state_imported' }
    $expectedDisposition = if ($denyEffective) { 'unavailable_preserved' } else { 'read_only_imported' }
    Assert-True ($upgradePayload.stateStoreMigration -eq $expectedMigration) "Prior supervision handling did not match the host ACL result. Expected $expectedMigration, got $($upgradePayload.stateStoreMigration)."
    Assert-True ($upgradePayload.priorStateDisposition -eq $expectedDisposition -and -not $upgradePayload.priorStateWriteAttempted) 'Prior supervision state was not handled as read-only evidence.'
    Assert-True (-not $upgradePayload.recurrenceEligible) 'State migration alone incorrectly authorized a Governor recurrence.'
  } finally {
    Set-Acl -LiteralPath $priorUpgradeDirectory -AclObject $priorAcl -ErrorAction SilentlyContinue
    Assert-True ((Get-Item -LiteralPath $priorUpgradeState -Force).LastWriteTimeUtc -eq $priorWriteTime) 'Prior supervision state changed during read-only migration.'
    Remove-Item -LiteralPath $upgradeTemp -Recurse -Force -ErrorAction SilentlyContinue
  }
  $governorSkillText = Get-Content -Raw -LiteralPath $governorSkillPath
  foreach ($requiredConvergenceControl in @(
    'chronos-supervision-v1',
    'at most three',
    'creation time ascending',
    'cycles zero and one',
    'zero active duplicates',
    'one machine and state root'
  )) {
    Assert-True ($governorSkillText.Contains($requiredConvergenceControl)) "Governor skill omitted host convergence control: $requiredConvergenceControl"
  }

  $bomState = Join-Path $root 'bom-registry.json'
  $bomStart = Complete-HookProcess (Start-HookProcess $bomState (@{
    session_id = 'thread-bom-probe'
    cwd = $root
    hook_event_name = 'SessionStart'
    source = 'startup'
    model = 'gpt-5.6-luna'
  } | ConvertTo-Json -Compress) '' -Utf8Bom)
  Assert-True ($bomStart.ExitCode -eq 0 -and (Test-Path -LiteralPath $bomState -PathType Leaf)) 'A UTF-8 BOM must not suppress lifecycle registration.'
  $bomStatus = Get-Payload (Invoke-Supervision $bomState)
  Assert-True ($bomStatus.activeTasks -eq 1) 'The BOM-framed lifecycle event was not registered.'

  $state = Join-Path $root 'registry.json'
  $empty = Invoke-Supervision $state
  Assert-True ($empty.ExitCode -eq 0) 'Empty supervision status failed.'
  $emptyData = Get-Payload $empty
  Assert-True ($emptyData.activeTasks -eq 0 -and $emptyData.activeAgents -eq 0 -and -not $emptyData.governorClaimed) 'Empty status was not quiescent.'
  Assert-True ($emptyData.recommendedCadenceMinutes -eq 360 -and $emptyData.maximumModelCallsPerDay -eq 4 -and $emptyData.workerRecurrence -eq 'disabled') 'Idle cadence, cost bound, or worker recurrence regressed.'
  Assert-True ($emptyData.hostEquivalenceKey -match '^chronos-supervision-v1:[a-f0-9]{32}$' -and $emptyData.hostReconcileAttemptLimit -eq 3 -and $emptyData.hostRecheckThroughCycle -eq 2) 'Host convergence identity, retry budget, or bounded recheck regressed.'
  Assert-True ($emptyData.hostPostcondition -eq 'one_live_governor_one_active_recurrence_zero_duplicates' -and $emptyData.localMutexScope -eq 'machine_state_root') 'Host postcondition or local-lock scope regressed.'
  Assert-True ($emptyData.equivalenceScope -eq 'installation' -and $emptyData.installationScopePersistence -eq 'state_root_anchor') 'Installation equivalence scope or persistence boundary regressed.'
  Assert-True ($emptyData.stateStoreMode -eq 'explicit' -and $emptyData.stateStoreWriteReady -and $emptyData.routineUserAction -eq 'none') 'State-store preflight or autonomous routine-failure contract regressed.'
  Assert-True ($emptyData.hookExecutionObservation -eq 'not_observed' -and $emptyData.hookTrustObservation -eq 'host_verification_required' -and $emptyData.registryCoverage -eq 'host_inventory_required') 'Empty hook observability must distinguish no evidence from disabled or trusted hooks.'
  Assert-True ($emptyData.hookRole -eq 'optional_acceleration' -and -not $emptyData.hookRequiredForAutonomy -and $emptyData.taskDiscoveryAuthority -eq 'complete_host_inventory_each_governor_cycle') 'Autonomy incorrectly depended on lifecycle-hook execution.'
  Assert-True ($emptyData.catalogRefreshAction -eq 'fully_restart_codex_then_start_fresh_task' -and $emptyData.loadedTaskCatalogHotSwap -eq 'unsupported_by_host') 'Install refresh guidance did not preserve the host catalog boundary.'
  Assert-True ($emptyData.recommendedGovernorModel -eq 'gpt-5.6-terra' -and $emptyData.recommendedGovernorReasoningEffort -eq 'medium') 'Governor model guidance did not select Terra Medium.'
  $scopePath = Join-Path (Split-Path -Parent $state) 'installation-scope.json'
  Assert-True (Test-Path -LiteralPath $scopePath -PathType Leaf) 'Status did not create a stable installation-scope anchor.'
  $scopeText = Get-Content -Raw -LiteralPath $scopePath
  Assert-True ($scopeText -match '^\{"schema":1,"id":"[a-f0-9]{32}"\}$') 'Installation-scope anchor was not minimal and opaque.'
  $repeatEmptyData = Get-Payload (Invoke-Supervision $state)
  Assert-True ($repeatEmptyData.hostEquivalenceKey -eq $emptyData.hostEquivalenceKey) 'Installation equivalence changed across status calls.'
  $otherStateDirectory = Join-Path $root 'other-installation'
  New-Item -ItemType Directory -Path $otherStateDirectory -Force | Out-Null
  $otherState = Join-Path $otherStateDirectory 'registry.json'
  $otherEmptyData = Get-Payload (Invoke-Supervision $otherState)
  Assert-True ($otherEmptyData.hostEquivalenceKey -ne $emptyData.hostEquivalenceKey) 'Independent installation roots shared a Governor equivalence key.'

  $hostState = Join-Path $root 'host-reconcile-registry.json'
  $hostGovernor = 'thread-host-governor'
  $hostInitialize = Invoke-Supervision $hostState 'initialize' $hostGovernor
  Assert-True ($hostInitialize.ExitCode -eq 0) 'Host reconciliation fixture could not claim its Governor.'
  $hostInitializeData = Get-Payload $hostInitialize
  Assert-True (-not $hostInitializeData.recurrenceEligible -and $hostInitializeData.recurrenceCreationPolicy -eq 'after_successful_complete_host_inventory_cycle') 'Initialization incorrectly authorized a recurrence before a complete host inventory cycle.'
  $hostInventoryPath = Join-Path $root 'host-inventory.json'
  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1
    capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    complete = $true
    tasks = @(
      [ordered]@{ id = $hostGovernor; status = 'running'; generation = 'generation-governor' },
      [ordered]@{ id = 'thread-missed-hook'; status = 'waiting'; generation = 'generation-missed' }
    )
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  $hostReconcile = Invoke-Supervision -State $hostState -Action 'reconcile-host' -Session $hostGovernor -HostInventory $hostInventoryPath
  Assert-True ($hostReconcile.ExitCode -eq 0) "Host inventory reconciliation failed: $($hostReconcile.Text)"
  $hostReconcileData = Get-Payload $hostReconcile
  Assert-True ($hostReconcileData.hostInventoryObserved -eq 2 -and $hostReconcileData.hostTasksAdded -eq 1 -and $hostReconcileData.activeTasks -eq 1) 'Host inventory did not add the task missed by lifecycle hooks.'
  Assert-True ($hostReconcileData.requiredHostAction -eq 'wait_compact_batch_then_evaluate_heartbeat' -and $hostReconcileData.routineUserAction -eq 'none') 'Reconciliation did not return the autonomous next host step.'
  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1
    capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    complete = $true
    tasks = @([ordered]@{ id = $hostGovernor; status = 'running'; generation = 'generation-governor' })
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  $hostClose = Get-Payload (Invoke-Supervision -State $hostState -Action 'reconcile-host' -Session $hostGovernor -HostInventory $hostInventoryPath)
  Assert-True ($hostClose.hostTasksEnded -eq 1 -and $hostClose.activeTasks -eq 0) 'Complete host inventory did not close an absent task.'
  [IO.File]::WriteAllText($hostInventoryPath, '{"schemaVersion":1,"capturedAtUtc":"2000-01-01T00:00:00Z","complete":true,"tasks":[]}', [Text.UTF8Encoding]::new($false))
  $staleInventory = Get-Payload (Invoke-Supervision -State $hostState -Action 'reconcile-host' -Session $hostGovernor -HostInventory $hostInventoryPath)
  Assert-True (-not $staleInventory.ok -and $staleInventory.error -eq 'supervision_host_inventory_invalid') 'Stale host inventory did not fail closed.'

  $cycleState = Join-Path $root 'cycle-registry.json'
  $cycleGovernor = 'thread-cycle-governor'
  [void](Invoke-Supervision $cycleState 'initialize' $cycleGovernor)
  $passiveDiscovery = Get-Payload (Invoke-Supervision $cycleState 'discover' $cycleGovernor)
  Assert-True (-not $passiveDiscovery.cycleAdvanced -and $passiveDiscovery.governorCycleCount -eq 0 -and $passiveDiscovery.requiredHostAction -eq 'run_cycle_with_complete_host_inventory') 'Passive discovery was incorrectly counted as a Governor cycle.'
  $missingCycleInventory = Get-Payload (Invoke-Supervision $cycleState 'cycle' $cycleGovernor)
  Assert-True (-not $missingCycleInventory.ok -and $missingCycleInventory.error -eq 'supervision_host_inventory_required') 'A Governor cycle without host inventory did not fail closed.'
  $governorOmittedInventory = Join-Path $root 'governor-omitted-inventory.json'
  [IO.File]::WriteAllText($governorOmittedInventory, ([ordered]@{
    schemaVersion = 1; capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o'); complete = $true
    tasks = @([ordered]@{ id = 'thread-other-live'; status = 'running'; generation = 'generation-other' })
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  $governorOmitted = Get-Payload (Invoke-Supervision -State $cycleState -Action 'cycle' -Session $cycleGovernor -HostInventory $governorOmittedInventory)
  Assert-True (-not $governorOmitted.ok -and $governorOmitted.error -eq 'supervision_governor_not_in_host_inventory') 'A complete inventory that omitted its Governor advanced the cycle.'
  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1; capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o'); complete = $false
    tasks = @([ordered]@{ id = $cycleGovernor; status = 'running'; generation = 'cycle-governor-generation' })
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  $incompleteCycle = Get-Payload (Invoke-Supervision -State $cycleState -Action 'cycle' -Session $cycleGovernor -HostInventory $hostInventoryPath)
  Assert-True (-not $incompleteCycle.ok -and $incompleteCycle.error -eq 'supervision_host_inventory_incomplete') 'An incomplete host inventory advanced a Governor cycle.'
  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1; capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o'); complete = $true
    tasks = @(
      [ordered]@{ id = $cycleGovernor; status = 'running'; generation = 'cycle-governor-generation' },
      [ordered]@{ id = 'thread-cycle-live'; status = 'waiting'; generation = 'cycle-live-generation' },
      [ordered]@{ id = 'thread-cycle-ended'; status = 'completed'; generation = $null }
    )
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  $cycle = Get-Payload (Invoke-Supervision -State $cycleState -Action 'cycle' -Session $cycleGovernor -HostInventory $hostInventoryPath)
  Assert-True ($cycle.ok -and $cycle.governorCycleCount -eq 1 -and $cycle.hostInventoryCycle -eq 1 -and $cycle.hostInventoryComplete -and $cycle.hostInventoryObserved -eq 3) 'A complete host inventory did not advance exactly one Governor cycle.'
  Assert-True ($cycle.recurrenceEligible -and $cycle.recurrenceCreationPolicy -eq 'after_successful_complete_host_inventory_cycle') 'A verified complete inventory cycle did not authorize the one Governor recurrence.'
  Assert-True (@($cycle.hostTaskStatuses).Count -eq 3 -and @($cycle.hostTaskStatuses | Where-Object status -eq 'live').Count -eq 2 -and @($cycle.hostTaskStatuses | Where-Object status -eq 'ended').Count -eq 1) 'The cycle did not return one normalized status per host task.'
  Assert-True (($cycle.hostTaskStatuses | ConvertTo-Json -Compress) -notmatch 'thread-cycle|cycle-live-generation|cycle-governor-generation') 'Compact host statuses exposed a raw task ID or generation.'
  Assert-True ($cycle.taskWakePolicy -eq 'intervention_claim_required' -and $cycle.routineUserAction -eq 'none') 'A normal cycle did not prohibit unclaimed task wakes.'

  $monotonicState = Join-Path $root 'host-monotonic.json'
  $monotonicGovernor = 'thread-monotonic-governor'
  $monotonicTask = 'thread-monotonic-worker'
  $hookTime = [DateTimeOffset]::UtcNow.AddSeconds(-10)
  [void](Invoke-Hook $monotonicState @{ session_id = $monotonicGovernor; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' } $hookTime.AddSeconds(-10).ToString('o'))
  [void](Invoke-Supervision $monotonicState 'initialize' $monotonicGovernor)
  [void](Invoke-Hook $monotonicState @{ session_id = $monotonicTask; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' } $hookTime.ToString('o'))
  $monotonicHash = Get-TestHash $monotonicTask
  $beforeInventory = (Get-Content -Raw $monotonicState | ConvertFrom-Json).sessions.$monotonicHash
  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1; capturedAtUtc = $hookTime.AddSeconds(-5).ToString('o'); complete = $true
    tasks = @(
      [ordered]@{ id = $monotonicGovernor; status = 'running'; generation = 'governor-generation' },
      [ordered]@{ id = $monotonicTask; status = 'running'; generation = 'generation-one' }
    )
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  [void](Invoke-Supervision -State $monotonicState -Action 'reconcile-host' -Session $monotonicGovernor -HostInventory $hostInventoryPath)
  $afterOlderInventory = (Get-Content -Raw $monotonicState | ConvertFrom-Json).sessions.$monotonicHash
  Assert-True ($afterOlderInventory.lastEventUtc -eq $beforeInventory.lastEventUtc -and $afterOlderInventory.recordRevision -eq $beforeInventory.recordRevision) 'Older host inventory rewound lifecycle time or revision.'

  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1; capturedAtUtc = $hookTime.AddSeconds(1).ToString('o'); complete = $true
    tasks = @(
      [ordered]@{ id = $monotonicGovernor; status = 'running'; generation = 'governor-generation' },
      [ordered]@{ id = $monotonicTask; status = 'running'; generation = 'generation-one' }
    )
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  [void](Invoke-Supervision -State $monotonicState -Action 'reconcile-host' -Session $monotonicGovernor -HostInventory $hostInventoryPath)

  $confirmedMonotonic = Get-Payload (Invoke-Supervision -State $monotonicState -Action 'confirm-active' -Session $monotonicGovernor -Subject $monotonicTask)
  Assert-True ($confirmedMonotonic.state -eq 'active') 'Monotonic fixture could not establish rank-3 activity.'
  $confirmedRecord = (Get-Content -Raw $monotonicState | ConvertFrom-Json).sessions.$monotonicHash
  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1; capturedAtUtc = $confirmedRecord.lastEventUtc; complete = $true
    tasks = @([ordered]@{ id = $monotonicGovernor; status = 'running'; generation = 'governor-generation' })
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  [void](Invoke-Supervision -State $monotonicState -Action 'reconcile-host' -Session $monotonicGovernor -HostInventory $hostInventoryPath)
  $afterEqualRank = (Get-Content -Raw $monotonicState | ConvertFrom-Json).sessions.$monotonicHash
  Assert-True ($afterEqualRank.state -eq 'active' -and $afterEqualRank.recordRevision -eq $confirmedRecord.recordRevision) 'Equal-timestamp rank-2 inventory ending overrode rank-3 activity.'

  [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
    schemaVersion = 1; capturedAtUtc = ([DateTimeOffset]::Parse($confirmedRecord.lastEventUtc).AddSeconds(1).ToString('o')); complete = $true
    tasks = @(
      [ordered]@{ id = $monotonicGovernor; status = 'running'; generation = 'governor-generation' },
      [ordered]@{ id = $monotonicTask; status = 'running'; generation = 'generation-two' }
    )
  } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
  $generationChange = Get-Payload (Invoke-Supervision -State $monotonicState -Action 'reconcile-host' -Session $monotonicGovernor -HostInventory $hostInventoryPath)
  $generationRecord = (Get-Content -Raw $monotonicState | ConvertFrom-Json).sessions.$monotonicHash
  Assert-True ($generationChange.hostTaskGenerationsChanged -eq 1 -and $generationRecord.generationHash -eq (Get-TestHash 'generation-two')) 'A reused task ID did not persist its new host generation.'

  $scopeRaceDirectory = Join-Path $root 'first-scope-race'
  New-Item -ItemType Directory -Path $scopeRaceDirectory -Force | Out-Null
  $scopeRaceProcesses = [Collections.Generic.List[object]]::new()
  for ($index = 1; $index -le 8; $index++) {
    $scopeRaceProcesses.Add((Start-SupervisionStatusProcess (Join-Path $scopeRaceDirectory ("registry-$index.json")))) | Out-Null
  }
  $scopeRaceKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($scopeRaceProcess in $scopeRaceProcesses) {
    $scopeRaceResult = Complete-HookProcess $scopeRaceProcess
    Assert-True ($scopeRaceResult.ExitCode -eq 0 -and -not $scopeRaceResult.Error) 'Concurrent first installation-scope status failed.'
    $scopeRaceLine = @($scopeRaceResult.Output -split "`r?`n" | Where-Object { $_ -like 'CHRONOS SUPERVISION *' } | Select-Object -Last 1)
    Assert-True ($scopeRaceLine.Count -eq 1) 'Concurrent installation-scope status omitted its payload.'
    $scopeRacePayload = $scopeRaceLine[0].Substring('CHRONOS SUPERVISION '.Length) | ConvertFrom-Json
    [void]$scopeRaceKeys.Add([string]$scopeRacePayload.hostEquivalenceKey)
  }
  Assert-True ($scopeRaceKeys.Count -eq 1) 'Concurrent first status calls returned different installation identities.'
  $scopeRaceAnchor = Join-Path $scopeRaceDirectory 'installation-scope.json'
  Assert-True (Test-Path -LiteralPath $scopeRaceAnchor -PathType Leaf) 'Concurrent first status calls did not persist one installation anchor.'
  Assert-True (@(Get-ChildItem -LiteralPath $scopeRaceDirectory -Filter '.supervision-scope-*.tmp' -Force).Count -eq 0) 'Installation-scope race left temporary files.'

  $task = 'thread-test-governor'
  $worker = '/root/read_probe'
  $cwd = Join-Path $root 'private-workspace-name'
  New-Item -ItemType Directory -Path $cwd -Force | Out-Null
  $start = Invoke-Hook $state @{
    session_id = $task
    transcript_path = (Join-Path $cwd 'private-rollout.jsonl')
    cwd = $cwd
    hook_event_name = 'SessionStart'
    source = 'startup'
    model = 'gpt-5.6-sol'
    permission_mode = 'default'
  }
  Assert-True ($start.ExitCode -eq 0 -and -not $start.Output -and -not $start.Error) 'SessionStart must be silent and non-blocking.'
  if (-not (Test-Path -LiteralPath $state -PathType Leaf)) {
    $diagnostic = Complete-HookProcess (Start-HookProcess $state (@{
      session_id = $task
      cwd = $cwd
      hook_event_name = 'SessionStart'
      source = 'startup'
      model = 'gpt-5.6-sol'
    } | ConvertTo-Json -Compress) '' -Diagnostic)
    throw "SessionStart did not create registry state. Diagnostic: $($diagnostic.Output) $($diagnostic.Error)"
  }
  $raw = [IO.File]::ReadAllText($state)
  foreach ($private in @($task, $cwd, 'private-rollout.jsonl')) {
    Assert-True (-not $raw.Contains($private)) "Registry persisted private input: $private"
  }

  $turnSignal = Invoke-Hook $state @{
    session_id = $task
    turn_id = 'turn-private-identifier'
    cwd = $cwd
    hook_event_name = 'Stop'
    model = 'gpt-5.6-sol'
    last_assistant_message = 'private assistant response that must not persist'
  }
  Assert-True ($turnSignal.ExitCode -eq 0 -and -not $turnSignal.Output -and -not $turnSignal.Error) 'Stop activity hook must be silent and non-blocking.'
  $turnStatus = Get-Payload (Invoke-Supervision $state)
  Assert-True ($turnStatus.turnSignals -eq 1 -and $turnStatus.monitoringMode -eq 'complete_host_inventory_plus_optional_hooks' -and $turnStatus.hookModelContext -eq 'none' -and $turnStatus.workerModelTurns -eq 0) 'Completed-turn activity did not update the zero-model-cost monitoring counters.'
  $rawAfterTurn = [IO.File]::ReadAllText($state)
  foreach ($private in @('turn-private-identifier', 'private assistant response that must not persist')) {
    Assert-True (-not $rawAfterTurn.Contains($private)) "Registry persisted private Stop input: $private"
  }
  [void](Invoke-Hook $state @{
    session_id = $task; turn_id = 'turn-private-identifier'; cwd = $cwd;
    hook_event_name = 'Stop'; model = 'gpt-5.6-sol'
  })
  $duplicateTurnStatus = Get-Payload (Invoke-Supervision $state)
  Assert-True ($duplicateTurnStatus.turnSignals -eq 1 -and $duplicateTurnStatus.duplicateSignals -eq 1) 'Duplicate completed-turn signal was not deduplicated.'

  $lateInstallState = Join-Path $root 'late-install-stop.json'
  [void](Invoke-Hook $lateInstallState @{
    session_id = 'thread-discovered-mid-session'; turn_id = 'turn-first-observed';
    cwd = $cwd; hook_event_name = 'Stop'; model = 'gpt-5.6-terra'
  })
  $lateInstallStatus = Get-Payload (Invoke-Supervision $lateInstallState)
  Assert-True ($lateInstallStatus.activeTasks -eq 1 -and $lateInstallStatus.turnSignals -eq 1) 'A task first observed after installation was not self-discovered.'

  $initialize = Invoke-Supervision $state 'initialize' $task
  Assert-True ($initialize.ExitCode -eq 0) "Governor initialization failed: $($initialize.Text)"
  $initializeData = Get-Payload $initialize
  Assert-True ($initializeData.governorClaimed -and $initializeData.currentIsGovernor) 'Current task did not claim Governor.'
  $claimedStatus = Get-Payload (Invoke-Supervision $state)
  Assert-True ($claimedStatus.governorTaskId -eq $task -and $claimedStatus.governorRoleCompatibility -eq 'host_verification_required') 'Status did not expose the exact claimed task for host role verification.'
  $persisted = Get-Content -Raw -LiteralPath $state | ConvertFrom-Json
  $governorRecord = $persisted.sessions.PSObject.Properties[$persisted.governor.idHash].Value
  Assert-True ($governorRecord.model -eq 'gpt-5.6-sol' -and $governorRecord.source -eq 'startup') 'Governor claim overwrote lifecycle metadata.'

  $agentStart = Invoke-Hook $state @{
    session_id = $task
    cwd = $cwd
    hook_event_name = 'SubagentStart'
    agent_id = $worker
    agent_type = 'explorer'
    model = 'gpt-5.6-luna'
  }
  Assert-True ($agentStart.ExitCode -eq 0 -and -not $agentStart.Output) 'SubagentStart must be silent.'
  $discovery = Invoke-Supervision $state 'discover' $task
  Assert-True ($discovery.ExitCode -eq 0) "Governor discovery failed: $($discovery.Text)"
  $discoveryData = Get-Payload $discovery
  Assert-True ($discoveryData.activeTasks -eq 0 -and $discoveryData.activeAgents -eq 1) 'Discovery did not exclude Governor or include active agent.'
  Assert-True ($discoveryData.agents[0].taskId -eq $worker -and $discoveryData.agents[0].model -eq 'gpt-5.6-luna') 'Discovery did not recover the runtime agent identity.'
  Assert-True ($discoveryData.recommendedCadenceMinutes -eq 60 -and $discoveryData.maximumModelCallsPerDay -eq 24 -and $discoveryData.modelCalls -eq 'governor_only') 'Active cadence or model-call ownership regressed.'
  Assert-True ($discoveryData.hostEquivalenceKey -eq $emptyData.hostEquivalenceKey -and $discoveryData.equivalenceScope -eq 'installation' -and $discoveryData.installationScopePersistence -eq 'state_root_anchor' -and $discoveryData.hostReconcileAttemptLimit -eq 3 -and $discoveryData.hostRecheckThroughCycle -eq 2 -and $discoveryData.hostPostcondition -eq 'one_live_governor_one_active_recurrence_zero_duplicates') 'Discovery omitted deterministic host convergence controls.'
  Assert-True ($discoveryData.hookExecutionObservation -eq 'observed' -and $discoveryData.registryCoverage -eq 'lifecycle_hooks_observed' -and $discoveryData.lastHookUtc) 'Observed hooks were not exposed distinctly.'
  Assert-True (@($discoveryData.checkBatch).Count -eq 1 -and $discoveryData.checkBatch[0].taskId -eq $worker) 'Governor check batch did not contain the active worker.'

  $cursor = [long]$discoveryData.revision
  $noChanges = Get-Payload (Invoke-Supervision $state 'discover' $task $cursor)
  Assert-True (@($noChanges.changes).Count -eq 0) 'Revision cursor returned unchanged records.'
  [void](Invoke-Supervision $state 'initialize' $task)
  Assert-True ((Get-Payload (Invoke-Supervision $state)).governorCycleCount -eq 0) 'Passive discovery or idempotent initialize changed the Governor cycle bound.'

  $duplicate = Invoke-Hook $state @{
    session_id = $task; cwd = $cwd; hook_event_name = 'SubagentStart';
    agent_id = $worker; agent_type = 'explorer'; model = 'gpt-5.6-luna'
  }
  Assert-True ($duplicate.ExitCode -eq 0) 'Duplicate lifecycle event failed.'
  $deduped = Get-Payload (Invoke-Supervision $state 'discover' $task)
  Assert-True ($deduped.activeAgents -eq 1) 'Duplicate lifecycle event created another agent.'

  $conflict = Invoke-Supervision $state 'initialize' '019fffff-ffff-7fff-ffff-ffffffffffff'
  Assert-True ($conflict.ExitCode -eq 1 -and (Get-Payload $conflict).error -eq 'supervision_governor_conflict') 'Active Governor conflict did not fail safely.'

  $forceState = Join-Path $root 'force-takeover.json'
  $forceGovernor = 'thread-force-governor'
  $forceReplacement = 'thread-force-replacement'
  [void](Invoke-Hook $forceState @{ session_id = $forceGovernor; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' })
  [void](Invoke-Hook $forceState @{ session_id = $forceReplacement; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' })
  [void](Invoke-Supervision $forceState 'initialize' $forceGovernor)
  $forceFixture = Get-Content -Raw $forceState | ConvertFrom-Json
  $forceGovernorHash = Get-TestHash $forceGovernor
  $forceFixture.sessions.$forceGovernorHash.lastEventUtc = [DateTimeOffset]::UtcNow.AddMinutes(2).ToString('o')
  [IO.File]::WriteAllText($forceState, ($forceFixture | ConvertTo-Json -Compress -Depth 12), [Text.UTF8Encoding]::new($false))
  $forcedConflict = Invoke-Supervision -State $forceState -Action 'initialize' -Session $forceReplacement -Force
  Assert-True ($forcedConflict.ExitCode -eq 1 -and (Get-Payload $forcedConflict).error -eq 'supervision_event_order_conflict') 'Forced takeover replaced a Governor whose terminal transition was rejected.'
  Assert-True ((Get-Payload (Invoke-Supervision $forceState)).governorTaskId -eq $forceGovernor) 'Failed forced takeover changed Governor ownership.'

  $beforeMalformed = (Get-Content -Raw -LiteralPath $state | ConvertFrom-Json).revision
  $malformed = Complete-HookProcess (Start-HookProcess $state '{bad')
  Assert-True ($malformed.ExitCode -eq 0 -and -not $malformed.Output -and -not $malformed.Error) 'Malformed hook input must fail silent.'
  Assert-True ((Get-Content -Raw -LiteralPath $state | ConvertFrom-Json).revision -eq $beforeMalformed) 'Malformed hook input changed state.'
  foreach ($ambiguous in @(
    '{"hook_event_name":"SessionStart","hook_event_name":"SessionEnd","session_id":"duplicate","cwd":"C:/safe"}',
    '{"hook_event_name":"SessionStart","SESSION_ID":"first","session_id":"second","cwd":"C:/safe"}'
  )) {
    $ambiguousResult = Complete-HookProcess (Start-HookProcess $state $ambiguous)
    Assert-True ($ambiguousResult.ExitCode -eq 0 -and -not $ambiguousResult.Output -and -not $ambiguousResult.Error) 'Ambiguous hook JSON must fail silent.'
    Assert-True ((Get-Content -Raw -LiteralPath $state | ConvertFrom-Json).revision -eq $beforeMalformed) 'Ambiguous hook JSON changed state.'
  }
  $oversizedJson = '{"hook_event_name":"SessionStart","session_id":"large","cwd":"' + ('x' * 70000) + '"}'
  $oversized = Complete-HookProcess (Start-HookProcess $state $oversizedJson)
  Assert-True ($oversized.ExitCode -eq 0 -and -not $oversized.Output -and -not $oversized.Error) 'Oversized hook input must fail silent.'

  $stop = Invoke-Hook $state @{
    session_id = $task; cwd = $cwd; hook_event_name = 'SubagentStop';
    agent_id = $worker; agent_type = 'explorer'; model = 'gpt-5.6-luna'
  }
  Assert-True ($stop.ExitCode -eq 0) 'SubagentStop failed.'
  Assert-True ((Get-Payload (Invoke-Supervision $state 'discover' $task)).activeAgents -eq 0) 'Stopped agent remained active.'

  $end = Invoke-Hook $state @{
    session_id = $task; cwd = $cwd; hook_event_name = 'SessionEnd'; reason = 'other'; model = 'gpt-5.6-sol'
  }
  Assert-True ($end.ExitCode -eq 0 -and -not $end.Output -and -not $end.Error) 'SessionEnd must be silent and non-blocking.'
  $endedStatus = Get-Payload (Invoke-Supervision $state)
  Assert-True ($endedStatus.governorClaimed -and $endedStatus.activeAgents -eq 0) 'SessionEnd must retain the Governor claim until host recurrence cleanup succeeds.'
  $releasePlan = Get-Payload (Invoke-Supervision $state 'release' $task)
  Assert-True (-not $releasePlan.releaseReady -and $releasePlan.governorClaimed) 'Release cleared ownership before host recurrence cleanup.'
  Assert-True ((Get-Payload (Invoke-Supervision $state 'status')).governorClaimed) 'Release plan mutated Governor state.'
  $releaseDone = Get-Payload (Invoke-Supervision -State $state -Action 'release' -Session $task -ConfirmRecurrenceStopped)
  Assert-True (-not $releaseDone.governorClaimed) 'Confirmed release did not clear Governor ownership.'

  $orderingState = Join-Path $root 'ordering.json'
  $orderingGovernor = 'thread-ordering-governor'
  $orderingTask = 'thread-ordering-worker'
  $orderingAgent = '/root/ordering_probe'
  $t0 = [DateTimeOffset]::Parse('2026-08-11T12:00:00Z').ToString('o')
  $t1 = [DateTimeOffset]::Parse('2026-08-11T12:00:01Z').ToString('o')
  $t2 = [DateTimeOffset]::Parse('2026-08-11T12:00:02Z').ToString('o')
  [void](Invoke-Hook $orderingState @{ session_id = $orderingGovernor; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-luna' } $t0)
  [void](Invoke-Supervision $orderingState 'initialize' $orderingGovernor)
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' } $t0)
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SubagentStart'; agent_id = $orderingAgent; model = 'gpt-5.6-luna' } $t0)
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SubagentStop'; agent_id = $orderingAgent; model = 'gpt-5.6-luna' } $t2)
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SessionEnd'; reason = 'other'; model = 'gpt-5.6-terra' } $t2)
  $terminalRevision = [long](Get-Content -Raw -LiteralPath $orderingState | ConvertFrom-Json).revision
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SubagentStart'; agent_id = $orderingAgent; model = 'gpt-5.6-luna' } $t1)
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' } $t1)
  $ordered = Get-Payload (Invoke-Supervision $orderingState 'discover' $orderingGovernor)
  Assert-True ($ordered.activeTasks -eq 0 -and $ordered.activeAgents -eq 0) 'Delayed start events revived terminal work.'
  Assert-True ([long](Get-Content -Raw -LiteralPath $orderingState | ConvertFrom-Json).revision -eq $terminalRevision) 'A stale start advanced the lifecycle revision.'
  Assert-True ($ordered.ignoredStaleEvents -ge 2) 'Ignored stale lifecycle events were not observable.'
  $confirmed = Get-Payload (Invoke-Supervision -State $orderingState -Action 'confirm-active' -Session $orderingGovernor -Subject $orderingTask)
  Assert-True ($confirmed.state -eq 'active') 'Host-confirmed task reactivation failed.'
  Assert-True ((Get-Payload (Invoke-Supervision $orderingState 'discover' $orderingGovernor)).activeTasks -eq 1) 'Confirmed active task was not discoverable.'
  $newerAgent = '/root/newer_ordering_probe'
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SubagentStart'; agent_id = $newerAgent; model = 'gpt-5.6-luna' })
  [void](Invoke-Hook $orderingState @{ session_id = $orderingTask; cwd = $cwd; hook_event_name = 'SessionEnd'; reason = 'other'; model = 'gpt-5.6-terra' } $t1)
  $staleCascade = Get-Payload (Invoke-Supervision $orderingState 'discover' $orderingGovernor)
  Assert-True ($staleCascade.activeTasks -eq 1 -and $staleCascade.activeAgents -eq 1) 'Rejected stale SessionEnd cascaded into newer child state.'

  $terminalFirstState = Join-Path $root 'terminal-first.json'
  $terminalFirstGovernor = 'thread-terminal-first-governor'
  $terminalFirstTask = 'thread-terminal-first-task'
  $terminalFirstAgent = '/root/terminal_first_agent'
  $parentEndedAgent = '/root/parent_ended_agent'
  [void](Invoke-Hook $terminalFirstState @{ session_id = $terminalFirstGovernor; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' } $t0)
  [void](Invoke-Supervision $terminalFirstState 'initialize' $terminalFirstGovernor)
  [void](Invoke-Hook $terminalFirstState @{ session_id = $terminalFirstTask; cwd = $cwd; hook_event_name = 'SessionEnd'; reason = 'other'; model = 'gpt-5.6-sol' } $t1)
  [void](Invoke-Hook $terminalFirstState @{ session_id = $terminalFirstTask; cwd = $cwd; hook_event_name = 'SubagentStop'; agent_id = $terminalFirstAgent; model = 'gpt-5.6-luna' } $t1)
  $terminalFirstRevision = [long](Get-Content -Raw -LiteralPath $terminalFirstState | ConvertFrom-Json).revision
  [void](Invoke-Hook $terminalFirstState @{ session_id = $terminalFirstTask; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-sol' } $t2)
  [void](Invoke-Hook $terminalFirstState @{ session_id = $terminalFirstTask; cwd = $cwd; hook_event_name = 'SubagentStart'; agent_id = $terminalFirstAgent; model = 'gpt-5.6-luna' } $t2)
  $afterDelayedStarts = Get-Payload (Invoke-Supervision $terminalFirstState 'discover' $terminalFirstGovernor)
  Assert-True ($afterDelayedStarts.activeTasks -eq 0 -and $afterDelayedStarts.activeAgents -eq 0) 'Terminal-first tombstones allowed delayed start handlers to revive finished work.'
  Assert-True ([long](Get-Content -Raw -LiteralPath $terminalFirstState | ConvertFrom-Json).revision -eq $terminalFirstRevision) 'Delayed starts changed terminal-first tombstones.'
  [void](Invoke-Hook $terminalFirstState @{ session_id = $terminalFirstTask; cwd = $cwd; hook_event_name = 'SubagentStart'; agent_id = $parentEndedAgent; model = 'gpt-5.6-luna' } $t2)
  $parentEndedState = Get-Content -Raw -LiteralPath $terminalFirstState | ConvertFrom-Json
  $terminalFirstTaskHash = Get-TestHash $terminalFirstTask
  $terminalFirstAgentHash = Get-TestHash $terminalFirstAgent
  $parentEndedAgentHash = Get-TestHash $parentEndedAgent
  Assert-True ($parentEndedState.sessions.$terminalFirstTaskHash.state -eq 'ended' -and $parentEndedState.sessions.$terminalFirstAgentHash.state -eq 'ended' -and $parentEndedState.sessions.$parentEndedAgentHash.state -eq 'ended') 'Terminal-first or parent-ended lifecycle records were not retained as ended tombstones.'
  Assert-True ((Get-Payload (Invoke-Supervision $terminalFirstState 'discover' $terminalFirstGovernor)).activeAgents -eq 0) 'A subagent start after its parent ended became active.'

  $asyncInversionState = Join-Path $root 'async-inversion.json'
  $asyncInversionGovernor = 'thread-async-inversion-governor'
  $asyncInversionAgent = '/root/async_inversion_agent'
  [void](Invoke-Hook $asyncInversionState @{ session_id = $asyncInversionGovernor; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-luna' } $t0)
  [void](Invoke-Supervision $asyncInversionState 'initialize' $asyncInversionGovernor)
  $asyncStop = Complete-HookProcess (Start-HookProcess $asyncInversionState ((@{ session_id = $asyncInversionGovernor; cwd = $cwd; hook_event_name = 'SubagentStop'; agent_id = $asyncInversionAgent; model = 'gpt-5.6-luna' } | ConvertTo-Json -Compress)) $t2)
  $asyncStart = Complete-HookProcess (Start-HookProcess $asyncInversionState ((@{ session_id = $asyncInversionGovernor; cwd = $cwd; hook_event_name = 'SubagentStart'; agent_id = $asyncInversionAgent; model = 'gpt-5.6-luna' } | ConvertTo-Json -Compress)) $t1)
  Assert-True ($asyncStop.ExitCode -eq 0 -and $asyncStart.ExitCode -eq 0 -and -not $asyncStop.Output -and -not $asyncStop.Error -and -not $asyncStart.Output -and -not $asyncStart.Error) 'Separate asynchronous terminal-first hook processes were noisy or failed.'
  $asyncInversion = Get-Payload (Invoke-Supervision $asyncInversionState 'discover' $asyncInversionGovernor)
  Assert-True ($asyncInversion.activeAgents -eq 0 -and @($asyncInversion.checkBatch | Where-Object taskId -eq $asyncInversionAgent).Count -eq 0) 'Completion-inverted asynchronous hooks left a stopped agent active or queued.'
  Assert-True ($asyncInversion.ignoredStaleEvents -ge 1 -and $asyncInversion.recommendedCadenceMinutes -eq 360 -and $asyncInversion.maximumModelCallsPerDay -eq 4) 'Completion inversion did not preserve stale ordering and idle Governor cadence.'

  $fairState = Join-Path $root 'fairness.json'
  $fairGovernor = 'thread-fair-governor'
  [void](Invoke-Hook $fairState @{ session_id = $fairGovernor; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-luna' })
  [void](Invoke-Supervision $fairState 'initialize' $fairGovernor)
  $expectedFairIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  for ($index = 1; $index -le 17; $index++) {
    $fairId = 'thread-fair-{0:d2}' -f $index
    [void]$expectedFairIds.Add($fairId)
    [void](Invoke-Hook $fairState @{ session_id = $fairId; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' })
  }
  $seenFairIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  for ($cycle = 0; $cycle -lt 3; $cycle++) {
    $fairTasks = [Collections.Generic.List[object]]::new()
    $fairTasks.Add([ordered]@{ id = $fairGovernor; status = 'running'; generation = 'fair-governor-generation' }) | Out-Null
    foreach ($fairId in @($expectedFairIds)) {
      $fairTasks.Add([ordered]@{ id = $fairId; status = 'running'; generation = 'fair-task-generation' }) | Out-Null
    }
    [IO.File]::WriteAllText($hostInventoryPath, ([ordered]@{
      schemaVersion = 1; capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o'); complete = $true; tasks = @($fairTasks)
    } | ConvertTo-Json -Compress -Depth 4), [Text.UTF8Encoding]::new($false))
    $fair = Get-Payload (Invoke-Supervision -State $fairState -Action 'cycle' -Session $fairGovernor -HostInventory $hostInventoryPath)
    Assert-True (@($fair.checkBatch).Count -le 8) 'Governor check batch exceeded the bounded size.'
    foreach ($entry in @($fair.checkBatch)) { [void]$seenFairIds.Add([string]$entry.taskId) }
  }
  Assert-True ($seenFairIds.Count -eq 17) 'Rotating batches did not cover all 17 active tasks in three cycles.'

  $capacityState = Join-Path $root 'capacity.json'
  Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
  $entropy = [Text.Encoding]::UTF8.GetBytes('Chronos.Supervision.Registry.v1')
  $sha = [Security.Cryptography.SHA256]::Create()
  $capacitySessions = [ordered]@{}
  $capacityNow = [DateTimeOffset]::UtcNow.ToString('o')
  $capacityWorkspace = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('capacity-workspace')))).Replace('-', '').ToLowerInvariant()
  for ($index = 1; $index -le 256; $index++) {
    $id = 'thread-capacity-{0:d3}' -f $index
    $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($id)))).Replace('-', '').ToLowerInvariant()
    $cipher = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($id), $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $capacitySessions[$hash] = [ordered]@{
      idHash = $hash; protectedId = [Convert]::ToBase64String($cipher); kind = 'task'; parentHash = $null
      workspaceHash = $capacityWorkspace; model = 'gpt-5.6-terra'; state = 'active'; source = 'startup'
      generationHash = $null
      firstSeenUtc = $capacityNow; lastSeenUtc = $capacityNow; endedAtUtc = $null
      lastEventUtc = $capacityNow; lastEventRank = 1; recordRevision = [long]$index
    }
  }
  $sha.Dispose()
  $capacityFixture = [ordered]@{
    schema = 3; revision = 256L; governor = $null; sessions = $capacitySessions
    health = [ordered]@{ hookRuns = 256L; droppedEntries = 0L; ignoredStaleEvents = 0L; scanOffset = 0L; lastHookUtc = $capacityNow }
  }
  [IO.File]::WriteAllText($capacityState, ($capacityFixture | ConvertTo-Json -Compress -Depth 10), [Text.UTF8Encoding]::new($false))
  [void](Invoke-Hook $capacityState @{ session_id = 'thread-capacity-overflow'; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' })
  $capacity = Get-Payload (Invoke-Supervision $capacityState)
  Assert-True ($capacity.engine -eq 'degraded' -and $capacity.registryCapacity -eq 'exhausted' -and $capacity.retainedRecords -eq 256 -and $capacity.droppedEntries -eq 1) ('Registry saturation was silent or evicted retained active work. ' + ($capacity | ConvertTo-Json -Compress -Depth 4))

  $corrupt = Join-Path $root 'corrupt.json'
  [IO.File]::WriteAllText($corrupt, '{bad', [Text.UTF8Encoding]::new($false))
  $corruptResult = Invoke-Supervision $corrupt
  Assert-True ($corruptResult.ExitCode -eq 1 -and (Get-Payload $corruptResult).error -eq 'supervision_state_invalid') 'Corrupt state did not fail safely.'
  Assert-True ([IO.File]::ReadAllText($corrupt) -eq '{bad') 'Corrupt state was overwritten.'
  $badScopeDirectory = Join-Path $root 'bad-installation-scope'
  New-Item -ItemType Directory -Path $badScopeDirectory -Force | Out-Null
  $badScopeState = Join-Path $badScopeDirectory 'registry.json'
  $badScopePath = Join-Path $badScopeDirectory 'installation-scope.json'
  [IO.File]::WriteAllText($badScopePath, '{"schema":1,"id":"not-an-opaque-id"}', [Text.UTF8Encoding]::new($false))
  $badScopeResult = Invoke-Supervision $badScopeState
  Assert-True ($badScopeResult.ExitCode -eq 1 -and (Get-Payload $badScopeResult).error -eq 'supervision_install_scope_invalid') 'Malformed installation scope produced healthy status.'
  Assert-True ([IO.File]::ReadAllText($badScopePath) -eq '{"schema":1,"id":"not-an-opaque-id"}') 'Malformed installation scope was overwritten.'
  $duplicateState = Join-Path $root 'duplicate-state.json'
  $duplicateStateText = '{"schema":2,"schema":2,"revision":0,"governor":null,"sessions":{},"health":{"hookRuns":0,"droppedEntries":0,"ignoredStaleEvents":0,"scanOffset":0,"lastHookUtc":null}}'
  [IO.File]::WriteAllText($duplicateState, $duplicateStateText, [Text.UTF8Encoding]::new($false))
  $duplicateStateResult = Invoke-Supervision $duplicateState
  Assert-True ($duplicateStateResult.ExitCode -eq 1 -and (Get-Payload $duplicateStateResult).error -eq 'supervision_state_invalid') 'Duplicate state keys were accepted.'
  Assert-True ([IO.File]::ReadAllText($duplicateState) -eq $duplicateStateText) 'Ambiguous state was overwritten.'
  foreach ($badTypedStateText in @(
    '{"schema":"2","revision":0,"governor":null,"sessions":{},"health":{"hookRuns":0,"droppedEntries":0,"ignoredStaleEvents":0,"scanOffset":0,"lastHookUtc":null}}',
    '{"schema":2,"revision":0.5,"governor":null,"sessions":{},"health":{"hookRuns":0,"droppedEntries":0,"ignoredStaleEvents":0,"scanOffset":0,"lastHookUtc":null}}',
    '{"schema":2,"revision":0,"governor":null,"sessions":{},"health":{"hookRuns":"0","droppedEntries":0,"ignoredStaleEvents":0,"scanOffset":0,"lastHookUtc":null}}'
  )) {
    $badTypedState = Join-Path $root ('typed-state-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($badTypedState, $badTypedStateText, [Text.UTF8Encoding]::new($false))
    $badTypedResult = Invoke-Supervision $badTypedState
    Assert-True ($badTypedResult.ExitCode -eq 1 -and (Get-Payload $badTypedResult).error -eq 'supervision_state_invalid') 'Wrongly typed state was accepted.'
  }
  $cryptoState = Join-Path $root 'crypto-state.json'
  Assert-True ((Invoke-Supervision $cryptoState 'initialize' $task).ExitCode -eq 0) 'Could not create protected-ID fixture.'
  $cryptoObject = Get-Content -Raw -LiteralPath $cryptoState | ConvertFrom-Json
  $cryptoObject.governor.protectedId = [Convert]::ToBase64String((New-Object byte[] 64))
  [IO.File]::WriteAllText($cryptoState, ($cryptoObject | ConvertTo-Json -Compress -Depth 10), [Text.UTF8Encoding]::new($false))
  $cryptoResult = Invoke-Supervision $cryptoState
  Assert-True ($cryptoResult.ExitCode -eq 1 -and (Get-Payload $cryptoResult).error -eq 'supervision_state_invalid') 'Unreadable protected ID produced a healthy status.'

  $outside = Join-Path $repo 'supervision-state-must-not-write.json'
  $outsideResult = Invoke-Supervision $outside
  Assert-True ($outsideResult.ExitCode -eq 1 -and (Get-Payload $outsideResult).error -eq 'supervision_state_path_invalid') 'Outside state path was accepted.'
  Assert-True (-not (Test-Path -LiteralPath $outside)) 'Outside state file was created.'

  $outsideTemp = Join-Path ([IO.Path]::GetTempPath()) ('chronos-supervision-outside-' + [guid]::NewGuid().ToString('N') + '.json')
  $outsideTempFull = [IO.Path]::GetFullPath($outsideTemp)
  $approvedTempFull = [IO.Path]::GetFullPath($approvedTempRoot).TrimEnd('\')
  Assert-True (-not $outsideTempFull.StartsWith($approvedTempFull + '\', [StringComparison]::OrdinalIgnoreCase)) 'Outside-temp fixture unexpectedly entered the private Chronos state root.'
  $outsideTempResult = Invoke-Supervision $outsideTemp
  Assert-True ($outsideTempResult.ExitCode -eq 1 -and (Get-Payload $outsideTempResult).error -eq 'supervision_state_path_invalid') 'State path elsewhere under TEMP was accepted.'
  Assert-True (-not (Test-Path -LiteralPath $outsideTemp)) 'Rejected TEMP state file was created.'

  $raceState = Join-Path $root 'race.json'
  $race = [Collections.Generic.List[object]]::new()
  for ($index = 1; $index -le 8; $index++) {
    $race.Add((Start-HookProcess $raceState (@{
      session_id = ('thread-race-{0:d2}' -f $index)
      cwd = $cwd
      hook_event_name = 'SessionStart'
      source = 'startup'
      model = 'gpt-5.6-terra'
    } | ConvertTo-Json -Compress))) | Out-Null
  }
  foreach ($invocation in $race) {
    $result = Complete-HookProcess $invocation
    Assert-True ($result.ExitCode -eq 0 -and -not $result.Output -and -not $result.Error) 'Concurrent hook was not silent.'
  }
  $raceStatus = Get-Payload (Invoke-Supervision $raceState)
  Assert-True ($raceStatus.engine -eq 'healthy' -and $raceStatus.activeTasks -eq 8 -and $raceStatus.retainedRecords -eq 8) "Concurrent lifecycle writes were lost or corrupted: $($raceStatus | ConvertTo-Json -Compress -Depth 8)"

  $mutexState = Join-Path $root 'mutex-deadline.json'
  [void](Invoke-Hook $mutexState @{ session_id = 'thread-mutex'; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' })
  $mutexStateBefore = [IO.File]::ReadAllText($mutexState)
  $mutexSha = [Security.Cryptography.SHA256]::Create()
  try {
    $mutexHash = ([BitConverter]::ToString($mutexSha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($mutexState).ToUpperInvariant())))).Replace('-', '').ToLowerInvariant()
  } finally { $mutexSha.Dispose() }
  $heldMutex = New-Object Threading.Mutex($false, ('Global\ChronosSupervision-' + $mutexHash.Substring(0, 24)))
  try {
    Assert-True ($heldMutex.WaitOne(1000)) 'Test could not acquire the live registry mutex.'
    $pendingDirectory = $mutexState + '.pending'
    New-Item -ItemType Directory -Path $pendingDirectory -Force | Out-Null
    foreach ($slot in 0..255) {
      $staleReservation = Join-Path $pendingDirectory ('pending-slot-{0:d3}.lock' -f $slot)
      [IO.File]::WriteAllText($staleReservation, '', [Text.UTF8Encoding]::new($false))
      (Get-Item -LiteralPath $staleReservation).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-10)
    }
    $contendedEnd = Invoke-Hook $mutexState @{ session_id = 'thread-mutex'; cwd = $cwd; hook_event_name = 'SessionEnd'; reason = 'other'; model = 'gpt-5.6-terra' }
    Assert-True ($contendedEnd.ExitCode -eq 0 -and -not $contendedEnd.Output -and -not $contendedEnd.Error) 'Contended SessionEnd did not fail silent.'
    Assert-True ([IO.File]::ReadAllText($mutexState) -eq $mutexStateBefore) 'Contended SessionEnd changed the locked registry state.'
  } finally {
    try { $heldMutex.ReleaseMutex() | Out-Null } catch {}
    $heldMutex.Dispose()
  }
  $pendingFiles = @(Get-ChildItem -LiteralPath $pendingDirectory -File -Force)
  $pendingJson = @($pendingFiles | Where-Object { $_.Extension -eq '.json' })
  $pendingLocks = @($pendingFiles | Where-Object { $_.Extension -eq '.lock' })
  Assert-True ($pendingJson.Count -eq 1 -and $pendingLocks.Count -eq 0) 'Contended SessionEnd was not preserved by one atomic slot or stale reservations were retained.'
  $pendingText = Get-Content -Raw -LiteralPath $pendingJson[0].FullName
  Assert-True ($pendingText -notmatch 'thread-mutex|[A-Za-z]:\\') 'Fallback queue persisted a raw task ID or workspace path.'
  $legacyPending = $pendingText | ConvertFrom-Json
  $legacyPending.schema = 1
  $legacyPending.PSObject.Properties.Remove('signalHash')
  [IO.File]::WriteAllText($pendingJson[0].FullName, ($legacyPending | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
  $reconciledMutexStatus = Get-Payload (Invoke-Supervision $mutexState)
  Assert-True ($reconciledMutexStatus.activeTasks -eq 0 -and $reconciledMutexStatus.hookRuns -eq 2) 'Governor status did not merge the legacy contended SessionEnd.'
  Assert-True (@(Get-ChildItem -LiteralPath $pendingDirectory -File -Force).Count -eq 0) 'Merged fallback queue entries were not removed.'

  $sourceText = Get-Content -Raw -LiteralPath $module
  Assert-True ($sourceText.Contains("Join-Path `$tempRoot 'Chronos\Supervision'")) 'Default supervision state must use the private TEMP Chronos namespace.'
  Assert-True ($sourceText.Contains("Join-Path `$localRoot 'session-registry.json'")) 'LocalAppData must remain available only as the legacy supervision migration source.'
  Assert-True ($sourceText.Contains('$script:SynchronousHookMutexWaitMilliseconds = 250')) 'Synchronous hook mutex deadline is not fixed at 250 ms.'
  Assert-True ($sourceText.Contains('$script:AsynchronousHookMutexWaitMilliseconds = 100')) 'Asynchronous hook mutex deadline is not fixed at 100 ms.'
  Assert-True (-not $sourceText.Contains("@('Global', 'Local')")) 'A shared registry must not silently fall back from the Global mutex namespace.'
  foreach ($forbidden in @('Register-ScheduledTask', 'New-ScheduledTask', 'Start-Job', 'Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod', 'HttpClient', 'WebClient')) {
    Assert-True (-not $sourceText.Contains($forbidden)) "Supervision module contains a prohibited host or network primitive: $forbidden"
  }

  'Chronos supervision deterministic validations passed.'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
