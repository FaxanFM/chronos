param(
  [ValidateSet('hook', 'status', 'initialize', 'confirm-active', 'reconcile-host', 'discover', 'cycle', 'release')]
  [string]$Action = 'status',
  [string]$StatePath,
  [string]$CodexHome,
  [string]$HostInventoryPath,
  [string]$SessionId = $env:CODEX_THREAD_ID,
  [string]$SubjectId,
  [string]$ObservedAtUtc,
  [ValidateRange(0, [long]::MaxValue)]
  [long]$SinceRevision = 0,
  [switch]$ConfirmRecurrenceStopped,
  [switch]$Diagnostic,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:StateByteLimit = 262144
$script:HookInputByteLimit = 65536
$script:SessionLimit = 256
$script:ResultLimit = 64
$script:CheckBatchLimit = 8
$script:EndedRetentionHours = 24
$script:ActiveRetentionDays = 30
$script:JsonNodeLimit = 8192
$script:PendingEventLimit = 256
$script:PendingEventReceiptLimit = $script:PendingEventLimit * 3
$script:PendingEventByteLimit = 4096
$script:PendingEventWriteAttemptLimit = 2
$script:PendingEventRetryDelayMilliseconds = 10
$script:SynchronousHookMutexWaitMilliseconds = 250
$script:AsynchronousHookMutexWaitMilliseconds = 100
$script:GovernorActiveCadenceMinutes = 60
$script:GovernorIdleCadenceMinutes = 360
$script:GovernorMaximumCycles = 336
$script:GovernorMaximumAgeDays = 14
$script:GovernorEquivalencePrefix = 'chronos-supervision-v1'
$script:HostEquivalenceKey = $script:GovernorEquivalencePrefix
$script:HostReconcileAttemptLimit = 3
$script:HostRecheckThroughCycle = 2
$script:Entropy = [Text.Encoding]::UTF8.GetBytes('Chronos.Supervision.Registry.v1')
$script:InvocationObservedAtUtc = [DateTimeOffset]::UtcNow
$script:HostInventoryByteLimit = 131072
$script:StateStoreMode = 'unknown'
$script:StateStoreMigration = 'not_applicable'
$script:StateStoreWriteReady = $false
$script:StateStoreProtection = 'dpapi_ids'
$script:LegacyDefaultStatePath = $null
$script:LegacyInstallationScopePath = $null
$script:PriorDefaultStatePath = $null
$script:PriorInstallationScopePath = $null
$script:PriorV2DefaultStatePath = $null
$script:PriorV2InstallationScopePath = $null
$script:AllowUnscopedLegacyMigration = $false
$script:PriorStateDisposition = 'not_checked'
$script:PriorStateWriteAttempted = $false
$script:PriorMigrationBlocked = $false
$script:DefaultStateCandidates = @()
$script:DefaultInstallationScopeId = $null
$script:RecoveredV3InstallationScopeId = $null
$script:InstallationScopeSource = 'unresolved'
$script:StateStoreSlot = -1
$script:StateStoreRecovery = 'not_applicable'
$script:StateStoreIdentity = 'unresolved'
$script:CodexHomeSource = 'unresolved'
$script:CodexHomeIdentity = 'unresolved'
$script:RegistryMutexIdentity = 'unresolved'
$script:HookInboxDirectory = $null

function Get-Value {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  if ($Object -is [Collections.IDictionary]) {
    if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
    return $Default
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function ConvertTo-Hashtable {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [Collections.IDictionary]) {
    $copy = @{}
    foreach ($key in $Value.Keys) { $copy[[string]$key] = ConvertTo-Hashtable $Value[$key] }
    return $copy
  }
  if ($Value.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
    $copy = @{}
    foreach ($property in $Value.PSObject.Properties) { $copy[$property.Name] = ConvertTo-Hashtable $property.Value }
    return $copy
  }
  if ($Value -is [Collections.IEnumerable] -and -not ($Value -is [string])) {
    return ,@($Value | ForEach-Object { ConvertTo-Hashtable $_ })
  }
  return $Value
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
      try {
        $decoded = $Text.Substring($start, $Index.Value - $start) | ConvertFrom-Json -ErrorAction Stop
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
  if ($Depth -gt 16) { throw $ErrorCode }
  Move-JsonWhitespace $Text $Index
  if ($Index.Value -ge $Text.Length) { throw $ErrorCode }
  $NodeCount.Value++
  if ($NodeCount.Value -gt $script:JsonNodeLimit) { throw $ErrorCode }
  $character = $Text[$Index.Value]
  if ($character -eq '"') { [void](Read-StrictJsonString $Text $Index $ErrorCode); return }
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

function Test-IsInteger {
  param($Value)
  return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
    $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
    $Value -is [int64] -or $Value -is [uint64])
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

function Get-BytesHash {
  param([byte[]]$Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($Value))).Replace('-', '').ToLowerInvariant()
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
  if ($full.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
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

function Test-PriorStoreUnavailableError {
  param($Record)
  if ($null -eq $Record) { return $false }
  if ($Record.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::PermissionDenied) { return $true }
  $exception = $Record.Exception
  while ($exception) {
    if ($exception -is [UnauthorizedAccessException] -or $exception -is [IO.IOException]) { return $true }
    $exception = $exception.InnerException
  }
  return $false
}

function Resolve-CodexHomeDirectory {
  param([string]$Requested)
  $hasRequested = -not [string]::IsNullOrWhiteSpace($Requested)
  $hasEnvironment = -not [string]::IsNullOrWhiteSpace([string]$env:CODEX_HOME)
  $source = if ($hasRequested) { 'explicit' } elseif ($hasEnvironment) { 'environment' } else { 'default' }
  $candidate = if ($hasRequested) { $Requested } elseif ($hasEnvironment) { [string]$env:CODEX_HOME } else { Join-Path $HOME '.codex' }
  try {
    $full = [IO.Path]::GetFullPath($candidate)
    if ($source -ne 'default') {
      $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
      if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'supervision_codex_home_invalid'
      }
      $full = [IO.Path]::GetFullPath($item.FullName)
    }
    if (-not (Test-NoReparseAncestors $full)) { throw 'supervision_codex_home_invalid' }
  } catch {
    if ([string]$_.Exception.Message -eq 'supervision_codex_home_invalid') { throw }
    if (Test-PriorStoreUnavailableError $_) { throw 'supervision_codex_home_unavailable' }
    throw 'supervision_codex_home_invalid'
  }
  $full = $full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  if ([string]::IsNullOrWhiteSpace($full)) { throw 'supervision_codex_home_invalid' }
  return [pscustomobject]@{
    Path = $full
    Identity = $full.ToUpperInvariant()
    Source = $source
  }
}

function Resolve-StatePath {
  param([string]$Requested)
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'supervision_state_path_invalid' }
  $localRoot = [IO.Path]::GetFullPath((Join-Path $localAppData 'Chronos\Supervision'))
  $priorTempRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot 'Chronos\Supervision'))
  $privateTempRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot 'Chronos\Supervision-v2'))
  $resolvedCodexHome = Resolve-CodexHomeDirectory $CodexHome
  $codexHome = [string]$resolvedCodexHome.Path
  $codexHomeIdentity = [string]$resolvedCodexHome.Identity
  $script:CodexHomeSource = [string]$resolvedCodexHome.Source
  $script:CodexHomeIdentity = (Get-TextHash $codexHomeIdentity).Substring(0, 16)
  # Pre-CODEX_HOME state is globally scoped. Only an invocation using the true
  # default home may import it; custom homes always start with isolated identity.
  $script:AllowUnscopedLegacyMigration = $script:CodexHomeSource -eq 'default'
  $scopeHash = Get-TextHash ('{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), $codexHomeIdentity)
  $priorScopeHash = Get-TextHash ('{0}|{1}' -f $env:COMPUTERNAME, $codexHome)
  $script:DefaultInstallationScopeId = (Get-TextHash ('Chronos.Supervision.Installation.v3|{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), $codexHomeIdentity)).Substring(0, 32)
  $script:HookInboxDirectory = [IO.Path]::GetFullPath((Join-Path $tempRoot ('Chronos-Supervision-Inbox-v1-{0}' -f $scopeHash.Substring(0, 24))))
  if (-not (Test-ContainedPath $script:HookInboxDirectory $tempRoot) -or -not (Test-NoReparseAncestors $script:HookInboxDirectory)) {
    throw 'supervision_pending_event_path_invalid'
  }
  $script:DefaultStateCandidates = @(0..3 | ForEach-Object {
    $slotRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot ('Chronos-Supervision-v3-{0}-{1}' -f $scopeHash.Substring(0, 24), $_)))
    Join-Path $slotRoot 'session-registry.json'
  })
  $script:LegacyDefaultStatePath = Join-Path $localRoot 'session-registry.json'
  $script:LegacyInstallationScopePath = Join-Path $localRoot 'installation-scope.json'
  $script:PriorDefaultStatePath = Join-Path $priorTempRoot 'session-registry.json'
  $script:PriorInstallationScopePath = Join-Path $priorTempRoot 'installation-scope.json'
  $script:PriorV2DefaultStatePath = Join-Path $privateTempRoot (Join-Path $priorScopeHash 'session-registry.json')
  $script:PriorV2InstallationScopePath = Join-Path $privateTempRoot (Join-Path $priorScopeHash 'installation-scope.json')
  $candidate = if ([string]::IsNullOrWhiteSpace($Requested)) {
    $script:StateStoreMode = 'temp_private'
    $script:StateStoreMigration = 'namespace_v3_new_root'
    $script:StateStoreRecovery = 'bounded_default_slot_selection'
    $script:DefaultStateCandidates[0]
  } else {
    $script:StateStoreMode = 'explicit'
    try { [IO.Path]::GetFullPath($Requested) } catch { throw 'supervision_state_path_invalid' }
  }
  $defaultContained = @($script:DefaultStateCandidates | Where-Object {
    [IO.Path]::GetFullPath($_).Equals([IO.Path]::GetFullPath($candidate), [StringComparison]::OrdinalIgnoreCase)
  }).Count -eq 1
  $contained = $defaultContained -or (Test-ContainedPath $candidate $localRoot) -or
    (Test-ContainedPath $candidate $priorTempRoot) -or
    (Test-ContainedPath $candidate $privateTempRoot)
  if ([IO.Path]::GetExtension($candidate) -ne '.json' -or -not $contained) {
    throw 'supervision_state_path_invalid'
  }
  if (-not (Test-NoReparseAncestors $candidate)) { throw 'supervision_state_path_invalid' }
  return [IO.Path]::GetFullPath($candidate)
}

