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
    PageMetricsOk = $false
    SequenceOk = $false
    LevelRowsOk = $false
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
    try {
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
    PageMetricsOk = $after.PageMetricsOk
    SequenceOk = $after.SequenceOk
    LevelRowsOk = $after.LevelRowsOk
    DatabaseGiB = if ($after.Present) { [math]::Round($after.DatabaseBytes / 1GB, 2) } else { $null }
    ReclaimableGiB = if ($after.PageMetricsOk) { [math]::Round($reclaimableBytes / 1GB, 2) } else { $null }
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
  if (-not (Test-Path -LiteralPath $sessionsRoot -PathType Container)) {
    return [pscustomobject]@{
      Files = @(); EligibleCount = 0; SelectedCount = 0; Capped = $false
      WindowHours = 6; WindowStartUtc = $cutoff.ToString('o'); WindowEndUtc = $windowEnd.ToString('o')
    }
  }

  $inventoryLimit = 20000
  $files = @(Get-ChildItem -LiteralPath $sessionsRoot -Filter "*.jsonl" -File -Recurse `
      -ErrorAction SilentlyContinue | Select-Object -First ($inventoryLimit + 1))
  $inventoryCapped = $files.Count -gt $inventoryLimit
  if ($inventoryCapped) { $files = @($files | Select-Object -First $inventoryLimit) }

  $eligible = @($files | Where-Object {
      $_.LastWriteTimeUtc -ge $cutoff
    } | Sort-Object LastWriteTimeUtc -Descending)
  $selected = @($eligible | Select-Object -First 8)
  [pscustomobject]@{
    Files = $selected
    EligibleCount = $eligible.Count
    SelectedCount = $selected.Count
    Capped = $inventoryCapped -or $eligible.Count -gt $selected.Count
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
    try { return ($Value | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
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
  $search = 0
  while ($search -lt $text.Length -and $blocks.Count -lt $MaxRules) {
    $match = [regex]::Match($text, '\bprefix_rule\s*\(', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromSeconds(1))
    if ($search -gt 0) {
      $match = [regex]::Match($text.Substring($search), '\bprefix_rule\s*\(', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromSeconds(1))
      if ($match.Success) {
        $match = [pscustomobject]@{ Success = $true; Index = $match.Index + $search; Length = $match.Length }
      }
    }
    if (-not $match.Success) { break }
    $open = $text.IndexOf('(', [int]$match.Index)
    $depth = 0
    $inString = $false
    $quote = [char]0
    $escaped = $false
    $comment = $false
    $closed = $false
    $limit = [math]::Min($text.Length - 1, $open + $MaxRuleChars - 1)
    for ($index = $open; $index -le $limit; $index++) {
      $character = $text[$index]
      if ($comment) {
        if ($character -eq "`n") { $comment = $false }
        continue
      }
      if ($inString) {
        if ($escaped) { $escaped = $false; continue }
        if ($character -eq '\') { $escaped = $true; continue }
        if ($character -eq $quote) { $inString = $false }
        continue
      }
      if ($character -eq '#') { $comment = $true; continue }
      if ($character -eq '"' -or $character -eq "'") { $inString = $true; $quote = $character; continue }
      if ($character -eq '(') { $depth++; continue }
      if ($character -eq ')') {
        $depth--
        if ($depth -eq 0) {
          $blocks.Add($text.Substring([int]$match.Index, $index - [int]$match.Index + 1))
          $search = $index + 1
          $closed = $true
          break
        }
      }
    }
    if (-not $closed) { return [pscustomobject]@{ Blocks = @($blocks); Complete = $false } }
  }
  [pscustomobject]@{ Blocks = @($blocks); Complete = ($blocks.Count -lt $MaxRules) }
}

