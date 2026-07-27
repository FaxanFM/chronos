param(
  [string]$PythonPath = "python"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$chronosScript = Join-Path $repoRoot "plugins\chronos\skills\chronos\scripts\chronos.ps1"
$fixtureScript = Join-Path $PSScriptRoot "create_log_fixture.py"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-tests-" + [guid]::NewGuid())
$fixtureHome = Join-Path $testRoot "fixture-home"
$missingHome = Join-Path $testRoot "missing-home"
$databasePath = Join-Path $fixtureHome "logs_2.sqlite"
$writer = $null

function Assert-Match($value, $pattern, $message) {
  if ($value -notmatch $pattern) {
    throw "$message`nOutput: $value"
  }
}

try {
  New-Item -ItemType Directory -Path $fixtureHome, $missingHome -Force | Out-Null
  & $PythonPath $fixtureScript create $databasePath
  if ($LASTEXITCODE -ne 0) { throw "Failed to create SQLite fixture." }

  $beforeHash = (Get-FileHash -LiteralPath $databasePath -Algorithm SHA256).Hash
  $beforeLength = (Get-Item -LiteralPath $databasePath).Length

  $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $fixtureHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos fixture inspection failed." }

  Assert-Match $output "^CHRONOS (HEALTHY|WARNING|CRITICAL) " "Missing Chronos status."
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
