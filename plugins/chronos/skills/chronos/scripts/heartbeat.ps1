param(
  [string]$Action = 'cycle',
  [string]$InputPath,
  [string]$InspectorOutputPath,
  [string]$StatePath,
  [string]$Scope,
  [string]$EventId,
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
$script:InputByteLimit = 262144
$script:InspectorByteLimit = 65536
$script:StateByteLimit = 262144
$script:JsonNodeLimit = 32768

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
  Assert-AllowedKeys $Record @('id', 'owner', 'owningSolThread', 'active', 'repeatedEquivalentActions', 'minutesSinceMeaningfulChange', 'tokensSinceMeaningfulChange', 'longRunningOperation', 'progressHash', 'lastToolHash', 'lastCommandHash', 'lastFileChangeUtc', 'lastGitHash', 'lastTestHash', 'totalTokens', 'operationClass', 'status')
  Assert-Field $Record 'id' id $true
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
  Assert-AllowedKeys $Record @('owner', 'dominantThread', 'owningSolThread', 'totalTokens', 'windowTokens', 'windowMinutes', 'ratePerMinute', 'baselineRatePerMinute', 'projectedExhaustionMinutes', 'reviewerShare', 'meaningfulProgress', 'progressHash')
  Assert-Field $Record 'owner' id
  Assert-Field $Record 'dominantThread' id
  Assert-Field $Record 'owningSolThread' id
  foreach ($name in @('totalTokens', 'windowTokens')) { Assert-Field $Record $name integer $false 0 9000000000000000 }
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
  Assert-AllowedKeys $Record @('name', 'owner', 'owningSolThread', 'status', 'commit', 'repairAttempts', 'failureCount', 'required', 'ran', 'environmentStatuses', 'buildId')
  Assert-Field $Record 'name' label $true
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
  Assert-AllowedKeys $Record @('id', 'owner', 'owningSolThread', 'status', 'dependsOn', 'dependencyStatus', 'ageHours', 'requiredCommit', 'requiredPush', 'requiredValidation', 'validationStatus', 'acknowledgedBug', 'assigned', 'updatedAt')
  Assert-Field $Record 'id' id $true
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
  Assert-AllowedKeys $Record @('origin', 'schedulerDuplicates', 'runtimeSeconds', 'runId', 'parentRunId')
  Assert-Field $Record 'origin' enum $false 0 0 @('host', 'heartbeat', 'heartbeat_notification', 'test')
  Assert-Field $Record 'schedulerDuplicates' integer $false 0 1000000
  Assert-Field $Record 'runtimeSeconds' number $false 0 86400
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
  if ([string]::IsNullOrWhiteSpace($RequestedScope)) {
    $codexHome = Join-Path $HOME '.codex'
    $RequestedScope = '{0}|{1}|{2}' -f $env:COMPUTERNAME, ([IO.Path]::GetFullPath($codexHome)), ([IO.Path]::GetFullPath((Get-Location).Path))
  }
  if ($RequestedScope.Length -gt 4096) { throw 'heartbeat_scope_invalid' }
  if ([string]::IsNullOrWhiteSpace($Requested)) {
    $scopeHash = Get-StableHash $RequestedScope
    return [pscustomobject]@{ Path = (Join-Path $localRoot (Join-Path $scopeHash 'heartbeat-state.json')); ScopeHash = $scopeHash }
  }
  try { $full = [IO.Path]::GetFullPath($Requested) } catch { throw 'heartbeat_state_path_invalid' }
  if ([IO.Path]::GetExtension($full) -ne '.json') { throw 'heartbeat_state_path_invalid' }
  if (-not (Test-ContainedPath $full $localRoot) -and -not (Test-ContainedPath $full $tempRoot)) { throw 'heartbeat_state_path_invalid' }
  if (-not (Test-NoReparseAncestors $full)) { throw 'heartbeat_state_path_invalid' }
  return [pscustomobject]@{ Path = $full; ScopeHash = (Get-StableHash $RequestedScope) }
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
    schema = 4
    revision = 0
    scopeHash = $ScopeHash
    previous = $previous
    conditions = @{}
    events = @()
    outbox = @()
    collectors = $collectors
    health = [ordered]@{
      runs = 0
      suppressedDuplicates = 0
      routesEmitted = 0
      resolutionEvents = 0
      duplicateRuns = 0
      mutexContention = 0
      lastCycleUtc = $null
      lastSuccessUtc = $null
      lastDurationMs = 0
      lastRunIdHash = $null
      lastError = $null
      backoffUntilUtc = $null
      deliveryAttempts = 0
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
  foreach ($key in $Record.Keys) {
    if ($Allowed -notcontains [string]$key -or -not (Test-PersistedScalar $Record[$key])) { throw 'heartbeat_state_invalid' }
    if ($null -eq $Record[$key] -or -not ($Record[$key] -is [string])) { continue }
    $text = [string]$Record[$key]
    if ([string]$key -match 'Hash$' -or [string]$key -eq 'eventId') {
      if ($text -notmatch '^[a-f0-9]{16,64}$') { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -in @('lastAttempt', 'lastRun', 'lastSuccess', 'backoffUntilUtc', 'firstObserved', 'lastObserved', 'lastNotified', 'resolvedAt', 'detected', 'lastCycleUtc', 'lastSuccessUtc')) {
      [void](ConvertTo-UtcTimestamp $text 'heartbeat_state_invalid')
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
    } elseif ([string]$key -in @('status', 'testStatus', 'installStatus', 'dependencyStatus', 'taskStatus', 'validationStatus', 'buildStatus')) {
      if ($statusValues -notcontains $text) { throw 'heartbeat_state_invalid' }
    } elseif ([string]$key -eq 'lastError') {
      if ($text -notmatch '^heartbeat_[a-z_]+$') { throw 'heartbeat_state_invalid' }
    } else {
      throw 'heartbeat_state_invalid'
    }
  }
}

function Assert-State {
  param($State, [string]$ExpectedScopeHash)
  if (-not ($State -is [System.Collections.IDictionary])) { throw 'heartbeat_state_invalid' }
  $top = @('schema', 'revision', 'scopeHash', 'previous', 'conditions', 'events', 'outbox', 'collectors', 'health', 'runIds')
  foreach ($key in $State.Keys) { if ($top -notcontains [string]$key) { throw 'heartbeat_state_invalid' } }
  if ([int]$State.schema -ne 4 -or [int64]$State.revision -lt 0 -or [string]$State.scopeHash -ne $ExpectedScopeHash) { throw 'heartbeat_state_invalid' }
  if (-not ($State.previous -is [System.Collections.IDictionary]) -or -not ($State.conditions -is [System.Collections.IDictionary]) -or -not ($State.collectors -is [System.Collections.IDictionary]) -or -not ($State.health -is [System.Collections.IDictionary])) { throw 'heartbeat_state_invalid' }
  if ($State.conditions.Count -gt $script:ConditionLimit -or @($State.events).Count -gt $script:EventLimit -or @($State.outbox).Count -gt $script:OutboxLimit -or @($State.runIds).Count -gt $script:RunIdLimit) { throw 'heartbeat_state_invalid' }
  $snapshotFields = @('active', 'progressHash', 'repeated', 'idleMinutes', 'tokens', 'totalTokens', 'longRunning', 'status', 'reviewCount', 'reviewsPerHour', 'ratio', 'turnShare', 'repeats', 'executions', 'pendingAllowed', 'acceleration', 'recursion', 'rate', 'baselineRate', 'projectionMinutes', 'reviewerShare', 'meaningfulProgress', 'childCount', 'forkDepth', 'overlap', 'compactions', 'rolloutBytes', 'growthRate', 'childRate', 'recursive', 'commitHash', 'repairAttempts', 'failureCount', 'environmentHash', 'required', 'ran', 'regressionActive', 'versionHash', 'intendedHash', 'drift', 'testStatus', 'installStatus', 'missingSkills', 'mcpConfigured', 'dependencyStatus', 'taskStatus', 'ageHours', 'assigned', 'acknowledgedBug', 'requiredCommit', 'requiredPush', 'requiredValidation', 'validationStatus', 'actionableActive', 'dirty', 'completedTaskIdle', 'requiresCommit', 'requiresPush', 'idleMinutes', 'ahead', 'behind', 'mergeConflict', 'branchChanged', 'destructiveOperation', 'expectedCommitPushed', 'conflictingScopes', 'buildStatus', 'identityMismatch', 'missingFiles', 'manifestMatches', 'sizeRatio', 'artifactHashMatches', 'schedulerDuplicates', 'runtimeSeconds')
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
    Assert-StateRecord $item @('eventId', 'event', 'type', 'severity', 'subjectHash', 'conditionHash', 'routeHash', 'routeClass', 'detected', 'attempts', 'lastAttempt')
    if ([string]$item.eventId -notmatch '^[a-f0-9]{64}$' -or [string]$item.conditionHash -notmatch '^[a-f0-9]{64}$' -or [string]$item.routeHash -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_state_invalid' }
    if ([string]$item.event -notin @('HEARTBEAT_EVENT', 'HEARTBEAT_RESOLVED')) { throw 'heartbeat_state_invalid' }
  }
  Assert-StateRecord $State.health @('runs', 'suppressedDuplicates', 'routesEmitted', 'resolutionEvents', 'duplicateRuns', 'mutexContention', 'lastCycleUtc', 'lastSuccessUtc', 'lastDurationMs', 'lastRunIdHash', 'lastError', 'backoffUntilUtc', 'deliveryAttempts')
  foreach ($runId in @($State.runIds)) { if ([string]$runId -notmatch '^[a-f0-9]{64}$') { throw 'heartbeat_state_invalid' } }
}

function Read-State {
  param([string]$Path, [string]$ScopeHash)
  if (-not (Test-Path -LiteralPath $Path)) { return New-DefaultState $ScopeHash }
  try {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $script:StateByteLimit) { throw 'invalid' }
    $text = Read-StrictUtf8JsonFile $Path $script:StateByteLimit 'heartbeat_state_invalid'
    $state = ConvertTo-Hashtable ($text | ConvertFrom-Json -ErrorAction Stop)
    Assert-State $state $ScopeHash
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
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
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
  param([string]$Family, [string]$Type, [string]$Severity, [string]$Subject, $Owner, $Thread, [string]$Reason, [string[]]$Changed, [string[]]$Evidence, [string]$Cause, [string]$RecommendedAction, [DateTimeOffset]$Detected)
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
    $progressHash = Get-ProgressHash $agent @('progressHash', 'lastToolHash', 'lastCommandHash', 'lastFileChangeUtc', 'lastGitHash', 'lastTestHash', 'status')
    $current = [ordered]@{
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
    $identity = Get-ConditionIdentity 'agent_stall' $id 'progress'
    Add-RouteHint $result $identity $id (Get-Value $agent 'owner') (Get-Value $agent 'owningSolThread')
    if (-not $current.active -or $current.longRunning) { continue }
    $prior = Get-Value $Previous $idHash
    $noProgress = $null -ne $prior -and [string]$prior.progressHash -eq $progressHash
    $tokenDelta = $current.tokens
    if ($prior -and $current.totalTokens -ge [int64]$prior.totalTokens) { $tokenDelta = [math]::Max($tokenDelta, $current.totalTokens - [int64]$prior.totalTokens) }
    $absoluteExtreme = $current.repeated -ge 8 -and $current.idleMinutes -ge ($StallMinutes * 2)
    $stalled = ($noProgress -and $current.idleMinutes -ge $StallMinutes -and ($current.repeated -ge 3 -or $tokenDelta -ge 20000)) -or $absoluteExtreme
    if (-not $stalled) { continue }
    $severity = if ($current.repeated -ge 20 -or $tokenDelta -ge 500000) { 'CRITICAL' } elseif ($current.repeated -ge 8 -or $tokenDelta -ge 100000) { 'HIGH' } else { 'WARNING' }
    Add-Candidate $result (New-Candidate 'agent_stall' 'AGENT_STALL' $severity $id (Get-Value $agent 'owner') (Get-Value $agent 'owningSolThread') 'progress' @('meaningfulProgress=unchanged', ('idleMinutes=' + (Format-Number $current.idleMinutes))) @('equivalentActions=' + $current.repeated, 'tokensWithoutProgress=' + $tokenDelta) 'The active agent repeated work without a meaningful state delta.' 'Inspect the blocked operation. Stop or re-scope only the affected work.' $Now)
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
  }
  $result.Snapshot[$idHash] = $current
  $identity = Get-ConditionIdentity 'usage' $subject 'burn'
  Add-RouteHint $result $identity $subject (Get-Value $usage 'owner' 'governor') (Get-Value $usage 'owningSolThread')
  $prior = Get-Value $Previous $idHash
  $reference = if ($current.baselineRate -gt 0) { $current.baselineRate } elseif ($prior -and [double]$prior.rate -gt 0) { [double]$prior.rate } else { 0 }
  $rateMultiple = if ($reference -gt 0) { $current.rate / $reference } else { 1 }
  $projectionWorsened = $prior -and $current.projectionMinutes -gt 0 -and [double]$prior.projectionMinutes -gt 0 -and $current.projectionMinutes -le ([double]$prior.projectionMinutes * .7)
  $noProgressDelta = -not $current.meaningfulProgress -and (-not $prior -or [string]$prior.progressHash -eq $current.progressHash)
  $burn = $current.rate -ge 10000 -and $rateMultiple -ge 2 -and $noProgressDelta
  if ($burn -or $projectionWorsened) {
    $severity = if ($current.projectionMinutes -gt 0 -and $current.projectionMinutes -le 10 -and $noProgressDelta) { 'CRITICAL' } elseif ($rateMultiple -ge 3 -or $current.reviewerShare -ge .75 -or $projectionWorsened) { 'HIGH' } else { 'WARNING' }
    Add-Candidate $result (New-Candidate 'usage' 'USAGE_BURN' $severity $subject (Get-Value $usage 'owner' 'governor') (Get-Value $usage 'owningSolThread') 'burn' @('rateMultiple=' + (Format-Number $rateMultiple), 'meaningfulProgress=' + $current.meaningfulProgress) @('tokensPerMinute=' + (Format-Number $current.rate), 'reviewerShare=' + (Format-Number $current.reviewerShare), 'projectedExhaustionMinutes=' + (Format-Number $current.projectionMinutes)) 'Usage velocity worsened without a matching progress signal.' 'Bound the dominant task and inspect reviewer, fork, and repeated-tool contribution.' $Now)
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

function Get-TestDetector {
  param($Snapshot, $Previous, [DateTimeOffset]$Now)
  $result = New-DetectorResult
  foreach ($test in (As-Array (Get-Value $Snapshot 'tests'))) {
    $name = [string]$test.name
    $idHash = Get-StableHash $name
    $prior = Get-Value $Previous $idHash
    $environmentValues = @(Get-EnvironmentStatusValues (Get-Value $test 'environmentStatuses'))
    $environmentHash = Get-StableHash (@($environmentValues | Sort-Object))
    $commitHash = if (Has-Value $test 'commit') { Get-StableHash ([string]$test.commit) } else { Get-StableHash 'unknown' }
    $current = [ordered]@{
      status = [string]$test.status
      commitHash = $commitHash
      repairAttempts = [int](Get-Value $test 'repairAttempts' 0)
      failureCount = [int](Get-Value $test 'failureCount' 0)
      environmentHash = $environmentHash
      required = [bool](Get-Value $test 'required' $false)
      ran = [bool](Get-Value $test 'ran' $true)
      regressionActive = $false
    }
    foreach ($reason in @('regression', 'environment-drift', 'validation-missing')) {
      $identity = Get-ConditionIdentity 'tests' $name $reason
      Add-RouteHint $result $identity $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread')
    }
    $regressed = $prior -and [string]$prior.status -eq 'passed' -and $current.status -eq 'failed'
    $repairWorsened = $prior -and $current.status -eq 'failed' -and $current.repairAttempts -gt [int]$prior.repairAttempts -and $current.repairAttempts -ge 2
    $current.regressionActive = $current.status -eq 'failed' -and ($regressed -or $repairWorsened -or ($prior -and [bool](Get-Value $prior 'regressionActive' $false)))
    $result.Snapshot[$idHash] = $current
    if ($current.regressionActive) {
      $severity = if ($current.repairAttempts -ge 4 -or $current.failureCount -ge 5) { 'CRITICAL' } else { 'HIGH' }
      Add-Candidate $result (New-Candidate 'tests' 'TEST_REGRESSION' $severity $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread') 'regression' @('status=' + $(if ($regressed) { 'passed->failed' } else { 'failed->failed' })) @('repairAttempts=' + $current.repairAttempts, 'failureCount=' + $current.failureCount, 'commitHash=' + $commitHash.Substring(0, 16)) 'A known-good test regressed or remained broken after additional repair work.' 'Investigate the introducing change and preserve the failing evidence.' $Now)
    }
    if (($environmentValues | Select-Object -Unique).Count -gt 1) {
      Add-Candidate $result (New-Candidate 'tests' 'TEST_ENVIRONMENT_DRIFT' 'WARNING' $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread') 'environment-drift' @('environmentResults=disagree') @('resultVariants=' + (($environmentValues | Select-Object -Unique).Count)) 'The same validation differs across supplied environments.' 'Compare installed version, configuration, and artifact identity.' $Now)
    }
    if ($current.required -and -not $current.ran) {
      Add-Candidate $result (New-Candidate 'tests' 'TEST_VALIDATION_MISSING' 'WARNING' $name (Get-Value $test 'owner') (Get-Value $test 'owningSolThread') 'validation-missing' @('requiredValidation=not_run') @('status=' + $current.status) 'Required validation was not run.' 'Run the required validation before release or handoff.' $Now)
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
    $prior = Get-Value $Previous $idHash
    $current = [ordered]@{
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
      $identity = Get-ConditionIdentity 'tasks' $id $reason
      Add-RouteHint $result $identity $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread')
    }
    $dependencyTransition = $prior -and [string]$prior.dependencyStatus -ne 'completed' -and $current.dependencyStatus -eq 'completed'
    $current.actionableActive = $current.taskStatus -eq 'waiting' -and ($dependencyTransition -or ($prior -and [bool](Get-Value $prior 'actionableActive' $false)))
    $result.Snapshot[$idHash] = $current
    if ($current.actionableActive) {
      Add-Candidate $result (New-Candidate 'tasks' 'TASK_ACTIONABLE' 'WARNING' $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread') 'actionable' @('dependencyStatus=incomplete->completed') @('dependencyHash=' + (Get-StableHash (Get-Value $task 'dependsOn' 'unknown')).Substring(0, 16)) 'A dependency completed while this task remained waiting.' 'Resume the owning task or explicitly reclassify it.' $Now)
    }
    $zombie = (($current.taskStatus -eq 'todo' -or $current.acknowledgedBug) -and -not $current.assigned -and $current.ageHours -ge 24)
    if ($zombie) {
      Add-Candidate $result (New-Candidate 'tasks' 'ZOMBIE_TASK' 'WARNING' $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread') 'zombie' @('ownership=unassigned') @('ageHours=' + (Format-Number $current.ageHours), 'acknowledgedBug=' + $current.acknowledgedBug) 'Recorded work has no active owner.' 'Assign the work or close it explicitly.' $Now)
    }
    $unfinished = $current.taskStatus -eq 'completed' -and (($current.requiredValidation -and $current.validationStatus -ne 'passed') -or $current.requiredCommit -or $current.requiredPush)
    if ($unfinished) {
      Add-Candidate $result (New-Candidate 'tasks' 'TASK_HANDOFF_INCOMPLETE' 'WARNING' $id (Get-Value $task 'owner') (Get-Value $task 'owningSolThread') 'unfinished-handoff' @('task=completed', 'handoff=incomplete') @('validation=' + $current.validationStatus, 'commitRequired=' + $current.requiredCommit, 'pushRequired=' + $current.requiredPush) 'Completed work still has a required handoff action.' 'Complete or explicitly waive the remaining commit, push, or validation step.' $Now)
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
  $current = [ordered]@{
    schedulerDuplicates = [int](Get-Value $activity 'schedulerDuplicates' 0)
    runtimeSeconds = [double](Get-Value $activity 'runtimeSeconds' 0)
  }
  $result.Snapshot[(Get-StableHash 'heartbeat-engine')] = $current
  $identity = Get-ConditionIdentity 'heartbeat' 'heartbeat-engine' 'self-health'
  Add-RouteHint $result $identity 'heartbeat-engine' 'governor' 'governor'
  if ($current.schedulerDuplicates -ge 2 -or $current.runtimeSeconds -ge 30) {
    $severity = if ($current.schedulerDuplicates -ge 5 -or $current.runtimeSeconds -ge 120) { 'CRITICAL' } else { 'HIGH' }
    Add-Candidate $result (New-Candidate 'heartbeat' 'HEARTBEAT_SELF_HEALTH' $severity 'heartbeat-engine' 'governor' 'governor' 'self-health' @('monitoringHealth=degraded') @('schedulerDuplicates=' + $current.schedulerDuplicates, 'runtimeSeconds=' + (Format-Number $current.runtimeSeconds)) 'Heartbeat scheduling or runtime is itself abnormal.' 'Back off this collector and keep one scheduler owner.' $Now)
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

function Convert-CandidateToEvent {
  param($Candidate, [string]$EventId)
  $route = Get-RouteTarget $Candidate
  return [ordered]@{
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
  }
}

function New-ResolutionEvent {
  param($Condition, [string]$ConditionHash, $RouteHint, [DateTimeOffset]$Now, [string]$EventId)
  $owner = if ($RouteHint) { $RouteHint.Owner } else { $null }
  $subject = if ($RouteHint) { [string]$RouteHint.Subject } else { [string]$Condition.subjectHash }
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
  }
}

function New-OutboxRecord {
  param($Event, [string]$ConditionHash)
  return [ordered]@{
    eventId = [string]$Event.EventId
    event = [string]$Event.Event
    type = [string]$Event.Type
    severity = [string]$Event.Severity
    subjectHash = Get-StableHash ([string]$Event.Subject)
    conditionHash = $ConditionHash
    routeHash = Get-StableHash ([string]$Event.OwningSolThread)
    routeClass = Get-RouteClass ([string]$Event.OwningSolThread)
    detected = [string]$Event.Detected
    attempts = 0
    lastAttempt = $null
  }
}

function Convert-OutboxToRetryEvent {
  param($Record)
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
    if ($due) { $result.Add((Convert-OutboxToRetryEvent $record)) | Out-Null }
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
    $State.revision = [int64]$State.revision + 1
    Write-State $State $ResolvedStatePath
  }
  return $acknowledged
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
    $counterContinuity = $continuity -and (Test-FamilyCounterContinuity $family $State.previous[$family] $detector.Snapshot)
    $seen = @{}
    foreach ($candidate in @($detector.Candidates)) {
      $conditionHash = [string]$candidate.ConditionHash
      $seen[$conditionHash] = $true
      $old = Get-Value $State.conditions $conditionHash
      $oldRank = if ($old -and $script:SeverityRank.ContainsKey([string]$old.severity)) { [int]$script:SeverityRank[[string]$old.severity] } else { 0 }
      $newRank = [int]$script:SeverityRank[[string]$candidate.Severity]
      $notify = $null -eq $old -or -not [bool]$old.open -or $newRank -gt $oldRank
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
        severity = [string]$candidate.Severity
        open = $true
        firstObserved = if ($old) { [string]$old.firstObserved } else { [string]$candidate.Detected }
        lastObserved = [string]$candidate.Detected
        lastNotified = if ($notify) { [string]$candidate.Detected } elseif ($old) { [string]$old.lastNotified } else { $null }
        occurrences = if ($old) { [int64]$old.occurrences + 1 } else { 1 }
        episode = $episode
        sourceEpochHash = if ($old -and [bool]$old.open) { $old.sourceEpochHash } else { $epochHash }
        signatureHash = Get-StableHash @{ type = $candidate.Type; severity = $candidate.Severity }
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
      if (-not [bool]$condition.resolutionNotified) {
        $hint = Get-Value $detector.Routes $conditionHash
        $resolutionEventId = Get-StableHash ('heartbeat-event-v1|{0}|{1}|resolved' -f $conditionHash, [int64](Get-Value $condition 'episode' 1))
        $resolutionEvent = New-ResolutionEvent $condition $conditionHash $hint $EvidenceNow $resolutionEventId
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
  Write-Output ('CHRONOS HEARTBEATS engine={0} activeTypes={1} open={2} outboxPending={3} coverageObserved={4} coveragePartial={5} coverageUnsupported={6} suppressed={7} routesEmitted={8} deliveryAttempts={9} lastCycle={10} durationMs={11}' -f $engine, $script:PublicFamilyCount, $open.Count, @($State.outbox).Count, $coverageCounts.observed, $coverageCounts.partial, $coverageCounts.unsupported, $State.health.suppressedDuplicates, $State.health.routesEmitted, $State.health.deliveryAttempts, $lastCycle, $State.health.lastDurationMs)
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
try {
  if ($Action -notin @('cycle', 'status', 'acknowledge')) { throw 'heartbeat_action_invalid' }
  $resolved = Resolve-StatePath $StatePath $Scope
  if ($Action -eq 'status') {
    $state = Read-State $resolved.Path $resolved.ScopeHash
    Write-Status $state ([DateTimeOffset]::UtcNow)
    exit 0
  }
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
  try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true; $abandoned = $true }
  if (-not $acquired) {
    if ($Action -eq 'cycle') { exit 0 }
    throw 'heartbeat_mutex_busy'
  }
  # Always reopen and validate authoritative state after acquisition. This is
  # mandatory after an abandoned mutex because the prior owner may have died.
  $state = Read-State $resolved.Path $resolved.ScopeHash
  if ($Action -eq 'acknowledge') {
    $acknowledged = Acknowledge-OutboxEvent $state $EventId $resolved.Path
    $payload = [ordered]@{ ok = $true; action = 'acknowledge'; eventId = $EventId; acknowledged = $acknowledged }
    Write-Output ('CHRONOS HEARTBEATS ' + ($payload | ConvertTo-Json -Compress))
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
  Write-SafeError $code $Action
  exit 1
} finally {
  if ($mutex) {
    if ($acquired) { try { $mutex.ReleaseMutex() | Out-Null } catch {} }
    $mutex.Dispose()
  }
}
