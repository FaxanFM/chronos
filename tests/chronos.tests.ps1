param(
  [string]$PythonPath = "python"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$chronosScript = Join-Path $repoRoot "plugins\chronos\skills\chronos\scripts\chronos.ps1"
$chronosSkill = Join-Path $repoRoot "plugins\chronos\skills\chronos\SKILL.md"
$fixtureScript = Join-Path $PSScriptRoot "create_log_fixture.py"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-tests-" + [guid]::NewGuid())
$fixtureHome = Join-Path $testRoot "fixture-home"
$missingHome = Join-Path $testRoot "missing-home"
$helperWarningHome = Join-Path $testRoot "helper-warning-home"
$helperCriticalHome = Join-Path $testRoot "helper-critical-home"
$databasePath = Join-Path $fixtureHome "logs_2.sqlite"
$writer = $null

function Assert-Match($value, $pattern, $message) {
  if ($value -notmatch $pattern) {
    throw "$message`nOutput: $value"
  }
}

try {
  New-Item -ItemType Directory -Path $fixtureHome, $missingHome, $helperWarningHome, `
    $helperCriticalHome -Force | Out-Null
  & $PythonPath $fixtureScript create $databasePath
  if ($LASTEXITCODE -ne 0) { throw "Failed to create SQLite fixture." }

  $beforeHash = (Get-FileHash -LiteralPath $databasePath -Algorithm SHA256).Hash
  $beforeLength = (Get-Item -LiteralPath $databasePath).Length

  $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $fixtureHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos fixture inspection failed." }

  Assert-Match $output "^CHRONOS (HEALTHY|WARNING|CRITICAL) " "Missing Chronos status."
  Assert-Match $output " advisory=true " "Inspection must declare advisory behavior."
  Assert-Match $output " logDb=HEALTHY " "Fixture log database should be healthy."
  Assert-Match $output " logSeq=400 " "Fixture sequence was not read."
  Assert-Match $output " logRate=0([.,]0)? " "Inactive fixture should have zero insert rate."
  Assert-Match $output " logTracePct=80([.,]0)?$" "Fixture TRACE percentage was not aggregated."

  $afterHash = (Get-FileHash -LiteralPath $databasePath -Algorithm SHA256).Hash
  $afterLength = (Get-Item -LiteralPath $databasePath).Length
  if ($beforeHash -ne $afterHash -or $beforeLength -ne $afterLength) {
    throw "Read-only inspection changed the SQLite fixture."
  }

  & $PythonPath $fixtureScript verify $databasePath
  if ($LASTEXITCODE -ne 0) { throw "SQLite fixture verification failed." }

  $writerArguments = @(
    "`"$fixtureScript`"",
    "write",
    "`"$databasePath`"",
    "--duration",
    "4"
  )
  $writer = Start-Process -FilePath $PythonPath -ArgumentList $writerArguments `
    -PassThru -WindowStyle Hidden
  Start-Sleep -Milliseconds 500

  $activeOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $fixtureHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos active-WAL inspection failed." }
  Assert-Match $activeOutput " logWalActive=true " "Active WAL writes were not detected."
  Assert-Match $activeOutput " logRate=([1-9][0-9]*)([.,][0-9]+)? " "Active insert rate was not detected."

  $writer.WaitForExit()
  if ($writer.ExitCode -ne 0) { throw "SQLite fixture writer failed." }

  $missingOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $missingHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos missing-database inspection failed." }
  Assert-Match $missingOutput " logDb=UNAVAILABLE " "Missing database should be unavailable."
  Assert-Match $missingOutput " logSeq=unknown " "Missing database should not invent a sequence."

  $markerTimestamp = (Get-Date).AddSeconds(-5).ToString("yyyy-MM-dd HH:mm:ss.fff")
  Set-Content -LiteralPath (Join-Path $helperWarningHome "sandbox.log") -Value `
    "[$markerTimestamp codex.exe] helper copy failed for command-runner: remove stale helper destination"
  $helperWarningOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $helperWarningHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos helper-warning inspection failed." }
  Assert-Match $helperWarningOutput " fsHelper=WARNING " `
    "Helper copy failure should produce a warning."
  Assert-Match $helperWarningOutput " fsHelperCopyFailure=true " `
    "Helper copy failure marker was not detected."
  Assert-Match $helperWarningOutput " fsHelperLaunchFailure=false " `
    "Warning fixture should not invent a launch failure."
  Assert-Match $helperWarningOutput " pcRestartAdvised=false " `
    "Copy failure alone should not advise a full PC restart."

  Set-Content -LiteralPath (Join-Path $helperCriticalHome "sandbox.log") -Value `
    "[$markerTimestamp codex.exe] windows sandbox: CreateProcessWithLogonW failed: 5"
  $helperCriticalOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $helperCriticalHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos helper-critical inspection failed." }
  Assert-Match $helperCriticalOutput "^CHRONOS CRITICAL advisory=true " `
    "Unusable filesystem helper should produce a critical advisory."
  Assert-Match $helperCriticalOutput " fsHelper=CRITICAL " `
    "Filesystem helper critical level was not reported."
  Assert-Match $helperCriticalOutput " fsHelperLaunchFailure=true " `
    "Filesystem helper launch failure was not detected."
  Assert-Match $helperCriticalOutput " pcRestartAdvised=true " `
    "Unusable filesystem helper should advise a full PC restart."

  $recoveryTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  Add-Content -LiteralPath (Join-Path $helperCriticalHome "sandbox.log") -Value `
    "[$recoveryTimestamp codex.exe] SUCCESS: powershell.exe"
  $helperRecoveredOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $helperCriticalHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos helper-recovery inspection failed." }
  Assert-Match $helperRecoveredOutput " fsHelper=HEALTHY " `
    "A later successful sandbox launch should clear the unusable state."
  Assert-Match $helperRecoveredOutput " pcRestartAdvised=false " `
    "Recovered filesystem helper should not continue advising a PC restart."

  $cleanupOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action cleanup -Force -CodexHome $missingHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos compatibility cleanup failed." }
  $cleanupText = $cleanupOutput -join "`n"
  Assert-Match $cleanupText "CHRONOS PLAN advisoryOnly=true " "Legacy plan must be advisory-only."
  Assert-Match $cleanupText "CHRONOS CLEANUP disabled=advisory-only stopped=0" `
    "Legacy cleanup must stop zero processes."

  $scriptText = Get-Content -LiteralPath $chronosScript -Raw
  if ($scriptText -match "\bStop-Process\b") {
    throw "Chronos script must not contain a process-termination path."
  }

  $skillText = Get-Content -LiteralPath $chronosSkill -Raw
  if ($skillText -match "stop starting new work") {
    throw "Chronos skill must not gate new work."
  }
  Assert-Match $skillText "Never use a Chronos status to\s+refuse, suspend, cancel, or stop" `
    "Chronos skill must explicitly prohibit status-based task blocking."
  Assert-Match $skillText "advise a full Windows\s+restart" `
    "Chronos skill must advise a full PC restart for an unusable helper."

  Write-Output "Chronos tests passed."
} finally {
  if ($writer -and -not $writer.HasExited) {
    Stop-Process -Id $writer.Id -Force -ErrorAction SilentlyContinue
    $writer.WaitForExit()
  }
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
}
