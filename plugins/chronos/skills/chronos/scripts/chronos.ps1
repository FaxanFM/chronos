param(
  [ValidateSet("inspect", "plan", "cleanup")]
  [string]$Action = "inspect",
  [int]$MinAgeMinutes = 60,
  [int]$ProcessId = 0,
  [string]$CodexHome = (Join-Path $HOME ".codex"),
  [ValidateRange(1, 10)]
  [int]$SampleSeconds = 2,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

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
  $capturedAt = Get-Date
  $databaseFile = Get-Item -LiteralPath $databasePath -ErrorAction SilentlyContinue
  $walFile = Get-Item -LiteralPath $walPath -ErrorAction SilentlyContinue

  $sample = [ordered]@{
    Present = $null -ne $databaseFile
    QueryOk = $false
    CapturedAt = $capturedAt
    DatabaseBytes = if ($databaseFile) { [long]$databaseFile.Length } else { 0L }
    WalBytes = if ($walFile) { [long]$walFile.Length } else { 0L }
    WalWriteTicks = if ($walFile) { [long]$walFile.LastWriteTimeUtc.Ticks } else { 0L }
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
    $pageSizeRows = $database.Query("PRAGMA page_size")
    $pageCountRows = $database.Query("PRAGMA page_count")
    $freelistRows = $database.Query("PRAGMA freelist_count")
    $sequenceRows = $database.Query("SELECT seq FROM sqlite_sequence WHERE name='logs'")
    $levelRows = $database.Query(
      "SELECT level, COUNT(*) FROM (SELECT level FROM logs ORDER BY id DESC LIMIT 2000) GROUP BY level"
    )

    $sample.PageSize = [long]$pageSizeRows[0][0]
    $sample.PageCount = [long]$pageCountRows[0][0]
    $sample.FreelistCount = [long]$freelistRows[0][0]
    if ($sequenceRows.Count -gt 0) { $sample.Sequence = [long]$sequenceRows[0][0] }

    foreach ($row in $levelRows) {
      $count = [int]$row[1]
      $sample.RecentRows += $count
      if ($row[0] -eq "TRACE") { $sample.TraceRows = $count }
    }
    $sample.QueryOk = $true
  } catch {
    $sample.QueryOk = $false
  } finally {
    if ($database) { $database.Dispose() }
  }

  [pscustomobject]$sample
}

