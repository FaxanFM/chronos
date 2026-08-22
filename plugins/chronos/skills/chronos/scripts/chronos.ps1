param(
  [ValidateSet("inspect", "plan", "cleanup", "heartbeat", "supervise", "install-status")]
  [string]$Action = "inspect",
  [int]$MinAgeMinutes = 60,
  [int]$ProcessId = 0,
  [string]$CodexHome = $(if (-not [string]::IsNullOrWhiteSpace([string]$env:CODEX_HOME)) { [string]$env:CODEX_HOME } else { Join-Path $HOME ".codex" }),
  [ValidateRange(1, 10)]
  [int]$SampleSeconds = 2,
  [string]$HeartbeatInputPath,
  [string]$HeartbeatInspectorOutputPath,
  [switch]$HeartbeatInspectorAuthorized,
  [string]$HeartbeatStatePath,
  [string]$HeartbeatScope,
  [string]$HeartbeatAcknowledgeEventId,
  [string]$HeartbeatEventId,
  [string]$HeartbeatCorroboratingEventId,
  [ValidateSet("", "list", "plan", "fail-closed", "claim", "reclaim", "transport", "response", "verify")]
  [string]$HeartbeatInterventionAction = "",
  [string]$HeartbeatInterventionId,
  [ValidateRange(0, 2147483647)]
  [int]$HeartbeatInterventionVersion = 0,
  [string]$HeartbeatTargetId,
  [string]$HeartbeatTargetGeneration,
  [string]$HeartbeatGovernorId,
  [string]$HeartbeatClaimToken,
  [ValidateSet("", "accepted", "definite_failure", "unknown")]
  [string]$HeartbeatTransportResult = "",
  [ValidateSet("", "acknowledged", "outcome_reported", "declined", "user_authority_required", "remediation_failed")]
  [string]$HeartbeatTaskResponse = "",
  [ValidateSet("", "host_inventory", "host_test", "host_git")]
  [string]$HeartbeatVerificationSource = "",
  [ValidateSet("", "resolved", "active", "failed")]
  [string]$HeartbeatVerificationResult = "",
  [ValidateSet("", "ambiguous_target", "target_not_live", "transport_unavailable", "user_authority_required", "unsupported_action")]
  [string]$HeartbeatFailureReason = "",
  [ValidateSet("status", "initialize", "confirm-active", "reconcile-host", "discover", "cycle", "release")]
  [string]$SupervisionAction = "status",
  [string]$SupervisionStatePath,
  [string]$SupervisionHostInventoryPath,
  [string]$SupervisionSessionId,
  [string]$SupervisionSubjectId,
  [ValidateRange(0, [long]::MaxValue)]
  [long]$SupervisionSinceRevision = 0,
  [switch]$SupervisionConfirmRecurrenceStopped,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

# Heartbeats share the installed Chronos command surface.  The implementation
# remains a small internal module so inspection behavior stays backward-compatible.
if ($Action -eq 'heartbeat') {
  $heartbeatScript = Join-Path $PSScriptRoot 'heartbeat.ps1'
  if (-not (Test-Path -LiteralPath $heartbeatScript)) { throw 'heartbeat_module_missing' }
  if ($HeartbeatInterventionAction -and $HeartbeatAcknowledgeEventId) { throw 'heartbeat_arguments_conflict' }
  $heartbeatCommon = @{ Scope = $HeartbeatScope }
  if ($PSBoundParameters.ContainsKey('CodexHome')) { $heartbeatCommon.CodexHome = $CodexHome }
  if ($HeartbeatInterventionAction) {
    $heartbeatArguments = @{
      Action = 'intervention-' + $HeartbeatInterventionAction
      Scope = $HeartbeatScope
      EventId = $HeartbeatEventId
      CorroboratingEventId = $HeartbeatCorroboratingEventId
      InterventionId = $HeartbeatInterventionId
      InterventionVersion = $HeartbeatInterventionVersion
      TargetId = $HeartbeatTargetId
      TargetGeneration = $HeartbeatTargetGeneration
      GovernorId = $HeartbeatGovernorId
      ClaimToken = $HeartbeatClaimToken
      TransportResult = $HeartbeatTransportResult
      TaskResponse = $HeartbeatTaskResponse
      VerificationSource = $HeartbeatVerificationSource
      VerificationResult = $HeartbeatVerificationResult
      FailureReason = $HeartbeatFailureReason
    }
    if ($HeartbeatStatePath) { $heartbeatArguments.StatePath = $HeartbeatStatePath }
    if ($heartbeatCommon.ContainsKey('CodexHome')) { $heartbeatArguments.CodexHome = $heartbeatCommon.CodexHome }
    & $heartbeatScript @heartbeatArguments
  } elseif ($HeartbeatAcknowledgeEventId) {
    if ($HeartbeatStatePath) { & $heartbeatScript @heartbeatCommon -Action acknowledge -EventId $HeartbeatAcknowledgeEventId -StatePath $HeartbeatStatePath }
    else { & $heartbeatScript @heartbeatCommon -Action acknowledge -EventId $HeartbeatAcknowledgeEventId }
  } elseif (-not $HeartbeatInputPath -and -not $HeartbeatInspectorOutputPath) {
    if ($HeartbeatStatePath) { & $heartbeatScript @heartbeatCommon -Action status -StatePath $HeartbeatStatePath }
    else { & $heartbeatScript @heartbeatCommon -Action status }
  } elseif ($HeartbeatStatePath) {
    & $heartbeatScript @heartbeatCommon -Action cycle -InputPath $HeartbeatInputPath -InspectorOutputPath $HeartbeatInspectorOutputPath -InspectorAuthorized:$HeartbeatInspectorAuthorized -StatePath $HeartbeatStatePath
  } else {
    & $heartbeatScript @heartbeatCommon -Action cycle -InputPath $HeartbeatInputPath -InspectorOutputPath $HeartbeatInspectorOutputPath -InspectorAuthorized:$HeartbeatInspectorAuthorized
  }
  exit $LASTEXITCODE
}

# Supervision is passive local lifecycle discovery for one host-managed
# Governor task. Worker tasks do not run model turns or recurring checks.
if ($Action -eq 'supervise') {
  $supervisionScript = Join-Path $PSScriptRoot 'session-registry.ps1'
  if (-not (Test-Path -LiteralPath $supervisionScript)) { throw 'supervision_module_missing' }
  $arguments = @{
    Action = $SupervisionAction
    SinceRevision = $SupervisionSinceRevision
  }
  if ($SupervisionStatePath) { $arguments.StatePath = $SupervisionStatePath }
  if ($PSBoundParameters.ContainsKey('CodexHome')) { $arguments.CodexHome = $CodexHome }
  if ($SupervisionHostInventoryPath) { $arguments.HostInventoryPath = $SupervisionHostInventoryPath }
  if ($SupervisionSessionId) { $arguments.SessionId = $SupervisionSessionId }
  if ($SupervisionSubjectId) { $arguments.SubjectId = $SupervisionSubjectId }
  if ($SupervisionConfirmRecurrenceStopped) { $arguments.ConfirmRecurrenceStopped = $true }
  if ($Force) { $arguments.Force = $true }
  & $supervisionScript @arguments
  exit $LASTEXITCODE
}

function Get-ChronosPluginVersion {
  try {
    $manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\.codex-plugin\plugin.json'))
    $manifest = Get-Content -Raw -LiteralPath $manifestPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $version = ([string]$manifest.version).Trim()
    if ($version -match '^\d+\.\d+\.\d+$') { return $version }
  } catch {}
  "unavailable"
}

$script:ChronosPluginVersion = Get-ChronosPluginVersion

function Initialize-ChronosReadRoot {
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item -or -not $item.PSIsContainer -or
      ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $null }
  ([System.IO.Path]::GetFullPath($item.FullName).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar)
}

$script:ChronosReadRoot = Initialize-ChronosReadRoot $CodexHome

