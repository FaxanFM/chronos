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
$tokenHealthHome = Join-Path $testRoot "token-health-home"
$largeTailHome = Join-Path $testRoot "large-tail-home"
$aggregateOverflowHome = Join-Path $testRoot "aggregate-overflow-home"
$databasePath = Join-Path $fixtureHome "logs_2.sqlite"
$writer = $null

function Assert-Match($value, $pattern, $message) {
  if ($value -notmatch $pattern) {
    throw "$message`nOutput: $value"
  }
}

try {
  New-Item -ItemType Directory -Path $fixtureHome, $missingHome, $helperWarningHome, `
    $helperCriticalHome, $tokenHealthHome, $largeTailHome, $aggregateOverflowHome `
    -Force | Out-Null
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
  Assert-Match $output " logTracePct=80([.,]0)? " "Fixture TRACE percentage was not aggregated."
  Assert-Match $output " quotaRisk=UNAVAILABLE " `
    "Fixture without session files should report unavailable quota risk."

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

  $sessionDay = Join-Path (Join-Path (Join-Path $tokenHealthHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $sessionDay = Join-Path $sessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $sessionDay -Force | Out-Null
  $sessionPath = Join-Path $sessionDay "rollout-token-fixture.jsonl"
  $sessionRecords = @(
    @{
      type = "turn_context"
      payload = @{
        model = "gpt-5.6-sol"
        effort = "high"
      }
    },
    @{
      type = "response_item"
      payload = @{
        type = "function_call"
        name = "spawn_agent"
        arguments = "private fixture arguments must never be returned"
      }
    },
    @{
      type = "event_msg"
      payload = @{
        type = "context_compacted"
      }
    },
    @{
      type = "event_msg"
      payload = @{
        type = "context_compacted"
      }
    },
    @{
      type = "event_msg"
      payload = @{
        type = "token_count"
        info = @{
          model_context_window = 100000
          total_token_usage = @{
            input_tokens = 60000000
            cached_input_tokens = 48000000
            cache_write_input_tokens = 20000000
            output_tokens = 100000
            reasoning_output_tokens = 40000
            total_tokens = 60100000
          }
          last_token_usage = @{
            input_tokens = 79000
            cached_input_tokens = 70000
            cache_write_input_tokens = 1000
            output_tokens = 1000
            reasoning_output_tokens = 400
            total_tokens = 80000
          }
        }
      }
    }
  )
  $sessionRecords | ForEach-Object {
    Add-Content -LiteralPath $sessionPath -Value ($_ | ConvertTo-Json -Compress -Depth 8)
  }

  $tokenOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $tokenHealthHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos token-health inspection failed." }
  Assert-Match $tokenOutput " quotaRisk=HIGH " `
    "High-effort, high-context token fixture should report high quota risk."
  Assert-Match $tokenOutput " tokenFiles=1 " "Token fixture file was not counted."
  Assert-Match $tokenOutput " tokenSamples=1 " "Token event was not counted."
  Assert-Match $tokenOutput " tokenCachedReadPct=80([.,]0)? " `
    "Cached-read percentage was not aggregated."
  Assert-Match $tokenOutput " tokenCacheWriteObserved=true " `
    "Cache-write activity was not detected."
  Assert-Match $tokenOutput " tokenReasoningPct=40([.,]0)? " `
    "Reasoning percentage was not aggregated."
  Assert-Match $tokenOutput " tokenMaxContextPct=80([.,]0)? " `
    "Active context pressure was not detected."
  Assert-Match $tokenOutput " tokenHighEffortSessions=1 " `
    "High-effort session was not counted."
  Assert-Match $tokenOutput " tokenSpawnCalls=1 " "Subagent spawn was not counted."
  Assert-Match $tokenOutput " tokenCompactions=2 " "Compactions were not counted."
  Assert-Match $tokenOutput " tokenAdvice=lower-effort,fresh-task,bound-subagents,avoid-repeat-compaction,cache-write-risk$" `
    "Token advice did not reflect the aggregate risk signals."
  if (($tokenOutput -join "`n") -match "private fixture arguments") {
    throw "Chronos output exposed tool arguments."
  }

  $largeSessionDay = Join-Path (Join-Path (Join-Path $largeTailHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $largeSessionDay = Join-Path $largeSessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $largeSessionDay -Force | Out-Null
  $largeSessionPath = Join-Path $largeSessionDay "rollout-large-tail-fixture.jsonl"
  $largeTokenRecord = @{
    type = "event_msg"
    payload = @{
      type = "token_count"
      info = @{
        model_context_window = 100000
        total_token_usage = @{
          input_tokens = 3000000000
          cached_input_tokens = 2500000000
          cache_write_input_tokens = 0
          output_tokens = 100000
          reasoning_output_tokens = 10000
          total_tokens = 3000100000
        }
        last_token_usage = @{
          input_tokens = 79000
          cached_input_tokens = 70000
          cache_write_input_tokens = 0
          output_tokens = 1000
          reasoning_output_tokens = 100
          total_tokens = 80000
        }
      }
    }
  } | ConvertTo-Json -Compress -Depth 8
  $largeStream = [System.IO.File]::Open(
    $largeSessionPath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::Read
  )
  try {
    $largeStream.SetLength(([long][int]::MaxValue + 1048576L))
    $null = $largeStream.Seek(0L, [System.IO.SeekOrigin]::End)
    $largeTailBytes = [System.Text.Encoding]::UTF8.GetBytes("`n$largeTokenRecord`n")
    $largeStream.Write($largeTailBytes, 0, $largeTailBytes.Length)
    $largeStream.Flush()
  } finally {
    $largeStream.Dispose()
  }

  $largeTailOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $largeTailHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) {
    throw "Chronos failed to inspect a rollout file larger than Int32.MaxValue."
  }
  Assert-Match $largeTailOutput " tokenFiles=1 " `
    "A bounded tail read should support rollout files larger than Int32.MaxValue."
  Assert-Match $largeTailOutput " tokenSessionInputM=3000([.,]0)? " `
    "Token totals larger than Int32.MaxValue should remain 64-bit."

  $aggregateSessionDay = Join-Path (Join-Path (Join-Path $aggregateOverflowHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $aggregateSessionDay = Join-Path $aggregateSessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $aggregateSessionDay -Force | Out-Null
  foreach ($index in 1..8) {
    $aggregateTokenRecord = @{
      type = "event_msg"
      payload = @{
        type = "token_count"
        info = @{
          model_context_window = 100000
          total_token_usage = @{
            input_tokens = 3000000000000000000L
            cached_input_tokens = 2400000000000000000L
            cache_write_input_tokens = 0
            output_tokens = 100000
            reasoning_output_tokens = 10000
            total_tokens = 3000000000000100000L
          }
          last_token_usage = @{
            input_tokens = 79000
            cached_input_tokens = 70000
            cache_write_input_tokens = 0
            output_tokens = 1000
            reasoning_output_tokens = 100
            total_tokens = 80000
          }
        }
      }
    } | ConvertTo-Json -Compress -Depth 8
    Set-Content -LiteralPath (Join-Path $aggregateSessionDay "rollout-$index.jsonl") `
      -Value $aggregateTokenRecord
  }

  $aggregateOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $aggregateOverflowHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) {
    throw "Chronos overflowed while aggregating individually valid token counters."
  }
  Assert-Match $aggregateOutput " tokenFiles=8 " `
    "All bounded token files should be aggregated without integer overflow."
  Assert-Match $aggregateOutput " quotaRisk=HIGH " `
    "Large aggregate token history should still produce a quota assessment."

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