function Get-LogDbMetrics($before, $after) {
  $elapsedSeconds = [math]::Max(0.001, ($after.CapturedAt - $before.CapturedAt).TotalSeconds)
  $rate = $null
  if ($before.QueryOk -and $after.QueryOk -and $null -ne $before.Sequence -and $null -ne $after.Sequence) {
    $sequenceDelta = [long]$after.Sequence - [long]$before.Sequence
    $rate = [math]::Round([math]::Max(0L, $sequenceDelta) / $elapsedSeconds, 1)
  }

  $tracePercent = $null
  if ($after.QueryOk -and $after.RecentRows -gt 0) {
    $tracePercent = [math]::Round(($after.TraceRows * 100.0) / $after.RecentRows, 1)
  }

  $reclaimableBytes = 0L
  if ($after.QueryOk) {
    $reclaimableBytes = $after.FreelistCount * $after.PageSize
  }

  [pscustomobject]@{
    Present = $after.Present
    QueryOk = $after.QueryOk
    DatabaseGiB = if ($after.Present) { [math]::Round($after.DatabaseBytes / 1GB, 2) } else { $null }
    ReclaimableGiB = if ($after.QueryOk) { [math]::Round($reclaimableBytes / 1GB, 2) } else { $null }
    WalMiB = if ($after.Present) { [math]::Round($after.WalBytes / 1MB, 1) } else { $null }
    WalActive = $after.WalWriteTicks -gt 0 -and $after.WalWriteTicks -ne $before.WalWriteTicks
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
      $_.LastWriteTimeUtc -ge $cutoff
    } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 2)

  if (-not $logs.Count) {
    return [pscustomobject]$health
  }

  $health.Present = $true
  $copyMarker = "helper copy failed for command-runner: remove stale helper destination"
  $launchMarker = "CreateProcessWithLogonW failed: 5"
  $successMarker = "] SUCCESS:"
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
      $timestampMatch = [regex]::Match(
        $line,
        "^\[(?<timestamp>\d{4}-\d{2}-\d{2}(?:T|\s)\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)"
      )
      if (-not $timestampMatch.Success) { continue }

      $timestamp = [DateTimeOffset]::MinValue
      if (-not [DateTimeOffset]::TryParse(
        $timestampMatch.Groups["timestamp"].Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
        [ref]$timestamp
      )) { continue }
      if ($timestamp -lt $markerCutoff) { continue }

      if ($line.IndexOf($copyMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
          $timestamp -gt $latestCopyFailure) {
        $latestCopyFailure = $timestamp
      }
      if ($line.IndexOf($launchMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
          $timestamp -gt $latestLaunchFailure) {
        $latestLaunchFailure = $timestamp
      }
      if ($line.IndexOf($successMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
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

function Get-RecentSessionFiles {
  $sessionsRoot = Join-Path $CodexHome "sessions"
  if (-not (Test-Path -LiteralPath $sessionsRoot -PathType Container)) { return @() }

  $cutoff = (Get-Date).ToUniversalTime().AddHours(-6)
  $files = @()
  foreach ($daysAgo in 0..1) {
    $day = (Get-Date).Date.AddDays(-$daysAgo)
    $dayPath = Join-Path (Join-Path (Join-Path $sessionsRoot $day.ToString("yyyy")) `
      $day.ToString("MM")) $day.ToString("dd")
    if (-not (Test-Path -LiteralPath $dayPath -PathType Container)) { continue }
    $files += @(Get-ChildItem -LiteralPath $dayPath -Filter "*.jsonl" -File `
      -ErrorAction SilentlyContinue)
  }

  @($files | Where-Object {
      $_.LastWriteTimeUtc -ge $cutoff
    } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 8)
}

function Get-QuotaHealth {
  $health = [ordered]@{
    Level = "UNAVAILABLE"
    Files = 0
    Samples = 0
    SessionInputM = $null
    CachedReadPercent = $null
    CacheWriteM = $null
    CacheWriteObserved = $false
    ReasoningPercent = $null
    MaxContextPercent = $null
    HighEffortSessions = 0
    ExtremeEffortSessions = 0
    UltraSessions = 0
    SpawnCalls = 0
    Compactions = 0
    Advice = "none"
  }

  $inputTokens = 0L
  $cachedInputTokens = 0L
  $cacheWriteTokens = 0L
  $outputTokens = 0L
  $reasoningTokens = 0L
  $maxContextPercent = 0.0
  $advice = [System.Collections.Generic.List[string]]::new()
  $sessionFiles = @(Get-RecentSessionFiles)

  foreach ($file in $sessionFiles) {
    $tail = Get-BoundedFileTail -Path $file.FullName
    if ([string]::IsNullOrEmpty($tail)) { continue }

    $lastInfo = $null
    $lastTurnContext = $null
    foreach ($line in ($tail -split "`r?`n")) {
      if (
        $line.IndexOf('"token_count"', [System.StringComparison]::Ordinal) -lt 0 -and
        $line.IndexOf('"turn_context"', [System.StringComparison]::Ordinal) -lt 0 -and
        $line.IndexOf('"context_compacted"', [System.StringComparison]::Ordinal) -lt 0 -and
        $line.IndexOf('"spawn_agent"', [System.StringComparison]::Ordinal) -lt 0
      ) { continue }

      try {
        $record = $line | ConvertFrom-Json -ErrorAction Stop
      } catch {
        continue
      }

      if ($record.type -eq "turn_context") {
        $lastTurnContext = $record.payload
        continue
      }

      if ($record.type -eq "event_msg") {
        if ($record.payload.type -eq "token_count") {
          $health.Samples++
          if ($record.payload.info) { $lastInfo = $record.payload.info }
        } elseif ($record.payload.type -eq "context_compacted") {
          $health.Compactions++
        }
        continue
      }

      if (
        $record.type -eq "response_item" -and
        $record.payload.type -eq "function_call" -and
        $record.payload.name -eq "spawn_agent"
      ) {
        $health.SpawnCalls++
      }
    }

    if ($lastInfo -and $lastInfo.total_token_usage) {
      $health.Files++
      $total = $lastInfo.total_token_usage
      $inputTokens += [long]$total.input_tokens
      $cachedInputTokens += [long]$total.cached_input_tokens
      $cacheWriteTokens += [long]$total.cache_write_input_tokens
      $outputTokens += [long]$total.output_tokens
      $reasoningTokens += [long]$total.reasoning_output_tokens

      if ($lastInfo.last_token_usage -and [long]$lastInfo.model_context_window -gt 0) {
        $contextPercent = 100.0 * [long]$lastInfo.last_token_usage.total_tokens /
          [long]$lastInfo.model_context_window
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

  if ($health.Files -eq 0) {
    return [pscustomobject]$health
  }

  $health.SessionInputM = [math]::Round($inputTokens / 1000000.0, 1)
  $health.CachedReadPercent = if ($inputTokens -gt 0) {
    [math]::Round(100.0 * $cachedInputTokens / $inputTokens, 1)
  } else { 0.0 }
  $health.CacheWriteM = [math]::Round($cacheWriteTokens / 1000000.0, 1)
  $health.CacheWriteObserved = $cacheWriteTokens -gt 0
  $health.ReasoningPercent = if ($outputTokens -gt 0) {
    [math]::Round(100.0 * $reasoningTokens / $outputTokens, 1)
  } else { 0.0 }
  $health.MaxContextPercent = [math]::Round($maxContextPercent, 1)

  if ($health.HighEffortSessions -gt 0) { $advice.Add("lower-effort") }
  if ($health.MaxContextPercent -ge 60) { $advice.Add("fresh-task") }
  if ($health.UltraSessions -gt 0 -or $health.SpawnCalls -gt 0) {
    $advice.Add("bound-subagents")
  }
  if ($health.Compactions -ge 2) { $advice.Add("avoid-repeat-compaction") }
  if ($health.CacheWriteObserved) { $advice.Add("cache-write-risk") }
  if ($advice.Count -gt 0) { $health.Advice = $advice -join "," }

  if (
    $cacheWriteTokens -ge [math]::Max(1, $inputTokens * 0.25) -or
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
  } else {
    $health.Level = "LOW"
  }

  [pscustomobject]$health
}

function Get-CodexFamily {
  @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -in @("Codex", "codex", "node_repl") -or
    $_.ProcessName -like "codex-command-runner-*"
  })
}

function Get-CpuBaseline($processes) {
  $baseline = @{}
  foreach ($process in $processes) {
    if ($null -ne $process.CPU) { $baseline[$process.Id] = [double]$process.CPU }
  }
  $baseline
}

function Get-CpuDelta($process, $baseline) {
  if (-not $baseline.ContainsKey($process.Id) -or $null -eq $process.CPU) { return 0 }
  [math]::Max(0, [double]$process.CPU - $baseline[$process.Id])
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

  $privateMB = [math]::Round((($family | Measure-Object PrivateMemorySize64 -Sum).Sum / 1MB), 1)
  $handles = [int](($family | Measure-Object HandleCount -Sum).Sum)
  $threads = [int](($family | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum)
  $cpuDelta = [math]::Round((($family | ForEach-Object { Get-CpuDelta $_ $baseline } | Measure-Object -Sum).Sum), 2)

  [pscustomobject]@{
    Family = $family
    Count = $family.Count
    Desktop = @($family | Where-Object ProcessName -eq "Codex").Count
    Helpers = @($family | Where-Object ProcessName -eq "codex").Count
    NodeRepl = @($family | Where-Object ProcessName -eq "node_repl").Count
    Runners = @($family | Where-Object ProcessName -like "codex-command-runner-*").Count
    PrivateMB = $privateMB
    Handles = $handles
    Threads = $threads
    CpuCores = [math]::Round($cpuDelta / $SampleSeconds, 2)
    DiskFreeGB = Get-FreeDiskGB $CodexHome
    Baseline = $baseline
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

function Get-LogDbLevel($metrics) {
  if (-not $metrics.Present) { return "UNAVAILABLE" }

  if (
    $metrics.DatabaseGiB -ge 4 -or $metrics.ReclaimableGiB -ge 2 -or
    $metrics.WalMiB -ge 512 -or
    ($null -ne $metrics.InsertRate -and $metrics.InsertRate -ge 500)
  ) { return "CRITICAL" }

  if (
    $metrics.DatabaseGiB -ge 0.5 -or $metrics.ReclaimableGiB -ge 0.25 -or
    $metrics.WalMiB -ge 64 -or
    ($null -ne $metrics.InsertRate -and $metrics.InsertRate -ge 10) -or
    ($metrics.WalActive -and $null -ne $metrics.TracePercent -and $metrics.TracePercent -ge 50)
  ) { return "WARNING" }

  "HEALTHY"
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
  @($snapshot.Family | Where-Object {
    if ($ProcessId -gt 0 -and $_.Id -ne $ProcessId) { return $false }
    $isEligibleName = $_.ProcessName -eq "node_repl" -or $_.ProcessName -like "codex-command-runner-*"
    if (-not $isEligibleName) { return $false }
    try {
      $ageMinutes = ($now - $_.StartTime).TotalMinutes
    } catch {
      return $false
    }
    $cpuDelta = Get-CpuDelta $_ $snapshot.Baseline
    $ageMinutes -ge $MinAgeMinutes -and $cpuDelta -le 0.02
  } | ForEach-Object {
    [pscustomobject]@{
      PID = $_.Id
      Name = $_.ProcessName
      AgeMinutes = [math]::Floor(((Get-Date) - $_.StartTime).TotalMinutes)
      StartTime = $_.StartTime
    }
  })
}

$logBefore = if ($Action -eq "inspect") { Get-LogDbSample } else { $null }
$snapshot = Get-Snapshot
$processLevel = Get-ProcessLevel $snapshot

if ($Action -eq "inspect") {
  $logAfter = Get-LogDbSample
  $logMetrics = Get-LogDbMetrics $logBefore $logAfter
  $logLevel = Get-LogDbLevel $logMetrics
  $filesystemHelper = Get-FilesystemHelperHealth
  $quotaHealth = Get-QuotaHealth
  $level = Get-WorseLevel (Get-WorseLevel $processLevel $logLevel) $filesystemHelper.Level
  $diskDisplay = if ($snapshot.DiskFreeGB -lt 0) { "unknown" } else { $snapshot.DiskFreeGB }
  Write-Output ("CHRONOS {0} advisory=true family={1} desktop={2} helpers={3} node_repl={4} runners={5} privateMB={6} handles={7} threads={8} cpuCores={9} diskFreeGB={10} fsHelper={11} fsHelperCopyFailure={12} fsHelperLaunchFailure={13} pcRestartAdvised={14} logDb={15} logDbGiB={16} logReclaimableGiB={17} logWalMiB={18} logWalActive={19} logSeq={20} logRate={21} logTracePct={22} quotaRisk={23} tokenFiles={24} tokenSamples={25} tokenSessionInputM={26} tokenCachedReadPct={27} tokenCacheWriteM={28} tokenCacheWriteObserved={29} tokenReasoningPct={30} tokenMaxContextPct={31} tokenHighEffortSessions={32} tokenExtremeEffortSessions={33} tokenUltraSessions={34} tokenSpawnCalls={35} tokenCompactions={36} tokenAdvice={37}" -f `
    $level, $snapshot.Count, $snapshot.Desktop, $snapshot.Helpers, $snapshot.NodeRepl,
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
    $quotaHealth.Advice)
  exit 0
}

$candidates = @(Get-Candidates $snapshot)
Write-Output ("CHRONOS PLAN advisoryOnly=true candidates={0} minAgeMinutes={1}" -f $candidates.Count, $MinAgeMinutes)

if ($Action -eq "plan") { exit 0 }
Write-Output "CHRONOS CLEANUP disabled=advisory-only stopped=0"