function Test-ChronosReadPath {
  param([string]$Path)
  if (-not $script:ChronosReadRoot -or [string]::IsNullOrWhiteSpace($Path)) { return $false }
  try { $fullPath = [System.IO.Path]::GetFullPath($Path) } catch { return $false }
  if (-not ($fullPath + $(if ((Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue).PSIsContainer) {
          [System.IO.Path]::DirectorySeparatorChar
        } else { "" })).StartsWith($script:ChronosReadRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $false
  }
  $cursor = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
  if (-not $cursor) { $cursor = Get-Item -LiteralPath (Split-Path -Parent $fullPath) -Force -ErrorAction SilentlyContinue }
  while ($cursor -and ($cursor.FullName.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar) -ne $script:ChronosReadRoot) {
    if ($cursor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
    $cursor = if ($cursor -is [System.IO.DirectoryInfo]) { $cursor.Parent } else { $cursor.Directory }
  }
  $null -ne $cursor
}

function Get-ChronosInstallStatus {
  $currentSource = 'standalone'
  try {
    $pluginRoot = Get-Item -LiteralPath ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))) -Force -ErrorAction Stop
    if ($pluginRoot.Parent -and $pluginRoot.Parent.Parent -and
        $pluginRoot.Parent.Name -eq 'chronos') {
      $currentSource = $pluginRoot.Parent.Parent.Name
    }
  } catch {}

  $sources = New-Object System.Collections.Generic.List[string]
  $cacheRoot = Join-Path $CodexHome 'plugins\cache'
  if (Test-ChronosReadPath $cacheRoot) {
    $marketplaces = @([System.IO.Directory]::EnumerateDirectories($cacheRoot) | Select-Object -First 32)
    foreach ($marketplacePath in $marketplaces) {
      $marketplace = Get-Item -LiteralPath $marketplacePath -Force -ErrorAction SilentlyContinue
      if (-not $marketplace -or
          ($marketplace.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
          -not (Test-ChronosReadPath $marketplace.FullName)) { continue }
      $pluginPath = Join-Path $marketplace.FullName 'chronos'
      if (-not (Test-ChronosReadPath $pluginPath)) { continue }
      $plugin = Get-Item -LiteralPath $pluginPath -Force -ErrorAction SilentlyContinue
      if (-not $plugin -or -not $plugin.PSIsContainer -or
          ($plugin.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { continue }

      $validPackage = $false
      foreach ($versionPath in @([System.IO.Directory]::EnumerateDirectories($plugin.FullName) | Select-Object -First 16)) {
        $version = Get-Item -LiteralPath $versionPath -Force -ErrorAction SilentlyContinue
        if (-not $version -or
            ($version.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
            -not (Test-ChronosReadPath $version.FullName)) { continue }
        $manifestPath = Join-Path $version.FullName '.codex-plugin\plugin.json'
        if (-not (Test-ChronosReadPath $manifestPath)) { continue }
        try {
          $manifestFile = Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
          if ($manifestFile.Length -gt 65536) { continue }
          $manifest = Get-Content -Raw -LiteralPath $manifestFile.FullName -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
          if ([string]$manifest.name -eq 'chronos' -and
              ([string]$manifest.version).Trim() -match '^\d+\.\d+\.\d+$') {
            $validPackage = $true
            break
          }
        } catch {}
      }
      if ($validPackage) { $sources.Add($marketplace.Name) }
    }
  }

  $sourceNames = @($sources | Sort-Object -Unique)
  $hasDirectorySource = $sourceNames -contains 'openai-curated-remote'
  $hasLegacyGitSource = $sourceNames -contains 'chronos'
  $cachedDuplicateSources = $sourceNames.Count -gt 1
  $legacyGitConfig = 'unavailable'
  $configPath = Join-Path $CodexHome 'config.toml'
  if (Test-ChronosReadPath $configPath) {
    try {
      $configFile = Get-Item -LiteralPath $configPath -Force -ErrorAction Stop
      if ($configFile.Length -le 1048576) {
        $legacyGitConfig = 'not_configured'
        $inLegacySection = $false
        foreach ($line in [System.IO.File]::ReadLines($configFile.FullName)) {
          $trimmed = $line.Trim()
          if ($trimmed -match '^\[(.+)\]$') {
            $section = $matches[1].Trim()
            $inLegacySection = $section -eq 'plugins."chronos@chronos"' -or
              $section -eq "plugins.'chronos@chronos'"
            continue
          }
          if ($inLegacySection -and $trimmed -match '^enabled\s*=\s*(true|false)\s*(?:#.*)?$') {
            $legacyGitConfig = if ($matches[1] -eq 'true') { 'enabled' } else { 'disabled' }
            break
          }
        }
      }
    } catch { $legacyGitConfig = 'unavailable' }
  }
  $canonicalSource = if ($hasDirectorySource) { 'openai-curated-remote' } elseif ($currentSource -ne 'standalone') { $currentSource } else { 'unavailable' }
  $sourceConflict = if ($currentSource -eq 'openai-curated-remote' -and $legacyGitConfig -eq 'enabled') {
    'CONFIRMED'
  } elseif ($hasDirectorySource -and $hasLegacyGitSource) {
    'POSSIBLE'
  } elseif ($sourceNames.Count -gt 0) { 'NONE' } else { 'UNAVAILABLE' }
  $recommendation = if ($sourceConflict -eq 'CONFIRMED') {
    'remove_legacy_git_install_then_start_new_task'
  } elseif ($sourceConflict -eq 'POSSIBLE') {
    'review_plugin_manager_sources'
  } else { 'none' }

  [pscustomobject][ordered]@{
    PluginVersion = $script:ChronosPluginVersion
    CurrentSource = $currentSource
    SourceObservation = if ($sourceNames.Count -gt 0) { 'cache_inventory_not_enabled_state' } else { 'unavailable' }
    CachedSourceCount = $sourceNames.Count
    CachedSources = if ($sourceNames.Count -gt 0) { $sourceNames -join ',' } else { 'none' }
    CachedDuplicateSources = $cachedDuplicateSources
    LegacyGitSourcePresent = $hasLegacyGitSource
    DirectorySourcePresent = $hasDirectorySource
    LegacyGitConfig = $legacyGitConfig
    SourceConflict = $sourceConflict
    CanonicalSource = $canonicalSource
    CurrentPluginIdentity = if ($currentSource -eq 'standalone') { 'standalone' } else { 'chronos@' + $currentSource }
    CanonicalPluginIdentity = if ($canonicalSource -eq 'unavailable') { 'unavailable' } else { 'chronos@' + $canonicalSource }
    SessionReloadRequired = $sourceConflict -eq 'CONFIRMED'
    RecommendedAction = $recommendation
  }
}

function Format-ChronosInstallValue($Value) {
  if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
  ([string]$Value).Replace(' ', '-')
}

$script:ChronosInstallStatus = Get-ChronosInstallStatus

if ($Action -eq 'install-status') {
  $installFields = [ordered]@{
    pluginVersion = $script:ChronosInstallStatus.PluginVersion
    currentSource = $script:ChronosInstallStatus.CurrentSource
    sourceObservation = $script:ChronosInstallStatus.SourceObservation
    cachedSourceCount = $script:ChronosInstallStatus.CachedSourceCount
    cachedSources = $script:ChronosInstallStatus.CachedSources
    cachedDuplicateSources = $script:ChronosInstallStatus.CachedDuplicateSources
    legacyGitSourcePresent = $script:ChronosInstallStatus.LegacyGitSourcePresent
    directorySourcePresent = $script:ChronosInstallStatus.DirectorySourcePresent
    legacyGitConfig = $script:ChronosInstallStatus.LegacyGitConfig
    sourceConflict = $script:ChronosInstallStatus.SourceConflict
    canonicalSource = $script:ChronosInstallStatus.CanonicalSource
    currentPluginIdentity = $script:ChronosInstallStatus.CurrentPluginIdentity
    canonicalPluginIdentity = $script:ChronosInstallStatus.CanonicalPluginIdentity
    sessionReloadRequired = $script:ChronosInstallStatus.SessionReloadRequired
    recommendedAction = $script:ChronosInstallStatus.RecommendedAction
  }
  $installText = @($installFields.GetEnumerator() | ForEach-Object {
      $_.Key + '=' + (Format-ChronosInstallValue $_.Value)
    }) -join ' '
  Write-Output ('CHRONOS INSTALL ' + $installText)
  exit 0
}

function Initialize-ChronosSqlite {
  if ("ChronosSqlite" -as [type]) { return $true }

  $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class ChronosSqlite : IDisposable {
    const int SQLITE_OK = 0;
    const int SQLITE_ROW = 100;
    const int SQLITE_DONE = 101;
    const int SQLITE_OPEN_READONLY = 0x00000001;
    IntPtr db;

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_open_v2(IntPtr filename, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    static extern int sqlite3_prepare16_v2(IntPtr db, string sql, int bytes, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_column_count(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_column_text16(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_busy_timeout(IntPtr db, int milliseconds);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_errmsg16(IntPtr db);

    public static ChronosSqlite OpenReadOnly(string path) {
        byte[] bytes = Encoding.UTF8.GetBytes(path + "\0");
        IntPtr pointer = Marshal.AllocHGlobal(bytes.Length);
        try {
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            IntPtr handle;
            int result = sqlite3_open_v2(pointer, out handle, SQLITE_OPEN_READONLY, IntPtr.Zero);
            if (result != SQLITE_OK) {
                string message = handle == IntPtr.Zero
                    ? "SQLite read-only open failed."
                    : Marshal.PtrToStringUni(sqlite3_errmsg16(handle));
                if (handle != IntPtr.Zero) sqlite3_close(handle);
                throw new InvalidOperationException(message);
            }
            sqlite3_busy_timeout(handle, 1000);
            return new ChronosSqlite { db = handle };
        } finally {
            Marshal.FreeHGlobal(pointer);
        }
    }

    public List<string[]> Query(string sql) {
        IntPtr statement;
        int result = sqlite3_prepare16_v2(db, sql, -1, out statement, IntPtr.Zero);
        if (result != SQLITE_OK) {
            throw new InvalidOperationException(Marshal.PtrToStringUni(sqlite3_errmsg16(db)));
        }

        try {
            var rows = new List<string[]>();
            int columns = sqlite3_column_count(statement);
            while ((result = sqlite3_step(statement)) == SQLITE_ROW) {
                var row = new string[columns];
                for (int i = 0; i < columns; i++) {
                    IntPtr value = sqlite3_column_text16(statement, i);
                    row[i] = value == IntPtr.Zero ? null : Marshal.PtrToStringUni(value);
                }
                rows.Add(row);
            }
            if (result != SQLITE_DONE) {
                throw new InvalidOperationException(Marshal.PtrToStringUni(sqlite3_errmsg16(db)));
            }
            return rows;
        } finally {
            sqlite3_finalize(statement);
        }
    }

    public void Dispose() {
        if (db != IntPtr.Zero) {
            sqlite3_close(db);
            db = IntPtr.Zero;
        }
    }
}
'@

  try {
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    $true
  } catch {
    $false
  }
}

function Get-LogDbSample {
  $databasePath = Join-Path $CodexHome "logs_2.sqlite"
  $walPath = "$databasePath-wal"
  $shmPath = "$databasePath-shm"
  $capturedAt = Get-Date
  $databaseFile = if (Test-ChronosReadPath $databasePath) { Get-Item -LiteralPath $databasePath -ErrorAction SilentlyContinue } else { $null }
  $walFile = if (Test-ChronosReadPath $walPath) { Get-Item -LiteralPath $walPath -ErrorAction SilentlyContinue } else { $null }
  $shmFile = if (Test-ChronosReadPath $shmPath) { Get-Item -LiteralPath $shmPath -ErrorAction SilentlyContinue } else { $null }
  $walBeforeBytes = if ($walFile) { [long]$walFile.Length } else { 0L }
  $walBeforeTicks = if ($walFile) { [long]$walFile.LastWriteTimeUtc.Ticks } else { 0L }
  $shmBeforeBytes = if ($shmFile) { [long]$shmFile.Length } else { 0L }
  $shmBeforeTicks = if ($shmFile) { [long]$shmFile.LastWriteTimeUtc.Ticks } else { 0L }

  $sample = [ordered]@{
    Present = $null -ne $databaseFile
    QueryOk = $false
    PageMetricsOk = $false
    SequenceOk = $false
    LevelRowsOk = $false
    CapturedAt = $capturedAt
    DatabaseBytes = if ($databaseFile) { [long]$databaseFile.Length } else { 0L }
    WalBytes = $walBeforeBytes
    WalWriteTicks = $walBeforeTicks
    ShmBytes = $shmBeforeBytes
    ShmWriteTicks = $shmBeforeTicks
    SqliteOpenMode = "logical_readonly"
    SqliteJournalMode = "unknown"
    SqliteSidecarMutationPossible = $null
    SqliteSidecarMutationObserved = $false
    PageSize = 0L
    PageCount = 0L
    FreelistCount = 0L
    Sequence = $null
    RecentRows = 0
    TraceRows = 0
  }

  if (-not $databaseFile -or -not (Initialize-ChronosSqlite)) {
    return [pscustomobject]$sample
  }

  $database = $null
  try {
    $database = [ChronosSqlite]::OpenReadOnly($databasePath)
    try {
      try {
        $journalRows = $database.Query("PRAGMA journal_mode")
        if ($journalRows.Count -gt 0 -and $journalRows[0].Count -gt 0) {
          $sample.SqliteJournalMode = ([string]$journalRows[0][0]).ToLowerInvariant()
        }
      } catch { $sample.SqliteJournalMode = "unknown" }
      $pageSizeRows = $database.Query("PRAGMA page_size")
      $pageCountRows = $database.Query("PRAGMA page_count")
      $freelistRows = $database.Query("PRAGMA freelist_count")
      $sample.PageSize = [long]$pageSizeRows[0][0]
      $sample.PageCount = [long]$pageCountRows[0][0]
      $sample.FreelistCount = [long]$freelistRows[0][0]
      $sample.PageMetricsOk = $true
    } catch { $sample.PageMetricsOk = $false }
    try {
      $sequenceRows = $database.Query("SELECT seq FROM sqlite_sequence WHERE name='logs'")
      if ($sequenceRows.Count -gt 0) { $sample.Sequence = [long]$sequenceRows[0][0] }
      $sample.SequenceOk = $true
    } catch { $sample.SequenceOk = $false }
    try {
      $levelRows = $database.Query(
        "SELECT level, COUNT(*) FROM (SELECT level FROM logs ORDER BY id DESC LIMIT 2000) GROUP BY level"
      )
      foreach ($row in $levelRows) {
        $count = [int]$row[1]
        $sample.RecentRows += $count
        if ($row[0] -eq "TRACE") { $sample.TraceRows = $count }
      }
      $sample.LevelRowsOk = $true
    } catch { $sample.LevelRowsOk = $false }
    $sample.QueryOk = $sample.PageMetricsOk -or $sample.SequenceOk -or $sample.LevelRowsOk
  } catch {
    $sample.QueryOk = $false
  } finally {
    if ($database) { $database.Dispose() }
  }

  $walAfter = Get-Item -LiteralPath $walPath -ErrorAction SilentlyContinue
  $shmAfter = Get-Item -LiteralPath $shmPath -ErrorAction SilentlyContinue
  $sample.SqliteSidecarMutationPossible = $true
  $sample.SqliteSidecarMutationObserved =
    ([bool]$walFile -ne [bool]$walAfter) -or ([bool]$shmFile -ne [bool]$shmAfter) -or
    ($walFile -and $walAfter -and (
        $walBeforeBytes -ne [long]$walAfter.Length -or
        $walBeforeTicks -ne [long]$walAfter.LastWriteTimeUtc.Ticks
      )) -or
    ($shmFile -and $shmAfter -and (
        $shmBeforeBytes -ne [long]$shmAfter.Length -or
        $shmBeforeTicks -ne [long]$shmAfter.LastWriteTimeUtc.Ticks
      ))
  $sample.WalBytes = if ($walAfter) { [long]$walAfter.Length } else { 0L }
  $sample.WalWriteTicks = if ($walAfter) { [long]$walAfter.LastWriteTimeUtc.Ticks } else { 0L }
  $sample.ShmBytes = if ($shmAfter) { [long]$shmAfter.Length } else { 0L }
  $sample.ShmWriteTicks = if ($shmAfter) { [long]$shmAfter.LastWriteTimeUtc.Ticks } else { 0L }

  [pscustomobject]$sample
}

function Get-LogDbMetrics($before, $after) {
  $elapsedSeconds = [math]::Max(0.001, ($after.CapturedAt - $before.CapturedAt).TotalSeconds)
  $rate = $null
  if ($before.SequenceOk -and $after.SequenceOk -and $null -ne $before.Sequence -and $null -ne $after.Sequence) {
    $sequenceDelta = [long]$after.Sequence - [long]$before.Sequence
    $rate = [math]::Round([math]::Max(0L, $sequenceDelta) / $elapsedSeconds, 1)
  }

  $tracePercent = $null
  if ($after.LevelRowsOk -and $after.RecentRows -gt 0) {
    $tracePercent = [math]::Round(($after.TraceRows * 100.0) / $after.RecentRows, 1)
  }

  $reclaimableBytes = 0L
  if ($after.PageMetricsOk) {
    $reclaimableBytes = $after.FreelistCount * $after.PageSize
  }

  [pscustomobject]@{
    Present = $after.Present
    QueryOk = $after.QueryOk
    Availability = if ($after.PageMetricsOk -and $after.SequenceOk -and $after.LevelRowsOk) {
      "full"
    } elseif ($after.QueryOk) {
      "partial"
    } else {
      "unavailable"
    }
    PageMetricsOk = $after.PageMetricsOk
    SequenceOk = $after.SequenceOk
    LevelRowsOk = $after.LevelRowsOk
    DatabaseGiB = if ($after.Present) { [math]::Round($after.DatabaseBytes / 1GB, 2) } else { $null }
    ReclaimableGiB = if ($after.PageMetricsOk) { [math]::Round($reclaimableBytes / 1GB, 2) } else { $null }
    WalMiB = if ($after.Present) { [math]::Round($after.WalBytes / 1MB, 1) } else { $null }
    WalActive = $after.WalWriteTicks -gt 0 -and $after.WalWriteTicks -ne $before.WalWriteTicks
    SqliteOpenMode = $after.SqliteOpenMode
    SqliteJournalMode = $after.SqliteJournalMode
    SqliteSidecarMutationPossible = $after.SqliteSidecarMutationPossible
    SqliteSidecarMutationObserved = [bool]$before.SqliteSidecarMutationObserved -or
      [bool]$after.SqliteSidecarMutationObserved
    Sequence = $after.Sequence
    InsertRate = $rate
    TracePercent = $tracePercent
  }
}

function Get-FilesystemHelperHealth {
  $health = [ordered]@{
    Present = $false
    ReadOk = $false
    Level = "UNAVAILABLE"
    CopyFailure = $false
    LaunchFailure = $false
    PcRestartAdvised = $false
  }

  $cutoff = (Get-Date).ToUniversalTime().AddHours(-24)
  $sandboxHome = Join-Path $CodexHome ".sandbox"
  $logs = @(@($CodexHome, $sandboxHome) | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -Filter "sandbox*.log" -File -ErrorAction SilentlyContinue
  } | Where-Object {
      (Test-ChronosReadPath $_.FullName) -and $_.LastWriteTimeUtc -ge $cutoff
    } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 2)

  if (-not $logs.Count) {
    return [pscustomobject]$health
  }

  $health.Present = $true
  $copyMessage = "helper copy failed for command-runner: remove stale helper destination"
  $launchMessages = @(
    "CreateProcessWithLogonW failed: 5",
    "windows sandbox: CreateProcessWithLogonW failed: 5"
  )
  $markerCutoff = [DateTimeOffset]::Now.AddMinutes(-15)
  $latestCopyFailure = [DateTimeOffset]::MinValue
  $latestLaunchFailure = [DateTimeOffset]::MinValue
  $latestSuccess = [DateTimeOffset]::MinValue

  foreach ($log in $logs) {
    try {
      $lines = @(Get-Content -LiteralPath $log.FullName -Tail 4000 -ErrorAction Stop)
      $health.ReadOk = $true
    } catch {
      continue
    }

    foreach ($line in $lines) {
      $eventMatch = [regex]::Match(
        $line,
        "^\[(?<timestamp>\d{4}-\d{2}-\d{2}(?:T|\s)\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)(?:\s+[^\]]*)?\]\s*(?<message>.*)$"
      )
      if (-not $eventMatch.Success) { continue }

      $timestamp = [DateTimeOffset]::MinValue
      if (-not [DateTimeOffset]::TryParse(
        $eventMatch.Groups["timestamp"].Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
        [ref]$timestamp
      )) { continue }
      if ($timestamp -lt $markerCutoff) { continue }
      $message = $eventMatch.Groups["message"].Value.Trim()

      if ($message.Equals($copyMessage, [System.StringComparison]::OrdinalIgnoreCase) -and
          $timestamp -gt $latestCopyFailure) {
        $latestCopyFailure = $timestamp
      }
      if ($launchMessages -contains $message -and
          $timestamp -gt $latestLaunchFailure) {
        $latestLaunchFailure = $timestamp
      }
      if ($message -match '^SUCCESS:\s+\S.*$' -and
          $timestamp -gt $latestSuccess) {
        $latestSuccess = $timestamp
      }
    }
  }

  if (-not $health.ReadOk) {
    return [pscustomobject]$health
  }

  $health.CopyFailure = $latestCopyFailure -ge $markerCutoff
  $health.LaunchFailure = $latestLaunchFailure -ge $markerCutoff -and
    $latestLaunchFailure -gt $latestSuccess

  if ($health.LaunchFailure) {
    $health.Level = "CRITICAL"
    $health.PcRestartAdvised = $true
  } elseif ($health.CopyFailure) {
    $health.Level = "WARNING"
  } else {
    $health.Level = "HEALTHY"
  }

  [pscustomobject]$health
}

function Get-BoundedFileTail {
  param(
    [string]$Path,
    [int]$MaxBytes = 2097152
  )

  $stream = $null
  if (-not (Test-ChronosReadPath $Path)) { return "" }
  try {
    $stream = [System.IO.FileStream]::new(
      $Path,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::ReadWrite
    )
    if ($stream.Length -le 0) { return "" }

    $bytesToRead = [int][math]::Min([long]$MaxBytes, [long]$stream.Length)
    $start = [math]::Max(0L, ([long]$stream.Length - [long]$bytesToRead))
    $null = $stream.Seek($start, [System.IO.SeekOrigin]::Begin)
    $buffer = [byte[]]::new($bytesToRead)
    $offset = 0
    while ($offset -lt $bytesToRead) {
      $read = $stream.Read($buffer, $offset, $bytesToRead - $offset)
      if ($read -le 0) { break }
      $offset += $read
    }

    $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $offset)
    if ($start -gt 0) {
      $newline = $text.IndexOf("`n", [System.StringComparison]::Ordinal)
      if ($newline -lt 0) { return "" }
      $text = $text.Substring($newline + 1)
    }
    $text
  } catch {
    ""
  } finally {
    if ($stream) { $stream.Dispose() }
  }
}

function Get-BoundedFileHead {
  param([string]$Path, [int]$MaxBytes = 65536)
  $stream = $null
  if (-not (Test-ChronosReadPath $Path)) { return "" }
  try {
    $stream = [System.IO.FileStream]::new(
      $Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::ReadWrite
    )
    $bytesToRead = [int][math]::Min([long]$MaxBytes, [long]$stream.Length)
    if ($bytesToRead -le 0) { return "" }
    $buffer = [byte[]]::new($bytesToRead)
    $offset = 0
    while ($offset -lt $bytesToRead) {
      $read = $stream.Read($buffer, $offset, $bytesToRead - $offset)
      if ($read -le 0) { break }
      $offset += $read
    }
    $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $offset)
    if ($stream.Length -gt $bytesToRead) {
      $newline = $text.LastIndexOf("`n", [System.StringComparison]::Ordinal)
      if ($newline -ge 0) { $text = $text.Substring(0, $newline + 1) }
    }
    $text
  } catch { "" } finally { if ($stream) { $stream.Dispose() } }
}

function Get-RecentSessionFiles {
  $windowEnd = (Get-Date).ToUniversalTime()
  $cutoff = $windowEnd.AddHours(-6)
  $sessionsRoot = Join-Path $CodexHome "sessions"
  if (-not (Test-Path -LiteralPath $sessionsRoot -PathType Container) -or
      -not (Test-ChronosReadPath $sessionsRoot)) {
    return [pscustomobject]@{
      Files = @(); EligibleCount = 0; SelectedCount = 0; Capped = $false
      InventoryTimedOut = $false; InventoryEntries = 0; InventoryEntryLimit = 20000
      InventoryEntryLimitHit = $false
      WindowHours = 6; WindowStartUtc = $cutoff.ToString('o'); WindowEndUtc = $windowEnd.ToString('o')
    }
  }

  $eligibleCount = 0
  $inventoryEntries = 0
  $inventoryEntryLimit = 20000
  $inventoryEntryLimitHit = $false
  $inventoryTimedOut = $false
  $inventoryDeadline = [DateTimeOffset]::UtcNow.AddSeconds(3)
  $newest = [System.Collections.Generic.List[object]]::new()
  $directories = [System.Collections.Generic.Stack[string]]::new()
  $directories.Push($sessionsRoot)
  while ($directories.Count -gt 0) {
    if ([DateTimeOffset]::UtcNow -ge $inventoryDeadline) { $inventoryTimedOut = $true; break }
    $directory = $directories.Pop()
    try { $entryPaths = [System.IO.Directory]::EnumerateFileSystemEntries($directory) } catch { continue }
    foreach ($entryPath in $entryPaths) {
      if ([DateTimeOffset]::UtcNow -ge $inventoryDeadline) { $inventoryTimedOut = $true; break }
      $inventoryEntries++
      if ($inventoryEntries -gt $inventoryEntryLimit) {
        $inventoryEntryLimitHit = $true
        break
      }
      try { $entry = Get-Item -LiteralPath $entryPath -Force -ErrorAction Stop } catch { continue }
      if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
      if ($entry.PSIsContainer) {
        if (Test-ChronosReadPath $entry.FullName) { $directories.Push($entry.FullName) }
        continue
      }
      if ($entry.Extension -ne ".jsonl" -or -not (Test-ChronosReadPath $entry.FullName) -or
          $entry.LastWriteTimeUtc -lt $cutoff) { continue }
      $eligibleCount++
      $newest.Add($entry)
      if ($newest.Count -gt 8) {
        $oldest = @($newest | Sort-Object LastWriteTimeUtc, FullName | Select-Object -First 1)[0]
        $null = $newest.Remove($oldest)
      }
    }
    if ($inventoryTimedOut -or $inventoryEntryLimitHit) { break }
  }
  $selected = @($newest | Sort-Object LastWriteTimeUtc -Descending)
  [pscustomobject]@{
    Files = $selected
    EligibleCount = $eligibleCount
    SelectedCount = $selected.Count
    Capped = $inventoryTimedOut -or $inventoryEntryLimitHit -or $eligibleCount -gt $selected.Count
    InventoryTimedOut = $inventoryTimedOut
    InventoryEntries = [math]::Min($inventoryEntries, $inventoryEntryLimit)
    InventoryEntryLimit = $inventoryEntryLimit
    InventoryEntryLimitHit = $inventoryEntryLimitHit
    WindowHours = 6
    WindowStartUtc = $cutoff.ToString('o')
    WindowEndUtc = $windowEnd.ToString('o')
  }
}

function Get-RecordTimestamp {
  param($Record)
  foreach ($name in @("timestamp", "created_at")) {
    $property = $Record.PSObject.Properties[$name]
    if (-not $property -or -not $property.Value) { continue }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse(
      [string]$property.Value,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
      [ref]$parsed
    )) { return $parsed }
  }
  $null
}

function Get-RecordHash {
  param([string]$Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
  } finally {
    $sha.Dispose()
  }
}

function Move-RolloutJsonWhitespace {
  param([string]$Text, [ref]$Index)
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -in @(' ', "`t", "`r", "`n")) { $Index.Value++ }
}

function Read-RolloutJsonString {
  param([string]$Text, [ref]$Index)
  if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne '"') { throw 'invalid' }
  $start = $Index.Value
  $Index.Value++
  while ($Index.Value -lt $Text.Length) {
    $character = $Text[$Index.Value]
    if ([int][char]$character -lt 0x20) { throw 'invalid' }
    if ($character -eq '"') {
      $Index.Value++
      $decoded = $Text.Substring($start, $Index.Value - $start) | ConvertFrom-Json -ErrorAction Stop
      if (-not ($decoded -is [string])) { throw 'invalid' }
      return $decoded.Normalize([Text.NormalizationForm]::FormC)
    }
    if ($character -eq '\') {
      $Index.Value++
      if ($Index.Value -ge $Text.Length) { throw 'invalid' }
      if ($Text[$Index.Value] -eq 'u') {
        if ($Index.Value + 4 -ge $Text.Length -or $Text.Substring($Index.Value + 1, 4) -notmatch '^[0-9A-Fa-f]{4}$') { throw 'invalid' }
        $Index.Value += 5
        continue
      }
      if ($Text[$Index.Value] -notin @('"', '\', '/', 'b', 'f', 'n', 'r', 't')) { throw 'invalid' }
    }
    $Index.Value++
  }
  throw 'invalid'
}

function Assert-RolloutJsonValue {
  param([string]$Text, [ref]$Index, [ref]$Nodes, [int]$Depth)
  if ($Depth -gt 16) { throw 'invalid' }
  Move-RolloutJsonWhitespace $Text $Index
  if ($Index.Value -ge $Text.Length) { throw 'invalid' }
  $Nodes.Value++
  if ($Nodes.Value -gt 4096) { throw 'invalid' }
  $character = $Text[$Index.Value]
  if ($character -eq '"') { [void](Read-RolloutJsonString $Text $Index); return }
  if ($character -eq '{') {
    $Index.Value++
    Move-RolloutJsonWhitespace $Text $Index
    $keys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq '}') { $Index.Value++; return }
    while ($true) {
      Move-RolloutJsonWhitespace $Text $Index
      if (-not $keys.Add((Read-RolloutJsonString $Text $Index))) { throw 'invalid' }
      Move-RolloutJsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne ':') { throw 'invalid' }
      $Index.Value++
      Assert-RolloutJsonValue $Text $Index $Nodes ($Depth + 1)
      Move-RolloutJsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length) { throw 'invalid' }
      if ($Text[$Index.Value] -eq '}') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { throw 'invalid' }
      $Index.Value++
    }
  }
  if ($character -eq '[') {
    $Index.Value++
    Move-RolloutJsonWhitespace $Text $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq ']') { $Index.Value++; return }
    while ($true) {
      Assert-RolloutJsonValue $Text $Index $Nodes ($Depth + 1)
      Move-RolloutJsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length) { throw 'invalid' }
      if ($Text[$Index.Value] -eq ']') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { throw 'invalid' }
      $Index.Value++
    }
  }
  $start = $Index.Value
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -notin @(',', ']', '}', ' ', "`t", "`r", "`n")) { $Index.Value++ }
  if ($Text.Substring($start, $Index.Value - $start) -notmatch '^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$') { throw 'invalid' }
}

function Test-RolloutJsonUnambiguous {
  param([string]$Text)
  try {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $index = 0; $nodes = 0
    Assert-RolloutJsonValue $Text ([ref]$index) ([ref]$nodes) 0
    Move-RolloutJsonWhitespace $Text ([ref]$index)
    return $index -eq $Text.Length
  } catch { return $false }
}

function Get-TextFingerprint {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return $null }
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $algorithm.Dispose()
  }
}

function ConvertFrom-StructuredArguments {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) {
    try {
      if (-not (Test-RolloutJsonUnambiguous $Value)) { return $null }
      return ($Value | ConvertFrom-Json -ErrorAction Stop)
    } catch { return $null }
  }
  if ($Value -is [pscustomobject] -or $Value -is [hashtable]) { return $Value }
  $null
}

