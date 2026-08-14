param(
  [string]$Action = 'cycle',
  [string]$InputPath,
  [string]$InspectorOutputPath,
  [string]$StatePath,
  [string]$Scope,
  [string]$EventId,
  [string]$CorroboratingEventId,
  [string]$InterventionId,
  [int]$InterventionVersion = 0,
  [string]$TargetId,
  [string]$TargetGeneration,
  [string]$GovernorId,
  [string]$ClaimToken,
  [ValidateSet('', 'accepted', 'definite_failure', 'unknown')]
  [string]$TransportResult = '',
  [ValidateSet('', 'acknowledged', 'outcome_reported', 'declined', 'user_authority_required', 'remediation_failed')]
  [string]$TaskResponse = '',
  [ValidateSet('', 'host_inventory', 'host_test', 'host_git')]
  [string]$VerificationSource = '',
  [ValidateSet('', 'resolved', 'active', 'failed')]
  [string]$VerificationResult = '',
  [ValidateSet('', 'ambiguous_target', 'target_not_live', 'transport_unavailable', 'user_authority_required', 'unsupported_action')]
  [string]$FailureReason = '',
  [ValidateRange(5, 1440)]
  [int]$StallMinutes = 20
)

$ErrorActionPreference = 'Stop'

$script:Families = @('agent_stall', 'guardian', 'usage', 'sessions', 'tests', 'machines', 'tasks', 'git_build', 'heartbeat')
$script:PublicFamilyCount = 8
$script:CadenceSeconds = [ordered]@{
  agent_stall = 300
  guardian = 300
  usage = 300
  sessions = 900
  tests = 600
  machines = 1800
  tasks = 300
  git_build = 600
  heartbeat = 300
}
$script:SeverityRank = @{ INFO = 1; WARNING = 2; HIGH = 3; CRITICAL = 4 }
$script:ConditionLimit = 256
$script:EventLimit = 50
$script:RunIdLimit = 32
$script:OutboxLimit = 64
$script:OutboxRetrySeconds = 900
$script:OutboxMaxAttempts = 2
$script:InterventionLimit = 64
$script:InterventionClaimSeconds = 900
$script:InputByteLimit = 262144
$script:InspectorByteLimit = 65536
$script:StateByteLimit = 262144
$script:JsonNodeLimit = 32768
$script:StateStoreMode = 'unknown'
$script:StateStoreMigration = 'not_applicable'
$script:StateStoreWriteReady = $false
$script:StateStoreProtection = 'hashed_metadata'
$script:PriorStateDisposition = 'not_applicable'
$script:PriorStateWriteAttempted = $false

if (-not ('ChronosHeartbeatPathIdentity' -as [type])) {
  $pathIdentitySource = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class ChronosHeartbeatPathIdentity {
  private const uint FILE_SHARE_READ = 1;
  private const uint FILE_SHARE_WRITE = 2;
  private const uint FILE_SHARE_DELETE = 4;
  private const uint OPEN_EXISTING = 3;
  private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

  [StructLayout(LayoutKind.Sequential)]
  private struct BY_HANDLE_FILE_INFORMATION {
    public uint FileAttributes;
    public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
    public uint VolumeSerialNumber;
    public uint FileSizeHigh;
    public uint FileSizeLow;
    public uint NumberOfLinks;
    public uint FileIndexHigh;
    public uint FileIndexLow;
  }

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern SafeFileHandle CreateFile(
    string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
    uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern uint GetFinalPathNameByHandle(
    SafeFileHandle handle, StringBuilder path, uint length, uint flags);

  [DllImport("kernel32.dll", SetLastError = true)]
  private static extern bool GetFileInformationByHandle(
    SafeFileHandle handle, out BY_HANDLE_FILE_INFORMATION information);

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

  public static uint LinkCount(string path) {
    using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read,
      FileShare.ReadWrite | FileShare.Delete)) {
      BY_HANDLE_FILE_INFORMATION information;
      if (!GetFileInformationByHandle(stream.SafeFileHandle, out information))
        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      return information.NumberOfLinks;
    }
  }
}
'@
  try { [void](Add-Type -TypeDefinition $pathIdentitySource -Language CSharp -ErrorAction Stop) } catch { throw 'heartbeat_runtime_unavailable' }
}

function Get-Value {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
    return $Default
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Has-Value {
  param($Object, [string]$Name)
  return ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name))
}

function ConvertTo-Hashtable {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [System.Collections.IDictionary]) {
    $copy = @{}
    foreach ($key in $Value.Keys) { $copy[[string]$key] = ConvertTo-Hashtable $Value[$key] }
    return $copy
  }
  # Windows PowerShell 5.1 can report piped scalar values as [pscustomobject].
  # The concrete type check avoids converting strings into @{ Length = ... }.
  if ($Value.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
    $copy = @{}
    foreach ($property in $Value.PSObject.Properties) { $copy[$property.Name] = ConvertTo-Hashtable $property.Value }
    return $copy
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $items = @($Value | ForEach-Object { ConvertTo-Hashtable $_ })
    return ,$items
  }
  return $Value
}

function As-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  return @($Value)
}

function Get-StableHash {
  param($Value)
  if ($null -eq $Value) { $Value = '__null__' }
  $json = $Value | ConvertTo-Json -Compress -Depth 16
  if ($null -eq $json) { $json = '[]' }
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Format-Number {
  param([double]$Value)
  return $Value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-UtcTimestamp {
  param($Value, [string]$ErrorCode = 'heartbeat_input_invalid')
  if (-not ($Value -is [string]) -or $Value.Length -gt 40) { throw $ErrorCode }
  $parsed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
    throw $ErrorCode
  }
  return $parsed.ToUniversalTime()
}

function Test-IsNumber {
  param($Value)
  return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
    $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
    $Value -is [int64] -or $Value -is [uint64] -or $Value -is [single] -or
    $Value -is [double] -or $Value -is [decimal])
}

function Test-IsInteger {
  param($Value)
  return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
    $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
    $Value -is [int64] -or $Value -is [uint64])
}

function Move-JsonWhitespace {
  param([string]$Text, [ref]$Index)
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -in @(' ', "`t", "`r", "`n")) { $Index.Value++ }
}

function Read-StrictJsonString {
  param([string]$Text, [ref]$Index, [string]$ErrorCode)
  if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne '"') { throw $ErrorCode }
  $start = $Index.Value
  $Index.Value++
  while ($Index.Value -lt $Text.Length) {
    $character = $Text[$Index.Value]
    if ([int][char]$character -lt 0x20) { throw $ErrorCode }
    if ($character -eq '"') {
      $Index.Value++
      $literal = $Text.Substring($start, $Index.Value - $start)
      try {
        $decoded = $literal | ConvertFrom-Json -ErrorAction Stop
        if (-not ($decoded -is [string])) { throw $ErrorCode }
        return $decoded.Normalize([Text.NormalizationForm]::FormC)
      } catch { throw $ErrorCode }
    }
    if ($character -eq '\') {
      $Index.Value++
      if ($Index.Value -ge $Text.Length) { throw $ErrorCode }
      $escape = $Text[$Index.Value]
      if ($escape -eq 'u') {
        if ($Index.Value + 4 -ge $Text.Length -or $Text.Substring($Index.Value + 1, 4) -notmatch '^[0-9A-Fa-f]{4}$') { throw $ErrorCode }
        $Index.Value += 5
        continue
      }
      if ($escape -notin @('"', '\', '/', 'b', 'f', 'n', 'r', 't')) { throw $ErrorCode }
    }
    $Index.Value++
  }
  throw $ErrorCode
}

function Assert-StrictJsonValue {
  param([string]$Text, [ref]$Index, [ref]$NodeCount, [int]$Depth, [string]$ErrorCode)
  if ($Depth -gt 20) { throw $ErrorCode }
  Move-JsonWhitespace $Text $Index
  if ($Index.Value -ge $Text.Length) { throw $ErrorCode }
  $NodeCount.Value++
  if ($NodeCount.Value -gt $script:JsonNodeLimit) { throw $ErrorCode }
  $character = $Text[$Index.Value]
  if ($character -eq '"') {
    [void](Read-StrictJsonString $Text $Index $ErrorCode)
    return
  }
  if ($character -eq '{') {
    $Index.Value++
    Move-JsonWhitespace $Text $Index
    $keys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq '}') { $Index.Value++; return }
    while ($true) {
      Move-JsonWhitespace $Text $Index
      $key = Read-StrictJsonString $Text $Index $ErrorCode
      if (-not $keys.Add($key)) { throw $ErrorCode }
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne ':') { throw $ErrorCode }
      $Index.Value++
      Assert-StrictJsonValue $Text $Index $NodeCount ($Depth + 1) $ErrorCode
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length) { throw $ErrorCode }
      if ($Text[$Index.Value] -eq '}') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { throw $ErrorCode }
      $Index.Value++
    }
  }
  if ($character -eq '[') {
    $Index.Value++
    Move-JsonWhitespace $Text $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq ']') { $Index.Value++; return }
    while ($true) {
      Assert-StrictJsonValue $Text $Index $NodeCount ($Depth + 1) $ErrorCode
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length) { throw $ErrorCode }
      if ($Text[$Index.Value] -eq ']') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { throw $ErrorCode }
      $Index.Value++
    }
  }
  $start = $Index.Value
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -notin @(',', ']', '}', ' ', "`t", "`r", "`n")) { $Index.Value++ }
  $token = $Text.Substring($start, $Index.Value - $start)
  if ($token -notmatch '^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$') { throw $ErrorCode }
}

function Assert-StrictJson {
  param([string]$Text, [string]$ErrorCode)
  if ([string]::IsNullOrWhiteSpace($Text)) { throw $ErrorCode }
  $index = 0
  $nodeCount = 0
  Assert-StrictJsonValue $Text ([ref]$index) ([ref]$nodeCount) 0 $ErrorCode
  Move-JsonWhitespace $Text ([ref]$index)
  if ($index -ne $Text.Length) { throw $ErrorCode }
}

function Read-StrictUtf8JsonFile {
  param([string]$Path, [int64]$ByteLimit, [string]$ErrorCode)
  try {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt $ByteLimit) { throw $ErrorCode }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    Assert-StrictJson $text $ErrorCode
    return $text
  } catch { throw $ErrorCode }
}

function Assert-AllowedKeys {
  param($Object, [string[]]$Allowed)
  if (-not ($Object -is [System.Collections.IDictionary])) { throw 'heartbeat_input_invalid' }
  foreach ($key in $Object.Keys) {
    if ($Allowed -notcontains [string]$key) { throw 'heartbeat_input_invalid' }
    $normalized = ([string]$key -replace '[-_]', '').ToLowerInvariant()
    if ($normalized -in @('password', 'secret', 'apikey', 'accesstoken', 'refreshtoken', 'credential', 'credentials', 'authorization', 'cookie', 'privatekey')) {
      throw 'heartbeat_input_invalid'
    }
  }
}

function Test-SecretShapedValue {
  param([string]$Value)
  if ($Value -match '(?i)(password|passwd|secret|api[_-]?key|access[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|credential|authorization|private[_-]?key)\s*[:=]') { return $true }
  return $Value -match '(?i)(?:sk-(?:proj-)?[a-z0-9_-]{12,}|gh[pousr]_[a-z0-9]{20,}|nfp_[a-z0-9]{20,}|AKIA[0-9A-Z]{16})'
}

function Assert-Identifier {
  param($Value)
  if (-not ($Value -is [string]) -or $Value.Length -lt 1 -or $Value.Length -gt 128) { throw 'heartbeat_input_invalid' }
  if (Test-SecretShapedValue $Value) { throw 'heartbeat_input_invalid' }
  if ($Value -match '[\\]' -or $Value -match '^[A-Za-z]:[/\\]' -or $Value -match '(^|/)\.\.($|/)') { throw 'heartbeat_input_invalid' }
  if ($Value -notmatch '^(?:[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}|/root(?:/[A-Za-z0-9._-]{1,64}){0,7})$') {
    throw 'heartbeat_input_invalid'
  }
}

function Assert-Label {
  param($Value, [int]$MaximumLength = 96)
  if (-not ($Value -is [string]) -or $Value.Length -lt 1 -or $Value.Length -gt $MaximumLength) { throw 'heartbeat_input_invalid' }
  if (Test-SecretShapedValue $Value) { throw 'heartbeat_input_invalid' }
  if ($Value -match '[\\]' -or $Value -match '^[A-Za-z]:[/\\]' -or $Value -match '(^|/)\.\.($|/)' -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._:@+/-]*$') {
    throw 'heartbeat_input_invalid'
  }
}

function Assert-Opaque {
  param($Value)
  if (-not ($Value -is [string]) -or $Value.Length -lt 1 -or $Value.Length -gt 128 -or (Test-SecretShapedValue $Value) -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._:@+-]*$') {
    throw 'heartbeat_input_invalid'
  }
}

function Assert-Version {
  param($Value)
  if (-not ($Value -is [string]) -or $Value.Length -lt 1 -or $Value.Length -gt 64 -or (Test-SecretShapedValue $Value) -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]*$') {
    throw 'heartbeat_input_invalid'
  }
}

function Assert-Commit {
  param($Value)
  if (-not ($Value -is [string]) -or ($Value -ne 'unknown' -and $Value -notmatch '^[A-Fa-f0-9]{7,64}$')) {
    throw 'heartbeat_input_invalid'
  }
}

function Assert-Field {
  param(
    $Object,
    [string]$Name,
    [ValidateSet('bool', 'number', 'integer', 'id', 'label', 'opaque', 'version', 'commit', 'time', 'enum')]
    [string]$Kind,
    [bool]$Required = $false,
    [double]$Minimum = [double]::MinValue,
    [double]$Maximum = [double]::MaxValue,
    [string[]]$Allowed = @()
  )
  if (-not (Has-Value $Object $Name)) {
    if ($Required) { throw 'heartbeat_input_invalid' }
    return
  }
  $value = $Object[$Name]
  if ($null -eq $value) { throw 'heartbeat_input_invalid' }
  switch ($Kind) {
    'bool' {
      if (-not ($value -is [bool])) { throw 'heartbeat_input_invalid' }
    }
    'number' {
      if (-not (Test-IsNumber $value)) { throw 'heartbeat_input_invalid' }
      $number = [double]$value
      if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt $Minimum -or $number -gt $Maximum) { throw 'heartbeat_input_invalid' }
    }
    'integer' {
      if (-not (Test-IsInteger $value)) { throw 'heartbeat_input_invalid' }
      $number = [double]$value
      if ($number -lt $Minimum -or $number -gt $Maximum) {
        throw 'heartbeat_input_invalid'
      }
    }
    'id' { Assert-Identifier $value }
    'label' { Assert-Label $value }
    'opaque' { Assert-Opaque $value }
    'version' { Assert-Version $value }
    'commit' { Assert-Commit $value }
    'time' { [void](ConvertTo-UtcTimestamp $value) }
    'enum' {
      if (-not ($value -is [string]) -or $Allowed -notcontains $value) { throw 'heartbeat_input_invalid' }
    }
  }
}

function Assert-StringArray {
  param($Object, [string]$Name, [int]$MaximumCount, [string[]]$Allowed = @())
  if (-not (Has-Value $Object $Name)) { return }
  $value = $Object[$Name]
  if ($value -is [string] -or -not ($value -is [System.Collections.IEnumerable])) { throw 'heartbeat_input_invalid' }
  $items = @($value)
  if ($items.Count -gt $MaximumCount) { throw 'heartbeat_input_invalid' }
  foreach ($item in $items) {
    if ($Allowed.Count -gt 0) {
      if (-not ($item -is [string]) -or $Allowed -notcontains $item) { throw 'heartbeat_input_invalid' }
    } else {
      Assert-Label $item 64
    }
  }
}

function Assert-AgentRecord {
  param($Record)
  Assert-AllowedKeys $Record @('id', 'generation', 'owner', 'owningSolThread', 'active', 'repeatedEquivalentActions', 'minutesSinceMeaningfulChange', 'tokensSinceMeaningfulChange', 'longRunningOperation', 'progressHash', 'lastToolHash', 'lastCommandHash', 'lastFileChangeUtc', 'lastGitHash', 'lastTestHash', 'totalTokens', 'operationClass', 'status')
  Assert-Field $Record 'id' id $true
  Assert-Field $Record 'generation' opaque
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  Assert-Field $Record 'active' bool $true
  Assert-Field $Record 'repeatedEquivalentActions' integer $false 0 1000000
  Assert-Field $Record 'minutesSinceMeaningfulChange' number $false 0 525600
  Assert-Field $Record 'tokensSinceMeaningfulChange' integer $false 0 9000000000000000
  Assert-Field $Record 'longRunningOperation' bool
  foreach ($name in @('progressHash', 'lastToolHash', 'lastCommandHash', 'lastGitHash', 'lastTestHash')) { Assert-Field $Record $name opaque }
  Assert-Field $Record 'lastFileChangeUtc' time
  Assert-Field $Record 'totalTokens' integer $false 0 9000000000000000
  Assert-Field $Record 'operationClass' label
  Assert-Field $Record 'status' enum $false 0 0 @('active', 'waiting', 'blocked', 'completed', 'failed', 'unknown')
}

function Assert-GuardianRecord {
  param($Record)
  Assert-AllowedKeys $Record @('reviewerSessionId', 'parentThreadId', 'owner', 'owningSolThread', 'reviewerModel', 'reviewCount', 'reviewsPerMinute', 'reviewsPerHour', 'averageReviewIntervalSeconds', 'reviewerTokens', 'mainTokens', 'reviewerUsageRatio', 'reviewerTurnShare', 'equivalentApprovalRequests', 'approvalExecutionCount', 'allowedPendingPostconditionCount', 'reviewAcceleration', 'reviewerRecursion', 'progressHash')
  Assert-Field $Record 'reviewerSessionId' id $true
  Assert-Field $Record 'parentThreadId' id
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  Assert-Field $Record 'reviewerModel' label
  foreach ($name in @('reviewCount', 'reviewerTokens', 'mainTokens', 'equivalentApprovalRequests', 'approvalExecutionCount', 'allowedPendingPostconditionCount')) { Assert-Field $Record $name integer $false 0 9000000000000000 }
  foreach ($name in @('reviewsPerMinute', 'reviewsPerHour', 'averageReviewIntervalSeconds', 'reviewAcceleration')) { Assert-Field $Record $name number $false 0 1000000000 }
  foreach ($name in @('reviewerUsageRatio', 'reviewerTurnShare')) { Assert-Field $Record $name number $false 0 1 }
  Assert-Field $Record 'reviewerRecursion' bool
  Assert-Field $Record 'progressHash' opaque
}

function Assert-UsageRecord {
  param($Record)
  Assert-AllowedKeys $Record @('owner', 'dominantThread', 'owningSolThread', 'role', 'totalTokens', 'windowTokens', 'windowMinutes', 'ratePerMinute', 'baselineRatePerMinute', 'projectedExhaustionMinutes', 'reviewerShare', 'meaningfulProgress', 'progressHash', 'completedCycles', 'stateChanges', 'acknowledgedEvents', 'failedCycles', 'duplicateRuns')
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'dominantThread' id
  Assert-Field $Record 'owningSolThread' id
  Assert-Field $Record 'role' enum $false 0 0 @('governor', 'worker', 'coordinator', 'unknown')
  foreach ($name in @('totalTokens', 'windowTokens', 'completedCycles', 'stateChanges', 'acknowledgedEvents', 'failedCycles', 'duplicateRuns')) { Assert-Field $Record $name integer $false 0 9000000000000000 }
  foreach ($name in @('windowMinutes', 'ratePerMinute', 'baselineRatePerMinute', 'projectedExhaustionMinutes')) { Assert-Field $Record $name number $false 0 1000000000000 }
  Assert-Field $Record 'reviewerShare' number $false 0 1
  Assert-Field $Record 'meaningfulProgress' bool
  Assert-Field $Record 'progressHash' opaque
}

function Assert-SessionRecord {
  param($Record)
  Assert-AllowedKeys $Record @('id', 'parentId', 'owner', 'owningSolThread', 'childCount', 'forkDepth', 'contextOverlap', 'compactionCount', 'rolloutBytes', 'storageGrowthBytesPerHour', 'childCreationRate', 'recursive', 'progressHash')
  Assert-Field $Record 'id' id $true
  Assert-Field $Record 'parentId' id
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  foreach ($name in @('childCount', 'forkDepth', 'compactionCount', 'rolloutBytes')) { Assert-Field $Record $name integer $false 0 9000000000000000 }
  Assert-Field $Record 'contextOverlap' number $false 0 1
  foreach ($name in @('storageGrowthBytesPerHour', 'childCreationRate')) { Assert-Field $Record $name number $false 0 1000000000000000 }
  Assert-Field $Record 'recursive' bool
  Assert-Field $Record 'progressHash' opaque
}

function Assert-TestRecord {
  param($Record)
  $statuses = @('passed', 'failed', 'skipped', 'not_run', 'unavailable', 'unknown')
  Assert-AllowedKeys $Record @('name', 'generation', 'owner', 'owningSolThread', 'status', 'commit', 'repairAttempts', 'failureCount', 'required', 'ran', 'environmentStatuses', 'buildId')
  Assert-Field $Record 'name' label $true
  Assert-Field $Record 'generation' opaque
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  Assert-Field $Record 'status' enum $true 0 0 $statuses
  Assert-Field $Record 'commit' commit
  foreach ($name in @('repairAttempts', 'failureCount')) { Assert-Field $Record $name integer $false 0 1000000 }
  Assert-Field $Record 'required' bool
  Assert-Field $Record 'ran' bool
  Assert-Field $Record 'buildId' opaque
  if (Has-Value $Record 'environmentStatuses') {
    $values = $Record.environmentStatuses
    if ($values -is [System.Collections.IDictionary]) {
      if ($values.Count -gt 16) { throw 'heartbeat_input_invalid' }
      foreach ($key in $values.Keys) {
        Assert-Identifier ([string]$key)
        if ($statuses -notcontains [string]$values[$key]) { throw 'heartbeat_input_invalid' }
      }
    } elseif ($values -is [System.Collections.IEnumerable] -and -not ($values -is [string])) {
      $items = @($values)
      if ($items.Count -gt 16) { throw 'heartbeat_input_invalid' }
      foreach ($item in $items) { if ($statuses -notcontains [string]$item) { throw 'heartbeat_input_invalid' } }
    } else { throw 'heartbeat_input_invalid' }
  }
}