function Get-RuleHealth {
  $result = [ordered]@{
    Observation = "unavailable"
    Count = 0
    Monolithic = 0
    ReusableNarrow = 0
    BroadInterpreter = 0
    CredentialShaped = 0
    AverageLength = $null
    MaximumLiteralLength = 0
    Status = "UNAVAILABLE"
    ValuesReturned = $false
    FilesEligible = 0
    FilesSelected = 0
    CoverageCapped = $false
    ParseFailures = 0
  }
  $rulesRoot = Join-Path $CodexHome "rules"
  if (-not (Test-Path -LiteralPath $rulesRoot -PathType Container)) {
    $result.Observation = "not_found"
    return [pscustomobject]$result
  }
  $eligibleFiles = @(Get-ChildItem -LiteralPath $rulesRoot -File -ErrorAction SilentlyContinue | Where-Object {
      $_.Extension -in @(".rules", ".toml")
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
  foreach ($file in $files) {
    $parsedRules = Get-BoundedPrefixRuleBlocks $file.FullName
    if (-not $parsedRules.Complete) { $result.ParseFailures++; $result.CoverageCapped = $true }
    foreach ($block in @($parsedRules.Blocks)) {
      $trimmed = $block.Trim()
      $result.Count++
      $lengthTotal += $trimmed.Length
      $literalMatches = @([regex]::Matches($trimmed, '"(?:\\.|[^"\\])*"'))
      $literalLengths = @($literalMatches | ForEach-Object { [math]::Max(0, $_.Value.Length - 2) })
      $maxLiteral = if ($literalLengths.Count) { [int](@($literalLengths | Measure-Object -Maximum).Maximum) } else { 0 }
      if ($maxLiteral -gt $result.MaximumLiteralLength) { $result.MaximumLiteralLength = $maxLiteral }
      $isMonolithic = $maxLiteral -gt 256
      if ($isMonolithic) { $result.Monolithic++ }

      $firstLiteral = if ($literalMatches.Count) {
        $literalMatches[0].Value.Trim('"').Trim().ToLowerInvariant()
      } else { "" }
      $firstExecutable = [System.IO.Path]::GetFileNameWithoutExtension($firstLiteral)
      $isBroad = $firstExecutable -in @("powershell", "pwsh", "bash", "python", "python3", "node", "curl") -and $literalMatches.Count -le 2
      if ($isBroad) { $result.BroadInterpreter++ }
      if (-not $isMonolithic -and -not $isBroad) { $result.ReusableNarrow++ }

      $secretShape = $trimmed -match '(?i)(token|secret|password|passwd|api[_-]?key|access[_-]?key|client[_-]?secret)\s*[=:]' -or
        $trimmed -match '(?i)(sk-[a-z0-9_-]{12,}|gh[pousr]_[a-z0-9]{20,}|nfp_[a-z0-9]{20,}|AKIA[0-9A-Z]{16})'
      if ($secretShape) { $result.CredentialShaped++ }
    }
  }
  $result.Observation = if ($result.CoverageCapped) { "observed_partial" } else { "observed" }
  if ($result.Count -gt 0) { $result.AverageLength = [math]::Round($lengthTotal / [double]$result.Count, 1) }
  $result.Status = if ($result.CredentialShaped -gt 0) { "CRITICAL" } elseif (
    $result.Monolithic -gt 0 -or $result.BroadInterpreter -gt 0
  ) { "WARNING" } else { "HEALTHY" }
  [pscustomobject]$result
}

function Get-CodexConfigurationHealth {
  $result = [ordered]@{
    ConfiguredReviewer = "unavailable"
    ManagedReviewer = "unavailable"
    PrimaryReasoningDefault = "unavailable"
  }
  $path = Join-Path $CodexHome "config.toml"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]$result }
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
    Signature = if ($dimensions.Count -gt 0 -or $prefixFingerprint) {
      $payloadType + "|" + (@($dimensions | Sort-Object) -join "|") +
        $(if ($prefixFingerprint) { "|prefix:" + $prefixFingerprint } else { "|prefix:unavailable" })
    } else { $null }
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
    CachedReadPercent = $null
    CacheWriteM = $null
    CacheWriteObserved = $null
    CacheWriteObservation = "unsupported_schema"
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
    ApprovalRequestsObserved = 0
    ApprovalUniqueClasses = 0
    ApprovalRepeatedRequests = 0
    ApprovalRepeatPercent = $null
    ApprovalSources = "unavailable"
    ApprovalDeniedObserved = 0
    ApprovalDecisionsObserved = 0
    ApprovalAllowedObserved = 0
    ApprovalAllowPercent = $null
    ApprovalDeniedObservation = "unavailable"
    ApprovalPersistenceRetries = 0
    ApprovalPersistenceFailures = 0
    ApprovalPersistenceDiagnosis = "not_observed"
    ApprovalRepeatedPrefixRequests = 0
    ApprovalLargestPrefixRepeat = 0
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
    RolloutLineageLinksObserved = 0
    RolloutForkFilesObserved = 0
    RolloutNearSizeClusterFiles = 0
    RolloutMaxTaskAgeDays = $null
    RolloutTop1ReviewShare = $null
    RolloutTop3ReviewShare = $null
    SpawnForkAll = 0
    SpawnForkAllDefaulted = 0
    SpawnForkNone = 0
    SpawnForkBounded = 0
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
  }

  $inputTokens = 0L
  $cachedInputTokens = 0L
  $cacheWriteTokens = 0L
  $cacheWriteAvailableFiles = 0
  $outputTokens = 0L
  $reasoningTokens = 0L
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
  $multiAgentV2Seen = $false
  $crossFileRecords = @{}
  $crossFileCompactions = @{}
  $tokenSnapshotOwners = @{}
  $approvalClasses = @{}
  $approvalPrefixes = @{}
  $approvalBoundaryCauses = @{}
  $approvalStates = @{}
  $approvalSources = @{}
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
    if ([long]$file.Length -gt 2097152L) {
      $headText = Get-BoundedFileHead -Path $file.FullName
      foreach ($headLine in @($headText -split "`r?`n" | Select-Object -First 256)) {
        if ([string]::IsNullOrWhiteSpace($headLine)) { continue }
        try { $headRecord = $headLine | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($headRecord.type -ne "session_meta") { continue }
        $sessionIdentifier = Get-SafeCategory $headRecord.payload @("thread_id", "session_id", "id")
        if ($sessionIdentifier) { $fileSessionKey = Get-TextFingerprint $sessionIdentifier }
        $versionProperty = if ($headRecord.payload) { $headRecord.payload.PSObject.Properties["multi_agent_version"] } else { $null }
        if ($versionProperty -and [string]$versionProperty.Value -match '^\d+$' -and [int]$versionProperty.Value -ge 2) {
          $multiAgentV2Seen = $true
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
    }
    $lines = @($tail -split "`r?`n")
    if (-not $tail.EndsWith("`n", [System.StringComparison]::Ordinal)) {
      $lastLineComplete = $false
      if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[-1])) {
        try { $null = $lines[-1] | ConvertFrom-Json -ErrorAction Stop; $lastLineComplete = $true } catch { $lastLineComplete = $false }
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
      if ($recordTimestamp) {
        if ($recordTimestamp -lt $fileFirstRecordTimestamp) { $fileFirstRecordTimestamp = $recordTimestamp }
        if ($seenRecords.ContainsKey($recordHash)) {
          $health.DuplicateRecords++
          continue
        }
        $seenRecords[$recordHash] = $true
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
        if ($approvalClass) {
          $health.ApprovalRequestsObserved++
          if ($approvalClass.InspectionShaped) { $health.InspectionShapedApprovalRequests++ }
          if ($approvalBoundaryCauses.ContainsKey($approvalClass.BoundaryCause)) {
            $approvalBoundaryCauses[$approvalClass.BoundaryCause]++
          } else { $approvalBoundaryCauses[$approvalClass.BoundaryCause] = 1 }
          if ($approvalSources.ContainsKey($approvalClass.Source)) {
            $approvalSources[$approvalClass.Source]++
          } else {
            $approvalSources[$approvalClass.Source] = 1
          }
          if ($approvalClass.Signature) {
            if ($approvalClasses.ContainsKey($approvalClass.Signature)) {
              $approvalClasses[$approvalClass.Signature]++
            } else {
              $approvalClasses[$approvalClass.Signature] = 1
            }
          }
          if ($approvalClass.PrefixFingerprint) {
            if ($approvalPrefixes.ContainsKey($approvalClass.PrefixFingerprint)) {
              $approvalPrefixes[$approvalClass.PrefixFingerprint]++
            } else { $approvalPrefixes[$approvalClass.PrefixFingerprint] = 1 }
          }
          $approvalStateKey = if ($approvalClass.CorrelationFingerprint) {
            $approvalClass.CorrelationFingerprint
          } else { $approvalClass.Signature }
          if ($approvalStateKey) {
            if ($approvalStates.ContainsKey($approvalStateKey)) {
              $priorApproval = $approvalStates[$approvalStateKey]
              if ($priorApproval.decision -eq "allowed" -and $approvalClass.State -eq "pending" -and -not $priorApproval.resolved) {
                $health.ApprovalPersistenceRetries++
              }
            }
            $approvalStates[$approvalStateKey] = @{
              decision = if ($approvalStates.ContainsKey($approvalStateKey)) { $approvalStates[$approvalStateKey].decision } else { "unknown" }
              resolved = $false
            }
          }
        }
        $approvalDecision = Get-ApprovalDecisionRecord $record
        if ($approvalDecision) {
          $health.ApprovalDecisionsObserved++
          if ($approvalDecision.Decision -eq "allowed") { $health.ApprovalAllowedObserved++ }
          if ($approvalDecision.Decision -eq "denied") { $health.ApprovalDeniedObserved++ }
          if ($approvalDecision.CorrelationFingerprint -and $approvalStates.ContainsKey($approvalDecision.CorrelationFingerprint)) {
            $approvalStates[$approvalDecision.CorrelationFingerprint].decision = $approvalDecision.Decision
          }
        }
        $payloadType = Get-SafeCategory $record.payload @("type")
        if ($payloadType -in @("approval_resolved", "approval_state_applied")) {
          $resolvedId = Get-SafeCategory $record.payload @("approval_id", "request_id", "call_id")
          $resolvedKey = if ($resolvedId) { Get-TextFingerprint $resolvedId } else { $null }
          if ($resolvedKey -and $approvalStates.ContainsKey($resolvedKey)) { $approvalStates[$resolvedKey].resolved = $true }
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
        $fileToolCalls++
        $functionName = Get-SafeCategory $record.payload @("name")
        $arguments = ConvertFrom-StructuredArguments $record.payload.arguments
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
          if ($fileParentLinkSeen) { $health.ChildAgentSpawns++ } else { $health.RootAgentSpawns++ }
          $forkProperty = if ($arguments) { $arguments.PSObject.Properties["fork_turns"] } else { $null }
          $forkValue = if ($forkProperty -and $null -ne $forkProperty.Value) {
            ([string]$forkProperty.Value).Trim().ToLowerInvariant()
          } else { "all" }
          if (-not $forkProperty) { $health.SpawnForkAllDefaulted++ }
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
            $(if ($fileFirstRecordTimestamp -ne [DateTimeOffset]::MaxValue) {
                $fileFirstRecordTimestamp.UtcDateTime
              } else { $file.CreationTimeUtc })
          ).TotalDays)
        IsReviewer = $reviewerSeenInFile
      })

    if ($lastSnapshot) {
      $health.Files++
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
  if ($health.ApprovalDecisionsObserved -gt 0) {
    $health.ApprovalAllowPercent = [math]::Round(
      100.0 * $health.ApprovalAllowedObserved / $health.ApprovalDecisionsObserved, 2
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
    if ($health.ApprovalRepeatedPrefixRequests -gt 0 -and $health.ApprovalPersistenceDiagnosis -eq "not_observed") {
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
  if (-not $health.RolloutGrowthMiBPerHour) {
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
  } elseif ($health.ApprovalRepeatedPrefixRequests -gt 0) {
    "manual_narrow_rule_review"
  } elseif ($health.ApprovalRepeatedRequests -gt 0) {
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
    $health.CacheWriteObservation = "observed"
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
  @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName.Equals("Codex", [System.StringComparison]::Ordinal) -or
    $_.ProcessName.Equals("codex", [System.StringComparison]::Ordinal) -or
    $_.ProcessName.Equals("node_repl", [System.StringComparison]::Ordinal) -or
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
  [math]::Max(0.0, [double]$process.CPU - $baseline[$process.Id])
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
    Desktop = @($family | Where-Object { $_.ProcessName.Equals("Codex", [System.StringComparison]::Ordinal) }).Count
    Helpers = @($family | Where-Object { $_.ProcessName.Equals("codex", [System.StringComparison]::Ordinal) }).Count
    NodeRepl = @($family | Where-Object { $_.ProcessName.Equals("node_repl", [System.StringComparison]::Ordinal) }).Count
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

  if (-not $metrics.QueryOk) { return "WARNING" }

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
  if (-not $metrics.QueryOk) { $reasons.Add("query-unavailable") }
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
  $logReasons = Get-LogDbReasons $logMetrics $logLevel
  $filesystemHelper = Get-FilesystemHelperHealth
  $quotaHealth = Get-QuotaHealth
  $machineLevel = Get-WorseLevel $processLevel $filesystemHelper.Level
  $resourceLevel = Get-WorseLevel $machineLevel $logLevel
  $quotaLevel = if ($quotaHealth.Level -eq 'HIGH') { 'CRITICAL' } elseif ($quotaHealth.Level -eq 'ELEVATED') { 'WARNING' } elseif ($quotaHealth.Level -eq 'LOW') { 'HEALTHY' } else { 'UNAVAILABLE' }
  $overallLevel = Get-WorseLevel (Get-WorseLevel $resourceLevel $quotaLevel) $quotaHealth.RuleStatus
  $diskDisplay = if ($snapshot.DiskFreeGB -lt 0) { "unknown" } else { $snapshot.DiskFreeGB }
  Write-Output ("CHRONOS {0} advisory=true family={1} desktop={2} helpers={3} node_repl={4} runners={5} privateMB={6} handles={7} threads={8} cpuCores={9} diskFreeGB={10} fsHelper={11} fsHelperCopyFailure={12} fsHelperLaunchFailure={13} pcRestartAdvised={14} logDb={15} logDbGiB={16} logReclaimableGiB={17} logWalMiB={18} logWalActive={19} logSeq={20} logRate={21} logTracePct={22} quotaRisk={23} tokenFiles={24} tokenSamples={25} tokenSessionInputM={26} tokenCachedReadPct={27} tokenCacheWriteM={28} tokenCacheWriteObserved={29} tokenReasoningPct={30} tokenMaxContextPct={31} tokenHighEffortSessions={32} tokenExtremeEffortSessions={33} tokenUltraSessions={34} tokenSpawnCalls={35} tokenCompactions={36} tokenMalformedRecords={37} tokenDuplicateRecords={38} tokenOutOfOrderRecords={39} tokenTailIncompleteFiles={40} machineHealth={41} tokenCoverageWindowHours={42} tokenCoverageStartUtc={43} tokenCoverageEndUtc={44} tokenFilesEligible={45} tokenFilesSelected={46} tokenCoverageCapped={47} tokenTailTruncatedFiles={48} tokenUnreadableFiles={49} tokenCoverageContinuity={50} tokenSpawnObservation={51} tokenCompactionObservation={52} approvalReviewTurnsObserved={53} approvalReviewerSessionsObserved={54} approvalReviewerModels={55} approvalReviewObservation={56} approvalReviewCoverage={57} approvalReviewsPerHour={58} approvalReviewerInputM={59} approvalPrimaryInputM={60} approvalReviewerMainInputRatio={61} approvalRequestObservation={62} approvalOptimization={63} rolloutSelectedMiB={64} rolloutGrowthMiBPerHour={65} rolloutCrossFileDuplicateRecords={66} rolloutCrossFileDuplicateCompactions={67} tokenUsageScope={68} approvalAverageIntervalSeconds={69} approvalPeakPerMinute={70} approvalConcurrentPeak={71} approvalParentLinksObserved={72} approvalRequestsObserved={73} approvalUniqueClasses={74} approvalRepeatedRequests={75} approvalRepeatPct={76} approvalSources={77} approvalDeniedObserved={78} approvalDeniedObservation={79} rolloutCrossFileDuplicateBytes={80} rolloutReplayPct={81} compactionUniqueSnapshots={82} compactionDuplicateBytes={83} rolloutGrowthObservation={84} rolloutProjected24hMiB={85} rolloutLineageLinksObserved={86} rolloutForkFilesObserved={87} rolloutNearSizeClusterFiles={88} codexVersionsObserved={89} authProvidersObserved={90} tokenInheritedSnapshots={91} tokenLineageDeltaFiles={92} logDbReasons={93} logDbPerformanceImpact={94} quotaRiskScope={95} tokenAdviceReason={96} approvalModesObserved={97} reviewerControlCapability={98} reviewerCompatibility={99} tokenQuotaContributors={100} tokenAdvice={101}" -f `
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
  $efficiencyFields = [ordered]@{
    headlineScope = 'machine_health'
    resourceDiagnosticLevel = $resourceLevel
    overallDiagnosticLevel = $overallLevel
    logDbQueryOk = $logMetrics.QueryOk
    logDbPageMetricsOk = $logMetrics.PageMetricsOk
    logDbSequenceOk = $logMetrics.SequenceOk
    logDbLevelRowsOk = $logMetrics.LevelRowsOk
    cacheWriteObservation = $quotaHealth.CacheWriteObservation
    rolloutRateSemantics = 'file_lifetime_average_not_measured_delta'
    reviewerConcurrencySemantics = 'file_activity_span_estimate'
    metricSource = $quotaHealth.ApprovalMetricSource
    dashboardEquivalence = $quotaHealth.DashboardEquivalence
    billingInference = $quotaHealth.BillingInference
    quotaConfidence = $quotaHealth.QuotaConfidence
    primaryTurnsObserved = $quotaHealth.PrimaryTurnsObserved
    approvalReviewTurnsObserved = $quotaHealth.ReviewerTurnsObserved
    reviewerTokenAttribution = $quotaHealth.ReviewerTokenAttribution
    reviewerUnclassifiedInputM = $quotaHealth.ReviewerUnclassifiedInputM
    approvalReviewTurnShare = $quotaHealth.ApprovalReviewTurnShare
    approvalDecisionsObserved = $quotaHealth.ApprovalDecisionsObserved
    approvalAllowedObserved = $quotaHealth.ApprovalAllowedObserved
    approvalDeniedObserved = $quotaHealth.ApprovalDeniedObserved
    approvalAllowPct = $quotaHealth.ApprovalAllowPercent
    approvalPersistenceRetries = $quotaHealth.ApprovalPersistenceRetries
    approvalPersistenceFailures = $quotaHealth.ApprovalPersistenceFailures
    approvalPersistenceDiagnosis = $quotaHealth.ApprovalPersistenceDiagnosis
    approvalRepeatedPrefixRequests = $quotaHealth.ApprovalRepeatedPrefixRequests
    approvalLargestPrefixRepeat = $quotaHealth.ApprovalLargestPrefixRepeat
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
    rolloutTop1ReviewShare = $quotaHealth.RolloutTop1ReviewShare
    rolloutTop3ReviewShare = $quotaHealth.RolloutTop3ReviewShare
    spawnForkAll = $quotaHealth.SpawnForkAll
    spawnForkAllDefaulted = $quotaHealth.SpawnForkAllDefaulted
    spawnForkNone = $quotaHealth.SpawnForkNone
    spawnForkBounded = $quotaHealth.SpawnForkBounded
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