function Initialize-StateStore {
  param([string]$ResolvedStatePath)
  [string[]]$candidates = if ($script:StateStoreMode -eq 'temp_private') { @($script:DefaultStateCandidates) } else { @([string]$ResolvedStatePath) }
  for ($slot = 0; $slot -lt $candidates.Count; $slot++) {
    $candidate = [IO.Path]::GetFullPath([string]$candidates[$slot])
    $directory = Split-Path -Parent $candidate
    $probe = $null
    try {
      if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
      }
      $item = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
      if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $directory)) {
        throw 'supervision_state_store_unwritable'
      }
      $probe = Join-Path $directory ('.supervision-probe-' + [guid]::NewGuid().ToString('N') + '.tmp')
      $stream = New-Object IO.FileStream($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      try { $stream.Flush($true) } finally { $stream.Dispose() }
      if ($script:StateStoreMode -eq 'temp_private') {
        # Default-slot selection happens before the registry mutex exists. It
        # must inspect prior state to recover from an inaccessible sandbox slot.
        foreach ($existingPath in @($candidate, (Join-Path $directory 'installation-scope.json'))) {
          if (-not (Test-Path -LiteralPath $existingPath -PathType Leaf)) { continue }
          $existingItem = Get-Item -LiteralPath $existingPath -Force -ErrorAction Stop
          if ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'supervision_state_store_unwritable' }
          $readProbe = New-Object IO.FileStream($existingPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
          $readProbe.Dispose()
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
          $existingState = Read-State $candidate -PreserveUnavailable
          try {
            Assert-StateProtectedIdentity $existingState
          } catch {
            if ([string]$_.Exception.Message -ne 'supervision_state_identity_unavailable') { throw }
            $scopePath = Join-Path $directory 'installation-scope.json'
            if ($null -eq $script:RecoveredV3InstallationScopeId -and (Test-Path -LiteralPath $scopePath -PathType Leaf)) {
              try { $script:RecoveredV3InstallationScopeId = Read-InstallationScopeId $scopePath } catch {}
            }
            throw
          }
        }
      }
      $script:StateStoreWriteReady = $true
      $script:StateStoreSlot = $slot
      if ($script:StateStoreMode -eq 'temp_private') {
        $script:StateStoreProtection = 'bounded_temp_slots_dpapi_ids'
        if ($slot -gt 0) { $script:StateStoreMigration = 'default_state_slot_recovered' }
      }
      return $candidate
    } catch {
      $failureCode = [string]$_.Exception.Message
      if ($script:StateStoreMode -ne 'temp_private') {
        if ($failureCode -in @('supervision_state_invalid', 'supervision_state_identity_unavailable')) { throw 'supervision_state_invalid' }
        throw 'supervision_state_store_unwritable'
      }
      if ($failureCode -eq 'supervision_state_invalid') { throw }
      if ($failureCode -ne 'supervision_state_identity_unavailable' -and
          $failureCode -ne 'supervision_state_store_unwritable' -and
          -not (Test-PriorStoreUnavailableError $_)) {
        throw 'supervision_state_store_unwritable'
      }
    } finally {
      if ($probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
    }
  }
  throw 'supervision_state_store_unwritable'
}

function Resolve-InstallationScopePath {
  param([string]$ResolvedStatePath)
  $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'supervision_install_scope_path_invalid' }
  $localRoot = [IO.Path]::GetFullPath((Join-Path $localAppData 'Chronos\Supervision'))
  $stateDirectory = Split-Path -Parent $ResolvedStatePath
  $candidate = if (Test-ContainedPath $ResolvedStatePath $localRoot) {
    Join-Path $localRoot 'installation-scope.json'
  } else {
    Join-Path $stateDirectory 'installation-scope.json'
  }
  if (-not (Test-NoReparseAncestors $candidate)) { throw 'supervision_install_scope_path_invalid' }
  return [IO.Path]::GetFullPath($candidate)
}

function Read-InstallationScopeId {
  param([string]$Path)
  try {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 256) { throw 'invalid' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $text = $utf8.GetString($bytes)
    Assert-StrictJson $text 'supervision_install_scope_invalid'
    $scope = ConvertTo-Hashtable ($text | ConvertFrom-Json -ErrorAction Stop)
    Assert-ExactKeys $scope @('schema', 'id')
    if (-not (Test-IsInteger $scope.schema) -or [int]$scope.schema -ne 1 -or [string]$scope.id -notmatch '^[a-f0-9]{32}$') { throw 'invalid' }
    return [string]$scope.id
  } catch {
    if ([string]$_.Exception.Message -eq 'supervision_install_scope_path_invalid') { throw }
    if (Test-PriorStoreUnavailableError $_) { throw }
    throw 'supervision_install_scope_invalid'
  }
}

function Write-InstallationScopeId {
  param([string]$Path, [string]$Id)
  if ($Id -notmatch '^[a-f0-9]{32}$') { throw 'supervision_install_scope_invalid' }
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  if (-not (Test-NoReparseAncestors $directory)) { throw 'supervision_install_scope_path_invalid' }
  $json = ([ordered]@{ schema = 1; id = $Id } | ConvertTo-Json -Compress)
  $temporary = Join-Path $directory ('.supervision-scope-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    try {
      [IO.File]::Move($temporary, $Path)
    } catch [IO.IOException] {
      if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'supervision_install_scope_unavailable' }
    }
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
  }
  return Read-InstallationScopeId $Path
}

function Get-OrCreateInstallationScopeId {
  param([string]$ResolvedStatePath)
  $path = Resolve-InstallationScopePath $ResolvedStatePath
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $script:InstallationScopeSource = if ($script:StateStoreMode -eq 'temp_private') { 'v3_anchor' } else { 'state_root_anchor' }
    return Read-InstallationScopeId $path
  }
  if ($script:StateStoreMode -eq 'temp_private') {
    if (-not [string]::IsNullOrWhiteSpace($script:RecoveredV3InstallationScopeId)) {
      $script:InstallationScopeSource = 'recovered_v3_anchor'
      return Write-InstallationScopeId $path $script:RecoveredV3InstallationScopeId
    }
    $priorScopePaths = @($script:PriorV2InstallationScopePath)
    if ($script:AllowUnscopedLegacyMigration) {
      $priorScopePaths += @($script:PriorInstallationScopePath, $script:LegacyInstallationScopePath)
    }
    foreach ($priorPath in $(if ($script:PriorMigrationBlocked) { @() } else { $priorScopePaths })) {
      if ([string]::IsNullOrWhiteSpace($priorPath)) { continue }
      try {
        $priorItem = Get-Item -LiteralPath $priorPath -Force -ErrorAction Stop
        if ($priorItem.PSIsContainer -or ($priorItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $priorPath)) {
          $script:StateStoreMigration = 'prior_state_invalid_new_root'
          $script:PriorStateDisposition = 'invalid_preserved'
          $script:PriorMigrationBlocked = $true
          break
        }
        $priorId = Read-InstallationScopeId $priorPath
        if ($script:StateStoreMigration -in @('namespace_v3_new_root', 'default_state_slot_recovered')) {
          $script:StateStoreMigration = 'prior_scope_imported'
        }
        $script:PriorStateDisposition = 'read_only_imported'
        $script:InstallationScopeSource = 'prior_anchor_imported'
        return Write-InstallationScopeId $path $priorId
      } catch {
        if (Test-PriorStoreUnavailableError $_) {
          $script:StateStoreMigration = 'prior_state_unavailable_new_root'
          $script:PriorStateDisposition = 'unavailable_preserved'
          $script:PriorMigrationBlocked = $true
          break
        }
        if ($_.CategoryInfo.Category -ne [Management.Automation.ErrorCategory]::ObjectNotFound) {
          $script:StateStoreMigration = 'prior_state_invalid_new_root'
          $script:PriorStateDisposition = 'invalid_preserved'
          $script:PriorMigrationBlocked = $true
          break
        }
      }
    }
    if ([string]::IsNullOrWhiteSpace($script:DefaultInstallationScopeId)) { throw 'supervision_install_scope_unavailable' }
    $script:InstallationScopeSource = 'deterministic_host_codex_home_hash'
    return Write-InstallationScopeId $path $script:DefaultInstallationScopeId
  }
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  if (-not (Test-NoReparseAncestors $directory)) { throw 'supervision_install_scope_path_invalid' }
  $random = New-Object byte[] 16
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($random) } finally { $rng.Dispose() }
  $id = ([BitConverter]::ToString($random)).Replace('-', '').ToLowerInvariant()
  $script:InstallationScopeSource = 'state_root_anchor'
  return Write-InstallationScopeId $path $id
}

function Normalize-OpaqueId {
  param($Value, [string]$ErrorCode = 'supervision_session_id_invalid')
  if (-not ($Value -is [string])) { throw $ErrorCode }
  $text = $Value.Trim()
  if ($text.Length -lt 1 -or $text.Length -gt 192 -or $text -notmatch '^[A-Za-z0-9._:/-]+$') { throw $ErrorCode }
  if ($text -match '^[A-Za-z]:[\\/]' -or $text -match '^\\' -or ($text.StartsWith('/') -and -not $text.StartsWith('/root/'))) {
    throw $ErrorCode
  }
  return $text
}

function Get-WorkspaceHash {
  param($Value)
  if (-not ($Value -is [string]) -or $Value.Length -lt 1 -or $Value.Length -gt 4096) {
    return Get-TextHash 'workspace-unavailable'
  }
  try {
    $normalized = [IO.Path]::GetFullPath($Value).TrimEnd([char[]]@('\\', '/')).ToUpperInvariant()
    return Get-TextHash $normalized
  } catch {
    return Get-TextHash 'workspace-unavailable'
  }
}

function Normalize-Model {
  param($Value)
  if ($Value -is [string]) {
    $text = $Value.Trim()
    if ($text.Length -ge 1 -and $text.Length -le 128 -and $text -match '^[A-Za-z0-9._:/-]+$') { return $text }
  }
  return 'unavailable'
}

