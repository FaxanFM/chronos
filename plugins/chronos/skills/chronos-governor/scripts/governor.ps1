param(
  [ValidateSet("plan", "lease", "renew", "result", "verify", "correct", "accept", "retire", "release", "status")]
  [string]$Action = "status",
  [string]$Repository = (Get-Location).Path,
  [string]$StatePath = "",
  [string]$TaskId = "",
  [ValidateSet("mechanical", "docs", "tests", "simple-code", "explore", "review", "verification", "risky")]
  [string]$TaskClass = "simple-code",
  [ValidateSet("read", "write")]
  [string]$AccessMode = "read",
  [string[]]$Scope = @(),
  [string]$WorkerId = "",
  [string]$RequestedModel = "",
  [string]$EffectiveModel = "",
  [ValidateSet("low", "medium", "high", "xhigh", "max", "ultra")]
  [string]$ReasoningEffort = "low",
  [string]$RuntimeModels = "",
  [string]$ExpectedWorkspaceId = "",
  [string]$MutationAttributionId = "",
  [switch]$MutationAttributionVerified,
  [string]$PlanToken = "",
  [string]$LeaseId = "",
  [string]$FencingToken = "",
  [ValidateSet("HEALTHY", "WARNING", "CRITICAL", "UNAVAILABLE")]
  [string]$Health = "UNAVAILABLE",
  [ValidateSet("LOW", "ELEVATED", "HIGH", "UNAVAILABLE")]
  [string]$QuotaRisk = "UNAVAILABLE",
  [switch]$VerificationPassed,
  [switch]$CoordinatorAccepted,
  [int]$MaxConcurrentWorkers = 2,
  [int]$MaxTotalAttempts = 3,
  [int]$MaxCorrections = 1,
  [int]$PlanMinutes = 5,
  [int]$LeaseMinutes = 30,
  [int]$StaleMinutes = 120,
  [int]$LockStaleSeconds = 30
)

$ErrorActionPreference = "Stop"

function Write-GovernorOutput {
  param([hashtable]$Data)
  Write-Output ("CHRONOS GOVERNOR " + ($Data | ConvertTo-Json -Compress -Depth 10))
}

function Throw-GovernorError {
  param([string]$Code)
  throw [System.InvalidOperationException]::new($Code)
}