function Get-CanonicalPrefixFingerprint {
  param($Object)
  if (-not $Object) { return $null }
  foreach ($name in @("proposed_prefix", "prefix_rule", "command_prefix")) {
    $property = $Object.PSObject.Properties[$name]
    if (-not $property -or $null -eq $property.Value) { continue }
    $tokens = @($property.Value | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($tokens.Count -eq 0 -or $tokens.Count -gt 16) { continue }
    return Get-TextFingerprint ((@($tokens | ForEach-Object { $_.ToLowerInvariant() }) | ConvertTo-Json -Compress))
  }
  $null
}

function Get-InspectionOperationClass {
  param($Object)
  $operation = Get-SafeCategory $Object @("operation_class", "operation", "tool_name", "tool")
  if ($operation) { return $operation }
  if (-not $Object) { return $null }
  foreach ($name in @("proposed_prefix", "prefix_rule", "command_prefix")) {
    $property = $Object.PSObject.Properties[$name]
    if (-not $property -or $null -eq $property.Value) { continue }
    $tokens = @($property.Value)
    if ($tokens.Count -eq 0) { continue }
    $candidate = [System.IO.Path]::GetFileNameWithoutExtension(([string]$tokens[0]).Trim()).ToLowerInvariant()
    if ($candidate -in @("get-content", "rg", "get-childitem", "select-string", "resolve-path", "test-path")) {
      return $candidate
    }
  }
  $null
}

function Get-BoundedPrefixRuleBlocks {
  param(
    [string]$Path,
    [int]$MaxBytes = 2097152,
    [int]$MaxRules = 2048,
    [int]$MaxRuleChars = 65536
  )
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $MaxBytes) {
    return [pscustomobject]@{ Blocks = @(); Complete = $false }
  }
  try { $text = [System.IO.File]::ReadAllText($item.FullName) } catch {
    return [pscustomobject]@{ Blocks = @(); Complete = $false }
  }
  $blocks = [System.Collections.Generic.List[string]]::new()
  $index = 0
  while ($index -lt $text.Length) {
    if ($blocks.Count -ge $MaxRules) {
      return [pscustomobject]@{ Blocks = @($blocks); Complete = $false }
    }
    $character = $text[$index]
    if ($character -eq '#') {
      $newline = $text.IndexOf("`n", $index)
      $index = if ($newline -lt 0) { $text.Length } else { $newline + 1 }
      continue
    }
    if ($character -eq '"' -or $character -eq "'") {
      $quote = $character
      $triple = $index + 2 -lt $text.Length -and
        $text[$index + 1] -eq $quote -and $text[$index + 2] -eq $quote
      $index += $(if ($triple) { 3 } else { 1 })
      $escaped = $false
      while ($index -lt $text.Length) {
        if ($escaped) { $escaped = $false; $index++; continue }
        if ($text[$index] -eq '\') { $escaped = $true; $index++; continue }
        if ($triple -and $index + 2 -lt $text.Length -and
          $text[$index] -eq $quote -and $text[$index + 1] -eq $quote -and $text[$index + 2] -eq $quote) {
          $index += 3
          break
        }
        if (-not $triple -and $text[$index] -eq $quote) { $index++; break }
        $index++
      }
      continue
    }
    $name = "prefix_rule"
    $nameLength = $name.Length
    $nameMatches = $index + $nameLength -le $text.Length -and
      [string]::Compare($text, $index, $name, 0, $nameLength, $true, [cultureinfo]::InvariantCulture) -eq 0
    $leftBoundary = $index -eq 0 -or -not [char]::IsLetterOrDigit($text[$index - 1]) -and $text[$index - 1] -ne '_'
    $rightIndex = $index + $nameLength
    $rightBoundary = $rightIndex -ge $text.Length -or -not [char]::IsLetterOrDigit($text[$rightIndex]) -and $text[$rightIndex] -ne '_'
    if (-not ($nameMatches -and $leftBoundary -and $rightBoundary)) { $index++; continue }
    $open = $rightIndex
    while ($open -lt $text.Length -and [char]::IsWhiteSpace($text[$open])) { $open++ }
    if ($open -ge $text.Length -or $text[$open] -ne '(') { $index = $rightIndex; continue }
    $depth = 0
    $inString = $false
    $quote = [char]0
    $triple = $false
    $escaped = $false
    $comment = $false
    $closed = $false
    $limit = [math]::Min($text.Length - 1, $open + $MaxRuleChars - 1)
    for ($cursor = $open; $cursor -le $limit; $cursor++) {
      $character = $text[$cursor]
      if ($comment) {
        if ($character -eq "`n") { $comment = $false }
        continue
      }
      if ($inString) {
        if ($escaped) { $escaped = $false; continue }
        if ($character -eq '\') { $escaped = $true; continue }
        if ($triple -and $cursor + 2 -lt $text.Length -and
          $text[$cursor] -eq $quote -and $text[$cursor + 1] -eq $quote -and $text[$cursor + 2] -eq $quote) {
          $inString = $false
          $cursor += 2
        } elseif (-not $triple -and $character -eq $quote) { $inString = $false }
        continue
      }
      if ($character -eq '#') { $comment = $true; continue }
      if ($character -eq '"' -or $character -eq "'") {
        $inString = $true
        $quote = $character
        $triple = $cursor + 2 -lt $text.Length -and
          $text[$cursor + 1] -eq $quote -and $text[$cursor + 2] -eq $quote
        if ($triple) { $cursor += 2 }
        continue
      }
      if ($character -eq '(') { $depth++; continue }
      if ($character -eq ')') {
        $depth--
        if ($depth -eq 0) {
          $blocks.Add($text.Substring($index, $cursor - $index + 1))
          $index = $cursor + 1
          $closed = $true
          break
        }
      }
    }
    if (-not $closed) { return [pscustomobject]@{ Blocks = @($blocks); Complete = $false } }
  }
  [pscustomobject]@{ Blocks = @($blocks); Complete = $true }
}

function Get-RuleLiteralTokens {
  param([string]$Text)
  $tokens = [System.Collections.Generic.List[string]]::new()
  $index = 0
  while ($index -lt $Text.Length) {
    if ($Text[$index] -eq '#') {
      $newline = $Text.IndexOf("`n", $index)
      $index = if ($newline -lt 0) { $Text.Length } else { $newline + 1 }
      continue
    }
    $quoteIndex = $index
    $isRaw = ($Text[$index] -eq 'r' -or $Text[$index] -eq 'R') -and
      $index + 1 -lt $Text.Length -and $Text[$index + 1] -in @('"', "'")
    if ($isRaw) {
      $quoteIndex++
    }
    if ($Text[$quoteIndex] -notin @('"', "'")) { $index++; continue }
    $quote = $Text[$quoteIndex]
    $triple = $quoteIndex + 2 -lt $Text.Length -and
      $Text[$quoteIndex + 1] -eq $quote -and $Text[$quoteIndex + 2] -eq $quote
    $cursor = $quoteIndex + $(if ($triple) { 3 } else { 1 })
    $value = [System.Text.StringBuilder]::new()
    while ($cursor -lt $Text.Length) {
      if ($triple -and $cursor + 2 -lt $Text.Length -and
          $Text[$cursor] -eq $quote -and $Text[$cursor + 1] -eq $quote -and
          $Text[$cursor + 2] -eq $quote) {
        $cursor += 3
        break
      }
      if (-not $triple -and $Text[$cursor] -eq $quote) { $cursor++; break }
      if ($Text[$cursor] -eq '\' -and $cursor + 1 -lt $Text.Length) {
        if ($isRaw -and $Text[$cursor + 1] -notin @($quote, "`r", "`n")) {
          $null = $value.Append($Text[$cursor])
          $cursor++
        } else {
          $null = $value.Append($Text[$cursor + 1])
          $cursor += 2
        }
        continue
      }
      $null = $value.Append($Text[$cursor])
      $cursor++
    }
    $tokens.Add($value.ToString())
    $index = $cursor
  }
  @($tokens)
}

function Split-RuleCommaSegments {
  param([string]$Text)
  $segments = [System.Collections.Generic.List[string]]::new()
  $start = 0
  $depth = 0
  $inString = $false
  $quote = [char]0
  $triple = $false
  $escaped = $false
  $comment = $false
  for ($cursor = 0; $cursor -lt $Text.Length; $cursor++) {
    $character = $Text[$cursor]
    if ($comment) { if ($character -eq "`n") { $comment = $false }; continue }
    if ($inString) {
      if ($escaped) { $escaped = $false; continue }
      if ($character -eq '\') { $escaped = $true; continue }
      if ($triple -and $cursor + 2 -lt $Text.Length -and
          $Text[$cursor] -eq $quote -and $Text[$cursor + 1] -eq $quote -and
          $Text[$cursor + 2] -eq $quote) {
        $inString = $false
        $cursor += 2
      } elseif (-not $triple -and $character -eq $quote) { $inString = $false }
      continue
    }
    if ($character -eq '#') { $comment = $true; continue }
    if ($character -in @('"', "'")) {
      $inString = $true
      $quote = $character
      $triple = $cursor + 2 -lt $Text.Length -and
        $Text[$cursor + 1] -eq $quote -and $Text[$cursor + 2] -eq $quote
      if ($triple) { $cursor += 2 }
      continue
    }
    if ($character -in @('(', '[', '{')) { $depth++; continue }
    if ($character -in @(')', ']', '}')) {
      $depth--
      if ($depth -lt 0) {
        return [pscustomobject]@{ Complete = $false; Segments = @() }
      }
      continue
    }
    if ($character -eq ',' -and $depth -eq 0) {
      $segments.Add($Text.Substring($start, $cursor - $start))
      $start = $cursor + 1
    }
  }
  if ($inString -or $depth -ne 0) {
    return [pscustomobject]@{ Complete = $false; Segments = @() }
  }
  $segments.Add($Text.Substring($start))
  [pscustomobject]@{ Complete = $true; Segments = @($segments) }
}

function ConvertFrom-RuleSingleLiteral {
  param([string]$Text)
  $cursor = 0
  while ($cursor -lt $Text.Length) {
    if ([char]::IsWhiteSpace($Text[$cursor])) { $cursor++; continue }
    if ($Text[$cursor] -eq '#') {
      $newline = $Text.IndexOf("`n", $cursor)
      $cursor = if ($newline -lt 0) { $Text.Length } else { $newline + 1 }
      continue
    }
    break
  }
  if ($cursor -ge $Text.Length) {
    return [pscustomobject]@{ Complete = $false; Value = $null }
  }
  $isRaw = ($Text[$cursor] -eq 'r' -or $Text[$cursor] -eq 'R') -and
    $cursor + 1 -lt $Text.Length -and $Text[$cursor + 1] -in @('"', "'")
  if ($isRaw) { $cursor++ }
  if ($Text[$cursor] -notin @('"', "'")) {
    return [pscustomobject]@{ Complete = $false; Value = $null }
  }
  $quote = $Text[$cursor]
  $triple = $cursor + 2 -lt $Text.Length -and
    $Text[$cursor + 1] -eq $quote -and $Text[$cursor + 2] -eq $quote
  $cursor += $(if ($triple) { 3 } else { 1 })
  $value = [System.Text.StringBuilder]::new()
  $closed = $false
  while ($cursor -lt $Text.Length) {
    if ($triple -and $cursor + 2 -lt $Text.Length -and
        $Text[$cursor] -eq $quote -and $Text[$cursor + 1] -eq $quote -and
        $Text[$cursor + 2] -eq $quote) {
      $cursor += 3
      $closed = $true
      break
    }
    if (-not $triple -and $Text[$cursor] -eq $quote) {
      $cursor++
      $closed = $true
      break
    }
    if ($Text[$cursor] -eq '\' -and $cursor + 1 -lt $Text.Length) {
      if ($isRaw -and $Text[$cursor + 1] -notin @($quote, "`r", "`n")) {
        $null = $value.Append($Text[$cursor])
        $cursor++
      } elseif ($isRaw -and $Text[$cursor + 1] -in @("`r", "`n")) {
        $null = $value.Append($Text[$cursor])
        $null = $value.Append($Text[$cursor + 1])
        $cursor += 2
      } else {
        $null = $value.Append($Text[$cursor + 1])
        $cursor += 2
      }
      continue
    }
    $null = $value.Append($Text[$cursor])
    $cursor++
  }
  if (-not $closed) {
    return [pscustomobject]@{ Complete = $false; Value = $null }
  }
  while ($cursor -lt $Text.Length) {
    if ([char]::IsWhiteSpace($Text[$cursor])) { $cursor++; continue }
    if ($Text[$cursor] -eq '#') {
      $newline = $Text.IndexOf("`n", $cursor)
      $cursor = if ($newline -lt 0) { $Text.Length } else { $newline + 1 }
      continue
    }
    return [pscustomobject]@{ Complete = $false; Value = $null }
  }
  [pscustomobject]@{ Complete = $true; Value = $value.ToString() }
}

function ConvertFrom-RulePatternExpression {
  param([string]$Text)
  $trimmed = $Text.Trim()
  if ($trimmed.Length -lt 2 -or $trimmed[0] -ne '[' -or $trimmed[$trimmed.Length - 1] -ne ']') {
    return [pscustomobject]@{ Complete = $false; Elements = @() }
  }
  $outer = Split-RuleCommaSegments $trimmed.Substring(1, $trimmed.Length - 2)
  if (-not $outer.Complete) {
    return [pscustomobject]@{ Complete = $false; Elements = @() }
  }
  $elements = [System.Collections.Generic.List[object]]::new()
  foreach ($rawSegment in @($outer.Segments)) {
    $segment = $rawSegment.Trim()
    if (-not $segment) { continue }
    $isAlternatives = $segment.Length -ge 2 -and
      $segment[0] -eq '[' -and $segment[$segment.Length - 1] -eq ']'
    $literalSegments = if ($isAlternatives) {
      $inner = Split-RuleCommaSegments $segment.Substring(1, $segment.Length - 2)
      if (-not $inner.Complete) {
        return [pscustomobject]@{ Complete = $false; Elements = @() }
      }
      @($inner.Segments)
    } else { @($segment) }
    $alternatives = [System.Collections.Generic.List[string]]::new()
    foreach ($literalSegment in $literalSegments) {
      $literal = ConvertFrom-RuleSingleLiteral $literalSegment
      if (-not $literal.Complete) {
        return [pscustomobject]@{ Complete = $false; Elements = @() }
      }
      $alternatives.Add([string]$literal.Value)
    }
    if ($alternatives.Count -eq 0) {
      return [pscustomobject]@{ Complete = $false; Elements = @() }
    }
    $elements.Add([pscustomobject]@{
        Alternatives = @($alternatives)
        IsAlternatives = $isAlternatives
      })
  }
  [pscustomobject]@{ Complete = $elements.Count -gt 0; Elements = @($elements) }
}

function Get-RuleExecutableName {
  param([string]$Literal)
  if (-not $Literal) { return "" }
  $normalized = $Literal.Trim().Replace('/', '\')
  ([System.IO.Path]::GetFileNameWithoutExtension($normalized)).ToLowerInvariant()
}

function Test-RuleElementIsFixedOperand {
  param($Element)
  $values = @($Element.Alternatives | ForEach-Object { ([string]$_).Trim() })
  return $values.Count -gt 0 -and
    @($values | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '^[-/]' }).Count -eq 0
}

function Test-InterpreterRuleHasFixedOperand {
  param([string]$Executable, [object[]]$PatternElements)
  if ($PatternElements.Count -lt 2) { return $false }
  $name = $Executable.ToLowerInvariant()
  if ($name -in @('powershell', 'pwsh')) {
    $switches = @('-nologo', '-noprofile', '-noninteractive', '-noexit', '-sta', '-mta')
    $valueOptions = @('-executionpolicy', '-inputformat', '-outputformat', '-windowstyle', '-workingdirectory', '-version', '-configurationname', '-custompipename', '-settingsfile')
    for ($position = 1; $position -lt $PatternElements.Count; $position++) {
      $values = @($PatternElements[$position].Alternatives | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
      if ($values.Count -eq 0) { return $false }
      if (@($values | Where-Object { $_ -notin $switches }).Count -eq 0) { continue }
      if (@($values | Where-Object { $_ -notin $valueOptions }).Count -eq 0) {
        $position++
        if ($position -ge $PatternElements.Count) { return $false }
        continue
      }
      if (@($values | Where-Object { $_ -ne '-file' }).Count -eq 0) {
        return $position + 1 -lt $PatternElements.Count -and
          (Test-RuleElementIsFixedOperand $PatternElements[$position + 1])
      }
      return $false
    }
    return $false
  }
  if ($name -eq 'curl') {
    # A URL does not constrain curl to one transfer. Prefix rules allow
    # trailing URLs and options, so curl allow prefixes remain broad.
    return $false
  }
  if ($name -in @('python', 'python3', 'node', 'bash', 'sh', 'zsh', 'dash', 'ksh', 'fish', 'cscript', 'wscript')) {
    # Only a direct fixed operand is considered constrained. Interpreter
    # options may consume following values, so unknown option layouts fail closed.
    return Test-RuleElementIsFixedOperand $PatternElements[1]
  }
  return $false
}

function ConvertFrom-PrefixRuleBlock {
  param([string]$Block)
  $open = $Block.IndexOf('(')
  $close = $Block.LastIndexOf(')')
  if ($open -lt 0 -or $close -le $open) {
    return [pscustomobject]@{ Complete = $false; PatternLiterals = @(); AllLiterals = @(); SemanticText = "" }
  }
  $body = $Block.Substring($open + 1, $close - $open - 1)
  $segments = [System.Collections.Generic.List[string]]::new()
  $start = 0
  $depth = 0
  $inString = $false
  $quote = [char]0
  $triple = $false
  $escaped = $false
  $comment = $false
  for ($cursor = 0; $cursor -lt $body.Length; $cursor++) {
    $character = $body[$cursor]
    if ($comment) { if ($character -eq "`n") { $comment = $false }; continue }
    if ($inString) {
      if ($escaped) { $escaped = $false; continue }
      if ($character -eq '\') { $escaped = $true; continue }
      if ($triple -and $cursor + 2 -lt $body.Length -and
          $body[$cursor] -eq $quote -and $body[$cursor + 1] -eq $quote -and
          $body[$cursor + 2] -eq $quote) {
        $inString = $false; $cursor += 2
      } elseif (-not $triple -and $character -eq $quote) { $inString = $false }
      continue
    }
    if ($character -eq '#') { $comment = $true; continue }
    if ($character -in @('"', "'")) {
      $inString = $true; $quote = $character
      $triple = $cursor + 2 -lt $body.Length -and
        $body[$cursor + 1] -eq $quote -and $body[$cursor + 2] -eq $quote
      if ($triple) { $cursor += 2 }
      continue
    }
    if ($character -in @('(', '[', '{')) { $depth++; continue }
    if ($character -in @(')', ']', '}')) { $depth--; continue }
    if ($character -eq ',' -and $depth -eq 0) {
      $segments.Add($body.Substring($start, $cursor - $start))
      $start = $cursor + 1
    }
  }
  if ($inString -or $depth -ne 0) {
    return [pscustomobject]@{ Complete = $false; PatternLiterals = @(); AllLiterals = @(); SemanticText = "" }
  }
  $segments.Add($body.Substring($start))
  $arguments = @{}
  $patternStructure = $null
  $allLiterals = [System.Collections.Generic.List[string]]::new()
  $semantic = [System.Collections.Generic.List[string]]::new()
  foreach ($segment in $segments) {
    $match = [regex]::Match($segment, '(?ms)^\s*(?:\#.*?\r?\n\s*)*([A-Za-z_][A-Za-z0-9_]*)\s*=')
    if (-not $match.Success) { continue }
    $name = $match.Groups[1].Value.ToLowerInvariant()
    $valueText = $segment.Substring($match.Index + $match.Length)
    $literals = @(Get-RuleLiteralTokens $valueText)
    $arguments[$name] = $literals
    if ($name -eq 'pattern') { $patternStructure = ConvertFrom-RulePatternExpression $valueText }
    $semantic.Add($name)
    foreach ($literal in $literals) { $allLiterals.Add($literal); $semantic.Add($literal) }
  }
  [pscustomobject]@{
    Complete = $arguments.ContainsKey('pattern') -and $patternStructure -and $patternStructure.Complete
    PatternLiterals = if ($arguments.ContainsKey('pattern')) { @($arguments['pattern']) } else { @() }
    PatternElements = if ($patternStructure -and $patternStructure.Complete) { @($patternStructure.Elements) } else { @() }
    Decision = if ($arguments.ContainsKey('decision') -and @($arguments['decision']).Count -gt 0) {
      ([string]@($arguments['decision'])[0]).Trim().ToLowerInvariant()
    } else { 'unknown' }
    AllLiterals = @($allLiterals)
    SemanticText = @($semantic) -join "`n"
  }
}

function Get-RuleHealth {
  $result = [ordered]@{
    Observation = "unavailable"
    Count = 0
    Monolithic = 0
    ReusableNarrow = 0
    BroadInterpreter = 0
    CredentialShaped = 0
    CredentialCandidateOrdinals = "none"
    CredentialCandidateClasses = "none"
    CredentialConfidence = "not_observed"
    AverageLength = $null
    MaximumLiteralLength = 0
    Status = "UNAVAILABLE"
    ValuesReturned = $false
    FilesEligible = 0
    FilesSelected = 0
    CoverageCapped = $false
    InventoryTimedOut = $false
    ParseFailures = 0
  }
  $rulesRoot = Join-Path $CodexHome "rules"
  if (-not (Test-Path -LiteralPath $rulesRoot -PathType Container) -or
      -not (Test-ChronosReadPath $rulesRoot)) {
    $result.Observation = "not_found"
    return [pscustomobject]$result
  }
  $eligibleFiles = @(Get-ChildItem -LiteralPath $rulesRoot -File -ErrorAction SilentlyContinue | Where-Object {
      $_.Extension -in @(".rules", ".toml") -and (Test-ChronosReadPath $_.FullName)
    } | Sort-Object FullName)
  $result.FilesEligible = $eligibleFiles.Count
  $files = @($eligibleFiles | Select-Object -First 32)
  $result.FilesSelected = $files.Count
  $result.CoverageCapped = $eligibleFiles.Count -gt $files.Count
  if ($files.Count -eq 0) {
    $result.Observation = "no_supported_files"
    return [pscustomobject]$result
  }
  $lengthTotal = 0L
  $credentialOrdinals = [System.Collections.Generic.List[int]]::new()
  $credentialClasses = [System.Collections.Generic.List[string]]::new()
  $credentialConfidenceRank = 0
  $remainingRules = 2048
  foreach ($file in $files) {
    if ($remainingRules -le 0) { $result.CoverageCapped = $true; break }
    $parsedRules = Get-BoundedPrefixRuleBlocks $file.FullName -MaxRules $remainingRules
    if (-not $parsedRules.Complete) { $result.ParseFailures++; $result.CoverageCapped = $true }
    foreach ($block in @($parsedRules.Blocks)) {
      $trimmed = $block.Trim()
      $result.Count++
      $lengthTotal += $trimmed.Length
      $structuredRule = ConvertFrom-PrefixRuleBlock $trimmed
      if (-not $structuredRule.Complete) {
        $result.ParseFailures++
        $result.CoverageCapped = $true
      }
      $literalLengths = @($structuredRule.AllLiterals | ForEach-Object { ([string]$_).Length })
      $maxLiteral = if ($literalLengths.Count) { [int](@($literalLengths | Measure-Object -Maximum).Maximum) } else { 0 }
      if ($maxLiteral -gt $result.MaximumLiteralLength) { $result.MaximumLiteralLength = $maxLiteral }
      $isMonolithic = $maxLiteral -gt 256
      if ($isMonolithic) { $result.Monolithic++ }

      $patternLiterals = @($structuredRule.PatternLiterals)
      $patternElements = @($structuredRule.PatternElements)
      $firstExecutables = if ($patternElements.Count -gt 0) {
        @($patternElements[0].Alternatives | ForEach-Object { Get-RuleExecutableName ([string]$_) })
      } else { @() }
      $interpreterNames = @(
        "powershell", "pwsh", "cmd", "bash", "sh", "zsh", "dash", "ksh", "fish",
        "wsl", "python", "python3", "node", "cscript", "wscript", "curl"
      )
      $hasInterpreter = @($firstExecutables | Where-Object { $_ -in $interpreterNames }).Count -gt 0
      $subsequentElements = if ($patternElements.Count -gt 1) {
        @($patternElements | Select-Object -Skip 1)
      } else { @() }
      $subsequentAlternatives = @($subsequentElements | ForEach-Object {
          $_.Alternatives | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }
        })
      $arbitraryCodePrefix = $false
      foreach ($executable in $firstExecutables) {
        $arbitraryFlags = switch ($executable) {
          { $_ -in @("powershell", "pwsh") } { @("-command", "-c", "-encodedcommand", "-enc"); break }
          "cmd" { @("/c", "/k"); break }
          { $_ -in @("bash", "sh", "zsh", "dash", "ksh", "fish") } { @("-c"); break }
          { $_ -in @("python", "python3") } { @("-c"); break }
          "node" { @("-e", "--eval"); break }
          "wsl" { @("-e", "--exec"); break }
          default { @() }
        }
        if (@($subsequentAlternatives | Where-Object { $_ -in $arbitraryFlags }).Count -gt 0) {
          $arbitraryCodePrefix = $true
          break
        }
      }
      $unsafeInterpreterBranch = @($firstExecutables | Where-Object {
          $_ -in $interpreterNames -and -not (Test-InterpreterRuleHasFixedOperand $_ $patternElements)
        }).Count -gt 0
      $fixedOperandGuaranteed = $hasInterpreter -and -not $unsafeInterpreterBranch
      $optionOnlyPrefix = $patternElements.Count -gt 1 -and -not $fixedOperandGuaranteed
      $missingFileOperand = $false
      if (@($firstExecutables | Where-Object { $_ -in @('powershell', 'pwsh') }).Count -gt 0) {
        for ($position = 1; $position -lt $patternElements.Count; $position++) {
          $positionValues = @($patternElements[$position].Alternatives | ForEach-Object {
              ([string]$_).Trim().ToLowerInvariant()
            })
          if ($positionValues -contains '-file') {
            $followingValues = if ($position + 1 -lt $patternElements.Count) {
              @($patternElements[$position + 1].Alternatives | ForEach-Object {
                  ([string]$_).Trim().ToLowerInvariant()
                })
            } else { @() }
            $hasFollowingOperand = $followingValues.Count -gt 0 -and
              @($followingValues | Where-Object { -not $_ -or $_ -match '^[-/]' }).Count -eq 0
            if (-not $hasFollowingOperand) { $missingFileOperand = $true }
          }
        }
      }
      $decisionCanGrant = $structuredRule.Decision -in @("allow", "allowed", "approve", "approved", "unknown")
      $isBroad = $structuredRule.Complete -and $decisionCanGrant -and $hasInterpreter -and
        ($patternElements.Count -eq 1 -or $arbitraryCodePrefix -or $optionOnlyPrefix -or $missingFileOperand)
      if ($isBroad) { $result.BroadInterpreter++ }
      if ($structuredRule.Complete -and -not $isMonolithic -and -not $isBroad) { $result.ReusableNarrow++ }

      $semanticText = $structuredRule.SemanticText
      $secretShape = $semanticText -match '(?i)(token|secret|password|passwd|api[_-]?key|access[_-]?key|client[_-]?secret)\s*[=:]' -or
        $semanticText -match '(?i)(sk-[a-z0-9_-]{12,}|gh[pousr]_[a-z0-9]{20,}|nfp_[a-z0-9]{20,}|AKIA[0-9A-Z]{16})'
      if ($secretShape) {
        $result.CredentialShaped++
        $ordinal = $result.Count
        $placeholderLike = $semanticText -match '(?i)placeholder|example|synthetic|dummy|redacted|test[_-]?only|your[_-]'
        $providerToken = $semanticText -match '(?i)(sk-[a-z0-9_-]{12,}|gh[pousr]_[a-z0-9]{20,}|nfp_[a-z0-9]{20,}|AKIA[0-9A-Z]{16})'
        $category = if ($placeholderLike) { "placeholder-like" } elseif ($providerToken) {
          "provider-token"
        } else { "named-assignment" }
        $confidenceRank = if ($placeholderLike) { 1 } elseif ($providerToken) { 3 } else { 2 }
        if ($credentialOrdinals.Count -lt 32) {
          $credentialOrdinals.Add($ordinal)
          $credentialClasses.Add(($ordinal.ToString() + ":" + $category))
        }
        if ($confidenceRank -gt $credentialConfidenceRank) { $credentialConfidenceRank = $confidenceRank }
      }
    }
    $remainingRules -= @($parsedRules.Blocks).Count
  }
  $result.Observation = if ($result.CoverageCapped) { "observed_partial" } else { "observed" }
  if ($result.Count -gt 0) { $result.AverageLength = [math]::Round($lengthTotal / [double]$result.Count, 1) }
  if ($credentialOrdinals.Count -gt 0) {
    $result.CredentialCandidateOrdinals = @($credentialOrdinals) -join ","
    $result.CredentialCandidateClasses = @($credentialClasses) -join ","
    $result.CredentialConfidence = @("not_observed", "low", "medium", "high")[$credentialConfidenceRank]
  }
  $result.Status = if ($result.CredentialShaped -gt 0) { "CRITICAL" } elseif (
    $result.Monolithic -gt 0 -or $result.BroadInterpreter -gt 0
  ) { "WARNING" } elseif ($result.CoverageCapped) { "WARNING" } else { "HEALTHY" }
  [pscustomobject]$result
}

function Get-CodexConfigurationHealth {
  $result = [ordered]@{
    ConfiguredReviewer = "unavailable"
    ManagedReviewer = "unavailable"
    PrimaryReasoningDefault = "unavailable"
  }
  $path = Join-Path $CodexHome "config.toml"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-ChronosReadPath $path)) {
    return [pscustomobject]$result
  }
  foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ($line -match '^\s*approvals_reviewer\s*=\s*["'']([a-zA-Z0-9_.-]{1,64})["'']') {
      $result.ConfiguredReviewer = $Matches[1].ToLowerInvariant()
    } elseif ($line -match '^\s*managed_approvals_reviewer\s*=\s*["'']([a-zA-Z0-9_.-]{1,64})["'']') {
      $result.ManagedReviewer = $Matches[1].ToLowerInvariant()
    } elseif ($line -match '^\s*(model_reasoning_effort|reasoning_effort)\s*=\s*["''](low|medium|high|xhigh|max|ultra)["'']') {
      $result.PrimaryReasoningDefault = $Matches[2].ToLowerInvariant()
    }
  }
  [pscustomobject]$result
}

function ConvertTo-TokenInt64 {
  param($Object, [string]$Name, [switch]$Optional)
  $property = if ($Object) { $Object.PSObject.Properties[$Name] } else { $null }
  if (-not $property -or $null -eq $property.Value) {
    if ($Optional) { return 0L }
    throw "missing_token_counter"
  }
  $value = [Convert]::ToInt64($property.Value, [System.Globalization.CultureInfo]::InvariantCulture)
  if ($value -lt 0) { throw "negative_token_counter" }
  $value
}

function Get-ValidatedTokenSnapshot {
  param($Info)
  try {
    if (-not $Info -or -not $Info.total_token_usage) { return $null }
    $total = $Info.total_token_usage
    $inputTokens = ConvertTo-TokenInt64 $total "input_tokens"
    $cachedInputTokens = ConvertTo-TokenInt64 $total "cached_input_tokens" -Optional
    $cacheWriteProperty = $total.PSObject.Properties["cache_write_input_tokens"]
    $cacheWriteAvailable = $null -ne $cacheWriteProperty -and $null -ne $cacheWriteProperty.Value
    $cacheWriteTokens = if ($cacheWriteAvailable) {
      ConvertTo-TokenInt64 $total "cache_write_input_tokens"
    } else { 0L }
    $outputTokens = ConvertTo-TokenInt64 $total "output_tokens"
    $reasoningTokens = ConvertTo-TokenInt64 $total "reasoning_output_tokens" -Optional
    $totalTokens = ConvertTo-TokenInt64 $total "total_tokens"
    if ($cachedInputTokens -gt $inputTokens) { throw "cached_tokens_exceed_input" }
    $contextWindow = ConvertTo-TokenInt64 $Info "model_context_window" -Optional
    $lastTotalTokens = 0L
    if ($Info.last_token_usage) {
      $lastTotalTokens = ConvertTo-TokenInt64 $Info.last_token_usage "total_tokens" -Optional
    }
    [pscustomobject]@{
      InputTokens = $inputTokens
      CachedInputTokens = $cachedInputTokens
      CacheWriteTokens = $cacheWriteTokens
      CacheWriteAvailable = $cacheWriteAvailable
      OutputTokens = $outputTokens
      ReasoningTokens = $reasoningTokens
      TotalTokens = $totalTokens
      ContextWindow = $contextWindow
      LastTotalTokens = $lastTotalTokens
    }
  } catch {
    $null
  }
}

function Get-SafeCategory {
  param($Object, [string[]]$Names)
  if (-not $Object) { return $null }
  foreach ($name in $Names) {
    $property = $Object.PSObject.Properties[$name]
    if (-not $property -or $null -eq $property.Value) { continue }
    $value = ([string]$property.Value).Trim().ToLowerInvariant()
    if ($value -match '^[a-z0-9][a-z0-9_.-]{0,63}$') { return $value }
  }
  $null
}

function Get-ApprovalRequestClass {
  param($Record)
  if (-not $Record -or $Record.type -ne "event_msg" -or -not $Record.payload) { return $null }
  $payloadType = Get-SafeCategory $Record.payload @("type")
  if ($payloadType -notin @(
      "approval_request", "exec_approval_request", "apply_patch_approval_request",
      "network_approval_request", "filesystem_approval_request"
    )) { return $null }

  $source = switch ($payloadType) {
    "exec_approval_request" { "shell" }
    "apply_patch_approval_request" { "filesystem" }
    "network_approval_request" { "network" }
    "filesystem_approval_request" { "filesystem" }
    default { "unknown" }
  }
  $prefixFingerprint = Get-CanonicalPrefixFingerprint $Record.payload
  $operationClass = Get-InspectionOperationClass $Record.payload
  $accessMode = Get-SafeCategory $Record.payload @("access_mode")
  $boundaryCause = Get-SafeCategory $Record.payload @(
    "escalation_reason", "boundary_cause", "approval_cause", "permission_class"
  )
  $state = Get-SafeCategory $Record.payload @("approval_state", "state", "status")
  $correlation = Get-SafeCategory $Record.payload @("approval_id", "request_id", "call_id")
  $dimensions = [System.Collections.Generic.List[string]]::new()
  foreach ($definition in @(
      @{ label = "tool"; names = @("tool_name", "tool") },
      @{ label = "permission"; names = @("permission_class", "sandbox_permission") },
      @{ label = "operation"; names = @("operation_class", "operation") },
      @{ label = "access"; names = @("access_mode") },
      @{ label = "risk"; names = @("risk_class") }
    )) {
    $value = Get-SafeCategory $Record.payload $definition.names
    if ($value) { $dimensions.Add($definition.label + ":" + $value) }
  }
  [pscustomobject]@{
    Schema = "event_msg"
    Source = $source
    PrefixFingerprint = $prefixFingerprint
    OperationClass = if ($operationClass) { $operationClass } else { "unknown" }
    InspectionShaped = $operationClass -in @(
      "get-content", "rg", "get-childitem", "select-string", "resolve-path", "test-path",
      "repository-read", "filesystem-read"
    )
    AccessMode = if ($accessMode) { $accessMode } else { "unknown" }
    BoundaryCause = if ($boundaryCause) { $boundaryCause } else { "unknown" }
    State = if ($state) { $state } else { "unknown" }
    CorrelationFingerprint = if ($correlation) { Get-TextFingerprint $correlation } else { $null }
    EquivalenceSignature = $source + "|operation:" +
      $(if ($operationClass) { $operationClass } else { "unknown" }) + "|prefix:" +
      $(if ($prefixFingerprint) { $prefixFingerprint } else { "unavailable" })
    Signature = if ($dimensions.Count -gt 0 -or $prefixFingerprint) {
      $payloadType + "|" + (@($dimensions | Sort-Object) -join "|") +
        $(if ($prefixFingerprint) { "|prefix:" + $prefixFingerprint } else { "|prefix:unavailable" })
    } else { $null }
  }
}

function Get-FunctionCallApprovalRequestClass {
  param($Record)
  if (-not $Record -or $Record.type -ne "response_item" -or
      -not $Record.payload -or $Record.payload.type -ne "function_call") { return $null }
  $arguments = ConvertFrom-StructuredArguments $Record.payload.arguments
  $permission = Get-SafeCategory $arguments @("sandbox_permissions", "permission_class")
  if ($permission -ne "require_escalated") { return $null }

  $functionName = Get-SafeCategory $Record.payload @("name")
  $source = switch ($functionName) {
    "shell_command" { "shell" }
    "apply_patch" { "filesystem" }
    "web__run" { "network" }
    default { "unknown" }
  }
  $prefixFingerprint = Get-CanonicalPrefixFingerprint $arguments
  $operationClass = Get-InspectionOperationClass $arguments
  $callProperty = $Record.payload.PSObject.Properties["call_id"]
  $callId = if ($callProperty -and $null -ne $callProperty.Value) { [string]$callProperty.Value } else { $null }
  $correlation = if ($callId -and $callId.Length -le 512) { Get-TextFingerprint $callId } else { $null }
  $signatureParts = @(
    "function_call_escalation",
    "source:" + $source,
    "function:" + $(if ($functionName) { $functionName } else { "unknown" }),
    "operation:" + $(if ($operationClass) { $operationClass } else { "unknown" }),
    "permission:" + $permission,
    "prefix:" + $(if ($prefixFingerprint) { $prefixFingerprint } else { "unavailable" })
  )
  [pscustomobject]@{
    Schema = "function_call_escalation"
    Source = $source
    PrefixFingerprint = $prefixFingerprint
    OperationClass = if ($operationClass) { $operationClass } else { "unknown" }
    InspectionShaped = $operationClass -in @(
      "get-content", "rg", "get-childitem", "select-string", "resolve-path", "test-path",
      "repository-read", "filesystem-read"
    )
    AccessMode = "unknown"
    BoundaryCause = "sandbox_escalation"
    State = "pending"
    CorrelationFingerprint = $correlation
    EquivalenceSignature = $source + "|operation:" +
      $(if ($operationClass) { $operationClass } else { "unknown" }) + "|prefix:" +
      $(if ($prefixFingerprint) { $prefixFingerprint } else { "unavailable" })
    Signature = $signatureParts -join "|"
  }
}

function Register-ResolvedAllowedApproval {
  param($State, $ApprovalResolvedAllowedEquivalences)
  if (-not $State -or $State.resolved_allowed_counted -or
      $State.decision -ne "allowed" -or -not $State.resolved -or
      -not $State.equivalence -or -not $State.rule_miss_eligible) { return }
  $key = [string]$State.equivalence
  if ($ApprovalResolvedAllowedEquivalences.ContainsKey($key)) {
    $ApprovalResolvedAllowedEquivalences[$key]++
  } else { $ApprovalResolvedAllowedEquivalences[$key] = 1 }
  $State.resolved_allowed_counted = $true
}

function Add-ApprovalRequestObservation {
  param($Health, $ApprovalClass, $RecordTimestamp, $ApprovalClasses, $ApprovalPrefixes,
    $ApprovalBoundaryCauses, $ApprovalSources, $ApprovalStates, $ApprovalRequestCorrelations,
    $ApprovalSchemas)
  if (-not $ApprovalClass) { return }
  if ($ApprovalClass.CorrelationFingerprint) {
    $priorCorrelation = if ($ApprovalRequestCorrelations.ContainsKey($ApprovalClass.CorrelationFingerprint)) {
      $ApprovalRequestCorrelations[$ApprovalClass.CorrelationFingerprint]
    } else { $null }
    $isCrossSchemaMirror = $priorCorrelation -and
      $priorCorrelation.schema -ne $ApprovalClass.Schema -and
      $priorCorrelation.equivalence -eq $ApprovalClass.EquivalenceSignature -and
      $priorCorrelation.timestamp -and $RecordTimestamp -and
      $priorCorrelation.timestamp -eq $RecordTimestamp
    if ($isCrossSchemaMirror) { return }
    $ApprovalRequestCorrelations[$ApprovalClass.CorrelationFingerprint] = @{
      schema = $ApprovalClass.Schema
      equivalence = $ApprovalClass.EquivalenceSignature
      timestamp = $RecordTimestamp
    }
  }
  if ($ApprovalClass.Schema) { $null = $ApprovalSchemas.Add([string]$ApprovalClass.Schema) }
  $Health.ApprovalRequestsObserved++
  if ($ApprovalClass.InspectionShaped) { $Health.InspectionShapedApprovalRequests++ }
  foreach ($pair in @(
      @{ Map = $ApprovalBoundaryCauses; Key = $ApprovalClass.BoundaryCause },
      @{ Map = $ApprovalSources; Key = $ApprovalClass.Source },
      @{ Map = $ApprovalClasses; Key = $ApprovalClass.Signature },
      @{ Map = $ApprovalPrefixes; Key = $ApprovalClass.PrefixFingerprint }
    )) {
    if (-not $pair.Key) { continue }
    if ($pair.Map.ContainsKey($pair.Key)) { $pair.Map[$pair.Key]++ } else { $pair.Map[$pair.Key] = 1 }
  }
  $stateKey = if ($ApprovalClass.CorrelationFingerprint) {
    $ApprovalClass.CorrelationFingerprint
  } else { $ApprovalClass.Signature }
  if (-not $stateKey) { return }
  $prior = if ($ApprovalStates.ContainsKey($stateKey)) {
    $ApprovalStates[$stateKey]
  } elseif ($ApprovalClass.Signature -and $ApprovalStates.ContainsKey($ApprovalClass.Signature)) {
    $ApprovalStates[$ApprovalClass.Signature]
  } else { $null }
  $priorUnresolvedAllow = $prior -and -not $prior.resolved -and (
    $prior.decision -eq "allowed" -or $prior.prior_unresolved_allowed
  )
  if ($priorUnresolvedAllow -and $ApprovalClass.State -eq "pending") {
    $Health.ApprovalPersistenceRetries++
  }
  $state = @{
    decision = "unknown"
    resolved = $false
    requested_at = $RecordTimestamp
    equivalence = $ApprovalClass.EquivalenceSignature
    rule_miss_eligible = [bool]$ApprovalClass.PrefixFingerprint
    prior_unresolved_allowed = [bool]$priorUnresolvedAllow
    resolved_allowed_counted = $false
  }
  $ApprovalStates[$stateKey] = $state
  if ($ApprovalClass.Signature) { $ApprovalStates[$ApprovalClass.Signature] = $state }
}

function Resolve-ApprovalObservation {
  param($Health, [string]$CorrelationFingerprint, $RecordTimestamp, $ApprovalStates,
    $ApprovalResolutionLatencies, $ApprovalResolvedAllowedEquivalences)
  if (-not $CorrelationFingerprint -or -not $ApprovalStates.ContainsKey($CorrelationFingerprint)) { return }
  $state = $ApprovalStates[$CorrelationFingerprint]
  if ($state.resolved) { return }
  $state.resolved = $true
  $state.prior_unresolved_allowed = $false
  $Health.ApprovalResolvedRequests++
  Register-ResolvedAllowedApproval $state $ApprovalResolvedAllowedEquivalences
  if ($RecordTimestamp -and $state.requested_at) {
    $latency = ($RecordTimestamp - $state.requested_at).TotalMilliseconds
    if ($latency -ge 0 -and $latency -le 86400000) { $ApprovalResolutionLatencies.Add([double]$latency) }
  }
}

function Get-ApprovalDecisionRecord {
  param($Record)
  if (-not $Record -or -not $Record.payload) { return $null }
  $payloadType = Get-SafeCategory $Record.payload @("type")
  if ($payloadType -notin @(
      "approval_decision", "approval_response", "exec_approval_response",
      "apply_patch_approval_response"
    )) { return $null }
  $decision = Get-SafeCategory $Record.payload @("decision", "status", "outcome")
  $normalized = if ($decision -in @("allowed", "allow", "approved", "approve")) {
    "allowed"
  } elseif ($decision -in @("denied", "rejected", "declined")) {
    "denied"
  } else { "unknown" }
  $correlation = Get-SafeCategory $Record.payload @("approval_id", "request_id", "call_id")
  [pscustomobject]@{
    Decision = $normalized
    CorrelationFingerprint = if ($correlation) { Get-TextFingerprint $correlation } else { $null }
  }
}

function Get-QuotaHealth {
  $health = [ordered]@{
    Level = "UNAVAILABLE"
    Files = 0
    Samples = 0
    SessionInputM = $null
    IntervalInputM = $null
    IntervalCachedInputM = $null
    IntervalOutputM = $null
    IntervalReasoningM = $null
    IntervalCacheWriteM = $null
    IntervalFiles = 0
    IntervalStartUtc = $null
    IntervalEndUtc = $null
    IntervalObservation = "unavailable"
    CachedReadPercent = $null
    CacheWriteM = $null
    CacheWriteObserved = $null
    CacheWriteObservation = "unsupported_schema"
    CacheWriteAvailableFiles = 0
    CacheWriteSelectedFiles = 0
    ReasoningPercent = $null
    MaxContextPercent = $null
    HighEffortSessions = 0
    ExtremeEffortSessions = 0
    UltraSessions = 0
    SpawnCalls = 0
    Compactions = 0
    MalformedRecords = 0
    DuplicateRecords = 0
    OutOfOrderRecords = 0
    TailIncompleteFiles = 0
    TailTruncatedFiles = 0
    UnreadableFiles = 0
    CoverageWindowHours = 6
    CoverageStartUtc = $null
    CoverageEndUtc = $null
    FilesEligible = 0
    FilesSelected = 0
    CoverageCapped = $false
    CoverageContinuity = "unknown"
    SpawnObservation = "unavailable"
    CompactionObservation = "unavailable"
    ReviewerTurnsObserved = 0
    ReviewerSessionsObserved = 0
    ReviewerModels = "none"
    ReviewerObservation = "unavailable"
    ReviewerCoverage = "unknown"
    ReviewerReviewsPerHour = $null
    ReviewerObservationSeconds = 0
    ReviewerRateNormalized = $false
    ReviewerRateConfidence = "unavailable"
    ReviewerAverageIntervalSeconds = $null
    ReviewerMedianIntervalSeconds = $null
    ReviewerPeakPerMinute = 0
    ReviewerP95PerMinute = 0
    ReviewerConsecutiveActiveMinutes = 0
    ReviewerConcurrentPeak = 0
    ReviewerParentLinksObserved = 0
    ReviewerInputM = $null
    PrimaryInputM = $null
    ReviewerUnclassifiedInputM = $null
    ReviewerTokenAttribution = "unavailable"
    ReviewerMainInputRatio = $null
    ApprovalRequestObservation = "unsupported_schema"
    ApprovalRequestSchemas = "none"
    ApprovalRequestsObserved = 0
    ApprovalResolvedRequests = 0
    ApprovalUnresolvedRequests = 0
    ApprovalResolutionObservation = "unavailable"
    ApprovalLatencySamples = 0
    ApprovalMedianLatencyMs = $null
    ApprovalP95LatencyMs = $null
    ApprovalUniqueClasses = 0
    ApprovalRepeatedRequests = 0
    ApprovalRepeatPercent = $null
    ApprovalSources = "unavailable"
    ApprovalDeniedObserved = 0
    ApprovalDecisionsObserved = 0
    ApprovalAllowedObserved = 0
    ApprovalUnknownDecisions = 0
    ApprovalAllowPercent = $null
    ApprovalDeniedObservation = "unavailable"
    ApprovalPersistenceRetries = 0
    ApprovalPersistenceFailures = 0
    ApprovalPersistenceDiagnosis = "not_observed"
    ApprovalRepeatedPrefixRequests = 0
    ApprovalLargestPrefixRepeat = 0
    ApprovalResolvedAllowedEquivalences = 0
    ApprovalLargestResolvedAllowedRepeat = 0
    ApprovalRuleMissDiagnosis = "not_observed"
    InspectionShapedApprovalRequests = 0
    InspectionShapedApprovalPercent = $null
    ApprovalBoundaryCauses = "unavailable"
    ApprovalMetricSource = "local_rollout"
    DashboardEquivalence = "unsupported"
    BillingInference = "unsupported"
    PrimaryTurnsObserved = 0
    ApprovalReviewTurnShare = $null
    ReviewerToolCalls = 0
    ReviewerEscalationsObserved = 0
    ReviewerEscalationUniquePrefixes = 0
    ReviewerEscalationRepeatedPrefixes = 0
    ReviewerEscalationLargestPrefix = 0
    NestedReviewerSessionsObserved = 0
    ApprovalRecursionRisk = "not_observed"
    ApprovalOptimization = "diagnostic_only"
    ApprovalModesObserved = "unavailable"
    ReviewerControlCapability = "unavailable"
    ReviewerCompatibility = "diagnostic_only"
    CrossFileDuplicateRecords = 0
    CrossFileDuplicateCompactions = 0
    CrossFileDuplicateBytes = 0L
    CrossFileReplayPercent = $null
    InheritedTokenSnapshots = 0
    TokenLineageDeltaFiles = 0
    CompactionUniqueSnapshots = 0
    CompactionDuplicateBytes = 0L
    RolloutSelectedMiB = 0.0
    RolloutGrowthMiBPerHour = $null
    RolloutGrowthObservation = "unavailable"
    RolloutProjected24hMiB = $null
    RolloutProjectionComparable = $false
    RolloutLineageLinksObserved = 0
    RolloutForkFilesObserved = 0
    RolloutNearSizeClusterFiles = 0
    RolloutMaxTaskAgeDays = $null
    RolloutAgeObservation = "unavailable"
    RolloutAgeFilesystemFallbackFiles = 0
    HeadTruncatedFiles = 0
    HeadMetadataUnavailableFiles = 0
    RolloutTop1ReviewShare = $null
    RolloutTop3ReviewShare = $null
    SpawnForkAll = 0
    SpawnForkAllDefaulted = 0
    SpawnForkNone = 0
    SpawnForkBounded = 0
    SpawnForkUnknown = 0
    SpawnSchemaV1 = 0
    SpawnSchemaV2 = 0
    SpawnSchemaUnknown = 0
    SpawnHighEffort = 0
    SpawnMaxEffort = 0
    SpawnInheritedTurnsObserved = 0
    SpawnContextAmplification = "not_observed"
    RootAgentSpawns = 0
    ChildAgentSpawns = 0
    NestedAgentObservation = "unavailable"
    CodexVersionsObserved = "unavailable"
    AuthProvidersObserved = "unavailable"
    TokenUsageScope = "selected_rollout_cumulative_snapshots"
    QuotaRiskBasis = "frozen_selected_cumulative_heuristic"
    QuotaContributors = "none"
    Advice = "none"
    AdviceReason = "no_supported_action_threshold_crossed"
    QuotaConfidence = "unavailable"
    EffectiveReviewer = "unavailable"
    ConfiguredReviewer = "unavailable"
    ManagedReviewer = "unavailable"
    ReviewerConfigurationComparison = "unavailable"
    PrimaryReasoningDefault = "unavailable"
    RuleObservation = "unavailable"
    RuleCount = 0
    RuleMonolithic = 0
    RuleReusableNarrow = 0
    RuleBroadInterpreter = 0
    RuleCredentialShaped = 0
    RuleCredentialCandidateOrdinals = "none"
    RuleCredentialCandidateClasses = "none"
    RuleCredentialConfidence = "not_observed"
    RuleAverageLength = $null
    RuleMaximumLiteralLength = 0
    RuleStatus = "UNAVAILABLE"
    RuleValuesReturned = $false
    RuleFilesEligible = 0
    RuleFilesSelected = 0
    RuleCoverageCapped = $false
    RuleParseFailures = 0
    RuleBrittlenessDiagnosis = "not_observed"
    RuleSecretDiagnosis = "not_observed"
    RuleBroadInterpreterDiagnosis = "not_observed"
    ApprovalProblemClass = "unavailable"
    InventoryEntries = 0
    InventoryEntryLimit = 20000
    InventoryEntryLimitHit = $false
  }

  $inputTokens = 0L
  $cachedInputTokens = 0L
  $cacheWriteTokens = 0L
  $cacheWriteAvailableFiles = 0
  $outputTokens = 0L
  $reasoningTokens = 0L
  $intervalInputTokens = 0L
  $intervalCachedInputTokens = 0L
  $intervalOutputTokens = 0L
  $intervalReasoningTokens = 0L
  $intervalCacheWriteTokens = 0L
  $intervalCacheWriteFiles = 0
  $intervalStart = [DateTimeOffset]::MaxValue
  $intervalEnd = [DateTimeOffset]::MinValue
  $reviewerInputTokens = 0L
  $primaryInputTokens = 0L
  $unclassifiedInputTokens = 0L
  $maxContextPercent = 0.0
  $advice = [System.Collections.Generic.List[string]]::new()
  $quotaContributors = [System.Collections.Generic.List[string]]::new()
  $sessionSelection = Get-RecentSessionFiles
  $sessionFiles = @($sessionSelection.Files)
  $health.CoverageWindowHours = $sessionSelection.WindowHours
  $health.CoverageStartUtc = $sessionSelection.WindowStartUtc
  $health.CoverageEndUtc = $sessionSelection.WindowEndUtc
  $health.FilesEligible = $sessionSelection.EligibleCount
  $health.FilesSelected = $sessionSelection.SelectedCount
  $health.CoverageCapped = $sessionSelection.Capped
  $health.InventoryTimedOut = $sessionSelection.InventoryTimedOut
  $health.InventoryEntries = $sessionSelection.InventoryEntries
  $health.InventoryEntryLimit = $sessionSelection.InventoryEntryLimit
  $health.InventoryEntryLimitHit = $sessionSelection.InventoryEntryLimitHit
  $multiAgentV2Seen = $false
  $crossFileRecords = @{}
  $crossFileCompactions = @{}
  $tokenSnapshotOwners = @{}
  $approvalClasses = @{}
  $approvalPrefixes = @{}
  $approvalBoundaryCauses = @{}
  $approvalStates = @{}
  $approvalRequestCorrelations = @{}
  $approvalResolvedAllowedEquivalences = @{}
  $approvalSources = @{}
  $approvalSchemas = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $approvalResolutionLatencies = [System.Collections.Generic.List[double]]::new()
  $reviewerEscalationPrefixes = @{}
  $codexVersions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $authProviders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $approvalModes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $reviewerModels = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
  )
  $reviewTimestamps = [System.Collections.Generic.List[DateTimeOffset]]::new()
  $reviewerIntervals = [System.Collections.Generic.List[object]]::new()
  $fileStats = [System.Collections.Generic.List[object]]::new()
  $selectedBytes = 0L
  $parsedBytes = 0L
  $growthRateTotal = 0.0
  $growthRateFiles = 0

  $configurationHealth = Get-CodexConfigurationHealth
  $health.ConfiguredReviewer = $configurationHealth.ConfiguredReviewer
  $health.ManagedReviewer = $configurationHealth.ManagedReviewer
  $health.PrimaryReasoningDefault = $configurationHealth.PrimaryReasoningDefault
  $ruleHealth = Get-RuleHealth
  $health.RuleObservation = $ruleHealth.Observation
  $health.RuleCount = $ruleHealth.Count
  $health.RuleMonolithic = $ruleHealth.Monolithic
  $health.RuleReusableNarrow = $ruleHealth.ReusableNarrow
  $health.RuleBroadInterpreter = $ruleHealth.BroadInterpreter
  $health.RuleCredentialShaped = $ruleHealth.CredentialShaped
  $health.RuleCredentialCandidateOrdinals = $ruleHealth.CredentialCandidateOrdinals
  $health.RuleCredentialCandidateClasses = $ruleHealth.CredentialCandidateClasses
  $health.RuleCredentialConfidence = $ruleHealth.CredentialConfidence
  $health.RuleAverageLength = $ruleHealth.AverageLength
  $health.RuleMaximumLiteralLength = $ruleHealth.MaximumLiteralLength
  $health.RuleStatus = $ruleHealth.Status
  $health.RuleValuesReturned = $ruleHealth.ValuesReturned
  $health.RuleFilesEligible = $ruleHealth.FilesEligible
  $health.RuleFilesSelected = $ruleHealth.FilesSelected
  $health.RuleCoverageCapped = $ruleHealth.CoverageCapped
  $health.RuleParseFailures = $ruleHealth.ParseFailures
  if ($ruleHealth.Monolithic -gt 0) { $health.RuleBrittlenessDiagnosis = "rule_brittleness_warning" }
  if ($ruleHealth.CredentialShaped -gt 0) { $health.RuleSecretDiagnosis = "rule_secret_exposure" }
  if ($ruleHealth.BroadInterpreter -gt 0) { $health.RuleBroadInterpreterDiagnosis = "broad_interpreter_rule" }

  foreach ($file in @($sessionFiles | Sort-Object CreationTimeUtc, LastWriteTimeUtc)) {
    $selectedBytes += [long]$file.Length
    $lifetimeHours = ($file.LastWriteTimeUtc - $file.CreationTimeUtc).TotalHours
    if ($lifetimeHours -ge (1.0 / 60.0)) {
      $growthRateTotal += ([long]$file.Length / 1MB) / $lifetimeHours
      $growthRateFiles++
    }
  }
  $health.RolloutSelectedMiB = [math]::Round($selectedBytes / 1MB, 1)
  if ($growthRateFiles -gt 0) {
    $health.RolloutGrowthMiBPerHour = [math]::Round($growthRateTotal, 1)
    $health.RolloutGrowthObservation = "file_lifetime_estimate"
    $health.RolloutProjected24hMiB = [math]::Round($growthRateTotal * 24.0, 1)
  }
  if ($sessionFiles.Count -ge 2) {
    $sizes = @($sessionFiles | ForEach-Object { [long]$_.Length } | Sort-Object)
    $largestCluster = 1
    for ($left = 0; $left -lt $sizes.Count; $left++) {
      $cluster = 1
      for ($right = $left + 1; $right -lt $sizes.Count; $right++) {
        $baseSize = [math]::Max(1.0, [double]$sizes[$left])
        if (([double]$sizes[$right] - [double]$sizes[$left]) / $baseSize -le 0.03) {
          $cluster++
        }
      }
      if ($cluster -gt $largestCluster) { $largestCluster = $cluster }
    }
    if ($largestCluster -ge 2) { $health.RolloutNearSizeClusterFiles = $largestCluster }
  }

  foreach ($file in $sessionFiles) {
    if ([long]$file.Length -gt 2097152L) { $health.TailTruncatedFiles++ }
    $tail = Get-BoundedFileTail -Path $file.FullName
    if ([string]::IsNullOrEmpty($tail)) {
      if ([long]$file.Length -gt 0) { $health.UnreadableFiles++ }
      continue
    }

    $lastSnapshot = $null
    $lastSnapshotTimestamp = [DateTimeOffset]::MinValue
    $lastSnapshotOrdinal = -1
    $firstIntervalSnapshot = $null
    $firstIntervalTimestamp = [DateTimeOffset]::MaxValue
    $lastIntervalSnapshot = $null
    $lastIntervalTimestamp = [DateTimeOffset]::MinValue
    $fileInheritedSnapshot = $null
    $lastTurnContext = $null
    $lastTurnContextTimestamp = [DateTimeOffset]::MinValue
    $reviewerSeenInFile = $false
    $reviewerFileFirst = [DateTimeOffset]::MaxValue
    $reviewerFileLast = [DateTimeOffset]::MinValue
    $fileParentLinkSeen = $false
    $fileSessionKey = Get-TextFingerprint $file.FullName
    $fileParentKey = $null
    $fileReviewerTurns = 0
    $fileCompactions = 0
    $fileToolCalls = 0
    $fileSpawns = 0
    $fileTurnCount = 0
    $currentTurnIsReviewer = $false
    $fileFirstRecordTimestamp = [DateTimeOffset]::MaxValue
    $fileMultiAgentSchema = "unknown"
    if ([long]$file.Length -gt 2097152L) {
      $health.HeadTruncatedFiles++
      $headMetadataFound = $false
      $headText = Get-BoundedFileHead -Path $file.FullName
      foreach ($headLine in @($headText -split "`r?`n" | Select-Object -First 256)) {
        if ([string]::IsNullOrWhiteSpace($headLine)) { continue }
        try { if (-not (Test-RolloutJsonUnambiguous $headLine)) { throw 'ambiguous' }; $headRecord = $headLine | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($headRecord.type -ne "session_meta") { continue }
        $headMetadataFound = $true
        $headTimestamp = Get-RecordTimestamp $headRecord
        if ($headTimestamp -and $headTimestamp -lt $fileFirstRecordTimestamp) {
          $fileFirstRecordTimestamp = $headTimestamp
        }
        $sessionIdentifier = Get-SafeCategory $headRecord.payload @("thread_id", "session_id", "id")
        if ($sessionIdentifier) { $fileSessionKey = Get-TextFingerprint $sessionIdentifier }
        $versionProperty = if ($headRecord.payload) { $headRecord.payload.PSObject.Properties["multi_agent_version"] } else { $null }
        if ($versionProperty -and [string]$versionProperty.Value -match '^\d+$' -and [int]$versionProperty.Value -ge 2) {
          $multiAgentV2Seen = $true
          $fileMultiAgentSchema = "v2"
        } elseif ($versionProperty -and [string]$versionProperty.Value -eq "1") {
          $fileMultiAgentSchema = "v1"
        }
        $sourceProperty = if ($headRecord.payload) { $headRecord.payload.PSObject.Properties["source"] } else { $null }
        if ($sourceProperty -and $sourceProperty.Value -is [pscustomobject] -and $sourceProperty.Value.PSObject.Properties["subagent"]) {
          $multiAgentV2Seen = $true
        }
        $codexVersion = Get-SafeCategory $headRecord.payload @("cli_version", "codex_version", "version")
        if ($codexVersion) { $null = $codexVersions.Add($codexVersion) }
        $authProvider = Get-SafeCategory $headRecord.payload @("auth_provider", "model_provider", "provider")
        if ($authProvider) { $null = $authProviders.Add($authProvider) }
        foreach ($parentName in @("parent_thread_id", "parent_id", "forked_from_id", "forked_from")) {
          $parentProperty = if ($headRecord.payload) { $headRecord.payload.PSObject.Properties[$parentName] } else { $null }
          if ($parentProperty -and $parentProperty.Value) {
            $fileParentLinkSeen = $true
            $fileParentKey = Get-TextFingerprint ([string]$parentProperty.Value)
            $health.RolloutLineageLinksObserved++
            $health.RolloutForkFilesObserved++
            break
          }
        }
        break
      }
      if (-not $headMetadataFound) { $health.HeadMetadataUnavailableFiles++ }
    }
    $lines = @($tail -split "`r?`n")
    if (-not $tail.EndsWith("`n", [System.StringComparison]::Ordinal)) {
      $lastLineComplete = $false
      if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[-1])) {
        try { if (-not (Test-RolloutJsonUnambiguous $lines[-1])) { throw 'ambiguous' }; $null = $lines[-1] | ConvertFrom-Json -ErrorAction Stop; $lastLineComplete = $true } catch { $lastLineComplete = $false }
      }
      if (-not $lastLineComplete) {
        $health.TailIncompleteFiles++
        if ($lines.Count -gt 0) { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
      }
    }
    $seenRecords = @{}
    $previousTimestamp = [DateTimeOffset]::MinValue
    $ordinal = 0
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }

      try {
        if (-not (Test-RolloutJsonUnambiguous $line)) { throw 'ambiguous' }
        $record = $line | ConvertFrom-Json -ErrorAction Stop
      } catch {
        $health.MalformedRecords++
        continue
      }

      $recordHash = Get-RecordHash $line.Trim()
      $recordBytes = [System.Text.Encoding]::UTF8.GetByteCount($line) + 1
      $parsedBytes += [long]$recordBytes
      $crossFileDuplicateRecord = $false
      if ($crossFileRecords.ContainsKey($recordHash)) {
        if ($crossFileRecords[$recordHash] -ne $file.FullName) {
          $crossFileDuplicateRecord = $true
          $health.CrossFileDuplicateRecords++
          $health.CrossFileDuplicateBytes += [long]$recordBytes
          if ($record.payload -and $record.payload.type -eq "context_compacted") {
            $health.CrossFileDuplicateCompactions++
            $health.CompactionDuplicateBytes += [long]$recordBytes
          }
          if (-not ($record.payload -and $record.payload.type -eq "token_count")) { continue }
        }
      } else {
        $crossFileRecords[$recordHash] = $file.FullName
      }

      $recordTimestamp = Get-RecordTimestamp $record
      if ($seenRecords.ContainsKey($recordHash)) {
        $health.DuplicateRecords++
        continue
      }
      $seenRecords[$recordHash] = $true
      if ($recordTimestamp) {
        if ($recordTimestamp -lt $fileFirstRecordTimestamp) { $fileFirstRecordTimestamp = $recordTimestamp }
        if ($previousTimestamp -ne [DateTimeOffset]::MinValue -and $recordTimestamp -lt $previousTimestamp) {
          $health.OutOfOrderRecords++
        }
        if ($recordTimestamp -gt $previousTimestamp) { $previousTimestamp = $recordTimestamp }
      }
      $ordinal++

      if ($record.type -eq "session_meta") {
        $sessionIdentifier = Get-SafeCategory $record.payload @("thread_id", "session_id", "id")
        if ($sessionIdentifier) { $fileSessionKey = Get-TextFingerprint $sessionIdentifier }
        $effectiveReviewer = Get-SafeCategory $record.payload @(
          "effective_approvals_reviewer", "effective_approval_reviewer", "approval_reviewer"
        )
        if ($effectiveReviewer) { $health.EffectiveReviewer = $effectiveReviewer }
        $managedReviewer = Get-SafeCategory $record.payload @("managed_approvals_reviewer", "managed_approval_reviewer")
        if ($managedReviewer) { $health.ManagedReviewer = $managedReviewer }
        $versionProperty = if ($record.payload) { $record.payload.PSObject.Properties["multi_agent_version"] } else { $null }
        if ($versionProperty -and [string]$versionProperty.Value -match '^\d+$' -and [int]$versionProperty.Value -ge 2) {
          $multiAgentV2Seen = $true
          $fileMultiAgentSchema = "v2"
        } elseif ($versionProperty -and [string]$versionProperty.Value -eq "1") {
          $fileMultiAgentSchema = "v1"
        }
        $sourceProperty = if ($record.payload) { $record.payload.PSObject.Properties["source"] } else { $null }
        if ($sourceProperty -and $sourceProperty.Value -is [pscustomobject] -and $sourceProperty.Value.PSObject.Properties["subagent"]) {
          $multiAgentV2Seen = $true
        }
        $codexVersion = Get-SafeCategory $record.payload @("cli_version", "codex_version", "version")
        if ($codexVersion) { $null = $codexVersions.Add($codexVersion) }
        $authProvider = Get-SafeCategory $record.payload @("auth_provider", "model_provider", "provider")
        if ($authProvider) { $null = $authProviders.Add($authProvider) }
        $reviewerControlProperty = if ($record.payload) {
          $record.payload.PSObject.Properties["auto_review_model_configurable"]
        } else { $null }
        if ($reviewerControlProperty -and $reviewerControlProperty.Value -is [bool]) {
          if ([bool]$reviewerControlProperty.Value) {
            $health.ReviewerControlCapability = "supported"
            $health.ReviewerCompatibility = "configuration_supported_inventory_unavailable"
          } else {
            $health.ReviewerControlCapability = "unsupported"
            $health.ReviewerCompatibility = "diagnostic_only"
          }
        }
        foreach ($parentName in @("parent_thread_id", "parent_id", "forked_from_id", "forked_from")) {
          $parentProperty = if ($record.payload) { $record.payload.PSObject.Properties[$parentName] } else { $null }
          if ($parentProperty -and $parentProperty.Value) {
            $fileParentLinkSeen = $true
            $fileParentKey = Get-TextFingerprint ([string]$parentProperty.Value)
            break
          }
        }
        if (-not $fileParentLinkSeen -and $record.payload -and $record.payload.PSObject.Properties["source"]) {
          $sourceText = [string]$record.payload.source
          if ($sourceText -match '(?i)subagent|fork') { $fileParentLinkSeen = $true }
        }
        if ($fileParentLinkSeen) {
          $health.RolloutLineageLinksObserved++
          $health.RolloutForkFilesObserved++
        }
        continue
      }

      if ($record.type -eq "turn_context") {
        $fileTurnCount++
        $modelProperty = if ($record.payload) { $record.payload.PSObject.Properties["model"] } else { $null }
        $approvalMode = Get-SafeCategory $record.payload @("approval_mode", "approval_policy")
        if ($approvalMode) { $null = $approvalModes.Add($approvalMode) }
        if ($modelProperty -and [string]$modelProperty.Value -eq "codex-auto-review") {
          $currentTurnIsReviewer = $true
          $health.ReviewerTurnsObserved++
          $fileReviewerTurns++
          $null = $reviewerModels.Add("codex-auto-review")
          if (-not $reviewerSeenInFile) {
            $health.ReviewerSessionsObserved++
            $reviewerSeenInFile = $true
          }
          if ($recordTimestamp) {
            $reviewTimestamps.Add($recordTimestamp)
            if ($recordTimestamp -lt $reviewerFileFirst) { $reviewerFileFirst = $recordTimestamp }
            if ($recordTimestamp -gt $reviewerFileLast) { $reviewerFileLast = $recordTimestamp }
          }
        } else {
          $currentTurnIsReviewer = $false
          $health.PrimaryTurnsObserved++
        }
        if (-not $recordTimestamp -or $recordTimestamp -ge $lastTurnContextTimestamp) {
          $lastTurnContext = $record.payload
          if ($recordTimestamp) { $lastTurnContextTimestamp = $recordTimestamp }
        }
        continue
      }

      if ($record.type -eq "event_msg") {
        $approvalClass = Get-ApprovalRequestClass $record
        Add-ApprovalRequestObservation $health $approvalClass $recordTimestamp $approvalClasses `
          $approvalPrefixes $approvalBoundaryCauses $approvalSources $approvalStates `
          $approvalRequestCorrelations $approvalSchemas
        $approvalDecision = Get-ApprovalDecisionRecord $record
        if ($approvalDecision) {
          $health.ApprovalDecisionsObserved++
          if ($approvalDecision.Decision -eq "allowed") { $health.ApprovalAllowedObserved++ }
          elseif ($approvalDecision.Decision -eq "denied") { $health.ApprovalDeniedObserved++ }
          else { $health.ApprovalUnknownDecisions++ }
          if ($approvalDecision.CorrelationFingerprint -and $approvalStates.ContainsKey($approvalDecision.CorrelationFingerprint)) {
            $decisionState = $approvalStates[$approvalDecision.CorrelationFingerprint]
            $decisionState.decision = $approvalDecision.Decision
            if ($approvalDecision.Decision -eq "denied") {
              $decisionState.prior_unresolved_allowed = $false
            }
            Register-ResolvedAllowedApproval $decisionState $approvalResolvedAllowedEquivalences
          }
        }
        $payloadType = Get-SafeCategory $record.payload @("type")
        if ($payloadType -in @("approval_resolved", "approval_state_applied")) {
          $resolvedId = Get-SafeCategory $record.payload @("approval_id", "request_id", "call_id")
          $resolvedKey = if ($resolvedId) { Get-TextFingerprint $resolvedId } else { $null }
          Resolve-ApprovalObservation $health $resolvedKey $recordTimestamp $approvalStates `
            $approvalResolutionLatencies $approvalResolvedAllowedEquivalences
        } elseif ($payloadType -in @("approval_state_persistence_error", "approval_persistence_error")) {
          $health.ApprovalPersistenceFailures++
        }
        if ($record.payload.type -eq "token_count") {
          $snapshot = Get-ValidatedTokenSnapshot $record.payload.info
          if (-not $snapshot) {
            $health.MalformedRecords++
            continue
          }
          $health.Samples++
          if ($tokenSnapshotOwners.ContainsKey($recordHash)) {
            if ($tokenSnapshotOwners[$recordHash].file -ne $file.FullName) {
              $health.InheritedTokenSnapshots++
              if (
                -not $fileInheritedSnapshot -or
                $snapshot.TotalTokens -gt $fileInheritedSnapshot.TotalTokens
              ) { $fileInheritedSnapshot = $snapshot }
            }
          } else {
            $tokenSnapshotOwners[$recordHash] = @{ file = $file.FullName; snapshot = $snapshot }
          }
          $candidateTimestamp = if ($recordTimestamp) { $recordTimestamp } else { [DateTimeOffset]::MinValue }
          if ($recordTimestamp) {
            if (-not $firstIntervalSnapshot -or $recordTimestamp -lt $firstIntervalTimestamp) {
              $firstIntervalSnapshot = $snapshot
              $firstIntervalTimestamp = $recordTimestamp
            }
            if (-not $lastIntervalSnapshot -or $recordTimestamp -gt $lastIntervalTimestamp) {
              $lastIntervalSnapshot = $snapshot
              $lastIntervalTimestamp = $recordTimestamp
            }
          }
          if (
            -not $lastSnapshot -or
            $snapshot.TotalTokens -gt $lastSnapshot.TotalTokens -or
            ($snapshot.TotalTokens -eq $lastSnapshot.TotalTokens -and $candidateTimestamp -gt $lastSnapshotTimestamp) -or
            ($snapshot.TotalTokens -eq $lastSnapshot.TotalTokens -and $candidateTimestamp -eq $lastSnapshotTimestamp -and $ordinal -gt $lastSnapshotOrdinal)
          ) {
            $lastSnapshot = $snapshot
            $lastSnapshotTimestamp = $candidateTimestamp
            $lastSnapshotOrdinal = $ordinal
          }
        } elseif ($record.payload.type -eq "context_compacted") {
          $health.Compactions++
          $fileCompactions++
          if ($crossFileCompactions.ContainsKey($recordHash)) {
            if ($crossFileCompactions[$recordHash] -ne $file.FullName) {
              $health.CrossFileDuplicateCompactions++
              $health.CompactionDuplicateBytes += [long]$recordBytes
            }
          } else {
            $crossFileCompactions[$recordHash] = $file.FullName
            $health.CompactionUniqueSnapshots++
          }
        }
        continue
      }

      if ($record.type -eq "response_item" -and $record.payload.type -eq "function_call") {
        $structuredArgumentText = if ($record.payload.arguments -is [string]) { ([string]$record.payload.arguments).Trim() } else { '' }
        if ($structuredArgumentText -match '^[\{\[]' -and
            -not (Test-RolloutJsonUnambiguous $structuredArgumentText)) {
          $health.MalformedRecords++
          continue
        }
        $fileToolCalls++
        $functionName = Get-SafeCategory $record.payload @("name")
        $arguments = ConvertFrom-StructuredArguments $record.payload.arguments
        $approvalClass = Get-FunctionCallApprovalRequestClass $record
        Add-ApprovalRequestObservation $health $approvalClass $recordTimestamp $approvalClasses `
          $approvalPrefixes $approvalBoundaryCauses $approvalSources $approvalStates `
          $approvalRequestCorrelations $approvalSchemas
        if ($currentTurnIsReviewer) {
          $health.ReviewerToolCalls++
          $sandboxPermission = Get-SafeCategory $arguments @("sandbox_permissions", "permission_class")
          if ($sandboxPermission -eq "require_escalated") {
            $health.ReviewerEscalationsObserved++
            $escalationPrefix = Get-CanonicalPrefixFingerprint $arguments
            if ($escalationPrefix) {
              if ($reviewerEscalationPrefixes.ContainsKey($escalationPrefix)) {
                $reviewerEscalationPrefixes[$escalationPrefix]++
              } else { $reviewerEscalationPrefixes[$escalationPrefix] = 1 }
            }
          }
        }
        if ($functionName -eq "spawn_agent") {
          $health.SpawnCalls++
          $fileSpawns++
          if ($fileMultiAgentSchema -eq "v2") { $health.SpawnSchemaV2++ }
          elseif ($fileMultiAgentSchema -eq "v1") { $health.SpawnSchemaV1++ }
          else { $health.SpawnSchemaUnknown++ }
          if ($fileParentLinkSeen) { $health.ChildAgentSpawns++ } else { $health.RootAgentSpawns++ }
          $forkProperty = if ($arguments) { $arguments.PSObject.Properties["fork_turns"] } else { $null }
          $forkValue = if ($forkProperty -and $null -ne $forkProperty.Value) {
            ([string]$forkProperty.Value).Trim().ToLowerInvariant()
          } else { "unknown" }
          if (-not $forkProperty -and $fileMultiAgentSchema -eq "v1") {
            $legacyForkProperty = if ($arguments) { $arguments.PSObject.Properties["fork_context"] } else { $null }
            if ($legacyForkProperty -and $legacyForkProperty.Value -is [bool]) {
              $forkValue = if ([bool]$legacyForkProperty.Value) { "all" } else { "none" }
            } else {
              $forkValue = "unknown"
              $health.SpawnForkUnknown++
            }
          } elseif (-not $forkProperty) {
            $health.SpawnForkUnknown++
          }
          if ($forkValue -eq "all") {
            $health.SpawnForkAll++
            $health.SpawnInheritedTurnsObserved += $fileTurnCount
          } elseif ($forkValue -eq "none") {
            $health.SpawnForkNone++
          } elseif ($forkValue -match '^\d+$') {
            $health.SpawnForkBounded++
            $health.SpawnInheritedTurnsObserved += [math]::Min($fileTurnCount, [int]$forkValue)
          }
          $workerEffort = Get-SafeCategory $arguments @("reasoning_effort", "effort")
          if ($workerEffort -in @("high", "xhigh", "max", "ultra")) { $health.SpawnHighEffort++ }
          if ($workerEffort -in @("max", "ultra")) { $health.SpawnMaxEffort++ }
          $taskComplexity = Get-SafeCategory $arguments @("task_complexity", "complexity")
          if ($forkValue -eq "all" -and $taskComplexity -in @("simple", "low", "bounded", "mechanical")) {
            $health.SpawnContextAmplification = "observed"
          }
        }
      }
      if ($record.type -eq "response_item" -and $record.payload.type -eq "function_call_output") {
        $callProperty = $record.payload.PSObject.Properties["call_id"]
        $callId = if ($callProperty -and $null -ne $callProperty.Value) { [string]$callProperty.Value } else { $null }
        $resolvedKey = if ($callId -and $callId.Length -le 512) { Get-TextFingerprint $callId } else { $null }
        Resolve-ApprovalObservation $health $resolvedKey $recordTimestamp $approvalStates `
          $approvalResolutionLatencies $approvalResolvedAllowedEquivalences
      }
    }

    if ($reviewerSeenInFile -and $fileParentLinkSeen) {
      $health.ReviewerParentLinksObserved++
    }
    if (
      $reviewerSeenInFile -and $reviewerFileFirst -ne [DateTimeOffset]::MaxValue -and
      $reviewerFileLast -ne [DateTimeOffset]::MinValue
    ) {
      $reviewerIntervals.Add([pscustomobject]@{ Start = $reviewerFileFirst; End = $reviewerFileLast })
    }
    $ageUsesFilesystemFallback = $fileFirstRecordTimestamp -eq [DateTimeOffset]::MaxValue
    if ($ageUsesFilesystemFallback) { $health.RolloutAgeFilesystemFallbackFiles++ }
    $fileStats.Add([pscustomobject]@{
        SessionKey = $fileSessionKey
        ParentKey = $fileParentKey
        HasParent = $fileParentLinkSeen
        ReviewerTurns = $fileReviewerTurns
        Compactions = $fileCompactions
        ToolCalls = $fileToolCalls
        Spawns = $fileSpawns
        AgeDays = [math]::Max(0.0, (
            (Get-Date).ToUniversalTime() -
            $(if (-not $ageUsesFilesystemFallback) {
                $fileFirstRecordTimestamp.UtcDateTime
              } else { $file.CreationTimeUtc })
          ).TotalDays)
        IsReviewer = $reviewerSeenInFile
      })

    if ($firstIntervalSnapshot -and $lastIntervalSnapshot -and
        $lastIntervalTimestamp -gt $firstIntervalTimestamp -and
        $lastIntervalSnapshot.InputTokens -ge $firstIntervalSnapshot.InputTokens -and
        $lastIntervalSnapshot.CachedInputTokens -ge $firstIntervalSnapshot.CachedInputTokens -and
        $lastIntervalSnapshot.OutputTokens -ge $firstIntervalSnapshot.OutputTokens -and
        $lastIntervalSnapshot.ReasoningTokens -ge $firstIntervalSnapshot.ReasoningTokens) {
      $health.IntervalFiles++
      $intervalInputTokens += [long]$lastIntervalSnapshot.InputTokens - [long]$firstIntervalSnapshot.InputTokens
      $intervalCachedInputTokens += [long]$lastIntervalSnapshot.CachedInputTokens - [long]$firstIntervalSnapshot.CachedInputTokens
      $intervalOutputTokens += [long]$lastIntervalSnapshot.OutputTokens - [long]$firstIntervalSnapshot.OutputTokens
      $intervalReasoningTokens += [long]$lastIntervalSnapshot.ReasoningTokens - [long]$firstIntervalSnapshot.ReasoningTokens
      if ($lastIntervalSnapshot.CacheWriteAvailable -and $firstIntervalSnapshot.CacheWriteAvailable -and
          $lastIntervalSnapshot.CacheWriteTokens -ge $firstIntervalSnapshot.CacheWriteTokens) {
        $intervalCacheWriteFiles++
        $intervalCacheWriteTokens += [long]$lastIntervalSnapshot.CacheWriteTokens - [long]$firstIntervalSnapshot.CacheWriteTokens
      }
      if ($firstIntervalTimestamp -lt $intervalStart) { $intervalStart = $firstIntervalTimestamp }
      if ($lastIntervalTimestamp -gt $intervalEnd) { $intervalEnd = $lastIntervalTimestamp }
    }

    if ($lastSnapshot) {
      $health.Files++
      $health.CacheWriteSelectedFiles++
      $aggregateSnapshot = $lastSnapshot
      if ($fileInheritedSnapshot -and $lastSnapshot.TotalTokens -ge $fileInheritedSnapshot.TotalTokens) {
        $aggregateSnapshot = [pscustomobject]@{
          InputTokens = [math]::Max(0L, [long]$lastSnapshot.InputTokens - [long]$fileInheritedSnapshot.InputTokens)
          CachedInputTokens = [math]::Max(0L, [long]$lastSnapshot.CachedInputTokens - [long]$fileInheritedSnapshot.CachedInputTokens)
          CacheWriteTokens = [math]::Max(0L, [long]$lastSnapshot.CacheWriteTokens - [long]$fileInheritedSnapshot.CacheWriteTokens)
          CacheWriteAvailable = [bool]$lastSnapshot.CacheWriteAvailable -and [bool]$fileInheritedSnapshot.CacheWriteAvailable
          OutputTokens = [math]::Max(0L, [long]$lastSnapshot.OutputTokens - [long]$fileInheritedSnapshot.OutputTokens)
          ReasoningTokens = [math]::Max(0L, [long]$lastSnapshot.ReasoningTokens - [long]$fileInheritedSnapshot.ReasoningTokens)
        }
        $health.TokenLineageDeltaFiles++
      }
      $inputTokens += [long]$aggregateSnapshot.InputTokens
      $cachedInputTokens += [long]$aggregateSnapshot.CachedInputTokens
      if ($aggregateSnapshot.CacheWriteAvailable) {
        $cacheWriteAvailableFiles++
        $health.CacheWriteAvailableFiles++
        $cacheWriteTokens += [long]$aggregateSnapshot.CacheWriteTokens
      }
      $outputTokens += [long]$aggregateSnapshot.OutputTokens
      $reasoningTokens += [long]$aggregateSnapshot.ReasoningTokens

      if ($fileTurnCount -gt 0 -and $fileReviewerTurns -eq $fileTurnCount) {
        $reviewerInputTokens += [long]$aggregateSnapshot.InputTokens
        $health.ReviewerTokenAttribution = "homogeneous_file_role"
      } elseif ($fileReviewerTurns -eq 0) {
        $primaryInputTokens += [long]$aggregateSnapshot.InputTokens
        if ($health.ReviewerTokenAttribution -eq "unavailable") { $health.ReviewerTokenAttribution = "homogeneous_file_role" }
      } else {
        $unclassifiedInputTokens += [long]$aggregateSnapshot.InputTokens
        $health.ReviewerTokenAttribution = "mixed_role_file_unclassified"
      }

      if ($lastSnapshot.ContextWindow -gt 0) {
        $contextPercent = 100.0 * [long]$lastSnapshot.LastTotalTokens /
          [long]$lastSnapshot.ContextWindow
        $maxContextPercent = [math]::Max($maxContextPercent, $contextPercent)
      }
    }

    if ($lastTurnContext) {
      $effort = [string]$lastTurnContext.effort
      if ($effort -in @("high", "xhigh", "max", "ultra")) {
        $health.HighEffortSessions++
      }
      if ($effort -in @("xhigh", "max", "ultra")) {
        $health.ExtremeEffortSessions++
      }
      if ($effort -eq "ultra") {
        $health.UltraSessions++
      }
    }
  }

  if ($health.FilesSelected -eq 0) {
    $health.CoverageContinuity = "unknown"
  } elseif (
    $health.CoverageCapped -or $health.TailTruncatedFiles -gt 0 -or
    $health.UnreadableFiles -gt 0 -or
    $health.TailIncompleteFiles -gt 0 -or $health.MalformedRecords -gt 0 -or
    $health.DuplicateRecords -gt 0 -or $health.OutOfOrderRecords -gt 0
  ) {
    $health.CoverageContinuity = "partial"
  } else {
    $health.CoverageContinuity = "complete"
  }
  if ($health.IntervalFiles -gt 0) {
    $health.IntervalInputM = [math]::Round($intervalInputTokens / 1000000.0, 3)
    $health.IntervalCachedInputM = [math]::Round($intervalCachedInputTokens / 1000000.0, 3)
    $health.IntervalOutputM = [math]::Round($intervalOutputTokens / 1000000.0, 3)
    $health.IntervalReasoningM = [math]::Round($intervalReasoningTokens / 1000000.0, 3)
    $health.IntervalCacheWriteM = if ($intervalCacheWriteFiles -gt 0) {
      [math]::Round($intervalCacheWriteTokens / 1000000.0, 3)
    } else { $null }
    $health.IntervalStartUtc = $intervalStart.ToUniversalTime().ToString("o")
    $health.IntervalEndUtc = $intervalEnd.ToUniversalTime().ToString("o")
    $health.IntervalObservation = if ($health.CoverageContinuity -eq "complete") {
      "observed"
    } else { "observed_partial_coverage" }
  } elseif ($health.Samples -gt 0) {
    $health.IntervalObservation = "insufficient_comparable_samples"
  }
  if ($health.CoverageContinuity -ne "complete") {
    $health.RolloutGrowthMiBPerHour = $null
    $health.RolloutProjected24hMiB = $null
    $health.RolloutProjectionComparable = $false
    $health.RolloutGrowthObservation = "suppressed_partial_coverage"
  } elseif ($null -ne $health.RolloutGrowthMiBPerHour) {
    $health.RolloutProjectionComparable = $true
  }
  $health.QuotaConfidence = if ($health.FilesSelected -eq 0) {
    "unavailable"
  } elseif ($health.CoverageContinuity -eq "complete") { "high" } else { "low" }
  if ($health.ReviewerTurnsObserved -gt 0) { $health.EffectiveReviewer = "auto_review" }
  $health.ReviewerConfigurationComparison = if (
    $health.ConfiguredReviewer -eq "unavailable" -or $health.EffectiveReviewer -eq "unavailable"
  ) { "unavailable" } elseif ($health.ConfiguredReviewer -eq $health.EffectiveReviewer) {
    "same_label"
  } else { "different_labels_mapping_possible" }
  $comparableTurns = $health.ReviewerTurnsObserved + $health.PrimaryTurnsObserved
  if ($comparableTurns -gt 0) {
    $health.ApprovalReviewTurnShare = [math]::Round(100.0 * $health.ReviewerTurnsObserved / $comparableTurns, 1)
  }
  $knownApprovalDecisions = $health.ApprovalAllowedObserved + $health.ApprovalDeniedObserved
  if ($knownApprovalDecisions -gt 0) {
    $health.ApprovalAllowPercent = [math]::Round(
      100.0 * $health.ApprovalAllowedObserved / $knownApprovalDecisions, 2
    )
  }
  if ($health.ApprovalRequestsObserved -gt 0) {
    $health.InspectionShapedApprovalPercent = [math]::Round(
      100.0 * $health.InspectionShapedApprovalRequests / $health.ApprovalRequestsObserved, 1
    )
  }
  if ($approvalBoundaryCauses.Count -gt 0) {
    $health.ApprovalBoundaryCauses = @($approvalBoundaryCauses.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $_.Name + ":" + $_.Value
      }) -join ","
  }
  if ($health.ApprovalPersistenceRetries -gt 0) {
    $health.ApprovalPersistenceDiagnosis = "approval_state_persistence_runaway"
    $health.ApprovalProblemClass = "persistence_runaway"
  } elseif ($health.ApprovalPersistenceFailures -gt 0) {
    $health.ApprovalPersistenceDiagnosis = "persistence_write_error_observed"
    $health.ApprovalProblemClass = "persistence_error"
  }
  if ($approvalPrefixes.Count -gt 0) {
    $health.ApprovalRepeatedPrefixRequests = [int](@($approvalPrefixes.Values | ForEach-Object {
          [math]::Max(0, [int]$_ - 1)
        } | Measure-Object -Sum).Sum)
    $health.ApprovalLargestPrefixRepeat = [int](@($approvalPrefixes.Values | Measure-Object -Maximum).Maximum)
  }
  if ($approvalResolvedAllowedEquivalences.Count -gt 0) {
    $health.ApprovalResolvedAllowedEquivalences = $approvalResolvedAllowedEquivalences.Count
    $health.ApprovalLargestResolvedAllowedRepeat = [int](@(
        $approvalResolvedAllowedEquivalences.Values | Measure-Object -Maximum
      ).Maximum)
    if ($health.ApprovalLargestResolvedAllowedRepeat -ge 2 -and
        $health.ApprovalPersistenceDiagnosis -eq "not_observed") {
      $health.ApprovalRuleMissDiagnosis = "repeated_rule_miss_candidate"
      $health.ApprovalProblemClass = "rule_miss_amplification"
    }
  }
  if ($health.ApprovalProblemClass -eq "unavailable" -and $health.ApprovalRequestsObserved -gt 0) {
    $health.ApprovalProblemClass = "legitimate_or_diverse_boundary_volume"
  }
  if ($reviewerEscalationPrefixes.Count -gt 0) {
    $health.ReviewerEscalationUniquePrefixes = $reviewerEscalationPrefixes.Count
    $health.ReviewerEscalationRepeatedPrefixes = [int](@($reviewerEscalationPrefixes.Values | ForEach-Object {
          [math]::Max(0, [int]$_ - 1)
        } | Measure-Object -Sum).Sum)
    $health.ReviewerEscalationLargestPrefix = [int](@($reviewerEscalationPrefixes.Values | Measure-Object -Maximum).Maximum)
  }

  $statsBySession = @{}
  foreach ($stat in $fileStats) { $statsBySession[$stat.SessionKey] = $stat }
  foreach ($stat in @($fileStats | Where-Object { $_.IsReviewer -and $_.ParentKey })) {
    if ($statsBySession.ContainsKey($stat.ParentKey) -and $statsBySession[$stat.ParentKey].IsReviewer) {
      $health.NestedReviewerSessionsObserved++
    }
  }
  if ($health.ReviewerEscalationsObserved -gt 0 -and $health.NestedReviewerSessionsObserved -gt 0) {
    $health.ApprovalRecursionRisk = "observed"
  }
  $health.NestedAgentObservation = if ($health.SpawnCalls -eq 0) {
    "unavailable"
  } elseif ($health.ChildAgentSpawns -gt 0) { "observed" } else { "not_observed" }
  if ($fileStats.Count -gt 0) {
    $health.RolloutMaxTaskAgeDays = [math]::Round(
      [double](@($fileStats | Measure-Object AgeDays -Maximum).Maximum), 1
    )
    $health.RolloutAgeObservation = if ($health.HeadMetadataUnavailableFiles -gt 0) {
      "partial_head_metadata"
    } elseif ($health.RolloutAgeFilesystemFallbackFiles -gt 0) {
      "observed_with_filesystem_creation_fallback"
    } else { "observed" }
    $lineageReviews = @{}
    foreach ($stat in $fileStats) {
      $root = $stat.SessionKey
      $cursor = $stat
      for ($depth = 0; $depth -lt 16; $depth++) {
        if (-not $cursor.ParentKey -or -not $statsBySession.ContainsKey($cursor.ParentKey)) { break }
        $root = $cursor.ParentKey
        $cursor = $statsBySession[$cursor.ParentKey]
      }
      if ($lineageReviews.ContainsKey($root)) { $lineageReviews[$root] += $stat.ReviewerTurns }
      else { $lineageReviews[$root] = $stat.ReviewerTurns }
    }
    if ($health.ReviewerTurnsObserved -gt 0) {
      $rankedLineages = @($lineageReviews.Values | Sort-Object -Descending)
      if ($rankedLineages.Count -gt 0) {
        $health.RolloutTop1ReviewShare = [math]::Round(100.0 * $rankedLineages[0] / $health.ReviewerTurnsObserved, 1)
        $top3 = [int](@($rankedLineages | Select-Object -First 3 | Measure-Object -Sum).Sum)
        $health.RolloutTop3ReviewShare = [math]::Round(100.0 * $top3 / $health.ReviewerTurnsObserved, 1)
      }
    }
  }
  $health.SpawnObservation = if ($health.SpawnCalls -gt 0) {
    "observed"
  } elseif ($multiAgentV2Seen) {
    "unsupported"
  } elseif ($health.CoverageContinuity -eq "partial") {
    "partial"
  } elseif ($health.CoverageContinuity -eq "complete") {
    "not_observed_in_window"
  } else {
    "unavailable"
  }
  $health.CompactionObservation = if ($health.Compactions -gt 0) {
    "observed"
  } elseif ($health.CoverageContinuity -eq "partial") {
    "partial"
  } elseif ($health.CoverageContinuity -eq "complete") {
    "not_observed_in_window"
  } else {
    "unavailable"
  }
  $health.ReviewerCoverage = $health.CoverageContinuity
  $health.ReviewerObservation = if ($health.ReviewerTurnsObserved -gt 0) {
    if ($health.CoverageContinuity -eq "complete") { "observed" } else { "observed_partial_coverage" }
  } elseif ($health.CoverageContinuity -eq "partial") {
    "partial"
  } elseif ($health.CoverageContinuity -eq "complete") {
    "not_observed_in_window"
  } else {
    "unavailable"
  }
  if ($reviewerModels.Count -gt 0) {
    $health.ReviewerModels = @($reviewerModels | Sort-Object) -join ","
  }
  if ($codexVersions.Count -gt 0) {
    $health.CodexVersionsObserved = @($codexVersions | Sort-Object) -join ","
  }
  if ($authProviders.Count -gt 0) {
    $health.AuthProvidersObserved = @($authProviders | Sort-Object) -join ","
  }
  if ($approvalModes.Count -gt 0) {
    $health.ApprovalModesObserved = @($approvalModes | Sort-Object) -join ","
  }
  if ($approvalSchemas.Count -gt 0) {
    $health.ApprovalRequestSchemas = @($approvalSchemas | Sort-Object) -join ","
  }
  $health.ApprovalUnresolvedRequests = [math]::Max(
    0, $health.ApprovalRequestsObserved - $health.ApprovalResolvedRequests
  )
  if ($health.ApprovalRequestsObserved -gt 0) {
    $health.ApprovalResolutionObservation = if (
      $health.ApprovalResolvedRequests -eq $health.ApprovalRequestsObserved
    ) {
      "observed_complete_outcomes"
    } elseif ($health.ApprovalResolvedRequests -gt 0) {
      "observed_partial_outcomes"
    } else { "requests_observed_no_structured_outcome" }
  }
  if ($approvalResolutionLatencies.Count -gt 0) {
    $orderedLatencies = @($approvalResolutionLatencies | Sort-Object)
    $health.ApprovalLatencySamples = $orderedLatencies.Count
    $middle = [int][math]::Floor($orderedLatencies.Count / 2)
    $medianLatency = if ($orderedLatencies.Count % 2 -eq 0) {
      ($orderedLatencies[$middle - 1] + $orderedLatencies[$middle]) / 2.0
    } else { $orderedLatencies[$middle] }
    $health.ApprovalMedianLatencyMs = [math]::Round($medianLatency, 1)
    $p95LatencyIndex = [math]::Max(0, [int][math]::Ceiling(0.95 * $orderedLatencies.Count) - 1)
    $health.ApprovalP95LatencyMs = [math]::Round($orderedLatencies[$p95LatencyIndex], 1)
  }
  if ($reviewTimestamps.Count -ge 2) {
    $orderedReviewTimestamps = @($reviewTimestamps | Sort-Object)
    $reviewDuration = $orderedReviewTimestamps[-1] - $orderedReviewTimestamps[0]
    $health.ReviewerObservationSeconds = [math]::Round($reviewDuration.TotalSeconds, 1)
    $reviewDurationHours = $reviewDuration.TotalHours
    if ($reviewDurationHours -gt 0) {
      $health.ReviewerReviewsPerHour = [math]::Round(($health.ReviewerTurnsObserved - 1) / $reviewDurationHours, 1)
      $health.ReviewerRateNormalized = $true
    }
    $reviewIntervalsSeconds = for ($index = 1; $index -lt $orderedReviewTimestamps.Count; $index++) {
      ($orderedReviewTimestamps[$index] - $orderedReviewTimestamps[$index - 1]).TotalSeconds
    }
    if (@($reviewIntervalsSeconds).Count -gt 0) {
      $health.ReviewerAverageIntervalSeconds = [math]::Round(
        (@($reviewIntervalsSeconds | Measure-Object -Average).Average), 1
      )
      $orderedIntervals = @($reviewIntervalsSeconds | Sort-Object)
      $middle = [int][math]::Floor($orderedIntervals.Count / 2)
      $median = if ($orderedIntervals.Count % 2 -eq 0) {
        ($orderedIntervals[$middle - 1] + $orderedIntervals[$middle]) / 2.0
      } else { $orderedIntervals[$middle] }
      $health.ReviewerMedianIntervalSeconds = [math]::Round($median, 1)
    }
    $minuteGroups = @($orderedReviewTimestamps | Group-Object {
        $_.ToUniversalTime().ToString("yyyyMMddHHmm")
      } | Sort-Object Name)
    $health.ReviewerPeakPerMinute = @($minuteGroups | Measure-Object Count -Maximum).Maximum
    $minuteCounts = @($minuteGroups | ForEach-Object { $_.Count } | Sort-Object)
    if ($minuteCounts.Count -gt 0) {
      $p95Index = [math]::Max(0, [int][math]::Ceiling(0.95 * $minuteCounts.Count) - 1)
      $health.ReviewerP95PerMinute = $minuteCounts[$p95Index]
    }
    $longestActive = 0
    $currentActive = 0
    $priorMinute = $null
    foreach ($group in $minuteGroups) {
      $minute = [DateTime]::ParseExact($group.Name, "yyyyMMddHHmm", [System.Globalization.CultureInfo]::InvariantCulture)
      if ($priorMinute -and ($minute - $priorMinute).TotalMinutes -eq 1) { $currentActive++ } else { $currentActive = 1 }
      if ($currentActive -gt $longestActive) { $longestActive = $currentActive }
      $priorMinute = $minute
    }
    $health.ReviewerConsecutiveActiveMinutes = $longestActive
    $health.ReviewerRateConfidence = if (
      $health.CoverageContinuity -ne "complete" -or $reviewDuration.TotalMinutes -lt 15 -or
      $health.ReviewerTurnsObserved -lt 20
    ) { "low" } elseif ($reviewDuration.TotalHours -lt 1 -or $health.ReviewerTurnsObserved -lt 100) {
      "medium"
    } else { "high" }
  } elseif ($reviewTimestamps.Count -eq 1) {
    $health.ReviewerPeakPerMinute = 1
    $health.ReviewerP95PerMinute = 1
    $health.ReviewerConsecutiveActiveMinutes = 1
    $health.ReviewerRateConfidence = "low"
  }
  foreach ($interval in $reviewerIntervals) {
    $concurrent = @($reviewerIntervals | Where-Object {
        $_.Start -le $interval.End -and $_.End -ge $interval.Start
      }).Count
    if ($concurrent -gt $health.ReviewerConcurrentPeak) {
      $health.ReviewerConcurrentPeak = $concurrent
    }
  }
  if ($parsedBytes -gt 0) {
    $health.CrossFileReplayPercent = [math]::Round(
      100.0 * [long]$health.CrossFileDuplicateBytes / [long]$parsedBytes, 1
    )
  }
  if ($health.RolloutGrowthObservation -ne "suppressed_partial_coverage" -and
      $null -eq $health.RolloutGrowthMiBPerHour) {
    $health.RolloutGrowthObservation = "insufficient_file_lifetime"
  }
  if ($health.ApprovalRequestsObserved -gt 0) {
    $health.ApprovalUniqueClasses = $approvalClasses.Count
    $health.ApprovalRepeatedRequests = [int](@($approvalClasses.Values | ForEach-Object {
          [math]::Max(0, [int]$_ - 1)
        } | Measure-Object -Sum).Sum)
    if ($approvalClasses.Count -gt 0) {
      $classedRequests = [int](@($approvalClasses.Values | Measure-Object -Sum).Sum)
      $health.ApprovalRepeatPercent = if ($classedRequests -gt 0) {
        [math]::Round(100.0 * $health.ApprovalRepeatedRequests / $classedRequests, 1)
      } else { $null }
      $health.ApprovalRequestObservation = if ($health.CoverageContinuity -eq "complete") {
        "observed"
      } else { "observed_partial_coverage" }
    } else {
      $health.ApprovalRequestObservation = "observed_insufficient_structure"
    }
    $health.ApprovalSources = @($approvalSources.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $_.Name + ":" + $_.Value
      }) -join ","
  }
  $health.ApprovalDeniedObservation = if ($health.ApprovalDecisionsObserved -gt 0) {
    "observed"
  } elseif ($health.ApprovalRequestsObserved -gt 0) {
    "response_schema_unavailable"
  } else {
    "unavailable"
  }
  $health.ApprovalOptimization = if ($health.ApprovalPersistenceDiagnosis -eq "approval_state_persistence_runaway") {
    "repair_persistence_before_cost_optimization"
  } elseif ($health.ApprovalRuleMissDiagnosis -eq "repeated_rule_miss_candidate") {
    "manual_narrow_rule_review"
  } elseif ($health.ApprovalRequestsObserved -gt 0) {
    "no_change_recommended"
  } elseif ($health.ReviewerTurnsObserved -gt 0) {
    "diagnostic_only_request_schema_unavailable"
  } else {
    "none"
  }

  if ($health.Files -eq 0) {
    return [pscustomobject]$health
  }

  $health.SessionInputM = [math]::Round($inputTokens / 1000000.0, 1)
  $health.CachedReadPercent = if ($inputTokens -gt 0) {
    [math]::Round(100.0 * $cachedInputTokens / $inputTokens, 1)
  } else { 0.0 }
  if ($cacheWriteAvailableFiles -gt 0) {
    $health.CacheWriteM = [math]::Round($cacheWriteTokens / 1000000.0, 1)
    $health.CacheWriteObserved = $cacheWriteTokens -gt 0
    $health.CacheWriteObservation = if ($cacheWriteAvailableFiles -eq $health.CacheWriteSelectedFiles) {
      "observed"
    } else {
      "observed_partial_schema"
    }
  }
  $health.ReasoningPercent = if ($outputTokens -gt 0) {
    [math]::Round(100.0 * $reasoningTokens / $outputTokens, 1)
  } else { 0.0 }
  $health.MaxContextPercent = [math]::Round($maxContextPercent, 1)
  $health.ReviewerInputM = [math]::Round($reviewerInputTokens / 1000000.0, 1)
  $health.PrimaryInputM = [math]::Round($primaryInputTokens / 1000000.0, 1)
  $health.ReviewerUnclassifiedInputM = [math]::Round($unclassifiedInputTokens / 1000000.0, 1)
  if ($primaryInputTokens -gt 0) {
    $health.ReviewerMainInputRatio = [math]::Round($reviewerInputTokens / [double]$primaryInputTokens, 3)
  }

  if ($health.HighEffortSessions -gt 0) { $advice.Add("lower-effort") }
  if ($health.MaxContextPercent -ge 60) { $advice.Add("fresh-task") }
  if ($health.UltraSessions -gt 0 -or $health.SpawnCalls -gt 0) {
    $advice.Add("bound-subagents")
  }
  if ($health.Compactions -ge 2) { $advice.Add("avoid-repeat-compaction") }
  if ($health.CacheWriteObserved) { $advice.Add("cache-write-risk") }
  if ($advice.Count -gt 0) {
    $health.Advice = $advice -join ","
    $health.AdviceReason = "measured_action_conditions"
  }

  $cacheWriteThreshold = [math]::Max(1.0, [double]$inputTokens * 0.25)

  if ($cacheWriteTokens -ge $cacheWriteThreshold) { $quotaContributors.Add("cache-write-volume") }
  if ($health.UltraSessions -gt 0) { $quotaContributors.Add("ultra-session") }
  if ($health.SpawnCalls -ge 4) { $quotaContributors.Add("spawn-calls-4plus") }
  if ($health.Compactions -ge 3) { $quotaContributors.Add("compactions-3plus") }
  if ($health.HighEffortSessions -gt 0 -and $health.MaxContextPercent -ge 60) {
    $quotaContributors.Add("high-effort-high-context")
  }
  if ($inputTokens -ge 50000000) { $quotaContributors.Add("input-50m") }

  if (
    $cacheWriteTokens -ge $cacheWriteThreshold -or
    $health.UltraSessions -gt 0 -or $health.SpawnCalls -ge 4 -or
    $health.Compactions -ge 3 -or
    ($health.HighEffortSessions -gt 0 -and $health.MaxContextPercent -ge 60) -or
    $inputTokens -ge 50000000
  ) {
    $health.Level = "HIGH"
  } elseif (
    $health.HighEffortSessions -gt 0 -or $health.SpawnCalls -gt 0 -or
    $health.Compactions -gt 0 -or $health.MaxContextPercent -ge 40 -or
    $inputTokens -ge 10000000
  ) {
    $health.Level = "ELEVATED"
    if ($health.HighEffortSessions -gt 0) { $quotaContributors.Add("high-effort-session") }
    if ($health.SpawnCalls -gt 0) { $quotaContributors.Add("spawn-call-observed") }
    if ($health.Compactions -gt 0) { $quotaContributors.Add("compaction-observed") }
    if ($health.MaxContextPercent -ge 40) { $quotaContributors.Add("context-40pct") }
    if ($inputTokens -ge 10000000) { $quotaContributors.Add("input-10m") }
  } else {
    $health.Level = "LOW"
  }
  if ($quotaContributors.Count -gt 0) {
    $health.QuotaContributors = @($quotaContributors | Select-Object -Unique) -join ","
  }

  [pscustomobject]$health
}