function Protect-OpaqueId {
  param([string]$Value)
  try {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $protected = [Security.Cryptography.ProtectedData]::Protect(
      $bytes,
      $script:Entropy,
      [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($protected)
  } catch { throw 'supervision_crypto_unavailable' }
}

function Unprotect-OpaqueId {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 1024) { throw 'supervision_state_invalid' }
  try {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
      [Convert]::FromBase64String($Value),
      $script:Entropy,
      [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return Normalize-OpaqueId ([Text.Encoding]::UTF8.GetString($plain)) 'supervision_state_invalid'
  } catch {
    if ([string]$_.Exception.Message -eq 'supervision_state_invalid') { throw }
    throw 'supervision_state_invalid'
  }
}

function Test-ProtectedIdShape {
  param($Value)
  if (-not ($Value -is [string]) -or $Value.Length -lt 1 -or $Value.Length -gt 1024) { return $false }
  try {
    $bytes = [Convert]::FromBase64String($Value)
    return $bytes.Length -ge 32 -and $bytes.Length -le 768
  } catch { return $false }
}

function ConvertTo-UtcTimestamp {
  param($Value)
  if (-not ($Value -is [string]) -or $Value.Length -gt 40) { throw 'supervision_state_invalid' }
  $parsed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
    throw 'supervision_state_invalid'
  }
  return $parsed.ToUniversalTime()
}

function New-State {
  return [ordered]@{
    schema = 5
    revision = 0L
    governor = $null
    sessions = @{}
    health = [ordered]@{
      hookRuns = 0L
      droppedEntries = 0L
      ignoredStaleEvents = 0L
      scanOffset = 0L
      lastHookUtc = $null
      turnSignals = 0L
      duplicateSignals = 0L
      processedHookEvents = @()
    }
  }
}

function Upgrade-State {
  param($State)
  $schema = Get-Value $State 'schema' $null
  if ((Test-IsInteger $schema) -and [int]$schema -eq 2) {
    foreach ($record in @($State.sessions.Values)) {
      if (-not $record.Contains('generationHash')) { $record['generationHash'] = $null }
    }
    $State.schema = 3
  }
  if ((Test-IsInteger $State.schema) -and [int]$State.schema -eq 3) {
    if (-not $State.health.Contains('turnSignals')) { $State.health['turnSignals'] = 0L }
    if (-not $State.health.Contains('duplicateSignals')) { $State.health['duplicateSignals'] = 0L }
    foreach ($record in @($State.sessions.Values)) {
      if (-not $record.Contains('lastSignalHash')) { $record['lastSignalHash'] = $null }
      if (-not $record.Contains('turnSignals')) { $record['turnSignals'] = 0L }
    }
    $State.schema = 4
  }
  if ((Test-IsInteger $State.schema) -and [int]$State.schema -eq 4) {
    if (-not $State.health.Contains('processedHookEvents')) { $State.health['processedHookEvents'] = @() }
    $State.schema = 5
  }
  return $State
}

function Assert-ExactKeys {
  param($Record, [string[]]$Allowed)
  if (-not ($Record -is [Collections.IDictionary])) { throw 'supervision_state_invalid' }
  foreach ($key in $Record.Keys) {
    if ($Allowed -notcontains [string]$key) { throw 'supervision_state_invalid' }
  }
}

function Assert-StateProtectedIdentity {
  param($State)
  $protectedIds = [Collections.Generic.List[object]]::new()
  if ($null -ne $State.governor) {
    $protectedIds.Add([pscustomobject]@{ Hash = [string]$State.governor.idHash; ProtectedId = [string]$State.governor.protectedId }) | Out-Null
  }
  foreach ($key in @($State.sessions.Keys)) {
    $protectedIds.Add([pscustomobject]@{ Hash = [string]$key; ProtectedId = [string]$State.sessions[$key].protectedId }) | Out-Null
  }
  foreach ($entry in $protectedIds) {
    try { $plainId = Unprotect-OpaqueId $entry.ProtectedId } catch { throw 'supervision_state_identity_unavailable' }
    if ((Get-TextHash $plainId) -ne $entry.Hash) { throw 'supervision_state_invalid' }
  }
}

function Assert-State {
  param($State, [switch]$ValidateProtectedIds)
  Assert-ExactKeys $State @('schema', 'revision', 'governor', 'sessions', 'health')
  if (-not (Test-IsInteger $State.schema) -or [int]$State.schema -ne 5 -or
      -not (Test-IsInteger $State.revision) -or [long]$State.revision -lt 0 -or
      -not ($State.sessions -is [Collections.IDictionary]) -or
      -not ($State.health -is [Collections.IDictionary]) -or
      $State.sessions.Count -gt $script:SessionLimit) {
    throw 'supervision_state_invalid'
  }
  Assert-ExactKeys $State.health @('hookRuns', 'droppedEntries', 'ignoredStaleEvents', 'scanOffset', 'lastHookUtc', 'turnSignals', 'duplicateSignals', 'processedHookEvents')
  if (-not (Test-IsInteger $State.health.hookRuns) -or [long]$State.health.hookRuns -lt 0 -or
      -not (Test-IsInteger $State.health.droppedEntries) -or [long]$State.health.droppedEntries -lt 0 -or
      -not (Test-IsInteger $State.health.ignoredStaleEvents) -or [long]$State.health.ignoredStaleEvents -lt 0 -or
      -not (Test-IsInteger $State.health.scanOffset) -or [long]$State.health.scanOffset -lt 0 -or
      -not (Test-IsInteger $State.health.turnSignals) -or [long]$State.health.turnSignals -lt 0 -or
      -not (Test-IsInteger $State.health.duplicateSignals) -or [long]$State.health.duplicateSignals -lt 0) {
    throw 'supervision_state_invalid'
  }
  if (-not ($State.health.processedHookEvents -is [Collections.IEnumerable]) -or
      $State.health.processedHookEvents -is [string] -or
      @($State.health.processedHookEvents).Count -gt $script:PendingEventReceiptLimit) {
    throw 'supervision_state_invalid'
  }
  $processedHookEventSet = @{}
  foreach ($receipt in @($State.health.processedHookEvents)) {
    if (-not ($receipt -is [string]) -or [string]$receipt -notmatch '^[a-f0-9]{64}(\|[a-f0-9]{64})?$' -or $processedHookEventSet.ContainsKey([string]$receipt)) {
      throw 'supervision_state_invalid'
    }
    $processedHookEventSet[[string]$receipt] = $true
  }
  if ($null -ne $State.health.lastHookUtc) { [void](ConvertTo-UtcTimestamp $State.health.lastHookUtc) }
  if ($null -ne $State.governor) {
    Assert-ExactKeys $State.governor @('idHash', 'protectedId', 'claimedAtUtc', 'lastSeenUtc', 'cycleCount', 'idleCycles', 'lastCycleUtc')
    if ([string]$State.governor.idHash -notmatch '^[a-f0-9]{64}$') { throw 'supervision_state_invalid' }
    if (-not (Test-ProtectedIdShape $State.governor.protectedId)) { throw 'supervision_state_invalid' }
    [void](ConvertTo-UtcTimestamp $State.governor.claimedAtUtc)
    [void](ConvertTo-UtcTimestamp $State.governor.lastSeenUtc)
    if (-not (Test-IsInteger $State.governor.cycleCount) -or [long]$State.governor.cycleCount -lt 0 -or
        -not (Test-IsInteger $State.governor.idleCycles) -or [long]$State.governor.idleCycles -lt 0) { throw 'supervision_state_invalid' }
    if ($null -ne $State.governor.lastCycleUtc) { [void](ConvertTo-UtcTimestamp $State.governor.lastCycleUtc) }
  }
  foreach ($key in $State.sessions.Keys) {
    if ([string]$key -notmatch '^[a-f0-9]{64}$') { throw 'supervision_state_invalid' }
    $record = $State.sessions[$key]
    Assert-ExactKeys $record @('idHash', 'protectedId', 'kind', 'parentHash', 'workspaceHash', 'model', 'state', 'source', 'generationHash', 'firstSeenUtc', 'lastSeenUtc', 'endedAtUtc', 'lastEventUtc', 'lastEventRank', 'recordRevision', 'lastSignalHash', 'turnSignals')
    if ([string]$record.idHash -ne [string]$key -or -not (Test-ProtectedIdShape $record.protectedId)) { throw 'supervision_state_invalid' }
    if ([string]$record.kind -notin @('task', 'agent') -or [string]$record.state -notin @('active', 'ended')) { throw 'supervision_state_invalid' }
    if ($null -ne $record.parentHash -and [string]$record.parentHash -notmatch '^[a-f0-9]{64}$') { throw 'supervision_state_invalid' }
    if ($null -ne $record.generationHash -and [string]$record.generationHash -notmatch '^[a-f0-9]{64}$') { throw 'supervision_state_invalid' }
    if ($null -ne $record.lastSignalHash -and [string]$record.lastSignalHash -notmatch '^[a-f0-9]{64}$') { throw 'supervision_state_invalid' }
    if ([string]$record.workspaceHash -notmatch '^[a-f0-9]{64}$' -or [string]$record.model -notmatch '^[A-Za-z0-9._:/-]{1,128}$') { throw 'supervision_state_invalid' }
    if ([string]$record.source -notin @('startup', 'resume', 'clear', 'compact', 'subagent', 'fallback')) { throw 'supervision_state_invalid' }
    [void](ConvertTo-UtcTimestamp $record.firstSeenUtc)
    [void](ConvertTo-UtcTimestamp $record.lastSeenUtc)
    if ($null -ne $record.endedAtUtc) { [void](ConvertTo-UtcTimestamp $record.endedAtUtc) }
    [void](ConvertTo-UtcTimestamp $record.lastEventUtc)
    if (-not (Test-IsInteger $record.lastEventRank) -or [int]$record.lastEventRank -lt 1 -or [int]$record.lastEventRank -gt 3) { throw 'supervision_state_invalid' }
    if (-not (Test-IsInteger $record.recordRevision) -or [long]$record.recordRevision -lt 0 -or [long]$record.recordRevision -gt [long]$State.revision) { throw 'supervision_state_invalid' }
    if (-not (Test-IsInteger $record.turnSignals) -or [long]$record.turnSignals -lt 0) { throw 'supervision_state_invalid' }
  }
  if ($null -ne $State.governor -and -not $State.sessions.Contains([string]$State.governor.idHash)) { throw 'supervision_state_invalid' }
  if ($ValidateProtectedIds) { Assert-StateProtectedIdentity $State }
}

function Read-State {
  param([string]$Path, [switch]$ValidateProtectedIds, [switch]$PreserveUnavailable)
  if (-not (Test-Path -LiteralPath $Path)) { return New-State }
  try {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $script:StateByteLimit) { throw 'invalid' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $text = $utf8.GetString($bytes)
    Assert-StrictJson $text 'supervision_state_invalid'
    $state = Upgrade-State (ConvertTo-Hashtable ($text | ConvertFrom-Json -ErrorAction Stop))
    Assert-State $state -ValidateProtectedIds:$ValidateProtectedIds
    return $state
  } catch {
    if ($PreserveUnavailable -and (Test-PriorStoreUnavailableError $_)) { throw }
    throw 'supervision_state_invalid'
  }
}

function Write-State {
  param($State, [string]$Path, [switch]$TrustedHookMutation)
  # Hook state was fully validated immediately after the mutex was acquired and
  # can only be changed by the closed lifecycle mutation functions below.
  if (-not $TrustedHookMutation) { Assert-State $State }
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  if (-not (Test-NoReparseAncestors $directory)) { throw 'supervision_state_path_invalid' }
  $temporary = Join-Path $directory ('.supervision-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $backup = Join-Path $directory ('.supervision-' + [guid]::NewGuid().ToString('N') + '.bak')
  try {
    $json = $State | ConvertTo-Json -Compress -Depth 12
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    if ($bytes.Length -gt $script:StateByteLimit) { throw 'supervision_state_capacity' }
    # This registry is an advisory discovery cache that host liveness can rebuild.
    # Atomic replacement matters; forcing a physical flush for every lifecycle
    # hint only extends lock contention and increases disk work.
    $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
    if (-not $TrustedHookMutation) {
      [void]((Get-Content -Raw -LiteralPath $temporary) | ConvertFrom-Json -ErrorAction Stop)
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      [IO.File]::Replace($temporary, $Path, $backup, $true)
    } else {
      [IO.File]::Move($temporary, $Path)
    }
  } catch {
    if ([string]$_.Exception.Message -match '^supervision_(state_|pending_|install_)') { throw }
    throw 'supervision_state_store_unwritable'
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
  }
}

function Import-LegacyStateIfPresent {
  param([string]$ResolvedStatePath)
  if ($script:StateStoreMode -ne 'temp_private' -or (Test-Path -LiteralPath $ResolvedStatePath)) { return }
  $priorStatePaths = @($script:PriorV2DefaultStatePath)
  if ($script:AllowUnscopedLegacyMigration) {
    $priorStatePaths += @($script:PriorDefaultStatePath, $script:LegacyDefaultStatePath)
  }
  foreach ($priorPath in $priorStatePaths) {
    if ([string]::IsNullOrWhiteSpace($priorPath)) { continue }
    try {
      $priorItem = Get-Item -LiteralPath $priorPath -Force -ErrorAction Stop
      if ($priorItem.PSIsContainer -or ($priorItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $priorPath)) {
        $script:StateStoreMigration = 'prior_state_invalid_new_root'
        $script:PriorStateDisposition = 'invalid_preserved'
        $script:PriorMigrationBlocked = $true
        return
      }
      $legacy = Read-State $priorPath -ValidateProtectedIds -PreserveUnavailable
      Write-State $legacy $ResolvedStatePath
      $script:StateStoreMigration = 'prior_state_imported'
      $script:PriorStateDisposition = 'read_only_imported'
      return
    } catch {
      if (Test-PriorStoreUnavailableError $_) {
        $script:StateStoreMigration = 'prior_state_unavailable_new_root'
        $script:PriorStateDisposition = 'unavailable_preserved'
        $script:PriorMigrationBlocked = $true
        return
      }
      if ($_.CategoryInfo.Category -ne [Management.Automation.ErrorCategory]::ObjectNotFound) {
        $script:StateStoreMigration = 'prior_state_invalid_new_root'
        $script:PriorStateDisposition = 'invalid_preserved'
        $script:PriorMigrationBlocked = $true
        return
      }
    }
  }
}

function Get-PendingEventDirectory {
  param([string]$ResolvedStatePath)
  return $ResolvedStatePath + '.pending'
}

function New-PreparedHookEvent {
  param($HookData, [DateTimeOffset]$EventObservedAt)
  $event = [string](Get-Value $HookData 'hook_event_name' '')
  if ($event -notin @('SessionStart', 'SessionEnd', 'SubagentStart', 'SubagentStop', 'Stop')) { throw 'supervision_hook_event_invalid' }
  $session = Normalize-OpaqueId (Get-Value $HookData 'session_id')
  $agent = $null
  if ($event -in @('SubagentStart', 'SubagentStop')) {
    $agent = Normalize-OpaqueId (Get-Value $HookData 'agent_id') 'supervision_agent_id_invalid'
  }
  $source = if ($event -eq 'SessionStart') { [string](Get-Value $HookData 'source' 'startup') } elseif ($event -in @('SubagentStart', 'SubagentStop')) { 'subagent' } else { 'fallback' }
  if ($event -eq 'SessionStart' -and $source -notin @('startup', 'resume', 'clear', 'compact')) { throw 'supervision_hook_source_invalid' }
  return [ordered]@{
    schema = 2
    event = $event
    protectedSessionId = Protect-OpaqueId $session
    protectedAgentId = if ($null -ne $agent) { Protect-OpaqueId $agent } else { $null }
    workspaceHash = Get-WorkspaceHash (Get-Value $HookData 'cwd')
    model = Normalize-Model (Get-Value $HookData 'model')
    source = $source
    signalHash = if ($event -eq 'Stop') { Get-TextHash (Normalize-OpaqueId (Get-Value $HookData 'turn_id') 'supervision_turn_id_invalid') } else { $null }
    observedAtUtc = $EventObservedAt.ToString('o')
  }
}

function Assert-PendingHookEvent {
  param($Record)
  $schema = Get-Value $Record 'schema' $null
  if (-not (Test-IsInteger $schema) -or [int]$schema -notin @(1, 2)) { throw 'supervision_pending_event_invalid' }
  if ([int]$schema -eq 1) {
    Assert-ExactKeys $Record @('schema', 'event', 'protectedSessionId', 'protectedAgentId', 'workspaceHash', 'model', 'source', 'observedAtUtc')
  } else {
    Assert-ExactKeys $Record @('schema', 'event', 'protectedSessionId', 'protectedAgentId', 'workspaceHash', 'model', 'source', 'signalHash', 'observedAtUtc')
  }
  $allowedEvents = if ([int]$schema -eq 1) { @('SessionStart', 'SessionEnd', 'SubagentStart', 'SubagentStop') } else { @('SessionStart', 'SessionEnd', 'SubagentStart', 'SubagentStop', 'Stop') }
  if ([string]$Record.event -notin $allowedEvents -or
      -not (Test-ProtectedIdShape $Record.protectedSessionId) -or
      [string]$Record.workspaceHash -notmatch '^[a-f0-9]{64}$' -or
      [string]$Record.model -notmatch '^[A-Za-z0-9._:/-]{1,128}$' -or
      [string]$Record.source -notin @('startup', 'resume', 'clear', 'compact', 'subagent', 'fallback')) {
    throw 'supervision_pending_event_invalid'
  }
  if ([string]$Record.event -in @('SubagentStart', 'SubagentStop')) {
    if (-not (Test-ProtectedIdShape $Record.protectedAgentId)) { throw 'supervision_pending_event_invalid' }
  } elseif ($null -ne $Record.protectedAgentId) {
    throw 'supervision_pending_event_invalid'
  }
  if ([int]$schema -eq 2 -and [string]$Record.event -eq 'Stop') {
    if ([string]$Record.signalHash -notmatch '^[a-f0-9]{64}$') { throw 'supervision_pending_event_invalid' }
  } elseif ([int]$schema -eq 2 -and $null -ne $Record.signalHash) {
    throw 'supervision_pending_event_invalid'
  }
  [void](ConvertTo-UtcTimestamp $Record.observedAtUtc)
}

function Write-PendingHookEvent {
  param([string]$ResolvedStatePath, $PreparedEvent)
  Assert-PendingHookEvent $PreparedEvent
  $directory = Get-PendingEventDirectory $ResolvedStatePath
  if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
  $directoryItem = Get-Item -LiteralPath $directory -Force
  if (-not $directoryItem.PSIsContainer -or ($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $directory)) { throw 'supervision_pending_event_path_invalid' }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($PreparedEvent | ConvertTo-Json -Compress -Depth 4))
  if ($bytes.Length -gt $script:PendingEventByteLimit) { throw 'supervision_pending_event_capacity' }
  foreach ($staleReservation in @(Get-ChildItem -LiteralPath $directory -File -Force -Filter 'pending-slot-*.lock' | Select-Object -First $script:PendingEventLimit)) {
    if ($staleReservation.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddMinutes(-5)) {
      Remove-Item -LiteralPath $staleReservation.FullName -Force -ErrorAction SilentlyContinue
    }
  }
  $start = [int]([BitConverter]::ToUInt32(([guid]::NewGuid()).ToByteArray(), 0) % [uint32]$script:PendingEventLimit)
  $reservation = $null
  $final = $null
  for ($offset = 0; $offset -lt $script:PendingEventLimit; $offset++) {
    $slot = ($start + $offset) % $script:PendingEventLimit
    $candidateFinal = Join-Path $directory ('pending-slot-{0:d3}.json' -f $slot)
    $candidateReservation = Join-Path $directory ('pending-slot-{0:d3}.lock' -f $slot)
    if (Test-Path -LiteralPath $candidateFinal -PathType Leaf) { continue }
    try {
      $reserveStream = New-Object IO.FileStream($candidateReservation, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      $reserveStream.Dispose()
      if (Test-Path -LiteralPath $candidateFinal -PathType Leaf) {
        Remove-Item -LiteralPath $candidateReservation -Force -ErrorAction SilentlyContinue
        continue
      }
      $reservation = $candidateReservation
      $final = $candidateFinal
      break
    } catch [IO.IOException] { continue }
  }
  if ([string]::IsNullOrWhiteSpace($final)) { throw 'supervision_pending_event_capacity' }
  $temporary = Join-Path $directory ('.pending-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    [IO.File]::Move($temporary, $final)
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    if ($reservation) { Remove-Item -LiteralPath $reservation -Force -ErrorAction SilentlyContinue }
  }
}

function Write-PendingHookEventDurably {
  param([string]$ResolvedStatePath, $PreparedEvent)
  $lastError = $null
  for ($attempt = 1; $attempt -le $script:PendingEventWriteAttemptLimit; $attempt++) {
    try {
      Write-PendingHookEvent $ResolvedStatePath $PreparedEvent
      return
    } catch {
      $lastError = $_
      if ($attempt -lt $script:PendingEventWriteAttemptLimit) {
        [Threading.Thread]::Sleep($script:PendingEventRetryDelayMilliseconds)
      }
    }
  }
  if ($null -ne $lastError -and [string]$lastError.Exception.Message -match '^supervision_[a-z_]+$') {
    throw ([string]$lastError.Exception.Message)
  }
  throw 'supervision_pending_event_unwritable'
}

function Read-PendingHookEvents {
  param([string]$ResolvedStatePath)
  $result = [Collections.Generic.List[object]]::new()
  $files = [Collections.Generic.List[object]]::new()
  $presentPathHashes = [Collections.Generic.List[string]]::new()
  $directories = @((Get-PendingEventDirectory $ResolvedStatePath))
  if ($script:StateStoreMode -eq 'temp_private' -and -not [string]::IsNullOrWhiteSpace([string]$script:HookInboxDirectory)) {
    $directories += @([string]$script:HookInboxDirectory)
  }
  foreach ($directory in @($directories | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $directory)) { continue }
    $directoryItem = Get-Item -LiteralPath $directory -Force
    if (-not $directoryItem.PSIsContainer -or ($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $directory)) { throw 'supervision_pending_event_path_invalid' }
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Force -Filter 'pending-*.json' | Sort-Object Name)) {
      $pathHash = Get-TextHash ('pending-path|{0}' -f $file.FullName.ToUpperInvariant())
      $presentPathHashes.Add($pathHash) | Out-Null
      $files.Add([pscustomobject]@{ File = $file; PathHash = $pathHash }) | Out-Null
      if ($files.Count -gt $script:PendingEventReceiptLimit) { throw 'supervision_pending_event_capacity' }
    }
  }
  foreach ($candidate in @($files | Select-Object -First $script:PendingEventLimit)) {
      $file = $candidate.File
      $pathHash = [string]$candidate.PathHash
      $eventHash = Get-TextHash ('pending-invalid|{0}|{1}|{2}' -f $pathHash, $file.Length, $file.LastWriteTimeUtc.Ticks)
      try {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt $script:PendingEventByteLimit) { throw 'invalid' }
        try { $bytes = [IO.File]::ReadAllBytes($file.FullName) } catch {
          $result.Add([pscustomobject]@{ Path = $file.FullName; PathHash = $pathHash; EventHash = $null; Record = $null; SessionId = $null; AgentId = $null; ObservedAt = $null; Readable = $false; Valid = $false }) | Out-Null
          continue
        }
        $eventHash = Get-BytesHash $bytes
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        Assert-StrictJson $text 'supervision_pending_event_invalid'
        $record = ConvertTo-Hashtable ($text | ConvertFrom-Json -ErrorAction Stop)
        Assert-PendingHookEvent $record
        $session = Unprotect-OpaqueId $record.protectedSessionId
        $agent = $null
        if ([string]$record.event -in @('SubagentStart', 'SubagentStop')) { $agent = Unprotect-OpaqueId $record.protectedAgentId }
        $observedAt = ConvertTo-UtcTimestamp $record.observedAtUtc
        $result.Add([pscustomobject]@{
          Path = $file.FullName
          PathHash = $pathHash
          EventHash = $eventHash
          Record = $record
          SessionId = $session
          AgentId = $agent
          ObservedAt = $observedAt
          Readable = $true
          Valid = $true
        }) | Out-Null
      } catch {
        $result.Add([pscustomobject]@{ Path = $file.FullName; PathHash = $pathHash; EventHash = $eventHash; Record = $null; SessionId = $null; AgentId = $null; ObservedAt = $null; Readable = $true; Valid = $false }) | Out-Null
      }
  }
  return [pscustomobject]@{ Items = @($result); PresentPathHashes = @($presentPathHashes) }
}