function Invoke-Git {
  param([string[]]$Arguments)
  $output = @(& git -C $script:RepositoryRoot @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { Throw-GovernorError "git_command_failed" }
  ($output -join "`n").Trim()
}

function Try-Invoke-Git {
  param([string[]]$Arguments)
  $output = @(& git -C $script:RepositoryRoot @Arguments 2>$null)
  @{
    ok = ($LASTEXITCODE -eq 0)
    output = ($output -join "`n").Trim()
  }
}

function ConvertTo-Hashtable {
  param($Value)
  if ($null -eq $Value) { return $null }
  if (
    $Value -is [string] -or $Value -is [bool] -or $Value -is [char] -or
    $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
    $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
    $Value -is [int64] -or $Value -is [uint64] -or $Value -is [single] -or
    $Value -is [double] -or $Value -is [decimal] -or $Value -is [datetime]
  ) { return $Value }
  if ($Value -is [System.Collections.IDictionary]) {
    $table = @{}
    foreach ($key in $Value.Keys) { $table[[string]$key] = ConvertTo-Hashtable $Value[$key] }
    return $table
  }
  if ($Value -is [pscustomobject]) {
    $table = @{}
    foreach ($property in $Value.PSObject.Properties) {
      $table[$property.Name] = ConvertTo-Hashtable $property.Value
    }
    return $table
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    $items = @($Value | ForEach-Object { ConvertTo-Hashtable $_ })
    return ,$items
  }
  $Value
}

function Get-TextHash {
  param([string]$Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
    ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-FileHashValue {
  param([string]$Path)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
      ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
    } finally {
      $stream.Dispose()
    }
  } finally {
    $sha.Dispose()
  }
}

function Initialize-NativePathResolver {
  if ($env:OS -ne 'Windows_NT' -or ('Chronos.NativePath' -as [type])) { return }
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Chronos {
  public static class NativePath {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateFileW(
      string name, uint access, uint share, IntPtr security, uint creation,
      uint flags, IntPtr template);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
      IntPtr handle, StringBuilder path, uint length, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    public static string Resolve(string path) {
      IntPtr handle = CreateFileW(path, 0x80, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
      if (handle == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
      try {
        var value = new StringBuilder(1024);
        uint length = GetFinalPathNameByHandleW(handle, value, (uint)value.Capacity, 0);
        if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
        if (length >= value.Capacity) {
          value = new StringBuilder((int)length + 1);
          length = GetFinalPathNameByHandleW(handle, value, (uint)value.Capacity, 0);
          if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        return value.ToString();
      } finally {
        CloseHandle(handle);
      }
    }
  }
}
'@
}

function Resolve-CanonicalPath {
  param([string]$Path)
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
  if (-not (Test-Path -LiteralPath $full)) { return $full }
  if ($env:OS -eq 'Windows_NT') {
    Initialize-NativePathResolver
    try {
      $resolved = [Chronos.NativePath]::Resolve($full)
      if ($resolved.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ('\\' + $resolved.Substring(8)).TrimEnd('\', '/')
      }
      if ($resolved.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolved.Substring(4).TrimEnd('\', '/')
      }
      return $resolved.TrimEnd('\', '/')
    } catch {
      Throw-GovernorError "canonical_path_unavailable"
    }
  }
  (Get-Item -LiteralPath $full -Force).FullName.TrimEnd('\', '/')
}

function Normalize-Identifier {
  param([string]$Value, [string]$ErrorCode)
  if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') {
    Throw-GovernorError $ErrorCode
  }
  $Value
}

function Normalize-WorkerIdentifier {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 128 -or $Value -match '[\\\x00-\x1f\x7f]') {
    Throw-GovernorError "invalid_worker_id"
  }
  if ($Value.StartsWith('/')) {
    $segments = @($Value.Substring(1).Split('/'))
    if ($segments.Count -lt 2 -or @($segments | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' }).Count -gt 0) {
      Throw-GovernorError "invalid_worker_id"
    }
    return '/' + ($segments -join '/')
  }
  Normalize-Identifier $Value 'invalid_worker_id'
}

function Normalize-ModelIdentifier {
  param([string]$Value)
  if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,95}$') {
    Throw-GovernorError "invalid_model_inventory"
  }
  $Value
}

function Normalize-Scope {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { Throw-GovernorError "invalid_scope" }
  $normalized = $Value.Trim().Replace('\', '/')
  while ($normalized.Contains('//')) { $normalized = $normalized.Replace('//', '/') }
  while ($normalized.StartsWith('./')) { $normalized = $normalized.Substring(2) }
  $segments = @($normalized.Split('/') | Where-Object { $_ -ne "" })
  if (
    [System.IO.Path]::IsPathRooted($normalized) -or
    $normalized -match '^[A-Za-z]:' -or
    $segments -contains '..' -or
    $segments -contains '.' -or
    $normalized -eq '.git' -or $normalized.StartsWith('.git/', [System.StringComparison]::OrdinalIgnoreCase) -or
    $normalized -eq '.chronos' -or $normalized.StartsWith('.chronos/', [System.StringComparison]::OrdinalIgnoreCase) -or
    $normalized -in @('*', '**', '**/*')
  ) { Throw-GovernorError "invalid_scope" }
  foreach ($segment in $segments) {
    if ($segment.TrimEnd(' ', '.') -ne $segment) { Throw-GovernorError "invalid_scope" }
  }
  $normalized.TrimEnd('/')
}

function Get-NormalizedScopes {
  if (-not $Scope -or $Scope.Count -eq 0) { Throw-GovernorError "scope_required" }
  $expanded = @($Scope | ForEach-Object { @($_ -split ',') })
  @($expanded | ForEach-Object { Normalize-Scope $_ } | Sort-Object -Unique)
}

function Test-PathInScope {
  param([string]$Path, [string[]]$AllowedScopes)
  $normalizedPath = Normalize-Scope $Path
  foreach ($allowed in $AllowedScopes) {
    if ($allowed.EndsWith('/**')) {
      $prefix = $allowed.Substring(0, $allowed.Length - 3).TrimEnd('/')
      if (
        $normalizedPath.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($prefix + '/', [System.StringComparison]::OrdinalIgnoreCase)
      ) { return $true }
      continue
    }
    $pattern = [System.Management.Automation.WildcardPattern]::new(
      $allowed,
      [System.Management.Automation.WildcardOptions]::IgnoreCase
    )
    if ($pattern.IsMatch($normalizedPath)) { return $true }
  }
  $false
}

function Test-GlobalLockPath {
  param([string]$Path)
  $normalized = (Normalize-Scope $Path).ToLowerInvariant()
  $leaf = [System.IO.Path]::GetFileName($normalized)
  if ($leaf -in @(
    'package.json', 'package-lock.json', 'pnpm-lock.yaml', 'yarn.lock',
    'cargo.toml', 'cargo.lock', 'pyproject.toml', 'requirements.txt',
    'dockerfile', 'docker-compose.yml', 'compose.yml', 'compose.yaml'
  )) { return $true }
  if ($normalized.StartsWith('.github/')) { return $true }
  if ($normalized -match '(^|/)migrations(/|$)') { return $true }
  $false
}

function Test-ReparsePath {
  param([string]$Path)
  $relative = Normalize-Scope $Path
  $fullPath = [System.IO.Path]::GetFullPath((Join-Path $script:RepositoryRoot $relative))
  $root = $script:RepositoryRoot.TrimEnd('\', '/')
  if (
    -not $fullPath.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -and
    -not $fullPath.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
  ) { return $true }
  $current = $fullPath
  while ($current -and -not $current.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $true }
    $current = Split-Path -Parent $current
  }
  if (Test-Path -LiteralPath $fullPath) {
    $canonical = Resolve-CanonicalPath $fullPath
    if (
      -not $canonical.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -and
      -not $canonical.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    ) { return $true }
  }
  $false
}

function Test-ScopeReparseRisk {
  param([string]$ScopeValue)
  $prefix = ($ScopeValue -split '[*?[]', 2)[0].TrimEnd('/')
  if (-not $prefix) { return $true }
  $candidate = Join-Path $script:RepositoryRoot $prefix
  while (-not (Test-Path -LiteralPath $candidate) -and $candidate -ne $script:RepositoryRoot) {
    $candidate = Split-Path -Parent $candidate
  }
  $relative = $candidate.Substring($script:RepositoryRoot.Length).TrimStart('\', '/')
  if (-not $relative) { return $false }
  Test-ReparsePath $relative
}

function Read-RuntimeModelInventory {
  param([string]$Value)
  $models = @()
  $seen = @{}
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return @{ models = @(); hash = Get-TextHash ''; available = $false }
  }
  $index = 0
  foreach ($entry in @($Value.Split(';'))) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }
    $parts = @($entry.Split('=', 2))
    if ($parts.Count -ne 2) { Throw-GovernorError "invalid_model_inventory" }
    $model = Normalize-ModelIdentifier $parts[0].Trim()
    $key = $model.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { Throw-GovernorError "invalid_model_inventory" }
    $metadataParts = @($parts[1].Split('|'))
    if ($metadataParts.Count -gt 2) { Throw-GovernorError "invalid_model_inventory" }
    $efforts = @($metadataParts[0].Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if ($efforts.Count -eq 0) { Throw-GovernorError "invalid_model_inventory" }
    foreach ($effort in $efforts) {
      if ($effort -notin @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')) {
        Throw-GovernorError "invalid_model_inventory"
      }
    }
    $costRank = $null
    if ($metadataParts.Count -eq 2) {
      $costParts = @($metadataParts[1].Trim().Split('=', 2))
      $parsedRank = 0
      if (
        $costParts.Count -ne 2 -or $costParts[0].Trim().ToLowerInvariant() -ne 'cost' -or
        -not [int]::TryParse($costParts[1].Trim(), [ref]$parsedRank) -or
        $parsedRank -lt 0 -or $parsedRank -gt 1000000
      ) { Throw-GovernorError "invalid_model_inventory" }
      $costRank = $parsedRank
    }
    $seen[$key] = $true
    $models += ,@{ id = $model; efforts = @($efforts); index = $index; cost_rank = $costRank }
    $index++
  }
  if ($models.Count -eq 0) { Throw-GovernorError "invalid_model_inventory" }
  $canonical = @($models | ForEach-Object {
      $_.id + '=' + ($_.efforts -join ',') + $(if ($null -ne $_.cost_rank) { '|cost=' + $_.cost_rank } else { '' })
    }) -join ';'
  @{ models = @($models); hash = Get-TextHash $canonical; available = $true }
}

function Select-RuntimeModel {
  param([hashtable]$Inventory, [string]$Requested, [string]$Effort)
  if (-not $Inventory.available) {
    return @{ selected = $false; reason = 'model_inventory_unavailable'; model = $null; index = $null }
  }
  if ($Requested) {
    $requestedId = Normalize-ModelIdentifier $Requested
    $match = @($Inventory.models | Where-Object { $_.id -eq $requestedId })
    if ($match.Count -eq 0) {
      return @{ selected = $false; reason = 'model_not_advertised'; model = $null; index = $null }
    }
    if ($match[0].efforts -notcontains $Effort) {
      return @{ selected = $false; reason = 'model_effort_unsupported'; model = $null; index = $null }
    }
    return @{ selected = $true; reason = 'requested_model_validated'; model = $match[0].id; index = $match[0].index; cost_rank = $match[0].cost_rank }
  }
  $compatible = @($Inventory.models | Where-Object { $_.efforts -contains $Effort })
  if ($compatible.Count -eq 0) {
    return @{ selected = $false; reason = 'no_compatible_worker_model'; model = $null; index = $null }
  }
  $allRanked = @($compatible | Where-Object { $null -eq $_.cost_rank }).Count -eq 0
  if ($allRanked) {
    $ranked = @($compatible | Sort-Object @{ Expression = { $_.cost_rank } }, @{ Expression = { $_.index } })
    return @{
      selected = $true; reason = 'runtime_cost_rank'; model = $ranked[0].id
      index = $ranked[0].index; cost_rank = $ranked[0].cost_rank
    }
  }
  @{
    selected = $true; reason = 'runtime_inventory_order_unranked'; model = $compatible[0].id
    index = $compatible[0].index; cost_rank = $null
  }
}

function Get-HeadState {
  $commit = Invoke-Git @('rev-parse', 'HEAD')
  $symbolic = Try-Invoke-Git @('symbolic-ref', '-q', 'HEAD')
  if ($symbolic.ok -and $symbolic.output) {
    return @{ mode = 'branch'; reference_hash = Get-TextHash $symbolic.output; commit = $commit }
  }
  @{ mode = 'detached'; reference_hash = Get-TextHash ('detached:' + $commit); commit = $commit }
}

function Get-TaskChanges {
  param([string]$BaseCommit)
  $trackedText = Invoke-Git @('diff', '--name-only', '--diff-filter=ACDMRTUXB', $BaseCommit, '--')
  $untrackedText = Invoke-Git @('ls-files', '--others', '--exclude-standard')
  $paths = @()
  if ($trackedText) { $paths += @($trackedText -split "`r?`n") }
  if ($untrackedText) { $paths += @($untrackedText -split "`r?`n") }
  @($paths | Where-Object { $_ } | ForEach-Object { Normalize-Scope $_ } | Sort-Object -Unique)
}

function Get-WorkspaceFingerprint {
  param([string]$BaseCommit)
  $head = Get-HeadState
  $status = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')
  $diff = Invoke-Git @('diff', '--no-ext-diff', '--binary', '--full-index', $BaseCommit, '--')
  $untracked = Invoke-Git @('ls-files', '--others', '--exclude-standard')
  $untrackedParts = @()
  if ($untracked) {
    foreach ($relative in @($untracked -split "`r?`n" | Where-Object { $_ } | Sort-Object -Unique)) {
      $normalized = Normalize-Scope $relative
      $full = Join-Path $script:RepositoryRoot $normalized
      if (Test-ReparsePath $normalized) {
        $untrackedParts += $normalized + ':reparse'
      } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
        $untrackedParts += $normalized + ':' + (Get-FileHashValue $full)
      } else {
        $untrackedParts += $normalized + ':non_file'
      }
    }
  }
  Get-TextHash ($head.mode + "`n" + $head.reference_hash + "`n" + $head.commit + "`n" + $status + "`n" + $diff + "`n" + ($untrackedParts -join "`n"))
}

function New-State {
  @{
    version = 3
    state_revision = [int64]0
    workers = @{}
    tasks = @{}
    leases = @{}
    plans = @{}
  }
}

function Read-State {
  $sourcePath = $script:ResolvedStatePath
  $legacySource = $false
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -and (Test-Path -LiteralPath $script:LegacyStatePath -PathType Leaf)) {
    $sourcePath = $script:LegacyStatePath
    $legacySource = $true
  }
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    return New-State
  }
  try {
    $parsed = Get-Content -Raw -LiteralPath $sourcePath | ConvertFrom-Json -ErrorAction Stop
    $state = ConvertTo-Hashtable $parsed
  } catch {
    Throw-GovernorError "state_invalid_json"
  }
  if ($state.version -in @(1, 2)) {
    $legacyActive = @($state.leases.Values | Where-Object { $_.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction') })
    if ($legacySource -and $legacyActive.Count -gt 0) { Throw-GovernorError "state_migration_active_leases" }
    $state.version = 3
    if ($null -eq $state.state_revision) { $state.state_revision = [int64]0 }
    if ($null -eq $state.plans) { $state.plans = @{} }
  }
  if ($state.version -ne 3 -or $null -eq $state.workers -or $null -eq $state.tasks -or $null -eq $state.leases -or $null -eq $state.plans) {
    Throw-GovernorError "state_version_unsupported"
  }
  if ($null -eq $state.state_revision) { Throw-GovernorError "state_version_unsupported" }
  $state
}

function Write-State {
  param([hashtable]$State)
  $directory = Split-Path -Parent $script:ResolvedStatePath
  try {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
      New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $State.state_revision = [int64]$State.state_revision + [int64]1
    $temporary = $script:ResolvedStatePath + ".tmp-" + [guid]::NewGuid().ToString('N')
    $backup = $script:ResolvedStatePath + ".bak"
    $json = $State | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $script:ResolvedStatePath -PathType Leaf) {
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
      [System.IO.File]::Replace($temporary, $script:ResolvedStatePath, $backup, $true)
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    } else {
      [System.IO.File]::Move($temporary, $script:ResolvedStatePath)
    }
  } catch [System.UnauthorizedAccessException] {
    Throw-GovernorError "state_store_unwritable"
  } catch [System.Security.SecurityException] {
    Throw-GovernorError "state_store_unwritable"
  } catch [System.IO.IOException] {
    Throw-GovernorError "state_persist_failed"
  } finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary -PathType Leaf)) {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
  }
}

function Test-LockOwnerAlive {
  param([hashtable]$Owner)
  try {
    $process = Get-Process -Id ([int]$Owner.pid) -ErrorAction Stop
    $ticks = $process.StartTime.ToUniversalTime().Ticks.ToString()
    $ticks -eq [string]$Owner.process_start_utc_ticks
  } catch {
    $false
  }
}

function Try-Recover-StateLock {
  param([string]$LockPath)
  if (-not (Test-Path -LiteralPath $LockPath -PathType Container)) { return $true }
  $ownerPath = Join-Path $LockPath 'owner.json'
  $item = if (Test-Path -LiteralPath $ownerPath -PathType Leaf) {
    Get-Item -LiteralPath $ownerPath -Force
  } else {
    Get-Item -LiteralPath $LockPath -Force
  }
  if ([DateTimeOffset]::UtcNow -lt ([DateTimeOffset]$item.LastWriteTimeUtc).AddSeconds($LockStaleSeconds)) {
    return $false
  }
  $owner = $null
  if (Test-Path -LiteralPath $ownerPath -PathType Leaf) {
    try { $owner = ConvertTo-Hashtable (Get-Content -Raw -LiteralPath $ownerPath | ConvertFrom-Json -ErrorAction Stop) } catch { $owner = $null }
  }
  if ($owner -and $owner.lock_id -and (Test-LockOwnerAlive $owner)) { return $false }
  $quarantine = $LockPath + '.stale-' + [guid]::NewGuid().ToString('N')
  try {
    [System.IO.Directory]::Move($LockPath, $quarantine)
    [System.IO.Directory]::Delete($quarantine, $true)
    $true
  } catch {
    $false
  }
}

function Acquire-StateLock {
  $lockPath = $script:ResolvedStatePath + ".lock"
  $directory = Split-Path -Parent $lockPath
  try {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
      New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
  } catch [System.UnauthorizedAccessException] {
    Throw-GovernorError "state_store_unwritable"
  } catch [System.Security.SecurityException] {
    Throw-GovernorError "state_store_unwritable"
  } catch [System.IO.IOException] {
    Throw-GovernorError "state_store_unwritable"
  }
  foreach ($attempt in 1..40) {
    try {
      [System.IO.Directory]::CreateDirectory($lockPath) | Out-Null
      $ownerPath = Join-Path $lockPath 'owner.json'
      $stream = [System.IO.File]::Open($ownerPath, 'CreateNew', 'Write', 'None')
      $lockId = [guid]::NewGuid().ToString('N')
      $owner = @{
        lock_id = $lockId
        pid = $PID
        process_start_utc_ticks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()
        created_at = [DateTimeOffset]::UtcNow.ToString('o')
      } | ConvertTo-Json -Compress
      $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
      try { $writer.Write($owner) } finally { $writer.Dispose() }
      return @{ lock_id = $lockId; path = $lockPath }
    } catch [System.UnauthorizedAccessException] {
      if (-not (Test-Path -LiteralPath $lockPath -PathType Container)) {
        Throw-GovernorError "state_store_unwritable"
      }
      Try-Recover-StateLock $lockPath | Out-Null
      if ($attempt -eq 40) { break }
      Start-Sleep -Milliseconds 50
    } catch [System.Security.SecurityException] {
      if (-not (Test-Path -LiteralPath $lockPath -PathType Container)) {
        Throw-GovernorError "state_store_unwritable"
      }
      Try-Recover-StateLock $lockPath | Out-Null
      if ($attempt -eq 40) { break }
      Start-Sleep -Milliseconds 50
    } catch [System.IO.IOException] {
      Try-Recover-StateLock $lockPath | Out-Null
      if ($attempt -eq 40) { break }
      Start-Sleep -Milliseconds 50
    }
  }
  Throw-GovernorError "state_lock_unavailable"
}

function Release-StateLock {
  param([hashtable]$Lock)
  if (-not $Lock) { return }
  $ownerPath = Join-Path $Lock.path 'owner.json'
  try {
    if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) { return }
    $owner = ConvertTo-Hashtable (Get-Content -Raw -LiteralPath $ownerPath | ConvertFrom-Json -ErrorAction Stop)
    if ($owner.lock_id -ne $Lock.lock_id) { return }
    [System.IO.File]::Delete($ownerPath)
    [System.IO.Directory]::Delete($Lock.path, $false)
  } catch {
    return
  }
}