function Get-CodexFamily {
  $family = [System.Collections.Generic.List[object]]::new()
  foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
    try { $name = [string]$process.ProcessName } catch { continue }
    if ($name.Equals("Codex", [System.StringComparison]::Ordinal) -or
        $name.Equals("codex", [System.StringComparison]::Ordinal) -or
        $name.Equals("node_repl", [System.StringComparison]::Ordinal) -or
        $name -like "codex-command-runner-*") { $family.Add($process) }
  }
  @($family)
}

function Get-CpuBaseline($processes) {
  $baseline = @{}
  foreach ($process in $processes) {
    try {
      $id = [int]$process.Id
      $cpu = $process.CPU
      if ($null -ne $cpu) { $baseline[$id] = [double]$cpu }
    } catch { continue }
  }
  $baseline
}

function Get-CpuDelta($process, $baseline) {
  try {
    $id = [int]$process.Id
    $cpu = $process.CPU
    if (-not $baseline.ContainsKey($id) -or $null -eq $cpu) { return 0 }
    [math]::Max(0.0, [double]$cpu - $baseline[$id])
  } catch { 0 }
}

function Get-SafeProcessSample($process, $baseline) {
  $complete = $true
  try { $id = [int]$process.Id } catch { return $null }
  try { $name = [string]$process.ProcessName } catch { return $null }
  try { $privateBytes = [long]$process.PrivateMemorySize64 } catch { $privateBytes = 0L; $complete = $false }
  try { $handles = [int]$process.HandleCount } catch { $handles = 0; $complete = $false }
  try { $threads = [int]$process.Threads.Count } catch { $threads = 0; $complete = $false }
  try { $startTime = $process.StartTime } catch { $startTime = $null; $complete = $false }
  try {
    $cpu = $process.CPU
    $cpuDelta = if ($null -ne $cpu -and $baseline.ContainsKey($id)) {
      [math]::Max(0.0, [double]$cpu - $baseline[$id])
    } else { 0.0 }
  } catch { $cpuDelta = 0.0; $complete = $false }
  [pscustomobject]@{
    Id = $id
    ProcessName = $name
    PrivateMemorySize64 = $privateBytes
    HandleCount = $handles
    ThreadCount = $threads
    StartTime = $startTime
    CpuDelta = $cpuDelta
    Complete = $complete
  }
}