function Merge-PendingHookEvents {
  param($State, [string]$ResolvedStatePath, [DateTimeOffset]$Now)
  $snapshot = Read-PendingHookEvents $ResolvedStatePath
  $items = @($snapshot.Items)
  $presentPathHashes = @{}
  foreach ($pathHash in @($snapshot.PresentPathHashes)) { $presentPathHashes[[string]$pathHash] = $true }
  $processedByPath = @{}
  $legacyEventHashes = @{}
  foreach ($receipt in @($State.health.processedHookEvents)) {
    $parts = @(([string]$receipt) -split '\|', 2)
    if ($parts.Count -eq 1) {
      if ($presentPathHashes.Count -gt 0) { $legacyEventHashes[[string]$parts[0]] = $true }
    } elseif ($presentPathHashes.ContainsKey([string]$parts[0])) {
      $processedByPath[[string]$parts[0]] = [string]$parts[1]
    }
  }

  $valid = @($items | Where-Object { $_.Readable -and $_.Valid } | Sort-Object ObservedAt, Path)
  foreach ($item in $valid) {
    $pathHash = [string]$item.PathHash
    $eventHash = [string]$item.EventHash
    if ($processedByPath.ContainsKey($pathHash) -and [string]$processedByPath[$pathHash] -eq $eventHash) { continue }
    if ($legacyEventHashes.ContainsKey($eventHash)) {
      $legacyEventHashes.Remove($eventHash)
      $processedByPath[$pathHash] = $eventHash
      continue
    }
    $record = $item.Record
    $hookData = @{
      hook_event_name = [string]$record.event
      session_id = [string]$item.SessionId
      model = [string]$record.model
      source = [string]$record.source
    }
    $preparedProtectedId = [string]$record.protectedSessionId
    if ([string]$record.event -in @('SubagentStart', 'SubagentStop')) {
      $hookData.agent_id = [string]$item.AgentId
      $preparedProtectedId = [string]$record.protectedAgentId
    }
    Invoke-HookEvent $State $hookData $Now $item.ObservedAt $preparedProtectedId ([string]$record.workspaceHash) ([string](Get-Value $record 'signalHash' ''))
    $processedByPath[$pathHash] = $eventHash
  }
  foreach ($item in @($items | Where-Object { $_.Readable -and -not $_.Valid })) {
    $pathHash = [string]$item.PathHash
    $eventHash = [string]$item.EventHash
    if ($processedByPath.ContainsKey($pathHash) -and [string]$processedByPath[$pathHash] -eq $eventHash) { continue }
    if ($legacyEventHashes.ContainsKey($eventHash)) {
      $legacyEventHashes.Remove($eventHash)
      $processedByPath[$pathHash] = $eventHash
      continue
    }
    $State.health.droppedEntries = [long]$State.health.droppedEntries + 1
    $processedByPath[$pathHash] = $eventHash
  }
  $processedReceipts = [Collections.Generic.List[string]]::new()
  foreach ($eventHash in @($legacyEventHashes.Keys | Sort-Object)) { $processedReceipts.Add([string]$eventHash) | Out-Null }
  foreach ($pathHash in @($processedByPath.Keys | Sort-Object)) {
    $processedReceipts.Add(('{0}|{1}' -f $pathHash, [string]$processedByPath[$pathHash])) | Out-Null
  }
  if ($processedReceipts.Count -gt $script:PendingEventReceiptLimit) { throw 'supervision_pending_event_capacity' }
  $State.health.processedHookEvents = @($processedReceipts)
  return @($items | Where-Object { $_.Readable })
}

