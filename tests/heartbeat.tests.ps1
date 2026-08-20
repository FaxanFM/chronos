param([string]$PluginRoot = '')

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PluginRoot)) { $PluginRoot = Join-Path $repo 'plugins\chronos' }
$PluginRoot = [IO.Path]::GetFullPath($PluginRoot)
$wrapper = Join-Path $PluginRoot 'skills\chronos\scripts\chronos.ps1'
$module = Join-Path $PluginRoot 'skills\chronos\scripts\heartbeat.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' ('tests-' + [guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $root | Out-Null

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    $stack = @(Get-PSCallStack | Select-Object -Skip 1 | ForEach-Object { $_.FunctionName + ':' + $_.ScriptLineNumber }) -join ' > '
    throw ($Message + ' Stack: ' + $stack)
  }
}

function Assert-Equal {
  param($Actual, $Expected, [string]$Message)
  if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Start-HiddenPowerShell {
  param([string]$EncodedCommand)
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = 'powershell.exe'
  $info.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + $EncodedCommand
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $info
  if (-not $process.Start()) {
    $process.Dispose()
    throw 'Could not start the bounded Heartbeat test helper.'
  }
  return $process
}

function Get-TestStableHash {
  param($Value)
  $json = $Value | ConvertTo-Json -Compress -Depth 16
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function New-Case {
  param([string]$Name)
  $path = Join-Path $root $Name
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return [pscustomobject]@{
    Name = $Name
    Path = $path
    State = Join-Path $path 'heartbeat-state.json'
    Sequence = 0
    BaseTime = [DateTimeOffset]::UtcNow.AddHours(-2)
  }
}

function Get-DefaultCoverage {
  param($Data)
  $coverage = @{}
  if ($Data.ContainsKey('agents')) { $coverage.agent_stall = 'observed' }
  if ($Data.ContainsKey('guardian')) { $coverage.guardian = 'observed' }
  if ($Data.ContainsKey('usage')) { $coverage.usage = 'observed' }
  if ($Data.ContainsKey('sessions')) { $coverage.sessions = 'observed' }
  if ($Data.ContainsKey('tests')) { $coverage.tests = 'observed' }
  if ($Data.ContainsKey('machines')) { $coverage.machines = 'observed' }
  if ($Data.ContainsKey('tasks')) { $coverage.tasks = 'observed' }
  if ($Data.ContainsKey('git') -or $Data.ContainsKey('build')) { $coverage.git_build = 'observed' }
  if ($Data.ContainsKey('heartbeatActivity')) { $coverage.heartbeat = 'observed' }
  return $coverage
}

function Invoke-Heartbeat {
  param(
    $Case,
    [hashtable]$Data,
    [Nullable[DateTimeOffset]]$At,
    [switch]$NoForce,
    [switch]$NoAcknowledge,
    [string]$InputPath,
    [string]$StatePath
  )
  $Case.Sequence++
  if (-not $Data.ContainsKey('schemaVersion')) { $Data.schemaVersion = 1 }
  if (-not $Data.ContainsKey('capturedAtUtc')) {
    $time = if ($PSBoundParameters.ContainsKey('At')) { [DateTimeOffset]$At } else { $Case.BaseTime.AddSeconds(301 * $Case.Sequence) }
    $Data.capturedAtUtc = $time.ToString('o')
  }
  if (-not $Data.ContainsKey('runId')) { $Data.runId = 'run-' + $Case.Name + '-' + $Case.Sequence }
  if (-not $Data.ContainsKey('sourceEpoch')) { $Data.sourceEpoch = 'epoch-' + $Case.Name }
  if (-not $Data.ContainsKey('sourceSequence')) { $Data.sourceSequence = $Case.Sequence }
  if (-not $Data.ContainsKey('origin')) { $Data.origin = 'test' }
  if (-not $Data.ContainsKey('collectorCoverage')) { $Data.collectorCoverage = Get-DefaultCoverage $Data }
  if (-not $Data.ContainsKey('forceCadence')) { $Data.forceCadence = -not $NoForce.IsPresent }
  if (-not $InputPath) { $InputPath = Join-Path $Case.Path ('input-' + $Case.Sequence + '.json') }
  if (-not $StatePath) { $StatePath = $Case.State }
  [IO.File]::WriteAllText($InputPath, ($Data | ConvertTo-Json -Depth 14), [Text.UTF8Encoding]::new($false))
  $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -Action heartbeat -HeartbeatInputPath $InputPath -HeartbeatStatePath $StatePath 2>&1)
  $exitCode = $LASTEXITCODE
  $text = $output -join "`n"
  if (-not $NoAcknowledge -and $exitCode -eq 0 -and $text.StartsWith('CHRONOS HEARTBEATS ')) {
    try {
      $payload = $text.Substring('CHRONOS HEARTBEATS '.Length) | ConvertFrom-Json
      $eventIds = @($payload.events | ForEach-Object { [string]$_.EventId } | Where-Object { $_ })
      if ($eventIds.Count -gt 0) {
        $persisted = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
        $persisted.outbox = @($persisted.outbox | Where-Object { $eventIds -notcontains [string]$_.eventId })
        $persisted.revision = [int64]$persisted.revision + 1
        [IO.File]::WriteAllText($StatePath, ($persisted | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
      }
    } catch { throw }
  }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output); Text = $text; InputPath = $InputPath; StatePath = $StatePath }
}

function Invoke-RawModule {
  param([string[]]$Arguments)
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $module @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
  } finally { $ErrorActionPreference = $previousPreference }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output); Text = ($output -join "`n") }
}

function Invoke-Intervention {
  param(
    $Case,
    [string]$Action,
    [string]$EventId,
    [string]$CorroboratingEventId,
    [string]$InterventionId,
    [int]$Version = 0,
    [string]$Target = 'worker-target',
    [string]$Generation = 'generation-1',
    [string]$Governor = 'governor-task',
    [string]$ClaimToken,
    [string]$TransportResult,
    [string]$TaskResponse,
    [string]$VerificationSource,
    [string]$VerificationResult,
    [string]$FailureReason
  )
  $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $wrapper, '-Action', 'heartbeat', '-HeartbeatStatePath', $Case.State, '-HeartbeatInterventionAction', $Action)
  if ($EventId) { $arguments += @('-HeartbeatEventId', $EventId) }
  if ($CorroboratingEventId) { $arguments += @('-HeartbeatCorroboratingEventId', $CorroboratingEventId) }
  if ($InterventionId) { $arguments += @('-HeartbeatInterventionId', $InterventionId) }
  if ($Version -gt 0) { $arguments += @('-HeartbeatInterventionVersion', [string]$Version) }
  if ($Target) { $arguments += @('-HeartbeatTargetId', $Target) }
  if ($Generation) { $arguments += @('-HeartbeatTargetGeneration', $Generation) }
  if ($Governor) { $arguments += @('-HeartbeatGovernorId', $Governor) }
  if ($ClaimToken) { $arguments += @('-HeartbeatClaimToken', $ClaimToken) }
  if ($TransportResult) { $arguments += @('-HeartbeatTransportResult', $TransportResult) }
  if ($TaskResponse) { $arguments += @('-HeartbeatTaskResponse', $TaskResponse) }
  if ($VerificationSource) { $arguments += @('-HeartbeatVerificationSource', $VerificationSource) }
  if ($VerificationResult) { $arguments += @('-HeartbeatVerificationResult', $VerificationResult) }
  if ($FailureReason) { $arguments += @('-HeartbeatFailureReason', $FailureReason) }
  $output = @(& powershell.exe @arguments 2>&1)
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output); Text = ($output -join "`n") }
}

function Get-InterventionPayload {
  param($Result)
  Assert-True ($Result.ExitCode -eq 0) ("Intervention exit code. Output: $($Result.Text)")
  $prefix = if ($Result.Text.StartsWith('CHRONOS INTERVENTION ')) { 'CHRONOS INTERVENTION ' } elseif ($Result.Text.StartsWith('CHRONOS INTERVENTIONS ')) { 'CHRONOS INTERVENTIONS ' } else { '' }
  Assert-True (-not [string]::IsNullOrWhiteSpace($prefix)) ("Missing intervention envelope: $($Result.Text)")
  return ($Result.Text.Substring($prefix.Length) | ConvertFrom-Json)
}

function Assert-Silent {
  param($Result, [string]$Message)
  Assert-Equal $Result.ExitCode 0 ($Message + ' exit code.')
  Assert-True ([string]::IsNullOrWhiteSpace($Result.Text)) ($Message + " Expected no output, got: $($Result.Text)")
}

function Assert-FailedSafely {
  param($Result, [string]$Code, [string]$Message)
  Assert-True ($Result.ExitCode -ne 0) ($Message + ' Expected a nonzero exit code.')
  Assert-True ($Result.Text -match [regex]::Escape($Code)) ($Message + " Expected $Code, got: $($Result.Text)")
  Assert-True ($Result.Text -notmatch [regex]::Escape($root)) ($Message + ' Error output exposed a local path.')
}

function Get-Payload {
  param($Result)
  Assert-True ($Result.ExitCode -eq 0) ("Heartbeat event exit code. Output: $($Result.Text)")
  Assert-True ($Result.Text.StartsWith('CHRONOS HEARTBEATS ')) ("Missing Heartbeat envelope: $($Result.Text)")
  return ($Result.Text.Substring('CHRONOS HEARTBEATS '.Length) | ConvertFrom-Json)
}

function Get-Events {
  param($Result)
  $payload = Get-Payload $Result
  return @($payload.events)
}

function Assert-Event {
  param($Result, [string]$Type, [string]$Route)
  $events = @(Get-Events $Result)
  $match = @($events | Where-Object { $_.Type -eq $Type -and $_.Event -eq 'HEARTBEAT_EVENT' })
  Assert-True ($match.Count -ge 1) ("Expected $Type, got: $($Result.Text)")
  if ($Route) { Assert-Equal $match[0].OwningSolThread $Route ("$Type route.") }
  return $match[0]
}

function Assert-Resolution {
  param($Result, [string]$Type, [string]$Route)
  $events = @(Get-Events $Result)
  $match = @($events | Where-Object { $_.Type -eq $Type -and $_.Event -eq 'HEARTBEAT_RESOLVED' })
  Assert-True ($match.Count -eq 1) ("Expected one $Type resolution, got: $($Result.Text)")
  if ($Route) { Assert-Equal $match[0].OwningSolThread $Route ("$Type resolution route.") }
}

function Get-TestHash {
  param($Value)
  $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Compress -Depth 8))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