function Get-FreeDiskGB($path) {
  $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($path))
  try {
    $drive = [System.IO.DriveInfo]::new($root)
    if (-not $drive.IsReady) { return -1 }
    [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
  } catch {
    -1
  }
}

function Get-Snapshot {
  $initial = Get-CodexFamily
  $baseline = Get-CpuBaseline $initial
  Start-Sleep -Seconds $SampleSeconds
  $family = Get-CodexFamily
  $samples = [System.Collections.Generic.List[object]]::new()
  $inaccessible = 0
  foreach ($process in $family) {
    $sample = Get-SafeProcessSample $process $baseline
    if (-not $sample) { $inaccessible++; continue }
    if (-not $sample.Complete) { $inaccessible++ }
    $samples.Add($sample)
  }
  $privateMB = [math]::Round((($samples | Measure-Object PrivateMemorySize64 -Sum).Sum / 1MB), 1)
  $handles = [int](($samples | Measure-Object HandleCount -Sum).Sum)
  $threads = [int](($samples | Measure-Object ThreadCount -Sum).Sum)
  $cpuDelta = [math]::Round((($samples | Measure-Object CpuDelta -Sum).Sum), 2)

  [pscustomobject]@{
    Family = $family
    Count = $samples.Count
    Desktop = @($samples | Where-Object { $_.ProcessName.Equals("Codex", [System.StringComparison]::Ordinal) }).Count
    Helpers = @($samples | Where-Object { $_.ProcessName.Equals("codex", [System.StringComparison]::Ordinal) }).Count
    NodeRepl = @($samples | Where-Object { $_.ProcessName.Equals("node_repl", [System.StringComparison]::Ordinal) }).Count
    Runners = @($samples | Where-Object ProcessName -like "codex-command-runner-*").Count
    PrivateMB = $privateMB
    Handles = $handles
    Threads = $threads
    CpuCores = [math]::Round($cpuDelta / $SampleSeconds, 2)
    DiskFreeGB = Get-FreeDiskGB $CodexHome
    Baseline = $baseline
    InaccessibleProcesses = $inaccessible
    ProcessSampleObservation = if ($inaccessible -gt 0) { "partial" } else { "complete" }
  }
}

