$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:HookInputByteLimit = 65536
$script:JsonNodeLimit = 8192
$script:PendingEventLimit = 256
$script:PendingEventByteLimit = 4096
$script:Entropy = [Text.Encoding]::UTF8.GetBytes('Chronos.Supervision.Registry.v1')

function Get-Value {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Move-JsonWhitespace {
  param([string]$Text, [ref]$Index)
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -in @(' ', "`t", "`r", "`n")) { $Index.Value++ }
}

function Read-StrictJsonString {
  param([string]$Text, [ref]$Index)
  if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne '"') { throw 'hook_json_invalid' }
  $start = $Index.Value
  $Index.Value++
  while ($Index.Value -lt $Text.Length) {
    $character = $Text[$Index.Value]
    if ([int][char]$character -lt 0x20) { throw 'hook_json_invalid' }
    if ($character -eq '"') {
      $Index.Value++
      try {
        $decoded = $Text.Substring($start, $Index.Value - $start) | ConvertFrom-Json -ErrorAction Stop
        if (-not ($decoded -is [string])) { throw 'hook_json_invalid' }
        return $decoded.Normalize([Text.NormalizationForm]::FormC)
      } catch { throw 'hook_json_invalid' }
    }
    if ($character -eq '\') {
      $Index.Value++
      if ($Index.Value -ge $Text.Length) { throw 'hook_json_invalid' }
      $escape = $Text[$Index.Value]
      if ($escape -eq 'u') {
        if ($Index.Value + 4 -ge $Text.Length -or $Text.Substring($Index.Value + 1, 4) -notmatch '^[0-9A-Fa-f]{4}$') { throw 'hook_json_invalid' }
        $Index.Value += 5
        continue
      }
      if ($escape -notin @('"', '\', '/', 'b', 'f', 'n', 'r', 't')) { throw 'hook_json_invalid' }
    }
    $Index.Value++
  }
  throw 'hook_json_invalid'
}

function Assert-StrictJsonValue {
  param([string]$Text, [ref]$Index, [ref]$NodeCount, [int]$Depth)
  if ($Depth -gt 16) { throw 'hook_json_invalid' }
  Move-JsonWhitespace $Text $Index
  if ($Index.Value -ge $Text.Length) { throw 'hook_json_invalid' }
  $NodeCount.Value++
  if ($NodeCount.Value -gt $script:JsonNodeLimit) { throw 'hook_json_invalid' }
  $character = $Text[$Index.Value]
  if ($character -eq '"') { [void](Read-StrictJsonString $Text $Index); return }
  if ($character -eq '{') {
    $Index.Value++
    Move-JsonWhitespace $Text $Index
    $keys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq '}') { $Index.Value++; return }
    while ($true) {
      Move-JsonWhitespace $Text $Index
      $key = Read-StrictJsonString $Text $Index
      if (-not $keys.Add($key)) { throw 'hook_json_invalid' }
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne ':') { throw 'hook_json_invalid' }
      $Index.Value++
      Assert-StrictJsonValue $Text $Index $NodeCount ($Depth + 1)
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length) { throw 'hook_json_invalid' }
      if ($Text[$Index.Value] -eq '}') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { throw 'hook_json_invalid' }
      $Index.Value++
    }
  }
  if ($character -eq '[') {
    $Index.Value++
    Move-JsonWhitespace $Text $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq ']') { $Index.Value++; return }
    while ($true) {
      Assert-StrictJsonValue $Text $Index $NodeCount ($Depth + 1)
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length) { throw 'hook_json_invalid' }
      if ($Text[$Index.Value] -eq ']') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { throw 'hook_json_invalid' }
      $Index.Value++
    }
  }
  $start = $Index.Value
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -notin @(',', ']', '}', ' ', "`t", "`r", "`n")) { $Index.Value++ }
  $token = $Text.Substring($start, $Index.Value - $start)
  if ($token -notmatch '^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$') { throw 'hook_json_invalid' }
}

