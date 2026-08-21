param(
  [ValidateSet("plan", "cancel-plan", "lease", "renew", "result", "verify", "correct", "accept", "retire", "release", "status")]
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
$script:StateByteLimit = 262144
$script:JsonNodeLimit = 32768
$script:StateCollectionLimit = 256
$script:StateMigrationPending = $false

if (-not ('ChronosGovernorPathIdentity' -as [type])) {
  $pathIdentitySource = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class ChronosGovernorPathIdentity {
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
  private static extern SafeFileHandle CreateFile(string fileName, uint desiredAccess, uint shareMode,
    IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint length, uint flags);
  [DllImport("kernel32.dll", SetLastError = true)]
  private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out BY_HANDLE_FILE_INFORMATION information);
  public static string FinalDirectoryPath(string path) {
    using (SafeFileHandle handle = CreateFile(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      StringBuilder buffer = new StringBuilder(32768);
      uint length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
      if (length == 0 || length >= buffer.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      return buffer.ToString();
    }
  }
  public static uint LinkCount(string path) {
    using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
      BY_HANDLE_FILE_INFORMATION information;
      if (!GetFileInformationByHandle(stream.SafeFileHandle, out information))
        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      return information.NumberOfLinks;
    }
  }
}
'@
  try { [void](Add-Type -TypeDefinition $pathIdentitySource -Language CSharp -ErrorAction Stop) } catch { throw 'governor_runtime_unavailable' }
}

function Move-JsonWhitespace {
  param([string]$Text, [ref]$Index)
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -in @(' ', "`t", "`r", "`n")) { $Index.Value++ }
}

function Read-StrictJsonString {
  param([string]$Text, [ref]$Index, [string]$ErrorCode)
  if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne '"') { Throw-GovernorError $ErrorCode }
  $start = $Index.Value
  $Index.Value++
  while ($Index.Value -lt $Text.Length) {
    $character = $Text[$Index.Value]
    if ([int][char]$character -lt 0x20) { Throw-GovernorError $ErrorCode }
    if ($character -eq '"') {
      $Index.Value++
      try {
        $decoded = $Text.Substring($start, $Index.Value - $start) | ConvertFrom-Json -ErrorAction Stop
        if (-not ($decoded -is [string])) { Throw-GovernorError $ErrorCode }
        return $decoded.Normalize([Text.NormalizationForm]::FormC)
      } catch { Throw-GovernorError $ErrorCode }
    }
    if ($character -eq '\') {
      $Index.Value++
      if ($Index.Value -ge $Text.Length) { Throw-GovernorError $ErrorCode }
      $escape = $Text[$Index.Value]
      if ($escape -eq 'u') {
        if ($Index.Value + 4 -ge $Text.Length -or $Text.Substring($Index.Value + 1, 4) -notmatch '^[0-9A-Fa-f]{4}$') { Throw-GovernorError $ErrorCode }
        $Index.Value += 5
        continue
      }
      if ($escape -notin @('"', '\', '/', 'b', 'f', 'n', 'r', 't')) { Throw-GovernorError $ErrorCode }
    }
    $Index.Value++
  }
  Throw-GovernorError $ErrorCode
}

function Assert-StrictJsonValue {
  param([string]$Text, [ref]$Index, [ref]$NodeCount, [int]$Depth, [string]$ErrorCode)
  if ($Depth -gt 16) { Throw-GovernorError $ErrorCode }
  Move-JsonWhitespace $Text $Index
  if ($Index.Value -ge $Text.Length) { Throw-GovernorError $ErrorCode }
  $NodeCount.Value++
  if ($NodeCount.Value -gt $script:JsonNodeLimit) { Throw-GovernorError $ErrorCode }
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
      if (-not $keys.Add($key)) { Throw-GovernorError $ErrorCode }
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne ':') { Throw-GovernorError $ErrorCode }
      $Index.Value++
      Assert-StrictJsonValue $Text $Index $NodeCount ($Depth + 1) $ErrorCode
      Move-JsonWhitespace $Text $Index
      if ($Index.Value -ge $Text.Length) { Throw-GovernorError $ErrorCode }
      if ($Text[$Index.Value] -eq '}') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { Throw-GovernorError $ErrorCode }
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
      if ($Index.Value -ge $Text.Length) { Throw-GovernorError $ErrorCode }
      if ($Text[$Index.Value] -eq ']') { $Index.Value++; return }
      if ($Text[$Index.Value] -ne ',') { Throw-GovernorError $ErrorCode }
      $Index.Value++
    }
  }
  $start = $Index.Value
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -notin @(',', ']', '}', ' ', "`t", "`r", "`n")) { $Index.Value++ }
  $token = $Text.Substring($start, $Index.Value - $start)
  if ($token -notmatch '^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$') { Throw-GovernorError $ErrorCode }
}

function Assert-StrictJson {
  param([string]$Text, [string]$ErrorCode)
  if ([string]::IsNullOrWhiteSpace($Text)) { Throw-GovernorError $ErrorCode }
  $index = 0
  $nodeCount = 0
  Assert-StrictJsonValue $Text ([ref]$index) ([ref]$nodeCount) 0 $ErrorCode
  Move-JsonWhitespace $Text ([ref]$index)
  if ($index -ne $Text.Length) { Throw-GovernorError $ErrorCode }
}