function Get-ProcessLevel($snapshot) {
  if (
    $snapshot.Count -ge 100 -or $snapshot.NodeRepl -ge 50 -or
    $snapshot.PrivateMB -ge 4096 -or $snapshot.Handles -ge 30000 -or
    ($snapshot.DiskFreeGB -ge 0 -and $snapshot.DiskFreeGB -lt 5)
  ) { return "CRITICAL" }

  if (
    $snapshot.Count -ge 40 -or $snapshot.NodeRepl -ge 20 -or
    $snapshot.PrivateMB -ge 2048 -or $snapshot.Handles -ge 15000 -or
    $snapshot.CpuCores -ge 1 -or
    ($snapshot.DiskFreeGB -ge 0 -and $snapshot.DiskFreeGB -lt 10)
  ) { return "WARNING" }

  "HEALTHY"
}

function Get-ProcessLevelReasons($snapshot, [string]$Level) {
  $reasons = [System.Collections.Generic.List[string]]::new()
  if ($Level -eq "CRITICAL") {
    if ($snapshot.Count -ge 100) { $reasons.Add("process-count-100") }
    if ($snapshot.NodeRepl -ge 50) { $reasons.Add("node-repl-50") }
    if ($snapshot.PrivateMB -ge 4096) { $reasons.Add("private-memory-4096mb") }
    if ($snapshot.Handles -ge 30000) { $reasons.Add("handles-30000") }
    if ($snapshot.DiskFreeGB -ge 0 -and $snapshot.DiskFreeGB -lt 5) { $reasons.Add("disk-free-below-5gb") }
  } elseif ($Level -eq "WARNING") {
    if ($snapshot.Count -ge 40) { $reasons.Add("process-count-40") }
    if ($snapshot.NodeRepl -ge 20) { $reasons.Add("node-repl-20") }
    if ($snapshot.PrivateMB -ge 2048) { $reasons.Add("private-memory-2048mb") }
    if ($snapshot.Handles -ge 15000) { $reasons.Add("handles-15000") }
    if ($snapshot.CpuCores -ge 1) { $reasons.Add("cpu-1-core") }
    if ($snapshot.DiskFreeGB -ge 0 -and $snapshot.DiskFreeGB -lt 10) { $reasons.Add("disk-free-below-10gb") }
  }
  if ($reasons.Count -eq 0) { "none" } else { @($reasons) -join "," }
}