function Remove-PendingHookEvents {
  param($Items, [string]$ResolvedStatePath)
  # Keep the empty parent directory. Fallback writers do not hold the registry
  # mutex, so deleting it here can race a writer between its path check and write.
  foreach ($item in @($Items)) {
    try { Remove-Item -LiteralPath ([string]$item.Path) -Force -ErrorAction Stop } catch {}
  }
}

function Read-HostInventory {
  param([string]$Path, [DateTimeOffset]$Now)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'supervision_host_inventory_required' }
  try { $full = [IO.Path]::GetFullPath($Path) } catch { throw 'supervision_host_inventory_invalid' }
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if ([IO.Path]::GetExtension($full) -ne '.json' -or -not (Test-ContainedPath $full $tempRoot) -or -not (Test-NoReparseAncestors $full)) {
    throw 'supervision_host_inventory_invalid'
  }
  try {
    $item = Get-Item -LiteralPath $full -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $script:HostInventoryByteLimit) { throw 'invalid' }
    $bytes = [IO.File]::ReadAllBytes($full)
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    Assert-StrictJson $text 'supervision_host_inventory_invalid'
    $inventory = ConvertTo-Hashtable ($text | ConvertFrom-Json -ErrorAction Stop)
    Assert-ExactKeys $inventory @('schemaVersion', 'capturedAtUtc', 'complete', 'callerVisibility', 'tasks')
    if (-not (Test-IsInteger $inventory.schemaVersion) -or [int]$inventory.schemaVersion -notin @(1, 2) -or -not ($inventory.complete -is [bool])) { throw 'invalid' }
    $schemaVersion = [int]$inventory.schemaVersion
    $callerVisibility = 'included'
    if ($schemaVersion -eq 1) {
      if ($inventory.Contains('callerVisibility')) { throw 'invalid' }
    } else {
      if (-not $inventory.Contains('callerVisibility') -or [string]$inventory.callerVisibility -notin @('included', 'excluded_by_host')) { throw 'invalid' }
      $callerVisibility = [string]$inventory.callerVisibility
    }
    $captured = ConvertTo-UtcTimestamp $inventory.capturedAtUtc
    if ($captured -gt $Now.AddMinutes(5) -or $captured -lt $Now.AddMinutes(-15)) { throw 'invalid' }
    $tasks = @($inventory.tasks)
    if ($tasks.Count -gt $script:SessionLimit) { throw 'invalid' }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $normalized = [Collections.Generic.List[object]]::new()
    $activeStates = @('active', 'running', 'waiting', 'blocked', 'needs_attention', 'pending', 'idle', 'ready')
    $endedStates = @('completed', 'failed', 'cancelled', 'archived', 'ended')
    foreach ($task in $tasks) {
      Assert-ExactKeys $task @('id', 'status', 'generation')
      $id = Normalize-OpaqueId (Get-Value $task 'id') 'supervision_host_inventory_invalid'
      if (-not $seen.Add($id)) { throw 'invalid' }
      $status = [string](Get-Value $task 'status' '')
      if ($status -notin @($activeStates + $endedStates)) { throw 'invalid' }
      $generation = $null
      if ($task.Contains('generation') -and $null -ne $task.generation) {
        $generation = Normalize-OpaqueId $task.generation 'supervision_host_inventory_invalid'
      }
      $normalized.Add([pscustomobject]@{
        Id = $id
        Active = ($status -in $activeStates)
        Status = if ($status -in $activeStates) { 'live' } else { 'ended' }
        Generation = $generation
      }) | Out-Null
    }
    return [pscustomobject]@{
      SchemaVersion = $schemaVersion
      CapturedAt = $captured
      Complete = [bool]$inventory.complete
      CallerVisibility = $callerVisibility
      RawObserved = $normalized.Count
      Tasks = @($normalized)
    }
  } catch {
    if ([string]$_.Exception.Message -match '^supervision_host_inventory_') { throw }
    throw 'supervision_host_inventory_invalid'
  }
}

function Complete-HostInventoryForGovernor {
  param($Inventory, [string]$CurrentGovernorId)
  $governorCount = @($Inventory.Tasks | Where-Object { [string]$_.Id -eq $CurrentGovernorId }).Count
  $tasks = @($Inventory.Tasks)
  $governorSource = 'inventory'
  if ([string]$Inventory.CallerVisibility -eq 'included') {
    if ($governorCount -ne 1) { throw 'supervision_governor_not_in_host_inventory' }
  } elseif ([string]$Inventory.CallerVisibility -eq 'excluded_by_host') {
    if ($governorCount -ne 0) { throw 'supervision_host_inventory_invalid' }
    $tasks += [pscustomobject]@{
      Id = $CurrentGovernorId
      Active = $true
      Status = 'live'
      Generation = $null
    }
    $governorSource = 'intrinsic_cycle_caller'
  } else {
    throw 'supervision_host_inventory_invalid'
  }
  return [pscustomobject]@{
    SchemaVersion = [int]$Inventory.SchemaVersion
    CapturedAt = $Inventory.CapturedAt
    Complete = [bool]$Inventory.Complete
    CallerVisibility = [string]$Inventory.CallerVisibility
    GovernorSource = $governorSource
    RawObserved = [int]$Inventory.RawObserved
    Tasks = @($tasks)
  }
}

function Invoke-HostInventoryReconciliation {
  param($State, $Inventory, [string]$CurrentGovernorId, [DateTimeOffset]$Now)
  $currentHash = Get-TextHash $CurrentGovernorId
  if ($null -eq $State.governor -or [string]$State.governor.idHash -ne $currentHash) { throw 'supervision_governor_mismatch' }
  $present = @{}
  $added = 0
  $reactivated = 0
  $generationChanged = 0
  $ended = 0
  foreach ($task in @($Inventory.Tasks)) {
    $hash = Get-TextHash ([string]$task.Id)
    $generationHash = if ([string]::IsNullOrWhiteSpace([string]$task.Generation)) { $null } else { Get-TextHash ([string]$task.Generation) }
    $present[$hash] = $true
    $existing = if ($State.sessions.Contains($hash)) { $State.sessions[$hash] } else { $null }
    if ([bool]$task.Active) {
      if ($null -eq $existing) {
        if (Set-SessionRecord $State ([string]$task.Id) 'task' $null (Get-TextHash 'workspace-unavailable') 'unavailable' 'active' 'fallback' $Now $Inventory.CapturedAt 3 -GenerationHash $generationHash -AllowReactivation) { $added++ }
      } elseif ([string]$existing.state -eq 'ended') {
        if (Set-SessionRecord $State ([string]$task.Id) 'task' $null ([string]$existing.workspaceHash) ([string]$existing.model) 'active' ([string]$existing.source) $Now $Inventory.CapturedAt 3 -GenerationHash $generationHash -AllowReactivation) { $reactivated++ }
      } else {
        $priorGeneration = [string](Get-Value $existing 'generationHash' '')
        if (Set-SessionRecord $State ([string]$task.Id) 'task' $null ([string]$existing.workspaceHash) ([string]$existing.model) 'active' ([string]$existing.source) $Now $Inventory.CapturedAt 3 -GenerationHash $generationHash -AllowReactivation) {
          if ($generationHash -and $priorGeneration -and $generationHash -ne $priorGeneration) { $generationChanged++ }
        }
      }
    } elseif ($null -ne $existing -and [string]$existing.state -eq 'active' -and $hash -ne $currentHash) {
      [void](Set-RecordEndedByHash $State $hash $Now $Inventory.CapturedAt $generationHash)
      if ([string]$State.sessions[$hash].state -eq 'ended') { $ended++ }
    }
  }
  if ([bool]$Inventory.Complete) {
    foreach ($hash in @($State.sessions.Keys)) {
      $record = $State.sessions[$hash]
      if ([string]$record.kind -ne 'task' -or [string]$record.state -ne 'active' -or $hash -eq $currentHash -or $present.ContainsKey($hash)) { continue }
      [void](Set-RecordEndedByHash $State ([string]$hash) $Now $Inventory.CapturedAt)
      if ([string]$State.sessions[$hash].state -eq 'ended') { $ended++ }
    }
  }
  return [pscustomobject]@{ Added = $added; Reactivated = $reactivated; GenerationChanged = $generationChanged; Ended = $ended; Observed = @($Inventory.Tasks).Count; Complete = [bool]$Inventory.Complete }
}

function Get-CompactHostTaskStatuses {
  param($Inventory)
  @($Inventory.Tasks | ForEach-Object {
    [ordered]@{
      idHash = (Get-TextHash ([string]$_.Id)).Substring(0, 16)
      status = [string]$_.Status
      generation = if ([string]::IsNullOrWhiteSpace([string]$_.Generation)) { 'unavailable' } else { 'observed' }
    }
  })
}

