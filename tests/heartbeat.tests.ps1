$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$wrapper = Join-Path $repo 'plugins\chronos\skills\chronos\scripts\chronos.ps1'
$module = Join-Path $repo 'plugins\chronos\skills\chronos\scripts\heartbeat.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('chronos-heartbeat-tests-' + [guid]::NewGuid().ToString('N'))
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
  $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $module @Arguments 2>&1)
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output); Text = ($output -join "`n") }
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

  # Agent stall: baseline, transition, dedupe, escalation, coverage, resolution, and canonical worker IDs.
  $case = New-Case 'agent'
  Assert-Silent (Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-a'; totalTokens = 1000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) }) 'Normal agent progress.'
  $warning = Invoke-Heartbeat $case @{ agents = @(@{ id = '/root/worker'; owner = '/root/dev'; owningSolThread = '/root/dev'; active = $true; progressHash = 'progress-a'; totalTokens = 31000; tokensSinceMeaningfulChange = 30000; repeatedEquivalentActions = 4; minutesSinceMeaningfulChange = 25 }) }
  $warningEvent = Assert-Event $warning 'AGENT_STALL' 'governor'
  Assert-Equal $warningEvent.Owner '/root/dev' 'Agent owner must remain a Governor triage hint.'
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
  Assert-Resolution (Invoke-Heartbeat $cadence @{ agents = @(@{ id = 'cadence-agent'; active = $true; progressHash = 'b'; totalTokens = 41000; repeatedEquivalentActions = 0; minutesSinceMeaningfulChange = 1 }) } -At ($t1.AddMinutes(6)) -NoForce) 'AGENT_STALL' 'governor'

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

  # Usage burn: high expected work stays quiet; abnormal no-progress velocity alerts.
  $usage = New-Case 'usage'
  Assert-Silent (Invoke-Heartbeat $usage @{ usage = @{ owner = 'governor'; dominantThread = 'thread-usage'; totalTokens = 100000; ratePerMinute = 12000; baselineRatePerMinute = 5000; meaningfulProgress = $true; progressHash = 'usage-a'; reviewerShare = .2 } }) 'High usage with progress.'
  $usageEvent = Assert-Event (Invoke-Heartbeat $usage @{ usage = @{ owner = 'governor'; dominantThread = 'thread-usage'; totalTokens = 300000; ratePerMinute = 18000; baselineRatePerMinute = 5000; meaningfulProgress = $false; progressHash = 'usage-a'; reviewerShare = .91; projectedExhaustionMinutes = 30 } }) 'USAGE_BURN' 'governor'
  Assert-True (($usageEvent.Evidence -join ' ') -match 'reviewerShare=0.91') 'Usage evidence did not identify reviewer share.'

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
  $selfHealth = New-Case 'self-health'
  $selfTime = [DateTimeOffset]::UtcNow
  Assert-Event (Invoke-Heartbeat $selfHealth @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 2; runtimeSeconds = 31 } } -At $selfTime) 'HEARTBEAT_SELF_HEALTH' 'governor' | Out-Null
  Assert-Silent (Invoke-Heartbeat $selfHealth @{ heartbeatActivity = @{ origin = 'host'; schedulerDuplicates = 2; runtimeSeconds = 31 } } -At ($selfTime.AddSeconds(1)) -NoForce) 'Self-health backoff.'
  $selfStatus = Invoke-RawModule @('-Action', 'status', '-StatePath', $selfHealth.State)
  Assert-True ($selfStatus.Text -match 'engine=backoff') 'Status did not expose Heartbeat backoff.'
  Assert-True ($selfStatus.Text -match 'activeTypes=8') 'Status did not report eight public heartbeat families.'

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
  $outsideState = Join-Path $repo 'heartbeat-state-must-not-write.json'
  Assert-FailedSafely (Invoke-RawModule @('-InputPath', $bad, '-StatePath', $outsideState)) 'heartbeat_state_path_invalid' 'State path outside approved roots.'
  Assert-True (-not (Test-Path -LiteralPath $outsideState)) 'Rejected state path was written.'

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
  Assert-True ((Get-Content -Raw $race.State | ConvertFrom-Json).schema -eq 4) 'Concurrent cycles corrupted state.'

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
  $ackOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -Action heartbeat -HeartbeatAcknowledgeEventId $firstEvent.EventId -HeartbeatStatePath $outbox.State 2>&1)
  Assert-Equal $LASTEXITCODE 0 'Outbox acknowledgement exit code.'
  Assert-True (($ackOutput -join "`n") -match '"acknowledged":true') 'Outbox acknowledgement response.'
  Assert-Equal @((Get-Content -Raw $outbox.State | ConvertFrom-Json).outbox).Count 0 'Acknowledged event remained pending.'
  Assert-Silent (Invoke-Heartbeat $outbox @{ collectorCoverage = @{ agent_stall = 'partial' }; agents = @(@{ id = 'outbox-agent'; active = $true; progressHash = 'a'; totalTokens = 50000 }) } -At $outbox.BaseTime.AddMinutes(70)) 'Acknowledged event must not retry.'

  # An abandoned named mutex is recovered without losing the cycle.
  $abandoned = New-Case 'abandoned-mutex'
  $abandonedInput = Join-Path $abandoned.Path 'input.json'
  $abandonedData = @{ schemaVersion = 1; capturedAtUtc = $abandoned.BaseTime.ToString('o'); runId = 'abandoned-run'; origin = 'test'; forceCadence = $true; collectorCoverage = @{ agent_stall = 'observed' }; agents = @() }
  [IO.File]::WriteAllText($abandonedInput, ($abandonedData | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
  $mutexName = 'Global\ChronosHeartbeat-' + (Get-TestHash (Get-TestCanonicalStateIdentity $abandoned.State)).Substring(0, 24)
  $holder = New-Object Threading.Mutex($false, $mutexName)
  try {
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$m=New-Object Threading.Mutex(`$false,'$mutexName');[void]`$m.WaitOne();[Environment]::Exit(0)"))
    $child = Start-Process powershell.exe -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand -PassThru -WindowStyle Hidden
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

  # The wrapper status path is concise and does not need an input snapshot.
  $emptyStatus = Invoke-RawModule @('-Action', 'status', '-StatePath', (Join-Path $root 'empty-status.json'))
  Assert-Equal $emptyStatus.ExitCode 0 'Empty status exit code.'
  Assert-True ($emptyStatus.Text -match '^CHRONOS HEARTBEATS engine=healthy activeTypes=8') 'Empty status headline.'

  'Chronos heartbeat deterministic validations passed.'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