function Assert-StrictJson {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { throw 'hook_json_invalid' }
  $index = 0
  $nodeCount = 0
  Assert-StrictJsonValue $Text ([ref]$index) ([ref]$nodeCount) 0
  Move-JsonWhitespace $Text ([ref]$index)
  if ($index -ne $Text.Length) { throw 'hook_json_invalid' }
}

function Get-TextHash {
  param([string]$Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Test-ContainedPath {
  param([string]$Path, [string]$Root)
  try {
    $full = [IO.Path]::GetFullPath($Path)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  } catch { return $false }
  return $full.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
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

function Normalize-OpaqueId {
  param($Value)
  if (-not ($Value -is [string])) { throw 'hook_id_invalid' }
  $text = $Value.Trim()
  if ($text.Length -lt 1 -or $text.Length -gt 192 -or $text -notmatch '^[A-Za-z0-9._:/-]+$') { throw 'hook_id_invalid' }
  if ($text -match '^[A-Za-z]:[\\/]' -or $text -match '^\\' -or ($text.StartsWith('/') -and -not $text.StartsWith('/root/'))) { throw 'hook_id_invalid' }
  return $text
}

function Protect-OpaqueId {
  param([string]$Value)
  Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
  $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
  $protected = [Security.Cryptography.ProtectedData]::Protect($bytes, $script:Entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  return [Convert]::ToBase64String($protected)
}

function Resolve-CodexHomeIdentity {
  $candidate = if (-not [string]::IsNullOrWhiteSpace([string]$env:CODEX_HOME)) { [string]$env:CODEX_HOME } else { Join-Path $HOME '.codex' }
  $full = [IO.Path]::GetFullPath($candidate)
  if (-not [string]::IsNullOrWhiteSpace([string]$env:CODEX_HOME)) {
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'hook_home_invalid' }
    $full = [IO.Path]::GetFullPath($item.FullName)
  }
  if (-not (Test-NoReparseAncestors $full)) { throw 'hook_home_invalid' }
  $full = $full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  if ([string]::IsNullOrWhiteSpace($full)) { throw 'hook_home_invalid' }
  return $full.ToUpperInvariant()
}

function Resolve-HookInboxDirectory {
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $homeIdentity = Resolve-CodexHomeIdentity
  $scopeHash = Get-TextHash ('{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), $homeIdentity)
  $directory = [IO.Path]::GetFullPath((Join-Path $tempRoot ('Chronos-Supervision-Inbox-v1-{0}' -f $scopeHash.Substring(0, 24))))
  if (-not (Test-ContainedPath $directory $tempRoot) -or -not (Test-NoReparseAncestors $directory)) { throw 'hook_inbox_invalid' }
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
  $item = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
  if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $directory)) { throw 'hook_inbox_invalid' }
  return $directory
}

function New-HookRecord {
  param($Data, [DateTimeOffset]$ObservedAt)
  $event = [string](Get-Value $Data 'hook_event_name' '')
  if ($event -notin @('SessionStart', 'SessionEnd', 'SubagentStart', 'SubagentStop', 'Stop')) { throw 'hook_event_invalid' }
  $session = Normalize-OpaqueId (Get-Value $Data 'session_id')
  $agent = $null
  if ($event -in @('SubagentStart', 'SubagentStop')) { $agent = Normalize-OpaqueId (Get-Value $Data 'agent_id') }
  $source = if ($event -eq 'SessionStart') { [string](Get-Value $Data 'source' 'startup') } elseif ($event -in @('SubagentStart', 'SubagentStop')) { 'subagent' } else { 'fallback' }
  if ($event -eq 'SessionStart' -and $source -notin @('startup', 'resume', 'clear', 'compact')) { throw 'hook_source_invalid' }
  $workspace = Get-Value $Data 'cwd'
  $workspaceHash = if ($workspace -is [string] -and $workspace.Length -ge 1 -and $workspace.Length -le 4096) {
    try { Get-TextHash ([IO.Path]::GetFullPath($workspace).TrimEnd([char[]]@('\\', '/')).ToUpperInvariant()) } catch { Get-TextHash 'workspace-unavailable' }
  } else { Get-TextHash 'workspace-unavailable' }
  $modelValue = Get-Value $Data 'model'
  $model = if ($modelValue -is [string] -and $modelValue.Trim() -match '^[A-Za-z0-9._:/-]{1,128}$') { $modelValue.Trim() } else { 'unavailable' }
  return [ordered]@{
    schema = 2
    event = $event
    protectedSessionId = Protect-OpaqueId $session
    protectedAgentId = if ($null -ne $agent) { Protect-OpaqueId $agent } else { $null }
    workspaceHash = $workspaceHash
    model = $model
    source = $source
    signalHash = if ($event -eq 'Stop') { Get-TextHash (Normalize-OpaqueId (Get-Value $Data 'turn_id')) } else { $null }
    observedAtUtc = $ObservedAt.ToString('o')
  }
}

function Write-HookRecord {
  param([string]$Directory, $Record)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Record | ConvertTo-Json -Compress -Depth 4))
  if ($bytes.Length -gt $script:PendingEventByteLimit) { throw 'hook_event_oversize' }
  foreach ($staleReservation in @(Get-ChildItem -LiteralPath $Directory -File -Force -Filter 'pending-slot-*.lock' | Select-Object -First $script:PendingEventLimit)) {
    if ($staleReservation.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddMinutes(-5)) { Remove-Item -LiteralPath $staleReservation.FullName -Force -ErrorAction SilentlyContinue }
  }
  $start = [int]([BitConverter]::ToUInt32(([guid]::NewGuid()).ToByteArray(), 0) % [uint32]$script:PendingEventLimit)
  $reservation = $null
  $final = $null
  for ($offset = 0; $offset -lt $script:PendingEventLimit; $offset++) {
    $slot = ($start + $offset) % $script:PendingEventLimit
    $candidateFinal = Join-Path $Directory ('pending-slot-{0:d3}.json' -f $slot)
    $candidateReservation = Join-Path $Directory ('pending-slot-{0:d3}.lock' -f $slot)
    if (Test-Path -LiteralPath $candidateFinal -PathType Leaf) { continue }
    try {
      $reserveStream = New-Object IO.FileStream($candidateReservation, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      $reserveStream.Dispose()
      if (Test-Path -LiteralPath $candidateFinal -PathType Leaf) { Remove-Item -LiteralPath $candidateReservation -Force -ErrorAction SilentlyContinue; continue }
      $reservation = $candidateReservation
      $final = $candidateFinal
      break
    } catch [IO.IOException] { continue }
  }
  if ([string]::IsNullOrWhiteSpace($final)) { throw 'hook_inbox_capacity' }
  $temporary = Join-Path $Directory ('.pending-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    [IO.File]::Move($temporary, $final)
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    if ($reservation) { Remove-Item -LiteralPath $reservation -Force -ErrorAction SilentlyContinue }
  }
}

try {
  $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false, $true), $true, 4096, $false)
  try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
  if ([string]::IsNullOrWhiteSpace($raw)) { throw 'hook_input_empty' }
  if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
  if ([Text.Encoding]::UTF8.GetByteCount($raw) -gt $script:HookInputByteLimit) { throw 'hook_input_oversize' }
  Assert-StrictJson $raw
  $data = $raw | ConvertFrom-Json -ErrorAction Stop
  if ($data.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { throw 'hook_shape_invalid' }
  $record = New-HookRecord $data ([DateTimeOffset]::UtcNow)
  Write-HookRecord (Resolve-HookInboxDirectory) $record
} catch {
  # Lifecycle hints are optional acceleration. The Governor's complete host
  # inventory remains authoritative when a bounded hook cannot persist a hint.
}
exit 0