function Get-LogDbLevel($metrics) {
  if (-not $metrics.Present) { return "UNAVAILABLE" }

  if (
    $metrics.DatabaseGiB -ge 4 -or $metrics.ReclaimableGiB -ge 2 -or
    $metrics.WalMiB -ge 512 -or
    ($null -ne $metrics.InsertRate -and $metrics.InsertRate -ge 500)
  ) { return "CRITICAL" }

  if ($metrics.Availability -ne "full") { return "WARNING" }

  if (
    $metrics.DatabaseGiB -ge 0.5 -or $metrics.ReclaimableGiB -ge 0.25 -or
    $metrics.WalMiB -ge 64 -or
    ($null -ne $metrics.InsertRate -and $metrics.InsertRate -ge 10) -or
    ($metrics.WalActive -and $null -ne $metrics.TracePercent -and $metrics.TracePercent -ge 50)
  ) { return "WARNING" }

  "HEALTHY"
}

function Get-LogDbReasons($metrics, [string]$Level) {
  if (-not $metrics.Present) { return "unavailable" }
  $reasons = [System.Collections.Generic.List[string]]::new()
  if ($metrics.Availability -eq "partial") { $reasons.Add("query-partial") }
  elseif ($metrics.Availability -eq "unavailable") { $reasons.Add("query-unavailable") }
  if ($Level -eq "CRITICAL") {
    if ($metrics.DatabaseGiB -ge 4) { $reasons.Add("database-size-4gib") }
    if ($metrics.ReclaimableGiB -ge 2) { $reasons.Add("reclaimable-2gib") }
    if ($metrics.WalMiB -ge 512) { $reasons.Add("wal-512mib") }
    if ($null -ne $metrics.InsertRate -and $metrics.InsertRate -ge 500) {
      $reasons.Add("insert-rate-500ps")
    }
  } elseif ($Level -eq "WARNING") {
    if ($metrics.DatabaseGiB -ge 0.5) { $reasons.Add("database-size-0.5gib") }
    if ($metrics.ReclaimableGiB -ge 0.25) { $reasons.Add("reclaimable-0.25gib") }
    if ($metrics.WalMiB -ge 64) { $reasons.Add("wal-64mib") }
    if ($null -ne $metrics.InsertRate -and $metrics.InsertRate -ge 10) {
      $reasons.Add("insert-rate-10ps")
    }
    if ($metrics.WalActive -and $null -ne $metrics.TracePercent -and $metrics.TracePercent -ge 50) {
      $reasons.Add("active-wal-trace-50pct")
    }
  }
  if ($reasons.Count -eq 0) { return "none" }
  $reasons -join ","
}

function Get-WorseLevel($left, $right) {
  $rank = @{ "UNAVAILABLE" = -1; "HEALTHY" = 0; "WARNING" = 1; "CRITICAL" = 2 }
  if ($rank[$right] -gt $rank[$left]) { return $right }
  $left
}

function Format-Metric($value) {
  if ($null -eq $value) { return "unknown" }
  if ($value -is [bool]) { return $value.ToString().ToLowerInvariant() }
  if ($value -is [System.IFormattable]) {
    return $value.ToString($null, [System.Globalization.CultureInfo]::InvariantCulture)
  }
  $value.ToString()
}

