param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$module = Join-Path $repo 'plugins\chronos\skills\chronos\scripts\session-registry.ps1'
$wrapper = Join-Path $repo 'plugins\chronos\skills\chronos\scripts\chronos.ps1'
$hooksPath = Join-Path $repo 'plugins\chronos\hooks\hooks.json'
$governorSkillPath = Join-Path $repo 'plugins\chronos\skills\chronos-governor\SKILL.md'
$root = Join-Path ([IO.Path]::GetTempPath()) ('chronos-supervision-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
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
  [pscustomobject]@{ Process = $process; State = $State }
}

function Complete-HookProcess {
  param($Invocation, [int]$TimeoutMilliseconds = 10000)
  if (-not $Invocation.Process.WaitForExit($TimeoutMilliseconds)) {
    try { $Invocation.Process.Kill() } catch {}
    throw 'Lifecycle hook exceeded its bounded test timeout.'
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

try {
  foreach ($file in @($module, $wrapper)) {
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors) | Out-Null
    if ($errors) { throw ($errors | ForEach-Object ToString | Out-String) }
  }

  $hooks = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
  $eventNames = @($hooks.hooks.PSObject.Properties.Name | Sort-Object)
  Assert-True (($eventNames -join ',') -eq 'SessionEnd,SessionStart,SubagentStart,SubagentStop') 'Hooks must contain lifecycle events only.'
  $hookText = Get-Content -Raw -LiteralPath $hooksPath
  foreach ($forbidden in @('PreToolUse', 'PostToolUse', 'UserPromptSubmit', 'PermissionRequest')) {
    Assert-True (-not $hookText.Contains($forbidden)) "Per-turn or turn-ending hook was present: $forbidden"
  }
  Assert-True ($hookText.Contains('-WindowStyle Hidden')) 'Windows hook commands must be headless.'
  Assert-True ($hookText.Contains('%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe')) 'Windows hooks must use the system PowerShell path.'
  Assert-True ($hookText.Contains('"async": true')) 'Non-ending lifecycle hooks must be asynchronous.'
  Assert-True (-not $hookText.Contains('additionalContext')) 'Lifecycle hooks must not add model context.'
  Assert-True (-not $hookText.Contains('-Diagnostic')) 'Production hook definitions must not expose diagnostic output.'
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
  Assert-True ($emptyData.hostEquivalenceKey -eq 'chronos-supervision-v1' -and $emptyData.hostReconcileAttemptLimit -eq 3 -and $emptyData.hostRecheckThroughCycle -eq 2) 'Host convergence identity, retry budget, or bounded recheck regressed.'
  Assert-True ($emptyData.hostPostcondition -eq 'one_live_governor_one_active_recurrence_zero_duplicates' -and $emptyData.localMutexScope -eq 'machine_state_root') 'Host postcondition or local-lock scope regressed.'

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
  Assert-True ($discoveryData.hostEquivalenceKey -eq 'chronos-supervision-v1' -and $discoveryData.hostReconcileAttemptLimit -eq 3 -and $discoveryData.hostRecheckThroughCycle -eq 2 -and $discoveryData.hostPostcondition -eq 'one_live_governor_one_active_recurrence_zero_duplicates') 'Discovery omitted deterministic host convergence controls.'
  Assert-True (@($discoveryData.checkBatch).Count -eq 1 -and $discoveryData.checkBatch[0].taskId -eq $worker) 'Governor check batch did not contain the active worker.'

  $cursor = [long]$discoveryData.revision
  $noChanges = Get-Payload (Invoke-Supervision $state 'discover' $task $cursor)
  Assert-True (@($noChanges.changes).Count -eq 0) 'Revision cursor returned unchanged records.'
  [void](Invoke-Supervision $state 'initialize' $task)
  Assert-True ((Get-Payload (Invoke-Supervision $state)).governorCycleCount -eq 2) 'Idempotent initialize reset the Governor cycle bound.'

  $duplicate = Invoke-Hook $state @{
    session_id = $task; cwd = $cwd; hook_event_name = 'SubagentStart';
    agent_id = $worker; agent_type = 'explorer'; model = 'gpt-5.6-luna'
  }
  Assert-True ($duplicate.ExitCode -eq 0) 'Duplicate lifecycle event failed.'
  $deduped = Get-Payload (Invoke-Supervision $state 'discover' $task)
  Assert-True ($deduped.activeAgents -eq 1) 'Duplicate lifecycle event created another agent.'

  $conflict = Invoke-Supervision $state 'initialize' '019fffff-ffff-7fff-ffff-ffffffffffff'
  Assert-True ($conflict.ExitCode -eq 1 -and (Get-Payload $conflict).error -eq 'supervision_governor_conflict') 'Active Governor conflict did not fail safely.'

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
    $fair = Get-Payload (Invoke-Supervision $fairState 'discover' $fairGovernor)
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
      firstSeenUtc = $capacityNow; lastSeenUtc = $capacityNow; endedAtUtc = $null
      lastEventUtc = $capacityNow; lastEventRank = 1; recordRevision = [long]$index
    }
  }
  $sha.Dispose()
  $capacityFixture = [ordered]@{
    schema = 2; revision = 256L; governor = $null; sessions = $capacitySessions
    health = [ordered]@{ hookRuns = 256L; droppedEntries = 0L; ignoredStaleEvents = 0L; scanOffset = 0L; lastHookUtc = $capacityNow }
  }
  [IO.File]::WriteAllText($capacityState, ($capacityFixture | ConvertTo-Json -Compress -Depth 10), [Text.UTF8Encoding]::new($false))
  [void](Invoke-Hook $capacityState @{ session_id = 'thread-capacity-overflow'; cwd = $cwd; hook_event_name = 'SessionStart'; source = 'startup'; model = 'gpt-5.6-terra' })
  $capacity = Get-Payload (Invoke-Supervision $capacityState)
  Assert-True ($capacity.engine -eq 'degraded' -and $capacity.registryCapacity -eq 'exhausted' -and $capacity.retainedRecords -eq 256 -and $capacity.droppedEntries -eq 1) 'Registry saturation was silent or evicted retained active work.'

  $corrupt = Join-Path $root 'corrupt.json'
  [IO.File]::WriteAllText($corrupt, '{bad', [Text.UTF8Encoding]::new($false))
  $corruptResult = Invoke-Supervision $corrupt
  Assert-True ($corruptResult.ExitCode -eq 1 -and (Get-Payload $corruptResult).error -eq 'supervision_state_invalid') 'Corrupt state did not fail safely.'
  Assert-True ([IO.File]::ReadAllText($corrupt) -eq '{bad') 'Corrupt state was overwritten.'
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
  Assert-True ($raceStatus.engine -eq 'healthy' -and $raceStatus.activeTasks -eq 8 -and $raceStatus.retainedRecords -eq 8) 'Concurrent lifecycle writes were lost or corrupted.'

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
    $deadlineWatch = [Diagnostics.Stopwatch]::StartNew()
    $contendedEnd = Invoke-Hook $mutexState @{ session_id = 'thread-mutex'; cwd = $cwd; hook_event_name = 'SessionEnd'; reason = 'other'; model = 'gpt-5.6-terra' }
    $deadlineWatch.Stop()
    Assert-True ($contendedEnd.ExitCode -eq 0 -and -not $contendedEnd.Output -and -not $contendedEnd.Error) 'Contended SessionEnd did not fail silent.'
    Assert-True ($deadlineWatch.ElapsedMilliseconds -lt 2800) 'Contended SessionEnd exceeded the three-second host hook ceiling.'
    Assert-True ([IO.File]::ReadAllText($mutexState) -eq $mutexStateBefore) 'Contended SessionEnd changed registry state.'
  } finally {
    try { $heldMutex.ReleaseMutex() | Out-Null } catch {}
    $heldMutex.Dispose()
  }

  $sourceText = Get-Content -Raw -LiteralPath $module
  Assert-True ($sourceText.Contains('SpecialFolder]::LocalApplicationData')) 'Default supervision state must use LocalAppData, not volatile temp storage.'
  Assert-True ($sourceText.Contains('$script:SynchronousHookMutexWaitMilliseconds = 250')) 'Synchronous hook mutex deadline is not fixed at 250 ms.'
  Assert-True ($sourceText.Contains("@('Global', 'Local')")) 'Registry mutex must fall back to the same-user Local namespace when Global is unavailable.'
  foreach ($forbidden in @('Register-ScheduledTask', 'New-ScheduledTask', 'Start-Job', 'Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod', 'HttpClient', 'WebClient')) {
    Assert-True (-not $sourceText.Contains($forbidden)) "Supervision module contains a prohibited host or network primitive: $forbidden"
  }

  'Chronos supervision deterministic validations passed.'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