function Assert-MachineRecord {
  param($Record)
  Assert-AllowedKeys $Record @('id', 'owner', 'owningSolThread', 'role', 'version', 'commit', 'pluginVersion', 'marketplaceVersion', 'manifestVersion', 'skills', 'missingSkills', 'mcpConfigured', 'testStatus', 'installStatus', 'intendedVersion', 'intendedCommit')
  Assert-Field $Record 'id' id $true
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  Assert-Field $Record 'role' enum $false 0 0 @('development', 'installer', 'canary', 'production', 'unknown')
  foreach ($name in @('version', 'pluginVersion', 'marketplaceVersion', 'manifestVersion', 'intendedVersion')) { Assert-Field $Record $name version }
  foreach ($name in @('commit', 'intendedCommit')) { Assert-Field $Record $name commit }
  Assert-StringArray $Record 'skills' 32
  Assert-StringArray $Record 'missingSkills' 32
  Assert-Field $Record 'mcpConfigured' bool
  Assert-Field $Record 'testStatus' enum $false 0 0 @('passed', 'failed', 'not_run', 'unavailable', 'unknown')
  Assert-Field $Record 'installStatus' enum $false 0 0 @('installed', 'failed', 'pending', 'stale', 'unknown')
}

function Assert-TaskRecord {
  param($Record)
  Assert-AllowedKeys $Record @('id', 'generation', 'owner', 'owningSolThread', 'status', 'dependsOn', 'dependencyStatus', 'ageHours', 'requiredCommit', 'requiredPush', 'requiredValidation', 'validationStatus', 'acknowledgedBug', 'assigned', 'updatedAt')
  Assert-Field $Record 'id' id $true
  Assert-Field $Record 'generation' opaque
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  Assert-Field $Record 'status' enum $true 0 0 @('todo', 'active', 'waiting', 'blocked', 'completed', 'failed', 'cancelled')
  Assert-Field $Record 'dependsOn' id
  Assert-Field $Record 'dependencyStatus' enum $false 0 0 @('todo', 'active', 'waiting', 'blocked', 'completed', 'failed', 'cancelled', 'unknown')
  Assert-Field $Record 'ageHours' number $false 0 1000000
  foreach ($name in @('requiredCommit', 'requiredPush', 'requiredValidation', 'acknowledgedBug', 'assigned')) { Assert-Field $Record $name bool }
  Assert-Field $Record 'validationStatus' enum $false 0 0 @('passed', 'failed', 'not_run', 'unavailable', 'unknown')
  Assert-Field $Record 'updatedAt' time
}

function Assert-GitRecord {
  param($Record)
  Assert-AllowedKeys $Record @('owner', 'owningSolThread', 'dirty', 'completedTaskIdle', 'requiresCommit', 'requiresPush', 'idleMinutes', 'ahead', 'behind', 'mergeConflict', 'branchChanged', 'destructiveOperation', 'expectedCommitPushed', 'conflictingScopes')
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  foreach ($name in @('dirty', 'completedTaskIdle', 'requiresCommit', 'requiresPush', 'mergeConflict', 'branchChanged', 'destructiveOperation', 'expectedCommitPushed')) { Assert-Field $Record $name bool }
  Assert-Field $Record 'idleMinutes' number $false 0 1000000
  foreach ($name in @('ahead', 'behind', 'conflictingScopes')) { Assert-Field $Record $name integer $false 0 1000000 }
}

function Assert-BuildRecord {
  param($Record)
  Assert-AllowedKeys $Record @('owner', 'owningSolThread', 'status', 'artifactCommit', 'expectedCommit', 'artifactVersion', 'expectedVersion', 'missingFiles', 'missingFileCount', 'manifestMatches', 'packageSizeBytes', 'previousPackageSizeBytes', 'installerArtifactHashMatches')
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'owningSolThread' id
  Assert-Field $Record 'status' enum $false 0 0 @('passed', 'failed', 'missing', 'not_run', 'unknown')
  foreach ($name in @('artifactCommit', 'expectedCommit')) { Assert-Field $Record $name commit }
  foreach ($name in @('artifactVersion', 'expectedVersion')) { Assert-Field $Record $name version }
  Assert-StringArray $Record 'missingFiles' 32
  foreach ($name in @('missingFileCount', 'packageSizeBytes', 'previousPackageSizeBytes')) { Assert-Field $Record $name integer $false 0 9000000000000000 }
  foreach ($name in @('manifestMatches', 'installerArtifactHashMatches')) { Assert-Field $Record $name bool }
}

function Assert-HeartbeatActivityRecord {
  param($Record)
  Assert-AllowedKeys $Record @('origin', 'schedulerDuplicates', 'runtimeSeconds', 'runtimeMilliseconds', 'runtimeBudgetMilliseconds', 'runId', 'parentRunId')
  Assert-Field $Record 'origin' enum $false 0 0 @('host', 'heartbeat', 'heartbeat_notification', 'test')
  Assert-Field $Record 'schedulerDuplicates' integer $false 0 1000000
  Assert-Field $Record 'runtimeSeconds' number $false 0 86400
  foreach ($name in @('runtimeMilliseconds', 'runtimeBudgetMilliseconds')) { Assert-Field $Record $name number $false 0 86400000 }
  Assert-Field $Record 'runId' id
  Assert-Field $Record 'parentRunId' id
}

function Assert-Input {
  param($Snapshot)
  $allowed = @('schemaVersion', 'capturedAtUtc', 'sourceEpoch', 'sourceSequence', 'runId', 'origin', 'collectorCoverage', 'forceCadence', 'allowMachineDrift', 'isHeartbeatGenerated', 'agents', 'guardian', 'usage', 'sessions', 'tests', 'machines', 'tasks', 'git', 'build', 'heartbeatActivity')
  Assert-AllowedKeys $Snapshot $allowed
  Assert-Field $Snapshot 'schemaVersion' integer $false 1 1
  Assert-Field $Snapshot 'capturedAtUtc' time
  Assert-Field $Snapshot 'sourceEpoch' opaque
  Assert-Field $Snapshot 'sourceSequence' integer $false 0 9000000000000000
  Assert-Field $Snapshot 'runId' id
  Assert-Field $Snapshot 'origin' enum $false 0 0 @('host', 'inspector', 'heartbeat', 'heartbeat_notification', 'test')
  Assert-Field $Snapshot 'forceCadence' bool
  Assert-Field $Snapshot 'allowMachineDrift' bool
  Assert-Field $Snapshot 'isHeartbeatGenerated' bool
  if (Has-Value $Snapshot 'collectorCoverage') {
    Assert-AllowedKeys $Snapshot.collectorCoverage $script:Families
    foreach ($key in $Snapshot.collectorCoverage.Keys) {
      if ([string]$Snapshot.collectorCoverage[$key] -notin @('observed', 'partial', 'unsupported')) { throw 'heartbeat_input_invalid' }
    }
  }
  $totalRecords = 0
  foreach ($family in @('agents', 'sessions', 'tests', 'machines', 'tasks')) {
    if (-not (Has-Value $Snapshot $family)) { continue }
    $value = $Snapshot[$family]
    if ($value -is [string] -or -not ($value -is [System.Collections.IEnumerable]) -or $value -is [System.Collections.IDictionary]) { throw 'heartbeat_input_invalid' }
    $records = @($value)
    if ($records.Count -gt 64) { throw 'heartbeat_input_invalid' }
    $totalRecords += $records.Count
    foreach ($record in $records) {
      switch ($family) {
        'agents' { Assert-AgentRecord $record }
        'sessions' { Assert-SessionRecord $record }
        'tests' { Assert-TestRecord $record }
        'machines' { Assert-MachineRecord $record }
        'tasks' { Assert-TaskRecord $record }
      }
    }
  }
  if ($totalRecords -gt 128) { throw 'heartbeat_input_invalid' }
  if (Has-Value $Snapshot 'guardian') { Assert-GuardianRecord $Snapshot.guardian }
  if (Has-Value $Snapshot 'usage') { Assert-UsageRecord $Snapshot.usage }
  if (Has-Value $Snapshot 'git') { Assert-GitRecord $Snapshot.git }
  if (Has-Value $Snapshot 'build') { Assert-BuildRecord $Snapshot.build }
  if (Has-Value $Snapshot 'heartbeatActivity') { Assert-HeartbeatActivityRecord $Snapshot.heartbeatActivity }
}

function Test-ContainedPath {
  param([string]$Path, [string]$Root)
  try {
    $full = [IO.Path]::GetFullPath($Path)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  } catch { return $false }
  if ($full.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
  $prefix = $base + [IO.Path]::DirectorySeparatorChar
  return $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-NoReparseAncestors {
  param([string]$Path)
  try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
  $cursorPath = $full
  while (-not (Test-Path -LiteralPath $cursorPath)) {
    $parent = Split-Path -Parent $cursorPath
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursorPath) { break }
    $cursorPath = $parent
  }
  $cursor = Get-Item -LiteralPath $cursorPath -Force -ErrorAction SilentlyContinue
  while ($cursor) {
    if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    if ($cursor -is [IO.DirectoryInfo]) { $cursor = $cursor.Parent } else { $cursor = $cursor.Directory }
  }
  return $true
}

function Get-CanonicalStateIdentity {
  param([string]$Path)
  try {
    $full = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      if ([ChronosHeartbeatPathIdentity]::LinkCount($full) -ne 1) { throw 'heartbeat_state_path_invalid' }
    }
    $directory = Split-Path -Parent $full
    $missing = [Collections.Generic.List[string]]::new()
    while (-not (Test-Path -LiteralPath $directory -PathType Container)) {
      $leaf = Split-Path -Leaf $directory
      if ([string]::IsNullOrWhiteSpace($leaf)) { throw 'heartbeat_state_path_invalid' }
      $missing.Add($leaf) | Out-Null
      $parent = Split-Path -Parent $directory
      if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $directory) { throw 'heartbeat_state_path_invalid' }
      $directory = $parent
    }
    $canonical = [ChronosHeartbeatPathIdentity]::FinalDirectoryPath($directory)
    for ($index = $missing.Count - 1; $index -ge 0; $index--) { $canonical = [IO.Path]::Combine($canonical, $missing[$index]) }
    $canonical = [IO.Path]::Combine($canonical, (Split-Path -Leaf $full))
    return $canonical.Replace('/', '\').TrimEnd('\').ToUpperInvariant()
  } catch {
    if ([string]$_.Exception.Message -eq 'heartbeat_state_path_invalid') { throw }
    throw 'heartbeat_mutex_identity_invalid'
  }
}

function Resolve-StatePath {
  param([string]$Requested, [string]$RequestedScope)
  $localRoot = Join-Path $env:LOCALAPPDATA 'Chronos\Heartbeat'
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $priorTempRoot = Join-Path $tempRoot 'Chronos\Heartbeat'
  $privateTempRoot = Join-Path $tempRoot 'Chronos\Heartbeat-v2'
  if ([string]::IsNullOrWhiteSpace($RequestedScope)) {
    $codexHome = Join-Path $HOME '.codex'
    $RequestedScope = '{0}|{1}' -f $env:COMPUTERNAME, ([IO.Path]::GetFullPath($codexHome))
  }
  if ($RequestedScope.Length -gt 4096) { throw 'heartbeat_scope_invalid' }
  if ([string]::IsNullOrWhiteSpace($Requested)) {
    $scopeHash = Get-StableHash $RequestedScope
    $script:StateStoreMode = 'temp_private'
    $script:StateStoreMigration = 'not_needed'
    $defaultPath = Join-Path $privateTempRoot (Join-Path $scopeHash 'heartbeat-state.json')
    if (-not (Test-NoReparseAncestors $defaultPath)) { throw 'heartbeat_state_path_invalid' }
    return [pscustomobject]@{
      Path = $defaultPath
      ScopeHash = $scopeHash
      PriorTempDirectory = (Join-Path $priorTempRoot $scopeHash)
      PriorTempPath = (Join-Path $priorTempRoot (Join-Path $scopeHash 'heartbeat-state.json'))
      LegacyPath = (Join-Path $localRoot (Join-Path $scopeHash 'heartbeat-state.json'))
    }
  }
  $script:StateStoreMode = 'explicit'
  try { $full = [IO.Path]::GetFullPath($Requested) } catch { throw 'heartbeat_state_path_invalid' }
  if ([IO.Path]::GetExtension($full) -ne '.json') { throw 'heartbeat_state_path_invalid' }
  if (-not (Test-ContainedPath $full $localRoot) -and -not (Test-ContainedPath $full $privateTempRoot)) { throw 'heartbeat_state_path_invalid' }
  if (-not (Test-NoReparseAncestors $full)) { throw 'heartbeat_state_path_invalid' }
  return [pscustomobject]@{ Path = $full; ScopeHash = (Get-StableHash $RequestedScope); PriorTempDirectory = $null; PriorTempPath = $null; LegacyPath = $null }
}

function Initialize-StateStore {
  param([string]$ResolvedStatePath)
  $directory = Split-Path -Parent $ResolvedStatePath
  try {
    if (-not (Test-NoReparseAncestors $directory)) { throw 'heartbeat_state_store_unwritable' }
    if (-not (Test-Path -LiteralPath $directory)) {
      $missing = [Collections.Generic.List[string]]::new()
      $cursor = $directory
      while (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
        $missing.Add($cursor) | Out-Null
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { throw 'heartbeat_state_store_unwritable' }
        $cursor = $parent
      }
      for ($index = $missing.Count - 1; $index -ge 0; $index--) {
        if (-not (Test-NoReparseAncestors $cursor)) { throw 'heartbeat_state_store_unwritable' }
        $next = $missing[$index]
        if (-not (Test-Path -LiteralPath $next -PathType Container)) { New-Item -ItemType Directory -Path $next | Out-Null }
        $nextItem = Get-Item -LiteralPath $next -Force
        if (-not $nextItem.PSIsContainer -or ($nextItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'heartbeat_state_store_unwritable' }
        $cursor = $next
      }
    }
    $item = Get-Item -LiteralPath $directory -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $directory)) {
      throw 'heartbeat_state_store_unwritable'
    }
    if ($script:StateStoreMode -eq 'temp_private') {
      # User TEMP already inherits the host user's boundary. Do not replace its
      # ACL with a transient sandbox SID or a later Codex identity can be locked
      # out of its own upgrade state.
      $script:StateStoreProtection = 'user_temp_inherited_hashed_metadata'
    }
    if (-not (Test-Path -LiteralPath $ResolvedStatePath -PathType Leaf)) {
      $probe = Join-Path $directory ('.heartbeat-probe-' + [guid]::NewGuid().ToString('N') + '.tmp')
      try {
        $stream = New-Object IO.FileStream($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
      } finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
      }
    }
    $script:StateStoreWriteReady = $true
  } catch {
    if ([string]$_.Exception.Message -eq 'heartbeat_state_store_unwritable') { throw }
    throw 'heartbeat_state_store_unwritable'
  }
}

function Resolve-InputFile {
  param([string]$Path, [int64]$ByteLimit, [string[]]$Extensions)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  try { $full = [IO.Path]::GetFullPath($Path) } catch { throw 'heartbeat_input_invalid' }
  if ($Extensions -notcontains [IO.Path]::GetExtension($full).ToLowerInvariant()) { throw 'heartbeat_input_invalid' }
  $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
  if (-not $item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $ByteLimit) { throw 'heartbeat_input_invalid' }
  if (-not (Test-NoReparseAncestors $full)) { throw 'heartbeat_input_invalid' }
  return $full
}

function Read-NormalizedInput {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return @{} }
  $safePath = Resolve-InputFile $Path $script:InputByteLimit @('.json')
  try {
    $text = Read-StrictUtf8JsonFile $safePath $script:InputByteLimit 'heartbeat_input_invalid'
    $parsed = $text | ConvertFrom-Json -ErrorAction Stop
    $result = ConvertTo-Hashtable $parsed
  } catch { throw 'heartbeat_input_invalid' }
  if (-not ($result -is [System.Collections.IDictionary])) { throw 'heartbeat_input_invalid' }
  Write-Output -NoEnumerate $result
}

function Convert-InspectorNumber {
  param($Value)
  if ($null -eq $Value) { return $null }
  $number = 0.0
  $text = ([string]$Value).Replace(',', '.')
  if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number }
  return $null
}

