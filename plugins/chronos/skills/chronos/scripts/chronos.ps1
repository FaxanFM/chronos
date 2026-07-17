param(
  [ValidateSet("inspect", "plan", "cleanup")]
  [string]$Action = "inspect",
  [int]$MinAgeMinutes = 60,
  [int]$ProcessId = 0,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

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

function Get-FreeDiskGB {
  $root = [System.IO.Path]::GetPathRoot((Get-Location).Path)
  $driveName = $root.TrimEnd("\").TrimEnd(":")
  $drive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
  if (-not $drive -or $null -eq $drive.Free) { return -1 }
  [math]::Round($drive.Free / 1GB, 1)
}

function Get-Snapshot {
  $initial = Get-CodexFamily
  $baseline = Get-CpuBaseline $initial
  Start-Sleep -Seconds 2
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
    CpuCores = [math]::Round($cpuDelta / 2, 2)
    DiskFreeGB = Get-FreeDiskGB
    Baseline = $baseline
  }
}

function Get-Level($snapshot) {
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

$snapshot = Get-Snapshot
$level = Get-Level $snapshot

if ($Action -eq "inspect") {
  $diskDisplay = if ($snapshot.DiskFreeGB -lt 0) { "unknown" } else { $snapshot.DiskFreeGB }
  Write-Output ("CHRONOS {0} family={1} desktop={2} helpers={3} node_repl={4} runners={5} privateMB={6} handles={7} threads={8} cpuCores={9} diskFreeGB={10}" -f `
    $level, $snapshot.Count, $snapshot.Desktop, $snapshot.Helpers, $snapshot.NodeRepl,
    $snapshot.Runners, $snapshot.PrivateMB, $snapshot.Handles, $snapshot.Threads,
    $snapshot.CpuCores, $diskDisplay)
  exit 0
}

$candidates = @(Get-Candidates $snapshot)
Write-Output ("CHRONOS PLAN candidates={0} minAgeMinutes={1}" -f $candidates.Count, $MinAgeMinutes)
if ($candidates.Count) {
  $candidates | Select-Object PID, Name, AgeMinutes | Format-Table -AutoSize
}

if ($Action -eq "plan") { exit 0 }
if (-not $Force) {
  Write-Output "Preview only. Explicit approval and -Force are required for cleanup."
  exit 0
}

$stopped = 0
foreach ($candidate in $candidates) {
  $current = Get-Process -Id $candidate.PID -ErrorAction SilentlyContinue
  if (-not $current) { continue }
  try {
    if ($current.StartTime -ne $candidate.StartTime) { continue }
  } catch {
    continue
  }
  Stop-Process -Id $candidate.PID -ErrorAction Stop
  $stopped += 1
}

Write-Output ("CHRONOS CLEANUP stopped={0}" -f $stopped)