if (-not ('ChronosHeartbeatTestPathIdentity' -as [type])) {
  Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class ChronosHeartbeatTestPathIdentity {
  private const uint FILE_SHARE_READ = 1;
  private const uint FILE_SHARE_WRITE = 2;
  private const uint FILE_SHARE_DELETE = 4;
  private const uint OPEN_EXISTING = 3;
  private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern SafeFileHandle CreateFile(
    string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
    uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern uint GetFinalPathNameByHandle(
    SafeFileHandle handle, StringBuilder path, uint length, uint flags);

  public static string FinalDirectoryPath(string path) {
    using (SafeFileHandle handle = CreateFile(path, 0,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      StringBuilder buffer = new StringBuilder(32768);
      uint length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
      if (length == 0 || length >= buffer.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      return buffer.ToString();
    }
  }
}
'@
}

function Get-TestCanonicalStateIdentity {
  param([string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  $directory = Split-Path -Parent $full
  $canonicalDirectory = [ChronosHeartbeatTestPathIdentity]::FinalDirectoryPath($directory)
  return ([IO.Path]::Combine($canonicalDirectory, (Split-Path -Leaf $full))).Replace('/', '\').TrimEnd('\').ToUpperInvariant()
}

try {
  $parseErrors = $null
  [void][Management.Automation.Language.Parser]::ParseFile($module, [ref]$null, [ref]$parseErrors)
  Assert-Equal @($parseErrors).Count 0 'Heartbeat module must parse on Windows PowerShell.'
  $heartbeatSource = Get-Content -Raw -LiteralPath $module
  Assert-True ($heartbeatSource -notmatch 'GetCurrentDirectory') 'Default Heartbeat identity must not vary with the Governor working directory.'
  $governorSkill = Get-Content -Raw -LiteralPath (Join-Path $PluginRoot 'skills\chronos-governor\SKILL.md')
  $compactGovernorSkill = $governorSkill -replace '\s+', ' '
  foreach ($required in @(
    'send_message_to_thread',
    'Plan all events before claiming one',
    'one active intervention per target',
    'Never retry `unknown`',
    'report is not proof that recovery occurred',
    'It can never target the Governor',
    'Do not broadcast, choose an arbitrary target, or manufacture a user action'
  )) {
    Assert-True ($compactGovernorSkill.Contains($required)) "Governor autonomy contract omitted: $required"
  }

  # Agent stall: baseline, transition, dedupe, escalation, coverage, resolution, and canonical worker IDs.
  $case = New-Case 'agent'
  Assert-Silent (Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-a'; totalTokens = 1000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }) 'Normal agent progress.'
  $warning = Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-a'; totalTokens = 31000; tokensSinceMeaningfulChange = 30000; repeatedEquivalentActions = 4; minutesSinceMeaningfulChange = 25 }) }
  $warningEvent = Assert-Event $warning 'AGENT_STALL' 'governor'
  Assert-True (@($warningEvent).Count -eq 1) ("Agent event helper returned multiple values: $((@($warningEvent) | ForEach-Object { if ($null -eq $_) { '<null>' } else { $_.GetType().FullName + ':' + [string]$_ } }) -join '|')")
  Assert-Equal $warningEvent.Owner '/root/dev' ("Agent owner must remain a Governor triage hint. Envelope: $($warning.Text)")
  Assert-Equal $warningEvent.Severity 'WARNING' 'Initial stall severity.'
  Assert-Silent (Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-a'; totalTokens = 32000; tokensSinceMeaningfulChange = 30000; repeatedEquivalentActions = 4; minutesSinceMeaningfulChange = 26 }) }) 'Unchanged stall dedupe.'
  $escalated = Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-a'; totalTokens = 160000; tokensSinceMeaningfulChange = 140000; repeatedEquivalentActions = 10; minutesSinceMeaningfulChange = 45 }) }
  $escalatedEvent = Assert-Event $escalated 'AGENT_STALL' 'governor'
  Assert-Equal $escalatedEvent.Severity 'HIGH' 'Material stall escalation.'
  Assert-Silent (Invoke-Heartbeat $case @{ collectorCoverage = @{ agent_stall = 'partial' }; agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-b'; totalTokens = 161000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }) 'Partial coverage must not resolve.'
  Assert-Resolution (Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-b'; totalTokens = 161000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }) 'AGENT_STALL' 'governor'
  Assert-Silent (Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-c'; totalTokens = 162000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }) 'Resolved stall stays quiet.'
  $agentStateText = Get-Content -Raw -LiteralPath $case.State
  Assert-True ($agentStateText -notmatch '/root/worker|/root/dev|progress-a|progress-b') 'Persistent state exposed agent or route identifiers.'

  # Missing entities, source restarts, and counter rollback cannot manufacture recovery.
  $continuity = New-Case 'continuity'
  Assert-Silent (Invoke-Heartbeat $continuity @{ agents = @(@{ id = 'continuity-agent'; active = $true; progressHash = 'a'; totalTokens = 1000 }) }) 'Continuity baseline.'
  Assert-Event (Invoke-Heartbeat $continuity @{ agents = @(@{ id = 'continuity-agent'; active = $true; progressHash = 'a'; totalTokens = 41000; tokensSinceMeaningfulChange = 40000; repeatedEquivalentActions = 4; minutesSinceMeaningfulChange = 25 }) }) 'AGENT_STALL' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $continuity @{ agents = @() }) 'Missing entity must not resolve an open condition.'
  Assert-True ((Invoke-RawModule @('-Action', 'status', '-StatePath', $continuity.State)).Text -match 'open=1') 'Missing entity closed the condition.'
  Assert-Silent (Invoke-Heartbeat $continuity @{ sourceEpoch = 'replacement-epoch'; agents = @(@{ id = 'continuity-agent'; active = $true; progressHash = 'b'; totalTokens = 1000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }) 'New source epoch must rebaseline without resolving.'
  Assert-True ((Invoke-RawModule @('-Action', 'status', '-StatePath', $continuity.State)).Text -match 'open=1') 'Source replacement closed the condition.'
  Assert-Silent (Invoke-Heartbeat $continuity @{ sourceEpoch = 'replacement-epoch'; agents = @(@{ id = 'continuity-agent'; active = $true; progressHash = 'b'; totalTokens = 2000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }) 'Replacement epoch continuity cannot resolve the original epoch.'
  Assert-True ((Invoke-RawModule @('-Action', 'status', '-StatePath', $continuity.State)).Text -match 'open=1') 'Replacement epoch eventually closed an older condition.'

  $counterReset = New-Case 'counter-reset'
  Assert-Silent (Invoke-Heartbeat $counterReset @{ guardian = @{ reviewerSessionId = 'reset-reviewer'; reviewCount = 10; reviewsPerHour = 2; reviewerUsageRatio = .2; equivalentApprovalRequests = 0; approvalExecutionCount = 2 } }) 'Counter baseline.'
  Assert-Event (Invoke-Heartbeat $counterReset @{ guardian = @{ reviewerSessionId = 'reset-reviewer'; reviewCount = 30; reviewsPerHour = 20; reviewerUsageRatio = .9; equivalentApprovalRequests = 8; approvalExecutionCount = 2 } }) 'GUARDIAN_RUNAWAY' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $counterReset @{ guardian = @{ reviewerSessionId = 'reset-reviewer'; reviewCount = 1; reviewsPerHour = 1; reviewerUsageRatio = .1; equivalentApprovalRequests = 0; approvalExecutionCount = 0 } }) 'Counter rollback must not resolve.'
  Assert-True ((Invoke-RawModule @('-Action', 'status', '-StatePath', $counterReset.State)).Text -match 'open=1') 'Counter rollback closed the condition.'
  Assert-Resolution (Invoke-Heartbeat $counterReset @{ guardian = @{ reviewerSessionId = 'reset-reviewer'; reviewCount = 2; reviewsPerHour = 1; reviewerUsageRatio = .1; equivalentApprovalRequests = 0; approvalExecutionCount = 1 } }) 'GUARDIAN_RUNAWAY' 'governor'

  # Cadence skip cannot close an open condition.
  $cadence = New-Case 'cadence'
  $t0 = $cadence.BaseTime
  Assert-Silent (Invoke-Heartbeat $cadence @{ agents = @(@{ id = 'cadence-agent'; active = $true; progressHash = 'a'; totalTokens = 1 }) } -At $t0) 'Cadence baseline.'
  $t1 = $t0.AddMinutes(10)
  Assert-Event (Invoke-Heartbeat $cadence @{ agents = @(@{ id = 'cadence-agent'; active = $true; progressHash = 'a'; totalTokens = 40000; tokensSinceMeaningfulChange = 40000; repeatedEquivalentActions = 4; minutesSinceMeaningfulChange = 25 }) } -At $t1) 'AGENT_STALL' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $cadence @{ agents = @(@{ id = 'cadence-agent'; active = $true; progressHash = 'b'; totalTokens = 41000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) } -At ($t1.AddSeconds(10)) -NoForce) 'Not-due family must remain silent.'
  $status = Invoke-RawModule @('-Action', 'status', '-StatePath', $cadence.State)
  Assert-True ($status.Text -match 'open=1') 'Cadence skip incorrectly resolved the condition.'
  Assert-True ($status.Text -match 'completedCycles=3 stateChanges=\d+ acknowledgedEvents=0 failedCycles=0 duplicateRuns=0') 'Compact status omitted autonomous Governor progress counters.'
  Assert-Resolution (Invoke-Heartbeat $cadence @{ agents = @(@{ id = 'cadence-agent'; active = $true; progressHash = 'b'; totalTokens = 41000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) } -At ($t1.AddMinutes(6)) -NoForce) 'AGENT_STALL' 'governor'

  # Compact status owns the Governor progress counters; no hidden host ledger is required.
  $counterStatus = New-Case 'counter-status'
  $counterRun = @{ runId = 'counter-run'; agents = @() }
  Assert-Silent (Invoke-Heartbeat $counterStatus $counterRun.Clone()) 'Counter baseline.'
  Assert-Silent (Invoke-Heartbeat $counterStatus $counterRun.Clone()) 'Duplicate counter run.'
  $failedCounterRun = Invoke-Heartbeat $counterStatus @{ runId = 'counter-failure'; sourceSequence = 1; agents = @() }
  Assert-FailedSafely $failedCounterRun 'heartbeat_source_out_of_order' 'Failed-cycle counter input.'
  $counterStatusResult = Invoke-RawModule @('-Action', 'status', '-StatePath', $counterStatus.State)
  Assert-True ($counterStatusResult.Text -match 'completedCycles=1 stateChanges=3 acknowledgedEvents=0 failedCycles=1 duplicateRuns=1') 'Compact status counters did not survive success, duplicate, and failed cycles.'

  # Guardian runaway uses deltas and approval postconditions.
  $guardian = New-Case 'guardian'
  Assert-Silent (Invoke-Heartbeat $guardian @{ guardian = @{ reviewerSessionId = 'reviewer-1'; reviewCount = 2; reviewsPerHour = 2; reviewerUsageRatio = .2; equivalentApprovalRequests = 0; approvalExecutionCount = 2; progressHash = 'review-a' } }) 'Normal Guardian activity.'
  $guardianEvent = Assert-Event (Invoke-Heartbeat $guardian @{ guardian = @{ reviewerSessionId = 'reviewer-1'; reviewCount = 22; reviewsPerHour = 18; reviewerUsageRatio = .9; equivalentApprovalRequests = 7; approvalExecutionCount = 2; progressHash = 'review-a' } }) 'GUARDIAN_RUNAWAY' 'governor'
  Assert-True (($guardianEvent.Evidence -join ' ') -match 'equivalentApprovalDelta=7') 'Guardian evidence omitted the retry delta.'
  Assert-Silent (Invoke-Heartbeat $guardian @{ guardian = @{ reviewerSessionId = 'reviewer-1'; reviewCount = 22; reviewsPerHour = 18; reviewerUsageRatio = .9; equivalentApprovalRequests = 7; approvalExecutionCount = 2; progressHash = 'review-a' } }) 'Guardian dedupe.'
  Assert-Resolution (Invoke-Heartbeat $guardian @{ guardian = @{ reviewerSessionId = 'reviewer-1'; reviewCount = 23; reviewsPerHour = 1; reviewerUsageRatio = .2; equivalentApprovalRequests = 7; approvalExecutionCount = 3; progressHash = 'review-b' } }) 'GUARDIAN_RUNAWAY' 'governor'
  $postcondition = New-Case 'guardian-postcondition'
  $postconditionEvent = Assert-Event (Invoke-Heartbeat $postcondition @{ guardian = @{ reviewerSessionId = 'reviewer-2'; reviewCount = 1; reviewsPerHour = 1; reviewerUsageRatio = .1; equivalentApprovalRequests = 1; approvalExecutionCount = 0; allowedPendingPostconditionCount = 1 } }) 'GUARDIAN_RUNAWAY' 'governor'
  Assert-Equal $postconditionEvent.Severity 'HIGH' 'Allowed-and-pending postcondition severity.'

  # Usage burn: Governor progress uses supervision counters, not repository edits.
  $usage = New-Case 'usage'
  Assert-Silent (Invoke-Heartbeat $usage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'thread-usage'; totalTokens = 100000; ratePerMinute = 12000; baselineRatePerMinute = 5000; meaningfulProgress = $true; progressHash = 'usage-a'; reviewerShare = .2; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 0 } }) 'High Governor usage with progress.'
  Assert-Silent (Invoke-Heartbeat $usage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'thread-usage'; totalTokens = 200000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'usage-a'; reviewerShare = .91; projectedExhaustionMinutes = 30; completedCycles = 2; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 0 } }) 'A completed Governor supervision cycle is meaningful progress.'
  $usageEvent = Assert-Event (Invoke-Heartbeat $usage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'thread-usage'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'usage-a'; reviewerShare = .91; projectedExhaustionMinutes = 30; completedCycles = 2; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 1 } }) 'USAGE_BURN' 'governor'
  Assert-True (($usageEvent.Evidence -join ' ') -match 'reviewerShare=0.91') 'Usage evidence did not identify reviewer share.'
  Assert-Equal $usageEvent.GovernorLocalAction 'throttle_recurrence_to_idle_cadence' 'Governor burn did not return its bounded local action.'
  Assert-True ($usageEvent.GovernorCadenceMinutes -eq 360 -and $usageEvent.RequiredHostAction -eq 'update_governor_recurrence_and_verify' -and -not $usageEvent.UserActionRequired) 'Governor burn attempted to make routine throttling a user task.'
  $usageResolutionCycle = Invoke-Heartbeat $usage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'thread-usage'; totalTokens = 310000; ratePerMinute = 5000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'usage-a'; reviewerShare = .2; completedCycles = 3; stateChanges = 1; acknowledgedEvents = 1; failedCycles = 0; duplicateRuns = 1 } }
  Assert-Resolution $usageResolutionCycle 'USAGE_BURN' 'governor'
  $usageResolved = @((Get-Events $usageResolutionCycle) | Where-Object { $_.Type -eq 'USAGE_BURN' -and $_.Event -eq 'HEARTBEAT_RESOLVED' })[0]
  Assert-Equal $usageResolved.GovernorLocalAction 'restore_supervision_recommended_cadence' 'Resolved Governor burn did not restore normal cadence policy.'
  $usageUnsupported = New-Case 'usage-governor-unsupported'
  Assert-Silent (Invoke-Heartbeat $usageUnsupported @{ usage = @{ owner = 'governor'; dominantThread = 'thread-usage-unsupported'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'unchanged'; reviewerShare = .91; projectedExhaustionMinutes = 30 } }) 'Governor burn without supervision progress counters must remain unsupported.'

  # Session explosion requires fork and overlap evidence.
  $sessions = New-Case 'sessions'
  Assert-Silent (Invoke-Heartbeat $sessions @{ sessions = @(@{ id = 'parent-1'; childCount = 2; forkDepth = 1; contextOverlap = .2; rolloutBytes = 1000; recursive = $false }) }) 'Normal session lineage.'
  Assert-Event (Invoke-Heartbeat $sessions @{ sessions = @(@{ id = 'parent-1'; childCount = 10; forkDepth = 4; contextOverlap = .88; rolloutBytes = 2000000; recursive = $true }) }) 'SESSION_EXPLOSION' 'governor' | Out-Null

  # Tests compare against persisted known-good state, not a caller-supplied previousStatus.
  $knownFailing = New-Case 'known-failing'
  Assert-Silent (Invoke-Heartbeat $knownFailing @{ tests = @(@{ name = 'known failing test'; status = 'failed'; commit = 'aaaaaaaa'; repairAttempts = 0; failureCount = 1 }) }) 'Known failing baseline.'
  Assert-Silent (Invoke-Heartbeat $knownFailing @{ tests = @(@{ name = 'known failing test'; status = 'failed'; commit = 'aaaaaaaa'; repairAttempts = 0; failureCount = 1 }) }) 'Unchanged known failure.'
  $tests = New-Case 'tests'
  Assert-Silent (Invoke-Heartbeat $tests @{ tests = @(@{ name = 'release test'; owner = '/root/dev'; owningSolThread = '/root/dev'; status = 'passed'; commit = 'aaaaaaaa'; repairAttempts = 0; failureCount = 0 }) }) 'Known-good test baseline.'
  Assert-Event (Invoke-Heartbeat $tests @{ tests = @(@{ name = 'release test'; owner = '/root/dev'; owningSolThread = '/root/dev'; status = 'failed'; commit = 'bbbbbbbb'; repairAttempts = 1; failureCount = 1 }) }) 'TEST_REGRESSION' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $tests @{ tests = @(@{ name = 'release test'; owner = '/root/dev'; owningSolThread = '/root/dev'; status = 'failed'; commit = 'bbbbbbbb'; repairAttempts = 1; failureCount = 1 }) }) 'Same test regression dedupe.'
  Assert-Event (Invoke-Heartbeat $tests @{ tests = @(@{ name = 'release test'; owner = '/root/dev'; owningSolThread = '/root/dev'; status = 'failed'; commit = 'bbbbbbbb'; repairAttempts = 4; failureCount = 5 }) }) 'TEST_REGRESSION' 'governor' | Out-Null
  $testDrift = New-Case 'test-drift'
  Assert-Event (Invoke-Heartbeat $testDrift @{ tests = @(@{ name = 'installer parity'; status = 'failed'; environmentStatuses = @{ 'installer-1' = 'failed'; 'installer-2' = 'passed' } }) }) 'TEST_ENVIRONMENT_DRIFT' 'governor' | Out-Null
  Assert-Event (Invoke-Heartbeat (New-Case 'test-missing') @{ tests = @(@{ name = 'required release test'; status = 'not_run'; required = $true; ran = $false }) }) 'TEST_VALIDATION_MISSING' 'governor' | Out-Null

  # Machine drift handles intended identity, fleet identity, installer routing, and resolution.
  $machines = New-Case 'machines'
  Assert-Silent (Invoke-Heartbeat $machines @{ machines = @(@{ id = 'install-1'; role = 'installer'; owner = 'installer-1'; version = '0.8.0'; pluginVersion = '0.8.0'; manifestVersion = '0.8.0'; commit = 'aaaaaaaa'; intendedVersion = '0.8.0'; intendedCommit = 'aaaaaaaa'; installStatus = 'installed'; testStatus = 'passed' }) }) 'Matching machine identity.'
  Assert-Event (Invoke-Heartbeat $machines @{ machines = @(@{ id = 'install-1'; role = 'installer'; owner = 'installer-1'; version = '0.7.7'; pluginVersion = '0.7.7'; manifestVersion = '0.7.7'; commit = 'bbbbbbbb'; intendedVersion = '0.8.0'; intendedCommit = 'aaaaaaaa'; installStatus = 'stale'; testStatus = 'passed' }) }) 'MACHINE_DRIFT' 'governor' | Out-Null
  Assert-Resolution (Invoke-Heartbeat $machines @{ machines = @(@{ id = 'install-1'; role = 'installer'; owner = 'installer-1'; version = '0.8.0'; pluginVersion = '0.8.0'; manifestVersion = '0.8.0'; commit = 'aaaaaaaa'; intendedVersion = '0.8.0'; intendedCommit = 'aaaaaaaa'; installStatus = 'installed'; testStatus = 'passed' }) }) 'MACHINE_DRIFT' 'governor'
  $fleet = New-Case 'fleet'
  Assert-Event (Invoke-Heartbeat $fleet @{ machines = @(@{ id = 'dev'; role = 'development'; owner = 'development'; version = '0.8.0'; commit = 'aaaaaaaa' }, @{ id = 'canary'; role = 'canary'; owner = 'installer-2'; version = '0.7.7'; commit = 'bbbbbbbb' }) }) 'MACHINE_DRIFT' 'governor' | Out-Null

  # Dependency transitions and zombie/handoff states.
  $tasks = New-Case 'tasks'
  Assert-Silent (Invoke-Heartbeat $tasks @{ tasks = @(@{ id = 'task-b'; owner = '/root/task-b'; owningSolThread = '/root/task-b'; status = 'waiting'; dependsOn = 'task-a'; dependencyStatus = 'active'; assigned = $true }) }) 'Incomplete dependency.'
  Assert-Event (Invoke-Heartbeat $tasks @{ tasks = @(@{ id = 'task-b'; owner = '/root/task-b'; owningSolThread = '/root/task-b'; status = 'waiting'; dependsOn = 'task-a'; dependencyStatus = 'completed'; assigned = $true }) }) 'TASK_ACTIONABLE' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $tasks @{ tasks = @(@{ id = 'task-b'; owner = '/root/task-b'; owningSolThread = '/root/task-b'; status = 'waiting'; dependsOn = 'task-a'; dependencyStatus = 'completed'; assigned = $true }) }) 'Actionable task dedupe.'
  Assert-Event (Invoke-Heartbeat (New-Case 'zombie') @{ tasks = @(@{ id = 'task-z'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 30; assigned = $false; acknowledgedBug = $true }) }) 'ZOMBIE_TASK' 'governor' | Out-Null
  Assert-Event (Invoke-Heartbeat (New-Case 'handoff') @{ tasks = @(@{ id = 'task-h'; owner = 'development'; status = 'completed'; dependencyStatus = 'completed'; requiredValidation = $true; validationStatus = 'not_run' }) }) 'TASK_HANDOFF_INCOMPLETE' 'governor' | Out-Null

  # Git/build routine work is quiet; unsafe or stale handoff state alerts.
  $git = New-Case 'git-build'
  Assert-Silent (Invoke-Heartbeat $git @{ git = @{ owner = 'development'; dirty = $true; completedTaskIdle = $false; requiresCommit = $false; idleMinutes = 2 } }) 'Normal active dirty tree.'
  Assert-Event (Invoke-Heartbeat $git @{ git = @{ owner = 'development'; dirty = $true; completedTaskIdle = $true; requiresCommit = $true; idleMinutes = 45 } }) 'GIT_BUILD_STATE' 'governor' | Out-Null
  $gitRisk = Assert-Event (Invoke-Heartbeat (New-Case 'git-risk') @{ git = @{ owner = 'development'; mergeConflict = $true; destructiveOperation = $false; branchChanged = $false; expectedCommitPushed = $true } }) 'GIT_STATE_RISK' 'governor'
  Assert-Equal $gitRisk.Severity 'CRITICAL' 'Merge conflict severity.'
  Assert-Event (Invoke-Heartbeat (New-Case 'build') @{ build = @{ owner = 'development'; status = 'passed'; artifactCommit = 'aaaaaaaa'; expectedCommit = 'bbbbbbbb'; artifactVersion = '0.7.7'; expectedVersion = '0.8.0'; manifestMatches = $false; installerArtifactHashMatches = $false; missingFileCount = 1; packageSizeBytes = 100; previousPackageSizeBytes = 100 } }) 'BUILD_ARTIFACT_DRIFT' 'governor' | Out-Null
  $buildContinuity = New-Case 'build-continuity'
  Assert-Event (Invoke-Heartbeat $buildContinuity @{ build = @{ owner = 'development'; status = 'failed'; artifactCommit = 'aaaaaaaa'; expectedCommit = 'bbbbbbbb'; manifestMatches = $false; installerArtifactHashMatches = $false } }) 'BUILD_ARTIFACT_DRIFT' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $buildContinuity @{ git = @{ owner = 'development'; dirty = $false; mergeConflict = $false; expectedCommitPushed = $true } }) 'Missing build evidence must not resolve build drift.'
  Assert-True ((Invoke-RawModule @('-Action', 'status', '-StatePath', $buildContinuity.State)).Text -match 'open=1') 'Git-only evidence resolved build drift.'
  Assert-Resolution (Invoke-Heartbeat $buildContinuity @{ build = @{ owner = 'development'; status = 'passed'; artifactCommit = 'bbbbbbbb'; expectedCommit = 'bbbbbbbb'; manifestMatches = $true; installerArtifactHashMatches = $true } }) 'BUILD_ARTIFACT_DRIFT' 'governor'

  # Recursion, duplicate run IDs, self-health backoff, and status UX.
  $recursion = New-Case 'recursion'
  Assert-Silent (Invoke-Heartbeat $recursion @{ origin = 'heartbeat_notification'; agents = @(@{ id = 'recursive'; active = $true; repeatedEquivalentActions = 20; minutesSinceMeaningfulChange = 60 }) }) 'Heartbeat-generated activity.'
  $duplicate = New-Case 'duplicate-run'
  $duplicateData = @{ runId = 'same-run'; agents = @(@{ id = 'dup-agent'; active = $true; repeatedEquivalentActions = 10; minutesSinceMeaningfulChange = 45 }) }
  Assert-Event (Invoke-Heartbeat $duplicate $duplicateData.Clone()) 'AGENT_STALL' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $duplicate $duplicateData.Clone()) 'Repeated run ID.'
  $duplicateState = Get-Content -Raw $duplicate.State | ConvertFrom-Json
  Assert-Equal $duplicateState.health.duplicateRuns 1 'Duplicate run accounting.'
  $runtimeVariance = New-Case 'runtime-variance'
  Assert-Silent (Invoke-Heartbeat $runtimeVariance @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 9000; runtimeBudgetMilliseconds = 10000 } }) 'Runtime baseline.'
  Assert-Silent (Invoke-Heartbeat $runtimeVariance @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 10629; runtimeBudgetMilliseconds = 10000 } }) 'Isolated 6.3 percent overrun.'
  $varianceStatus = Invoke-RawModule @('-Action', 'status', '-StatePath', $runtimeVariance.State)
  Assert-True ($varianceStatus.Text -match 'engine=healthy' -and $varianceStatus.Text -match 'runtimeBudgetMs=10000' -and $varianceStatus.Text -match 'runtimeObservedMs=10629' -and $varianceStatus.Text -match 'runtimeOverrunMs=629' -and $varianceStatus.Text -match 'runtimeOverrunPercent=6.3' -and $varianceStatus.Text -match 'runtimeClassification=normal_variance' -and $varianceStatus.Text -match 'runtimeBackoffApplied=false') 'Compact status did not explain tolerated runtime variance.'
  Assert-Silent (Invoke-Heartbeat $runtimeVariance @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 9500; runtimeBudgetMilliseconds = 10000 } }) 'Healthy runtime did not reset overrun streak.'

  $sustainedRuntime = New-Case 'runtime-sustained'
  $sustainedTime = [DateTimeOffset]::UtcNow
  Assert-Silent (Invoke-Heartbeat $sustainedRuntime @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 9000; runtimeBudgetMilliseconds = 10000 } } -At $sustainedTime) 'Sustained runtime baseline.'
  Assert-Silent (Invoke-Heartbeat $sustainedRuntime @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 10629; runtimeBudgetMilliseconds = 10000 } } -At ($sustainedTime.AddSeconds(1))) 'First modest overrun.'
  Assert-Silent (Invoke-Heartbeat $sustainedRuntime @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 10777; runtimeBudgetMilliseconds = 10000 } } -At ($sustainedTime.AddSeconds(2))) 'Second modest overrun.'
  $sustainedEvent = Assert-Event (Invoke-Heartbeat $sustainedRuntime @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 10650; runtimeBudgetMilliseconds = 10000 } } -At ($sustainedTime.AddSeconds(3))) 'HEARTBEAT_SELF_HEALTH' 'governor'
  Assert-True (@($sustainedEvent.Changed) -contains 'classification=sustained_overrun' -and @($sustainedEvent.Evidence) -contains 'runtimeOverrunStreak=3') 'Self-health event did not preserve separate classification evidence fields.'
  $sustainedStatus = Invoke-RawModule @('-Action', 'status', '-StatePath', $sustainedRuntime.State)
  Assert-True ($sustainedStatus.Text -match 'engine=backoff' -and $sustainedStatus.Text -match 'runtimeClassification=sustained_overrun' -and $sustainedStatus.Text -match 'runtimeOverrunStreak=3' -and $sustainedStatus.Text -match 'runtimeBackoffApplied=true') 'Sustained overrun did not back off with an explainable status.'
  Assert-Resolution (Invoke-Heartbeat $sustainedRuntime @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 9000; runtimeBudgetMilliseconds = 10000 } } -At ($sustainedTime.AddSeconds(4))) 'HEARTBEAT_SELF_HEALTH' 'governor'
  $recoveredStatus = Invoke-RawModule @('-Action', 'status', '-StatePath', $sustainedRuntime.State)
  Assert-True ($recoveredStatus.Text -match 'engine=healthy' -and $recoveredStatus.Text -match 'runtimeClassification=within_budget' -and $recoveredStatus.Text -match 'runtimeBackoffApplied=false' -and $recoveredStatus.Text -match 'backoffUntil=none') 'Healthy runtime did not clear the self-health backoff.'

  $materialRuntime = New-Case 'runtime-material'
  Assert-Silent (Invoke-Heartbeat $materialRuntime @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 9000; runtimeBudgetMilliseconds = 10000 } }) 'Material runtime baseline.'
  Assert-Event (Invoke-Heartbeat $materialRuntime @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 0; runtimeMilliseconds = 16000; runtimeBudgetMilliseconds = 10000 } }) 'HEARTBEAT_SELF_HEALTH' 'governor' | Out-Null
  Assert-True ((Invoke-RawModule @('-Action', 'status', '-StatePath', $materialRuntime.State)).Text -match 'runtimeClassification=material_overrun') 'Material overrun classification.'

  $selfHealth = New-Case 'self-health'
  $selfTime = [DateTimeOffset]::UtcNow
  Assert-Event (Invoke-Heartbeat $selfHealth @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 2; runtimeMilliseconds = 9000; runtimeBudgetMilliseconds = 10000 } } -At $selfTime) 'HEARTBEAT_SELF_HEALTH' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $selfHealth @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 2; runtimeMilliseconds = 9000; runtimeBudgetMilliseconds = 10000 } } -At ($selfTime.AddSeconds(1)) -NoForce) 'Self-health backoff.'
  $selfStatus = Invoke-RawModule @('-Action', 'status', '-StatePath', $selfHealth.State)
  Assert-True ($selfStatus.Text -match 'engine=backoff') 'Status did not expose Heartbeat backoff.'
  Assert-True ($selfStatus.Text -match 'activeTypes=8') 'Status did not report eight public heartbeat families.'
  Assert-True ($selfStatus.Text -match 'stateStoreMode=explicit' -and $selfStatus.Text -match 'stateStoreWriteReady=true') 'Heartbeat status did not expose its successful state-store preflight.'

  # Strict input schema accepts token counters but rejects unknown, secret, path, and loose Boolean data.
  $boundaries = New-Case 'boundaries'
  Assert-Silent (Invoke-Heartbeat $boundaries @{ agents = @(@{ id = '/root/token-worker'; active = $true; totalTokens = 922337203685477; tokensSinceMeaningfulChange = 0; progressHash = 'safe-hash' }) }) '64-bit token counters and canonical IDs.'
  $bad = Join-Path $boundaries.Path 'bad.json'
  [IO.File]::WriteAllText($bad, '{bad', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Malformed JSON.'
  [IO.File]::WriteAllText($bad, '{"agents":[{"id":"C:\\private","active":true}],"collectorCoverage":{"agent_stall":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Local path identifier.'
  [IO.File]::WriteAllText($bad, '{"agents":[{"id":"/home/alice/private","active":true}],"collectorCoverage":{"agent_stall":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Unix absolute path identifier.'
  [IO.File]::WriteAllText($bad, '{"agents":[{"id":"a","owner":"sk-sensitive-token-value-123456","active":true}],"collectorCoverage":{"agent_stall":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Secret-shaped value.'
  [IO.File]::WriteAllText($bad, '{"guardian":{"reviewerSessionId":"r","password":"do-not-persist"},"collectorCoverage":{"guardian":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Secret-shaped field.'
  [IO.File]::WriteAllText($bad, '{"agents":[{"id":"a","active":"false"}],"collectorCoverage":{"agent_stall":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Loose Boolean.'
  [IO.File]::WriteAllText($bad, '{"usage":{"owner":"governor","role":"governor","completedCycles":-1},"collectorCoverage":{"usage":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Negative Governor progress counter.'
  [IO.File]::WriteAllText($bad, '{"agents":[{"id":"a","active":true,"unknownField":1}],"collectorCoverage":{"agent_stall":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Unknown nested field.'
  [IO.File]::WriteAllText($bad, '{"schemaVersion":1,"capturedAtUtc":"2026-01-01T00:00:00Z","sourceEpoch":"a","sourceSequence":1,"collectorCoverage":{"agent_stall":"partial","agent_stall":"observed"},"agents":[]}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Duplicate JSON key.'
  [IO.File]::WriteAllText($bad, '{"schemaVersion":1,"capturedAtUtc":"2026-01-01T00:00:00Z","sourceEpoch":"a","sourceSequence":1,"collectorCoverage":{"agent_stall":"observed"},"agents":[{"id":"a","active":true,"owner":"safe","Owner":"other"}]}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Case-colliding JSON key.'
  [IO.File]::WriteAllText($bad, '{"schemaVersion":1,"capturedAtUtc":"2026-01-01T00:00:00Z","sourceEpoch":"a","sourceSequence":1e3,"collectorCoverage":{"agent_stall":"observed"},"agents":[]}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Scientific-notation sequence.'
  $oversized = Join-Path $boundaries.Path 'oversized.json'
  [IO.File]::WriteAllText($oversized, ('x' * 262145), [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $oversized, '-StatePath', (Join-Path $boundaries.Path 'bad-state.json'))) 'heartbeat_input_invalid' 'Oversized input.'
  $outsideState = Join-Path ([Environment]::GetFolderPath('UserProfile')) ('heartbeat-state-must-not-write-' + [guid]::NewGuid().ToString('N') + '.json')
  $outsideStateFull = [IO.Path]::GetFullPath($outsideState)
  foreach ($approvedRoot in @((Join-Path ([IO.Path]::GetTempPath()) 'Chronos\Heartbeat-v2'), (Join-Path $env:LOCALAPPDATA 'Chronos\Heartbeat'))) {
    $approvedRootFull = [IO.Path]::GetFullPath($approvedRoot).TrimEnd('\')
    Assert-True (-not $outsideStateFull.Equals($approvedRootFull, [StringComparison]::OrdinalIgnoreCase) -and -not $outsideStateFull.StartsWith($approvedRootFull + '\', [StringComparison]::OrdinalIgnoreCase)) 'Outside-root test fixture unexpectedly fell inside an approved state root.'
  }
  $validForPath = Join-Path $boundaries.Path 'valid-for-state-path.json'
  [IO.File]::WriteAllText($validForPath, '{"schemaVersion":1,"capturedAtUtc":"2026-01-01T00:00:00Z","sourceEpoch":"path-test","sourceSequence":1,"collectorCoverage":{"agent_stall":"observed"},"agents":[]}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $validForPath, '-StatePath', $outsideState)) 'heartbeat_state_path_invalid' 'State path outside approved roots.'
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', $outsideState)) 'heartbeat_state_path_invalid' 'State-path validation must precede malformed-input validation.'
  Assert-True (-not (Test-Path -LiteralPath $outsideState)) 'Rejected state path was written.'
  $tempSiblingDirectory = Join-Path ([IO.Path]::GetTempPath()) ('heartbeat-state-sibling-' + [guid]::NewGuid().ToString('N'))
  $tempSiblingState = Join-Path $tempSiblingDirectory 'arbitrary.json'
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $validForPath, '-StatePath', $tempSiblingState)) 'heartbeat_state_path_invalid' 'State path in a TEMP sibling outside the approved Heartbeat root.'
  Assert-True (-not (Test-Path -LiteralPath $tempSiblingState) -and -not (Test-Path -LiteralPath $tempSiblingDirectory)) 'Rejected TEMP sibling state path was created.'

  # State corruption, replacement, interrupted temp files, and out-of-order samples fail safely.
  $stateCase = New-Case 'state'
  Assert-Silent (Invoke-Heartbeat $stateCase @{ agents = @(@{ id = 'state-agent'; active = $true; progressHash = 'a' }) }) 'Initial state write.'
  $revision1 = (Get-Content -Raw $stateCase.State | ConvertFrom-Json).revision
  [IO.File]::WriteAllText((Join-Path $stateCase.Path '.heartbeat-interrupted.tmp'), '{bad', [Text.UTF8Encoding]::new($false))
  Assert-Silent (Invoke-Heartbeat $stateCase @{ agents = @(@{ id = 'state-agent'; active = $true; progressHash = 'b' }) }) 'Atomic replacement with orphan temp.'
  $revision2 = (Get-Content -Raw $stateCase.State | ConvertFrom-Json).revision
  Assert-True ($revision2 -gt $revision1) 'State revision did not advance.'
  $corruptState = Join-Path $stateCase.Path 'corrupt-state.json'
  [IO.File]::WriteAllText($corruptState, '{bad', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-Action', 'status', '-StatePath', $corruptState)) 'heartbeat_state_invalid' 'Malformed state.'
  $duplicateStatePath = Join-Path $stateCase.Path 'duplicate-state.json'
  $duplicateStateText = (Get-Content -Raw $stateCase.State) -replace '^\{', '{"schema":4,'
  [IO.File]::WriteAllText($duplicateStatePath, $duplicateStateText, [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-Action', 'status', '-StatePath', $duplicateStatePath)) 'heartbeat_state_invalid' 'Duplicate state key.'
  $largeState = Join-Path $stateCase.Path 'large-state.json'
  [IO.File]::WriteAllText($largeState, ('x' * 262145), [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-Action', 'status', '-StatePath', $largeState)) 'heartbeat_state_invalid' 'Oversized state.'
  $timeCase = New-Case 'time-order'
  $later = $timeCase.BaseTime.AddHours(1)
  Assert-Silent (Invoke-Heartbeat $timeCase @{ agents = @(@{ id = 'time-agent'; active = $true; progressHash = 'a' }) } -At $later) 'Time baseline.'
  $outOfOrder = Invoke-Heartbeat $timeCase @{ agents = @(@{ id = 'time-agent'; active = $true; progressHash = 'b' }) } -At ($later.AddMinutes(-10))
  Assert-FailedSafely $outOfOrder 'heartbeat_time_out_of_order' 'Out-of-order snapshot.'
  $sourceOrder = New-Case 'source-order'
  Assert-Silent (Invoke-Heartbeat $sourceOrder @{ agents = @(@{ id = 'source-agent'; active = $true }) }) 'Source sequence baseline.'
  $staleSequence = $sourceOrder.Sequence
  $sourceOrder.Sequence++
  $sourceInput = Join-Path $sourceOrder.Path 'stale-source.json'
  $sourceData = @{ schemaVersion = 1; capturedAtUtc = $sourceOrder.BaseTime.AddMinutes(20).ToString('o'); sourceEpoch = 'epoch-source-order'; sourceSequence = $staleSequence; runId = 'different-run'; origin = 'test'; forceCadence = $true; collectorCoverage = @{ agent_stall = 'observed' }; agents = @(@{ id = 'source-agent'; active = $true }) }
  [IO.File]::WriteAllText($sourceInput, ($sourceData | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $sourceInput, '-StatePath', $sourceOrder.State)) 'heartbeat_source_out_of_order' 'Non-monotonic source sequence.'

  # Reparse-point containment for input and state paths.
  $reparse = New-Case 'reparse'
  $realDirectory = Join-Path $reparse.Path 'real'
  $junction = Join-Path $reparse.Path 'junction'
  New-Item -ItemType Directory -Path $realDirectory | Out-Null
  New-Item -ItemType Junction -Path $junction -Target $realDirectory | Out-Null
  $junctionInput = Join-Path $junction 'input.json'
  [IO.File]::WriteAllText($junctionInput, '{"agents":[],"collectorCoverage":{"agent_stall":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $junctionInput, '-StatePath', (Join-Path $reparse.Path 'state.json'))) 'heartbeat_input_invalid' 'Reparse input path.'
  $safeInput = Join-Path $reparse.Path 'safe.json'
  [IO.File]::WriteAllText($safeInput, '{"agents":[],"collectorCoverage":{"agent_stall":"observed"}}', [Text.UTF8Encoding]::new($false))
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $safeInput, '-StatePath', (Join-Path $junction 'state.json'))) 'heartbeat_state_path_invalid' 'Reparse state path.'

  # Multiple directory-entry names for one state file cannot create independent locks.
  $hardlink = New-Case 'hardlink'
  Assert-Silent (Invoke-Heartbeat $hardlink @{ agents = @(@{ id = 'hardlink-agent'; active = $true }) }) 'Hard-link baseline.'
  $hardlinkAlias = Join-Path $hardlink.Path 'state-alias.json'
  New-Item -ItemType HardLink -Path $hardlinkAlias -Target $hardlink.State | Out-Null
  Assert-FailedSafely (Invoke-Heartbeat $hardlink @{ agents = @(@{ id = 'hardlink-agent'; active = $true }) } -StatePath $hardlinkAlias) 'heartbeat_state_path_invalid' 'Hard-linked state alias.'

  # Inspector adapter uses existing compact Chronos fields without persisting raw output.
  $adapter = New-Case 'inspector-adapter'
  $inspector1 = Join-Path $adapter.Path 'inspector-1.txt'
  $inspector2 = Join-Path $adapter.Path 'inspector-2.txt'
  [IO.File]::WriteAllText($inspector1, "CHRONOS HEALTHY approvalReviewCoverage=complete approvalReviewsPerHour=2 approvalReviewerMainInputRatio=0.2 approvalRepeatedRequests=0`nCHRONOS EFFICIENCY pluginVersion=0.8.0 approvalReviewTurnsObserved=2 primaryTurnsObserved=10 approvalReviewTurnShare=16.7 approvalRepeatedPrefixRequests=0 approvalPersistenceRetries=0", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($inspector2, "CHRONOS WARNING approvalReviewCoverage=complete approvalReviewsPerHour=20 approvalReviewerMainInputRatio=0.9 approvalRepeatedRequests=10`nCHRONOS EFFICIENCY pluginVersion=0.8.0 approvalReviewTurnsObserved=30 primaryTurnsObserved=3 approvalReviewTurnShare=91 approvalRepeatedPrefixRequests=10 approvalPersistenceRetries=8", [Text.UTF8Encoding]::new($false))
  $adapterInput1 = Join-Path $adapter.Path 'adapter-1.json'
  $adapterInput2 = Join-Path $adapter.Path 'adapter-2.json'
  [IO.File]::WriteAllText($adapterInput1, (@{ schemaVersion = 1; runId = 'adapter-1'; capturedAtUtc = $adapter.BaseTime.ToString('o'); origin = 'inspector'; forceCadence = $true } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($adapterInput2, (@{ schemaVersion = 1; runId = 'adapter-2'; capturedAtUtc = $adapter.BaseTime.AddMinutes(10).ToString('o'); origin = 'inspector'; forceCadence = $true } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  Assert-Silent ([pscustomobject]@{ ExitCode = $( $o = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -Action heartbeat -HeartbeatInputPath $adapterInput1 -HeartbeatInspectorOutputPath $inspector1 -HeartbeatStatePath $adapter.State 2>&1); $LASTEXITCODE ); Output = $o; Text = ($o -join "`n") }) 'Inspector adapter baseline.'
  $adapterOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -Action heartbeat -HeartbeatInputPath $adapterInput2 -HeartbeatInspectorOutputPath $inspector2 -HeartbeatStatePath $adapter.State 2>&1)
  $adapterResult = [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $adapterOutput; Text = ($adapterOutput -join "`n") }
  Assert-Event $adapterResult 'GUARDIAN_RUNAWAY' 'governor' | Out-Null
  $adapterStateText = Get-Content -Raw $adapter.State
  Assert-True ($adapterStateText -notmatch 'CHRONOS HEALTHY|approvalReviewTurnsObserved|inspector-1.txt') 'Inspector output was persisted raw.'

  # Cross-process duplicate scheduling emits one event and keeps valid state.
  $race = New-Case 'race'
  $raceInput = Join-Path $race.Path 'race.json'
  $raceData = @{ schemaVersion = 1; capturedAtUtc = $race.BaseTime.ToString('o'); runId = 'race-run'; origin = 'test'; forceCadence = $true; collectorCoverage = @{ agent_stall = 'observed' }; agents = @(@{ id = 'race-agent'; active = $true; repeatedEquivalentActions = 10; minutesSinceMeaningfulChange = 45 }) }
  [IO.File]::WriteAllText($raceInput, ($raceData | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
  $stateAliases = @($race.State.ToLowerInvariant(), $race.State.ToUpperInvariant())
  $processes = @()
  foreach ($index in 1..2) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action heartbeat -HeartbeatInputPath "{1}" -HeartbeatStatePath "{2}"' -f $wrapper, $raceInput, $stateAliases[$index - 1]
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $processes += $process
  }
  $raceText = ''
  foreach ($process in $processes) {
    $raceText += $process.StandardOutput.ReadToEnd()
    $raceText += $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Assert-Equal $process.ExitCode 0 'Concurrent Heartbeat process exit code.'
    $process.Dispose()
  }
  Assert-Equal ([regex]::Matches($raceText, 'AGENT_STALL').Count) 1 'Concurrent cycles must emit one stall event.'
  Assert-True ((Get-Content -Raw $race.State | ConvertFrom-Json).schema -eq 7) 'Concurrent cycles corrupted state.'

  $busy = New-Case 'cycle-busy'
  $busyInput = Join-Path $busy.Path 'busy.json'
  $busyReady = Join-Path $busy.Path 'ready.txt'
  [IO.File]::WriteAllText($busyInput, (@{ schemaVersion = 1; capturedAtUtc = $busy.BaseTime.ToString('o'); sourceEpoch = 'busy'; sourceSequence = 1; runId = 'busy-run'; origin = 'test'; forceCadence = $true; collectorCoverage = @{ agent_stall = 'observed' }; agents = @() } | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
  $busyMutexName = 'Global\ChronosHeartbeat-' + (Get-TestHash (Get-TestCanonicalStateIdentity $busy.State)).Substring(0, 24)
  $busyCommand = "`$m=New-Object Threading.Mutex(`$false,'$busyMutexName');[void]`$m.WaitOne();[IO.File]::WriteAllText('$($busyReady.Replace("'", "''"))','ready');Start-Sleep -Seconds 7;`$m.ReleaseMutex();`$m.Dispose()"
  $busyEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($busyCommand))
  $busyHolder = Start-HiddenPowerShell $busyEncoded
  try {
    $busyDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $busyReady) -and [DateTime]::UtcNow -lt $busyDeadline) { Start-Sleep -Milliseconds 50 }
    Assert-True (Test-Path -LiteralPath $busyReady) 'Cycle contention fixture did not acquire the Heartbeat mutex.'
    $busyResult = Invoke-RawModule @('-InputPath', $busyInput, '-StatePath', $busy.State)
    Assert-True ($busyResult.ExitCode -ne 0 -and $busyResult.Text -match 'heartbeat_mutex_busy' -and $busyResult.Text -match '"retryRequired":true') 'A unique overlapping cycle was silently discarded instead of returning an explicit retry contract.'
  } finally {
    $busyHolder.WaitForExit()
    $busyHolder.Dispose()
  }

  # The persisted outbox closes the state/output crash window with stable IDs.
  $outbox = New-Case 'outbox'
  Assert-Silent (Invoke-Heartbeat $outbox @{ agents = @(@{ id = 'outbox-agent'; active = $true; progressHash = 'a'; totalTokens = 1000 }) }) 'Outbox baseline.'
  $firstDelivery = Invoke-Heartbeat $outbox @{ agents = @(@{ id = 'outbox-agent'; active = $true; progressHash = 'a'; totalTokens = 50000; tokensSinceMeaningfulChange = 49000; repeatedEquivalentActions = 5; minutesSinceMeaningfulChange = 25 }) } -NoAcknowledge
  $firstEvent = Assert-Event $firstDelivery 'AGENT_STALL' 'governor'
  Assert-True ($firstEvent.EventId -match '^[a-f0-9]{64}$') 'Heartbeat event lacks a stable event ID.'
  $pendingState = Get-Content -Raw $outbox.State | ConvertFrom-Json
  Assert-Equal @($pendingState.outbox).Count 1 'New event was not persisted to the outbox.'
  Assert-Equal $pendingState.outbox[0].attempts 1 'Initial delivery attempt was not recorded.'
  Assert-True ((Get-Content -Raw $outbox.State) -notmatch 'outbox-agent') 'Outbox persisted a raw subject identifier.'
  $pendingState.outbox[0].attempts = 0
  $pendingState.outbox[0].lastAttempt = $null
  [IO.File]::WriteAllText($outbox.State, ($pendingState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  $retryDelivery = Invoke-RawModule @('-InputPath', $firstDelivery.InputPath, '-StatePath', $outbox.State)
  $retryEvents = @(Get-Events $retryDelivery)
  $retry = @($retryEvents | Where-Object { $_.EventId -eq $firstEvent.EventId -and $_.Delivery -eq 'retry' })
  Assert-Equal $retry.Count 1 'Pending event did not retry with the stable event ID.'
  Assert-Equal $retry[0].OwningSolThread 'governor' 'Privacy-safe retry must fall back to Governor.'

  # Retry cadence is wall-clock delivery time, and stale evidence cannot preempt it.
  Assert-Silent (Invoke-Heartbeat $outbox @{ collectorCoverage = @{ agent_stall = 'partial' }; agents = @(@{ id = 'outbox-agent'; active = $true; progressHash = 'a'; totalTokens = 50000 }) } -At $outbox.BaseTime.AddMinutes(60)) 'Newer partial cycle before old-run replay.'
  $elapsedState = Get-Content -Raw $outbox.State | ConvertFrom-Json
  $elapsedState.outbox[0].lastAttempt = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToString('o')
  [IO.File]::WriteAllText($outbox.State, ($elapsedState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  $elapsedRetry = Invoke-RawModule @('-InputPath', $firstDelivery.InputPath, '-StatePath', $outbox.State)
  $elapsedEvents = @(Get-Events $elapsedRetry | Where-Object { $_.EventId -eq $firstEvent.EventId -and $_.Delivery -eq 'retry' })
  Assert-Equal $elapsedEvents.Count 1 'Newer evidence preempted a due replay of the older serialized run.'
  $replayedState = Get-Content -Raw $outbox.State | ConvertFrom-Json
  Assert-Equal $replayedState.health.lastCycleUtc $elapsedState.health.lastCycleUtc 'Stale replay advanced detector evidence time.'
  $replayedState.outbox[0].lastAttempt = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToString('o')
  [IO.File]::WriteAllText($outbox.State, ($replayedState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  Assert-Silent (Invoke-RawModule @('-InputPath', $firstDelivery.InputPath, '-StatePath', $outbox.State)) 'Outbox retry budget must stop after two attempts.'
  $ackOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -Action heartbeat -HeartbeatAcknowledgeEventId $firstEvent.EventId -HeartbeatStatePath $outbox.State 2>&1)
  Assert-Equal $LASTEXITCODE 0 'Outbox acknowledgement exit code.'
  Assert-True (($ackOutput -join "`n") -match '"acknowledged":true') 'Outbox acknowledgement response.'
  Assert-Equal @((Get-Content -Raw $outbox.State | ConvertFrom-Json).outbox).Count 0 'Acknowledged event remained pending.'
  Assert-Silent (Invoke-Heartbeat $outbox @{ collectorCoverage = @{ agent_stall = 'partial' }; agents = @(@{ id = 'outbox-agent'; active = $true; progressHash = 'a'; totalTokens = 50000 }) } -At $outbox.BaseTime.AddMinutes(70)) 'Acknowledged event must not retry.'

  # Native planning enforces each fixed target policy instead of trusting the host.
  $subjectBinding = New-Case 'intervention-subject-binding'
  Assert-Silent (Invoke-Heartbeat $subjectBinding @{ usage = @{ owner = 'usage-owner'; dominantThread = 'usage-subject'; totalTokens = 10000; ratePerMinute = 5000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same' } }) 'Subject target baseline.'
  $subjectBindingCycle = Invoke-Heartbeat $subjectBinding @{ usage = @{ owner = 'usage-owner'; dominantThread = 'usage-subject'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same' } } -NoAcknowledge
  $subjectBindingEvent = Assert-Event $subjectBindingCycle 'USAGE_BURN' 'governor'
  $subjectMismatch = Get-InterventionPayload (Invoke-Intervention $subjectBinding 'plan' -EventId $subjectBindingEvent.EventId -Target 'usage-owner' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $subjectMismatch.reason 'target_policy_mismatch' 'A subject-only event was redirected to its owner.'

  $ownerBinding = New-Case 'intervention-owner-binding'
  Assert-Silent (Invoke-Heartbeat $ownerBinding @{ tests = @(@{ name = 'binding-test'; owner = 'binding-owner'; status = 'passed'; commit = 'aaaaaaaa'; repairAttempts = 0; failureCount = 0 }) }) 'Owner target baseline.'
  $ownerBindingCycle = Invoke-Heartbeat $ownerBinding @{ tests = @(@{ name = 'binding-test'; owner = 'binding-owner'; status = 'failed'; commit = 'aaaaaaaa'; repairAttempts = 1; failureCount = 1 }) } -NoAcknowledge
  $ownerBindingEvent = Assert-Event $ownerBindingCycle 'TEST_REGRESSION' 'governor'
  $ownerMismatch = Get-InterventionPayload (Invoke-Intervention $ownerBinding 'plan' -EventId $ownerBindingEvent.EventId -Target 'binding-test' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $ownerMismatch.reason 'target_policy_mismatch' 'An owner-only event was redirected to its subject.'

  $subjectOrOwnerBinding = New-Case 'intervention-subject-or-owner-binding'
  Assert-Silent (Invoke-Heartbeat $subjectOrOwnerBinding @{ agents = @(@{ id = 'binding-agent'; owner = 'binding-root'; active = $true; progressHash = 'same'; totalTokens = 1000 }) }) 'Subject-or-owner baseline.'
  $subjectOrOwnerCycle = Invoke-Heartbeat $subjectOrOwnerBinding @{ agents = @(@{ id = 'binding-agent'; owner = 'binding-root'; active = $true; progressHash = 'same'; totalTokens = 60000; tokensSinceMeaningfulChange = 59000; repeatedEquivalentActions = 6; minutesSinceMeaningfulChange = 30 }) } -NoAcknowledge
  $subjectOrOwnerEvent = Assert-Event $subjectOrOwnerCycle 'AGENT_STALL' 'governor'
  $ownerPlan = Get-InterventionPayload (Invoke-Intervention $subjectOrOwnerBinding 'plan' -EventId $subjectOrOwnerEvent.EventId -Target 'binding-root' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $ownerPlan.decision 'send' 'A verified owner was rejected for a subject-or-owner event.'

  # Pending evidence is bound to the generation observed by the collector.
  $staleGeneration = New-Case 'intervention-stale-generation'
  Assert-Silent (Invoke-Heartbeat $staleGeneration @{ agents = @(@{ id = 'stale-target'; generation = 'generation-one'; owner = 'stale-target'; active = $true; progressHash = 'same'; totalTokens = 1000 }) }) 'Stale-generation baseline.'
  $staleGenerationCycle = Invoke-Heartbeat $staleGeneration @{ agents = @(@{ id = 'stale-target'; generation = 'generation-one'; owner = 'stale-target'; active = $true; progressHash = 'same'; totalTokens = 60000; tokensSinceMeaningfulChange = 59000; repeatedEquivalentActions = 6; minutesSinceMeaningfulChange = 30 }) } -NoAcknowledge
  $staleGenerationEvent = Assert-Event $staleGenerationCycle 'AGENT_STALL' 'governor'
  Assert-Silent (Invoke-Heartbeat $staleGeneration @{ agents = @(@{ id = 'stale-target'; generation = 'generation-two'; owner = 'stale-target'; active = $true; progressHash = 'new'; totalTokens = 61000 }) }) 'Replacement generation observation.'
  $staleGenerationPlan = Get-InterventionPayload (Invoke-Intervention $staleGeneration 'plan' -EventId $staleGenerationEvent.EventId -Target 'stale-target' -Generation 'generation-two' -Governor 'governor-task')
  Assert-Equal $staleGenerationPlan.decision 'failed_closed' 'A stale event was rebound to a replacement task generation.'
  Assert-Equal $staleGenerationPlan.reason 'target_generation_mismatch' 'Stale generation rejection was not explicit.'

  # Owner-targeted events bind the owner's generation, not the child record's.
  $ownerGeneration = New-Case 'intervention-owner-generation'
  $ownerGenerationCycle = Invoke-Heartbeat $ownerGeneration @{ tasks = @(@{ id = 'child-task'; generation = 'child-g1'; owner = 'parent-task'; ownerGeneration = 'parent-g9'; status = 'completed'; requiredValidation = $true; validationStatus = 'failed' }) } -NoAcknowledge
  $ownerGenerationEvent = Assert-Event $ownerGenerationCycle 'TASK_HANDOFF_INCOMPLETE' 'governor'
  $ownerGenerationPlan = Get-InterventionPayload (Invoke-Intervention $ownerGeneration 'plan' -EventId $ownerGenerationEvent.EventId -Target 'parent-task' -Generation 'parent-g9' -Governor 'governor-task')
  Assert-Equal $ownerGenerationPlan.decision 'send' 'A truthful owner generation was compared with the child generation.'

  $correctedOwnerGeneration = New-Case 'intervention-corrected-owner-generation'
  $missingOwnerCycle = Invoke-Heartbeat $correctedOwnerGeneration @{ tasks = @(@{ id = 'child-task'; generation = 'child-g1'; owner = 'parent-task'; status = 'completed'; requiredValidation = $true; validationStatus = 'failed' }) } -NoAcknowledge
  $missingOwnerEvent = Assert-Event $missingOwnerCycle 'TASK_HANDOFF_INCOMPLETE' 'governor'
  $correctedOwnerCycle = Invoke-Heartbeat $correctedOwnerGeneration @{ tasks = @(@{ id = 'child-task'; generation = 'child-g1'; owner = 'parent-task'; ownerGeneration = 'parent-g9'; status = 'completed'; requiredValidation = $true; validationStatus = 'failed' }) } -NoAcknowledge
  $correctedOwnerEvent = Assert-Event $correctedOwnerCycle 'TASK_HANDOFF_INCOMPLETE' 'governor'
  Assert-True ($correctedOwnerEvent.EventId -ne $missingOwnerEvent.EventId) 'Corrected owner generation reused the stale event identity.'
  Assert-FailedSafely (Invoke-Intervention $correctedOwnerGeneration 'plan' -EventId $missingOwnerEvent.EventId -Target 'parent-task' -Generation 'parent-g9' -Governor 'governor-task') 'heartbeat_intervention_event_unavailable' 'Corrected owner evidence left the stale event planable.'
  $correctedOwnerPlan = Get-InterventionPayload (Invoke-Intervention $correctedOwnerGeneration 'plan' -EventId $correctedOwnerEvent.EventId -Target 'parent-task' -Generation 'parent-g9' -Governor 'governor-task')
  Assert-Equal $correctedOwnerPlan.decision 'send' 'Corrected owner generation did not re-arm the open condition.'

  $staleOwnerGeneration = New-Case 'intervention-stale-owner-generation'
  $staleOwnerCycle = Invoke-Heartbeat $staleOwnerGeneration @{ tasks = @(@{ id = 'child-task'; generation = 'child-g1'; owner = 'parent-task'; ownerGeneration = 'parent-g9'; status = 'completed'; requiredValidation = $true; validationStatus = 'failed' }) } -NoAcknowledge
  $staleOwnerEvent = Assert-Event $staleOwnerCycle 'TASK_HANDOFF_INCOMPLETE' 'governor'
  $rotatedOwnerCycle = Invoke-Heartbeat $staleOwnerGeneration @{ tasks = @(@{ id = 'child-task'; generation = 'child-g1'; owner = 'parent-task'; ownerGeneration = 'parent-g10'; status = 'completed'; requiredValidation = $true; validationStatus = 'failed' }) } -NoAcknowledge
  $rotatedOwnerEvent = Assert-Event $rotatedOwnerCycle 'TASK_HANDOFF_INCOMPLETE' 'governor'
  Assert-True ($rotatedOwnerEvent.EventId -ne $staleOwnerEvent.EventId) 'Owner rotation did not replace the stale event identity.'
  Assert-FailedSafely (Invoke-Intervention $staleOwnerGeneration 'plan' -EventId $staleOwnerEvent.EventId -Target 'parent-task' -Generation 'parent-g10' -Governor 'governor-task') 'heartbeat_intervention_event_unavailable' 'Owner rotation left the stale event planable.'
  $rotatedOwnerPlan = Get-InterventionPayload (Invoke-Intervention $staleOwnerGeneration 'plan' -EventId $rotatedOwnerEvent.EventId -Target 'parent-task' -Generation 'parent-g10' -Governor 'governor-task')
  Assert-Equal $rotatedOwnerPlan.decision 'send' 'Owner rotation did not re-arm the open condition.'

  # Eight events for one task are coalesced before any host wake is claimed.
  $coalesce = New-Case 'intervention-coalesce'
  $coalesceTasks = @(1..8 | ForEach-Object { @{ id = ('coalesce-item-' + $_); owner = 'coalesce-target'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false } })
  $coalesceCycle = Invoke-Heartbeat $coalesce @{ tasks = $coalesceTasks } -NoAcknowledge
  $coalesceEvents = @(Get-Events $coalesceCycle | Where-Object { $_.Event -eq 'HEARTBEAT_EVENT' })
  Assert-Equal $coalesceEvents.Count 8 'Expected eight simultaneous task events for coalescing.'
  $planDecisions = @()
  foreach ($event in $coalesceEvents) {
    $planDecisions += (Get-InterventionPayload (Invoke-Intervention $coalesce 'plan' -EventId $event.EventId -Target 'coalesce-target' -Generation 'generation-1' -Governor 'governor-task')).decision
  }
  Assert-Equal @($planDecisions | Where-Object { $_ -eq 'send' }).Count 1 'One task received more than one initial intervention envelope.'
  Assert-Equal @($planDecisions | Where-Object { $_ -eq 'coalesced' }).Count 7 'Compatible task events were not coalesced.'
  $coalescedState = Get-Content -Raw $coalesce.State | ConvertFrom-Json
  $activeInterventions = @($coalescedState.interventions | Where-Object { $_.state -eq 'queued' })
  Assert-Equal $activeInterventions.Count 1 'More than one active intervention was retained for one target.'
  Assert-Equal $activeInterventions[0].coalescedCount 7 'Coalesced event count was not retained.'
  Assert-True ((Get-Content -Raw $coalesce.State) -notmatch 'coalesce-target') 'Intervention state persisted a raw target identifier.'
  $coalescedClaim = Get-InterventionPayload (Invoke-Intervention $coalesce 'claim' -InterventionId $activeInterventions[0].interventionId -Version 1 -Target 'coalesce-target' -Generation 'generation-1' -Governor 'governor-task')
  $unknownDelivery = Get-InterventionPayload (Invoke-Intervention $coalesce 'transport' -InterventionId $coalescedClaim.interventionId -Version 1 -ClaimToken $coalescedClaim.claimToken -TransportResult 'unknown')
  Assert-Equal $unknownDelivery.state 'delivery_unknown' 'Ambiguous transport was not retained as delivery_unknown.'
  Assert-FailedSafely (Invoke-Intervention $coalesce 'claim' -InterventionId $coalescedClaim.interventionId -Version 1 -Target 'coalesce-target' -Generation 'generation-1' -Governor 'governor-task') 'heartbeat_intervention_transition_invalid' 'Ambiguous delivery was retried blindly.'

  # Same task IDs in different host generations never share intervention state.
  $generationCase = New-Case 'intervention-generation'
  $generationOneCycle = Invoke-Heartbeat $generationCase @{ tasks = @(
      @{ id = 'generation-target'; generation = 'generation-one'; owner = 'generation-target'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false }
    ) } -NoAcknowledge
  $generationOneEvent = @(Get-Events $generationOneCycle | Where-Object { $_.Event -eq 'HEARTBEAT_EVENT' })[0]
  $generationOnePlan = Get-InterventionPayload (Invoke-Intervention $generationCase 'plan' -EventId $generationOneEvent.EventId -Target 'generation-target' -Generation 'generation-one' -Governor 'governor-task')
  $generationTwoCycle = Invoke-Heartbeat $generationCase @{ tasks = @(
      @{ id = 'generation-target'; generation = 'generation-two'; owner = 'generation-target'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false }
    ) } -NoAcknowledge
  $generationTwoEvent = @(Get-Events $generationTwoCycle | Where-Object { $_.Event -eq 'HEARTBEAT_EVENT' })[0]
  $generationTwoPlan = Get-InterventionPayload (Invoke-Intervention $generationCase 'plan' -EventId $generationTwoEvent.EventId -Target 'generation-target' -Generation 'generation-two' -Governor 'governor-task')
  Assert-Equal $generationOnePlan.decision 'send' 'Initial generation plan was not queued.'
  Assert-Equal $generationTwoPlan.decision 'send' 'A new host generation was coalesced into the old generation.'
  $generationState = Get-Content -Raw $generationCase.State | ConvertFrom-Json
  Assert-Equal @($generationState.interventions | Where-Object { $_.state -eq 'superseded' }).Count 1 'Old-generation intervention was not isolated.'
  Assert-Equal @($generationState.interventions | Where-Object { $_.state -eq 'queued' }).Count 1 'New-generation intervention was not independently queued.'

  $listed = Get-InterventionPayload (Invoke-Intervention $generationCase 'list' -Governor 'governor-task')
  Assert-Equal $listed.count 1 'A restarted Governor could not enumerate its active intervention.'
  Assert-Equal $listed.interventions[0].permittedNextAction 'claim' 'Intervention recovery did not expose the bounded next action.'
  Assert-True ($listed.interventions[0].targetHash -notmatch 'generation-target' -and $listed.interventions[0].generationHash.Length -eq 16) 'Intervention recovery exposed a raw target or omitted generation evidence.'
  $generationClaim = Get-InterventionPayload (Invoke-Intervention $generationCase 'claim' -InterventionId $generationTwoPlan.interventionId -Version 1 -Target 'generation-target' -Generation 'generation-two' -Governor 'governor-task')
  $claimedState = Get-Content -Raw $generationCase.State | ConvertFrom-Json
  @($claimedState.interventions | Where-Object { $_.interventionId -eq $generationTwoPlan.interventionId })[0].claimExpiresAt = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
  [IO.File]::WriteAllText($generationCase.State, ($claimedState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  $reclaimList = Get-InterventionPayload (Invoke-Intervention $generationCase 'list' -Governor 'governor-task')
  Assert-Equal $reclaimList.interventions[0].permittedNextAction 'mark_delivery_unknown' 'Expired persisted claim did not expose its ambiguous delivery state.'
  $reclaimed = Get-InterventionPayload (Invoke-Intervention $generationCase 'reclaim' -InterventionId $generationTwoPlan.interventionId -Version 1 -Governor 'governor-task')
  Assert-Equal $reclaimed.state 'delivery_unknown' 'Expired claimed send was incorrectly made retryable.'
  Assert-FailedSafely (Invoke-Intervention $generationCase 'claim' -InterventionId $generationTwoPlan.interventionId -Version 1 -Target 'generation-target' -Generation 'generation-two' -Governor 'governor-task') 'heartbeat_intervention_transition_invalid' 'An ambiguous expired send was retried.'

  $incompatible = New-Case 'intervention-incompatible-contract'
  Assert-Silent (Invoke-Heartbeat $incompatible @{ agents = @(@{ id = 'incompatible-target'; owner = 'incompatible-target'; active = $true; progressHash = 'same'; totalTokens = 1000 }) }) 'Incompatible-contract baseline.'
  $incompatibleCycle = Invoke-Heartbeat $incompatible @{
      agents = @(@{ id = 'incompatible-target'; owner = 'incompatible-target'; active = $true; progressHash = 'same'; totalTokens = 60000; tokensSinceMeaningfulChange = 59000; repeatedEquivalentActions = 6; minutesSinceMeaningfulChange = 30 })
      tasks = @(@{ id = 'incompatible-item'; owner = 'incompatible-target'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false })
    } -NoAcknowledge
  $incompatibleEvents = @(Get-Events $incompatibleCycle)
  $taskContractEvent = @($incompatibleEvents | Where-Object { $_.Type -eq 'ZOMBIE_TASK' })[0]
  $stallContractEvent = @($incompatibleEvents | Where-Object { $_.Type -eq 'AGENT_STALL' })[0]
  [void](Get-InterventionPayload (Invoke-Intervention $incompatible 'plan' -EventId $taskContractEvent.EventId -Target 'incompatible-target' -Generation 'generation-1' -Governor 'governor-task'))
  $deferredContract = Get-InterventionPayload (Invoke-Intervention $incompatible 'plan' -EventId $stallContractEvent.EventId -Target 'incompatible-target' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $deferredContract.decision 'deferred_incompatible' 'An incompatible remediation contract was coalesced by target alone.'
  Assert-True (@((Get-Content -Raw $incompatible.State | ConvertFrom-Json).outbox | Where-Object { $_.eventId -eq $stallContractEvent.EventId }).Count -eq 1) 'Deferred incompatible evidence was consumed instead of remaining recoverable.'

  # A higher-severity event replaces an unsent version instead of adding a wake.
  $replace = New-Case 'intervention-replace'
  Assert-Silent (Invoke-Heartbeat $replace @{ agents = @(@{ id = 'replace-target'; owner = 'replace-target'; active = $true; progressHash = 'same'; totalTokens = 1000 }) }) 'Replacement baseline.'
  $warningCycle = Invoke-Heartbeat $replace @{ agents = @(@{ id = 'replace-target'; owner = 'replace-target'; active = $true; progressHash = 'same'; totalTokens = 60000; tokensSinceMeaningfulChange = 59000; repeatedEquivalentActions = 6; minutesSinceMeaningfulChange = 30 }) } -NoAcknowledge
  $warningReplaceEvent = @((Get-Events $warningCycle) | Where-Object { $_.Type -eq 'AGENT_STALL' })[0]
  $warningPlan = Get-InterventionPayload (Invoke-Intervention $replace 'plan' -EventId $warningReplaceEvent.EventId -Target 'replace-target' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $warningPlan.version 1 'Initial warning intervention version.'
  $highCycle = Invoke-Heartbeat $replace @{ agents = @(@{ id = 'replace-target'; owner = 'replace-target'; active = $true; progressHash = 'same'; totalTokens = 220000; tokensSinceMeaningfulChange = 160000; repeatedEquivalentActions = 10; minutesSinceMeaningfulChange = 45 }) } -NoAcknowledge
  $highReplaceEvent = @((Get-Events $highCycle) | Where-Object { $_.Type -eq 'AGENT_STALL' })[0]
  $highPlan = Get-InterventionPayload (Invoke-Intervention $replace 'plan' -EventId $highReplaceEvent.EventId -Target 'replace-target' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $highPlan.version 2 'Higher-severity event did not replace the unsent intervention version.'
  $replaceState = Get-Content -Raw $replace.State | ConvertFrom-Json
  Assert-Equal @($replaceState.interventions | Where-Object { $_.state -eq 'queued' }).Count 1 'Replacement retained multiple queued wakes.'
  Assert-Equal @($replaceState.interventions | Where-Object { $_.state -eq 'superseded' }).Count 1 'Prior unsent version was not superseded.'

  # Governor usage can be diagnosed, but it can never target or wake Governor.
  $selfUsage = New-Case 'intervention-self-usage'
  Assert-Silent (Invoke-Heartbeat $selfUsage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'governor-task'; totalTokens = 10000; ratePerMinute = 5000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 0 } }) 'Governor usage baseline.'
  $selfCycle = Invoke-Heartbeat $selfUsage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'governor-task'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; reviewerShare = .8; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 1 } } -NoAcknowledge
  $selfEvent = Assert-Event $selfCycle 'USAGE_BURN' 'governor'
  Assert-Equal $selfEvent.CostImpact 'unknown' 'Usage volume was incorrectly converted into model cost.'
  Assert-Equal $selfEvent.QuotaImpact 'unknown' 'Usage volume was incorrectly converted into quota impact.'
  $selfPlan = Get-InterventionPayload (Invoke-Intervention $selfUsage 'plan' -EventId $selfEvent.EventId -Target 'governor-task' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $selfPlan.decision 'failed_closed' 'Governor self-target was not rejected.'
  Assert-Equal $selfPlan.reason 'self_target_forbidden' 'Governor self-target rejection was not explicit.'
  Assert-True (-not $selfPlan.userActionRequired -and $selfPlan.routineFailureHandling -eq 'governor_local_fail_closed') 'Self-target failure was incorrectly assigned to the user.'
  Assert-Equal @((Get-Content -Raw $selfUsage.State | ConvertFrom-Json).outbox).Count 0 'Self-origin event remained eligible for repeat delivery.'

  $governorUsageLocal = New-Case 'governor-usage-local'
  Assert-Silent (Invoke-Heartbeat $governorUsageLocal @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'governor-task'; totalTokens = 10000; ratePerMinute = 5000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 0 } }) 'Governor-local usage baseline.'
  $governorUsageCycle = Invoke-Heartbeat $governorUsageLocal @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'governor-task'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; reviewerShare = .8; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 1 } } -NoAcknowledge
  $governorUsageEvent = Assert-Event $governorUsageCycle 'USAGE_BURN' 'governor'
  $unrelatedPlan = Get-InterventionPayload (Invoke-Intervention $governorUsageLocal 'plan' -EventId $governorUsageEvent.EventId -Target 'unrelated-task' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $unrelatedPlan.reason 'governor_usage_uncorroborated' 'Governor usage alone was allowed to wake another task.'
  Assert-Equal $unrelatedPlan.nextHostAction 'apply_governor_local_throttle_only' 'Uncorroborated Governor usage did not remain an autonomous local action.'
  Assert-True (-not $unrelatedPlan.userActionRequired) 'Uncorroborated Governor usage became a user chore.'

  $corroboratedUsage = New-Case 'governor-usage-corroborated'
  Assert-Silent (Invoke-Heartbeat $corroboratedUsage @{
      agents = @(@{ id = 'affected-task'; owner = 'affected-task'; active = $true; progressHash = 'same'; totalTokens = 1000 })
      usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'affected-task'; totalTokens = 10000; ratePerMinute = 5000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 0 }
    }) 'Corroborated usage baseline.'
  $corroboratedCycle = Invoke-Heartbeat $corroboratedUsage @{
      agents = @(@{ id = 'affected-task'; owner = 'affected-task'; active = $true; progressHash = 'same'; totalTokens = 60000; tokensSinceMeaningfulChange = 59000; repeatedEquivalentActions = 6; minutesSinceMeaningfulChange = 30 })
      usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'affected-task'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; reviewerShare = .8; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 1 }
    } -NoAcknowledge
  $corroboratedEvents = @(Get-Events $corroboratedCycle)
  $corroboratedUsageEvent = @($corroboratedEvents | Where-Object { $_.Type -eq 'USAGE_BURN' })[0]
  $corroboratingStallEvent = @($corroboratedEvents | Where-Object { $_.Type -eq 'AGENT_STALL' })[0]
  $corroboratedPlan = Get-InterventionPayload (Invoke-Intervention $corroboratedUsage 'plan' -EventId $corroboratedUsageEvent.EventId -CorroboratingEventId $corroboratingStallEvent.EventId -Target 'affected-task' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $corroboratedPlan.decision 'send' 'Same-subject same-window corroboration did not authorize the affected task.'

  # A task report is advisory; only later independent evidence resolves the event.
  $postcondition = New-Case 'intervention-postcondition'
  Assert-Silent (Invoke-Heartbeat $postcondition @{ agents = @(@{ id = 'postcondition-worker'; active = $true; progressHash = 'a'; totalTokens = 1000 }) }) 'Postcondition baseline.'
  $postCycle = Invoke-Heartbeat $postcondition @{ agents = @(@{ id = 'postcondition-worker'; active = $true; progressHash = 'a'; totalTokens = 60000; tokensSinceMeaningfulChange = 59000; repeatedEquivalentActions = 6; minutesSinceMeaningfulChange = 30 }) } -NoAcknowledge
  $postEvent = Assert-Event $postCycle 'AGENT_STALL' 'governor'
  $postPlan = Get-InterventionPayload (Invoke-Intervention $postcondition 'plan' -EventId $postEvent.EventId -Target 'postcondition-worker' -Generation 'generation-1' -Governor 'governor-task')
  Assert-FailedSafely (Invoke-Intervention $postcondition 'verify' -InterventionId $postPlan.interventionId -Version 1 -Target 'postcondition-worker' -Generation 'generation-1' -VerificationSource 'host_inventory' -VerificationResult 'resolved') 'heartbeat_intervention_transition_invalid' 'A queued intervention was resolved before remediation.'
  $postClaim = Get-InterventionPayload (Invoke-Intervention $postcondition 'claim' -InterventionId $postPlan.interventionId -Version 1 -Target 'postcondition-worker' -Generation 'generation-1' -Governor 'governor-task')
  Assert-FailedSafely (Invoke-Intervention $postcondition 'verify' -InterventionId $postPlan.interventionId -Version 1 -Target 'postcondition-worker' -Generation 'generation-1' -VerificationSource 'host_inventory' -VerificationResult 'resolved') 'heartbeat_intervention_transition_invalid' 'A send-claimed intervention was resolved before delivery.'
  $postTransport = Get-InterventionPayload (Invoke-Intervention $postcondition 'transport' -InterventionId $postPlan.interventionId -Version 1 -ClaimToken $postClaim.claimToken -TransportResult 'accepted')
  Assert-Equal $postTransport.state 'awaiting_task_ack' 'Accepted transport was treated as task acknowledgement.'
  Assert-FailedSafely (Invoke-Intervention $postcondition 'response' -InterventionId $postPlan.interventionId -Version 1 -Target 'wrong-worker' -Generation 'generation-1' -TaskResponse 'outcome_reported') 'heartbeat_intervention_reporter_mismatch' 'A different task advanced the intervention.'
  $reported = Get-InterventionPayload (Invoke-Intervention $postcondition 'response' -InterventionId $postPlan.interventionId -Version 1 -Target 'postcondition-worker' -Generation 'generation-1' -TaskResponse 'outcome_reported')
  Assert-Equal $reported.state 'verification_pending' 'Task outcome did not enter independent verification.'
  $publicEngine = Invoke-RawModule @('-Action', 'intervention-verify', '-StatePath', $postcondition.State, '-InterventionId', $postPlan.interventionId, '-InterventionVersion', '1', '-TargetId', 'postcondition-worker', '-TargetGeneration', 'generation-1', '-VerificationSource', 'heartbeat_engine', '-VerificationResult', 'resolved')
  Assert-True ($publicEngine.ExitCode -ne 0) 'The public verification boundary accepted heartbeat_engine impersonation.'
  $reportedState = Get-Content -Raw $postcondition.State | ConvertFrom-Json
  Assert-True (@($reportedState.conditions.PSObject.Properties.Value | Where-Object { $_.type -eq 'AGENT_STALL' -and $_.open }).Count -eq 1) 'Task self-report resolved the detector condition.'
  $resolutionCycle = Invoke-Heartbeat $postcondition @{ agents = @(@{ id = 'postcondition-worker'; active = $true; progressHash = 'b'; totalTokens = 61000; tokensSinceMeaningfulChange = 0; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }
  $resolutionEvents = @(Get-Events $resolutionCycle | Where-Object { $_.Event -eq 'HEARTBEAT_RESOLVED' -and $_.Type -eq 'AGENT_STALL' })
  Assert-Equal $resolutionEvents.Count 1 'Independent observed recovery did not resolve the stall.'
  Assert-True ([bool]$resolutionEvents[0].ReleaseNoticeEligible) 'An acknowledged temporary restriction did not become release-notice eligible.'
  $resolvedIntervention = @((Get-Content -Raw $postcondition.State | ConvertFrom-Json).interventions | Where-Object { $_.interventionId -eq $postPlan.interventionId })[0]
  Assert-Equal $resolvedIntervention.state 'verified_resolved' 'Independent detector recovery did not resolve the intervention.'
  Assert-Equal $resolvedIntervention.verificationSource 'heartbeat_engine' 'Task self-report was mistaken for independent verification.'

  # A pass from a different environment identity cannot resolve a regression.
  $testEnvironment = New-Case 'test-environment-binding'
  Assert-Silent (Invoke-Heartbeat $testEnvironment @{ tests = @(@{ name = 'environment-bound-test'; owner = 'test-owner'; status = 'passed'; commit = 'aaaaaaaa'; buildId = 'suite-one'; environmentStatuses = @{ machineA = 'passed' }; repairAttempts = 0; failureCount = 0 }) }) 'Environment-bound test baseline.'
  $environmentFailure = Invoke-Heartbeat $testEnvironment @{ tests = @(@{ name = 'environment-bound-test'; owner = 'test-owner'; status = 'failed'; commit = 'bbbbbbbb'; buildId = 'suite-one'; environmentStatuses = @{ machineA = 'failed' }; repairAttempts = 1; failureCount = 1 }) } -NoAcknowledge
  $environmentEvent = Assert-Event $environmentFailure 'TEST_REGRESSION' 'governor'
  $environmentPlan = Get-InterventionPayload (Invoke-Intervention $testEnvironment 'plan' -EventId $environmentEvent.EventId -Target 'test-owner' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $environmentPlan.decision 'send' 'Environment-bound regression was not planned.'
  [void](Invoke-Heartbeat $testEnvironment @{ tests = @(@{ name = 'environment-bound-test'; owner = 'test-owner'; status = 'passed'; commit = 'cccccccc'; buildId = 'suite-one'; environmentStatuses = @{ machineB = 'passed' }; repairAttempts = 0; failureCount = 0 }) })
  $environmentState = Get-Content -Raw $testEnvironment.State | ConvertFrom-Json
  Assert-True (@($environmentState.conditions.PSObject.Properties.Value | Where-Object { $_.type -eq 'TEST_REGRESSION' -and $_.open }).Count -eq 1) 'A pass from an incompatible environment resolved the prior regression.'
  $environmentResolution = Invoke-Heartbeat $testEnvironment @{ tests = @(@{ name = 'environment-bound-test'; owner = 'test-owner'; status = 'passed'; commit = 'dddddddd'; buildId = 'suite-one'; environmentStatuses = @{ machineA = 'passed' }; repairAttempts = 0; failureCount = 0 }) }
  Assert-Equal @((Get-Events $environmentResolution) | Where-Object { $_.Event -eq 'HEARTBEAT_RESOLVED' -and $_.Type -eq 'TEST_REGRESSION' }).Count 1 'Compatible environment recovery did not resolve the regression.'

  # Only a definite send failure receives one retry.
  $retryBudget = New-Case 'intervention-retry-budget'
  $retryCycle = Invoke-Heartbeat $retryBudget @{ tasks = @(@{ id = 'retry-item'; owner = 'retry-target'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false }) } -NoAcknowledge
  $retryEvent = @(Get-Events $retryCycle | Where-Object { $_.Event -eq 'HEARTBEAT_EVENT' })[0]
  $retryPlan = Get-InterventionPayload (Invoke-Intervention $retryBudget 'plan' -EventId $retryEvent.EventId -Target 'retry-target' -Generation 'generation-1' -Governor 'governor-task')
  $retryClaim1 = Get-InterventionPayload (Invoke-Intervention $retryBudget 'claim' -InterventionId $retryPlan.interventionId -Version 1 -Target 'retry-target' -Generation 'generation-1' -Governor 'governor-task')
  $retryFailure1 = Get-InterventionPayload (Invoke-Intervention $retryBudget 'transport' -InterventionId $retryPlan.interventionId -Version 1 -ClaimToken $retryClaim1.claimToken -TransportResult 'definite_failure')
  Assert-Equal $retryFailure1.state 'retry_queued' 'A definite first failure did not queue one retry.'
  $retryClaim2 = Get-InterventionPayload (Invoke-Intervention $retryBudget 'claim' -InterventionId $retryPlan.interventionId -Version 1 -Target 'retry-target' -Generation 'generation-1' -Governor 'governor-task')
  $retryFailure2 = Get-InterventionPayload (Invoke-Intervention $retryBudget 'transport' -InterventionId $retryPlan.interventionId -Version 1 -ClaimToken $retryClaim2.claimToken -TransportResult 'definite_failure')
  Assert-Equal $retryFailure2.state 'undelivered' 'Second definite failure did not exhaust the retry budget.'
  Assert-Equal @((Get-Content -Raw $retryBudget.State | ConvertFrom-Json).interventions)[0].attempts 2 'Intervention exceeded its two-attempt bound.'

  # Legacy Heartbeat state upgrades in place on the next mutating cycle.
  $migration = New-Case 'intervention-schema-migration'
  Assert-Silent (Invoke-Heartbeat $migration @{ agents = @() }) 'Schema migration baseline.'
  $legacyState = Get-Content -Raw $migration.State | ConvertFrom-Json
  $legacyState.schema = 4
  $legacyState.PSObject.Properties.Remove('interventions')
  $legacyState.health.PSObject.Properties.Remove('acknowledgedEvents')
  $legacyState.health.PSObject.Properties.Remove('failedCycles')
  [IO.File]::WriteAllText($migration.State, ($legacyState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  Assert-Silent (Invoke-Heartbeat $migration @{ agents = @() }) 'Schema 4 migration cycle.'
  $migratedState = Get-Content -Raw $migration.State | ConvertFrom-Json
  Assert-Equal $migratedState.schema 7 'Schema 4 state did not migrate to schema 7.'
  Assert-True ($migratedState.health.acknowledgedEvents -eq 0 -and $migratedState.health.failedCycles -eq 0) 'Schema 4 migration omitted Governor progress counters.'

  $schemaFive = New-Case 'schema-five-migration'
  Assert-Silent (Invoke-Heartbeat $schemaFive @{ agents = @() }) 'Schema 5 migration baseline.'
  $schemaFiveState = Get-Content -Raw $schemaFive.State | ConvertFrom-Json
  $schemaFiveState.schema = 6
  $schemaFiveState.health.PSObject.Properties.Remove('acknowledgedEvents')
  $schemaFiveState.health.PSObject.Properties.Remove('failedCycles')
  [IO.File]::WriteAllText($schemaFive.State, ($schemaFiveState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  Assert-Silent (Invoke-Heartbeat $schemaFive @{ agents = @() }) 'Schema 6 migration cycle.'
  Assert-Equal (Get-Content -Raw $schemaFive.State | ConvertFrom-Json).schema 7 'Schema 6 state did not migrate to schema 7.'

  $legacyQueued = New-Case 'schema-six-queued-intervention'
  $legacyQueuedCycle = Invoke-Heartbeat $legacyQueued @{ tasks = @(@{ id = 'legacy-queued-target'; owner = 'legacy-queued-target'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false }) } -NoAcknowledge
  $legacyQueuedEvent = @(Get-Events $legacyQueuedCycle | Where-Object { $_.Event -eq 'HEARTBEAT_EVENT' })[0]
  $legacyQueuedPlan = Get-InterventionPayload (Invoke-Intervention $legacyQueued 'plan' -EventId $legacyQueuedEvent.EventId -Target 'legacy-queued-target' -Generation 'legacy-generation' -Governor 'old-governor')
  $legacyQueuedState = Get-Content -Raw $legacyQueued.State | ConvertFrom-Json
  $legacyQueuedState.schema = 6
  $legacyQueuedRecord = @($legacyQueuedState.interventions | Where-Object { $_.interventionId -eq $legacyQueuedPlan.interventionId })[0]
  $legacyQueuedRecord.PSObject.Properties.Remove('governorHash')
  $legacyQueuedRecord.PSObject.Properties.Remove('claimExpiresAt')
  [IO.File]::WriteAllText($legacyQueued.State, ($legacyQueuedState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  $legacyQueuedList = Get-InterventionPayload (Invoke-Intervention $legacyQueued 'list' -Governor 'replacement-governor')
  Assert-Equal $legacyQueuedList.count 1 'A schema-6 queued intervention was orphaned during migration.'
  Assert-Equal $legacyQueuedList.interventions[0].permittedNextAction 'claim' 'A provably unsent legacy intervention was not resumable.'
  $legacyQueuedClaim = Get-InterventionPayload (Invoke-Intervention $legacyQueued 'claim' -InterventionId $legacyQueuedPlan.interventionId -Version 1 -Target 'legacy-queued-target' -Generation 'legacy-generation' -Governor 'replacement-governor')
  Assert-Equal $legacyQueuedClaim.state 'send_claimed' 'A matching replacement Governor could not adopt an unsent legacy intervention.'

  $legacyClaimed = New-Case 'schema-six-claimed-intervention'
  $legacyClaimedCycle = Invoke-Heartbeat $legacyClaimed @{ tasks = @(@{ id = 'legacy-claimed-target'; owner = 'legacy-claimed-target'; status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false }) } -NoAcknowledge
  $legacyClaimedEvent = @(Get-Events $legacyClaimedCycle | Where-Object { $_.Event -eq 'HEARTBEAT_EVENT' })[0]
  $legacyClaimedPlan = Get-InterventionPayload (Invoke-Intervention $legacyClaimed 'plan' -EventId $legacyClaimedEvent.EventId -Target 'legacy-claimed-target' -Generation 'legacy-generation' -Governor 'old-governor')
  [void](Get-InterventionPayload (Invoke-Intervention $legacyClaimed 'claim' -InterventionId $legacyClaimedPlan.interventionId -Version 1 -Target 'legacy-claimed-target' -Generation 'legacy-generation' -Governor 'old-governor'))
  $legacyClaimedState = Get-Content -Raw $legacyClaimed.State | ConvertFrom-Json
  $legacyClaimedState.schema = 6
  $legacyClaimedRecord = @($legacyClaimedState.interventions | Where-Object { $_.interventionId -eq $legacyClaimedPlan.interventionId })[0]
  $legacyClaimedRecord.PSObject.Properties.Remove('governorHash')
  $legacyClaimedRecord.PSObject.Properties.Remove('claimExpiresAt')
  [IO.File]::WriteAllText($legacyClaimed.State, ($legacyClaimedState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  $legacyClaimedList = Get-InterventionPayload (Invoke-Intervention $legacyClaimed 'list' -Governor 'replacement-governor')
  Assert-Equal $legacyClaimedList.count 1 'A schema-6 claimed intervention disappeared during migration.'
  Assert-Equal $legacyClaimedList.interventions[0].state 'delivery_unknown' 'A legacy claimed send was incorrectly made retryable.'
  Assert-Equal $legacyClaimedList.interventions[0].permittedNextAction 'reconcile_delivery_without_retry' 'A legacy ambiguous delivery did not remain visible for reconciliation.'
  Assert-Equal (Get-Content -Raw $legacyClaimed.State | ConvertFrom-Json).schema 7 'Intervention-list did not persist schema-6 migration.'

  $legacyUsage = New-Case 'legacy-usage-migration'
  Assert-Silent (Invoke-Heartbeat $legacyUsage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'legacy-usage-task'; totalTokens = 10000; ratePerMinute = 5000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 0 } }) 'Legacy usage baseline.'
  $legacyUsageCycle = Invoke-Heartbeat $legacyUsage @{ usage = @{ owner = 'governor'; role = 'governor'; dominantThread = 'legacy-usage-task'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'same'; completedCycles = 1; stateChanges = 0; acknowledgedEvents = 0; failedCycles = 0; duplicateRuns = 1 } } -NoAcknowledge
  $legacyUsageEvent = Assert-Event $legacyUsageCycle 'USAGE_BURN' 'governor'
  $legacyUsageState = Get-Content -Raw $legacyUsage.State | ConvertFrom-Json
  $legacyUsageState.schema = 4
  $legacyUsageState.PSObject.Properties.Remove('interventions')
  foreach ($entry in @($legacyUsageState.outbox)) {
    $entry.PSObject.Properties.Remove('ownerHash')
    $entry.PSObject.Properties.Remove('governorOrigin')
  }
  [IO.File]::WriteAllText($legacyUsage.State, ($legacyUsageState | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
  $legacyUsagePlan = Get-InterventionPayload (Invoke-Intervention $legacyUsage 'plan' -EventId $legacyUsageEvent.EventId -Target 'legacy-usage-task' -Generation 'generation-1' -Governor 'governor-task')
  Assert-Equal $legacyUsagePlan.reason 'governor_usage_uncorroborated' 'Legacy usage outbox upgrade permitted an uncorroborated task wake.'

  # An abandoned named mutex is recovered without losing the cycle.
  $abandoned = New-Case 'abandoned-mutex'
  $abandonedInput = Join-Path $abandoned.Path 'input.json'
  $abandonedData = @{ schemaVersion = 1; capturedAtUtc = $abandoned.BaseTime.ToString('o'); runId = 'abandoned-run'; origin = 'test'; forceCadence = $true; collectorCoverage = @{ agent_stall = 'observed' }; agents = @() }
  [IO.File]::WriteAllText($abandonedInput, ($abandonedData | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
  $mutexName = 'Global\ChronosHeartbeat-' + (Get-TestHash (Get-TestCanonicalStateIdentity $abandoned.State)).Substring(0, 24)
  $holder = New-Object Threading.Mutex($false, $mutexName)
  try {
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$m=New-Object Threading.Mutex(`$false,'$mutexName');[void]`$m.WaitOne();[Environment]::Exit(0)"))
    $child = Start-HiddenPowerShell $encodedCommand
    $child.WaitForExit()
    $child.Dispose()
    $abandonedResult = Invoke-RawModule @('-InputPath', $abandonedInput, '-StatePath', $abandoned.State)
    Assert-Silent $abandonedResult 'Abandoned mutex recovery.'
  } finally { $holder.Dispose() }

  # Bounded retention and privacy remain intact under many actionable records.
  $bounded = New-Case 'bounded'
  foreach ($batch in 1..5) {
    $taskRecords = @()
    foreach ($index in 1..64) { $taskRecords += @{ id = ('z-{0}-{1}' -f $batch, $index); status = 'todo'; dependencyStatus = 'unknown'; ageHours = 48; assigned = $false } }
    $boundedResult = Invoke-Heartbeat $bounded @{ tasks = $taskRecords }
    if ($batch -lt 5) { Assert-Equal $boundedResult.ExitCode 0 'Bounded active-condition batch.' }
  }
  Assert-FailedSafely $boundedResult 'heartbeat_condition_capacity' 'Active-condition capacity fails closed.'
  $boundedState = Get-Content -Raw $bounded.State | ConvertFrom-Json
  Assert-True (@($boundedState.conditions.PSObject.Properties).Count -le 256) 'Condition retention exceeded its bound.'
  Assert-True (@($boundedState.events).Count -le 50) 'Event retention exceeded its bound.'
  Assert-True ((Get-Item $bounded.State).Length -le 262144) 'Heartbeat state exceeded its byte limit.'
  Assert-True ((Get-Content -Raw $bounded.State) -notmatch 'z-5-64') 'Raw task identifiers were persisted.'

  # The v0.8.6 CWD-scoped default is imported into the stable default without
  # modifying the source, even when the source requires schema migration.
  $savedUserProfile = $env:USERPROFILE
  $savedHomeEnvironment = $env:HOME
  $savedComputerName = $env:COMPUTERNAME
  $defaultUpgradeHome = Join-Path $root 'default-upgrade-home'
  $env:USERPROFILE = $defaultUpgradeHome
  $env:HOME = $defaultUpgradeHome
  $env:COMPUTERNAME = 'CHRONOS-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
  $defaultCodexHome = Join-Path $defaultUpgradeHome '.codex'
  $priorDefaultScope = '{0}|{1}|{2}' -f $env:COMPUTERNAME, ([IO.Path]::GetFullPath($defaultCodexHome)), ([IO.Path]::GetFullPath((Get-Location).Path))
  $currentDefaultScope = '{0}|{1}' -f $env:COMPUTERNAME, ([IO.Path]::GetFullPath($defaultCodexHome))
  $priorDefaultHash = Get-TestStableHash $priorDefaultScope
  $currentDefaultHash = Get-TestStableHash $currentDefaultScope
  $priorDefaultDirectory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' $priorDefaultHash)
  $priorDefaultState = Join-Path $priorDefaultDirectory 'heartbeat-state.json'
  $currentDefaultDirectory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' $currentDefaultHash)
  $currentDefaultState = Join-Path $currentDefaultDirectory 'heartbeat-state.json'
  $defaultUpgradeInput = Join-Path $root 'default-upgrade-input.json'
  [IO.File]::WriteAllText($defaultUpgradeInput, '{"schemaVersion":1,"capturedAtUtc":"2026-01-01T00:00:00Z","sourceEpoch":"default-upgrade","sourceSequence":1,"runId":"default-upgrade-1","origin":"test","forceCadence":true,"collectorCoverage":{"agent_stall":"observed"},"agents":[]}', [Text.UTF8Encoding]::new($false))
  try {
    $seedDefault = Invoke-RawModule @('-Action', 'cycle', '-InputPath', $defaultUpgradeInput, '-StatePath', $priorDefaultState, '-Scope', $priorDefaultScope)
    Assert-Equal $seedDefault.ExitCode 0 'Could not seed the v0.8.6 default namespace.'
    $priorDefaultData = Get-Content -Raw $priorDefaultState | ConvertFrom-Json
    $priorDefaultData.schema = 6
    [IO.File]::WriteAllText($priorDefaultState, ($priorDefaultData | ConvertTo-Json -Compress -Depth 16), [Text.UTF8Encoding]::new($false))
    $priorDefaultHashBefore = (Get-FileHash -LiteralPath $priorDefaultState -Algorithm SHA256).Hash
    $priorDefaultTimestampBefore = (Get-Item -LiteralPath $priorDefaultState).LastWriteTimeUtc
    $defaultUpgradeStatus = Invoke-RawModule @('-Action', 'status')
    Assert-Equal $defaultUpgradeStatus.ExitCode 0 'Default v0.8.6 namespace import failed.'
    Assert-True ($defaultUpgradeStatus.Text -match 'stateStoreMigration=prior_v2_default_state_imported') 'Default v0.8.6 namespace was not discovered.'
    Assert-True (Test-Path -LiteralPath $currentDefaultState -PathType Leaf) 'Stable default state was not created.'
    Assert-Equal (Get-Content -Raw $currentDefaultState | ConvertFrom-Json).scopeHash $currentDefaultHash 'Imported state did not rebind only in the new namespace.'
    Assert-Equal (Get-Content -Raw $currentDefaultState | ConvertFrom-Json).schema 7 'Imported state was not upgraded in the destination.'
    Assert-Equal (Get-Content -Raw $priorDefaultState | ConvertFrom-Json).schema 6 'Prior state was upgraded in place.'
    Assert-Equal (Get-FileHash -LiteralPath $priorDefaultState -Algorithm SHA256).Hash $priorDefaultHashBefore 'Prior state content changed during import.'
    Assert-Equal (Get-Item -LiteralPath $priorDefaultState).LastWriteTimeUtc $priorDefaultTimestampBefore 'Prior state timestamp changed during import.'
  } finally {
    Remove-Item -LiteralPath $priorDefaultDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $currentDefaultDirectory -Recurse -Force -ErrorAction SilentlyContinue
    $env:USERPROFILE = $savedUserProfile
    $env:HOME = $savedHomeEnvironment
    $env:COMPUTERNAME = $savedComputerName
  }

  # A protected v0.8.2 default directory cannot strand a later sandbox
  # identity. The versioned namespace starts clean and reports the skipped
  # migration without taking ownership of or changing the prior directory.
  $upgradeScope = 'heartbeat-upgrade-' + [guid]::NewGuid().ToString('N')
  $upgradeHash = Get-TestStableHash $upgradeScope
  $priorUpgradeDirectory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat' $upgradeHash)
  $priorUpgradeState = Join-Path $priorUpgradeDirectory 'heartbeat-state.json'
  $savedLocalAppData = $env:LOCALAPPDATA
  $env:LOCALAPPDATA = Join-Path $root 'upgrade-local-appdata'
  $legacyUpgradeDirectory = Join-Path $env:LOCALAPPDATA (Join-Path 'Chronos\Heartbeat' $upgradeHash)
  $legacyUpgradeState = Join-Path $legacyUpgradeDirectory 'heartbeat-state.json'
  $newUpgradeDirectory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' $upgradeHash)
  $newUpgradeState = Join-Path $newUpgradeDirectory 'heartbeat-state.json'
  $upgradeSeedState = Join-Path $root 'upgrade-seed-state.json'
  $upgradeInput = Join-Path $root 'upgrade-input.json'
  [IO.File]::WriteAllText($upgradeInput, '{"schemaVersion":1,"capturedAtUtc":"2026-01-01T00:00:00Z","sourceEpoch":"upgrade","sourceSequence":1,"runId":"upgrade-1","origin":"test","forceCadence":true,"collectorCoverage":{"agent_stall":"observed"},"agents":[]}', [Text.UTF8Encoding]::new($false))
  $priorSeed = Invoke-RawModule @('-Action', 'cycle', '-InputPath', $upgradeInput, '-StatePath', $upgradeSeedState, '-Scope', $upgradeScope)
  Assert-Equal $priorSeed.ExitCode 0 'Could not seed prior default Heartbeat state.'
  New-Item -ItemType Directory -Path $priorUpgradeDirectory -Force | Out-Null
  Copy-Item -LiteralPath $upgradeSeedState -Destination $priorUpgradeState -Force
  New-Item -ItemType Directory -Path $legacyUpgradeDirectory -Force | Out-Null
  Copy-Item -LiteralPath $upgradeSeedState -Destination $legacyUpgradeState -Force
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
  } catch {
    $denyEffective = $true
  }
  try {
    $upgradeStatus = Invoke-RawModule @('-Action', 'status', '-Scope', $upgradeScope)
    Assert-Equal $upgradeStatus.ExitCode 0 'Inaccessible prior default state blocked new Heartbeat status.'
    $expectedMigration = if ($denyEffective) { 'prior_state_unavailable_new_root' } else { 'prior_temp_state_imported' }
    $expectedDisposition = if ($denyEffective) { 'unavailable_preserved' } else { 'read_only_imported' }
    Assert-True ($upgradeStatus.Text -match ('stateStoreMigration=' + $expectedMigration)) "Prior-state handling did not match the host's enforced ACL semantics. Expected $expectedMigration."
    Assert-True ($upgradeStatus.Text -match ('priorStateDisposition=' + $expectedDisposition)) "Prior-state disposition did not match the host's enforced ACL semantics. Expected $expectedDisposition."
    Assert-True ($upgradeStatus.Text -match 'priorStateWriteAttempted=false') 'Prior-state handling reported a legacy write attempt.'
    $upgradeCycle = Invoke-RawModule @('-Action', 'cycle', '-InputPath', $upgradeInput, '-Scope', $upgradeScope)
    Assert-Equal $upgradeCycle.ExitCode 0 'Inaccessible prior default state blocked a live Heartbeat cycle.'
    Assert-True (Test-Path -LiteralPath $newUpgradeState -PathType Leaf) 'Live Heartbeat cycle did not persist in the versioned namespace.'
    Assert-True ((Get-Content -Raw -LiteralPath $newUpgradeState | ConvertFrom-Json).scopeHash -eq $upgradeHash) 'Versioned state lost the stable scope identity.'
  } finally {
    Set-Acl -LiteralPath $priorUpgradeDirectory -AclObject $priorAcl -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $priorUpgradeDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $legacyUpgradeDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $newUpgradeDirectory -Recurse -Force -ErrorAction SilentlyContinue
    $env:LOCALAPPDATA = $savedLocalAppData
  }

  # An accessible empty prior scope is not mislabeled as inaccessible state.
  $emptyPriorScope = 'heartbeat-empty-prior-' + [guid]::NewGuid().ToString('N')
  $emptyPriorHash = Get-TestStableHash $emptyPriorScope
  $emptyPriorDirectory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat' $emptyPriorHash)
  $emptyPriorV2Directory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' $emptyPriorHash)
  New-Item -ItemType Directory -Path $emptyPriorDirectory -Force | Out-Null
  try {
    $emptyPriorStatus = Invoke-RawModule @('-Action', 'status', '-Scope', $emptyPriorScope)
    Assert-Equal $emptyPriorStatus.ExitCode 0 'Accessible empty prior scope blocked Heartbeat status.'
    Assert-True ($emptyPriorStatus.Text -match 'stateStoreMigration=namespace_v2_new_root') 'Accessible empty prior scope was mislabeled as inaccessible state.'
    Assert-True ($emptyPriorStatus.Text -match 'priorStateDisposition=not_found') 'Accessible empty prior scope did not report prior state as absent.'
    Assert-True ($emptyPriorStatus.Text -match 'priorStateWriteAttempted=false') 'Empty prior-scope handling reported a legacy write attempt.'
  } finally {
    Remove-Item -LiteralPath $emptyPriorDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $emptyPriorV2Directory -Recurse -Force -ErrorAction SilentlyContinue
  }

  # A junction at the authoritative prior scope cannot redirect migration to
  # otherwise valid state outside the prior Heartbeat namespace.
  $priorJunctionScope = 'heartbeat-prior-junction-' + [guid]::NewGuid().ToString('N')
  $priorJunctionHash = Get-TestStableHash $priorJunctionScope
  $priorJunctionDirectory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat' $priorJunctionHash)
  $priorJunctionV2Directory = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'Chronos\Heartbeat-v2' $priorJunctionHash)
  $priorJunctionTarget = Join-Path $root 'prior-junction-target'
  $priorJunctionSeed = Join-Path $root 'prior-junction-seed.json'
  $priorJunctionInput = Join-Path $root 'prior-junction-input.json'
  [IO.File]::WriteAllText($priorJunctionInput, '{"schemaVersion":1,"capturedAtUtc":"2026-01-01T00:00:00Z","sourceEpoch":"prior-junction","sourceSequence":1,"runId":"prior-junction-1","origin":"test","forceCadence":true,"collectorCoverage":{"agent_stall":"observed"},"agents":[]}', [Text.UTF8Encoding]::new($false))
  Assert-Equal (Invoke-RawModule @('-Action', 'cycle', '-InputPath', $priorJunctionInput, '-StatePath', $priorJunctionSeed, '-Scope', $priorJunctionScope)).ExitCode 0 'Could not seed prior-junction state.'
  New-Item -ItemType Directory -Path $priorJunctionTarget -Force | Out-Null
  Copy-Item -LiteralPath $priorJunctionSeed -Destination (Join-Path $priorJunctionTarget 'heartbeat-state.json') -Force
  New-Item -ItemType Directory -Path (Split-Path -Parent $priorJunctionDirectory) -Force | Out-Null
  New-Item -ItemType Junction -Path $priorJunctionDirectory -Target $priorJunctionTarget | Out-Null
  try {
    $priorJunctionStatus = Invoke-RawModule @('-Action', 'status', '-Scope', $priorJunctionScope)
    Assert-Equal $priorJunctionStatus.ExitCode 0 'Prior-state junction blocked safe Heartbeat initialization.'
    Assert-True ($priorJunctionStatus.Text -match 'stateStoreMigration=prior_state_invalid_rebuilt') 'Prior-state junction was not rejected as invalid.'
    Assert-True ($priorJunctionStatus.Text -match 'priorStateDisposition=invalid_preserved') 'Prior-state junction did not preserve the invalid authoritative source.'
    Assert-True ($priorJunctionStatus.Text -match 'priorStateWriteAttempted=false') 'Prior-state junction handling reported a legacy write attempt.'
  } finally {
    if (Test-Path -LiteralPath $priorJunctionDirectory) { [IO.Directory]::Delete($priorJunctionDirectory) }
    Remove-Item -LiteralPath $priorJunctionTarget -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $priorJunctionV2Directory -Recurse -Force -ErrorAction SilentlyContinue
  }

  # The wrapper status path is concise and does not need an input snapshot.
  $emptyStatus = Invoke-RawModule @('-Action', 'status', '-StatePath', (Join-Path $root 'empty-status.json'))
  Assert-Equal $emptyStatus.ExitCode 0 'Empty status exit code.'
  Assert-True ($emptyStatus.Text -match '^CHRONOS HEARTBEATS engine=healthy activeTypes=8') 'Empty status headline.'

  'Chronos heartbeat deterministic validations passed.'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