function Get-ActiveLeases {
  param([hashtable]$State)
  @($State.leases.Values | Where-Object { $_.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified') })
}

function Test-LeaseExpired {
  param([hashtable]$Lease)
  try { [DateTimeOffset]::Parse([string]$Lease.expires_at) -le [DateTimeOffset]::UtcNow } catch { $true }
}

function Assert-LeaseCredentials {
  param([hashtable]$Lease, [switch]$AllowExpiredRelease)
  if ($WorkerId -and $Lease.worker_id -ne $WorkerId) { Throw-GovernorError "worker_mismatch" }
  if ($AllowExpiredRelease -and $CoordinatorAccepted -and (Test-LeaseExpired $Lease)) { return }
  if (-not $LeaseId -or $Lease.lease_id -ne $LeaseId) { Throw-GovernorError "lease_id_mismatch" }
  if (-not $FencingToken -or $Lease.fencing_token -ne $FencingToken) { Throw-GovernorError "fencing_token_mismatch" }
  if (Test-LeaseExpired $Lease) { Throw-GovernorError "lease_expired" }
}

try {
  $resolvedRepository = [System.IO.Path]::GetFullPath($Repository)
  if (-not (Test-Path -LiteralPath $resolvedRepository -PathType Container)) {
    Throw-GovernorError "repository_unavailable"
  }
  $rawRoot = (& git -C $resolvedRepository rev-parse --show-toplevel 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $rawRoot) { Throw-GovernorError "git_repository_required" }
  $script:RepositoryRoot = Resolve-CanonicalPath $rawRoot
  $rawCommonDir = (& git -C $script:RepositoryRoot rev-parse --path-format=absolute --git-common-dir 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $rawCommonDir) { Throw-GovernorError "git_common_dir_unavailable" }
  $script:GitCommonDir = Resolve-CanonicalPath $rawCommonDir
  $repositoryId = Get-TextHash $script:GitCommonDir.ToLowerInvariant()
  $workspaceId = Get-TextHash ($script:RepositoryRoot.ToLowerInvariant() + "`n" + $script:GitCommonDir.ToLowerInvariant())
  $stateRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'Chronos\Governor'
  $expectedStatePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $stateRoot $repositoryId) 'governor-state.json'))
  $script:LegacyStatePath = [System.IO.Path]::GetFullPath((Join-Path $script:GitCommonDir 'chronos/governor-state.json'))
  if ($StatePath) {
    $candidateStatePath = [System.IO.Path]::GetFullPath($StatePath)
    if (-not $candidateStatePath.Equals($expectedStatePath, [System.StringComparison]::OrdinalIgnoreCase)) {
      Throw-GovernorError "custom_state_path_disabled"
    }
  }
  $script:ResolvedStatePath = $expectedStatePath

  if ($MaxConcurrentWorkers -lt 1 -or $MaxConcurrentWorkers -gt 4) { Throw-GovernorError "invalid_concurrency_limit" }
  if ($MaxTotalAttempts -lt 1 -or $MaxTotalAttempts -gt 5) { Throw-GovernorError "invalid_attempt_limit" }
  if ($MaxCorrections -lt 0 -or $MaxCorrections -gt 2) { Throw-GovernorError "invalid_correction_limit" }
  if ($PlanMinutes -lt 1 -or $PlanMinutes -gt 15) { Throw-GovernorError "invalid_plan_limit" }
  if ($LeaseMinutes -lt 1 -or $LeaseMinutes -gt 240) { Throw-GovernorError "invalid_lease_limit" }
  if ($StaleMinutes -lt 15 -or $StaleMinutes -gt 1440) { Throw-GovernorError "invalid_stale_limit" }
  if ($LockStaleSeconds -lt 1 -or $LockStaleSeconds -gt 600) { Throw-GovernorError "invalid_lock_stale_limit" }

  if ($Action -eq 'status') {
    $state = Read-State
    $active = @(Get-ActiveLeases $state)
    $staleCutoff = [DateTimeOffset]::UtcNow.AddMinutes(-$StaleMinutes)
    $stale = @($active | Where-Object {
      try { [DateTimeOffset]::Parse([string]$_.updated_at) -lt $staleCutoff } catch { $true }
    })
    Write-GovernorOutput @{
      ok = $true
      action = 'status'
      repository_id = $repositoryId
      workspace_id = $workspaceId
      active_workers = $active.Count
      active_writers = @($active | Where-Object { $_.access_mode -eq 'write' }).Count
      expired_leases = @($active | Where-Object { Test-LeaseExpired $_ }).Count
      idle_workers = @($state.workers.Values | Where-Object { $_.status -eq 'idle' }).Count
      stale_leases = $stale.Count
      pending_plans = @($state.plans.Values | Where-Object { $_.status -eq 'issued' }).Count
      tasks = $state.tasks.Count
      state_version = $state.version
      state_revision = [int64]$state.state_revision
      state_store = 'per_user_temp'
      persistent_content = 'metadata-only'
    }
    exit 0
  }

  if ($Action -eq 'plan') {
    $task = Normalize-Identifier $TaskId 'invalid_task_id'
    $scopes = @(Get-NormalizedScopes)
    $role = if ($TaskClass -in @('review', 'verification', 'explore')) { 'analysis_worker' } else { 'implementation_worker' }
    $effort = if ($TaskClass -in @('simple-code', 'tests', 'review')) { 'medium' } else { 'low' }
    if ($QuotaRisk -eq 'HIGH' -and $effort -eq 'medium' -and $TaskClass -notin @('simple-code', 'tests')) { $effort = 'low' }
    $inventory = Read-RuntimeModelInventory $RuntimeModels
    $selection = Select-RuntimeModel $inventory $RequestedModel $effort
    $decision = 'delegate'
    $reason = 'bounded_low_complexity_task'
    $reuse = @()
    $planTokenValue = $null
    $planExpiresAt = $null
    $planLock = $null
    try {
      $planLock = Acquire-StateLock
      $state = Read-State
      $active = @(Get-ActiveLeases $state)
      if ($TaskClass -eq 'risky') {
        $decision = 'coordinator'; $reason = 'risk_requires_coordinator'
      } elseif ($Health -eq 'CRITICAL') {
        $decision = 'coordinator'; $reason = 'health_advises_no_new_worker'
      } elseif ($state.leases.ContainsKey($task) -and $state.leases[$task].status -in @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified')) {
        $decision = 'coordinator'; $reason = 'task_already_leased'
      } elseif ($active.Count -ge $MaxConcurrentWorkers) {
        $decision = 'coordinator'; $reason = 'concurrency_budget_reached'
      } elseif ($AccessMode -eq 'write' -and @($active | Where-Object { $_.access_mode -eq 'write' }).Count -gt 0) {
        $decision = 'coordinator'; $reason = 'single_writer_lease_active'
      } elseif (-not $selection.selected) {
        $decision = 'coordinator'; $reason = $selection.reason
      }

      $attributionHash = $null
      if ($AccessMode -eq 'write') {
        $head = Get-HeadState
        if ($head.mode -eq 'detached') { $decision = 'coordinator'; $reason = 'detached_head_write_unsupported' }
        if (-not $ExpectedWorkspaceId -or $ExpectedWorkspaceId -ne $workspaceId) {
          $decision = 'coordinator'; $reason = 'workspace_identity_unverified'
        } elseif (-not $MutationAttributionVerified -or -not $MutationAttributionId) {
          $decision = 'coordinator'; $reason = 'mutation_attribution_unverified'
        } else {
          Normalize-Identifier $MutationAttributionId 'invalid_mutation_attribution_id' | Out-Null
          $attributionHash = Get-TextHash $MutationAttributionId
        }
        foreach ($scopeItem in $scopes) {
          if (Test-GlobalLockPath $scopeItem) { $decision = 'coordinator'; $reason = 'global_lock_scope' }
          if (Test-ScopeReparseRisk $scopeItem) { $decision = 'coordinator'; $reason = 'reparse_scope_risk' }
        }
        $dirty = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')
        if ($dirty) { $decision = 'coordinator'; $reason = 'same_folder_write_requires_clean_tree' }
      }

      if ($selection.selected) {
        $reuse = @($state.workers.Values | Where-Object {
          $_.status -eq 'idle' -and $_.repository_id -eq $repositoryId -and
          $_.role -eq $role -and $_.requested_model -eq $selection.model -and $_.access_mode -eq $AccessMode
        } | Select-Object -First 1)
      }

      if ($decision -eq 'delegate') {
        $nowOffset = [DateTimeOffset]::UtcNow
        foreach ($planKey in @($state.plans.Keys)) {
          $existingPlan = $state.plans[$planKey]
          $expired = try { [DateTimeOffset]::Parse([string]$existingPlan.expires_at) -le $nowOffset } catch { $true }
          if ($existingPlan.status -ne 'issued' -or $expired) { $state.plans.Remove($planKey) }
        }
        $planTokenValue = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
        $planExpiresAt = $nowOffset.AddMinutes($PlanMinutes).ToString('o')
        $state.plans[$task] = @{
          task_id = $task
          token_hash = Get-TextHash $planTokenValue
          repository_id = $repositoryId
          workspace_id = $workspaceId
          task_class = $TaskClass
          access_mode = $AccessMode
          scopes = $scopes
          role = $role
          selected_model = $selection.model
          model_selection_reason = $selection.reason
          model_inventory_hash = $inventory.hash
          model_inventory_index = $selection.index
          model_cost_rank = $selection.cost_rank
          reasoning_effort = $effort
          mutation_attribution_hash = $attributionHash
          mutation_attribution_verified = [bool]$MutationAttributionVerified
          status = 'issued'
          created_at = $nowOffset.ToString('o')
          expires_at = $planExpiresAt
        }
        Write-State $state
      }
    } catch {
      $planFailure = if ($_.Exception.Message -match '^[a-z0-9_]+$') { $_.Exception.Message } else { 'internal_error' }
      if ($planFailure -in @('state_store_unwritable', 'state_lock_unavailable', 'state_persist_failed')) {
        $decision = 'coordinator'
        $reason = $planFailure
        $planTokenValue = $null
        $planExpiresAt = $null
      } else {
        throw
      }
    } finally {
      Release-StateLock $planLock
    }
    Write-GovernorOutput @{
      ok = $true
      action = 'plan'
      task_id = $task
      repository_id = $repositoryId
      workspace_id = $workspaceId
      decision = $decision
      reason = $reason
      worker_role = $role
      requested_model = $selection.model
      model_selection_reason = $selection.reason
      model_inventory_hash = $inventory.hash
      model_inventory_index = $selection.index
      model_cost_rank = $selection.cost_rank
      reasoning_effort = $effort
      access_mode = $AccessMode
      scopes = $scopes
      plan_token = $planTokenValue
      plan_expires_at = $planExpiresAt
      state_store = 'per_user_temp'
      reuse_worker_id = if ($reuse.Count) { $reuse[0].worker_id } else { $null }
      fork_context = $false
      max_delegation_depth = 1
      nested_workers_allowed = $false
      final_coordinator_verification_required = $true
    }
    exit 0
  }

  $lock = Acquire-StateLock
  try {
    $state = Read-State
    $nowOffset = [DateTimeOffset]::UtcNow
    $now = $nowOffset.ToString('o')
    $task = Normalize-Identifier $TaskId 'invalid_task_id'

    if ($Action -eq 'lease') {
      $worker = Normalize-WorkerIdentifier $WorkerId
      if (-not $PlanToken) { Throw-GovernorError "plan_token_required" }
      if (-not $state.plans.ContainsKey($task)) { Throw-GovernorError "plan_not_found" }
      $plan = $state.plans[$task]
      if ($plan.status -ne 'issued') { Throw-GovernorError "plan_already_consumed" }
      try {
        if ([DateTimeOffset]::Parse([string]$plan.expires_at) -le $nowOffset) { Throw-GovernorError "plan_expired" }
      } catch [System.FormatException] {
        Throw-GovernorError "plan_invalid"
      }
      if ((Get-TextHash $PlanToken) -ne $plan.token_hash) { Throw-GovernorError "plan_token_mismatch" }
      if ($plan.repository_id -ne $repositoryId -or $plan.workspace_id -ne $workspaceId) {
        Throw-GovernorError "plan_workspace_mismatch"
      }
      $TaskClass = [string]$plan.task_class
      $AccessMode = [string]$plan.access_mode
      $ReasoningEffort = [string]$plan.reasoning_effort
      $scopes = @($plan.scopes)
      $selection = @{
        selected = $true
        model = [string]$plan.selected_model
        index = $plan.model_inventory_index
        cost_rank = $plan.model_cost_rank
      }
      if ($EffectiveModel) {
        $normalizedEffectiveModel = Normalize-ModelIdentifier $EffectiveModel
        if ($normalizedEffectiveModel -ne [string]$selection.model) {
          Throw-GovernorError "model_plan_mismatch"
        }
        $EffectiveModel = $normalizedEffectiveModel
      }
      $active = @(Get-ActiveLeases $state)
      if ($state.leases.ContainsKey($task) -and $state.leases[$task].status -in @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified')) {
        Throw-GovernorError "task_already_leased"
      }
      if ($active.Count -ge $MaxConcurrentWorkers) { Throw-GovernorError "concurrency_budget_reached" }
      if ($AccessMode -eq 'write' -and @($active | Where-Object { $_.access_mode -eq 'write' }).Count -gt 0) {
        Throw-GovernorError "single_writer_lease_active"
      }
      $head = Get-HeadState
      if ($AccessMode -eq 'write') {
        if ($head.mode -eq 'detached') { Throw-GovernorError "detached_head_write_unsupported" }
        if (-not $plan.mutation_attribution_verified -or -not $plan.mutation_attribution_hash) { Throw-GovernorError "mutation_attribution_unverified" }
        $dirty = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')
        if ($dirty) { Throw-GovernorError "same_folder_write_requires_clean_tree" }
        foreach ($scopeItem in $scopes) {
          if (Test-GlobalLockPath $scopeItem) { Throw-GovernorError "global_lock_scope" }
          if (Test-ScopeReparseRisk $scopeItem) { Throw-GovernorError "reparse_scope_risk" }
        }
      }

      $attempts = 1
      $corrections = 0
      $createdAt = $now
      if ($state.tasks.ContainsKey($task)) {
        $attempts = [int]$state.tasks[$task].attempts + 1
        $corrections = [int]$state.tasks[$task].corrections
        $createdAt = [string]$state.tasks[$task].created_at
      }
      if ($attempts -gt $MaxTotalAttempts) { Throw-GovernorError "attempt_budget_reached" }

      $baseCommit = $head.commit
      $baselineFingerprint = Get-WorkspaceFingerprint $baseCommit
      $leaseIdentifier = [guid]::NewGuid().ToString('N')
      $fencing = [guid]::NewGuid().ToString('N')
      $expiresAt = $nowOffset.AddMinutes($LeaseMinutes).ToString('o')
      $role = if ($TaskClass -in @('review', 'verification', 'explore')) { 'analysis_worker' } else { 'implementation_worker' }
      $attributionHash = $plan.mutation_attribution_hash
      $taskRecord = @{
        task_id = $task
        repository_id = $repositoryId
        workspace_id = $workspaceId
        base_commit = $baseCommit
        head_mode = $head.mode
        reference_hash = $head.reference_hash
        baseline_fingerprint = $baselineFingerprint
        access_mode = $AccessMode
        scopes = $scopes
        attempts = $attempts
        corrections = $corrections
        status = 'working'
        created_at = $createdAt
        updated_at = $now
      }
      $workerRecord = @{
        worker_id = $worker
        repository_id = $repositoryId
        workspace_id = $workspaceId
        role = $role
        requested_model = $selection.model
        effective_model = if ($EffectiveModel) { $EffectiveModel } else { $null }
        model_verification = if ($EffectiveModel) { 'reported' } else { 'runtime_not_exposed' }
        model_inventory_hash = $plan.model_inventory_hash
        model_inventory_index = $selection.index
        model_cost_rank = $selection.cost_rank
        reasoning_effort = $ReasoningEffort
        access_mode = $AccessMode
        status = 'leased'
        updated_at = $now
      }
      $leaseRecord = @{
        task_id = $task
        lease_id = $leaseIdentifier
        fencing_token = $fencing
        worker_id = $worker
        repository_id = $repositoryId
        workspace_id = $workspaceId
        mutation_attribution_hash = $attributionHash
        mutation_attribution_verified = [bool]$plan.mutation_attribution_verified
        base_commit = $baseCommit
        head_mode = $head.mode
        reference_hash = $head.reference_hash
        baseline_fingerprint = $baselineFingerprint
        access_mode = $AccessMode
        scopes = $scopes
        status = 'working'
        created_at = $now
        updated_at = $now
        expires_at = $expiresAt
      }
      $state.tasks[$task] = $taskRecord
      $state.workers[$worker] = $workerRecord
      $state.leases[$task] = $leaseRecord
      $state.plans[$task].status = 'consumed'
      $state.plans[$task].consumed_at = $now
      $state.plans[$task].worker_id_hash = Get-TextHash $worker
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'lease'
        task_id = $task
        worker_id = $worker
        repository_id = $repositoryId
        workspace_id = $workspaceId
        lease_id = $leaseIdentifier
        fencing_token = $fencing
        expires_at = $expiresAt
        base_commit = $baseCommit
        selected_model = $selection.model
        model_inventory_hash = $plan.model_inventory_hash
        model_inventory_index = $selection.index
        model_cost_rank = $selection.cost_rank
        attempt = $attempts
        max_attempts = $MaxTotalAttempts
        max_delegation_depth = 1
        nested_workers_allowed = $false
      }
      exit 0
    }

    if (-not $state.leases.ContainsKey($task)) { Throw-GovernorError "lease_not_found" }
    $lease = $state.leases[$task]
    Assert-LeaseCredentials $lease -AllowExpiredRelease:($Action -eq 'release')
    if ($lease.repository_id -ne $repositoryId -or $lease.workspace_id -ne $workspaceId) {
      Throw-GovernorError "workspace_identity_mismatch"
    }

    if ($Action -eq 'renew') {
      if ($lease.status -notin @('working', 'needs_correction', 'awaiting_verification', 'verified')) { Throw-GovernorError "lease_not_renewable" }
      $lease.updated_at = $now
      $lease.expires_at = $nowOffset.AddMinutes($LeaseMinutes).ToString('o')
      $state.tasks[$task].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{ ok = $true; action = 'renew'; task_id = $task; lease_id = $lease.lease_id; expires_at = $lease.expires_at }
      exit 0
    }

    if ($Action -eq 'result') {
      if ($lease.status -notin @('working', 'needs_correction')) { Throw-GovernorError "lease_not_working" }
      if ($EffectiveModel) {
        $normalizedEffectiveModel = Normalize-ModelIdentifier $EffectiveModel
        $plannedModel = [string]$state.workers[$lease.worker_id].requested_model
        if ($normalizedEffectiveModel -ne $plannedModel) { Throw-GovernorError "model_plan_mismatch" }
        $EffectiveModel = $normalizedEffectiveModel
      }
      if ($lease.access_mode -eq 'write') {
        if (-not $MutationAttributionVerified -or -not $MutationAttributionId) { Throw-GovernorError "mutation_attribution_unverified" }
        if ((Get-TextHash $MutationAttributionId) -ne $lease.mutation_attribution_hash) { Throw-GovernorError "mutation_attribution_mismatch" }
      }
      $resultFingerprint = Get-WorkspaceFingerprint ([string]$lease.base_commit)
      $lease.result_fingerprint = $resultFingerprint
      $lease.status = 'awaiting_verification'
      $lease.updated_at = $now
      $state.tasks[$task].status = 'awaiting_verification'
      $state.tasks[$task].updated_at = $now
      $state.workers[$lease.worker_id].status = 'awaiting_verification'
      if ($EffectiveModel) {
        $state.workers[$lease.worker_id].effective_model = $EffectiveModel
        $state.workers[$lease.worker_id].model_verification = 'reported'
      }
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'result'
        task_id = $task
        worker_id = $lease.worker_id
        status = 'awaiting_verification'
        result_fingerprint_recorded = $true
        worker_claims_are_untrusted = $true
      }
      exit 0
    }

    if ($Action -eq 'verify') {
      if ($lease.status -ne 'awaiting_verification') { Throw-GovernorError "result_not_ready" }
      if (-not $lease.result_fingerprint) { Throw-GovernorError "result_fingerprint_missing" }
      $currentFingerprint = Get-WorkspaceFingerprint ([string]$lease.base_commit)
      if ($currentFingerprint -ne $lease.result_fingerprint) { Throw-GovernorError "workspace_changed_after_result" }
      $head = Get-HeadState
      if ($head.mode -ne $lease.head_mode -or $head.reference_hash -ne $lease.reference_hash) { Throw-GovernorError "head_identity_mismatch" }
      $baseCommit = [string]$lease.base_commit
      & git -C $script:RepositoryRoot merge-base --is-ancestor $baseCommit HEAD 2>$null
      if ($LASTEXITCODE -ne 0) { Throw-GovernorError "base_commit_mismatch" }
      $changed = @()
      if ($lease.access_mode -eq 'read') {
        if ($currentFingerprint -ne $lease.baseline_fingerprint) { Throw-GovernorError "read_worker_modified_workspace" }
      } else {
        $changed = @(Get-TaskChanges $baseCommit)
        if ($changed.Count -eq 0) { Throw-GovernorError "no_changes_detected" }
        $outOfScope = @($changed | Where-Object { -not (Test-PathInScope -Path $_ -AllowedScopes @($lease.scopes)) })
        $globalLocks = @($changed | Where-Object { Test-GlobalLockPath -Path $_ })
        $reparseChanges = @($changed | Where-Object { Test-ReparsePath -Path $_ })
        if ($outOfScope.Count -gt 0) { Throw-GovernorError "out_of_scope_changes" }
        if ($globalLocks.Count -gt 0) { Throw-GovernorError "global_lock_change" }
        if ($reparseChanges.Count -gt 0) { Throw-GovernorError "reparse_path_change" }
      }
      if (-not $VerificationPassed) { Throw-GovernorError "verification_evidence_required" }
      $lease.status = 'verified'
      $lease.changed_file_count = $changed.Count
      $lease.updated_at = $now
      $state.tasks[$task].status = 'verified'
      $state.tasks[$task].updated_at = $now
      $state.workers[$lease.worker_id].status = 'awaiting_acceptance'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'verify'
        task_id = $task
        status = 'verified'
        changed_files = $changed
        changed_file_count = $changed.Count
        scope_valid = $true
        workspace_identity_valid = $true
        mutation_attribution_valid = [bool]$lease.mutation_attribution_verified
        result_fingerprint_valid = $true
        base_commit_valid = $true
        verification_passed = $true
      }
      exit 0
    }

    if ($Action -eq 'correct') {
      if ($lease.status -ne 'awaiting_verification') { Throw-GovernorError "result_not_ready" }
      $corrections = [int]$state.tasks[$task].corrections + 1
      if ($corrections -gt $MaxCorrections) { Throw-GovernorError "correction_budget_reached" }
      $state.tasks[$task].corrections = $corrections
      $state.tasks[$task].status = 'needs_correction'
      $state.tasks[$task].updated_at = $now
      $lease.status = 'needs_correction'
      $lease.result_fingerprint = $null
      $lease.updated_at = $now
      $state.workers[$lease.worker_id].status = 'leased'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{ ok = $true; action = 'correct'; task_id = $task; worker_id = $lease.worker_id; correction = $corrections; max_corrections = $MaxCorrections; reuse_same_worker = $true }
      exit 0
    }

    if ($Action -eq 'accept') {
      if ($lease.status -ne 'verified') { Throw-GovernorError "verification_required" }
      if (-not $CoordinatorAccepted) { Throw-GovernorError "coordinator_acceptance_required" }
      $lease.status = 'accepted'
      $lease.updated_at = $now
      $state.tasks[$task].status = 'accepted'
      $state.tasks[$task].updated_at = $now
      $state.workers[$lease.worker_id].status = 'idle'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{ ok = $true; action = 'accept'; task_id = $task; worker_id = $lease.worker_id; status = 'accepted'; worker_reusable = $true; automatic_merge = $false; automatic_cleanup = $false }
      exit 0
    }

    if ($Action -eq 'retire') {
      $lease.status = 'failed'
      $lease.updated_at = $now
      $state.tasks[$task].status = 'failed'
      $state.tasks[$task].updated_at = $now
      $state.workers[$lease.worker_id].status = 'retired'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{ ok = $true; action = 'retire'; task_id = $task; worker_id = $lease.worker_id; status = 'retired'; automatic_cleanup = $false }
      exit 0
    }

    if ($Action -eq 'release') {
      $lease.status = 'released'
      $lease.updated_at = $now
      $state.tasks[$task].status = 'released'
      $state.tasks[$task].updated_at = $now
      $state.workers[$lease.worker_id].status = 'idle'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{ ok = $true; action = 'release'; task_id = $task; worker_id = $lease.worker_id; automatic_merge = $false; automatic_cleanup = $false }
      exit 0
    }
  } finally {
    Release-StateLock $lock
  }
} catch {
  $code = if ($_.Exception.Message -match '^[a-z0-9_]+$') { $_.Exception.Message } else { 'internal_error' }
  Write-GovernorOutput @{ ok = $false; action = $Action; error = $code }
  exit 1
}