function Merge-InspectorOutput {
  param($Snapshot, [string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  $safePath = Resolve-InputFile $Path $script:InspectorByteLimit @('.txt', '.out', '.log')
  $allowed = @(
    'pluginVersion', 'approvalReviewCoverage', 'approvalReviewObservation', 'approvalReviewsPerHour',
    'approvalAverageIntervalSeconds', 'approvalReviewTurnsObserved', 'primaryTurnsObserved',
    'approvalReviewTurnShare', 'approvalReviewerMainInputRatio', 'approvalRepeatedRequests',
    'approvalRepeatedPrefixRequests', 'approvalPersistenceRetries', 'approvalPersistenceFailures',
    'approvalPeakPerMinute', 'approvalConcurrentPeak', 'nestedReviewerSessionsObserved',
    'approvalRecursionRisk', 'tokenIntervalInputM', 'tokenIntervalStartUtc', 'tokenIntervalEndUtc',
    'tokenIntervalObservation', 'rolloutForkFilesObserved', 'rolloutReplayPct',
    'rolloutGrowthMiBPerHour', 'tokenCompactions'
  )
  $fields = @{}
  foreach ($line in (Get-Content -LiteralPath $safePath)) {
    if ($line -notmatch '^CHRONOS(?: EFFICIENCY)? ') { continue }
    foreach ($match in [regex]::Matches($line, '(?:^|\s)(?<key>[A-Za-z][A-Za-z0-9]+)=(?<value>[^\s]{1,128})')) {
      $key = $match.Groups['key'].Value
      if ($allowed -contains $key) { $fields[$key] = $match.Groups['value'].Value }
    }
  }
  if ($fields.Count -eq 0) { throw 'heartbeat_inspector_input_invalid' }
  if (-not (Has-Value $Snapshot 'collectorCoverage')) { $Snapshot['collectorCoverage'] = @{} }

  if (-not (Has-Value $Snapshot 'guardian') -and $fields.Contains('approvalReviewTurnsObserved')) {
    $reviewCount = Convert-InspectorNumber $fields.approvalReviewTurnsObserved
    $reviewsPerHour = Convert-InspectorNumber $fields.approvalReviewsPerHour
    $turnShare = Convert-InspectorNumber $fields.approvalReviewTurnShare
    $inputRatio = Convert-InspectorNumber $fields.approvalReviewerMainInputRatio
    if ($null -ne $turnShare -and $turnShare -gt 1 -and $turnShare -le 100) { $turnShare = $turnShare / 100.0 }
    $inputShare = if ($null -ne $inputRatio -and $inputRatio -ge 0) { $inputRatio / (1.0 + $inputRatio) } else { $null }
    $repeatValues = @('approvalRepeatedRequests', 'approvalRepeatedPrefixRequests', 'approvalPersistenceRetries') | ForEach-Object { Convert-InspectorNumber $fields[$_] }
    $repeats = [int](($repeatValues | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum)
    $guardian = @{
      reviewerSessionId = 'chronos-inspector-window'
      owner = 'governor'
      owningSolThread = 'governor'
      reviewCount = [int64]$(if ($null -eq $reviewCount) { 0 } else { $reviewCount })
      equivalentApprovalRequests = $repeats
      progressHash = (Get-StableHash $fields).Substring(0, 32)
    }
    if ($null -ne $reviewsPerHour) { $guardian.reviewsPerHour = $reviewsPerHour }
    if ($null -ne $turnShare -and $turnShare -ge 0 -and $turnShare -le 1) { $guardian.reviewerTurnShare = $turnShare }
    if ($null -ne $inputShare -and $inputShare -ge 0 -and $inputShare -le 1) { $guardian.reviewerUsageRatio = $inputShare }
    if ($fields.Contains('approvalAverageIntervalSeconds')) {
      $interval = Convert-InspectorNumber $fields.approvalAverageIntervalSeconds
      if ($null -ne $interval -and $interval -ge 0) { $guardian.averageReviewIntervalSeconds = $interval }
    }
    if ($fields.Contains('nestedReviewerSessionsObserved')) {
      $nested = Convert-InspectorNumber $fields.nestedReviewerSessionsObserved
      if ($null -ne $nested) { $guardian.reviewerRecursion = ($nested -gt 0) }
    }
    $Snapshot['guardian'] = $guardian
    $coverage = [string]$fields.approvalReviewCoverage
    $Snapshot.collectorCoverage['guardian'] = if ($coverage -match '^(complete|observed)$') { 'observed' } else { 'partial' }
  }

  if (-not (Has-Value $Snapshot 'usage') -and $fields.Contains('tokenIntervalInputM')) {
    $millions = Convert-InspectorNumber $fields.tokenIntervalInputM
    if ($null -ne $millions -and $millions -ge 0) {
      $usage = @{ owner = 'governor'; owningSolThread = 'governor'; meaningfulProgress = $true; windowTokens = [int64]($millions * 1000000) }
      if ($fields.Contains('tokenIntervalStartUtc') -and $fields.Contains('tokenIntervalEndUtc')) {
        try {
          $start = ConvertTo-UtcTimestamp $fields.tokenIntervalStartUtc 'heartbeat_inspector_input_invalid'
          $end = ConvertTo-UtcTimestamp $fields.tokenIntervalEndUtc 'heartbeat_inspector_input_invalid'
          $minutes = ($end - $start).TotalMinutes
          if ($minutes -gt 0) { $usage.windowMinutes = $minutes; $usage.ratePerMinute = [double]$usage.windowTokens / $minutes }
        } catch {}
      }
      $Snapshot['usage'] = $usage
      $Snapshot.collectorCoverage['usage'] = 'partial'
    }
  }

  if (-not (Has-Value $Snapshot 'machines') -and $fields.Contains('pluginVersion')) {
    $Snapshot['machines'] = @(@{ id = 'local-inspector'; role = 'development'; pluginVersion = [string]$fields.pluginVersion; owner = 'development' })
    $Snapshot.collectorCoverage['machines'] = 'partial'
  }
}

function New-CollectorState {
  param([string]$Family)
  return [ordered]@{
    cadenceSeconds = [int]$script:CadenceSeconds[$Family]
    lastAttempt = $null
    lastRun = $null
    lastSuccess = $null
    coverage = 'unsupported'
    skippedCadence = 0
    backoffUntilUtc = $null
    sourceEpochHash = $null
    lastSequence = $null
  }
}

function New-DefaultState {
  param([string]$ScopeHash)
  $collectors = [ordered]@{}
  $previous = [ordered]@{}
  foreach ($family in $script:Families) {
    $collectors[$family] = New-CollectorState $family
    $previous[$family] = @{}
  }
  return [ordered]@{
    schema = 7
    revision = 0
    scopeHash = $ScopeHash
    previous = $previous
    conditions = @{}
    events = @()
    outbox = @()
    interventions = @()
    collectors = $collectors
    health = [ordered]@{
      runs = 0
      suppressedDuplicates = 0
      routesEmitted = 0
      resolutionEvents = 0
      duplicateRuns = 0
      acknowledgedEvents = 0
      failedCycles = 0
      mutexContention = 0
      lastCycleUtc = $null
      lastSuccessUtc = $null
      lastDurationMs = 0
      lastRunIdHash = $null
      lastError = $null
      backoffUntilUtc = $null
      deliveryAttempts = 0
      runtimeBudgetMs = 0
      runtimeObservedMs = 0
      runtimeOverrunMs = 0
      runtimeOverrunPercent = 0
      runtimeBaselineMs = 0
      runtimeClassification = 'unobserved'
      runtimeOverrunStreak = 0
      runtimeBackoffApplied = $false
    }
    runIds = @()
  }
}

function Test-PersistedScalar {
  param($Value)
  if ($null -eq $Value -or $Value -is [bool] -or (Test-IsNumber $Value)) { return $true }
  if (-not ($Value -is [string]) -or $Value.Length -gt 160) { return $false }
  if ($Value -match '[\\/]' -or $Value -match '(?i)(password|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|credential|authorization|cookie|private[_-]?key)') { return $false }
  return $true
}

function Assert-StateRecord {
  param($Record, [string[]]$Allowed)
  if (-not ($Record -is [System.Collections.IDictionary])) { throw 'heartbeat_state_invalid' }
  $eventTypes = @('AGENT_STALL', 'GUARDIAN_RUNAWAY', 'USAGE_BURN', 'SESSION_EXPLOSION', 'TEST_REGRESSION', 'TEST_ENVIRONMENT_DRIFT', 'TEST_VALIDATION_MISSING', 'MACHINE_DRIFT', 'TASK_ACTIONABLE', 'ZOMBIE_TASK', 'TASK_HANDOFF_INCOMPLETE', 'GIT_BUILD_STATE', 'GIT_STATE_RISK', 'BUILD_ARTIFACT_DRIFT', 'HEARTBEAT_SELF_HEALTH')
  $statusValues = @('active', 'waiting', 'blocked', 'completed', 'failed', 'unknown', 'passed', 'skipped', 'not_run', 'unavailable', 'installed', 'pending', 'stale', 'todo', 'cancelled')
  $interventionStates = @('queued', 'send_claimed', 'retry_queued', 'delivery_unknown', 'awaiting_task_ack', 'remediating', 'verification_pending', 'active_violation', 'verified_resolved', 'declined', 'user_authority_required', 'remediation_failed', 'undelivered', 'failed_closed', 'superseded')
  $interventionTemplates = @('contain_agent_work', 'stop_review_amplification', 'contain_usage_growth', 'stop_recursive_workers_and_checkpoint', 'rerun_known_narrow_test_once', 'run_known_required_validation_once', 'resume_one_bounded_step', 'reconcile_owned_child', 'complete_existing_handoff', 'preserve_and_verify_handoff', 'stop_new_writes_and_verify_ownership', 'preserve_and_verify_artifact', 'governor_local_only')
  $postconditions = @('agent_progress_or_terminal', 'review_activity_stable', 'usage_progress_stable', 'session_growth_stable', 'known_test_passed', 'required_validation_observed', 'task_progress_observed', 'ownership_reconciled', 'handoff_verified', 'git_state_stable', 'artifact_identity_stable', 'none')
  foreach ($key in $Record.Keys) {
    if ($Allowed -notcontains [string]$key -or -not (Test-PersistedScalar $Record[$key])) { throw 'heartbeat_state_invalid' }
    if ($null -eq $Record[$key] -or -not ($Record[$key] -is [string])) { continue }
    $text = [string]$Record[$key]
    if ([string]$key -match 'Hash$' -or [string]$key -in @('eventId', 'interventionId')) {
      if ($text -notmatch '^[a-f0-9]{16,64}$') { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -in @('lastAttempt', 'lastRun', 'lastSuccess', 'backoffUntilUtc', 'firstObserved', 'lastObserved', 'lastNotified', 'resolvedAt', 'detected', 'lastCycleUtc', 'lastSuccessUtc', 'createdAt', 'updatedAt', 'claimExpiresAt')) {
      [void](ConvertTo-UtcTimestamp $text 'heartbeat_state_invalid')
    } elseif ([string]$key -eq 'role') {
      if ($text -notin @('governor', 'worker', 'coordinator', 'unknown')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'family') {
      if ($script:Families -notcontains $text) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'type') {
      if ($eventTypes -notcontains $text) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'event') {
      if ($text -notin @('HEARTBEAT_EVENT', 'HEARTBEAT_RESOLVED')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'severity') {
      if (-not $script:SeverityRank.ContainsKey($text)) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'routeClass') {
      if ($text -notin @('governor', 'installer', 'development', 'owned')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'coverage') {
      if ($text -notin @('observed', 'partial', 'unsupported')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'state') {
      if ($interventionStates -notcontains $text) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'template') {
      if ($interventionTemplates -notcontains $text) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'postcondition') {
      if ($postconditions -notcontains $text) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'failureReason') {
      if ($text -notin @('none', 'ambiguous_target', 'target_not_live', 'target_policy_mismatch', 'target_generation_mismatch', 'transport_unavailable', 'user_authority_required', 'unsupported_action', 'self_target_forbidden', 'governor_usage_uncorroborated', 'retry_budget_exhausted', 'legacy_delivery_ambiguous', 'claim_expired_delivery_ambiguous')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'transportResult') {
      if ($text -notin @('none', 'accepted', 'definite_failure', 'unknown')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'taskResponse') {
      if ($text -notin @('none', 'acknowledged', 'outcome_reported', 'declined', 'user_authority_required', 'remediation_failed')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'verificationSource') {
      if ($text -notin @('none', 'heartbeat_engine', 'host_inventory', 'host_test', 'host_git')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'verificationResult') {
      if ($text -notin @('none', 'resolved', 'active', 'failed')) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -in @('status', 'testStatus', 'installStatus', 'dependencyStatus', 'taskStatus', 'validationStatus', 'buildStatus')) {
      if ($statusValues -notcontains $text) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'lastError') {
      if ($text -notmatch '^heartbeat_[a-z_]+$') { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'runtimeClassification') {
      if ($text -notin @('unobserved', 'within_budget', 'normal_variance', 'elevated_variance', 'sustained_overrun', 'material_overrun')) { throw 'heartbeat_state_invalid' }
    } else {
      throw 'heartbeat_state_invalid'
    }
  }
}

function Assert-State {
  param($State, [string]$ExpectedScopeHash)
  if (-not ($State -is [System.Collections.IDictionary])) { throw 'heartbeat_state_invalid' }
  $top = @('schema', 'revision', 'scopeHash', 'previous', 'conditions', 'events', 'outbox', 'interventions', 'collectors', 'health', 'runIds')
  foreach ($key in $State.Keys) { if ($top -notcontains [string]$key) { throw 'heartbeat_state_invalid' } }
  if ([int]$State.schema -ne 7 -or [int64]$State.revision -lt 0 -or [string]$State.scopeHash -ne $ExpectedScopeHash) { throw 'heartbeat_state_invalid' }
  if (-not ($State.previous -is [System.Collections.IDictionary]) -or -not ($State.conditions -is [System.Collections.IDictionary]) -or -not ($State.collectors -is [System.Collections.IDictionary]) -or -not ($State.health -is [System.Collections.IDictionary])) { throw 'heartbeat_state_invalid' }
  if ($State.conditions.Count -gt $script:ConditionLimit -or @($State.events).Count -gt $script:EventLimit -or @($State.outbox).Count -gt $script:OutboxLimit -or @($State.interventions).Count -gt $script:InterventionLimit -or @($State.runIds).Count -gt $script:RunIdLimit) { throw 'heartbeat_state_invalid' }
  $snapshotFields = @('generationHash', 'active', 'progressHash', 'repeated', 'idleMinutes', 'tokens', 'totalTokens', 'longRunning', 'status', 'reviewCount', 'reviewsPerHour', 'ratio', 'turnShare', 'repeats', 'executions', 'pendingAllowed', 'acceleration', 'recursion', 'rate', 'baselineRate', 'projectionMinutes', 'reviewerShare', 'meaningfulProgress', 'role', 'progressCountersObserved', 'completedCycles', 'stateChanges', 'acknowledgedEvents', 'failedCycles', 'duplicateRuns', 'childCount', 'forkDepth', 'overlap', 'compactions', 'rolloutBytes', 'growthRate', 'childRate', 'recursive', 'commitHash', 'suiteHash', 'repairAttempts', 'failureCount', 'environmentHash', 'required', 'ran', 'regressionActive', 'versionHash', 'intendedHash', 'drift', 'testStatus', 'installStatus', 'missingSkills', 'mcpConfigured', 'dependencyStatus', 'taskStatus', 'ageHours', 'assigned', 'acknowledgedBug', 'requiredCommit', 'requiredPush', 'requiredValidation', 'validationStatus', 'actionableActive', 'dirty', 'completedTaskIdle', 'requiresCommit', 'requiresPush', 'idleMinutes', 'ahead', 'behind', 'mergeConflict', 'branchChanged', 'destructiveOperation', 'expectedCommitPushed', 'conflictingScopes', 'buildStatus', 'identityMismatch', 'missingFiles', 'manifestMatches', 'sizeRatio', 'artifactHashMatches', 'schedulerDuplicates', 'runtimeSeconds', 'runtimeMs', 'runtimeBudgetMs', 'runtimeOverrunMs', 'runtimeOverrunPercent', 'runtimeBaselineMs', 'runtimeClassification', 'runtimeOverrunStreak', 'runtimeBackoffApplied')
  foreach ($family in $script:Families) {
    if (-not $State.previous.Contains($family) -or -not ($State.previous[$family] -is [System.Collections.IDictionary]) -or $State.previous[$family].Count -gt 128) { throw 'heartbeat_state_invalid' }
    foreach ($recordKey in $State.previous[$family].Keys) {
      if ([string]$recordKey -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_state_invalid' }
      Assert-StateRecord $State.previous[$family][$recordKey] $snapshotFields
    }
    if (-not $State.collectors.Contains($family)) { throw 'heartbeat_state_invalid' }
    Assert-StateRecord $State.collectors[$family] @('cadenceSeconds', 'lastAttempt', 'lastRun', 'lastSuccess', 'coverage', 'skippedCadence', 'backoffUntilUtc', 'sourceEpochHash', 'lastSequence')
  }
  foreach ($conditionKey in $State.conditions.Keys) {
    if ([string]$conditionKey -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_state_invalid' }
    Assert-StateRecord $State.conditions[$conditionKey] @('family', 'type', 'severity', 'open', 'firstObserved', 'lastObserved', 'lastNotified', 'occurrences', 'episode', 'sourceEpochHash', 'signatureHash', 'subjectHash', 'ownerHash', 'routeClass', 'resolutionNotified', 'resolvedAt')
    if ([string]$State.conditions[$conditionKey].family -notin $script:Families -or [string]$State.conditions[$conditionKey].severity -notin $script:SeverityRank.Keys) { throw 'heartbeat_state_invalid' }
  }
  foreach ($event in @($State.events)) {
    Assert-StateRecord $event @('type', 'severity', 'routeClass', 'detected', 'dedupHash')
  }
  foreach ($item in @($State.outbox)) {
    Assert-StateRecord $item @('eventId', 'event', 'type', 'severity', 'subjectHash', 'ownerHash', 'conditionHash', 'routeHash', 'routeClass', 'detected', 'attempts', 'lastAttempt', 'governorOrigin', 'expectedTargetGenerationHash')
    if ([string]$item.eventId -notmatch '^[a-f0-9]{64}$' -or [string]$item.conditionHash -notmatch '^[a-f0-9]{64}$' -or [string]$item.routeHash -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_state_invalid' }
    if ([string]$item.event -notin @('HEARTBEAT_EVENT', 'HEARTBEAT_RESOLVED')) { throw 'heartbeat_state_invalid' }
  }
  foreach ($item in @($State.interventions)) {
    Assert-StateRecord $item @('interventionId', 'eventId', 'conditionHash', 'type', 'severity', 'version', 'targetHash', 'targetGenerationHash', 'governorHash', 'state', 'attempts', 'claimHash', 'claimExpiresAt', 'createdAt', 'updatedAt', 'template', 'postcondition', 'resolutionNoticeRequired', 'escalationSent', 'coalescedCount', 'failureReason', 'transportResult', 'taskResponse', 'verificationSource', 'verificationResult')
    if ([int]$item.version -lt 1 -or [int]$item.attempts -lt 0 -or [int]$item.attempts -gt 2 -or [int]$item.coalescedCount -lt 0) { throw 'heartbeat_state_invalid' }
  }
  Assert-StateRecord $State.health @('runs', 'suppressedDuplicates', 'routesEmitted', 'resolutionEvents', 'duplicateRuns', 'acknowledgedEvents', 'failedCycles', 'mutexContention', 'lastCycleUtc', 'lastSuccessUtc', 'lastDurationMs', 'lastRunIdHash', 'lastError', 'backoffUntilUtc', 'deliveryAttempts', 'runtimeBudgetMs', 'runtimeObservedMs', 'runtimeOverrunMs', 'runtimeOverrunPercent', 'runtimeBaselineMs', 'runtimeClassification', 'runtimeOverrunStreak', 'runtimeBackoffApplied')
  foreach ($runId in @($State.runIds)) { if ([string]$runId -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_state_invalid' } }
}

function Upgrade-State {
  param($State)
  if ([int](Get-Value $State 'schema' 0) -eq 4) {
    if (-not (Has-Value $State 'interventions')) { $State['interventions'] = @() }
    foreach ($item in @($State.outbox)) {
      if (-not (Has-Value $item 'ownerHash')) { $item['ownerHash'] = Get-StableHash '' }
      if (-not (Has-Value $item 'governorOrigin')) {
        # Legacy usage delivery cannot prove a non-Governor owner. Require
        # corroboration instead of permitting a worker wake after upgrade.
        $item['governorOrigin'] = ([string]$item.type -eq 'USAGE_BURN')
      }
    }
    $State.schema = 5
  }
  if ([int](Get-Value $State 'schema' 0) -eq 5) {
    if (-not (Has-Value $State.health 'acknowledgedEvents')) { $State.health['acknowledgedEvents'] = 0L }
    if (-not (Has-Value $State.health 'failedCycles')) { $State.health['failedCycles'] = 0L }
    $State.schema = 6
  }
  if ([int](Get-Value $State 'schema' 0) -eq 6) {
    $runtimeDefaults = [ordered]@{ runtimeBudgetMs = 0; runtimeObservedMs = 0; runtimeOverrunMs = 0; runtimeOverrunPercent = 0; runtimeBaselineMs = 0; runtimeClassification = 'unobserved'; runtimeOverrunStreak = 0; runtimeBackoffApplied = $false }
    foreach ($name in $runtimeDefaults.Keys) { if (-not (Has-Value $State.health $name)) { $State.health[$name] = $runtimeDefaults[$name] } }
    $legacyGovernorHash = Get-StableHash 'legacy-governor-unassigned'
    foreach ($item in @($State.interventions)) {
      if (-not (Has-Value $item 'governorHash')) { $item['governorHash'] = $legacyGovernorHash }
      if (-not (Has-Value $item 'claimExpiresAt')) { $item['claimExpiresAt'] = $null }
      if ([string]$item.state -eq 'send_claimed' -and -not $item.claimExpiresAt) {
        # A legacy claimed send may already have reached the host. Preserve the
        # ambiguity and make it visible, but never synthesize a retry.
        $item.state = 'delivery_unknown'
        $item.claimHash = $null
        $item.transportResult = 'unknown'
        $item.failureReason = 'legacy_delivery_ambiguous'
      }
    }
    $State.schema = 7
  }
  return $State
}

function Read-State {
  param([string]$Path, [string]$ScopeHash)
  if (-not (Test-Path -LiteralPath $Path)) { return New-DefaultState $ScopeHash }
  try {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $script:StateByteLimit) { throw 'invalid' }
    $text = Read-StrictUtf8JsonFile $Path $script:StateByteLimit 'heartbeat_state_invalid'
    $state = ConvertTo-Hashtable ($text | ConvertFrom-Json -ErrorAction Stop)
    $originalSchema = [int](Get-Value $state 'schema' 0)
    $state = Upgrade-State $state
    Assert-State $state $ScopeHash
    if ([int]$state.schema -ne $originalSchema) { Write-State $state $Path }
    return $state
  } catch { throw 'heartbeat_state_invalid' }
}

function Write-State {
  param($State, [string]$Path)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  if (-not (Test-NoReparseAncestors $directory)) { throw 'heartbeat_state_path_invalid' }
  $temporary = Join-Path $directory ('.heartbeat-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $backup = Join-Path $directory ('.heartbeat-' + [guid]::NewGuid().ToString('N') + '.bak')
  try {
    $json = $State | ConvertTo-Json -Compress -Depth 16
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    if ($bytes.Length -gt $script:StateByteLimit) { throw 'heartbeat_state_too_large' }
    $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    $written = Read-StrictUtf8JsonFile $temporary $script:StateByteLimit 'heartbeat_state_invalid'
    [void]($written | ConvertFrom-Json -ErrorAction Stop)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      [IO.File]::Replace($temporary, $Path, $backup, $true)
    } else {
      [IO.File]::Move($temporary, $Path)
    }
  } catch {
    if ([string]$_.Exception.Message -match '^heartbeat_state_') { throw }
    throw 'heartbeat_state_store_unwritable'
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
  }
}

function Import-LegacyStateIfPresent {
  param($Resolved)
  if ($script:StateStoreMode -ne 'temp_private' -or
      (Test-Path -LiteralPath $Resolved.Path)) {
    if ($script:StateStoreMode -eq 'temp_private') { $script:PriorStateDisposition = 'not_checked_existing_v2' }
    return
  }
  $unavailable = $false
  $invalid = $false
  foreach ($candidate in @(
    [pscustomobject]@{ Path = [string]$Resolved.PriorTempPath; Directory = [string]$Resolved.PriorTempDirectory; Imported = 'prior_temp_state_imported'; DetectDirectory = $true },
    [pscustomobject]@{ Path = [string]$Resolved.LegacyPath; Directory = $null; Imported = 'legacy_state_imported'; DetectDirectory = $false }
  )) {
    if ([string]::IsNullOrWhiteSpace($candidate.Path)) { continue }
    if (-not (Test-NoReparseAncestors $candidate.Path)) {
      $invalid = $true
      if ($candidate.DetectDirectory) { break }
      continue
    }
    try {
      $item = Get-Item -LiteralPath $candidate.Path -Force -ErrorAction Stop
    } catch {
      $accessDenied = $_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::PermissionDenied -or
        $_.Exception -is [UnauthorizedAccessException] -or
        $_.Exception.InnerException -is [UnauthorizedAccessException]
      if ($accessDenied) { $unavailable = $true }
      elseif ($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ObjectNotFound -and $candidate.DetectDirectory) {
        # Windows can normalize a child lookup beneath a sandbox-owned directory
        # to ObjectNotFound. The exact scoped directory is a safe existence
        # signal; Chronos never changes or takes ownership of it.
        try {
          $priorDirectory = Get-Item -LiteralPath $candidate.Directory -Force -ErrorAction Stop
          if (-not $priorDirectory.PSIsContainer -or ($priorDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $invalid = $true }
          else {
            try {
              # Force one bounded directory enumeration. An accessible empty
              # directory means the old state is absent; an access failure means
              # Windows hid the child beneath an unavailable scoped directory.
              [void]@(Get-ChildItem -LiteralPath $candidate.Directory -Force -ErrorAction Stop | Select-Object -First 1)
            } catch {
              $enumerationDenied = $_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::PermissionDenied -or
                $_.Exception -is [UnauthorizedAccessException] -or
                $_.Exception.InnerException -is [UnauthorizedAccessException]
              if ($enumerationDenied) { $unavailable = $true }
              else { $invalid = $true }
            }
          }
        } catch {
          $directoryAccessDenied = $_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::PermissionDenied -or
            $_.Exception -is [UnauthorizedAccessException] -or
            $_.Exception.InnerException -is [UnauthorizedAccessException]
          if ($directoryAccessDenied) { $unavailable = $true }
          elseif ($_.CategoryInfo.Category -ne [Management.Automation.ErrorCategory]::ObjectNotFound) { $invalid = $true }
        }
      } elseif ($_.CategoryInfo.Category -ne [Management.Automation.ErrorCategory]::ObjectNotFound) { $invalid = $true }
      if ($candidate.DetectDirectory -and ($unavailable -or $invalid)) { break }
      continue
    }
    if ($item.PSIsContainer) {
      $invalid = $true
      if ($candidate.DetectDirectory) { break }
      continue
    }
    try {
      $probe = New-Object IO.FileStream($candidate.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
      $probe.Dispose()
    } catch {
      if ($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::PermissionDenied -or
          $_.Exception -is [UnauthorizedAccessException] -or
          $_.Exception.InnerException -is [UnauthorizedAccessException]) { $unavailable = $true }
      else { $invalid = $true }
      if ($candidate.DetectDirectory) { break }
      continue
    }
    try {
      $legacy = Read-State $candidate.Path $Resolved.ScopeHash
      Write-State $legacy $Resolved.Path
      $script:StateStoreMigration = $candidate.Imported
      $script:PriorStateDisposition = 'read_only_imported'
      return
    } catch {
      if ($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::PermissionDenied -or
          $_.Exception -is [UnauthorizedAccessException] -or
          $_.Exception.InnerException -is [UnauthorizedAccessException]) { $unavailable = $true }
      else { $invalid = $true }
      if ($candidate.DetectDirectory) { break }
    }
  }
  if ($unavailable) {
    $script:StateStoreMigration = 'prior_state_unavailable_new_root'
    $script:PriorStateDisposition = 'unavailable_preserved'
  } elseif ($invalid) {
    $script:StateStoreMigration = 'prior_state_invalid_rebuilt'
    $script:PriorStateDisposition = 'invalid_preserved'
  } else {
    $script:StateStoreMigration = 'namespace_v2_new_root'
    $script:PriorStateDisposition = 'not_found'
  }
}

function New-DetectorResult {
  return [pscustomobject]@{
    Candidates = [Collections.Generic.List[object]]::new()
    Routes = @{}
    Snapshot = @{}
  }
}

function Get-ConditionIdentity {
  param([string]$Family, [string]$Subject, [string]$Reason)
  $subjectHash = Get-StableHash $Subject
  $dedupKey = '{0}:{1}:{2}' -f $Family, $subjectHash.Substring(0, 16), $Reason
  return [pscustomobject]@{ DedupKey = $dedupKey; ConditionHash = (Get-StableHash $dedupKey); SubjectHash = $subjectHash }
}

function Add-RouteHint {
  param($Result, $Identity, $Subject, $Owner, $Thread)
  $Result.Routes[$Identity.ConditionHash] = [pscustomobject]@{ Subject = $Subject; Owner = $Owner; Thread = $Thread }
}

function New-Candidate {
  param([string]$Family, [string]$Type, [string]$Severity, [string]$Subject, $Owner, $Thread, [string]$Reason, [string[]]$Changed, [string[]]$Evidence, [string]$Cause, [string]$RecommendedAction, [DateTimeOffset]$Detected, [string]$TargetGenerationHash = $null)
  $identity = Get-ConditionIdentity $Family $Subject $Reason
  return [pscustomobject]@{
    Family = $Family
    ConditionHash = $identity.ConditionHash
    SubjectHash = $identity.SubjectHash
    Type = $Type
    Severity = $Severity
    Subject = $Subject
    Owner = $Owner
    OwningSolThread = $Thread
    Detected = $Detected.ToString('o')
    Changed = @($Changed)
    Evidence = @($Evidence)
    LikelyCause = $Cause
    RecommendedAction = $RecommendedAction
    DedupKey = $identity.DedupKey
    TargetGenerationHash = $TargetGenerationHash
  }
}

function Add-Candidate {
  param($Result, $Candidate)
  $Result.Candidates.Add($Candidate) | Out-Null
  $Result.Routes[$Candidate.ConditionHash] = [pscustomobject]@{ Subject = $Candidate.Subject; Owner = $Candidate.Owner; Thread = $Candidate.OwningSolThread }
}

function Get-ProgressHash {
  param($Record, [string[]]$Fields)
  $values = [ordered]@{}
  foreach ($field in $Fields) { if (Has-Value $Record $field) { $values[$field] = $Record[$field] } }
  return Get-StableHash $values
}

function Get-AgentDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  foreach ($agent in (As-Array (Get-Value $Snapshot 'agents'))) {
    $id = [string]$agent.id
    $idHash = Get-StableHash $id
    $generationHash = Get-StableHash ([string](Get-Value $agent 'generation' 'generation-unavailable'))
    $observedGenerationHash = if (Has-Value $agent 'generation') { $generationHash } else { $null }
    $progressHash = Get-ProgressHash $agent @('progressHash', 'lastToolHash', 'lastCommandHash', 'lastFileChangeUtc', 'lastGitHash', 'lastTestHash', 'status')
    $current = [ordered]@{
      generationHash = $generationHash
      active = [bool]$agent.active
      progressHash = $progressHash
      repeated = [int](Get-Value $agent 'repeatedEquivalentActions' 0)
      idleMinutes = [double](Get-Value $agent 'minutesSinceMeaningfulChange' 0)
      tokens = [int64](Get-Value $agent 'tokensSinceMeaningfulChange' 0)
      totalTokens = [int64](Get-Value $agent 'totalTokens' 0)
      longRunning = [bool](Get-Value $agent 'longRunningOperation' $false)
      status = [string](Get-Value $agent 'status' 'unknown')
    }
    $result.Snapshot[$idHash] = $current
    $conditionReason = 'progress:' + $generationHash
    $identity = Get-ConditionIdentity 'agent_stall' $id $conditionReason
    Add-RouteHint $result $identity $id (Get-Value $agent 'owner') (Get-Value $agent 'owningSolThread')
    if (-not $current.active -or $current.longRunning) { continue }
    $prior = Get-Value $Previous $idHash
    $compatiblePrior = $null -ne $prior -and [string](Get-Value $prior 'generationHash' '') -eq $generationHash
    $noProgress = $compatiblePrior -and [string]$prior.progressHash -eq $progressHash
    $tokenDelta = $current.tokens
    if ($compatiblePrior -and $current.totalTokens -ge [int64]$prior.totalTokens) { $tokenDelta = [math]::Max($tokenDelta, $current.totalTokens - [int64]$prior.totalTokens) }
    $absoluteExtreme = $current.repeated -ge 8 -and $current.idleMinutes -ge ($StallMinutes * 2)
    $stalled = ($noProgress -and $current.idleMinutes -ge $StallMinutes -and ($current.repeated -ge 3 -or $tokenDelta -ge 20000)) -or $absoluteExtreme
    if (-not $stalled) { continue }
    $severity = if ($current.repeated -ge 20 -or $tokenDelta -ge 500000) { 'CRITICAL' } elseif ($current.repeated -ge 8 -or $tokenDelta -ge 100000) { 'HIGH' } else { 'WARNING' }
    Add-Candidate $result (New-Candidate 'agent_stall' 'AGENT_STALL' $severity $id (Get-Value $agent 'owner') (Get-Value $agent 'owningSolThread') $conditionReason @('meaningfulProgress=unchanged', ('idleMinutes=' + (Format-Number $current.idleMinutes))) @('equivalentActions=' + $current.repeated, 'tokensWithoutProgress=' + $tokenDelta, 'generationHash=' + $generationHash.Substring(0, 16)) 'The active agent repeated work without a meaningful state delta.' 'Inspect the blocked operation. Stop or re-scope only the affected work.' $Now $observedGenerationHash)
  }
  return $result
}

function Get-GuardianDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  $guardian = Get-Value $Snapshot 'guardian'
  if ($null -eq $guardian) { return $result }
  $id = [string]$guardian.reviewerSessionId
  $idHash = Get-StableHash $id
  $ratio = [math]::Max([double](Get-Value $guardian 'reviewerUsageRatio' 0), [double](Get-Value $guardian 'reviewerTurnShare' 0))
  $current = [ordered]@{
    reviewCount = [int64](Get-Value $guardian 'reviewCount' 0)
    reviewsPerHour = [double](Get-Value $guardian 'reviewsPerHour' 0)
    ratio = $ratio
    turnShare = [double](Get-Value $guardian 'reviewerTurnShare' 0)
    repeats = [int](Get-Value $guardian 'equivalentApprovalRequests' 0)
    executions = [int](Get-Value $guardian 'approvalExecutionCount' 0)
    pendingAllowed = [int](Get-Value $guardian 'allowedPendingPostconditionCount' 0)
    acceleration = [double](Get-Value $guardian 'reviewAcceleration' 0)
    recursion = [bool](Get-Value $guardian 'reviewerRecursion' $false)
    progressHash = Get-ProgressHash $guardian @('progressHash', 'reviewCount', 'approvalExecutionCount')
  }
  $result.Snapshot[$idHash] = $current
  $identity = Get-ConditionIdentity 'guardian' $id 'runaway'
  Add-RouteHint $result $identity $id (Get-Value $guardian 'owner' 'governor') (Get-Value $guardian 'owningSolThread')
  $prior = Get-Value $Previous $idHash
  $reviewDelta = if ($prior) { [math]::Max(0, $current.reviewCount - [int64]$prior.reviewCount) } else { $current.reviewCount }
  $repeatDelta = if ($prior) { [math]::Max(0, $current.repeats - [int]$prior.repeats) } else { $current.repeats }
  $velocity = if ($prior -and [double]$prior.reviewsPerHour -gt 0) { $current.reviewsPerHour / [double]$prior.reviewsPerHour } elseif ($current.acceleration -gt 0) { $current.acceleration } else { 1 }
  $postconditionBroken = $current.pendingAllowed -gt 0
  $absoluteExtreme = $current.ratio -ge .85 -and $current.repeats -ge 5
  $runaway = ($current.ratio -ge .75 -and $repeatDelta -ge 3 -and $velocity -ge 1.5) -or $absoluteExtreme -or $current.recursion -or $postconditionBroken
  if ($runaway) {
    $severity = if ($current.recursion -and $current.repeats -ge 20) { 'CRITICAL' } elseif ($postconditionBroken -or $current.ratio -ge .85 -or $current.repeats -ge 8) { 'HIGH' } else { 'WARNING' }
    Add-Candidate $result (New-Candidate 'guardian' 'GUARDIAN_RUNAWAY' $severity $id (Get-Value $guardian 'owner' 'governor') (Get-Value $guardian 'owningSolThread') 'runaway' @('reviewVelocity=' + (Format-Number $velocity), 'reviewerShare=' + (Format-Number $current.ratio)) @('reviewDelta=' + $reviewDelta, 'equivalentApprovalDelta=' + $repeatDelta, 'allowedPendingPostconditions=' + $current.pendingAllowed) 'Automatic review or approval activity is amplifying without a matching execution postcondition.' 'Stop equivalent retries and inspect the approval state, rule match, and retry budget.' $Now)
  }
  return $result
}

function Get-UsageDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  $usage = Get-Value $Snapshot 'usage'
  if ($null -eq $usage) { return $result }
  $subject = [string](Get-Value $usage 'dominantThread' 'usage-window')
  $owner = [string](Get-Value $usage 'owner' 'governor')
  $role = [string](Get-Value $usage 'role' $(if ($owner -eq 'governor') { 'governor' } else { 'unknown' }))
  $isGovernor = $role -eq 'governor' -or $owner -eq 'governor'
  $progressCounterNames = @('completedCycles', 'stateChanges', 'acknowledgedEvents', 'failedCycles', 'duplicateRuns')
  $progressCountersObserved = @($progressCounterNames | Where-Object { Has-Value $usage $_ }).Count -eq $progressCounterNames.Count
  $idHash = Get-StableHash $subject
  $rate = [double](Get-Value $usage 'ratePerMinute' 0)
  if ($rate -le 0 -and (Get-Value $usage 'windowMinutes' 0) -gt 0) { $rate = [double](Get-Value $usage 'windowTokens' 0) / [double]$usage.windowMinutes }
  $current = [ordered]@{
    totalTokens = [int64](Get-Value $usage 'totalTokens' 0)
    rate = $rate
    baselineRate = [double](Get-Value $usage 'baselineRatePerMinute' 0)
    projectionMinutes = [double](Get-Value $usage 'projectedExhaustionMinutes' 0)
    reviewerShare = [double](Get-Value $usage 'reviewerShare' 0)
    meaningfulProgress = [bool](Get-Value $usage 'meaningfulProgress' $true)
    progressHash = Get-ProgressHash $usage @('progressHash')
    role = $role
    progressCountersObserved = $progressCountersObserved
    completedCycles = [int64](Get-Value $usage 'completedCycles' 0)
    stateChanges = [int64](Get-Value $usage 'stateChanges' 0)
    acknowledgedEvents = [int64](Get-Value $usage 'acknowledgedEvents' 0)
    failedCycles = [int64](Get-Value $usage 'failedCycles' 0)
    duplicateRuns = [int64](Get-Value $usage 'duplicateRuns' 0)
  }
  $result.Snapshot[$idHash] = $current
  $identity = Get-ConditionIdentity 'usage' $subject 'burn'
  Add-RouteHint $result $identity $subject $owner (Get-Value $usage 'owningSolThread')
  $prior = Get-Value $Previous $idHash
  $reference = if ($current.baselineRate -gt 0) { $current.baselineRate } elseif ($prior -and [double]$prior.rate -gt 0) { [double]$prior.rate } else { 0 }
  $rateMultiple = if ($reference -gt 0) { $current.rate / $reference } else { 1 }
  $governorCounterProgress = $prior -and $current.progressCountersObserved -and [bool](Get-Value $prior 'progressCountersObserved' $false) -and (
    $current.completedCycles -gt [int64](Get-Value $prior 'completedCycles' 0) -or
    $current.stateChanges -gt [int64](Get-Value $prior 'stateChanges' 0) -or
    $current.acknowledgedEvents -gt [int64](Get-Value $prior 'acknowledgedEvents' 0)
  )
  $hashProgress = $prior -and [string]$prior.progressHash -ne $current.progressHash
  $progressObserved = $current.meaningfulProgress -or $hashProgress -or $governorCounterProgress
  $governorProgressComparable = $prior -and $current.progressCountersObserved -and [bool](Get-Value $prior 'progressCountersObserved' $false)
  $projectionWorsened = $prior -and $current.projectionMinutes -gt 0 -and [double]$prior.projectionMinutes -gt 0 -and $current.projectionMinutes -le ([double]$prior.projectionMinutes * .7) -and (-not $isGovernor -or $governorProgressComparable)
  $noProgressDelta = if ($isGovernor) { $governorProgressComparable -and -not $progressObserved } else { -not $current.meaningfulProgress -and (-not $prior -or -not $hashProgress) }
  $burn = $current.rate -ge 10000 -and $rateMultiple -ge 2 -and $noProgressDelta
  if ($burn -or $projectionWorsened) {
    $severity = if ($current.projectionMinutes -gt 0 -and $current.projectionMinutes -le 10 -and $noProgressDelta) { 'CRITICAL' } elseif ($rateMultiple -ge 3 -or $current.reviewerShare -ge .75 -or $projectionWorsened) { 'HIGH' } else { 'WARNING' }
    $cause = if ($isGovernor) { 'Governor usage velocity worsened across comparable supervision cycles without polling, reconciliation, acknowledgement, or state-change progress.' } else { 'Usage velocity worsened without a matching progress signal.' }
    $action = if ($isGovernor) { 'Keep the condition Governor-local and increase only the Governor recurrence to the idle cadence until a comparable cycle shows progress.' } else { 'Bound the dominant task and inspect reviewer, fork, and repeated-tool contribution.' }
    Add-Candidate $result (New-Candidate 'usage' 'USAGE_BURN' $severity $subject $owner (Get-Value $usage 'owningSolThread') 'burn' @('rateMultiple=' + (Format-Number $rateMultiple), 'meaningfulProgress=' + $progressObserved, 'governorProgressComparable=' + $governorProgressComparable) @('tokensPerMinute=' + (Format-Number $current.rate), 'reviewerShare=' + (Format-Number $current.reviewerShare), 'projectedExhaustionMinutes=' + (Format-Number $current.projectionMinutes)) $cause $action $Now)
  }
  return $result
}

function Get-SessionDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  foreach ($session in (As-Array (Get-Value $Snapshot 'sessions'))) {
    $id = [string]$session.id
    $idHash = Get-StableHash $id
    $current = [ordered]@{
      childCount = [int](Get-Value $session 'childCount' 0)
      forkDepth = [int](Get-Value $session 'forkDepth' 0)
      overlap = [double](Get-Value $session 'contextOverlap' 0)
      compactions = [int64](Get-Value $session 'compactionCount' 0)
      rolloutBytes = [int64](Get-Value $session 'rolloutBytes' 0)
      growthRate = [double](Get-Value $session 'storageGrowthBytesPerHour' 0)
      childRate = [double](Get-Value $session 'childCreationRate' 0)
      recursive = [bool](Get-Value $session 'recursive' $false)
      progressHash = Get-ProgressHash $session @('progressHash', 'childCount', 'forkDepth', 'rolloutBytes')
    }
    $result.Snapshot[$idHash] = $current
    $identity = Get-ConditionIdentity 'sessions' $id 'explosion'
    Add-RouteHint $result $identity $id (Get-Value $session 'owner') (Get-Value $session 'owningSolThread')
    $prior = Get-Value $Previous $idHash
    $childDelta = if ($prior) { [math]::Max(0, $current.childCount - [int]$prior.childCount) } else { 0 }
    $growthDelta = if ($prior) { [math]::Max(0, $current.rolloutBytes - [int64]$prior.rolloutBytes) } else { 0 }
    $absolute = $current.childCount -ge 8 -and $current.forkDepth -ge 3 -and $current.overlap -ge .75
    $transition = $prior -and $childDelta -ge 4 -and $current.overlap -ge .75 -and ($current.recursive -or $current.forkDepth -ge 3)
    if ($absolute -or $transition) {
      $severity = if ($current.childCount -ge 24 -and $current.overlap -ge .9) { 'CRITICAL' } elseif ($current.childCount -ge 12 -or $current.recursive -or $growthDelta -ge 1073741824) { 'HIGH' } else { 'WARNING' }
      Add-Candidate $result (New-Candidate 'sessions' 'SESSION_EXPLOSION' $severity $id (Get-Value $session 'owner') (Get-Value $session 'owningSolThread') 'explosion' @('childDelta=' + $childDelta, 'forkDepth=' + $current.forkDepth) @('children=' + $current.childCount, 'contextOverlap=' + (Format-Number $current.overlap), 'rolloutGrowthBytes=' + $growthDelta) 'Repeated forks are replaying highly overlapping context.' 'Stop recursive forks and reduce inherited context before creating more workers.' $Now)
    }
  }
  return $result
}

function Get-EnvironmentStatusValues {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Collections.IDictionary]) { return @($Value.Values) }
  return @($Value)
}

function Get-TestEnvironmentIdentityHash {
  param($Value)
  if ($Value -is [System.Collections.IDictionary]) {
    return Get-StableHash (@($Value.Keys | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Sort-Object))
  }
  if ($null -eq $Value) { return Get-StableHash 'environment-unavailable' }
  return Get-StableHash 'environment-unidentified'
}

function Get-TestDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  foreach ($test in (As-Array (Get-Value $Snapshot 'tests'))) {
    $name = [string]$test.name
    $idHash = Get-StableHash $name
    $prior = Get-Value $Previous $idHash
    $environmentStatuses = Get-Value $test 'environmentStatuses'
    $environmentValues = @(Get-EnvironmentStatusValues $environmentStatuses)
    $environmentHash = Get-TestEnvironmentIdentityHash $environmentStatuses
    $commitHash = if (Has-Value $test 'commit') { Get-StableHash ([string]$test.commit) } else { Get-StableHash 'unknown' }
    $suiteHash = if (Has-Value $test 'buildId') { Get-StableHash ([string]$test.buildId) } else { Get-StableHash ('test-suite:' + $name) }
    $generationHash = Get-StableHash ([string](Get-Value $test 'generation' 'generation-unavailable'))
    $observedGenerationHash = if (Has-Value $test 'generation') { $generationHash } else { $null }
    $current = [ordered]@{
      status = [string]$test.status
      commitHash = $commitHash
      suiteHash = $suiteHash
      generationHash = $generationHash
      repairAttempts = [int](Get-Value $test 'repairAttempts' 0)
      failureCount = [int](Get-Value $test 'failureCount' 0)
      environmentHash = $environmentHash
      required = [bool](Get-Value $test 'required' $false)
      ran = [bool](Get-Value $test 'ran' $true)
      regressionActive = $false
    }
    foreach ($reason in @('regression', 'environment-drift', 'validation-missing')) {
      $identityReason = if ($reason -eq 'regression') { '{0}:{1}:{2}:{3}' -f $reason, $environmentHash, $suiteHash, $generationHash } else { '{0}:{1}' -f $reason, $generationHash }
      $identity = Get-ConditionIdentity 'tests' $name $identityReason
      Add-RouteHint $result $identity $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread')
    }
    $compatiblePrior = $prior -and [string]$prior.environmentHash -eq $environmentHash -and [string](Get-Value $prior 'suiteHash' '') -eq $suiteHash -and [string](Get-Value $prior 'generationHash' '') -eq $generationHash
    $regressed = $compatiblePrior -and [string]$prior.status -eq 'passed' -and $current.status -eq 'failed'
    $repairWorsened = $compatiblePrior -and $current.status -eq 'failed' -and $current.repairAttempts -gt [int]$prior.repairAttempts -and $current.repairAttempts -ge 2
    $current.regressionActive = $current.status -eq 'failed' -and ($regressed -or $repairWorsened -or ($compatiblePrior -and [bool](Get-Value $prior 'regressionActive' $false)))
    $result.Snapshot[$idHash] = $current
    if ($current.regressionActive) {
      $severity = if ($current.repairAttempts -ge 4 -or $current.failureCount -ge 5) { 'CRITICAL' } else { 'HIGH' }
      Add-Candidate $result (New-Candidate 'tests' 'TEST_REGRESSION' $severity $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread') ('regression:{0}:{1}:{2}' -f $environmentHash, $suiteHash, $generationHash) @('status=' + $(if ($regressed) { 'passed->failed' } else { 'failed->failed' })) @('repairAttempts=' + $current.repairAttempts, 'failureCount=' + $current.failureCount, 'commitHash=' + $commitHash.Substring(0, 16), 'environmentHash=' + $environmentHash.Substring(0, 16), 'suiteHash=' + $suiteHash.Substring(0, 16), 'generationHash=' + $generationHash.Substring(0, 16)) 'A known-good test regressed or remained broken after additional repair work.' 'Investigate the introducing change and preserve the failing evidence.' $Now $observedGenerationHash)
    }
    if (($environmentValues | Select-Object -Unique).Count -gt 1) {
      Add-Candidate $result (New-Candidate 'tests' 'TEST_ENVIRONMENT_DRIFT' 'WARNING' $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread') ('environment-drift:' + $generationHash) @('environmentResults=disagree') @('resultVariants=' + (($environmentValues | Select-Object -Unique).Count), 'generationHash=' + $generationHash.Substring(0, 16)) 'The same validation differs across supplied environments.' 'Compare installed version, configuration, and artifact identity.' $Now $observedGenerationHash)
    }
    if ($current.required -and -not $current.ran) {
      Add-Candidate $result (New-Candidate 'tests' 'TEST_VALIDATION_MISSING' 'WARNING' $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread') ('validation-missing:' + $generationHash) @('requiredValidation=not_run') @('status=' + $current.status, 'generationHash=' + $generationHash.Substring(0, 16)) 'Required validation was not run.' 'Run the required validation before release or handoff.' $Now $observedGenerationHash)
    }
  }
  return $result
}

function Get-MachineDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  $machines = As-Array (Get-Value $Snapshot 'machines')
  $fleetIdentities = @()
  foreach ($machine in $machines) {
    $id = [string]$machine.id
    $idHash = Get-StableHash $id
    $actual = '{0}|{1}|{2}|{3}' -f (Get-Value $machine 'version' ''), (Get-Value $machine 'commit' ''), (Get-Value $machine 'pluginVersion' ''), (Get-Value $machine 'manifestVersion' '')
    $intended = '{0}|{1}' -f (Get-Value $machine 'intendedVersion' ''), (Get-Value $machine 'intendedCommit' '')
    $versionMismatch = (Has-Value $machine 'intendedVersion') -and ([string]$machine.intendedVersion -ne [string](Get-Value $machine 'pluginVersion' (Get-Value $machine 'version')))
    $commitMismatch = (Has-Value $machine 'intendedCommit') -and ([string]$machine.intendedCommit -ne [string](Get-Value $machine 'commit'))
    $manifestMismatch = (Has-Value $machine 'pluginVersion') -and (Has-Value $machine 'manifestVersion') -and ([string]$machine.pluginVersion -ne [string]$machine.manifestVersion)
    $missingSkills = @(Get-Value $machine 'missingSkills' @()).Count
    $drift = $versionMismatch -or $commitMismatch -or $manifestMismatch -or $missingSkills -gt 0 -or [string](Get-Value $machine 'installStatus') -in @('failed', 'stale')
    $current = [ordered]@{
      versionHash = Get-StableHash $actual
      intendedHash = Get-StableHash $intended
      drift = $drift
      testStatus = [string](Get-Value $machine 'testStatus' 'unknown')
      installStatus = [string](Get-Value $machine 'installStatus' 'unknown')
      missingSkills = $missingSkills
      mcpConfigured = [bool](Get-Value $machine 'mcpConfigured' $false)
    }
    $result.Snapshot[$idHash] = $current
    $fleetIdentities += $current.versionHash
    $identity = Get-ConditionIdentity 'machines' $id 'identity'
    Add-RouteHint $result $identity $id (Get-Value $machine 'owner') (Get-Value $machine 'owningSolThread')
    if ($drift) {
      $severity = if ($current.installStatus -eq 'failed' -or $current.testStatus -eq 'failed') { 'HIGH' } else { 'WARNING' }
      Add-Candidate $result (New-Candidate 'machines' 'MACHINE_DRIFT' $severity $id (Get-Value $machine 'owner') (Get-Value $machine 'owningSolThread') 'identity' @('installedIdentity=unexpected') @('versionMismatch=' + $versionMismatch, 'commitMismatch=' + $commitMismatch, 'manifestMismatch=' + $manifestMismatch, 'missingSkills=' + $missingSkills) 'The installed machine state does not match its intended state.' 'Install the intended artifact or correct the intended deployment record.' $Now)
    }
  }
  $fleetIdentity = Get-ConditionIdentity 'machines' 'machine-fleet' 'fleet'
  if ($machines.Count -gt 0) { Add-RouteHint $result $fleetIdentity 'machine-fleet' (Get-Value $machines[0] 'owner' 'development') (Get-Value $machines[0] 'owningSolThread') }
  if ($machines.Count -gt 1) {
    $fleetIdentity = Get-ConditionIdentity 'machines' 'machine-fleet' 'fleet'
    Add-RouteHint $result $fleetIdentity 'machine-fleet' (Get-Value $machines[0] 'owner' 'development') (Get-Value $machines[0] 'owningSolThread')
    if (-not [bool](Get-Value $Snapshot 'allowMachineDrift' $false) -and ($fleetIdentities | Select-Object -Unique).Count -gt 1) {
      Add-Candidate $result (New-Candidate 'machines' 'MACHINE_DRIFT' 'WARNING' 'machine-fleet' (Get-Value $machines[0] 'owner' 'development') (Get-Value $machines[0] 'owningSolThread') 'fleet' @('fleetIdentity=diverged') @('identityVariants=' + (($fleetIdentities | Select-Object -Unique).Count)) 'Machines do not share the expected build identity.' 'Confirm whether the drift is intentional, then align the stale installation.' $Now)
    }
  }
  return $result
}

function Get-TaskDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  foreach ($task in (As-Array (Get-Value $Snapshot 'tasks'))) {
    $id = [string]$task.id
    $idHash = Get-StableHash $id
    $generationHash = Get-StableHash ([string](Get-Value $task 'generation' 'generation-unavailable'))
    $observedGenerationHash = if (Has-Value $task 'generation') { $generationHash } else { $null }
    $prior = Get-Value $Previous $idHash
    $current = [ordered]@{
      generationHash = $generationHash
      dependencyStatus = [string](Get-Value $task 'dependencyStatus' 'unknown')
      taskStatus = [string]$task.status
      ageHours = [double](Get-Value $task 'ageHours' 0)
      assigned = [bool](Get-Value $task 'assigned' (Has-Value $task 'owner'))
      acknowledgedBug = [bool](Get-Value $task 'acknowledgedBug' $false)
      requiredCommit = [bool](Get-Value $task 'requiredCommit' $false)
      requiredPush = [bool](Get-Value $task 'requiredPush' $false)
      requiredValidation = [bool](Get-Value $task 'requiredValidation' $false)
      validationStatus = [string](Get-Value $task 'validationStatus' 'unknown')
      actionableActive = $false
    }
    foreach ($reason in @('actionable', 'zombie', 'unfinished-handoff')) {
      $identity = Get-ConditionIdentity 'tasks' $id ($reason + ':' + $generationHash)
      Add-RouteHint $result $identity $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread')
    }
    $compatiblePrior = $prior -and [string](Get-Value $prior 'generationHash' '') -eq $generationHash
    $dependencyTransition = $compatiblePrior -and [string]$prior.dependencyStatus -ne 'completed' -and $current.dependencyStatus -eq 'completed'
    $current.actionableActive = $current.taskStatus -eq 'waiting' -and ($dependencyTransition -or ($compatiblePrior -and [bool](Get-Value $prior 'actionableActive' $false)))
    $result.Snapshot[$idHash] = $current
    if ($current.actionableActive) {
      Add-Candidate $result (New-Candidate 'tasks' 'TASK_ACTIONABLE' 'WARNING' $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread') ('actionable:' + $generationHash) @('dependencyStatus=incomplete->completed') @('dependencyHash=' + (Get-StableHash (Get-Value $task 'dependsOn' 'unknown')).Substring(0, 16), 'generationHash=' + $generationHash.Substring(0, 16)) 'A dependency completed while this task remained waiting.' 'Resume the owning task or explicitly reclassify it.' $Now $observedGenerationHash)
    }
    $zombie = (($current.taskStatus -eq 'todo' -or $current.acknowledgedBug) -and -not $current.assigned -and $current.ageHours -ge 24)
    if ($zombie) {
      Add-Candidate $result (New-Candidate 'tasks' 'ZOMBIE_TASK' 'WARNING' $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread') ('zombie:' + $generationHash) @('ownership=unassigned') @('ageHours=' + (Format-Number $current.ageHours), 'acknowledgedBug=' + $current.acknowledgedBug, 'generationHash=' + $generationHash.Substring(0, 16)) 'Recorded work has no active owner.' 'Assign the work or close it explicitly.' $Now $observedGenerationHash)
    }
    $unfinished = $current.taskStatus -eq 'completed' -and (($current.requiredValidation -and $current.validationStatus -ne 'passed') -or $current.requiredCommit -or $current.requiredPush)
    if ($unfinished) {
      Add-Candidate $result (New-Candidate 'tasks' 'TASK_HANDOFF_INCOMPLETE' 'WARNING' $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread') ('unfinished-handoff:' + $generationHash) @('task=completed', 'handoff=incomplete') @('validation=' + $current.validationStatus, 'commitRequired=' + $current.requiredCommit, 'pushRequired=' + $current.requiredPush, 'generationHash=' + $generationHash.Substring(0, 16)) 'Completed work still has a required handoff action.' 'Complete or explicitly waive the remaining commit, push, or validation step.' $Now $observedGenerationHash)
    }
  }
  return $result
}

function Get-GitBuildDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  $git = Get-Value $Snapshot 'git'
  $build = Get-Value $Snapshot 'build'
  $current = [ordered]@{}
  if ($git) {
    $current.dirty = [bool](Get-Value $git 'dirty' $false)
    $current.completedTaskIdle = [bool](Get-Value $git 'completedTaskIdle' $false)
    $current.requiresCommit = [bool](Get-Value $git 'requiresCommit' $false)
    $current.requiresPush = [bool](Get-Value $git 'requiresPush' $false)
    $current.idleMinutes = [double](Get-Value $git 'idleMinutes' 0)
    $current.ahead = [int](Get-Value $git 'ahead' 0)
    $current.behind = [int](Get-Value $git 'behind' 0)
    $current.mergeConflict = [bool](Get-Value $git 'mergeConflict' $false)
    $current.branchChanged = [bool](Get-Value $git 'branchChanged' $false)
    $current.destructiveOperation = [bool](Get-Value $git 'destructiveOperation' $false)
    $current.expectedCommitPushed = [bool](Get-Value $git 'expectedCommitPushed' $true)
    $current.conflictingScopes = [int](Get-Value $git 'conflictingScopes' 0)
  }
  if ($build) {
    $identityMismatch = ((Has-Value $build 'artifactCommit') -and (Has-Value $build 'expectedCommit') -and [string]$build.artifactCommit -ne [string]$build.expectedCommit) -or ((Has-Value $build 'artifactVersion') -and (Has-Value $build 'expectedVersion') -and [string]$build.artifactVersion -ne [string]$build.expectedVersion)
    $missingFiles = if (Has-Value $build 'missingFileCount') { [int]$build.missingFileCount } else { @(Get-Value $build 'missingFiles' @()).Count }
    $sizeRatio = 1.0
    if ((Get-Value $build 'previousPackageSizeBytes' 0) -gt 0) { $sizeRatio = [double](Get-Value $build 'packageSizeBytes' 0) / [double]$build.previousPackageSizeBytes }
    $current.buildStatus = [string](Get-Value $build 'status' 'unknown')
    $current.identityMismatch = $identityMismatch
    $current.missingFiles = $missingFiles
    $current.manifestMatches = [bool](Get-Value $build 'manifestMatches' $true)
    $current.sizeRatio = $sizeRatio
    $current.artifactHashMatches = [bool](Get-Value $build 'installerArtifactHashMatches' $true)
  }
  $result.Snapshot[(Get-StableHash 'repository-state')] = $current
  if ($git) {
    foreach ($reason in @('uncommitted', 'unsafe-git')) {
      $identity = Get-ConditionIdentity 'git_build' 'repository-state' $reason
      Add-RouteHint $result $identity 'repository-state' (Get-Value $git 'owner') (Get-Value $git 'owningSolThread')
    }
  }
  if ($build) {
    $identity = Get-ConditionIdentity 'git_build' 'repository-state' 'artifact'
    Add-RouteHint $result $identity 'repository-state' (Get-Value $build 'owner') (Get-Value $build 'owningSolThread')
  }
  if ($git -and $current.dirty -and $current.completedTaskIdle -and $current.requiresCommit) {
    Add-Candidate $result (New-Candidate 'git_build' 'GIT_BUILD_STATE' 'WARNING' 'repository-state' (Get-Value $git 'owner') (Get-Value $git 'owningSolThread') 'uncommitted' @('completedWork=uncommitted') @('idleMinutes=' + (Format-Number $current.idleMinutes)) 'Completed work remains uncommitted beyond its expected handoff.' 'Review, validate, and commit only the intended changes.' $Now)
  }
  if ($git -and ($current.mergeConflict -or $current.destructiveOperation -or $current.branchChanged -or $current.conflictingScopes -gt 0 -or ($current.requiresPush -and -not $current.expectedCommitPushed))) {
    $severity = if ($current.destructiveOperation -or $current.mergeConflict) { 'CRITICAL' } else { 'HIGH' }
    Add-Candidate $result (New-Candidate 'git_build' 'GIT_STATE_RISK' $severity 'repository-state' (Get-Value $git 'owner') (Get-Value $git 'owningSolThread') 'unsafe-git' @('repositoryState=unexpected') @('mergeConflict=' + $current.mergeConflict, 'branchChanged=' + $current.branchChanged, 'conflictingScopes=' + $current.conflictingScopes, 'expectedCommitPushed=' + $current.expectedCommitPushed) 'Repository state conflicts with the expected task handoff.' 'Stop new writes and verify ownership, branch, and intended commit before continuing.' $Now)
  }
  if ($build -and ($current.buildStatus -in @('failed', 'missing') -or $current.identityMismatch -or $current.missingFiles -gt 0 -or -not $current.manifestMatches -or -not $current.artifactHashMatches -or $current.sizeRatio -lt .5 -or $current.sizeRatio -gt 1.5)) {
    $severity = if (-not $current.artifactHashMatches -or $current.identityMismatch) { 'HIGH' } else { 'WARNING' }
    Add-Candidate $result (New-Candidate 'git_build' 'BUILD_ARTIFACT_DRIFT' $severity 'repository-state' (Get-Value $build 'owner') (Get-Value $build 'owningSolThread') 'artifact' @('artifactState=unexpected') @('buildStatus=' + $current.buildStatus, 'identityMismatch=' + $current.identityMismatch, 'missingFiles=' + $current.missingFiles, 'manifestMatches=' + $current.manifestMatches, 'sizeRatio=' + (Format-Number $current.sizeRatio)) 'The build or package does not match its intended source state.' 'Rebuild from the intended commit and verify the manifest and artifact checksum.' $Now)
  }
  return $result
}

function Get-HeartbeatDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  $activity = Get-Value $Snapshot 'heartbeatActivity'
  if ($null -eq $activity) { return $result }
  $recordKey = Get-StableHash 'heartbeat-engine'
  $prior = Get-Value $Previous $recordKey @{}
  $runtimeMs = if (Has-Value $activity 'runtimeMilliseconds') { [double]$activity.runtimeMilliseconds } else { [double](Get-Value $activity 'runtimeSeconds' 0) * 1000.0 }
  $runtimeBudgetMs = if (Has-Value $activity 'runtimeBudgetMilliseconds') { [double]$activity.runtimeBudgetMilliseconds } else { 30000.0 }
  if ($runtimeBudgetMs -le 0) { $runtimeBudgetMs = 30000.0 }
  $priorBaselineMs = [double](Get-Value $prior 'runtimeBaselineMs' 0)
  if ($priorBaselineMs -le 0) { $priorBaselineMs = [math]::Min($runtimeMs, $runtimeBudgetMs) }
  $overrunMs = [math]::Max(0.0, $runtimeMs - $runtimeBudgetMs)
  $overrunPercent = if ($runtimeBudgetMs -gt 0) { [math]::Round(($overrunMs / $runtimeBudgetMs) * 100.0, 1) } else { 0.0 }
  $overrunStreak = if ($overrunMs -gt 0) { [int](Get-Value $prior 'runtimeOverrunStreak' 0) + 1 } else { 0 }
  $varianceLimitMs = [math]::Max($runtimeBudgetMs + [math]::Max(1000.0, $runtimeBudgetMs * 0.10), $priorBaselineMs * 1.25)
  $materialLimitMs = [math]::Max($runtimeBudgetMs * 1.50, $priorBaselineMs * 1.50)
  $runtimeClassification = if ($overrunMs -le 0) {
    'within_budget'
  } elseif ($runtimeMs -ge $materialLimitMs) {
    'material_overrun'
  } elseif ($overrunStreak -ge 3) {
    'sustained_overrun'
  } elseif ($runtimeMs -le $varianceLimitMs) {
    'normal_variance'
  } else {
    'elevated_variance'
  }
  $runtimeBackoffApplied = $runtimeClassification -in @('material_overrun', 'sustained_overrun')
  $runtimeBaselineMs = $priorBaselineMs
  if ($runtimeClassification -in @('within_budget', 'normal_variance')) {
    $runtimeBaselineMs = if ($priorBaselineMs -gt 0) { [math]::Round(($priorBaselineMs * 0.75) + ($runtimeMs * 0.25), 1) } else { [math]::Round($runtimeMs, 1) }
  }
  $current = [ordered]@{
    schedulerDuplicates = [int](Get-Value $activity 'schedulerDuplicates' 0)
    runtimeSeconds = [math]::Round($runtimeMs / 1000.0, 3)
    runtimeMs = [math]::Round($runtimeMs, 1)
    runtimeBudgetMs = [math]::Round($runtimeBudgetMs, 1)
    runtimeOverrunMs = [math]::Round($overrunMs, 1)
    runtimeOverrunPercent = $overrunPercent
    runtimeBaselineMs = $runtimeBaselineMs
    runtimeClassification = $runtimeClassification
    runtimeOverrunStreak = $overrunStreak
    runtimeBackoffApplied = $runtimeBackoffApplied
  }
  $result.Snapshot[$recordKey] = $current
  $identity = Get-ConditionIdentity 'heartbeat' 'heartbeat-engine' 'self-health'
  Add-RouteHint $result $identity 'heartbeat-engine' 'governor' 'governor'
  $shouldBackoff = $current.schedulerDuplicates -ge 2 -or $runtimeBackoffApplied
  if ($shouldBackoff) {
    $severity = if ($current.schedulerDuplicates -ge 5 -or $runtimeMs -ge ($runtimeBudgetMs * 2.0)) { 'CRITICAL' } else { 'HIGH' }
    $reason = if ($current.schedulerDuplicates -ge 2) { 'duplicate_scheduler' } else { $runtimeClassification }
    $changed = @('monitoringHealth=degraded', ('classification={0}' -f $reason))
    $evidence = @(
      ('schedulerDuplicates={0}' -f $current.schedulerDuplicates)
      ('runtimeBudgetMs={0}' -f (Format-Number $current.runtimeBudgetMs))
      ('runtimeObservedMs={0}' -f (Format-Number $current.runtimeMs))
      ('runtimeOverrunMs={0}' -f (Format-Number $current.runtimeOverrunMs))
      ('runtimeOverrunPercent={0}' -f (Format-Number $current.runtimeOverrunPercent))
      ('runtimeBaselineMs={0}' -f (Format-Number $current.runtimeBaselineMs))
      ('runtimeOverrunStreak={0}' -f $current.runtimeOverrunStreak)
      'backoffApplied=true'
    )
    Add-Candidate $result (New-Candidate 'heartbeat' 'HEARTBEAT_SELF_HEALTH' $severity 'heartbeat-engine' 'governor' 'governor' 'self-health' $changed $evidence 'Heartbeat scheduling or sustained runtime is abnormal.' 'Keep one scheduler owner and back off only sustained or material runtime degradation.' $Now)
  }
  return $result
}

function Invoke-Detector {
  param([string]$Family, $Snapshot, $Previous, [DateTimeOffset]$Now)
  switch ($Family) {
    'agent_stall' { return Get-AgentDetector $Snapshot $Previous $Now }
    'guardian' { return Get-GuardianDetector $Snapshot $Previous $Now }
    'usage' { return Get-UsageDetector $Snapshot $Previous $Now }
    'sessions' { return Get-SessionDetector $Snapshot $Previous $Now }
    'tests' { return Get-TestDetector $Snapshot $Previous $Now }
    'machines' { return Get-MachineDetector $Snapshot $Previous $Now }
    'tasks' { return Get-TaskDetector $Snapshot $Previous $Now }
    'git_build' { return Get-GitBuildDetector $Snapshot $Previous $Now }
    'heartbeat' { return Get-HeartbeatDetector $Snapshot $Previous $Now }
  }
  throw 'heartbeat_family_invalid'
}

function Test-FamilyPresent {
  param($Snapshot, [string]$Family)
  switch ($Family) {
    'agent_stall' { return Has-Value $Snapshot 'agents' }
    'guardian' { return Has-Value $Snapshot 'guardian' }
    'usage' { return Has-Value $Snapshot 'usage' }
    'sessions' { return Has-Value $Snapshot 'sessions' }
    'tests' { return Has-Value $Snapshot 'tests' }
    'machines' { return Has-Value $Snapshot 'machines' }
    'tasks' { return Has-Value $Snapshot 'tasks' }
    'git_build' { return (Has-Value $Snapshot 'git') -or (Has-Value $Snapshot 'build') }
    'heartbeat' { return Has-Value $Snapshot 'heartbeatActivity' }
  }
  return $false
}

function Test-FamilyDue {
  param($Collector, [DateTimeOffset]$Now, [bool]$Force)
  if ($Force) { return $true }
  if (-not [string]::IsNullOrWhiteSpace([string]$Collector.backoffUntilUtc)) {
    $backoff = ConvertTo-UtcTimestamp ([string]$Collector.backoffUntilUtc) 'heartbeat_state_invalid'
    if ($Now -lt $backoff) { return $false }
  }
  if ([string]::IsNullOrWhiteSpace([string]$Collector.lastRun)) { return $true }
  $last = ConvertTo-UtcTimestamp ([string]$Collector.lastRun) 'heartbeat_state_invalid'
  return (($Now - $last).TotalSeconds -ge [int]$Collector.cadenceSeconds)
}

function Get-RouteTarget {
  param($Candidate)
  # Heartbeats use one Governor inbox. Owner and subject remain event hints.
  return 'governor'
}

function Get-RouteClass {
  param([string]$Route)
  if ($Route -eq 'governor') { return 'governor' }
  if ($Route -match '^installer') { return 'installer' }
  if ($Route -match '^(development|dev)') { return 'development' }
  return 'owned'
}

function Get-InterventionContract {
  param([string]$Type)
  $contract = switch ($Type) {
    'AGENT_STALL' {
      @('agent_stall', 'contain_agent_work', 'verified_subject_or_owner', 'agent_progress_or_terminal', $true, $true,
        'Stop creating workers. Finish or checkpoint one bounded step, return completed workers, and report the categorical result.')
    }
    'GUARDIAN_RUNAWAY' {
      @('review_amplification', 'stop_review_amplification', 'verified_subject_or_owner', 'review_activity_stable', $true, $true,
        'Stop equivalent review and approval retries. Batch remaining inspection, checkpoint, and report the categorical result.')
    }
    'USAGE_BURN' {
      @('usage_growth', 'contain_usage_growth', 'verified_non_governor_subject', 'usage_progress_stable', $true, $true,
        'Stop creating workers, reduce task-controlled parallel work, checkpoint, and report the categorical result.')
    }
    'SESSION_EXPLOSION' {
      @('context_growth', 'stop_recursive_workers_and_checkpoint', 'verified_subject', 'session_growth_stable', $true, $true,
        'Stop recursive worker creation. Checkpoint the current work and prepare a fresh-task handoff without copying working history.')
    }
    'TEST_REGRESSION' {
      @('test_regression', 'rerun_known_narrow_test_once', 'verified_owner', 'known_test_passed', $true, $false,
        'Rerun the already identified narrow test once. Do not broaden the test scope. Report only the categorical result.')
    }
    'TEST_VALIDATION_MISSING' {
      @('test_validation', 'run_known_required_validation_once', 'verified_owner', 'required_validation_observed', $true, $false,
        'Run the already identified required validation once. Do not broaden the scope. Report only the categorical result.')
    }
    'TASK_ACTIONABLE' {
      @('task_progress', 'resume_one_bounded_step', 'verified_subject', 'task_progress_observed', $true, $false,
        'Resume one existing bounded step within the current assignment, checkpoint, and report the categorical result.')
    }
    'ZOMBIE_TASK' {
      @('task_ownership', 'reconcile_owned_child', 'verified_owner', 'ownership_reconciled', $true, $false,
        'Reconcile only the child task you already own. Return completed work or report the dependency state. Do not close unrelated tasks.')
    }
    'TASK_HANDOFF_INCOMPLETE' {
      @('task_handoff', 'complete_existing_handoff', 'verified_owner', 'handoff_verified', $true, $false,
        'Complete only the already authorized handoff step, verify it, and report the categorical result.')
    }
    'GIT_BUILD_STATE' {
      @('git_handoff', 'preserve_and_verify_handoff', 'verified_owner', 'git_state_stable', $true, $false,
        'Preserve current work and verify the existing bounded handoff scope. Do not reset, clean, merge, push, publish, or delete.')
    }
    'GIT_STATE_RISK' {
      @('git_risk', 'stop_new_writes_and_verify_ownership', 'verified_owner', 'git_state_stable', $true, $true,
        'Stop new writes. Preserve current work and verify ownership, branch, and intended commit. Do not reset, clean, merge, push, or delete.')
    }
    'BUILD_ARTIFACT_DRIFT' {
      @('artifact_drift', 'preserve_and_verify_artifact', 'verified_owner', 'artifact_identity_stable', $true, $false,
        'Preserve the current artifact and verify its source identity. Do not publish, replace, or delete artifacts.')
    }
    default {
      @('governor_local', 'governor_local_only', 'none', 'none', $false, $false,
        'Keep this condition in Governor-local state. Do not message a monitored task.')
    }
  }
  return [pscustomobject]@{
    Class = [string]$contract[0]
    Template = [string]$contract[1]
    TargetPolicy = [string]$contract[2]
    Postcondition = [string]$contract[3]
    Autonomous = [bool]$contract[4]
    ResolutionNoticeRequired = [bool]$contract[5]
    Instruction = [string]$contract[6]
    SelfTargetAllowed = $false
  }
}

function Convert-CandidateToEvent {
  param($Candidate, [string]$EventId)
  $route = Get-RouteTarget $Candidate
  $intervention = Get-InterventionContract ([string]$Candidate.Type)
  $governorOrigin = [string]$Candidate.Owner -eq 'governor'
  $governorLocalUsage = [string]$Candidate.Type -eq 'USAGE_BURN' -and $governorOrigin
  $event = [ordered]@{
    Event = 'HEARTBEAT_EVENT'
    EventId = $EventId
    Delivery = 'new'
    Type = $Candidate.Type
    Severity = $Candidate.Severity
    Owner = $Candidate.Owner
    OwningSolThread = $route
    Subject = $Candidate.Subject
    Detected = $Candidate.Detected
    Changed = @($Candidate.Changed)
    Evidence = @($Candidate.Evidence)
    LikelyCause = $Candidate.LikelyCause
    RecommendedAction = $Candidate.RecommendedAction
    DedupKey = $Candidate.DedupKey
    InterventionClass = if ($governorLocalUsage) { 'governor_usage_control' } else { $intervention.Class }
    InterventionTemplate = if ($governorLocalUsage) { 'governor_local_only' } else { $intervention.Template }
    TargetPolicy = if ($governorLocalUsage) { 'none' } else { $intervention.TargetPolicy }
    Postcondition = $intervention.Postcondition
    Autonomous = $intervention.Autonomous
    SelfTargetAllowed = $false
    InterventionInstruction = if ($governorLocalUsage) { 'Update only the Governor recurrence to the returned cadence, verify one active recurrence remains, and do not message a monitored task.' } else { $intervention.Instruction }
    CostImpact = if ([string]$Candidate.Type -eq 'USAGE_BURN') { 'unknown' } else { 'not_applicable' }
    QuotaImpact = if ([string]$Candidate.Type -eq 'USAGE_BURN') { 'unknown' } else { 'not_applicable' }
    GovernorOrigin = $governorOrigin
    CorroborationRequired = $governorLocalUsage
    CorroborationScope = if ($governorLocalUsage) { 'same_subject_and_window_for_monitored_task_message' } else { 'none' }
    GovernorLocalAction = if ($governorLocalUsage) { 'throttle_recurrence_to_idle_cadence' } else { 'none' }
    GovernorCadenceMinutes = if ($governorLocalUsage) { 360 } else { 0 }
    RequiredHostAction = if ($governorLocalUsage) { 'update_governor_recurrence_and_verify' } else { 'evaluate_intervention_contract' }
    MonitoredTaskMessage = if ($governorLocalUsage) { 'forbidden_without_independent_corroboration' } else { 'eligible_after_target_verification' }
    UserActionRequired = $false
  }
  if ($Candidate.TargetGenerationHash) {
    $event['TargetGenerationHash'] = [string]$Candidate.TargetGenerationHash
  }
  return $event
}

function New-ResolutionEvent {
  param($Condition, [string]$ConditionHash, $RouteHint, [DateTimeOffset]$Now, [string]$EventId)
  $owner = if ($RouteHint) { $RouteHint.Owner } else { $null }
  $subject = if ($RouteHint) { [string]$RouteHint.Subject } else { [string]$Condition.subjectHash }
  $intervention = Get-InterventionContract ([string]$Condition.type)
  $governorOrigin = [string]$Condition.type -eq 'USAGE_BURN' -and [string]$Condition.ownerHash -eq (Get-StableHash 'governor')
  return [ordered]@{
    Event = 'HEARTBEAT_RESOLVED'
    EventId = $EventId
    Delivery = 'new'
    Type = [string]$Condition.type
    Severity = 'INFO'
    Owner = $owner
    OwningSolThread = 'governor'
    Subject = $subject
    Detected = $Now.ToString('o')
    Changed = @('condition=open->resolved')
    Evidence = @('conditionHash=' + $ConditionHash.Substring(0, 16))
    LikelyCause = 'The prior condition is no longer present in an observed, due collector result.'
    RecommendedAction = 'No action is required unless the condition returns.'
    DedupKey = 'resolved:' + $ConditionHash.Substring(0, 16)
    InterventionClass = $intervention.Class
    InterventionTemplate = 'release_if_active_restriction'
    TargetPolicy = $intervention.TargetPolicy
    Postcondition = $intervention.Postcondition
    Autonomous = $false
    SelfTargetAllowed = $false
    InterventionInstruction = 'Close the Governor-local condition. Notify the target only when an acknowledged temporary restriction must be lifted.'
    CostImpact = 'not_applicable'
    QuotaImpact = 'not_applicable'
    GovernorOrigin = $governorOrigin
    CorroborationRequired = $false
    CorroborationScope = 'none'
    GovernorLocalAction = if ($governorOrigin) { 'restore_supervision_recommended_cadence' } else { 'none' }
    GovernorCadenceMinutes = 0
    RequiredHostAction = if ($governorOrigin) { 'reconcile_governor_recurrence_and_verify' } else { 'close_local_condition' }
    MonitoredTaskMessage = 'none_unless_release_notice_eligible'
    UserActionRequired = $false
  }
}

function New-OutboxRecord {
  param($Event, [string]$ConditionHash)
  $record = [ordered]@{
    eventId = [string]$Event.EventId
    event = [string]$Event.Event
    type = [string]$Event.Type
    severity = [string]$Event.Severity
    subjectHash = Get-StableHash ([string]$Event.Subject)
    ownerHash = Get-StableHash ([string]$Event.Owner)
    conditionHash = $ConditionHash
    routeHash = Get-StableHash ([string]$Event.OwningSolThread)
    routeClass = Get-RouteClass ([string]$Event.OwningSolThread)
    detected = [string]$Event.Detected
    attempts = 0
    lastAttempt = $null
    governorOrigin = [bool]$Event.GovernorOrigin
  }
  if ($Event -is [System.Collections.IDictionary] -and $Event.Contains('TargetGenerationHash') -and $Event['TargetGenerationHash']) {
    $record['expectedTargetGenerationHash'] = [string]$Event['TargetGenerationHash']
  }
  return $record
}

function Convert-OutboxToRetryEvent {
  param($Record)
  $intervention = Get-InterventionContract ([string]$Record.type)
  $governorLocalUsage = [string]$Record.type -eq 'USAGE_BURN' -and [bool]$Record.governorOrigin
  return [ordered]@{
    Event = [string]$Record.event
    EventId = [string]$Record.eventId
    Delivery = 'retry'
    Type = [string]$Record.type
    Severity = [string]$Record.severity
    Owner = $null
    OwningSolThread = 'governor'
    Subject = 'hash:' + ([string]$Record.subjectHash).Substring(0, 16)
    Detected = [string]$Record.detected
    Changed = @('delivery=pending')
    Evidence = @('conditionHash=' + ([string]$Record.conditionHash).Substring(0, 16), 'routeHash=' + ([string]$Record.routeHash).Substring(0, 16))
    LikelyCause = 'A prior Heartbeat transition remains unacknowledged by the invoking host.'
    RecommendedAction = 'Deduplicate by EventId, deliver once, then acknowledge the event.'
    DedupKey = 'event:' + [string]$Record.eventId
    InterventionClass = if ($governorLocalUsage) { 'governor_usage_control' } else { $intervention.Class }
    InterventionTemplate = if ($governorLocalUsage) { 'governor_local_only' } else { $intervention.Template }
    TargetPolicy = if ($governorLocalUsage) { 'none' } else { $intervention.TargetPolicy }
    Postcondition = $intervention.Postcondition
    Autonomous = $intervention.Autonomous
    SelfTargetAllowed = $false
    InterventionInstruction = if ($governorLocalUsage) { 'Update only the Governor recurrence to the returned cadence, verify one active recurrence remains, and do not message a monitored task.' } else { $intervention.Instruction }
    CostImpact = if ([string]$Record.type -eq 'USAGE_BURN') { 'unknown' } else { 'not_applicable' }
    QuotaImpact = if ([string]$Record.type -eq 'USAGE_BURN') { 'unknown' } else { 'not_applicable' }
    GovernorOrigin = [bool]$Record.governorOrigin
    CorroborationRequired = $governorLocalUsage
    CorroborationScope = if ($governorLocalUsage) { 'same_subject_and_window_for_monitored_task_message' } else { 'none' }
    GovernorLocalAction = if ($governorLocalUsage) { 'throttle_recurrence_to_idle_cadence' } else { 'none' }
    GovernorCadenceMinutes = if ($governorLocalUsage) { 360 } else { 0 }
    RequiredHostAction = if ($governorLocalUsage) { 'update_governor_recurrence_and_verify' } else { 'evaluate_intervention_contract' }
    MonitoredTaskMessage = if ($governorLocalUsage) { 'forbidden_without_independent_corroboration' } else { 'eligible_after_target_verification' }
    UserActionRequired = $false
  }
}

function Get-DueOutboxEvents {
  param($State, [DateTimeOffset]$Now)
  $result = [Collections.Generic.List[object]]::new()
  foreach ($record in @($State.outbox)) {
    $due = [string]::IsNullOrWhiteSpace([string]$record.lastAttempt)
    if (-not $due) {
      $lastAttempt = ConvertTo-UtcTimestamp ([string]$record.lastAttempt) 'heartbeat_state_invalid'
      $due = ($Now - $lastAttempt).TotalSeconds -ge $script:OutboxRetrySeconds
    }
    if ($due -and [int]$record.attempts -lt $script:OutboxMaxAttempts) { $result.Add((Convert-OutboxToRetryEvent $record)) | Out-Null }
  }
  return @($result)
}

function Mark-OutboxAttempts {
  param($State, [string[]]$EventIds, [string]$ResolvedStatePath, [DateTimeOffset]$Now)
  if ($EventIds.Count -eq 0) { return }
  foreach ($record in @($State.outbox)) {
    if ($EventIds -contains [string]$record.eventId) {
      $record.attempts = [int64]$record.attempts + 1
      $record.lastAttempt = $Now.ToString('o')
      $State.health.deliveryAttempts = [int64]$State.health.deliveryAttempts + 1
    }
  }
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
}

function Acknowledge-OutboxEvent {
  param($State, [string]$AcknowledgedEventId, [string]$ResolvedStatePath)
  if ($AcknowledgedEventId -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_event_id_invalid' }
  $before = @($State.outbox).Count
  $State.outbox = @($State.outbox | Where-Object { [string]$_.eventId -ne $AcknowledgedEventId })
  $acknowledged = @($State.outbox).Count -lt $before
  if ($acknowledged) {
    $State.health.acknowledgedEvents = [int64]$State.health.acknowledgedEvents + 1
    $State.revision = [int64]$State.revision + 1
    Write-State $State $ResolvedStatePath
  }
  return $acknowledged
}

function Get-InterventionRecord {
  param($State, [string]$RequestedInterventionId)
  return @($State.interventions | Where-Object { [string]$_.interventionId -eq $RequestedInterventionId } | Select-Object -First 1)[0]
}

function Get-PendingEventRecord {
  param($State, [string]$RequestedEventId)
  if ($RequestedEventId -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_event_id_invalid' }
  return @($State.outbox | Where-Object { [string]$_.eventId -eq $RequestedEventId } | Select-Object -First 1)[0]
}

function Test-InterventionTerminal {
  param([string]$StateName)
  return $StateName -in @('verified_resolved', 'declined', 'user_authority_required', 'remediation_failed', 'undelivered', 'failed_closed', 'superseded')
}

function Assert-InterventionRuntimeId {
  param([string]$Value)
  try { Assert-Identifier $Value } catch { throw 'heartbeat_intervention_input_invalid' }
}

function Remove-PendingEvent {
  param($State, [string]$RequestedEventId)
  $State.outbox = @($State.outbox | Where-Object { [string]$_.eventId -ne $RequestedEventId })
}

function New-InterventionRecord {
  param($EventRecord, [string]$TargetHash, [string]$GenerationHash, [string]$GovernorHash, [int]$Version, [string]$StateName, [string]$Reason, [DateTimeOffset]$Now, [bool]$EscalationSent)
  $contract = Get-InterventionContract ([string]$EventRecord.type)
  $id = Get-StableHash ('chronos-intervention-v1|{0}|{1}|{2}|{3}' -f [string]$EventRecord.eventId, $Version, $TargetHash, $GenerationHash)
  return [ordered]@{
    interventionId = $id
    eventId = [string]$EventRecord.eventId
    conditionHash = [string]$EventRecord.conditionHash
    type = [string]$EventRecord.type
    severity = [string]$EventRecord.severity
    version = $Version
    targetHash = $TargetHash
    targetGenerationHash = $GenerationHash
    governorHash = $GovernorHash
    state = $StateName
    attempts = 0
    claimHash = $null
    claimExpiresAt = $null
    createdAt = $Now.ToString('o')
    updatedAt = $Now.ToString('o')
    template = $contract.Template
    postcondition = $contract.Postcondition
    resolutionNoticeRequired = [bool]$contract.ResolutionNoticeRequired
    escalationSent = $EscalationSent
    coalescedCount = 0
    failureReason = $Reason
    transportResult = 'none'
    taskResponse = 'none'
    verificationSource = 'none'
    verificationResult = 'none'
  }
}

function Get-InterventionPayload {
  param($Record, [string]$ActionName, [string]$Decision, [string]$ClaimTokenValue = $null)
  $contract = Get-InterventionContract ([string]$Record.type)
  $failureReason = [string]$Record.failureReason
  $nextHostAction = switch ($failureReason) {
    'ambiguous_target' { 'retry_host_discovery_next_cycle' }
    'target_not_live' { 'retry_host_discovery_next_cycle' }
    'transport_unavailable' { 'retain_condition_without_user_handoff' }
    'governor_usage_uncorroborated' { 'apply_governor_local_throttle_only' }
    'user_authority_required' { 'surface_once_for_user_authority' }
    default {
      if ($Decision -eq 'send') { 'send_once_to_verified_target' }
      elseif ($Decision -eq 'deferred_incompatible') { 'complete_active_intervention_then_plan_pending_event' }
      else { 'none' }
    }
  }
  $payload = [ordered]@{
    ok = $true
    action = $ActionName
    decision = $Decision
    interventionId = [string]$Record.interventionId
    eventId = [string]$Record.eventId
    version = [int]$Record.version
    state = [string]$Record.state
    type = [string]$Record.type
    severity = [string]$Record.severity
    template = [string]$Record.template
    postcondition = [string]$Record.postcondition
    targetHash = ([string]$Record.targetHash).Substring(0, 16)
    instruction = $contract.Instruction
    selfTargetAllowed = $false
    maxSendAttempts = 2
    requiresIndependentVerification = $true
    nextHostAction = $nextHostAction
    userActionRequired = ($failureReason -eq 'user_authority_required')
    routineFailureHandling = 'governor_local_fail_closed'
    replyFormat = ('CHRONOS INTERVENTION RESULT id={0} version={1} state=<acknowledged|outcome_reported|declined|user_authority_required|remediation_failed>' -f [string]$Record.interventionId, [int]$Record.version)
  }
  if (-not [string]::IsNullOrWhiteSpace($ClaimTokenValue)) { $payload.claimToken = $ClaimTokenValue }
  if ($failureReason -ne 'none') { $payload.reason = $failureReason }
  return $payload
}

function Write-InterventionPayload {
  param($Payload)
  Write-Output ('CHRONOS INTERVENTION ' + ($Payload | ConvertTo-Json -Compress -Depth 6))
}

function Test-UsageCorroboration {
  param($State, $UsageEvent, [string]$RequestedCorroboratingEventId)
  if ([string]::IsNullOrWhiteSpace($RequestedCorroboratingEventId) -or $RequestedCorroboratingEventId -notmatch '^[a-f0-9]{64}$') { return $false }
  $other = Get-PendingEventRecord $State $RequestedCorroboratingEventId
  if ($null -eq $other -or [string]$other.event -ne 'HEARTBEAT_EVENT' -or [string]$other.eventId -eq [string]$UsageEvent.eventId) { return $false }
  if ([string]$other.type -notin @('AGENT_STALL', 'GUARDIAN_RUNAWAY', 'MACHINE_DRIFT')) { return $false }
  $sameSubject = [string]$other.subjectHash -eq [string]$UsageEvent.subjectHash -or [string]$other.ownerHash -eq [string]$UsageEvent.subjectHash
  if (-not $sameSubject) { return $false }
  try {
    $usageTime = ConvertTo-UtcTimestamp ([string]$UsageEvent.detected) 'heartbeat_state_invalid'
    $otherTime = ConvertTo-UtcTimestamp ([string]$other.detected) 'heartbeat_state_invalid'
    return [math]::Abs(($usageTime - $otherTime).TotalSeconds) -le 900
  } catch { return $false }
}

function Test-InterventionTargetPolicy {
  param($EventRecord, [string]$TargetHash, [string]$Policy)
  $subjectMatch = $TargetHash -eq [string]$EventRecord.subjectHash
  $ownerMatch = $TargetHash -eq [string]$EventRecord.ownerHash
  switch ($Policy) {
    'verified_subject' { return $subjectMatch }
    'verified_non_governor_subject' { return $subjectMatch }
    'verified_owner' { return $ownerMatch }
    'verified_subject_or_owner' { return $subjectMatch -or $ownerMatch }
    default { return $false }
  }
}

function Add-BoundedIntervention {
  param($State, $Record)
  if (@($State.interventions).Count -ge $script:InterventionLimit) {
    $oldestTerminal = @($State.interventions | Where-Object { Test-InterventionTerminal ([string]$_.state) } | Sort-Object updatedAt | Select-Object -First 1)[0]
    if ($oldestTerminal) {
      $State.interventions = @($State.interventions | Where-Object { [string]$_.interventionId -ne [string]$oldestTerminal.interventionId })
    }
  }
  if (@($State.interventions).Count -ge $script:InterventionLimit) { throw 'heartbeat_intervention_capacity' }
  $State.interventions = @($State.interventions + $Record)
}

function Invoke-InterventionPlan {
  param($State, [string]$ResolvedStatePath, [string]$RequestedEventId, [string]$RequestedCorroboratingEventId, [string]$RequestedTargetId, [string]$RequestedGeneration, [string]$CurrentGovernorId, [DateTimeOffset]$Now)
  Assert-InterventionRuntimeId $RequestedTargetId
  Assert-InterventionRuntimeId $RequestedGeneration
  Assert-InterventionRuntimeId $CurrentGovernorId
  $eventRecord = Get-PendingEventRecord $State $RequestedEventId
  if ($null -eq $eventRecord -or [string]$eventRecord.event -ne 'HEARTBEAT_EVENT') { throw 'heartbeat_intervention_event_unavailable' }
  $targetHash = Get-StableHash $RequestedTargetId
  $generationHash = Get-StableHash $RequestedGeneration
  $governorHash = Get-StableHash $CurrentGovernorId
  $contract = Get-InterventionContract ([string]$eventRecord.type)
  $failure = $null
  if ($eventRecord.expectedTargetGenerationHash -and [string]$eventRecord.expectedTargetGenerationHash -ne $generationHash) { $failure = 'target_generation_mismatch' }
  elseif ($targetHash -eq $governorHash) { $failure = 'self_target_forbidden' }
  elseif (-not [bool]$contract.Autonomous) { $failure = 'unsupported_action' }
  elseif ([string]$eventRecord.type -eq 'USAGE_BURN' -and [bool]$eventRecord.governorOrigin -and -not (Test-UsageCorroboration $State $eventRecord $RequestedCorroboratingEventId)) { $failure = 'governor_usage_uncorroborated' }
  elseif (-not (Test-InterventionTargetPolicy $eventRecord $targetHash ([string]$contract.TargetPolicy))) { $failure = 'target_policy_mismatch' }
  if ($failure) {
    $reason = $failure
    $record = New-InterventionRecord $eventRecord $targetHash $generationHash $governorHash 1 'failed_closed' $reason $Now $false
    Add-BoundedIntervention $State $record
    Remove-PendingEvent $State $RequestedEventId
    Trim-State $State
    $State.revision = [int64]$State.revision + 1
    Write-State $State $ResolvedStatePath
    return Get-InterventionPayload $record 'plan' 'failed_closed'
  }

  foreach ($staleGeneration in @($State.interventions | Where-Object {
        [string]$_.targetHash -eq $targetHash -and
        [string]$_.targetGenerationHash -ne $generationHash -and
        -not (Test-InterventionTerminal ([string]$_.state))
      })) {
    $staleGeneration.state = 'superseded'
    $staleGeneration.updatedAt = $Now.ToString('o')
  }
  $active = @($State.interventions | Where-Object {
      [string]$_.targetHash -eq $targetHash -and
      [string]$_.targetGenerationHash -eq $generationHash -and
      -not (Test-InterventionTerminal ([string]$_.state))
    } | Sort-Object updatedAt -Descending | Select-Object -First 1)[0]
  if ($active) {
    if ([string]$active.template -ne [string]$contract.Template -or [string]$active.postcondition -ne [string]$contract.Postcondition) {
      return Get-InterventionPayload $active 'plan' 'deferred_incompatible'
    }
    $newRank = [int]$script:SeverityRank[[string]$eventRecord.severity]
    $activeRank = [int]$script:SeverityRank[[string]$active.severity]
    if ([string]$active.eventId -eq $RequestedEventId -or $newRank -le $activeRank -or ([bool]$active.escalationSent -and [int]$active.attempts -gt 0)) {
      $active.coalescedCount = [int]$active.coalescedCount + 1
      $active.updatedAt = $Now.ToString('o')
      Remove-PendingEvent $State $RequestedEventId
      $State.revision = [int64]$State.revision + 1
      Write-State $State $ResolvedStatePath
      return Get-InterventionPayload $active 'plan' 'coalesced'
    }
    $nextVersion = [int]$active.version + 1
    $alreadySent = [int]$active.attempts -gt 0
    $active.state = 'superseded'
    $active.escalationSent = $alreadySent
    $active.updatedAt = $Now.ToString('o')
    $record = New-InterventionRecord $eventRecord $targetHash $generationHash $governorHash $nextVersion 'queued' 'none' $Now $alreadySent
  } else {
    $record = New-InterventionRecord $eventRecord $targetHash $generationHash $governorHash 1 'queued' 'none' $Now $false
  }
  Add-BoundedIntervention $State $record
  Remove-PendingEvent $State $RequestedEventId
  Trim-State $State
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
  return Get-InterventionPayload $record 'plan' 'send'
}

function Invoke-InterventionFailClosed {
  param($State, [string]$ResolvedStatePath, [string]$RequestedEventId, [string]$Reason, [DateTimeOffset]$Now)
  if ($Reason -notin @('ambiguous_target', 'target_not_live', 'transport_unavailable', 'user_authority_required', 'unsupported_action')) { throw 'heartbeat_intervention_input_invalid' }
  $eventRecord = Get-PendingEventRecord $State $RequestedEventId
  if ($null -eq $eventRecord) { throw 'heartbeat_intervention_event_unavailable' }
  $record = New-InterventionRecord $eventRecord (Get-StableHash 'unresolved-target') (Get-StableHash 'unresolved-generation') (Get-StableHash 'unresolved-governor') 1 'failed_closed' $Reason $Now $false
  Add-BoundedIntervention $State $record
  Remove-PendingEvent $State $RequestedEventId
  Trim-State $State
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
  return Get-InterventionPayload $record 'fail-closed' 'failed_closed'
}

function Assert-CurrentTarget {
  param($Record, [string]$RequestedTargetId, [string]$RequestedGeneration, [string]$CurrentGovernorId)
  Assert-InterventionRuntimeId $RequestedTargetId
  Assert-InterventionRuntimeId $RequestedGeneration
  Assert-InterventionRuntimeId $CurrentGovernorId
  $targetHash = Get-StableHash $RequestedTargetId
  $governorHash = Get-StableHash $CurrentGovernorId
  if ($targetHash -eq $governorHash) { throw 'heartbeat_intervention_self_target' }
  if ($targetHash -ne [string]$Record.targetHash -or (Get-StableHash $RequestedGeneration) -ne [string]$Record.targetGenerationHash) { throw 'heartbeat_intervention_target_changed' }
  if ($governorHash -ne [string]$Record.governorHash) {
    $legacyGovernorHash = Get-StableHash 'legacy-governor-unassigned'
    if ([string]$Record.governorHash -eq $legacyGovernorHash -and [string]$Record.state -in @('queued', 'retry_queued')) {
      # Schema-6 did not persist Governor ownership. An unsent legacy record
      # can be adopted only after target and generation hashes match.
      $Record.governorHash = $governorHash
    } else { throw 'heartbeat_intervention_governor_changed' }
  }
}

function Invoke-InterventionClaim {
  param($State, [string]$ResolvedStatePath, [string]$RequestedInterventionId, [int]$RequestedVersion, [string]$RequestedTargetId, [string]$RequestedGeneration, [string]$CurrentGovernorId, [DateTimeOffset]$Now)
  $record = Get-InterventionRecord $State $RequestedInterventionId
  if ($null -eq $record -or [int]$record.version -ne $RequestedVersion) { throw 'heartbeat_intervention_not_found' }
  Assert-CurrentTarget $record $RequestedTargetId $RequestedGeneration $CurrentGovernorId
  if ([string]$record.state -notin @('queued', 'retry_queued')) { throw 'heartbeat_intervention_transition_invalid' }
  if ([int]$record.attempts -ge 2) {
    $record.state = 'undelivered'
    $record.failureReason = 'retry_budget_exhausted'
    $record.updatedAt = $Now.ToString('o')
    $State.revision = [int64]$State.revision + 1
    Write-State $State $ResolvedStatePath
    return Get-InterventionPayload $record 'claim' 'undelivered'
  }
  $token = [guid]::NewGuid().ToString('N')
  $record.claimHash = Get-StableHash $token
  $record.attempts = [int]$record.attempts + 1
  $record.state = 'send_claimed'
  $record.claimExpiresAt = $Now.AddSeconds($script:InterventionClaimSeconds).ToString('o')
  $record.updatedAt = $Now.ToString('o')
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
  return Get-InterventionPayload $record 'claim' 'send' $token
}

function Assert-InterventionClaim {
  param($Record, [int]$RequestedVersion, [string]$RequestedClaimToken)
  if ($RequestedVersion -ne [int]$Record.version -or [string]::IsNullOrWhiteSpace($RequestedClaimToken) -or (Get-StableHash $RequestedClaimToken) -ne [string]$Record.claimHash) { throw 'heartbeat_intervention_claim_invalid' }
}

function Invoke-InterventionTransport {
  param($State, [string]$ResolvedStatePath, [string]$RequestedInterventionId, [int]$RequestedVersion, [string]$RequestedClaimToken, [string]$Result, [DateTimeOffset]$Now)
  $record = Get-InterventionRecord $State $RequestedInterventionId
  if ($null -eq $record) { throw 'heartbeat_intervention_not_found' }
  Assert-InterventionClaim $record $RequestedVersion $RequestedClaimToken
  if ([string]$record.state -notin @('send_claimed', 'delivery_unknown')) { throw 'heartbeat_intervention_transition_invalid' }
  if ([string]$record.state -eq 'delivery_unknown' -and $Result -ne 'accepted') { throw 'heartbeat_intervention_transition_invalid' }
  $record.transportResult = $Result
  switch ($Result) {
    'accepted' { $record.state = 'awaiting_task_ack'; $record.claimExpiresAt = $null }
    'definite_failure' {
      if ([int]$record.attempts -lt 2) { $record.state = 'retry_queued' }
      else { $record.state = 'undelivered'; $record.failureReason = 'retry_budget_exhausted' }
      $record.claimHash = $null
      $record.claimExpiresAt = $null
    }
    'unknown' { $record.state = 'delivery_unknown' }
    default { throw 'heartbeat_intervention_input_invalid' }
  }
  $record.updatedAt = $Now.ToString('o')
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
  return Get-InterventionPayload $record 'transport' ([string]$record.state)
}

function Invoke-InterventionResponse {
  param($State, [string]$ResolvedStatePath, [string]$RequestedInterventionId, [int]$RequestedVersion, [string]$ReportingTaskId, [string]$ReportingGeneration, [string]$Response, [DateTimeOffset]$Now)
  $record = Get-InterventionRecord $State $RequestedInterventionId
  if ($null -eq $record -or [int]$record.version -ne $RequestedVersion) { throw 'heartbeat_intervention_not_found' }
  Assert-InterventionRuntimeId $ReportingTaskId
  Assert-InterventionRuntimeId $ReportingGeneration
  if ((Get-StableHash $ReportingTaskId) -ne [string]$record.targetHash -or (Get-StableHash $ReportingGeneration) -ne [string]$record.targetGenerationHash) { throw 'heartbeat_intervention_reporter_mismatch' }
  if ([string]$record.state -notin @('awaiting_task_ack', 'remediating')) { throw 'heartbeat_intervention_transition_invalid' }
  $record.taskResponse = $Response
  switch ($Response) {
    'acknowledged' { $record.state = 'remediating' }
    'outcome_reported' { $record.state = 'verification_pending' }
    'declined' { $record.state = 'declined' }
    'user_authority_required' { $record.state = 'user_authority_required'; $record.failureReason = 'user_authority_required' }
    'remediation_failed' { $record.state = 'remediation_failed' }
    default { throw 'heartbeat_intervention_input_invalid' }
  }
  $record.updatedAt = $Now.ToString('o')
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
  return Get-InterventionPayload $record 'response' ([string]$record.state)
}

function Test-VerificationSourceAllowed {
  param([string]$Type, [string]$Source)
  switch ($Type) {
    { $_ -in @('AGENT_STALL', 'TASK_ACTIONABLE', 'ZOMBIE_TASK', 'TASK_HANDOFF_INCOMPLETE') } { return $Source -eq 'host_inventory' }
    { $_ -in @('TEST_REGRESSION', 'TEST_VALIDATION_MISSING') } { return $Source -eq 'host_test' }
    { $_ -in @('GIT_BUILD_STATE', 'GIT_STATE_RISK', 'BUILD_ARTIFACT_DRIFT') } { return $Source -eq 'host_git' }
    default { return $false }
  }
}

function Invoke-InterventionVerify {
  param($State, [string]$ResolvedStatePath, [string]$RequestedInterventionId, [int]$RequestedVersion, [string]$RequestedTargetId, [string]$RequestedGeneration, [string]$Source, [string]$Result, [DateTimeOffset]$Now)
  $record = Get-InterventionRecord $State $RequestedInterventionId
  if ($null -eq $record -or [int]$record.version -ne $RequestedVersion) { throw 'heartbeat_intervention_not_found' }
  Assert-InterventionRuntimeId $RequestedTargetId
  Assert-InterventionRuntimeId $RequestedGeneration
  if ((Get-StableHash $RequestedTargetId) -ne [string]$record.targetHash -or (Get-StableHash $RequestedGeneration) -ne [string]$record.targetGenerationHash) { throw 'heartbeat_intervention_target_changed' }
  if ([string]$record.state -notin @('verification_pending', 'active_violation')) { throw 'heartbeat_intervention_transition_invalid' }
  if (-not (Test-VerificationSourceAllowed ([string]$record.type) $Source)) { throw 'heartbeat_intervention_verification_invalid' }
  $record.verificationSource = $Source
  $record.verificationResult = $Result
  switch ($Result) {
    'resolved' { $record.state = 'verified_resolved' }
    'active' { $record.state = 'active_violation' }
    'failed' { $record.state = 'remediation_failed' }
    default { throw 'heartbeat_intervention_input_invalid' }
  }
  $record.updatedAt = $Now.ToString('o')
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
  return Get-InterventionPayload $record 'verify' ([string]$record.state)
}

function Get-InterventionNextAction {
  param($Record, [DateTimeOffset]$Now)
  switch ([string]$Record.state) {
    'queued' { return 'claim' }
    'retry_queued' { return 'claim' }
    'send_claimed' {
      if ($Record.claimExpiresAt -and (ConvertTo-UtcTimestamp $Record.claimExpiresAt 'heartbeat_state_invalid') -le $Now) { return 'mark_delivery_unknown' }
      return 'wait_for_claim_expiry'
    }
    'delivery_unknown' { return 'reconcile_delivery_without_retry' }
    'awaiting_task_ack' { return 'wait_for_task_response' }
    'remediating' { return 'wait_for_task_outcome' }
    'verification_pending' { return 'verify_host_postcondition' }
    'active_violation' { return 'verify_host_postcondition' }
    default { return 'none' }
  }
}

function Invoke-InterventionList {
  param($State, [string]$CurrentGovernorId, [DateTimeOffset]$Now)
  Assert-InterventionRuntimeId $CurrentGovernorId
  $governorHash = Get-StableHash $CurrentGovernorId
  $legacyGovernorHash = Get-StableHash 'legacy-governor-unassigned'
  $records = [Collections.Generic.List[object]]::new()
  foreach ($record in @($State.interventions | Where-Object {
        [string]$_.governorHash -in @($governorHash, $legacyGovernorHash) -and -not (Test-InterventionTerminal ([string]$_.state))
      } | Sort-Object updatedAt | Select-Object -First 16)) {
    $records.Add([ordered]@{
        interventionId = [string]$record.interventionId
        version = [int]$record.version
        state = [string]$record.state
        type = [string]$record.type
        severity = [string]$record.severity
        targetHash = ([string]$record.targetHash).Substring(0, 16)
        generationHash = ([string]$record.targetGenerationHash).Substring(0, 16)
        template = [string]$record.template
        postcondition = [string]$record.postcondition
        attempts = [int]$record.attempts
        updatedAt = [string]$record.updatedAt
        permittedNextAction = Get-InterventionNextAction $record $Now
      }) | Out-Null
  }
  return [ordered]@{ ok = $true; action = 'list'; count = $records.Count; interventions = @($records) }
}

function Invoke-InterventionReclaim {
  param($State, [string]$ResolvedStatePath, [string]$RequestedInterventionId, [int]$RequestedVersion, [string]$CurrentGovernorId, [DateTimeOffset]$Now)
  Assert-InterventionRuntimeId $CurrentGovernorId
  $record = Get-InterventionRecord $State $RequestedInterventionId
  if ($null -eq $record -or [int]$record.version -ne $RequestedVersion) { throw 'heartbeat_intervention_not_found' }
  if ((Get-StableHash $CurrentGovernorId) -ne [string]$record.governorHash) { throw 'heartbeat_intervention_governor_changed' }
  if ([string]$record.state -ne 'send_claimed' -or -not $record.claimExpiresAt -or (ConvertTo-UtcTimestamp $record.claimExpiresAt 'heartbeat_state_invalid') -gt $Now) { throw 'heartbeat_intervention_transition_invalid' }
  $record.claimHash = $null
  $record.claimExpiresAt = $null
  $record.state = 'delivery_unknown'
  $record.transportResult = 'unknown'
  $record.failureReason = 'claim_expired_delivery_ambiguous'
  $record.updatedAt = $Now.ToString('o')
  $State.revision = [int64]$State.revision + 1
  Write-State $State $ResolvedStatePath
  return Get-InterventionPayload $record 'reclaim' ([string]$record.state)
}

function Resolve-ConditionInterventions {
  param($State, [string]$ConditionHash, [DateTimeOffset]$Now)
  $noticeEligible = $false
  foreach ($record in @($State.interventions | Where-Object { [string]$_.conditionHash -eq $ConditionHash -and -not (Test-InterventionTerminal ([string]$_.state)) })) {
    if ([bool]$record.resolutionNoticeRequired -and [string]$record.state -in @('awaiting_task_ack', 'remediating', 'verification_pending', 'active_violation')) { $noticeEligible = $true }
    $record.state = 'verified_resolved'
    $record.verificationSource = 'heartbeat_engine'
    $record.verificationResult = 'resolved'
    $record.updatedAt = $Now.ToString('o')
  }
  return $noticeEligible
}

function Test-FamilyCounterContinuity {
  param([string]$Family, $Previous, $Current)
  $monotonic = switch ($Family) {
    'agent_stall' { @('totalTokens') }
    'guardian' { @('reviewCount', 'repeats', 'executions') }
    'usage' { @('totalTokens') }
    'sessions' { @('childCount', 'compactions', 'rolloutBytes') }
    default { @() }
  }
  foreach ($recordKey in $Current.Keys) {
    $prior = Get-Value $Previous $recordKey
    if (-not $prior) { continue }
    foreach ($field in $monotonic) {
      if ((Has-Value $prior $field) -and (Has-Value $Current[$recordKey] $field) -and [double]$Current[$recordKey][$field] -lt [double]$prior[$field]) { return $false }
    }
  }
  return $true
}

function Trim-State {
  param($State)
  $openCount = @($State.conditions.Values | Where-Object { [bool]$_.open }).Count
  if ($openCount -gt $script:ConditionLimit) { throw 'heartbeat_condition_capacity' }
  if ($State.conditions.Count -gt $script:ConditionLimit) {
    $ordered = @($State.conditions.GetEnumerator() | Sort-Object @{Expression={ if ($_.Value.open) { 1 } else { 0 } };Descending=$true}, @{Expression={$_.Value.lastObserved};Descending=$true})
    $keep = @($ordered | Select-Object -First $script:ConditionLimit | ForEach-Object { $_.Key })
    foreach ($key in @($State.conditions.Keys)) { if ($keep -notcontains $key) { $State.conditions.Remove($key) } }
  }
  $State.events = @($State.events | Select-Object -Last $script:EventLimit)
  if (@($State.interventions).Count -gt $script:InterventionLimit) {
    $State.interventions = @($State.interventions | Sort-Object @{Expression={ if (Test-InterventionTerminal ([string]$_.state)) { 0 } else { 1 } };Descending=$true}, @{Expression={$_.updatedAt};Descending=$true} | Select-Object -First $script:InterventionLimit)
  }
  $State.runIds = @($State.runIds | Select-Object -Last $script:RunIdLimit)
}

function Invoke-Cycle {
  param(
    $Snapshot,
    $State,
    [string]$ResolvedStatePath,
    [DateTimeOffset]$EvidenceNow,
    [DateTimeOffset]$DeliveryNow
  )
  $started = Get-Date
  if ([bool](Get-Value $Snapshot 'isHeartbeatGenerated' $false) -or [string](Get-Value $Snapshot 'origin' 'host') -in @('heartbeat', 'heartbeat_notification')) { return @() }
  $routed = [Collections.Generic.List[object]]::new()
  foreach ($pendingEvent in @(Get-DueOutboxEvents $State $DeliveryNow)) { $routed.Add($pendingEvent) | Out-Null }
  $runId = [string](Get-Value $Snapshot 'runId' '')
  $runHash = $null
  if (-not [string]::IsNullOrWhiteSpace($runId)) {
    $runHash = Get-StableHash $runId
    if (@($State.runIds) -contains $runHash) {
      $State.health.duplicateRuns = [int64]$State.health.duplicateRuns + 1
      $State.revision = [int64]$State.revision + 1
      Write-State $State $ResolvedStatePath
      return @($routed)
    }
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$State.health.lastCycleUtc)) {
    $lastCycle = ConvertTo-UtcTimestamp ([string]$State.health.lastCycleUtc) 'heartbeat_state_invalid'
    if ($EvidenceNow -lt $lastCycle) {
      if ($routed.Count -gt 0) {
        $State.health.lastError = 'heartbeat_time_out_of_order'
        return @($routed)
      }
      throw 'heartbeat_time_out_of_order'
    }
  }
  if ($runHash) {
    $State.runIds = @($State.runIds + $runHash)
    $State.health.lastRunIdHash = $runHash
  }
  $coverage = Get-Value $Snapshot 'collectorCoverage' @{}
  $force = [bool](Get-Value $Snapshot 'forceCadence' $false)
  $newEvents = [Collections.Generic.List[object]]::new()
  $newOutbox = [Collections.Generic.List[object]]::new()

  foreach ($family in $script:Families) {
    if (-not (Test-FamilyPresent $Snapshot $family)) { continue }
    $collector = $State.collectors[$family]
    $collector.lastAttempt = $EvidenceNow.ToString('o')
    $collector.coverage = [string](Get-Value $coverage $family 'unsupported')
    if (-not (Test-FamilyDue $collector $EvidenceNow $force)) {
      $collector.skippedCadence = [int64]$collector.skippedCadence + 1
      continue
    }
    $collector.lastRun = $EvidenceNow.ToString('o')
    if ($collector.coverage -ne 'observed') { continue }
    $hasEpoch = Has-Value $Snapshot 'sourceEpoch'
    $hasSequence = Has-Value $Snapshot 'sourceSequence'
    $epochHash = if ($hasEpoch) { Get-StableHash ([string]$Snapshot.sourceEpoch) } else { $null }
    $sequence = if ($hasSequence) { [int64]$Snapshot.sourceSequence } else { $null }
    $priorEpoch = [string]$collector.sourceEpochHash
    $hasPriorContinuity = -not [string]::IsNullOrWhiteSpace($priorEpoch) -and $null -ne $collector.lastSequence
    if ($hasPriorContinuity -and $hasEpoch -and $hasSequence -and $priorEpoch -eq $epochHash -and $sequence -le [int64]$collector.lastSequence) {
      throw 'heartbeat_source_out_of_order'
    }
    $continuity = $hasPriorContinuity -and $hasEpoch -and $hasSequence -and $priorEpoch -eq $epochHash -and $sequence -gt [int64]$collector.lastSequence
    $previousForDetector = if ($continuity) { $State.previous[$family] } else { @{} }
    $detector = Invoke-Detector $family $Snapshot $previousForDetector $EvidenceNow
    if ($family -eq 'heartbeat') {
      $runtimeState = Get-Value $detector.Snapshot (Get-StableHash 'heartbeat-engine') @{}
      $State.health.runtimeBudgetMs = [double](Get-Value $runtimeState 'runtimeBudgetMs' 0)
      $State.health.runtimeObservedMs = [double](Get-Value $runtimeState 'runtimeMs' 0)
      $State.health.runtimeOverrunMs = [double](Get-Value $runtimeState 'runtimeOverrunMs' 0)
      $State.health.runtimeOverrunPercent = [double](Get-Value $runtimeState 'runtimeOverrunPercent' 0)
      $State.health.runtimeBaselineMs = [double](Get-Value $runtimeState 'runtimeBaselineMs' 0)
      $State.health.runtimeClassification = [string](Get-Value $runtimeState 'runtimeClassification' 'unobserved')
      $State.health.runtimeOverrunStreak = [int](Get-Value $runtimeState 'runtimeOverrunStreak' 0)
      $State.health.runtimeBackoffApplied = ([bool](Get-Value $runtimeState 'runtimeBackoffApplied' $false) -or @($detector.Candidates).Count -gt 0)
      if (@($detector.Candidates).Count -eq 0) {
        $collector.backoffUntilUtc = $null
        $State.health.backoffUntilUtc = $null
      }
    }
    $counterContinuity = $continuity -and (Test-FamilyCounterContinuity $family $State.previous[$family] $detector.Snapshot)
    $seen = @{}
    foreach ($candidate in @($detector.Candidates)) {
      $conditionHash = [string]$candidate.ConditionHash
      $seen[$conditionHash] = $true
      $old = Get-Value $State.conditions $conditionHash
      $oldRank = if ($old -and $script:SeverityRank.ContainsKey([string]$old.severity)) { [int]$script:SeverityRank[[string]$old.severity] } else { 0 }
      $newRank = [int]$script:SeverityRank[[string]$candidate.Severity]
      $notify = $null -eq $old -or -not [bool]$old.open -or $newRank -gt $oldRank
      $episodeSeverity = if ($old -and [bool]$old.open -and $oldRank -gt $newRank) { [string]$old.severity } else { [string]$candidate.Severity }
      $episode = if ($old) { if ([bool]$old.open) { [int64](Get-Value $old 'episode' 1) } else { [int64](Get-Value $old 'episode' 1) + 1 } } else { 1 }
      if ($notify) {
        $eventId = Get-StableHash ('heartbeat-event-v1|{0}|{1}|{2}|open' -f $conditionHash, $episode, $candidate.Severity)
        $event = Convert-CandidateToEvent $candidate $eventId
        $routed.Add($event) | Out-Null
        $newEvents.Add($event) | Out-Null
        $newOutbox.Add((New-OutboxRecord $event $conditionHash)) | Out-Null
        $State.health.routesEmitted = [int64]$State.health.routesEmitted + 1
      } else {
        $State.health.suppressedDuplicates = [int64]$State.health.suppressedDuplicates + 1
      }
      $route = Get-RouteTarget $candidate
      $State.conditions[$conditionHash] = [ordered]@{
        family = $family
        type = [string]$candidate.Type
        severity = $episodeSeverity
        open = $true
        firstObserved = if ($old) { [string]$old.firstObserved } else { [string]$candidate.Detected }
        lastObserved = [string]$candidate.Detected
        lastNotified = if ($notify) { [string]$candidate.Detected } elseif ($old) { [string]$old.lastNotified } else { $null }
        occurrences = if ($old) { [int64]$old.occurrences + 1 } else { 1 }
        episode = $episode
        sourceEpochHash = if ($old -and [bool]$old.open) { $old.sourceEpochHash } else { $epochHash }
        signatureHash = Get-StableHash @{ type = $candidate.Type; severity = $episodeSeverity }
        subjectHash = [string]$candidate.SubjectHash
        ownerHash = Get-StableHash (Get-Value $candidate 'Owner' 'unknown')
        routeClass = Get-RouteClass $route
        resolutionNotified = $false
        resolvedAt = $null
      }
      if ($family -eq 'heartbeat') {
        $backoff = $EvidenceNow.AddMinutes(15).ToString('o')
        $collector.backoffUntilUtc = $backoff
        $State.health.backoffUntilUtc = $backoff
      }
    }
    foreach ($conditionHash in @($State.conditions.Keys)) {
      $condition = $State.conditions[$conditionHash]
      if ([string]$condition.family -ne $family -or -not [bool]$condition.open -or $seen.ContainsKey($conditionHash) -or -not $counterContinuity -or -not $detector.Routes.ContainsKey($conditionHash) -or [string]::IsNullOrWhiteSpace([string]$condition.sourceEpochHash) -or [string]$condition.sourceEpochHash -ne $epochHash) { continue }
      $condition.open = $false
      $condition.resolvedAt = $EvidenceNow.ToString('o')
      $releaseNoticeEligible = Resolve-ConditionInterventions $State $conditionHash $EvidenceNow
      if (-not [bool]$condition.resolutionNotified) {
        $hint = Get-Value $detector.Routes $conditionHash
        $resolutionEventId = Get-StableHash ('heartbeat-event-v1|{0}|{1}|resolved' -f $conditionHash, [int64](Get-Value $condition 'episode' 1))
        $resolutionEvent = New-ResolutionEvent $condition $conditionHash $hint $EvidenceNow $resolutionEventId
        $resolutionEvent['ReleaseNoticeEligible'] = [bool]$releaseNoticeEligible
        $routed.Add($resolutionEvent) | Out-Null
        $newEvents.Add($resolutionEvent) | Out-Null
        $newOutbox.Add((New-OutboxRecord $resolutionEvent $conditionHash)) | Out-Null
        $condition.resolutionNotified = $true
        $State.health.routesEmitted = [int64]$State.health.routesEmitted + 1
        $State.health.resolutionEvents = [int64]$State.health.resolutionEvents + 1
      }
    }
    $State.previous[$family] = $detector.Snapshot
    if ($hasEpoch -and $hasSequence) {
      $collector.sourceEpochHash = $epochHash
      $collector.lastSequence = $sequence
    } else {
      $collector.sourceEpochHash = $null
      $collector.lastSequence = $null
    }
    $collector.lastSuccess = $EvidenceNow.ToString('o')
  }

  $State.health.runs = [int64]$State.health.runs + 1
  $State.health.lastCycleUtc = $EvidenceNow.ToString('o')
  $State.health.lastSuccessUtc = $EvidenceNow.ToString('o')
  $State.health.lastDurationMs = [int][math]::Max(0, ((Get-Date) - $started).TotalMilliseconds)
  $State.health.lastError = $null
  $State.revision = [int64]$State.revision + 1
  if (@($State.outbox).Count + $newOutbox.Count -gt $script:OutboxLimit) { throw 'heartbeat_outbox_capacity' }
  $State.outbox = @($State.outbox + @($newOutbox))
  foreach ($event in @($newEvents)) {
    $State.events = @($State.events + [ordered]@{
      type = [string]$event.Type
      severity = [string]$event.Severity
      routeClass = Get-RouteClass ([string]$event.OwningSolThread)
      detected = [string]$event.Detected
      dedupHash = Get-StableHash ([string]$event.DedupKey)
    })
  }
  Trim-State $State
  Write-State $State $ResolvedStatePath
  return @($routed)
}

function Write-Status {
  param($State, [DateTimeOffset]$Now)
  $open = @($State.conditions.Values | Where-Object { [bool]$_.open })
  $engine = 'healthy'
  if (-not [string]::IsNullOrWhiteSpace([string]$State.health.lastError)) { $engine = 'degraded' }
  if (-not [string]::IsNullOrWhiteSpace([string]$State.health.backoffUntilUtc)) {
    try { if ($Now -lt (ConvertTo-UtcTimestamp ([string]$State.health.backoffUntilUtc) 'heartbeat_state_invalid')) { $engine = 'backoff' } } catch { $engine = 'degraded' }
  }
  $coverageCounts = @{ observed = 0; partial = 0; unsupported = 0 }
  foreach ($family in $script:Families) {
    $value = [string]$State.collectors[$family].coverage
    if ($coverageCounts.ContainsKey($value)) { $coverageCounts[$value]++ } else { $coverageCounts.unsupported++ }
  }
  $lastCycle = if ([string]::IsNullOrWhiteSpace([string]$State.health.lastCycleUtc)) { 'never' } else { [string]$State.health.lastCycleUtc }
  $activeInterventions = @($State.interventions | Where-Object { -not (Test-InterventionTerminal ([string]$_.state)) })
  $deliveryUnknown = @($activeInterventions | Where-Object { [string]$_.state -eq 'delivery_unknown' }).Count
  $outboxExhausted = @($State.outbox | Where-Object { [int]$_.attempts -ge $script:OutboxMaxAttempts }).Count
  $backoffUntil = if ([string]::IsNullOrWhiteSpace([string]$State.health.backoffUntilUtc)) { 'none' } else { [string]$State.health.backoffUntilUtc }
  Write-Output ('CHRONOS HEARTBEATS engine={0} activeTypes={1} open={2} outboxPending={3} outboxExhausted={4} interventionsActive={5} deliveryUnknown={6} coverageObserved={7} coveragePartial={8} coverageUnsupported={9} suppressed={10} routesEmitted={11} deliveryAttempts={12} lastCycle={13} durationMs={14} stateStoreMode={15} stateStoreWriteReady={16} stateStoreProtection={17} stateStoreMigration={18} priorStateDisposition={19} priorStateWriteAttempted={20} completedCycles={21} stateChanges={22} acknowledgedEvents={23} failedCycles={24} duplicateRuns={25} runtimeBudgetMs={26} runtimeObservedMs={27} runtimeOverrunMs={28} runtimeOverrunPercent={29} runtimeBaselineMs={30} runtimeClassification={31} runtimeOverrunStreak={32} runtimeBackoffApplied={33} backoffUntil={34}' -f $engine, $script:PublicFamilyCount, $open.Count, @($State.outbox).Count, $outboxExhausted, $activeInterventions.Count, $deliveryUnknown, $coverageCounts.observed, $coverageCounts.partial, $coverageCounts.unsupported, $State.health.suppressedDuplicates, $State.health.routesEmitted, $State.health.deliveryAttempts, $lastCycle, $State.health.lastDurationMs, $script:StateStoreMode, $script:StateStoreWriteReady.ToString().ToLowerInvariant(), $script:StateStoreProtection, $script:StateStoreMigration, $script:PriorStateDisposition, $script:PriorStateWriteAttempted.ToString().ToLowerInvariant(), $State.health.runs, $State.revision, $State.health.acknowledgedEvents, $State.health.failedCycles, $State.health.duplicateRuns, (Format-Number $State.health.runtimeBudgetMs), (Format-Number $State.health.runtimeObservedMs), (Format-Number $State.health.runtimeOverrunMs), (Format-Number $State.health.runtimeOverrunPercent), (Format-Number $State.health.runtimeBaselineMs), $State.health.runtimeClassification, $State.health.runtimeOverrunStreak, ([bool]$State.health.runtimeBackoffApplied).ToString().ToLowerInvariant(), $backoffUntil)
  foreach ($condition in @($open | Sort-Object @{Expression={ $script:SeverityRank[[string]$_.severity] };Descending=$true}, lastObserved | Select-Object -First 8)) {
    Write-Output ('CHRONOS HEARTBEAT CONDITION severity={0} type={1} subjectHash={2} route={3} firstObserved={4} lastObserved={5}' -f $condition.severity, $condition.type, ([string]$condition.subjectHash).Substring(0, 16), $condition.routeClass, $condition.firstObserved, $condition.lastObserved)
  }
}

function Write-SafeError {
  param([string]$Code, [string]$RequestedAction)
  $payload = [ordered]@{ ok = $false; error = $Code; action = $RequestedAction }
  Write-Output ('CHRONOS HEARTBEATS ' + ($payload | ConvertTo-Json -Compress))
}

function New-HeartbeatMutex {
  param([string]$ResolvedStatePath)
  $identity = Get-CanonicalStateIdentity $ResolvedStatePath
  $name = 'Global\ChronosHeartbeat-' + (Get-StableHash $identity).Substring(0, 24)
  try {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security = New-Object Security.AccessControl.MutexSecurity
    $rule = New-Object Security.AccessControl.MutexAccessRule($sid, [Security.AccessControl.MutexRights]::FullControl, [Security.AccessControl.AccessControlType]::Allow)
    $security.AddAccessRule($rule)
    $created = $false
    return New-Object Threading.Mutex($false, $name, [ref]$created, $security)
  } catch {
    throw 'heartbeat_mutex_unavailable'
  }
}

$mutex = $null
$acquired = $false
$state = $null
$resolved = $null
try {
  if ($Action -notin @('cycle', 'status', 'acknowledge', 'intervention-list', 'intervention-plan', 'intervention-fail-closed', 'intervention-claim', 'intervention-reclaim', 'intervention-transport', 'intervention-response', 'intervention-verify')) { throw 'heartbeat_action_invalid' }
  $resolved = Resolve-StatePath $StatePath $Scope
  Initialize-StateStore $resolved.Path
  $input = $null
  $deliveryNow = [DateTimeOffset]::UtcNow
  $evidenceNow = $deliveryNow
  if ($Action -eq 'cycle') {
    if ([string]::IsNullOrWhiteSpace($InputPath) -and [string]::IsNullOrWhiteSpace($InspectorOutputPath)) { throw 'heartbeat_input_required' }
    $input = Read-NormalizedInput $InputPath
    Merge-InspectorOutput $input $InspectorOutputPath
    Assert-Input $input
    $evidenceNow = if (Has-Value $input 'capturedAtUtc') { ConvertTo-UtcTimestamp $input.capturedAtUtc } else { $deliveryNow }
    if ($evidenceNow -gt $deliveryNow.AddMinutes(10)) { throw 'heartbeat_time_in_future' }
  }
  $mutex = New-HeartbeatMutex $resolved.Path
  $abandoned = $false
  $mutexWaitMilliseconds = if ($Action -eq 'cycle') { 5000 } else { 1000 }
  try { $acquired = $mutex.WaitOne($mutexWaitMilliseconds) } catch [Threading.AbandonedMutexException] { $acquired = $true; $abandoned = $true }
  if (-not $acquired) {
    if ($Action -eq 'cycle') {
      Write-Output 'CHRONOS HEARTBEATS {"ok":false,"error":"heartbeat_mutex_busy","cycleDropped":false,"retryRequired":true}'
      exit 1
    }
    throw 'heartbeat_mutex_busy'
  }
  # Always reopen and validate authoritative state after acquisition. This is
  # mandatory after an abandoned mutex because the prior owner may have died.
  Import-LegacyStateIfPresent $resolved
  $state = Read-State $resolved.Path $resolved.ScopeHash
  if ($Action -eq 'status') {
    Write-Status $state ([DateTimeOffset]::UtcNow)
    exit 0
  }
  if ($Action -eq 'acknowledge') {
    $acknowledged = Acknowledge-OutboxEvent $state $EventId $resolved.Path
    $payload = [ordered]@{ ok = $true; action = 'acknowledge'; eventId = $EventId; acknowledged = $acknowledged }
    Write-Output ('CHRONOS HEARTBEATS ' + ($payload | ConvertTo-Json -Compress))
    exit 0
  }
  if ($Action -eq 'intervention-list') {
    Write-Output ('CHRONOS INTERVENTIONS ' + ((Invoke-InterventionList $state $GovernorId $deliveryNow) | ConvertTo-Json -Compress -Depth 6))
    exit 0
  }
  if ($Action -eq 'intervention-plan') {
    Write-InterventionPayload (Invoke-InterventionPlan $state $resolved.Path $EventId $CorroboratingEventId $TargetId $TargetGeneration $GovernorId $deliveryNow)
    exit 0
  }
  if ($Action -eq 'intervention-fail-closed') {
    Write-InterventionPayload (Invoke-InterventionFailClosed $state $resolved.Path $EventId $FailureReason $deliveryNow)
    exit 0
  }
  if ($Action -eq 'intervention-claim') {
    Write-InterventionPayload (Invoke-InterventionClaim $state $resolved.Path $InterventionId $InterventionVersion $TargetId $TargetGeneration $GovernorId $deliveryNow)
    exit 0
  }
  if ($Action -eq 'intervention-reclaim') {
    Write-InterventionPayload (Invoke-InterventionReclaim $state $resolved.Path $InterventionId $InterventionVersion $GovernorId $deliveryNow)
    exit 0
  }
  if ($Action -eq 'intervention-transport') {
    Write-InterventionPayload (Invoke-InterventionTransport $state $resolved.Path $InterventionId $InterventionVersion $ClaimToken $TransportResult $deliveryNow)
    exit 0
  }
  if ($Action -eq 'intervention-response') {
    Write-InterventionPayload (Invoke-InterventionResponse $state $resolved.Path $InterventionId $InterventionVersion $TargetId $TargetGeneration $TaskResponse $deliveryNow)
    exit 0
  }
  if ($Action -eq 'intervention-verify') {
    Write-InterventionPayload (Invoke-InterventionVerify $state $resolved.Path $InterventionId $InterventionVersion $TargetId $TargetGeneration $VerificationSource $VerificationResult $deliveryNow)
    exit 0
  }
  $events = @(Invoke-Cycle $input $state $resolved.Path $evidenceNow $deliveryNow)
  if ($events.Count -gt 0) {
    $payload = [ordered]@{ ok = $true; eventCount = $events.Count; events = $events }
    Write-Output ('CHRONOS HEARTBEATS ' + ($payload | ConvertTo-Json -Compress -Depth 10))
    Mark-OutboxAttempts $state @($events | ForEach-Object { [string]$_.EventId }) $resolved.Path $deliveryNow
  }
  exit 0
} catch {
  $code = [string]$_.Exception.Message
  if ($code -notmatch '^heartbeat_[a-z_]+$') { $code = 'heartbeat_internal_error' }
  if ($Action -eq 'cycle' -and $acquired -and $null -ne $resolved) {
    try {
      $committed = Read-State $resolved.Path $resolved.ScopeHash
      $committed.health.failedCycles = [int64]$committed.health.failedCycles + 1
      $committed.health.lastError = $code
      $committed.revision = [int64]$committed.revision + 1
      Write-State $committed $resolved.Path
    } catch {
      # Preserve the original privacy-safe cycle error if failure accounting
      # cannot be committed.
    }
  }
  Write-SafeError $code $Action
  exit 1
} finally {
  if ($mutex) {
    if ($acquired) { try { $mutex.ReleaseMutex() | Out-Null } catch {} }
    $mutex.Dispose()
  }
}