function New-RegistryMutex {
  param([string]$Path)
  $pathHash = Get-TextHash ([IO.Path]::GetFullPath($Path).ToUpperInvariant())
  $script:RegistryMutexIdentity = $pathHash.Substring(0, 16)
  $suffix = 'ChronosSupervision-' + $pathHash.Substring(0, 24)
  $sid = $null
  $security = $null
  try {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security = New-Object Security.AccessControl.MutexSecurity
    $rule = New-Object Security.AccessControl.MutexAccessRule($sid, [Security.AccessControl.MutexRights]::FullControl, [Security.AccessControl.AccessControlType]::Allow)
    $security.AddAccessRule($rule)
  } catch { throw 'supervision_mutex_unavailable' }
  try {
    $created = $false
    return New-Object Threading.Mutex($false, ('Global\' + $suffix), [ref]$created, $security)
  } catch { throw 'supervision_mutex_unavailable' }
}

function Remove-ExpiredRecords {
  param($State, [DateTimeOffset]$Now)
  $remove = [Collections.Generic.List[string]]::new()
  foreach ($key in @($State.sessions.Keys)) {
    if ($null -ne $State.governor -and [string]$State.governor.idHash -eq [string]$key) { continue }
    $record = $State.sessions[$key]
    $lastSeen = ConvertTo-UtcTimestamp $record.lastSeenUtc
    if (($record.state -eq 'ended' -and ($Now - $lastSeen).TotalHours -ge $script:EndedRetentionHours) -or
        ($record.state -eq 'active' -and ($Now - $lastSeen).TotalDays -ge $script:ActiveRetentionDays)) {
      $remove.Add([string]$key) | Out-Null
    }
  }
  foreach ($key in $remove) { $State.sessions.Remove($key) }
}

function Set-RecordEndedByHash {
  param($State, [string]$Hash, [DateTimeOffset]$Now, [DateTimeOffset]$EventObservedAt, [string]$GenerationHash)
  if (-not $State.sessions.Contains($Hash)) { return $false }
  $record = $State.sessions[$Hash]
  if ($record.state -eq 'ended') { return $true }
  if ($GenerationHash -and $record.generationHash -and [string]$record.generationHash -ne $GenerationHash) {
    $State.health.ignoredStaleEvents = [long]$State.health.ignoredStaleEvents + 1
    return $false
  }
  $lastEvent = ConvertTo-UtcTimestamp $record.lastEventUtc
  if ($EventObservedAt -lt $lastEvent -or ($EventObservedAt -eq $lastEvent -and 2 -le [int]$record.lastEventRank)) {
    $State.health.ignoredStaleEvents = [long]$State.health.ignoredStaleEvents + 1
    return $false
  }
  $State.revision = [long]$State.revision + 1
  $record.state = 'ended'
  $record.lastSeenUtc = $Now.ToString('o')
  $record.endedAtUtc = $Now.ToString('o')
  $record.lastEventUtc = $EventObservedAt.ToString('o')
  $record.lastEventRank = 2
  $record.recordRevision = [long]$State.revision
  return $true
}

function Set-SessionRecord {
  param(
    $State,
    [string]$Id,
    [string]$Kind,
    [string]$ParentHash,
    [string]$WorkspaceHash,
    [string]$Model,
    [string]$LifecycleState,
    [string]$Source,
    [DateTimeOffset]$Now,
    [DateTimeOffset]$EventObservedAt,
    [ValidateRange(1, 3)][int]$EventRank,
    [string]$PreparedProtectedId,
    [string]$GenerationHash,
    [switch]$AllowReactivation
  )
  $hash = Get-TextHash $Id
  $existing = if ($State.sessions.Contains($hash)) { $State.sessions[$hash] } else { $null }
  if ($null -ne $existing) {
    $lastEvent = ConvertTo-UtcTimestamp $existing.lastEventUtc
    if ($EventObservedAt -lt $lastEvent -or
        ($EventObservedAt -eq $lastEvent -and $EventRank -le [int]$existing.lastEventRank) -or
        ($existing.state -eq 'ended' -and $LifecycleState -eq 'active' -and -not $AllowReactivation)) {
      $State.health.ignoredStaleEvents = [long]$State.health.ignoredStaleEvents + 1
      return $false
    }
  }
  if ($null -eq $existing -and $State.sessions.Count -ge $script:SessionLimit) {
    Remove-ExpiredRecords $State $Now
    if ($State.sessions.Count -ge $script:SessionLimit) {
      $State.health.droppedEntries = [long]$State.health.droppedEntries + 1
      return $false
    }
  }
  $State.revision = [long]$State.revision + 1
  $firstSeen = if ($null -ne $existing) { [string]$existing.firstSeenUtc } else { $Now.ToString('o') }
  $State.sessions[$hash] = [ordered]@{
    idHash = $hash
    protectedId = if ($null -ne $existing) {
      [string]$existing.protectedId
    } elseif (-not [string]::IsNullOrWhiteSpace($PreparedProtectedId)) {
      $PreparedProtectedId
    } else {
      Protect-OpaqueId $Id
    }
    kind = $Kind
    parentHash = if ([string]::IsNullOrWhiteSpace($ParentHash)) { $null } else { $ParentHash }
    workspaceHash = $WorkspaceHash
    model = $Model
    state = $LifecycleState
    source = $Source
    generationHash = if (-not [string]::IsNullOrWhiteSpace($GenerationHash)) { $GenerationHash } elseif ($existing) { $existing.generationHash } else { $null }
    firstSeenUtc = $firstSeen
    lastSeenUtc = $Now.ToString('o')
    endedAtUtc = if ($LifecycleState -eq 'ended') { $Now.ToString('o') } else { $null }
    lastEventUtc = $EventObservedAt.ToString('o')
    lastEventRank = $EventRank
    recordRevision = [long]$State.revision
    lastSignalHash = if ($existing) { $existing.lastSignalHash } else { $null }
    turnSignals = if ($existing) { [long]$existing.turnSignals } else { 0L }
  }
  if ($null -ne $State.governor -and [string]$State.governor.idHash -eq $hash) {
    $State.governor.lastSeenUtc = $Now.ToString('o')
  }
  return $true
}

function Invoke-HookEvent {
  param($State, $HookData, [DateTimeOffset]$Now, [DateTimeOffset]$EventObservedAt, [string]$PreparedProtectedId, [string]$PreparedWorkspaceHash, [string]$PreparedSignalHash)
  $event = [string](Get-Value $HookData 'hook_event_name' '')
  if ($event -notin @('SessionStart', 'SessionEnd', 'SubagentStart', 'SubagentStop', 'Stop')) { throw 'supervision_hook_event_invalid' }
  $session = Normalize-OpaqueId (Get-Value $HookData 'session_id')
  $workspaceHash = if ([string]$PreparedWorkspaceHash -match '^[a-f0-9]{64}$') { $PreparedWorkspaceHash } else { Get-WorkspaceHash (Get-Value $HookData 'cwd') }
  $model = Normalize-Model (Get-Value $HookData 'model')
  switch ($event) {
    'SessionStart' {
      $source = [string](Get-Value $HookData 'source' 'startup')
      if ($source -notin @('startup', 'resume', 'clear', 'compact')) { throw 'supervision_hook_source_invalid' }
      [void](Set-SessionRecord $State $session 'task' $null $workspaceHash $model 'active' $source $Now $EventObservedAt 1 $PreparedProtectedId)
    }
    'SessionEnd' {
      $hash = Get-TextHash $session
      $source = if ($State.sessions.Contains($hash)) { [string]$State.sessions[$hash].source } else { 'fallback' }
      $sessionEnded = Set-SessionRecord $State $session 'task' $null $workspaceHash $model 'ended' $source $Now $EventObservedAt 2 $PreparedProtectedId
      if ($sessionEnded) {
        foreach ($key in @($State.sessions.Keys)) {
          $record = $State.sessions[$key]
          if ($record.kind -eq 'agent' -and $record.parentHash -eq $hash -and $record.state -eq 'active') {
            Set-RecordEndedByHash $State ([string]$key) $Now $EventObservedAt
          }
        }
      }
    }
    'SubagentStart' {
      $agent = Normalize-OpaqueId (Get-Value $HookData 'agent_id') 'supervision_agent_id_invalid'
      $parentHash = Get-TextHash $session
      $parentEnded = $State.sessions.Contains($parentHash) -and [string]$State.sessions[$parentHash].state -eq 'ended'
      $agentHash = Get-TextHash $agent
      if (-not $parentEnded) {
        [void](Set-SessionRecord $State $agent 'agent' $parentHash $workspaceHash $model 'active' 'subagent' $Now $EventObservedAt 1 $PreparedProtectedId)
      } elseif ($State.sessions.Contains($agentHash) -and [string]$State.sessions[$agentHash].state -eq 'ended') {
        # Reapply the delayed start as active so the terminal-state guard records
        # it as stale without rewriting the existing tombstone.
        [void](Set-SessionRecord $State $agent 'agent' $parentHash $workspaceHash $model 'active' 'subagent' $Now $EventObservedAt 1 $PreparedProtectedId)
      } else {
        [void](Set-SessionRecord $State $agent 'agent' $parentHash $workspaceHash $model 'ended' 'subagent' $Now $EventObservedAt 2 $PreparedProtectedId)
      }
    }
    'SubagentStop' {
      $agent = Normalize-OpaqueId (Get-Value $HookData 'agent_id') 'supervision_agent_id_invalid'
      $hash = Get-TextHash $agent
      $record = if ($State.sessions.Contains($hash)) { $State.sessions[$hash] } else { $null }
      $recordWorkspaceHash = if ($record) { [string]$record.workspaceHash } else { $workspaceHash }
      $recordModel = if ($record) { [string]$record.model } else { $model }
      [void](Set-SessionRecord $State $agent 'agent' (Get-TextHash $session) $recordWorkspaceHash $recordModel 'ended' 'subagent' $Now $EventObservedAt 2 $PreparedProtectedId)
    }
    'Stop' {
      $signalHash = if ($PreparedSignalHash -match '^[a-f0-9]{64}$') {
        $PreparedSignalHash
      } else {
        Get-TextHash (Normalize-OpaqueId (Get-Value $HookData 'turn_id') 'supervision_turn_id_invalid')
      }
      $hash = Get-TextHash $session
      if ($State.sessions.Contains($hash) -and [string]$State.sessions[$hash].lastSignalHash -eq $signalHash) {
        $State.health.duplicateSignals = [long]$State.health.duplicateSignals + 1
      } else {
        $existing = if ($State.sessions.Contains($hash)) { $State.sessions[$hash] } else { $null }
        $source = if ($existing) { [string]$existing.source } else { 'fallback' }
        $updated = Set-SessionRecord $State $session 'task' $null $workspaceHash $model 'active' $source $Now $EventObservedAt 3 $PreparedProtectedId
        if ($updated) {
          $State.sessions[$hash].lastSignalHash = $signalHash
          $State.sessions[$hash].turnSignals = [long]$State.sessions[$hash].turnSignals + 1
          $State.health.turnSignals = [long]$State.health.turnSignals + 1
        }
      }
    }
  }
  $State.health.hookRuns = [long]$State.health.hookRuns + 1
  $State.health.lastHookUtc = $Now.ToString('o')
  Remove-ExpiredRecords $State $Now
}

function Get-DiscoveryPayload {
  param($State, [string]$RequestedAction, [string]$CurrentSession, [long]$Cursor, [DateTimeOffset]$Now)
  $governorId = $null
  if ($null -ne $State.governor) { $governorId = Unprotect-OpaqueId $State.governor.protectedId }
  $currentHash = if ([string]::IsNullOrWhiteSpace($CurrentSession)) { $null } else { Get-TextHash (Normalize-OpaqueId $CurrentSession) }
  $activeTasks = [Collections.Generic.List[object]]::new()
  $activeAgents = [Collections.Generic.List[object]]::new()
  $allActive = [Collections.Generic.List[object]]::new()
  $changes = [Collections.Generic.List[object]]::new()
  $governorHash = if ($null -ne $State.governor) { [string]$State.governor.idHash } else { $null }
  foreach ($key in @($State.sessions.Keys | Sort-Object)) {
    $record = $State.sessions[$key]
    $rawId = Unprotect-OpaqueId $record.protectedId
    $summary = [ordered]@{
      taskId = $rawId
      idHash = ([string]$record.idHash).Substring(0, 16)
      kind = [string]$record.kind
      state = [string]$record.state
      workspaceHash = ([string]$record.workspaceHash).Substring(0, 16)
      model = [string]$record.model
      lastSeenUtc = [string]$record.lastSeenUtc
      turnSignals = [long]$record.turnSignals
      liveness = if ($record.state -eq 'ended') { 'ended' } elseif (($Now - (ConvertTo-UtcTimestamp $record.lastSeenUtc)).TotalHours -le 2) { 'recent' } else { 'host_verification_required' }
      recordRevision = [long]$record.recordRevision
    }
    if ([long]$record.recordRevision -gt $Cursor -and $changes.Count -lt $script:ResultLimit) { $changes.Add($summary) | Out-Null }
    if ($record.state -ne 'active' -or [string]$record.idHash -eq $governorHash) { continue }
    $allActive.Add($summary) | Out-Null
    if ($record.kind -eq 'task' -and $activeTasks.Count -lt $script:ResultLimit) { $activeTasks.Add($summary) | Out-Null }
    if ($record.kind -eq 'agent' -and $activeAgents.Count -lt $script:ResultLimit) { $activeAgents.Add($summary) | Out-Null }
  }
  $activeCount = $allActive.Count
  $batch = [Collections.Generic.List[object]]::new()
  $batchOffset = if ($activeCount -gt 0) { [int]([long]$State.health.scanOffset % $activeCount) } else { 0 }
  $batchCount = [Math]::Min($script:CheckBatchLimit, $activeCount)
  for ($index = 0; $index -lt $batchCount; $index++) {
    $batch.Add($allActive[($batchOffset + $index) % $activeCount]) | Out-Null
  }
  $nextBatchOffset = if ($activeCount -gt 0) { ($batchOffset + $batchCount) % $activeCount } else { 0 }
  $cycleCount = if ($null -ne $State.governor) { [long]$State.governor.cycleCount } else { 0L }
  $governorAgeDays = if ($null -ne $State.governor) {
    ($Now - (ConvertTo-UtcTimestamp $State.governor.claimedAtUtc)).TotalDays
  } else { 0 }
  $rotationRequired = $cycleCount -ge $script:GovernorMaximumCycles -or $governorAgeDays -ge $script:GovernorMaximumAgeDays
  $engine = if ([long]$State.health.droppedEntries -gt 0) { 'degraded' } else { 'healthy' }
  return [ordered]@{
    ok = $true
    action = $RequestedAction
    engine = $engine
    schemaVersion = 2
    revision = [long]$State.revision
    governorTaskId = $governorId
    governorClaimed = ($null -ne $State.governor)
    currentIsGovernor = ($null -ne $currentHash -and $null -ne $State.governor -and $currentHash -eq [string]$State.governor.idHash)
    activeTasks = $activeTasks.Count
    activeAgents = $activeAgents.Count
    tasks = @($activeTasks)
    agents = @($activeAgents)
    checkBatch = @($batch)
    checkBatchLimit = $script:CheckBatchLimit
    batchOffset = $batchOffset
    nextBatchOffset = $nextBatchOffset
    changes = @($changes)
    resultTruncated = ($activeCount -gt ($activeTasks.Count + $activeAgents.Count))
    registryCoverage = if ([long]$State.health.hookRuns -gt 0) { 'lifecycle_hooks_observed' } else { 'host_inventory_required' }
    monitoringMode = 'complete_host_inventory_plus_optional_hooks'
    monitoredTaskPolicy = 'all_live_host_tasks_including_explicit_targets'
    turnSignals = [long]$State.health.turnSignals
    duplicateSignals = [long]$State.health.duplicateSignals
    hookModelContext = 'none'
    workerModelTurns = 0
    hookExecutionObservation = if ([long]$State.health.hookRuns -gt 0) { 'observed' } else { 'not_observed' }
    hookTrustObservation = 'host_verification_required'
    hookRole = 'optional_acceleration'
    hookRequiredForAutonomy = $false
    lastHookUtc = $State.health.lastHookUtc
    livenessAuthority = 'complete_host_inventory'
    taskDiscoveryAuthority = 'complete_host_inventory_each_governor_cycle'
    catalogRefreshAction = 'fully_restart_codex_then_start_fresh_task'
    loadedTaskCatalogHotSwap = 'unsupported_by_host'
    taskTransport = 'host_required'
    requiredHostAction = 'reconcile_host_inventory_then_wait_compact_batch'
    routineUserAction = 'none'
    hostEquivalenceKey = $script:HostEquivalenceKey
    equivalenceScope = 'installation'
    installationScopePersistence = if ($script:StateStoreMode -eq 'temp_private') { 'bounded_v3_state_root_anchor' } else { 'state_root_anchor' }
    installationScopeSource = $script:InstallationScopeSource
    stateStoreMode = $script:StateStoreMode
    stateStoreWriteReady = $script:StateStoreWriteReady
    stateStoreProtection = $script:StateStoreProtection
    stateStoreMigration = $script:StateStoreMigration
    stateStoreSlot = $script:StateStoreSlot
    stateStoreRecovery = $script:StateStoreRecovery
    stateStoreIdentity = $script:StateStoreIdentity
    codexHomeSource = $script:CodexHomeSource
    codexHomeIdentity = $script:CodexHomeIdentity
    registryMutexIdentity = $script:RegistryMutexIdentity
    hostReconcileAttemptLimit = $script:HostReconcileAttemptLimit
    hostRecheckThroughCycle = $script:HostRecheckThroughCycle
    hostPostcondition = 'one_live_governor_one_active_recurrence_zero_duplicates'
    localMutexScope = 'machine_state_root'
    workerRecurrence = 'disabled'
    modelCalls = 'governor_only'
    recommendedGovernorModel = 'gpt-5.6-terra'
    recommendedGovernorReasoningEffort = 'medium'
    recommendedCadenceMinutes = if ($activeCount -gt 0) { $script:GovernorActiveCadenceMinutes } else { $script:GovernorIdleCadenceMinutes }
    maximumModelCallsPerDay = if ($activeCount -gt 0) { [int](1440 / $script:GovernorActiveCadenceMinutes) } else { [int](1440 / $script:GovernorIdleCadenceMinutes) }
    governorCycleCount = $cycleCount
    governorMaximumCycles = $script:GovernorMaximumCycles
    governorMaximumAgeDays = $script:GovernorMaximumAgeDays
    rotationRequired = $rotationRequired
    registryCapacity = if ([long]$State.health.droppedEntries -gt 0) { 'exhausted' } else { 'available' }
    ignoredStaleEvents = [long]$State.health.ignoredStaleEvents
  }
}

function Write-SafeOutput {
  param($Payload)
  Write-Output ('CHRONOS SUPERVISION ' + ($Payload | ConvertTo-Json -Compress -Depth 8))
}

function Write-SafeError {
  param([string]$Code, [string]$RequestedAction)
  Write-SafeOutput ([ordered]@{ ok = $false; error = $Code; action = $RequestedAction })
}

$mutex = $null
$acquired = $false
$hookData = $null
$preparedHookEvent = $null
$preparedProtectedId = $null
$resolved = $null
$hookDurable = $false
$eventObservedAt = $script:InvocationObservedAtUtc
try {
  if ($Action -eq 'hook') {
    $reader = $null
    try {
      $reader = [IO.StreamReader]::new(
        [Console]::OpenStandardInput(),
        [Text.UTF8Encoding]::new($false, $true),
        $true,
        4096,
        $false
      )
      $raw = $reader.ReadToEnd()
    } catch {
      throw 'supervision_hook_input_encoding_invalid'
    } finally {
      if ($reader) { $reader.Dispose() }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { throw 'supervision_hook_input_empty' }
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    if ([Text.Encoding]::UTF8.GetByteCount($raw) -gt $script:HookInputByteLimit) { throw 'supervision_hook_input_oversize' }
    Assert-StrictJson $raw 'supervision_hook_json_invalid'
    try { $hookData = ConvertTo-Hashtable ($raw | ConvertFrom-Json -ErrorAction Stop) } catch { throw 'supervision_hook_json_invalid' }
    if (-not ($hookData -is [Collections.IDictionary])) { throw 'supervision_hook_shape_invalid' }
    if (-not [string]::IsNullOrWhiteSpace($ObservedAtUtc)) {
      try { $eventObservedAt = ConvertTo-UtcTimestamp $ObservedAtUtc } catch { throw 'supervision_hook_timestamp_invalid' }
    }
  }
  if ($Action -eq 'hook') {
    $preparedHookEvent = New-PreparedHookEvent $hookData $eventObservedAt
    $preparedProtectedId = if ([string]$preparedHookEvent.event -eq 'SessionStart') { [string]$preparedHookEvent.protectedSessionId } elseif ([string]$preparedHookEvent.event -eq 'SubagentStart') { [string]$preparedHookEvent.protectedAgentId } else { $null }
  }
  $resolved = Resolve-StatePath $StatePath
  $resolved = Initialize-StateStore $resolved
  $script:StateStoreIdentity = (Get-TextHash ([IO.Path]::GetFullPath($resolved).ToUpperInvariant())).Substring(0, 16)
  $mutex = New-RegistryMutex $resolved
  $mutexWaitMilliseconds = if ($Action -eq 'hook' -and [string](Get-Value $hookData 'hook_event_name' '') -eq 'SessionEnd') {
    $script:SynchronousHookMutexWaitMilliseconds
  } elseif ($Action -eq 'hook') {
    $script:AsynchronousHookMutexWaitMilliseconds
  } else { 1000 }
  try { $acquired = $mutex.WaitOne($mutexWaitMilliseconds) } catch [Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) {
    if ($Action -eq 'hook') {
      Write-PendingHookEventDurably $resolved $preparedHookEvent
      $hookDurable = $true
      exit 0
    }
    throw 'supervision_mutex_busy'
  }
  Import-LegacyStateIfPresent $resolved
  if ($Action -ne 'hook') {
    $installationScopeId = Get-OrCreateInstallationScopeId $resolved
    $script:HostEquivalenceKey = $script:GovernorEquivalencePrefix + ':' + $installationScopeId
  }
  $state = Read-State $resolved -ValidateProtectedIds:($Action -ne 'hook')
  $now = [DateTimeOffset]::UtcNow
  $processedHookEventsBeforeMerge = ConvertTo-Json -InputObject @($state.health.processedHookEvents) -Compress -Depth 4
  $pendingItems = @(Merge-PendingHookEvents $state $resolved $now)
  $processedHookEventsAfterMerge = ConvertTo-Json -InputObject @($state.health.processedHookEvents) -Compress -Depth 4
  $processedHookEventsChanged = $processedHookEventsBeforeMerge -ne $processedHookEventsAfterMerge

  if ($Action -eq 'hook') {
    Invoke-HookEvent $state $hookData $now $eventObservedAt $preparedProtectedId ([string]$preparedHookEvent.workspaceHash)
    Write-State $state $resolved -TrustedHookMutation
    $hookDurable = $true
    Remove-PendingHookEvents $pendingItems $resolved
    exit 0
  }
  if ($pendingItems.Count -gt 0 -or $processedHookEventsChanged) {
    Write-State $state $resolved -TrustedHookMutation
    Remove-PendingHookEvents $pendingItems $resolved
  }

  if ($Action -eq 'status') {
    Remove-ExpiredRecords $state $now
    $governorTaskId = if ($null -ne $state.governor) { Unprotect-OpaqueId $state.governor.protectedId } else { $null }
    $governorLifecycleState = if ($null -ne $state.governor) { [string]$state.sessions[[string]$state.governor.idHash].state } else { 'unclaimed' }
    $activeTasks = @($state.sessions.Values | Where-Object { $_.kind -eq 'task' -and $_.state -eq 'active' -and ($null -eq $state.governor -or $_.idHash -ne $state.governor.idHash) }).Count
    $activeAgents = @($state.sessions.Values | Where-Object { $_.kind -eq 'agent' -and $_.state -eq 'active' }).Count
    Write-SafeOutput ([ordered]@{
      ok = $true
      action = 'status'
      engine = if ([long]$state.health.droppedEntries -gt 0) { 'degraded' } else { 'healthy' }
      schemaVersion = 2
      revision = [long]$state.revision
      governorClaimed = ($null -ne $state.governor)
      governorTaskId = $governorTaskId
      governorLifecycleState = $governorLifecycleState
      governorRoleCompatibility = if ($null -ne $state.governor) { 'host_verification_required' } else { 'unclaimed' }
      activeTasks = $activeTasks
      activeAgents = $activeAgents
      retainedRecords = $state.sessions.Count
      hookRuns = [long]$state.health.hookRuns
      turnSignals = [long]$state.health.turnSignals
      duplicateSignals = [long]$state.health.duplicateSignals
      droppedEntries = [long]$state.health.droppedEntries
      ignoredStaleEvents = [long]$state.health.ignoredStaleEvents
      registryCapacity = if ([long]$state.health.droppedEntries -gt 0) { 'exhausted' } else { 'available' }
      registryCoverage = if ([long]$state.health.hookRuns -gt 0) { 'lifecycle_hooks_observed' } else { 'host_inventory_required' }
      hookExecutionObservation = if ([long]$state.health.hookRuns -gt 0) { 'observed' } else { 'not_observed' }
      hookTrustObservation = 'host_verification_required'
      hookRole = 'optional_acceleration'
      hookRequiredForAutonomy = $false
      lastHookUtc = $state.health.lastHookUtc
      livenessAuthority = 'complete_host_inventory'
      taskDiscoveryAuthority = 'complete_host_inventory_each_governor_cycle'
      catalogRefreshAction = 'fully_restart_codex_then_start_fresh_task'
      loadedTaskCatalogHotSwap = 'unsupported_by_host'
      taskTransport = 'host_required'
      requiredHostAction = 'reconcile_host_inventory_then_wait_compact_batch'
      routineUserAction = 'none'
      hostEquivalenceKey = $script:HostEquivalenceKey
      equivalenceScope = 'installation'
      installationScopePersistence = if ($script:StateStoreMode -eq 'temp_private') { 'bounded_v3_state_root_anchor' } else { 'state_root_anchor' }
      installationScopeSource = $script:InstallationScopeSource
      stateStoreMode = $script:StateStoreMode
      stateStoreWriteReady = $script:StateStoreWriteReady
      stateStoreProtection = $script:StateStoreProtection
      stateStoreMigration = $script:StateStoreMigration
      stateStoreSlot = $script:StateStoreSlot
      stateStoreRecovery = $script:StateStoreRecovery
      stateStoreIdentity = $script:StateStoreIdentity
      codexHomeSource = $script:CodexHomeSource
      codexHomeIdentity = $script:CodexHomeIdentity
      registryMutexIdentity = $script:RegistryMutexIdentity
      priorStateDisposition = $script:PriorStateDisposition
      priorStateWriteAttempted = $script:PriorStateWriteAttempted
      hostReconcileAttemptLimit = $script:HostReconcileAttemptLimit
      hostRecheckThroughCycle = $script:HostRecheckThroughCycle
      hostPostcondition = 'one_live_governor_one_active_recurrence_zero_duplicates'
      localMutexScope = 'machine_state_root'
      workerRecurrence = 'disabled'
      modelCalls = 'governor_only'
      monitoringMode = 'complete_host_inventory_plus_optional_hooks'
      monitoredTaskPolicy = 'all_live_host_tasks_including_explicit_targets'
      hookModelContext = 'none'
      workerModelTurns = 0
      recurrenceEligible = ($null -ne $state.governor -and [long]$state.governor.cycleCount -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$state.governor.lastCycleUtc))
      recurrenceCreationPolicy = 'after_successful_complete_host_inventory_cycle'
      recommendedGovernorModel = 'gpt-5.6-terra'
      recommendedGovernorReasoningEffort = 'medium'
      recommendedCadenceMinutes = if (($activeTasks + $activeAgents) -gt 0) { $script:GovernorActiveCadenceMinutes } else { $script:GovernorIdleCadenceMinutes }
      maximumModelCallsPerDay = if (($activeTasks + $activeAgents) -gt 0) { [int](1440 / $script:GovernorActiveCadenceMinutes) } else { [int](1440 / $script:GovernorIdleCadenceMinutes) }
      governorCycleCount = if ($null -ne $state.governor) { [long]$state.governor.cycleCount } else { 0L }
      governorMaximumCycles = $script:GovernorMaximumCycles
      governorMaximumAgeDays = $script:GovernorMaximumAgeDays
    })
    exit 0
  }

  $current = Normalize-OpaqueId $SessionId
  $currentHash = Get-TextHash $current
  if ($Action -eq 'initialize') {
    $sameGovernor = $null -ne $state.governor -and [string]$state.governor.idHash -eq $currentHash
    if ($null -ne $state.governor -and [string]$state.governor.idHash -ne $currentHash) {
      if (-not $Force) { throw 'supervision_governor_conflict' }
      $priorGovernorHash = [string]$state.governor.idHash
      $endedPriorGovernor = Set-RecordEndedByHash $state $priorGovernorHash $now $now
      if (-not $endedPriorGovernor -or [string]$state.sessions[$priorGovernorHash].state -ne 'ended') {
        throw 'supervision_event_order_conflict'
      }
    }
    $existing = if ($state.sessions.Contains($currentHash)) { $state.sessions[$currentHash] } else { $null }
    $workspaceHash = if ($null -ne $existing) { [string]$existing.workspaceHash } else { Get-WorkspaceHash (Get-Location).Path }
    $model = if ($null -ne $existing) { [string]$existing.model } else { 'unavailable' }
    $source = if ($null -ne $existing) { [string]$existing.source } else { 'fallback' }
    $initialized = Set-SessionRecord $state $current 'task' $null $workspaceHash $model 'active' $source $now $now 3 -AllowReactivation
    if (-not $initialized -or $state.sessions[$currentHash].state -ne 'active') { throw 'supervision_event_order_conflict' }
    $state.revision = [long]$state.revision + 1
    if ($sameGovernor) {
      $state.governor.lastSeenUtc = $now.ToString('o')
    } else {
      $state.governor = [ordered]@{
        idHash = $currentHash
        protectedId = Protect-OpaqueId $current
        claimedAtUtc = $now.ToString('o')
        lastSeenUtc = $now.ToString('o')
        cycleCount = 0L
        idleCycles = 0L
        lastCycleUtc = $null
      }
    }
    Write-State $state $resolved
    $initializePayload = Get-DiscoveryPayload $state 'initialize' $current $SinceRevision $now
    $initializePayload['recurrenceEligible'] = $false
    $initializePayload['recurrenceCreationPolicy'] = 'after_successful_complete_host_inventory_cycle'
    $initializePayload['requiredHostAction'] = 'run_complete_host_inventory_cycle_before_recurrence'
    Write-SafeOutput $initializePayload
    exit 0
  }
  if ($Action -eq 'confirm-active') {
    if ($null -eq $state.governor -or [string]$state.governor.idHash -ne $currentHash) { throw 'supervision_governor_mismatch' }
    $subject = Normalize-OpaqueId $SubjectId 'supervision_subject_id_invalid'
    $subjectHash = Get-TextHash $subject
    if (-not $state.sessions.Contains($subjectHash)) { throw 'supervision_subject_unknown' }
    $record = $state.sessions[$subjectHash]
    $confirmed = Set-SessionRecord $state $subject ([string]$record.kind) ([string]$record.parentHash) ([string]$record.workspaceHash) ([string]$record.model) 'active' ([string]$record.source) $now $now 3 -AllowReactivation
    if (-not $confirmed -or $state.sessions[$subjectHash].state -ne 'active') { throw 'supervision_event_order_conflict' }
    Write-State $state $resolved
    Write-SafeOutput ([ordered]@{ ok = $true; action = 'confirm-active'; revision = [long]$state.revision; subjectHash = $subjectHash.Substring(0, 16); state = 'active' })
    exit 0
  }
  if ($Action -eq 'reconcile-host') {
    if ($null -eq $state.governor -or [string]$state.governor.idHash -ne $currentHash) { throw 'supervision_governor_mismatch' }
    $inventory = Complete-HostInventoryForGovernor (Read-HostInventory $HostInventoryPath $now) $current
    $reconciled = Invoke-HostInventoryReconciliation $state $inventory $current $now
    $state.governor.lastSeenUtc = $now.ToString('o')
    $payload = Get-DiscoveryPayload $state 'reconcile-host' $current $SinceRevision $now
    $payload['hostInventoryObserved'] = [int]$reconciled.Observed
    $payload['hostInventoryRawObserved'] = [int]$inventory.RawObserved
    $payload['hostInventoryComplete'] = [bool]$reconciled.Complete
    $payload['hostInventoryCallerVisibility'] = [string]$inventory.CallerVisibility
    $payload['hostInventoryGovernorSource'] = [string]$inventory.GovernorSource
    $payload['hostTasksAdded'] = [int]$reconciled.Added
    $payload['hostTasksReactivated'] = [int]$reconciled.Reactivated
    $payload['hostTaskGenerationsChanged'] = [int]$reconciled.GenerationChanged
    $payload['hostTasksEnded'] = [int]$reconciled.Ended
    $payload['hostTaskStatuses'] = @(Get-CompactHostTaskStatuses $inventory)
    $payload['taskWakePolicy'] = 'intervention_claim_required'
    $payload['requiredHostAction'] = 'wait_compact_batch_then_evaluate_heartbeat'
    $payload['recurrenceEligible'] = $false
    $payload['recurrenceCreationPolicy'] = 'after_successful_complete_host_inventory_cycle'
    Write-State $state $resolved
    Write-SafeOutput $payload
    exit 0
  }
  if ($Action -eq 'release') {
    if ($null -eq $state.governor -or [string]$state.governor.idHash -ne $currentHash) { throw 'supervision_governor_mismatch' }
    if (-not $ConfirmRecurrenceStopped) {
      Write-SafeOutput ([ordered]@{
        ok = $true
        action = 'release'
        releaseReady = $false
        governorClaimed = $true
        requiredHostAction = 'pause_or_delete_chronos_governor_pulse_then_verify_absent'
      })
      exit 0
    }
    $state.revision = [long]$state.revision + 1
    $state.governor = $null
    Write-State $state $resolved
    Write-SafeOutput ([ordered]@{ ok = $true; action = 'release'; revision = [long]$state.revision; governorClaimed = $false })
    exit 0
  }
  if ($Action -eq 'cycle') {
    if ($null -eq $state.governor -or [string]$state.governor.idHash -ne $currentHash) { throw 'supervision_governor_mismatch' }
    $inventory = Read-HostInventory $HostInventoryPath $now
    if (-not [bool]$inventory.Complete) { throw 'supervision_host_inventory_incomplete' }
    $inventory = Complete-HostInventoryForGovernor $inventory $current
    $reconciled = Invoke-HostInventoryReconciliation $state $inventory $current $now
    $state.governor.cycleCount = [long]$state.governor.cycleCount + 1
    $state.governor.lastCycleUtc = $now.ToString('o')
    $state.governor.lastSeenUtc = $now.ToString('o')
    $activeCount = @($state.sessions.Values | Where-Object { $_.state -eq 'active' -and $_.idHash -ne $state.governor.idHash }).Count
    $state.governor.idleCycles = if ($activeCount -gt 0) { 0L } else { [long]$state.governor.idleCycles + 1 }
    $payload = Get-DiscoveryPayload $state 'cycle' $current $SinceRevision $now
    $payload['hostInventoryObserved'] = [int]$reconciled.Observed
    $payload['hostInventoryRawObserved'] = [int]$inventory.RawObserved
    $payload['hostInventoryComplete'] = $true
    $payload['hostInventoryCallerVisibility'] = [string]$inventory.CallerVisibility
    $payload['hostInventoryGovernorSource'] = [string]$inventory.GovernorSource
    $payload['hostInventoryCycle'] = [long]$state.governor.cycleCount
    $payload['hostTasksAdded'] = [int]$reconciled.Added
    $payload['hostTasksReactivated'] = [int]$reconciled.Reactivated
    $payload['hostTaskGenerationsChanged'] = [int]$reconciled.GenerationChanged
    $payload['hostTasksEnded'] = [int]$reconciled.Ended
    $payload['hostTaskStatuses'] = @(Get-CompactHostTaskStatuses $inventory)
    $payload['taskWakePolicy'] = 'intervention_claim_required'
    $payload['requiredHostAction'] = 'wait_compact_batch_then_evaluate_heartbeat'
    $payload['recurrenceEligible'] = $true
    $payload['recurrenceCreationPolicy'] = 'after_successful_complete_host_inventory_cycle'
    $state.health.scanOffset = [long]$payload.nextBatchOffset
    Write-State $state $resolved
    Write-SafeOutput $payload
    exit 0
  }
  if ($Action -eq 'discover') {
    if ($null -eq $state.governor -or [string]$state.governor.idHash -ne $currentHash) { throw 'supervision_governor_mismatch' }
    $payload = Get-DiscoveryPayload $state 'discover' $current $SinceRevision $now
    $payload['cycleAdvanced'] = $false
    $payload['taskWakePolicy'] = 'intervention_claim_required'
    $payload['requiredHostAction'] = 'run_cycle_with_complete_host_inventory'
    Write-SafeOutput $payload
    exit 0
  }
  throw 'supervision_action_invalid'
} catch {
  $code = [string]$_.Exception.Message
  if ($code -notmatch '^supervision_[a-z_]+$') { $code = 'supervision_internal_error' }
  if ($Action -eq 'hook') {
    # A lifecycle hint must reach either the registry or the protected pending
    # queue before the production hook returns silently. This also catches a
    # transient direct-state or first pending-slot failure without retrying the
    # model task or extending the mutex deadline.
    if (-not $hookDurable -and $null -ne $preparedHookEvent -and -not [string]::IsNullOrWhiteSpace([string]$resolved)) {
      try {
        Write-PendingHookEventDurably $resolved $preparedHookEvent
        $hookDurable = $true
        exit 0
      } catch {
        $fallbackCode = [string]$_.Exception.Message
        if ($fallbackCode -match '^supervision_[a-z_]+$') { $code = $fallbackCode }
        else { $code = 'supervision_pending_event_unwritable' }
      }
    }
    if ($Diagnostic) {
      Write-SafeError $code 'hook'
      exit 1
    }
    exit 0
  }
  Write-SafeError $code $Action
  exit 1
} finally {
  if ($mutex) {
    if ($acquired) { try { $mutex.ReleaseMutex() | Out-Null } catch {} }
    $mutex.Dispose()
  }
}