function Test-ContainedPath {
  param([string]$Path, [string]$Root)
  try {
    $full = [IO.Path]::GetFullPath($Path)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  } catch { return $false }
  return $full.Equals($base, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
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

function Write-GovernorOutput {
  param([hashtable]$Data)
  if (-not $Data.ContainsKey('plugin_version')) { $Data.plugin_version = $script:ChronosPluginVersion }
  Write-Output ("CHRONOS GOVERNOR " + ($Data | ConvertTo-Json -Compress -Depth 10))
}

function Throw-GovernorError {
  param([string]$Code)
  throw [System.InvalidOperationException]::new($Code)
}

function Invoke-Git {
  param([string[]]$Arguments)
  $output = Invoke-SanitizedGit $Arguments $false
  if (-not $output.ok) { Throw-GovernorError "git_command_failed" }
  $output.output
}

function Try-Invoke-Git {
  param([string[]]$Arguments)
  try { Invoke-SanitizedGit $Arguments $true } catch { @{ ok = $false; output = '' } }
}

function Invoke-GitIdentityCommand {
  param([ValidateSet('root', 'common')] [string]$Mode)
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = 'git.exe'
  $startInfo.WorkingDirectory = $script:RepositoryRoot
  $startInfo.Arguments = if ($Mode -eq 'root') {
    '-c core.fsmonitor=false -c core.hooksPath=NUL rev-parse --show-toplevel'
  } else {
    '-c core.fsmonitor=false -c core.hooksPath=NUL rev-parse --path-format=absolute --git-common-dir'
  }
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($name in @(
    'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0',
    'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_NOSYSTEM',
    'GIT_ATTR_NOSYSTEM', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_EXTERNAL_DIFF', 'GIT_DIFF_OPTS', 'GIT_PAGER', 'GIT_TRACE',
    'GIT_TRACE2', 'GIT_TRACE2_EVENT', 'GIT_OPTIONAL_LOCKS'
  )) { [void]$startInfo.EnvironmentVariables.Remove($name) }
  $startInfo.EnvironmentVariables['GIT_CONFIG_COUNT'] = '1'
  $startInfo.EnvironmentVariables['GIT_CONFIG_KEY_0'] = 'safe.directory'
  $startInfo.EnvironmentVariables['GIT_CONFIG_VALUE_0'] = $script:RepositoryRoot
  $startInfo.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = 'NUL'
  $startInfo.EnvironmentVariables['GIT_CONFIG_SYSTEM'] = 'NUL'
  $startInfo.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
  $startInfo.EnvironmentVariables['GIT_ATTR_NOSYSTEM'] = '1'
  $startInfo.EnvironmentVariables['GIT_OPTIONAL_LOCKS'] = '0'
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  try {
    if (-not $process.Start()) { return @{ ok = $false; output = ''; failure = 'start_failed' } }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(5000)) {
      try { $process.Kill() } catch {}
      return @{ ok = $false; output = ''; failure = 'timeout' }
    }
    [void]$stderr.Result
    $text = ([string]$stdout.Result).Trim()
    if ($process.ExitCode -ne 0 -or [Text.Encoding]::UTF8.GetByteCount($text) -gt 32768) {
      return @{ ok = $false; output = ''; failure = 'command_failed' }
    }
    return @{ ok = $true; output = $text; failure = 'none' }
  } catch {
    return @{ ok = $false; output = ''; failure = 'invocation_unavailable' }
  } finally {
    $process.Dispose()
  }
}

function Invoke-SanitizedGit {
  param([string[]]$Arguments, [bool]$SuppressError)
  $names = @(
    'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0',
    'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_NOSYSTEM',
    'GIT_ATTR_NOSYSTEM', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_EXTERNAL_DIFF', 'GIT_DIFF_OPTS', 'GIT_PAGER', 'GIT_TRACE',
    'GIT_TRACE2', 'GIT_TRACE2_EVENT', 'GIT_OPTIONAL_LOCKS'
  )
  $saved = @{}
  foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
  try {
    $env:GIT_CONFIG_COUNT = '0'
    $env:GIT_CONFIG_GLOBAL = 'NUL'
    $env:GIT_CONFIG_SYSTEM = 'NUL'
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_ATTR_NOSYSTEM = '1'
    $env:GIT_DIR = $null
    $env:GIT_WORK_TREE = $null
    $env:GIT_INDEX_FILE = $null
    $env:GIT_OBJECT_DIRECTORY = $null
    $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $null
    $env:GIT_EXTERNAL_DIFF = $null
    $env:GIT_DIFF_OPTS = $null
    $env:GIT_PAGER = 'cat'
    $env:GIT_TRACE = $null
    $env:GIT_TRACE2 = $null
    $env:GIT_TRACE2_EVENT = $null
    $env:GIT_OPTIONAL_LOCKS = '0'
    $gitArguments = @(
      '-c', ('safe.directory=' + $script:RepositoryRoot),
      '-c', 'core.fsmonitor=false',
      '-c', 'core.hooksPath=NUL',
      '-c', 'diff.external=',
      '-c', 'interactive.diffFilter=',
      '-c', 'pager.diff=false',
      '-C', $script:RepositoryRoot
    ) + $Arguments
    $output = if ($SuppressError) { @(& git @gitArguments 2>$null) } else { @(& git @gitArguments 2>&1) }
    @{
      ok = ($LASTEXITCODE -eq 0)
      output = ($output -join "`n").Trim()
    }
  } finally {
    foreach ($name in $names) {
      [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
  }
}

function Invoke-SanitizedGitBytes {
  param(
    [string[]]$Arguments,
    [int]$MaxBytes = 8388608,
    [int]$TimeoutMilliseconds = 5000
  )
  $gitArguments = @(
    '-c', 'core.fsmonitor=false',
    '-c', 'core.hooksPath=NUL',
    '-c', 'diff.external=',
    '-c', 'interactive.diffFilter=',
    '-c', 'pager.diff=false'
  ) + $Arguments
  if (@($gitArguments | Where-Object { $_ -match '[\s"\x00-\x1f]' }).Count -gt 0) {
    Throw-GovernorError "git_argument_unsupported"
  }
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = 'git'
  $startInfo.WorkingDirectory = $script:RepositoryRoot
  $startInfo.Arguments = $gitArguments -join ' '
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $names = @(
      'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0',
      'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_NOSYSTEM',
      'GIT_ATTR_NOSYSTEM', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE',
      'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES',
      'GIT_EXTERNAL_DIFF', 'GIT_DIFF_OPTS', 'GIT_PAGER', 'GIT_TRACE',
      'GIT_TRACE2', 'GIT_TRACE2_EVENT', 'GIT_OPTIONAL_LOCKS'
    )
  $saved = @{}
  foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
  $env:GIT_CONFIG_COUNT = '1'
  $env:GIT_CONFIG_KEY_0 = 'safe.directory'
  $env:GIT_CONFIG_VALUE_0 = $script:RepositoryRoot
  $env:GIT_CONFIG_GLOBAL = 'NUL'
  $env:GIT_CONFIG_SYSTEM = 'NUL'
  $env:GIT_CONFIG_NOSYSTEM = '1'
  $env:GIT_ATTR_NOSYSTEM = '1'
  $env:GIT_DIR = $null
  $env:GIT_WORK_TREE = $null
  $env:GIT_INDEX_FILE = $null
  $env:GIT_OBJECT_DIRECTORY = $null
  $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $null
  $env:GIT_EXTERNAL_DIFF = $null
  $env:GIT_DIFF_OPTS = $null
  $env:GIT_PAGER = 'cat'
  $env:GIT_TRACE = $null
  $env:GIT_TRACE2 = $null
  $env:GIT_TRACE2_EVENT = $null
  $env:GIT_OPTIONAL_LOCKS = '0'

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  $memory = [System.IO.MemoryStream]::new()
  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    if (-not $process.Start()) { Throw-GovernorError "git_command_failed" }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $buffer = New-Object byte[] 8192
    while ($true) {
      $remaining = $TimeoutMilliseconds - [int]$timer.ElapsedMilliseconds
      if ($remaining -le 0) {
        try { $process.Kill() } catch {}
        Throw-GovernorError "workspace_fingerprint_timeout"
      }
      $readTask = $process.StandardOutput.BaseStream.ReadAsync($buffer, 0, $buffer.Length)
      if (-not $readTask.Wait($remaining)) {
        try { $process.Kill() } catch {}
        Throw-GovernorError "workspace_fingerprint_timeout"
      }
      $count = $readTask.Result
      if ($count -eq 0) { break }
      if ($memory.Length + $count -gt $MaxBytes) {
        try { $process.Kill() } catch {}
        Throw-GovernorError "workspace_fingerprint_limit_exceeded"
      }
      $memory.Write($buffer, 0, $count)
    }
    $remaining = $TimeoutMilliseconds - [int]$timer.ElapsedMilliseconds
    if ($remaining -le 0 -or -not $process.WaitForExit($remaining)) {
      try { $process.Kill() } catch {}
      Throw-GovernorError "workspace_fingerprint_timeout"
    }
    if ($process.ExitCode -ne 0) { Throw-GovernorError "git_command_failed" }
    $memory.ToArray()
  } finally {
    foreach ($name in $names) {
      [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
    $timer.Stop()
    $memory.Dispose()
    $process.Dispose()
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

function Add-FingerprintText {
  param(
    [System.Security.Cryptography.HashAlgorithm]$Hasher,
    [string]$Value
  )
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value + "`n")
  [void]$Hasher.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
}

function Get-BoundedRawFileDigest {
  param(
    [string]$Path,
    [System.Diagnostics.Stopwatch]$Timer,
    [ref]$TotalBytes,
    [int64]$MaxFileBytes,
    [int64]$MaxTotalBytes,
    [int]$TimeoutMilliseconds
  )
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($item.Length -gt $MaxFileBytes -or $TotalBytes.Value + $item.Length -gt $MaxTotalBytes) {
    Throw-GovernorError "workspace_fingerprint_limit_exceeded"
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
  try {
    $buffer = New-Object byte[] 65536
    $observed = [int64]0
    while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
      if ($Timer.ElapsedMilliseconds -gt $TimeoutMilliseconds) {
        Throw-GovernorError "workspace_fingerprint_timeout"
      }
      $observed += $count
      if ($observed -gt $MaxFileBytes -or $TotalBytes.Value + $observed -gt $MaxTotalBytes) {
        Throw-GovernorError "workspace_fingerprint_limit_exceeded"
      }
      [void]$sha.TransformBlock($buffer, 0, $count, $buffer, 0)
    }
    [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
    $TotalBytes.Value += $observed
    @{
      bytes = $observed
      hash = ([System.BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
      attributes = [int64]$item.Attributes
    }
  } finally {
    $stream.Dispose()
    $sha.Dispose()
  }
}

function Get-WorkspaceFingerprint {
  param([string]$BaseCommit)
  $maxFiles = 20000
  $maxTotalBytes = [int64](128MB)
  $maxFileBytes = [int64](16MB)
  $timeoutMilliseconds = 10000
  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $head = Get-HeadState
    $indexBytes = Invoke-SanitizedGitBytes @('ls-files', '--stage', '-z') 8388608 5000
    $pathBytes = Invoke-SanitizedGitBytes @('ls-files', '--cached', '--others', '--exclude-standard', '-z') 8388608 5000
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
      $pathText = $utf8.GetString($pathBytes)
    } catch {
      Throw-GovernorError "workspace_fingerprint_path_encoding"
    }
    $paths = @($pathText.Split([char]0) | Where-Object { $_ } | Sort-Object -Unique)
    if ($paths.Count -gt $maxFiles) { Throw-GovernorError "workspace_fingerprint_limit_exceeded" }

    $indexSha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $indexDigest = ([System.BitConverter]::ToString($indexSha.ComputeHash($indexBytes))).Replace('-', '').ToLowerInvariant()
    } finally {
      $indexSha.Dispose()
    }
    $workspaceSha = [System.Security.Cryptography.SHA256]::Create()
    try {
      Add-FingerprintText $workspaceSha ('format=raw-manifest-v1')
      Add-FingerprintText $workspaceSha ('base=' + $BaseCommit)
      Add-FingerprintText $workspaceSha ('head_mode=' + $head.mode)
      Add-FingerprintText $workspaceSha ('head_reference=' + $head.reference_hash)
      Add-FingerprintText $workspaceSha ('head_commit=' + $head.commit)
      Add-FingerprintText $workspaceSha ('index_bytes=' + $indexBytes.Length)
      Add-FingerprintText $workspaceSha ('index_sha256=' + $indexDigest)
      $totalBytes = [int64]0
      foreach ($relative in $paths) {
        if ($timer.ElapsedMilliseconds -gt $timeoutMilliseconds) {
          Throw-GovernorError "workspace_fingerprint_timeout"
        }
        $normalized = Normalize-Scope $relative
        if (Test-ReparsePath $normalized) { Throw-GovernorError "workspace_fingerprint_reparse_path" }
        $full = [System.IO.Path]::GetFullPath((Join-Path $script:RepositoryRoot $normalized))
        if (Test-Path -LiteralPath $full -PathType Leaf) {
          $digest = Get-BoundedRawFileDigest $full $timer ([ref]$totalBytes) $maxFileBytes $maxTotalBytes $timeoutMilliseconds
          Add-FingerprintText $workspaceSha ($normalized + "`0file`0" + $digest.attributes + "`0" + $digest.bytes + "`0" + $digest.hash)
        } elseif (Test-Path -LiteralPath $full) {
          Throw-GovernorError "workspace_fingerprint_non_file"
        } else {
          Add-FingerprintText $workspaceSha ($normalized + "`0missing")
        }
      }
      [void]$workspaceSha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
      ([System.BitConverter]::ToString($workspaceSha.Hash)).Replace('-', '').ToLowerInvariant()
    } finally {
      $workspaceSha.Dispose()
    }
  } finally {
    $timer.Stop()
  }
}

function New-State {
  @{
    version = 4
    state_revision = [int64]0
    workers = @{}
    tasks = @{}
    leases = @{}
    plans = @{}
  }
}

function ConvertTo-StateInt64 {
  param($Value)
  if ($null -eq $Value) { Throw-GovernorError "state_schema_invalid" }
  $text = [Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
  $parsed = [int64]0
  if (
    -not [int64]::TryParse(
      $text,
      [System.Globalization.NumberStyles]::Integer,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [ref]$parsed
    ) -or $parsed -lt 0
  ) {
    Throw-GovernorError "state_schema_invalid"
  }
  $parsed
}

function Assert-StateMap {
  param([hashtable]$State, [string]$Name)
  if (-not $State.ContainsKey($Name) -or $State[$Name] -isnot [System.Collections.IDictionary]) {
    Throw-GovernorError "state_schema_invalid"
  }
  if ($State[$Name].Count -gt $script:StateCollectionLimit) { Throw-GovernorError "state_schema_invalid" }
  foreach ($entry in $State[$Name].GetEnumerator()) {
    if (
      [string]::IsNullOrWhiteSpace([string]$entry.Key) -or
      $entry.Value -isnot [System.Collections.IDictionary]
    ) {
      Throw-GovernorError "state_schema_invalid"
    }
  }
}

function Assert-RecordKeys {
  param($Record, [string[]]$Allowed)
  if ($Record -isnot [System.Collections.IDictionary]) { Throw-GovernorError 'state_schema_invalid' }
  foreach ($key in $Record.Keys) {
    if ([string]$key -notin $Allowed) { Throw-GovernorError 'state_schema_invalid' }
  }
}

function Assert-GovernorStateRecords {
  param([hashtable]$State)
  Assert-RecordKeys $State @('version', 'state_revision', 'workers', 'tasks', 'leases', 'plans')
  $allowed = @{
    workers = @('worker_id','repository_id','workspace_id','role','requested_model','effective_model','model_verification','model_inventory_hash','model_inventory_index','model_cost_rank','reasoning_effort','access_mode','status','updated_at','legacy_status','quarantined_at')
    tasks = @('task_id','repository_id','workspace_id','base_commit','head_mode','reference_hash','baseline_fingerprint','baseline_status_hash','branch_hash','access_mode','scopes','attempts','corrections','status','created_at','updated_at','legacy_status','quarantined_at')
    leases = @('task_id','lease_id','fencing_token','worker_id','repository_id','workspace_id','mutation_attribution_hash','mutation_attribution_verified','base_commit','head_mode','reference_hash','baseline_fingerprint','baseline_status_hash','branch_hash','changed_file_count','result_fingerprint','access_mode','scopes','status','created_at','updated_at','expires_at','policy','legacy_status','quarantined_at')
    plans = @('task_id','plan_id','token_hash','repository_id','workspace_id','task_class','access_mode','scopes','role','selected_model','model_selection_reason','model_inventory_hash','model_inventory_index','model_cost_rank','reasoning_effort','mutation_attribution_hash','mutation_attribution_verified','plan_base_commit','plan_head_mode','plan_reference_hash','planned_workspace_fingerprint','policy','status','created_at','expires_at','canceled_at','consumed_at','worker_id_hash','quarantined_at')
  }
  foreach ($mapName in $allowed.Keys) {
    foreach ($record in @($State[$mapName].Values)) {
      Assert-RecordKeys $record $allowed[$mapName]
      if ($record.Contains('scopes') -and @($record.scopes).Count -gt 64) { Throw-GovernorError 'state_schema_invalid' }
      if ($record.Contains('policy') -and $null -ne $record.policy) {
        Assert-RecordKeys $record.policy @('max_concurrent_workers','max_total_attempts','max_corrections','lease_minutes')
      }
    }
  }
}

function Initialize-GovernorStateStore {
  if (-not (Test-ContainedPath $script:ResolvedStatePath $script:StateRoot) -or -not (Test-NoReparseAncestors $script:ResolvedStatePath)) {
    Throw-GovernorError 'state_path_invalid'
  }
  $directory = Split-Path -Parent $script:ResolvedStatePath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $missing = [Collections.Generic.List[string]]::new()
    $cursor = $directory
    while (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
      $missing.Add($cursor) | Out-Null
      $parent = Split-Path -Parent $cursor
      if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { Throw-GovernorError 'state_path_invalid' }
      $cursor = $parent
    }
    for ($index = $missing.Count - 1; $index -ge 0; $index--) {
      if (-not (Test-NoReparseAncestors $cursor)) { Throw-GovernorError 'state_path_invalid' }
      $next = $missing[$index]
      if (-not (Test-Path -LiteralPath $next -PathType Container)) { New-Item -ItemType Directory -Path $next | Out-Null }
      $item = Get-Item -LiteralPath $next -Force
      if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Throw-GovernorError 'state_path_invalid' }
      $cursor = $next
    }
  }
  Assert-GovernorStatePath
}

function Assert-GovernorStatePath {
  if (-not (Test-ContainedPath $script:ResolvedStatePath $script:StateRoot) -or -not (Test-NoReparseAncestors $script:ResolvedStatePath)) { Throw-GovernorError 'state_path_invalid' }
  $directory = Split-Path -Parent $script:ResolvedStatePath
  $rootItem = Get-Item -LiteralPath $script:StateRoot -Force -ErrorAction Stop
  $directoryItem = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
  if (-not $rootItem.PSIsContainer -or -not $directoryItem.PSIsContainer -or
      ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
      ($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Throw-GovernorError 'state_path_invalid' }
  $canonicalRoot = [ChronosGovernorPathIdentity]::FinalDirectoryPath($script:StateRoot)
  $canonicalDirectory = [ChronosGovernorPathIdentity]::FinalDirectoryPath($directory)
  if (-not (Test-ContainedPath $canonicalDirectory $canonicalRoot)) { Throw-GovernorError 'state_path_invalid' }
  if (Test-Path -LiteralPath $script:ResolvedStatePath -PathType Leaf) {
    $stateItem = Get-Item -LiteralPath $script:ResolvedStatePath -Force
    if (($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or [ChronosGovernorPathIdentity]::LinkCount($script:ResolvedStatePath) -ne 1) { Throw-GovernorError 'state_path_invalid' }
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
  if ($legacySource) {
    if (-not (Test-NoReparseAncestors $sourcePath)) { Throw-GovernorError 'state_store_unreadable' }
  } else {
    Assert-GovernorStatePath
  }
  try {
    $item = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $script:StateByteLimit) { Throw-GovernorError 'state_invalid_json' }
    if ([ChronosGovernorPathIdentity]::LinkCount($sourcePath) -ne 1) { Throw-GovernorError 'state_path_invalid' }
    $bytes = [IO.File]::ReadAllBytes($sourcePath)
    $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($json.Length -gt 0 -and [int][char]$json[0] -eq 0xFEFF) { $json = $json.Substring(1) }
    Assert-StrictJson $json 'state_invalid_json'
  } catch [System.UnauthorizedAccessException] {
    Throw-GovernorError "state_store_unreadable"
  } catch [System.Security.SecurityException] {
    Throw-GovernorError "state_store_unreadable"
  } catch [System.IO.IOException] {
    Throw-GovernorError "state_read_failed"
  }
  try {
    $state = ConvertTo-Hashtable ($json | ConvertFrom-Json -ErrorAction Stop)
  } catch {
    Throw-GovernorError "state_invalid_json"
  }
  if ($state -isnot [System.Collections.IDictionary]) {
    Throw-GovernorError "state_schema_invalid"
  }
  $stateVersion = ConvertTo-StateInt64 $state.version
  if ($stateVersion -notin @(1, 2, 3, 4)) {
    Throw-GovernorError "state_version_unsupported"
  }
  $state.version = [int]$stateVersion
  foreach ($requiredMap in @('workers', 'tasks', 'leases')) {
    Assert-StateMap $state $requiredMap
  }
  if ($state.version -in @(1, 2)) {
    $legacyActive = @($state.leases.Values | Where-Object { $_.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction') })
    if ($legacySource -and $legacyActive.Count -gt 0) { Throw-GovernorError "state_migration_active_leases" }
    $state.version = 3
    if ($null -eq $state.state_revision) { $state.state_revision = [int64]0 }
    if ($null -eq $state.plans) { $state.plans = @{} }
    $script:StateMigrationPending = $true
  }
  Assert-StateMap $state 'plans'
  $state.state_revision = ConvertTo-StateInt64 $state.state_revision
  foreach ($plan in @($state.plans.Values)) {
    if ($plan.access_mode -eq 'write' -and $plan.status -eq 'issued') {
      $plan.status = 'quarantined_legacy_write'
      $plan.quarantined_at = [DateTimeOffset]::UtcNow.ToString('o')
      $script:StateMigrationPending = $true
    }
  }
  foreach ($lease in @($state.leases.Values)) {
    if (
      $lease.access_mode -eq 'write' -and
      $lease.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified')
    ) {
      $lease.legacy_status = [string]$lease.status
      $lease.status = 'blocked_legacy_write'
      $lease.quarantined_at = [DateTimeOffset]::UtcNow.ToString('o')
      if ($state.tasks.ContainsKey([string]$lease.task_id)) {
        $state.tasks[[string]$lease.task_id].status = 'blocked_legacy_write'
      }
      if ($state.workers.ContainsKey([string]$lease.worker_id)) {
        $state.workers[[string]$lease.worker_id].status = 'blocked_legacy_write'
      }
      $script:StateMigrationPending = $true
    }
  }
  $state.version = 4
  Assert-GovernorStateRecords $state
  $state
}

function Write-State {
  param([hashtable]$State)
  Initialize-GovernorStateStore
  $directory = Split-Path -Parent $script:ResolvedStatePath
  try {
    Assert-GovernorStateRecords $State
    $State.state_revision = [int64]$State.state_revision + [int64]1
    $temporary = $script:ResolvedStatePath + ".tmp-" + [guid]::NewGuid().ToString('N')
    $backup = $script:ResolvedStatePath + ".bak"
    $json = $State | ConvertTo-Json -Depth 10
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    if ($bytes.Length -gt $script:StateByteLimit) { Throw-GovernorError 'state_schema_invalid' }
    $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    Assert-StrictJson ([Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($temporary))) 'state_invalid_json'
    Assert-GovernorStatePath
    if (Test-Path -LiteralPath $script:ResolvedStatePath -PathType Leaf) {
      if ([ChronosGovernorPathIdentity]::LinkCount($script:ResolvedStatePath) -ne 1) { Throw-GovernorError 'state_path_invalid' }
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
      [System.IO.File]::Replace($temporary, $script:ResolvedStatePath, $backup, $true)
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    } else {
      [System.IO.File]::Move($temporary, $script:ResolvedStatePath)
    }
    Assert-GovernorStatePath
    $script:StateMigrationPending = $false
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
  $lockItem = Get-Item -LiteralPath $LockPath -Force
  if (($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $LockPath)) { Throw-GovernorError 'state_lock_unavailable' }
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
    try {
      $ownerItem = Get-Item -LiteralPath $ownerPath -Force
      if ($ownerItem.Length -gt 4096 -or ($ownerItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'invalid' }
      $ownerText = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($ownerPath))
      Assert-StrictJson $ownerText 'state_lock_owner_invalid'
      $owner = ConvertTo-Hashtable ($ownerText | ConvertFrom-Json -ErrorAction Stop)
    } catch { $owner = $null }
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
  Initialize-GovernorStateStore
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
      $lockItem = Get-Item -LiteralPath $lockPath -Force
      if (($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-NoReparseAncestors $lockPath)) { Throw-GovernorError 'state_lock_unavailable' }
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
    $ownerItem = Get-Item -LiteralPath $ownerPath -Force
    if ($ownerItem.Length -gt 4096 -or ($ownerItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
    $ownerText = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($ownerPath))
    Assert-StrictJson $ownerText 'state_lock_owner_invalid'
    $owner = ConvertTo-Hashtable ($ownerText | ConvertFrom-Json -ErrorAction Stop)
    if ($owner.lock_id -ne $Lock.lock_id) { return }
    [System.IO.File]::Delete($ownerPath)
    [System.IO.Directory]::Delete($Lock.path, $false)
  } catch {
    return
  }
}

function Get-ActiveLeases {
  param([hashtable]$State)
  @($State.leases.Values | Where-Object { $_.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified', 'blocked_legacy_write') })
}

function Get-BlockedLegacyWriteLeases {
  param([hashtable]$State)
  @($State.leases.Values | Where-Object {
      $_.access_mode -eq 'write' -and
      $_.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified', 'blocked_legacy_write')
    })
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

$script:FailureStage = 'repository_path'
try {
  $resolvedRepository = [System.IO.Path]::GetFullPath($Repository)
  if (-not (Test-Path -LiteralPath $resolvedRepository -PathType Container)) {
    Throw-GovernorError "repository_unavailable"
  }
  $script:RepositoryRoot = Resolve-CanonicalPath $resolvedRepository
  $script:FailureStage = 'repository_identity'
  $rootResult = Invoke-GitIdentityCommand 'root'
  $rawRoot = $rootResult.output
  if (-not $rootResult.ok -or -not $rawRoot) { Throw-GovernorError "git_repository_required" }
  $script:RepositoryRoot = Resolve-CanonicalPath $rawRoot
  $commonResult = Invoke-GitIdentityCommand 'common'
  $rawCommonDir = $commonResult.output
  if (-not $commonResult.ok -or -not $rawCommonDir) { Throw-GovernorError "git_common_dir_unavailable" }
  $script:GitCommonDir = Resolve-CanonicalPath $rawCommonDir
  $repositoryId = Get-TextHash $script:GitCommonDir.ToLowerInvariant()
  $workspaceId = Get-TextHash ($script:RepositoryRoot.ToLowerInvariant() + "`n" + $script:GitCommonDir.ToLowerInvariant())
  $script:FailureStage = 'state_path'
  $stateRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'Chronos\Governor'
  $script:StateRoot = [System.IO.Path]::GetFullPath($stateRoot)
  $expectedStatePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $stateRoot $repositoryId) 'governor-state.json'))
  $script:LegacyStatePath = [System.IO.Path]::GetFullPath((Join-Path $script:GitCommonDir 'chronos/governor-state.json'))
  if ($StatePath) {
    $candidateStatePath = [System.IO.Path]::GetFullPath($StatePath)
    if (-not $candidateStatePath.Equals($expectedStatePath, [System.StringComparison]::OrdinalIgnoreCase)) {
      Throw-GovernorError "custom_state_path_disabled"
    }
  }
  $script:ResolvedStatePath = $expectedStatePath
  try {
    Initialize-GovernorStateStore
  } catch [System.UnauthorizedAccessException] {
    if ($Action -ne 'plan') { throw }
    Write-GovernorOutput @{ ok = $true; action = 'plan'; decision = 'coordinator'; reason = 'state_store_unwritable'; repository_id = $repositoryId; workspace_id = $workspaceId; worker_spawn_allowed = $false }
    exit 0
  } catch [System.Security.SecurityException] {
    if ($Action -ne 'plan') { throw }
    Write-GovernorOutput @{ ok = $true; action = 'plan'; decision = 'coordinator'; reason = 'state_store_unwritable'; repository_id = $repositoryId; workspace_id = $workspaceId; worker_spawn_allowed = $false }
    exit 0
  } catch [System.IO.IOException] {
    if ($Action -ne 'plan') { throw }
    Write-GovernorOutput @{ ok = $true; action = 'plan'; decision = 'coordinator'; reason = 'state_store_unwritable'; repository_id = $repositoryId; workspace_id = $workspaceId; worker_spawn_allowed = $false }
    exit 0
  }

  if ($MaxConcurrentWorkers -lt 1 -or $MaxConcurrentWorkers -gt 4) { Throw-GovernorError "invalid_concurrency_limit" }
  if ($MaxTotalAttempts -lt 1 -or $MaxTotalAttempts -gt 5) { Throw-GovernorError "invalid_attempt_limit" }
  if ($MaxCorrections -lt 0 -or $MaxCorrections -gt 2) { Throw-GovernorError "invalid_correction_limit" }
  if ($PlanMinutes -lt 1 -or $PlanMinutes -gt 15) { Throw-GovernorError "invalid_plan_limit" }
  if ($LeaseMinutes -lt 1 -or $LeaseMinutes -gt 240) { Throw-GovernorError "invalid_lease_limit" }
  if ($StaleMinutes -lt 15 -or $StaleMinutes -gt 1440) { Throw-GovernorError "invalid_stale_limit" }
  if ($LockStaleSeconds -lt 1 -or $LockStaleSeconds -gt 600) { Throw-GovernorError "invalid_lock_stale_limit" }
  $script:FailureStage = 'action_' + $Action

  if ($Action -eq 'status') {
    $script:FailureStage = 'state_read'
    $state = Read-State
    $migrationPersisted = $false
    if ($script:StateMigrationPending) {
      $migrationLock = Acquire-StateLock
      try {
        $script:StateMigrationPending = $false
        $state = Read-State
        if ($script:StateMigrationPending) {
          Write-State $state
          $migrationPersisted = $true
        }
      } finally { Release-StateLock $migrationLock }
    }
    $script:FailureStage = 'status_summary'
    $active = @(Get-ActiveLeases $state)
    $staleCutoff = [DateTimeOffset]::UtcNow.AddMinutes(-$StaleMinutes)
    $stale = @($active | Where-Object {
      try { [DateTimeOffset]::Parse([string]$_.updated_at) -lt $staleCutoff } catch { $true }
    })
    $nowOffset = [DateTimeOffset]::UtcNow
    $issuedPlans = @($state.plans.Values | Where-Object { $_.status -eq 'issued' })
    $expiredPlans = @($issuedPlans | Where-Object {
      try { [DateTimeOffset]::Parse([string]$_.expires_at) -le $nowOffset } catch { $true }
    })
    Write-GovernorOutput @{
      ok = $true
      action = 'status'
      repository_id = $repositoryId
      workspace_id = $workspaceId
      active_workers = $active.Count
      active_writers = @($active | Where-Object { $_.access_mode -eq 'write' }).Count
      blocked_legacy_write_leases = @(Get-BlockedLegacyWriteLeases $state).Count
      expired_leases = @($active | Where-Object { Test-LeaseExpired $_ }).Count
      idle_workers = @($state.workers.Values | Where-Object { $_.status -eq 'idle' }).Count
      stale_leases = $stale.Count
      pending_plans = $issuedPlans.Count - $expiredPlans.Count
      expired_plans = $expiredPlans.Count
      tasks = $state.tasks.Count
      state_version = $state.version
      state_revision = [int64]$state.state_revision
      state_store = 'per_user_temp'
      state_integrity = 'untrusted_coordination_only'
      security_boundary = $false
      write_delegation_enabled = $false
      persistent_content = 'metadata-only'
      migration_persisted = $migrationPersisted
    }
    exit 0
  }

  if ($Action -eq 'plan') {
    $script:FailureStage = 'plan'
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
      $blockedLegacyWrites = @(Get-BlockedLegacyWriteLeases $state)
      $nowOffset = [DateTimeOffset]::UtcNow
      foreach ($planKey in @($state.plans.Keys)) {
        $existingPlan = $state.plans[$planKey]
        $expired = try { [DateTimeOffset]::Parse([string]$existingPlan.expires_at) -le $nowOffset } catch { $true }
        if ($existingPlan.status -ne 'issued' -or $expired) { $state.plans.Remove($planKey) }
      }
      $pendingPlanCount = @($state.plans.Values | Where-Object { $_.status -eq 'issued' }).Count
      if ($blockedLegacyWrites.Count -gt 0) {
        $decision = 'coordinator'; $reason = 'legacy_write_lease_disabled'
      } elseif ($TaskClass -eq 'risky') {
        $decision = 'coordinator'; $reason = 'risk_requires_coordinator'
      } elseif ($AccessMode -eq 'write') {
        $decision = 'coordinator'; $reason = 'shared_folder_write_delegation_disabled'
      } elseif ($Health -eq 'CRITICAL') {
        $decision = 'coordinator'; $reason = 'health_advises_no_new_worker'
      } elseif ($state.plans.ContainsKey($task) -and $state.plans[$task].status -eq 'issued') {
        $decision = 'coordinator'; $reason = 'task_plan_already_issued'
      } elseif ($state.leases.ContainsKey($task) -and $state.leases[$task].status -in @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified')) {
        $decision = 'coordinator'; $reason = 'task_already_leased'
      } elseif (($active.Count + $pendingPlanCount) -ge $MaxConcurrentWorkers) {
        $decision = 'coordinator'; $reason = 'concurrency_budget_reached'
      } elseif ($AccessMode -eq 'write' -and @($active | Where-Object { $_.access_mode -eq 'write' }).Count -gt 0) {
        $decision = 'coordinator'; $reason = 'single_writer_lease_active'
      } elseif (-not $selection.selected) {
        $decision = 'coordinator'; $reason = $selection.reason
      }

      $attributionHash = $null

      if ($selection.selected) {
        $reuse = @($state.workers.Values | Where-Object {
          $_.status -eq 'idle' -and $_.repository_id -eq $repositoryId -and
          $_.workspace_id -eq $workspaceId -and $_.role -eq $role -and
          $_.requested_model -eq $selection.model -and $_.reasoning_effort -eq $effort -and
          $_.access_mode -eq $AccessMode
        } | Select-Object -First 1)
      }

      if ($decision -eq 'delegate') {
        $planHead = Get-HeadState
        $plannedWorkspaceFingerprint = Get-WorkspaceFingerprint $planHead.commit
        $planId = [guid]::NewGuid().ToString('N')
        $planTokenValue = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
        $planExpiresAt = $nowOffset.AddMinutes($PlanMinutes).ToString('o')
        $state.plans[$task] = @{
          task_id = $task
          plan_id = $planId
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
          plan_base_commit = $planHead.commit
          plan_head_mode = $planHead.mode
          plan_reference_hash = $planHead.reference_hash
          planned_workspace_fingerprint = $plannedWorkspaceFingerprint
          policy = @{
            max_concurrent_workers = $MaxConcurrentWorkers
            max_total_attempts = $MaxTotalAttempts
            max_corrections = $MaxCorrections
            lease_minutes = $LeaseMinutes
          }
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
      plan_id = if ($decision -eq 'delegate') { $planId } else { $null }
      plan_expires_at = $planExpiresAt
      capacity_reserved = [bool]($decision -eq 'delegate' -and $planTokenValue)
      state_store = 'per_user_temp'
      state_integrity = 'untrusted_coordination_only'
      security_boundary = $false
      write_delegation_enabled = $false
      read_only_enforcement = 'advisory_git_visible_projection'
      reuse_worker_id = if ($reuse.Count) { $reuse[0].worker_id } else { $null }
      spawn_contract = 'multi_agent_v2'
      fork_turns = 'none'
      delegation_depth_policy = 1
      nested_workers_policy = 'prohibited_not_runtime_enforced'
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

    if ($Action -eq 'cancel-plan') {
      if (-not $PlanToken) { Throw-GovernorError "plan_token_required" }
      if (-not $state.plans.ContainsKey($task)) { Throw-GovernorError "plan_not_found" }
      $plan = $state.plans[$task]
      if ($plan.status -ne 'issued') { Throw-GovernorError "plan_already_consumed" }
      if ((Get-TextHash $PlanToken) -ne $plan.token_hash) { Throw-GovernorError "plan_token_mismatch" }
      if ($plan.repository_id -ne $repositoryId -or $plan.workspace_id -ne $workspaceId) {
        Throw-GovernorError "plan_workspace_mismatch"
      }
      $plan.status = 'canceled'
      $plan.canceled_at = $now
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'cancel-plan'
        task_id = $task
        status = 'canceled'
        capacity_released = $true
      }
      exit 0
    }

    if ($Action -eq 'lease') {
      $worker = Normalize-WorkerIdentifier $WorkerId
      if (-not $PlanToken) { Throw-GovernorError "plan_token_required" }
      if (-not $state.plans.ContainsKey($task)) { Throw-GovernorError "plan_not_found" }
      $plan = $state.plans[$task]
      if ($plan.status -eq 'quarantined_legacy_write' -or $plan.access_mode -eq 'write') {
        Throw-GovernorError "legacy_write_lease_disabled"
      }
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
      if ($AccessMode -eq 'write') { Throw-GovernorError "shared_folder_write_delegation_disabled" }
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
      if (@($active | Where-Object { $_.worker_id -eq $worker }).Count -gt 0) {
        Throw-GovernorError "worker_already_leased"
      }
      if ($AccessMode -eq 'write' -and @($active | Where-Object { $_.access_mode -eq 'write' }).Count -gt 0) {
        Throw-GovernorError "single_writer_lease_active"
      }
      $head = Get-HeadState
      if (-not $plan.planned_workspace_fingerprint -or
          $plan.plan_base_commit -ne $head.commit -or
          $plan.plan_head_mode -ne $head.mode -or
          $plan.plan_reference_hash -ne $head.reference_hash) {
        Throw-GovernorError "workspace_changed_since_plan"
      }
      $baselineFingerprint = Get-WorkspaceFingerprint $head.commit
      if ($baselineFingerprint -ne $plan.planned_workspace_fingerprint) {
        Throw-GovernorError "workspace_changed_since_plan"
      }
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
      $leasePolicy = if ($plan.policy) { $plan.policy } else { @{
          max_concurrent_workers = $MaxConcurrentWorkers; max_total_attempts = $MaxTotalAttempts
          max_corrections = $MaxCorrections; lease_minutes = $LeaseMinutes
        } }
      if ($active.Count -ge [int]$leasePolicy.max_concurrent_workers) { Throw-GovernorError "concurrency_budget_reached" }
      if ($attempts -gt [int]$leasePolicy.max_total_attempts) { Throw-GovernorError "attempt_budget_reached" }

      $baseCommit = $head.commit
      $leaseIdentifier = [guid]::NewGuid().ToString('N')
      $fencing = [guid]::NewGuid().ToString('N')
      $expiresAt = $nowOffset.AddMinutes([int]$leasePolicy.lease_minutes).ToString('o')
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
        policy = $leasePolicy
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
        lease_state_transition = 'atomic_single_write_after_validation'
        attempt = $attempts
        max_attempts = [int]$leasePolicy.max_total_attempts
        delegation_depth_policy = 1
        nested_workers_policy = 'prohibited_not_runtime_enforced'
        security_boundary = $false
      }
      exit 0
    }

    if (-not $state.leases.ContainsKey($task)) { Throw-GovernorError "lease_not_found" }
    $lease = $state.leases[$task]
    if ($lease.access_mode -eq 'write') {
      if ($Action -notin @('release', 'retire')) { Throw-GovernorError "legacy_write_lease_disabled" }
      if (-not $CoordinatorAccepted) { Throw-GovernorError "coordinator_acceptance_required" }
      if ($lease.status -notin @('leased', 'working', 'awaiting_verification', 'needs_correction', 'verified', 'blocked_legacy_write')) {
        Throw-GovernorError "invalid_lifecycle_transition"
      }
      $terminalStatus = if ($Action -eq 'release') { 'released' } else { 'failed' }
      $workerStatus = if ($Action -eq 'release') { 'idle' } else { 'retired' }
      $lease.status = $terminalStatus
      $lease.updated_at = $now
      if ($state.tasks.ContainsKey($task)) {
        $state.tasks[$task].status = $terminalStatus
        $state.tasks[$task].updated_at = $now
      }
      if ($state.workers.ContainsKey([string]$lease.worker_id)) {
        $state.workers[[string]$lease.worker_id].status = $workerStatus
        $state.workers[[string]$lease.worker_id].updated_at = $now
      }
      Write-State $state
      Write-GovernorOutput @{
        ok = $true; action = $Action; task_id = $task; worker_id = $lease.worker_id
        status = $terminalStatus; legacy_write_lease_quarantined = $true
        fingerprint_executed = $false; automatic_merge = $false; automatic_cleanup = $false
      }
      exit 0
    }
    Assert-LeaseCredentials $lease -AllowExpiredRelease:($Action -eq 'release')
    if ($lease.repository_id -ne $repositoryId -or $lease.workspace_id -ne $workspaceId) {
      Throw-GovernorError "workspace_identity_mismatch"
    }

    if ($Action -eq 'renew') {
      if ($lease.status -notin @('working', 'needs_correction', 'awaiting_verification', 'verified')) { Throw-GovernorError "lease_not_renewable" }
      $lease.updated_at = $now
      $lease.expires_at = $nowOffset.AddMinutes([int]$lease.policy.lease_minutes).ToString('o')
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
      $ancestor = Try-Invoke-Git @('merge-base', '--is-ancestor', $baseCommit, 'HEAD')
      if (-not $ancestor.ok) { Throw-GovernorError "base_commit_mismatch" }
      if ($lease.access_mode -ne 'read') { Throw-GovernorError "legacy_write_lease_disabled" }
      $changed = @()
      if ($currentFingerprint -ne $lease.baseline_fingerprint) { Throw-GovernorError "read_worker_modified_workspace" }
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
        mutation_attribution_valid = $false
        result_fingerprint_valid = $true
        base_commit_valid = $true
        verification_passed = $true
      }
      exit 0
    }

    if ($Action -eq 'correct') {
      if ($lease.status -ne 'awaiting_verification') { Throw-GovernorError "result_not_ready" }
      $corrections = [int]$state.tasks[$task].corrections + 1
      if ($corrections -gt [int]$lease.policy.max_corrections) { Throw-GovernorError "correction_budget_reached" }
      $state.tasks[$task].corrections = $corrections
      $state.tasks[$task].status = 'needs_correction'
      $state.tasks[$task].updated_at = $now
      $lease.status = 'needs_correction'
      $lease.result_fingerprint = $null
      $lease.updated_at = $now
      $state.workers[$lease.worker_id].status = 'leased'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{ ok = $true; action = 'correct'; task_id = $task; worker_id = $lease.worker_id; correction = $corrections; max_corrections = [int]$lease.policy.max_corrections; reuse_same_worker = $true }
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
      if ($lease.status -notin @('working', 'needs_correction', 'awaiting_verification', 'verified')) { Throw-GovernorError "invalid_lifecycle_transition" }
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
      if ($lease.status -eq 'verified' -and (-not $CoordinatorAccepted -or -not (Test-LeaseExpired $lease))) {
        Throw-GovernorError "invalid_lifecycle_transition"
      }
      if ($lease.status -notin @('working', 'needs_correction', 'awaiting_verification', 'verified')) { Throw-GovernorError "invalid_lifecycle_transition" }
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
  $failure = @{ ok = $false; action = $Action; error = $code }
  if ($code -eq 'internal_error') {
    $failure.failure_stage = $script:FailureStage
    $failure.exception_type = $_.Exception.GetType().Name
    $failure.recovery = 'continue_as_coordinator_and_report'
  }
  Write-GovernorOutput $failure
  exit 1
}