function Get-Candidates($snapshot) {
  $now = Get-Date
  $candidates = [System.Collections.Generic.List[object]]::new()
  foreach ($process in @($snapshot.Family)) {
    try {
      $id = [int]$process.Id
      if ($ProcessId -gt 0 -and $id -ne $ProcessId) { continue }
      $name = [string]$process.ProcessName
      if ($name -ne "node_repl" -and $name -notlike "codex-command-runner-*") { continue }
      $startTime = $process.StartTime
      $ageMinutes = ($now - $startTime).TotalMinutes
      $cpuDelta = Get-CpuDelta $process $snapshot.Baseline
      if ($ageMinutes -lt $MinAgeMinutes -or $cpuDelta -gt 0.02) { continue }
      $candidates.Add([pscustomobject]@{
          PID = $id
          Name = $name
          AgeMinutes = [math]::Floor($ageMinutes)
          StartTime = $startTime
        })
    } catch {
      continue
    }
  }
  @($candidates)
}

$logBefore = if ($Action -eq "inspect") { Get-LogDbSample } else { $null }
$snapshot = Get-Snapshot
$processLevel = Get-ProcessLevel $snapshot
$processReasons = Get-ProcessLevelReasons $snapshot $processLevel

if ($Action -eq "inspect") {
  $logAfter = Get-LogDbSample
  $logMetrics = Get-LogDbMetrics $logBefore $logAfter
  $logLevel = Get-LogDbLevel $logMetrics
  $logReasons = Get-LogDbReasons $logMetrics $logLevel
  $filesystemHelper = Get-FilesystemHelperHealth
  $quotaHealth = Get-QuotaHealth
  $machineLevel = Get-WorseLevel $processLevel $filesystemHelper.Level
  $machineContributors = [System.Collections.Generic.List[string]]::new()
  if ($processReasons -ne "none") { $machineContributors.Add($processReasons) }
  if ($filesystemHelper.CopyFailure) { $machineContributors.Add("filesystem-helper-copy-failure") }
  if ($filesystemHelper.LaunchFailure) { $machineContributors.Add("filesystem-helper-launch-failure") }
  $machineContributorText = if ($machineContributors.Count) { @($machineContributors) -join "," } else { "none" }
  $resourceLevel = Get-WorseLevel $machineLevel $logLevel
  $quotaLevel = if ($quotaHealth.Level -eq 'HIGH') { 'CRITICAL' } elseif ($quotaHealth.Level -eq 'ELEVATED') { 'WARNING' } elseif ($quotaHealth.Level -eq 'LOW') { 'HEALTHY' } else { 'UNAVAILABLE' }
  $overallLevel = Get-WorseLevel (Get-WorseLevel $resourceLevel $quotaLevel) $quotaHealth.RuleStatus
  $diskDisplay = if ($snapshot.DiskFreeGB -lt 0) { "unknown" } else { $snapshot.DiskFreeGB }
  $headline = ("CHRONOS {0} advisory=true family={1} desktop={2} helpers={3} node_repl={4} runners={5} privateMB={6} handles={7} threads={8} cpuCores={9} diskFreeGB={10} fsHelper={11} fsHelperCopyFailure={12} fsHelperLaunchFailure={13} pcRestartAdvised={14} logDb={15} logDbGiB={16} logReclaimableGiB={17} logWalMiB={18} logWalActive={19} logSeq={20} logRate={21} logTracePct={22} quotaRisk={23} tokenFiles={24} tokenSamples={25} tokenSessionInputM={26} tokenCachedReadPct={27} tokenCacheWriteM={28} tokenCacheWriteObserved={29} tokenReasoningPct={30} tokenMaxContextPct={31} tokenHighEffortSessions={32} tokenExtremeEffortSessions={33} tokenUltraSessions={34} tokenSpawnCalls={35} tokenCompactions={36} tokenMalformedRecords={37} tokenDuplicateRecords={38} tokenOutOfOrderRecords={39} tokenTailIncompleteFiles={40} machineHealth={41} tokenCoverageWindowHours={42} tokenCoverageStartUtc={43} tokenCoverageEndUtc={44} tokenFilesEligible={45} tokenFilesSelected={46} tokenCoverageCapped={47} tokenTailTruncatedFiles={48} tokenUnreadableFiles={49} tokenCoverageContinuity={50} tokenSpawnObservation={51} tokenCompactionObservation={52} approvalReviewTurnsObserved={53} approvalReviewerSessionsObserved={54} approvalReviewerModels={55} approvalReviewObservation={56} approvalReviewCoverage={57} approvalReviewsPerHour={58} approvalReviewerInputM={59} approvalPrimaryInputM={60} approvalReviewerMainInputRatio={61} approvalRequestObservation={62} approvalOptimization={63} rolloutSelectedMiB={64} rolloutGrowthMiBPerHour={65} rolloutCrossFileDuplicateRecords={66} rolloutCrossFileDuplicateCompactions={67} tokenUsageScope={68} approvalAverageIntervalSeconds={69} approvalPeakPerMinute={70} approvalConcurrentPeak={71} approvalParentLinksObserved={72} approvalRequestsObserved={73} approvalUniqueClasses={74} approvalRepeatedRequests={75} approvalRepeatPct={76} approvalSources={77} approvalDeniedObserved={78} approvalDeniedObservation={79} rolloutCrossFileDuplicateBytes={80} rolloutReplayPct={81} compactionUniqueSnapshots={82} compactionDuplicateBytes={83} rolloutGrowthObservation={84} rolloutProjected24hMiB={85} rolloutLineageLinksObserved={86} rolloutForkFilesObserved={87} rolloutNearSizeClusterFiles={88} codexVersionsObserved={89} authProvidersObserved={90} tokenInheritedSnapshots={91} tokenLineageDeltaFiles={92} logDbReasons={93} logDbPerformanceImpact={94} quotaRiskScope={95} tokenAdviceReason={96} approvalModesObserved={97} reviewerControlCapability={98} reviewerCompatibility={99} tokenQuotaContributors={100} tokenAdvice={101}" -f `
    $machineLevel, $snapshot.Count, $snapshot.Desktop, $snapshot.Helpers, $snapshot.NodeRepl,
    $snapshot.Runners, $snapshot.PrivateMB, $snapshot.Handles, $snapshot.Threads,
    $snapshot.CpuCores, $diskDisplay, $filesystemHelper.Level,
    (Format-Metric $filesystemHelper.CopyFailure),
    (Format-Metric $filesystemHelper.LaunchFailure),
    (Format-Metric $filesystemHelper.PcRestartAdvised),
    $logLevel, (Format-Metric $logMetrics.DatabaseGiB),
    (Format-Metric $logMetrics.ReclaimableGiB), (Format-Metric $logMetrics.WalMiB),
    (Format-Metric $logMetrics.WalActive), (Format-Metric $logMetrics.Sequence),
    (Format-Metric $logMetrics.InsertRate), (Format-Metric $logMetrics.TracePercent),
    $quotaHealth.Level, $quotaHealth.Files, $quotaHealth.Samples,
    (Format-Metric $quotaHealth.SessionInputM),
    (Format-Metric $quotaHealth.CachedReadPercent),
    (Format-Metric $quotaHealth.CacheWriteM),
    (Format-Metric $quotaHealth.CacheWriteObserved),
    (Format-Metric $quotaHealth.ReasoningPercent),
    (Format-Metric $quotaHealth.MaxContextPercent),
    $quotaHealth.HighEffortSessions, $quotaHealth.ExtremeEffortSessions,
    $quotaHealth.UltraSessions, $quotaHealth.SpawnCalls, $quotaHealth.Compactions,
    $quotaHealth.MalformedRecords, $quotaHealth.DuplicateRecords,
    $quotaHealth.OutOfOrderRecords, $quotaHealth.TailIncompleteFiles,
    $machineLevel, $quotaHealth.CoverageWindowHours,
    (Format-Metric $quotaHealth.CoverageStartUtc), (Format-Metric $quotaHealth.CoverageEndUtc),
    $quotaHealth.FilesEligible, $quotaHealth.FilesSelected,
    (Format-Metric $quotaHealth.CoverageCapped), $quotaHealth.TailTruncatedFiles,
    $quotaHealth.UnreadableFiles, $quotaHealth.CoverageContinuity,
    $quotaHealth.SpawnObservation, $quotaHealth.CompactionObservation,
    $quotaHealth.ReviewerTurnsObserved, $quotaHealth.ReviewerSessionsObserved,
    $quotaHealth.ReviewerModels, $quotaHealth.ReviewerObservation,
    $quotaHealth.ReviewerCoverage, (Format-Metric $quotaHealth.ReviewerReviewsPerHour),
    (Format-Metric $quotaHealth.ReviewerInputM), (Format-Metric $quotaHealth.PrimaryInputM),
    (Format-Metric $quotaHealth.ReviewerMainInputRatio), $quotaHealth.ApprovalRequestObservation,
    $quotaHealth.ApprovalOptimization, (Format-Metric $quotaHealth.RolloutSelectedMiB),
    (Format-Metric $quotaHealth.RolloutGrowthMiBPerHour), $quotaHealth.CrossFileDuplicateRecords,
    $quotaHealth.CrossFileDuplicateCompactions, $quotaHealth.TokenUsageScope,
    (Format-Metric $quotaHealth.ReviewerAverageIntervalSeconds),
    $quotaHealth.ReviewerPeakPerMinute, $quotaHealth.ReviewerConcurrentPeak,
    $quotaHealth.ReviewerParentLinksObserved, $quotaHealth.ApprovalRequestsObserved,
    $quotaHealth.ApprovalUniqueClasses, $quotaHealth.ApprovalRepeatedRequests,
    (Format-Metric $quotaHealth.ApprovalRepeatPercent), $quotaHealth.ApprovalSources,
    $quotaHealth.ApprovalDeniedObserved, $quotaHealth.ApprovalDeniedObservation,
    $quotaHealth.CrossFileDuplicateBytes, (Format-Metric $quotaHealth.CrossFileReplayPercent),
    $quotaHealth.CompactionUniqueSnapshots, $quotaHealth.CompactionDuplicateBytes,
    $quotaHealth.RolloutGrowthObservation, (Format-Metric $quotaHealth.RolloutProjected24hMiB),
    $quotaHealth.RolloutLineageLinksObserved, $quotaHealth.RolloutForkFilesObserved,
    $quotaHealth.RolloutNearSizeClusterFiles, $quotaHealth.CodexVersionsObserved,
    $quotaHealth.AuthProvidersObserved,
    $quotaHealth.InheritedTokenSnapshots, $quotaHealth.TokenLineageDeltaFiles,
    $logReasons, "not_measured", "selected_rollout_window", $quotaHealth.AdviceReason,
    $quotaHealth.ApprovalModesObserved, $quotaHealth.ReviewerControlCapability,
    $quotaHealth.ReviewerCompatibility,
    $quotaHealth.QuotaContributors,
    $quotaHealth.Advice)
  Write-Output $headline
  $efficiencyFields = [ordered]@{
    inspectionEvidenceVersion = 1
    inspectionRunId = [guid]::NewGuid().ToString('N')
    inspectionCapturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    pluginVersion = $script:ChronosPluginVersion
    installCurrentSource = $script:ChronosInstallStatus.CurrentSource
    installSourceObservation = $script:ChronosInstallStatus.SourceObservation
    installCachedSources = $script:ChronosInstallStatus.CachedSources
    installCachedDuplicateSources = $script:ChronosInstallStatus.CachedDuplicateSources
    installLegacyGitConfig = $script:ChronosInstallStatus.LegacyGitConfig
    installSourceConflict = $script:ChronosInstallStatus.SourceConflict
    installCanonicalSource = $script:ChronosInstallStatus.CanonicalSource
    installSessionReloadRequired = $script:ChronosInstallStatus.SessionReloadRequired
    installRecommendedAction = $script:ChronosInstallStatus.RecommendedAction
    headlineScope = 'machine_health'
    processDiagnosticLevel = $processLevel
    machineHealthContributors = $machineContributorText
    machineHealthConfidence = if ($snapshot.InaccessibleProcesses -gt 0) {
      'threshold_observation_partial_process_sample'
    } else { 'threshold_observation_only' }
    responsivenessObservation = 'not_measured'
    processSampleSeconds = $SampleSeconds
    processInaccessible = $snapshot.InaccessibleProcesses
    processSampleObservation = $snapshot.ProcessSampleObservation
    processOwnershipObservation = 'executable_name_only_unverified'
    filesystemHelperObservation = 'known_markers_15m'
    resourceDiagnosticLevel = $resourceLevel
    overallDiagnosticLevel = $overallLevel
    logDbAvailability = $logMetrics.Availability
    logDbQueryOk = $logMetrics.QueryOk
    logDbPageMetricsOk = $logMetrics.PageMetricsOk
    logDbSequenceOk = $logMetrics.SequenceOk
    logDbLevelRowsOk = $logMetrics.LevelRowsOk
    sqliteOpenMode = $logMetrics.SqliteOpenMode
    sqliteJournalMode = $logMetrics.SqliteJournalMode
    sqliteSidecarMutationPossible = $logMetrics.SqliteSidecarMutationPossible
    sqliteSidecarMutationObserved = $logMetrics.SqliteSidecarMutationObserved
    cacheWriteObservation = $quotaHealth.CacheWriteObservation
    cacheWriteAvailableFiles = $quotaHealth.CacheWriteAvailableFiles
    cacheWriteSelectedFiles = $quotaHealth.CacheWriteSelectedFiles
    rolloutRateSemantics = 'file_lifetime_average_not_measured_delta'
    rolloutInventoryTimedOut = $quotaHealth.InventoryTimedOut
    rolloutInventoryEntries = $quotaHealth.InventoryEntries
    rolloutInventoryEntryLimit = $quotaHealth.InventoryEntryLimit
    rolloutInventoryEntryLimitHit = $quotaHealth.InventoryEntryLimitHit
    reviewerConcurrencySemantics = 'file_activity_span_estimate'
    metricSource = $quotaHealth.ApprovalMetricSource
    dashboardEquivalence = $quotaHealth.DashboardEquivalence
    billingInference = $quotaHealth.BillingInference
    quotaConfidence = $quotaHealth.QuotaConfidence
    quotaRiskBasis = $quotaHealth.QuotaRiskBasis
    tokenSelectedCumulativeInputM = $quotaHealth.SessionInputM
    tokenIntervalInputM = $quotaHealth.IntervalInputM
    tokenIntervalCachedInputM = $quotaHealth.IntervalCachedInputM
    tokenIntervalOutputM = $quotaHealth.IntervalOutputM
    tokenIntervalReasoningM = $quotaHealth.IntervalReasoningM
    tokenIntervalCacheWriteM = $quotaHealth.IntervalCacheWriteM
    tokenIntervalFiles = $quotaHealth.IntervalFiles
    tokenIntervalStartUtc = $quotaHealth.IntervalStartUtc
    tokenIntervalEndUtc = $quotaHealth.IntervalEndUtc
    tokenIntervalObservation = $quotaHealth.IntervalObservation
    rolloutProjectionComparable = $quotaHealth.RolloutProjectionComparable
    primaryTurnsObserved = $quotaHealth.PrimaryTurnsObserved
    approvalReviewTurnsObserved = $quotaHealth.ReviewerTurnsObserved
    reviewerTokenAttribution = $quotaHealth.ReviewerTokenAttribution
    reviewerUnclassifiedInputM = $quotaHealth.ReviewerUnclassifiedInputM
    approvalReviewTurnShare = $quotaHealth.ApprovalReviewTurnShare
    approvalDecisionsObserved = $quotaHealth.ApprovalDecisionsObserved
    approvalAllowedObserved = $quotaHealth.ApprovalAllowedObserved
    approvalDeniedObserved = $quotaHealth.ApprovalDeniedObserved
    approvalUnknownDecisions = $quotaHealth.ApprovalUnknownDecisions
    approvalAllowPct = $quotaHealth.ApprovalAllowPercent
    approvalRequestSchemas = $quotaHealth.ApprovalRequestSchemas
    approvalResolvedRequests = $quotaHealth.ApprovalResolvedRequests
    approvalUnresolvedRequests = $quotaHealth.ApprovalUnresolvedRequests
    approvalResolutionObservation = $quotaHealth.ApprovalResolutionObservation
    approvalLatencySamples = $quotaHealth.ApprovalLatencySamples
    approvalMedianLatencyMs = $quotaHealth.ApprovalMedianLatencyMs
    approvalP95LatencyMs = $quotaHealth.ApprovalP95LatencyMs
    approvalPersistenceRetries = $quotaHealth.ApprovalPersistenceRetries
    approvalPersistenceFailures = $quotaHealth.ApprovalPersistenceFailures
    approvalPersistenceDiagnosis = $quotaHealth.ApprovalPersistenceDiagnosis
    approvalRepeatedPrefixRequests = $quotaHealth.ApprovalRepeatedPrefixRequests
    approvalLargestPrefixRepeat = $quotaHealth.ApprovalLargestPrefixRepeat
    approvalResolvedAllowedEquivalences = $quotaHealth.ApprovalResolvedAllowedEquivalences
    approvalLargestResolvedAllowedRepeat = $quotaHealth.ApprovalLargestResolvedAllowedRepeat
    approvalRuleMissDiagnosis = $quotaHealth.ApprovalRuleMissDiagnosis
    approvalProblemClass = $quotaHealth.ApprovalProblemClass
    inspectionShapedApprovalRequests = $quotaHealth.InspectionShapedApprovalRequests
    inspectionShapedApprovalPct = $quotaHealth.InspectionShapedApprovalPercent
    approvalBoundaryCauses = $quotaHealth.ApprovalBoundaryCauses
    approvalObservationSeconds = $quotaHealth.ReviewerObservationSeconds
    approvalRateNormalized = $quotaHealth.ReviewerRateNormalized
    approvalRateConfidence = $quotaHealth.ReviewerRateConfidence
    approvalMedianIntervalSeconds = $quotaHealth.ReviewerMedianIntervalSeconds
    approvalP95PerMinute = $quotaHealth.ReviewerP95PerMinute
    approvalConsecutiveActiveMinutes = $quotaHealth.ReviewerConsecutiveActiveMinutes
    reviewerToolCalls = $quotaHealth.ReviewerToolCalls
    reviewerEscalationsObserved = $quotaHealth.ReviewerEscalationsObserved
    reviewerEscalationUniquePrefixes = $quotaHealth.ReviewerEscalationUniquePrefixes
    reviewerEscalationRepeatedPrefixes = $quotaHealth.ReviewerEscalationRepeatedPrefixes
    reviewerEscalationLargestPrefix = $quotaHealth.ReviewerEscalationLargestPrefix
    nestedReviewerSessionsObserved = $quotaHealth.NestedReviewerSessionsObserved
    approvalRecursionRisk = $quotaHealth.ApprovalRecursionRisk
    ruleObservation = $quotaHealth.RuleObservation
    ruleCount = $quotaHealth.RuleCount
    ruleMonolithic = $quotaHealth.RuleMonolithic
    ruleReusableNarrow = $quotaHealth.RuleReusableNarrow
    ruleBroadInterpreter = $quotaHealth.RuleBroadInterpreter
    ruleCredentialShaped = $quotaHealth.RuleCredentialShaped
    ruleSecretCandidateOrdinals = $quotaHealth.RuleCredentialCandidateOrdinals
    ruleSecretCandidateClasses = $quotaHealth.RuleCredentialCandidateClasses
    ruleSecretConfidence = $quotaHealth.RuleCredentialConfidence
    ruleAverageLength = $quotaHealth.RuleAverageLength
    ruleMaximumLiteralLength = $quotaHealth.RuleMaximumLiteralLength
    ruleStatus = $quotaHealth.RuleStatus
    ruleValuesReturned = $quotaHealth.RuleValuesReturned
    ruleFilesEligible = $quotaHealth.RuleFilesEligible
    ruleFilesSelected = $quotaHealth.RuleFilesSelected
    ruleCoverageCapped = $quotaHealth.RuleCoverageCapped
    ruleParseFailures = $quotaHealth.RuleParseFailures
    ruleBrittlenessDiagnosis = $quotaHealth.RuleBrittlenessDiagnosis
    ruleSecretDiagnosis = $quotaHealth.RuleSecretDiagnosis
    ruleBroadInterpreterDiagnosis = $quotaHealth.RuleBroadInterpreterDiagnosis
    rolloutMaxTaskAgeDays = $quotaHealth.RolloutMaxTaskAgeDays
    rolloutAgeObservation = $quotaHealth.RolloutAgeObservation
    rolloutAgeFilesystemFallbackFiles = $quotaHealth.RolloutAgeFilesystemFallbackFiles
    rolloutHeadTruncatedFiles = $quotaHealth.HeadTruncatedFiles
    rolloutHeadMetadataUnavailableFiles = $quotaHealth.HeadMetadataUnavailableFiles
    rolloutTop1ReviewShare = $quotaHealth.RolloutTop1ReviewShare
    rolloutTop3ReviewShare = $quotaHealth.RolloutTop3ReviewShare
    spawnForkAll = $quotaHealth.SpawnForkAll
    spawnForkAllDefaulted = $quotaHealth.SpawnForkAllDefaulted
    spawnForkNone = $quotaHealth.SpawnForkNone
    spawnForkBounded = $quotaHealth.SpawnForkBounded
    spawnForkUnknown = $quotaHealth.SpawnForkUnknown
    spawnSchemaV1 = $quotaHealth.SpawnSchemaV1
    spawnSchemaV2 = $quotaHealth.SpawnSchemaV2
    spawnSchemaUnknown = $quotaHealth.SpawnSchemaUnknown
    spawnHighEffort = $quotaHealth.SpawnHighEffort
    spawnMaxEffort = $quotaHealth.SpawnMaxEffort
    spawnInheritedTurnsObserved = $quotaHealth.SpawnInheritedTurnsObserved
    spawnContextAmplification = $quotaHealth.SpawnContextAmplification
    rootAgentSpawns = $quotaHealth.RootAgentSpawns
    childAgentSpawns = $quotaHealth.ChildAgentSpawns
    nestedAgentObservation = $quotaHealth.NestedAgentObservation
    configuredReviewer = $quotaHealth.ConfiguredReviewer
    effectiveReviewer = $quotaHealth.EffectiveReviewer
    managedReviewer = $quotaHealth.ManagedReviewer
    reviewerConfigurationComparison = $quotaHealth.ReviewerConfigurationComparison
    primaryReasoningDefault = $quotaHealth.PrimaryReasoningDefault
  }
  $efficiencyText = @($efficiencyFields.GetEnumerator() | ForEach-Object {
      $_.Key + "=" + (Format-Metric $_.Value)
    }) -join " "
  Write-Output ("CHRONOS EFFICIENCY " + $efficiencyText)
  exit 0
}

$candidates = @(Get-Candidates $snapshot)
Write-Output ("CHRONOS PLAN advisoryOnly=true candidates={0} minAgeMinutes={1}" -f $candidates.Count, $MinAgeMinutes)

if ($Action -eq "plan") { exit 0 }
Write-Output "CHRONOS CLEANUP disabled=advisory-only stopped=0"
