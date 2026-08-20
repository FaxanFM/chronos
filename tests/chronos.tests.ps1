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
$helperFalsePositiveHome = Join-Path $testRoot "helper-false-positive-home"
$tokenHealthHome = Join-Path $testRoot "token-health-home"
$tokenIntegrityHome = Join-Path $testRoot "token-integrity-home"
$tokenIntervalHome = Join-Path $testRoot "token-interval-home"
$largeTailHome = Join-Path $testRoot "large-tail-home"
$aggregateOverflowHome = Join-Path $testRoot "aggregate-overflow-home"
$v2CoverageHome = Join-Path $testRoot "v2-coverage-home"
$reviewerHealthHome = Join-Path $testRoot "reviewer-health-home"
$machine2Home = Join-Path $testRoot "machine2-home"
$ruleMissHome = Join-Path $testRoot "rule-miss-home"
$ruleStructureHome = Join-Path $testRoot "rule-structure-home"
$independentAllowHome = Join-Path $testRoot "independent-allow-home"
  $stableApprovalHome = Join-Path $testRoot "stable-approval-home"
  $v1ForkHome = Join-Path $testRoot "v1-fork-home"
  $forkReplayHome = Join-Path $testRoot "fork-replay-home"
  $completeNoNewlineHome = Join-Path $testRoot "complete-no-newline-home"
  $invalidDbHome = Join-Path $testRoot "invalid-db-home"
$partialDbHome = Join-Path $testRoot "partial-db-home"
  $walSidecarHome = Join-Path $testRoot "wal-sidecar-home"
  $unsupportedCacheHome = Join-Path $testRoot "unsupported-cache-home"
  $partialCacheHome = Join-Path $testRoot "partial-cache-home"
  $reparseHome = Join-Path $testRoot "reparse-home"
$reparseExternal = Join-Path $testRoot "reparse-external"
$duplicateInstallHome = Join-Path $testRoot "duplicate-install-home"
$directoryInstallHome = Join-Path $testRoot "directory-install-home"
$databasePath = Join-Path $fixtureHome "logs_2.sqlite"
$writer = $null

function Assert-Match($value, $pattern, $message) {
  if (($value -join "`n") -notmatch $pattern) {
    throw "$message`nOutput: $value"
  }
}

function Get-DirectorySnapshot([string]$Path) {
  @((Get-ChildItem -LiteralPath $Path -File | Sort-Object Name | ForEach-Object {
      $_.Name + ':' + $_.Length + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })) -join '|'
}

try {
  New-Item -ItemType Directory -Path $fixtureHome, $missingHome, $helperWarningHome, `
    $helperCriticalHome, $helperFalsePositiveHome, $tokenHealthHome, $tokenIntegrityHome, $tokenIntervalHome, $duplicateInstallHome, $directoryInstallHome, `
    $largeTailHome, $aggregateOverflowHome, $v2CoverageHome, $reviewerHealthHome, $machine2Home, $ruleMissHome, $ruleStructureHome, $independentAllowHome, $stableApprovalHome, $v1ForkHome, $forkReplayHome, $completeNoNewlineHome, $invalidDbHome, $partialDbHome, $walSidecarHome, $unsupportedCacheHome, $partialCacheHome, $reparseHome, $reparseExternal `
    -Force | Out-Null
  & $PythonPath $fixtureScript create $databasePath
  if ($LASTEXITCODE -ne 0) { throw "Failed to create SQLite fixture." }

  foreach ($source in @('chronos', 'openai-curated-remote')) {
    $manifestDirectory = Join-Path $duplicateInstallHome "plugins\cache\$source\chronos\0.9.2\.codex-plugin"
    New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
    [System.IO.File]::WriteAllText(
      (Join-Path $manifestDirectory 'plugin.json'),
      '{"name":"chronos","version":"0.9.2"}',
      [System.Text.UTF8Encoding]::new($false)
    )
  }
  [System.IO.File]::WriteAllText(
    (Join-Path $duplicateInstallHome 'config.toml'),
    "[plugins.`"chronos@chronos`"]`nenabled = true`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $installedScriptDirectory = Join-Path $duplicateInstallHome 'plugins\cache\openai-curated-remote\chronos\0.9.2\skills\chronos\scripts'
  New-Item -ItemType Directory -Path $installedScriptDirectory -Force | Out-Null
  Copy-Item -LiteralPath $chronosScript -Destination (Join-Path $installedScriptDirectory 'chronos.ps1')
  $installedChronosScript = Join-Path $installedScriptDirectory 'chronos.ps1'
  $directoryManifest = Join-Path $directoryInstallHome 'plugins\cache\openai-curated-remote\chronos\0.9.2\.codex-plugin'
  New-Item -ItemType Directory -Path $directoryManifest -Force | Out-Null
  [System.IO.File]::WriteAllText(
    (Join-Path $directoryManifest 'plugin.json'),
    '{"name":"chronos","version":"0.9.2"}',
    [System.Text.UTF8Encoding]::new($false)
  )

  $duplicateInstallOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $installedChronosScript -Action install-status -CodexHome $duplicateInstallHome
  if ($LASTEXITCODE -ne 0) { throw 'Chronos duplicate install-source check failed.' }
  Assert-Match $duplicateInstallOutput '^CHRONOS INSTALL pluginVersion=0\.9\.2 ' 'Install status must report its package version.'
  Assert-Match $duplicateInstallOutput ' sourceObservation=cache_inventory_not_enabled_state ' 'Cache inventory must not be reported as enabled state.'
  Assert-Match $duplicateInstallOutput ' currentSource=openai-curated-remote sourceObservation=cache_inventory_not_enabled_state cachedSourceCount=2 cachedSources=chronos,openai-curated-remote cachedDuplicateSources=true legacyGitSourcePresent=true directorySourcePresent=true legacyGitConfig=enabled sourceConflict=CONFIRMED canonicalSource=openai-curated-remote currentPluginIdentity=chronos@openai-curated-remote canonicalPluginIdentity=chronos@openai-curated-remote sessionReloadRequired=true recommendedAction=remove_legacy_git_install_then_start_new_task$' `
    'The Git and Directory duplicate must recommend the canonical migration.'
  if (($duplicateInstallOutput -join "`n").Contains($testRoot)) { throw 'Install status exposed an absolute local path.' }

  $directoryInstallOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action install-status -CodexHome $directoryInstallHome
  Assert-Match $directoryInstallOutput ' cachedSourceCount=1 cachedSources=openai-curated-remote cachedDuplicateSources=false legacyGitSourcePresent=false directorySourcePresent=true legacyGitConfig=unavailable sourceConflict=NONE canonicalSource=openai-curated-remote currentPluginIdentity=standalone canonicalPluginIdentity=chronos@openai-curated-remote sessionReloadRequired=false recommendedAction=none$' `
    'A single Directory package must not produce a duplicate warning.'

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

  [System.IO.File]::WriteAllBytes((Join-Path $invalidDbHome "logs_2.sqlite"), [byte[]](1..128))
  $invalidDbOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $invalidDbHome -SampleSeconds 1
  Assert-Match $invalidDbOutput " logDb=WARNING " "A present but unreadable diagnostic database must not be reported healthy."
  Assert-Match $invalidDbOutput " logDbReasons=query-unavailable " "Database query failure must be explicit."
  Assert-Match $invalidDbOutput " logDbQueryOk=false " "Database query availability must be emitted."

  & $PythonPath $fixtureScript partial (Join-Path $partialDbHome "logs_2.sqlite")
  if ($LASTEXITCODE -ne 0) { throw "Failed to create partial SQLite fixture." }
  $partialDbOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $partialDbHome -SampleSeconds 1
  Assert-Match $partialDbOutput " logDb=WARNING " `
    "Partial diagnostic coverage must not be reported healthy."
  Assert-Match $partialDbOutput " logDbAvailability=partial " `
    "Partial diagnostic coverage must be explicit."
  Assert-Match $partialDbOutput " logDbReasons=query-partial " `
    "Partial diagnostic coverage must explain the warning."
  Assert-Match $missingOutput " logSeq=unknown " "Missing database should not invent a sequence."

  $walDatabasePath = Join-Path $walSidecarHome "logs_2.sqlite"
  & $PythonPath $fixtureScript wal $walDatabasePath
  if ($LASTEXITCODE -ne 0) { throw "Failed to create closed WAL SQLite fixture." }
  $walBeforeHash = (Get-FileHash -LiteralPath $walDatabasePath -Algorithm SHA256).Hash
  $walBeforeDirectory = Get-DirectorySnapshot $walSidecarHome
  $walSidecarOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $walSidecarHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos closed-WAL inspection failed." }
  $walAfterDirectory = Get-DirectorySnapshot $walSidecarHome
  $walAfterHash = (Get-FileHash -LiteralPath $walDatabasePath -Algorithm SHA256).Hash
  if ($walBeforeHash -ne $walAfterHash) { throw "Logical read-only inspection changed the main WAL database." }
  $sidecarMutationObserved = $walBeforeDirectory -ne $walAfterDirectory
  Assert-Match $walSidecarOutput " sqliteOpenMode=logical_readonly sqliteJournalMode=wal sqliteSidecarMutationPossible=true sqliteSidecarMutationObserved=$($sidecarMutationObserved.ToString().ToLowerInvariant()) " `
    "SQLite open mode and observed coordination-sidecar behavior must match the Windows directory result."

  [System.IO.File]::WriteAllText(
    (Join-Path $reparseExternal "escaped.jsonl"),
    '{"timestamp":"2026-08-09T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":100000,"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":1010},"last_token_usage":{"total_tokens":10}}}}' + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $null = New-Item -ItemType Junction -Path (Join-Path $reparseHome "sessions") -Target $reparseExternal
  $reparseOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $reparseHome -SampleSeconds 1
  Assert-Match $reparseOutput " tokenFiles=0 " `
    "Session readers must reject a reparse point that escapes the canonical Codex root."

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

  Set-Content -LiteralPath (Join-Path $helperFalsePositiveHome "sandbox.log") -Value @(
    "[$markerTimestamp codex.exe] INFO user text: helper copy failed for command-runner: remove stale helper destination",
    "[$markerTimestamp codex.exe] DEBUG payload=CreateProcessWithLogonW failed: 5",
    "[$markerTimestamp codex.exe] UNSUCCESS: contains SUCCESS: but is not a launch event"
  )
  $helperFalsePositiveOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $helperFalsePositiveHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos helper false-positive inspection failed." }
  Assert-Match $helperFalsePositiveOutput " fsHelper=HEALTHY " `
    "Marker text embedded in unrelated log messages must not change helper health."
  Assert-Match $helperFalsePositiveOutput " fsHelperCopyFailure=false " `
    "Embedded copy-marker text produced a false positive."
  Assert-Match $helperFalsePositiveOutput " fsHelperLaunchFailure=false " `
    "Embedded launch-marker text produced a false positive."

  $integritySessionDay = Join-Path (Join-Path (Join-Path $tokenIntegrityHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $integritySessionDay = Join-Path $integritySessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $integritySessionDay -Force | Out-Null
  $integrityPath = Join-Path $integritySessionDay "rollout-integrity-fixture.jsonl"
  function New-IntegrityTokenRecord([string]$Timestamp, [long]$InputTokens) {
    @{
      timestamp = $Timestamp
      type = "event_msg"
      payload = @{
        type = "token_count"
        info = @{
          model_context_window = 100000
          total_token_usage = @{
            input_tokens = $InputTokens
            cached_input_tokens = 0
            cache_write_input_tokens = 0
            output_tokens = 1000
            reasoning_output_tokens = 100
            total_tokens = $InputTokens + 1000
          }
          last_token_usage = @{
            total_tokens = 1000
          }
        }
      }
    } | ConvertTo-Json -Compress -Depth 8
  }
  $firstIntegrityRecord = New-IntegrityTokenRecord "2026-07-31T12:00:02Z" 1000000L
  $outOfOrderIntegrityRecord = New-IntegrityTokenRecord "2026-07-31T12:00:01Z" 3000000L
  [System.IO.File]::WriteAllText(
    $integrityPath,
    $firstIntegrityRecord + "`n" + $firstIntegrityRecord + "`n" +
      '{"timestamp":"2026-07-31T12:00:03Z","type":"event_msg","payload":{"type":"token_count"' + "`n" +
      $outOfOrderIntegrityRecord + "`n" +
      '{"type":"event_msg","payload":{"type":"token_count"',
    [System.Text.UTF8Encoding]::new($false)
  )
  $integrityOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $tokenIntegrityHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos rollout-integrity inspection failed." }
  Assert-Match $integrityOutput " tokenFiles=1 " "A valid cumulative record should survive malformed neighbors."
  Assert-Match $integrityOutput " tokenSamples=2 " "Duplicate and incomplete token records should not be counted as samples."
  Assert-Match $integrityOutput " tokenSessionInputM=3([.,]0)? " `
    "The greatest cumulative total should win even when records are out of order."
  Assert-Match $integrityOutput " tokenMalformedRecords=1 " "Malformed complete rollout records should be counted."
  Assert-Match $integrityOutput " tokenDuplicateRecords=1 " "Duplicate rollout records should be counted and ignored."
  Assert-Match $integrityOutput " tokenOutOfOrderRecords=1 " "Out-of-order rollout timestamps should be reported."
  Assert-Match $integrityOutput " tokenTailIncompleteFiles=1 " "A partially written final rollout record should be reported and ignored."
  Assert-Match $integrityOutput " tokenCoverageContinuity=partial " `
    "Malformed, duplicate, out-of-order, or incomplete records must mark coverage partial."

  $completeNoNewlineDay = Join-Path (Join-Path (Join-Path $completeNoNewlineHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $completeNoNewlineDay = Join-Path $completeNoNewlineDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $completeNoNewlineDay -Force | Out-Null
  [System.IO.File]::WriteAllText(
    (Join-Path $completeNoNewlineDay "complete-final-record.jsonl"),
    $outOfOrderIntegrityRecord,
    [System.Text.UTF8Encoding]::new($false)
  )
  $completeNoNewlineOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $completeNoNewlineHome -SampleSeconds 1
  Assert-Match $completeNoNewlineOutput " tokenSamples=1 " "A complete final JSONL record without a newline must be retained."
  Assert-Match $completeNoNewlineOutput " tokenTailIncompleteFiles=0 " "A valid final JSONL record must not be labeled incomplete."

  $untimestampedDuplicatePath = Join-Path $completeNoNewlineDay "untimestamped-duplicate.jsonl"
  $untimestampedDuplicate = '{"type":"event_msg","payload":{"type":"context_compacted"}}'
  [System.IO.File]::WriteAllText(
    $untimestampedDuplicatePath,
    $untimestampedDuplicate + "`n" + $untimestampedDuplicate + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $untimestampedDuplicateOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $completeNoNewlineHome -SampleSeconds 1
  Assert-Match $untimestampedDuplicateOutput " tokenDuplicateRecords=1 " `
    "Exact untimestamped records must be counted once and deduplicated."

  $unsupportedCacheDay = Join-Path (Join-Path (Join-Path $unsupportedCacheHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $unsupportedCacheDay = Join-Path $unsupportedCacheDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $unsupportedCacheDay -Force | Out-Null
  $unsupportedCacheRecord = @{
    timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    type = 'event_msg'
    payload = @{
      type = 'token_count'
      info = @{
        total_token_usage = @{
          input_tokens = 1000; cached_input_tokens = 500; output_tokens = 100
          reasoning_output_tokens = 10; total_tokens = 1100
        }
        model_context_window = 100000
      }
    }
  } | ConvertTo-Json -Compress -Depth 8
  [System.IO.File]::WriteAllText(
    (Join-Path $unsupportedCacheDay 'unsupported-cache.jsonl'),
    $unsupportedCacheRecord + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $unsupportedCacheOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $unsupportedCacheHome -SampleSeconds 1
  Assert-Match $unsupportedCacheOutput " tokenCacheWriteObserved=unknown " "Unsupported cache-write telemetry must not be reported as false."
  Assert-Match $unsupportedCacheOutput " cacheWriteObservation=unsupported_schema " "Unsupported cache-write telemetry must be labeled."

  $partialCacheDay = Join-Path (Join-Path (Join-Path $partialCacheHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $partialCacheDay = Join-Path $partialCacheDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $partialCacheDay -Force | Out-Null
  [System.IO.File]::WriteAllText(
    (Join-Path $partialCacheDay 'unsupported-cache.jsonl'),
    $unsupportedCacheRecord + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $supportedCacheRecord = ($unsupportedCacheRecord | ConvertFrom-Json)
  $supportedCacheRecord.payload.info.total_token_usage | Add-Member `
    -NotePropertyName cache_write_input_tokens -NotePropertyValue 250
  [System.IO.File]::WriteAllText(
    (Join-Path $partialCacheDay 'supported-cache.jsonl'),
    ($supportedCacheRecord | ConvertTo-Json -Compress -Depth 8) + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $partialCacheOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $partialCacheHome -SampleSeconds 1
  Assert-Match $partialCacheOutput " cacheWriteObservation=observed_partial_schema " `
    "Mixed cache-write schemas must disclose partial coverage."
  Assert-Match $partialCacheOutput " cacheWriteAvailableFiles=1 cacheWriteSelectedFiles=2 " `
    "Cache-write schema coverage counts must be explicit."

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
  Assert-Match $tokenOutput " tokenCompactions=1 " `
    "Exact untimestamped compaction duplicates must be counted once."
  Assert-Match $tokenOutput " tokenCoverageWindowHours=6 " "Token coverage window was not explicit."
  Assert-Match $tokenOutput " tokenFilesEligible=1 tokenFilesSelected=1 tokenCoverageCapped=false " `
    "Token file selection coverage was not explicit."
  Assert-Match $tokenOutput " tokenCoverageContinuity=partial " `
    "A deduplicated rollout fixture must disclose partial continuity."
  Assert-Match $tokenOutput " tokenSpawnObservation=observed tokenCompactionObservation=observed " `
    "Observed worker and compaction events should be qualified."
  Assert-Match $tokenOutput " spawnForkUnknown=1 spawnSchemaV1=0 spawnSchemaV2=0 spawnSchemaUnknown=1 " `
    "An unversioned spawn with no fork field must not imply full-context inheritance."
  Assert-Match $tokenOutput " tokenQuotaContributors=.*(cache-write-volume|input-50m)" `
    "High quota risk should expose contributing measurements."
  Assert-Match $tokenOutput " tokenAdvice=lower-effort,fresh-task,bound-subagents,cache-write-risk(\r?\n|$)" `
    "Token advice did not reflect the aggregate risk signals."
  if (($tokenOutput -join "`n") -match "private fixture arguments") {
    throw "Chronos output exposed tool arguments."
  }

  $intervalSessionDay = Join-Path (Join-Path (Join-Path $tokenIntervalHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $intervalSessionDay = Join-Path $intervalSessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $intervalSessionDay -Force | Out-Null
  $intervalStart = [DateTimeOffset]::UtcNow.AddMinutes(-5)
  $intervalRecords = foreach ($definition in @(
      @{ seconds = 0; input = 1000000L; cached = 500000L; output = 10000L; reasoning = 2000L; write = 100000L },
      @{ seconds = 60; input = 3000000L; cached = 1500000L; output = 30000L; reasoning = 6000L; write = 300000L }
    )) {
    @{
      timestamp = $intervalStart.AddSeconds($definition.seconds).ToString("o")
      type = "event_msg"
      payload = @{
        type = "token_count"
        info = @{
          model_context_window = 100000
          total_token_usage = @{
            input_tokens = $definition.input
            cached_input_tokens = $definition.cached
            cache_write_input_tokens = $definition.write
            output_tokens = $definition.output
            reasoning_output_tokens = $definition.reasoning
            total_tokens = $definition.input + $definition.output
          }
          last_token_usage = @{ total_tokens = 1000 }
        }
      }
    } | ConvertTo-Json -Compress -Depth 8
  }
  [System.IO.File]::WriteAllLines(
    (Join-Path $intervalSessionDay "rollout-token-interval.jsonl"),
    $intervalRecords,
    [System.Text.UTF8Encoding]::new($false)
  )
  $intervalOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $tokenIntervalHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos token interval inspection failed." }
  Assert-Match $intervalOutput " tokenIntervalInputM=2([.,]0)? .*tokenIntervalCachedInputM=1([.,]0)? .*tokenIntervalOutputM=0([.,]02)? .*tokenIntervalReasoningM=0([.,]004)? .*tokenIntervalCacheWriteM=0([.,]2)? .*tokenIntervalFiles=1 " `
    "Comparable timestamped snapshots must produce marginal interval deltas."
  Assert-Match $intervalOutput " tokenIntervalObservation=observed " `
    "Complete token coverage must distinguish an observed interval from the cumulative snapshot."

  $reviewerSessionDay = Join-Path (Join-Path (Join-Path $reviewerHealthHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $reviewerSessionDay = Join-Path $reviewerSessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $reviewerSessionDay -Force | Out-Null
  $reviewerPath = Join-Path $reviewerSessionDay "rollout-reviewer-fixture.jsonl"
  $reviewerRecords = [System.Collections.Generic.List[string]]::new()
  $reviewerStart = [DateTimeOffset]::UtcNow.AddMinutes(-10)
  $reviewerRecords.Add((@{
    timestamp = $reviewerStart.AddSeconds(-1).ToString("o")
    type = "session_meta"
    payload = @{
      multi_agent_version = 2
      codex_version = "0.146.0-alpha.3.1"
      auth_provider = "chatgpt"
      auto_review_model_configurable = $false
      parent_thread_id = "private-parent-id-must-not-be-returned"
    }
  } | ConvertTo-Json -Compress -Depth 8))
  foreach ($index in 0..589) {
    $reviewerRecords.Add((@{
      timestamp = $reviewerStart.AddSeconds($index).ToString("o")
      type = "turn_context"
      payload = @{ model = "codex-auto-review"; approval_mode = "auto" }
    } | ConvertTo-Json -Compress -Depth 8))
    if ($index -lt 589) {
      $reviewerRecords.Add((@{
        timestamp = $reviewerStart.AddSeconds($index).AddMilliseconds(1).ToString("o")
        type = "thread_settings_applied"
        payload = @{ model = "codex-auto-review" }
      } | ConvertTo-Json -Compress -Depth 8))
    }
  }
  foreach ($index in 0..9) {
    $reviewerRecords.Add((@{
      timestamp = $reviewerStart.AddSeconds(590 + $index).ToString("o")
      type = "event_msg"
      payload = @{
        type = "exec_approval_request"
        tool_name = "shell"
        permission_class = "workspace-read"
        operation_class = "repository-read"
        proposed_prefix = @("rg", "synthetic-pattern")
        command = "private command text must never be returned"
      }
    } | ConvertTo-Json -Compress -Depth 8))
  }
  $reviewerRecords.Add((@{
    timestamp = $reviewerStart.AddSeconds(599).AddMilliseconds(1).ToString("o")
    type = "event_msg"
    payload = @{
      type = "apply_patch_approval_request"
      tool_name = "apply_patch"
      permission_class = "workspace-write"
      operation_class = "write"
    }
  } | ConvertTo-Json -Compress -Depth 8))
  $reviewerRecords.Add((@{
    timestamp = $reviewerStart.AddSeconds(599).AddMilliseconds(2).ToString("o")
    type = "event_msg"
    payload = @{ type = "approval_decision"; decision = "denied" }
  } | ConvertTo-Json -Compress -Depth 8))
  $duplicateCompaction = (@{
    timestamp = $reviewerStart.AddSeconds(600).ToString("o")
    type = "event_msg"
    payload = @{ type = "context_compacted" }
  } | ConvertTo-Json -Compress -Depth 8)
  $reviewerRecords.Add($duplicateCompaction)
  [System.IO.File]::WriteAllLines($reviewerPath, $reviewerRecords, [System.Text.UTF8Encoding]::new($false))
  $reviewerDuplicatePath = Join-Path $reviewerSessionDay "rollout-reviewer-duplicate-fixture.jsonl"
  [System.IO.File]::WriteAllText(
    $reviewerDuplicatePath,
    $duplicateCompaction + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $reviewerOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $reviewerHealthHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos reviewer-health inspection failed." }
  Assert-Match $reviewerOutput " approvalReviewTurnsObserved=590 " `
    "Reviewer turns must count only turn_context records, not matching bookkeeping records."
  Assert-Match $reviewerOutput " approvalReviewerSessionsObserved=1 " `
    "Reviewer sessions should be counted without exposing session identifiers."
  Assert-Match $reviewerOutput " approvalReviewerModels=codex-auto-review " `
    "The observed reviewer model was not surfaced."
  Assert-Match $reviewerOutput " approvalReviewObservation=observed " `
    "Complete reviewer coverage should qualify the count as observed."
  Assert-Match $reviewerOutput " approvalAverageIntervalSeconds=1([.,]0)? " `
    "Reviewer intervals should be calculated from structured timestamps."
  Assert-Match $reviewerOutput " approvalPeakPerMinute=60 approvalConcurrentPeak=1 approvalParentLinksObserved=1 " `
    "Reviewer peak, concurrency, and parent-link aggregates were not reported."
  Assert-Match $reviewerOutput " approvalRequestsObserved=11 approvalUniqueClasses=2 approvalRepeatedRequests=9 approvalRepeatPct=81([.,]8)? " `
    "Structured approval requests should be classed without reading command text."
  Assert-Match $reviewerOutput " approvalSources=filesystem:1,shell:10 approvalDeniedObserved=1 approvalDeniedObservation=observed " `
    "Approval source and denial aggregates were not reported."
  Assert-Match $reviewerOutput " rolloutLineageLinksObserved=1 rolloutForkFilesObserved=1 " `
    "Sanitized lineage counts should recognize the parent link."
  Assert-Match $reviewerOutput " codexVersionsObserved=0\.146\.0-alpha\.3\.1 authProvidersObserved=chatgpt " `
    "Sanitized runtime metadata should be reported when available."
  Assert-Match $reviewerOutput " approvalModesObserved=auto reviewerControlCapability=unsupported reviewerCompatibility=diagnostic_only " `
    "Reviewer-control capability must be explicit and must not invent an override."
  Assert-Match $reviewerOutput " rolloutCrossFileDuplicateCompactions=1 " `
    "Exact cross-rollout compaction duplicates should be identified separately."
  Assert-Match $reviewerOutput " approvalRequestObservation=observed approvalOptimization=no_change_recommended " `
    "Denied or unresolved repetition must not recommend a permission rule."
  if (($reviewerOutput -join "`n") -match "private-parent-id|private command text") {
    throw "Chronos output exposed a session identifier or approval command."
  }
  Assert-Match $reviewerOutput " metricSource=local_rollout dashboardEquivalence=unsupported billingInference=unsupported " `
    "Local approval metrics must not be presented as dashboard or billing equivalents."
  Assert-Match $reviewerOutput " approvalRepeatedPrefixRequests=9 approvalLargestPrefixRepeat=10 approvalResolvedAllowedEquivalences=0 approvalLargestResolvedAllowedRepeat=0 approvalRuleMissDiagnosis=not_observed " `
    "Repeated denied or unresolved prefixes must not be classified as rule misses."
  Assert-Match $reviewerOutput " inspectionShapedApprovalRequests=10 inspectionShapedApprovalPct=90([.,]9)? " `
    "Inspection-shaped approval pressure should remain a descriptive measurement."
  Assert-Match $reviewerOutput " approvalRateConfidence=low " `
    "A sub-fifteen-minute reviewer sample must have low normalized-rate confidence."

  $machine2Rules = Join-Path $machine2Home "rules"
  New-Item -ItemType Directory -Path $machine2Rules -Force | Out-Null
  $longLiteral = "x" * 300
  [System.IO.File]::WriteAllLines(
    (Join-Path $machine2Rules "default.rules"),
    @(
      "prefix_rule(",
      "    pattern = [`"powershell.exe`", `"$longLiteral`"],",
      "    decision = `"allow`",",
      ")",
      "prefix_rule(pattern=[`"python`"], decision=`"allow`")",
      "prefix_rule(pattern=[`"npm.cmd`",`"run`",`"test`"], decision=`"allow`")",
      "prefix_rule(",
      "    pattern = [`"cmd`", `"API_KEY=synthetic_value_for_test_only`"],",
      "    decision = `"allow`",",
      ")",
      "prefix_rule(pattern=['python3'], decision='allow')",
      "prefix_rule(pattern=[r'C:\Tools\node.exe'], decision='allow')",
      "prefix_rule(justification=`"`"`"required for tooling`"`"`", pattern=['pwsh'], decision='allow')",
      "prefix_rule(justification='reordered', pattern=['npm.cmd','run','lint'], decision='allow')",
      "prefix_rule(",
      "    # API_KEY=sk-comment-only-must-not-match-123456789",
      "    pattern=['git','status'], decision='allow',",
      ")",
      "prefix_rule(pattern=[['rg','--files'],['git','status']], decision='allow')",
      "prefix_rule(pattern=['cmd','say \'hello\''], decision='allow')",
      "prefix_rule(pattern=['cmd','$longLiteral'], decision='allow')"
    ),
    [System.Text.UTF8Encoding]::new($false)
  )
  [System.IO.File]::WriteAllText(
    (Join-Path $machine2Rules "quoted-examples.toml"),
    "# prefix_rule(pattern=[`"ignored-comment`"], decision=`"allow`")`nnotes = `"`"`"prefix_rule(pattern=[`"ignored-string`"], decision=`"allow`")`"`"`"`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  [System.IO.File]::WriteAllLines(
    (Join-Path $machine2Home "config.toml"),
    @('approvals_reviewer="guardian_subagent"', 'model_reasoning_effort="xhigh"'),
    [System.Text.UTF8Encoding]::new($false)
  )
  $machine2Start = [DateTimeOffset]::UtcNow.AddDays(-28)
  $machine2SessionDay = Join-Path (Join-Path (Join-Path $machine2Home "sessions") `
    $machine2Start.ToString("yyyy")) $machine2Start.ToString("MM")
  $machine2SessionDay = Join-Path $machine2SessionDay $machine2Start.ToString("dd")
  New-Item -ItemType Directory -Path $machine2SessionDay -Force | Out-Null
  $machine2Path = Join-Path $machine2SessionDay "rollout-machine2-regression.jsonl"
  $machine2Records = [System.Collections.Generic.List[string]]::new()
  $machine2Records.Add((@{
    timestamp = $machine2Start.ToString("o")
    type = "session_meta"
    payload = @{ id = "root-machine-2"; multi_agent_version = 2 }
  } | ConvertTo-Json -Compress -Depth 8))
  foreach ($index in 0..589) {
    $machine2Records.Add((@{
      timestamp = $machine2Start.AddSeconds($index + 1).ToString("o")
      type = "turn_context"
      payload = @{ model = "codex-auto-review"; approval_mode = "auto" }
    } | ConvertTo-Json -Compress -Depth 8))
  }
  $machine2Records.Add((@{
    timestamp = $machine2Start.AddSeconds(600).ToString("o")
    type = "event_msg"
    payload = @{
      type = "exec_approval_request"
      approval_id = "approval-machine2"
      approval_state = "pending"
      operation_class = "repository-read"
      access_mode = "read"
      boundary_cause = "policy-rule-miss"
      proposed_prefix = @("rg", "synthetic-pattern")
    }
  } | ConvertTo-Json -Compress -Depth 8))
  $machine2Records.Add((@{
    timestamp = $machine2Start.AddSeconds(600).AddMilliseconds(1).ToString("o")
    type = "event_msg"
    payload = @{ type = "approval_decision"; approval_id = "approval-machine2"; decision = "allow" }
  } | ConvertTo-Json -Compress -Depth 8))
  $machine2Records.Add((@{
    timestamp = $machine2Start.AddSeconds(600).AddMilliseconds(2).ToString("o")
    type = "event_msg"
    payload = @{ type = "approval_state_persistence_error"; approval_id = "approval-machine2" }
  } | ConvertTo-Json -Compress -Depth 8))
  foreach ($index in 1..581) {
    $machine2Records.Add((@{
      timestamp = $machine2Start.AddSeconds(600 + $index).ToString("o")
      type = "event_msg"
      payload = @{
        type = "exec_approval_request"
        approval_id = "approval-machine2-retry-$index"
        approval_state = "pending"
        operation_class = "repository-read"
        access_mode = "read"
        boundary_cause = "policy-rule-miss"
        proposed_prefix = @("rg", "synthetic-pattern")
      }
    } | ConvertTo-Json -Compress -Depth 8))
  }
  $machine2Records.Add((@{
    timestamp = $machine2Start.AddSeconds(1182).ToString("o")
    type = "response_item"
    payload = @{
      type = "function_call"
      name = "spawn_agent"
      arguments = (@{ fork_turns = "all"; task_complexity = "simple"; reasoning_effort = "max" } | ConvertTo-Json -Compress)
    }
  } | ConvertTo-Json -Compress -Depth 8))
  foreach ($index in 0..1) {
    $machine2Records.Add((@{
      timestamp = $machine2Start.AddSeconds(1183 + $index).ToString("o")
      type = "response_item"
      payload = @{
        type = "function_call"
        name = "shell_command"
        call_id = "machine2-escalation-$index"
        arguments = (@{
          sandbox_permissions = "require_escalated"
          prefix_rule = @("rg", "synthetic-pattern")
          command = "private current-schema command must never be returned"
          justification = "private current-schema justification must never be returned"
        } | ConvertTo-Json -Compress)
      }
    } | ConvertTo-Json -Compress -Depth 8))
  }
  $machine2Records.Add((@{
    timestamp = $machine2Start.AddSeconds(1184).AddMilliseconds(500).ToString("o")
    type = "response_item"
    payload = @{
      type = "function_call_output"
      call_id = "machine2-escalation-1"
      output = "private tool output and secret sk-not-returned-123456789"
    }
  } | ConvertTo-Json -Compress -Depth 8))
  [System.IO.File]::WriteAllLines($machine2Path, $machine2Records, [System.Text.UTF8Encoding]::new($false))
  $machine2Output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $machine2Home -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos Machine 2 regression inspection failed." }
  Assert-Match $machine2Output " approvalReviewTurnsObserved=590 " `
    "Machine 1 regression must retain 590 distinct reviewer turn_context records."
  Assert-Match $machine2Output " approvalDecisionsObserved=1 approvalAllowedObserved=1 approvalDeniedObserved=0 approvalUnknownDecisions=0 approvalAllowPct=100 " `
    "Allowed decisions and allow rate were not accounted separately."
  Assert-Match $machine2Output " approvalPersistenceRetries=581 approvalPersistenceFailures=1 approvalPersistenceDiagnosis=approval_state_persistence_runaway " `
    "Structurally equivalent retries with regenerated IDs must be classified as a persistence runaway."
  Assert-Match $machine2Output " approvalRequestSchemas=event_msg,function_call_escalation approvalResolvedRequests=1 approvalUnresolvedRequests=583 approvalResolutionObservation=observed_partial_outcomes approvalLatencySamples=1 approvalMedianLatencyMs=500 approvalP95LatencyMs=500 " `
    "Current function-call escalation requests must expose bounded resolution and latency aggregates."
  Assert-Match $machine2Output " reviewerToolCalls=3 reviewerEscalationsObserved=2 reviewerEscalationUniquePrefixes=1 reviewerEscalationRepeatedPrefixes=1 reviewerEscalationLargestPrefix=2 " `
    "Reviewer-originated escalation traffic was not classified independently."
  Assert-Match $machine2Output " ruleCount=12 ruleMonolithic=2 ruleReusableNarrow=4 ruleBroadInterpreter=8 ruleCredentialShaped=1 " `
    "Structured rule parsing did not classify single, raw, triple, reordered, nested, escaped, and comment forms correctly."
  Assert-Match $machine2Output " ruleStatus=CRITICAL ruleValuesReturned=false " `
    "Credential-shaped rule output must be critical and must never return values."
  Assert-Match $machine2Output " ruleSecretCandidateOrdinals=4 ruleSecretCandidateClasses=4:placeholder-like ruleSecretConfidence=low " `
    "Rule diagnostics must provide privacy-safe ordinal, category, and confidence without secret text."
  Assert-Match $machine2Output " ruleFilesEligible=2 ruleFilesSelected=2 ruleCoverageCapped=false ruleParseFailures=0 " `
    "Comments, raw strings, escaped quotes, and triple-quoted examples must parse without false blocks."
  Assert-Match $machine2Output " ruleBrittlenessDiagnosis=rule_brittleness_warning ruleSecretDiagnosis=rule_secret_exposure ruleBroadInterpreterDiagnosis=broad_interpreter_rule " `
    "Named rule defect classes were not emitted."
  Assert-Match $machine2Output " spawnForkAll=1 spawnForkAllDefaulted=0 spawnForkNone=0 spawnForkBounded=0 .*spawnHighEffort=1 spawnMaxEffort=1 " `
    "Full-history and high-effort worker amplification was not measured."
  Assert-Match $machine2Output " spawnForkUnknown=0 spawnSchemaV1=0 spawnSchemaV2=1 spawnSchemaUnknown=0 " `
    "A versioned V2 spawn must be classified by its advertised schema."
  Assert-Match $machine2Output " spawnContextAmplification=observed rootAgentSpawns=1 childAgentSpawns=0 nestedAgentObservation=not_observed " `
    "Root-only spawning must not be misreported as recursive child-agent fan-out."
  Assert-Match $machine2Output " configuredReviewer=guardian_subagent effectiveReviewer=auto_review managedReviewer=unavailable reviewerConfigurationComparison=different_labels_mapping_possible primaryReasoningDefault=xhigh" `
    "Configured and effective reviewer labels should be surfaced without asserting incompatibility."
  if (($machine2Output -join "`n") -match "synthetic_value_for_test_only|API_KEY|synthetic-pattern|approval-machine2|root-machine-2|private current-schema|sk-not-returned") {
    throw "Chronos output exposed a credential, prefix, approval identifier, or session identifier."
  }

  $ruleStructureRoot = Join-Path $ruleStructureHome "rules"
  New-Item -ItemType Directory -Path $ruleStructureRoot -Force | Out-Null
  [System.IO.File]::WriteAllLines(
    (Join-Path $ruleStructureRoot "structured.rules"),
    @(
      "prefix_rule(pattern=[['powershell','pwsh']], decision='allow')",
      "prefix_rule(pattern=[['cmd.exe','cmd']], decision='allow')",
      "prefix_rule(pattern=['powershell','-Command'], decision='allow')",
      "prefix_rule(pattern=['bash','-c'], decision='allow')",
      "prefix_rule(pattern=[r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'], decision='allow')",
      "prefix_rule(pattern=['powershell','-NoProfile','-Command'], decision='allow')",
      "prefix_rule(pattern=['cmd.exe','/d','/c'], decision='allow')",
      "prefix_rule(pattern=['bash','--noprofile','-c'], decision='allow')",
      "prefix_rule(pattern=['python','-I','-c'], decision='allow')",
      "prefix_rule(pattern=['node','--no-warnings','-e'], decision='allow')",
      "prefix_rule(pattern=['powershell','-ExecutionPolicy','Bypass'], decision='allow')",
      "prefix_rule(pattern=['powershell','-WorkingDirectory',r'C:\safe'], decision='allow')",
      "prefix_rule(pattern=['python','-X','utf8'], decision='allow')",
      "prefix_rule(pattern=['node','--require','module'], decision='allow')",
      "prefix_rule(pattern=['bash','--rcfile','file'], decision='allow')",
      "prefix_rule(pattern=['powershell','-File'], decision='allow')",
      "prefix_rule(pattern=['powershell',['-NoProfile','safe.ps1']], decision='allow')",
      "prefix_rule(pattern=['powershell',['-File','safe.ps1']], decision='allow')",
      "prefix_rule(pattern=[['powershell','pwsh'],'-File','safe.ps1'], decision='allow')",
      "prefix_rule(pattern=[['powershell','pwsh'],'-File',['safe.ps1','other.ps1']], decision='allow')",
      "prefix_rule(pattern=['curl','https://safe.example'], decision='allow')",
      "prefix_rule(pattern=['powershell'], decision='prompt')",
      "prefix_rule(pattern=['cmd.exe'], decision='forbidden')"
    ),
    [System.Text.UTF8Encoding]::new($false)
  )
  $ruleStructureOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $ruleStructureHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos structured rule regression failed." }
  Assert-Match $ruleStructureOutput " ruleCount=23 ruleMonolithic=0 ruleReusableNarrow=4 ruleBroadInterpreter=19 ruleCredentialShaped=0 " `
    "Nested alternatives, curl multi-URL prefixes, raw Windows paths, displaced arbitrary-code flags, branch-specific missing operands, constrained files, and non-allow decisions were not classified safely."
  Assert-Match $ruleStructureOutput " ruleFilesEligible=1 ruleFilesSelected=1 ruleCoverageCapped=false ruleParseFailures=0 " `
    "Valid structured rule alternatives must parse without degraded coverage."

  $stableApprovalDay = Join-Path (Join-Path (Join-Path $stableApprovalHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $stableApprovalDay = Join-Path $stableApprovalDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $stableApprovalDay -Force | Out-Null
  $stableStart = [DateTimeOffset]::UtcNow.AddMinutes(-5)
  $stableRecords = @(
    @{ timestamp=$stableStart.ToString('o'); type='session_meta'; payload=@{ id='stable-root' } },
    @{ timestamp=$stableStart.AddSeconds(1).ToString('o'); type='event_msg'; payload=@{
        type='exec_approval_request'; approval_id='stable-request'; approval_state='pending'
        operation_class='repository-read'; proposed_prefix=@('rg','stable') } },
    @{ timestamp=$stableStart.AddSeconds(2).ToString('o'); type='event_msg'; payload=@{
        type='approval_decision'; approval_id='stable-request'; decision='allow' } },
    @{ timestamp=$stableStart.AddSeconds(3).ToString('o'); type='event_msg'; payload=@{
        type='exec_approval_request'; approval_id='stable-request'; approval_state='pending'
        operation_class='repository-read'; proposed_prefix=@('rg','stable') } },
    @{ timestamp=$stableStart.AddSeconds(4).ToString('o'); type='event_msg'; payload=@{
        type='approval_resolved'; approval_id='stable-request'; status='resolved' } },
    @{ timestamp=$stableStart.AddSeconds(5).ToString('o'); type='event_msg'; payload=@{
        type='exec_approval_request'; call_id='mirror-request'; approval_state='pending'
        operation_class='rg'; proposed_prefix=@('rg','mirror') } },
    @{ timestamp=$stableStart.AddSeconds(5).ToString('o'); type='response_item'; payload=@{
        type='function_call'; name='shell_command'; call_id='mirror-request'
        arguments=(@{ sandbox_permissions='require_escalated'; prefix_rule=@('rg','mirror') } | ConvertTo-Json -Compress) } },
    @{ timestamp=$stableStart.AddSeconds(6).ToString('o'); type='event_msg'; payload=@{
        type='approval_decision'; decision='deferred' } },
    @{ timestamp=$stableStart.AddSeconds(7).ToString('o'); type='response_item'; payload=@{
        type='function_call'; name='shell_command'; call_id='ambiguous-nested-arguments'
        arguments='{"sandbox_permissions":"none","sandbox_permissions":"require_escalated"}' } }
  ) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 }
  [System.IO.File]::WriteAllLines(
    (Join-Path $stableApprovalDay 'rollout-stable-approval.jsonl'), $stableRecords,
    [System.Text.UTF8Encoding]::new($false)
  )
  $stableOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $stableApprovalHome -SampleSeconds 1
  Assert-Match $stableOutput " approvalRequestsObserved=3 " `
    "A later same-ID request must count while an exact cross-schema mirror remains deduplicated."
  Assert-Match $stableOutput " tokenMalformedRecords=1 " `
    "Duplicate keys inside JSON-encoded function-call arguments must be rejected as malformed."
  Assert-Match $stableOutput " approvalPersistenceRetries=1 approvalPersistenceFailures=0 approvalPersistenceDiagnosis=approval_state_persistence_runaway " `
    "A stable-correlation pending retry after ALLOW must be classified as a persistence runaway."
  Assert-Match $stableOutput " approvalDecisionsObserved=2 approvalAllowedObserved=1 approvalDeniedObserved=0 approvalUnknownDecisions=1 approvalAllowPct=100 " `
    "Unknown outcomes must be counted but excluded from the known-decision allow-rate denominator."
  if (($stableOutput -join "`n") -match "stable-request|mirror-request|stable-root") {
    throw "Stable-correlation diagnostics exposed local identifiers."
  }

  $v1ForkDay = Join-Path (Join-Path (Join-Path $v1ForkHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $v1ForkDay = Join-Path $v1ForkDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $v1ForkDay -Force | Out-Null
  $v1ForkStart = [DateTimeOffset]::UtcNow.AddMinutes(-4)
  $v1ForkRecords = @(
    @{ timestamp=$v1ForkStart.ToString('o'); type='session_meta'; payload=@{
        id='v1-root'; multi_agent_version=1 } },
    @{ timestamp=$v1ForkStart.AddSeconds(1).ToString('o'); type='response_item'; payload=@{
        type='function_call'; name='spawn_agent'
        arguments=(@{ fork_context=$false; task_complexity='simple' } | ConvertTo-Json -Compress) } },
    @{ timestamp=$v1ForkStart.AddSeconds(2).ToString('o'); type='response_item'; payload=@{
        type='function_call'; name='spawn_agent'
        arguments=(@{ task_complexity='simple' } | ConvertTo-Json -Compress) } }
  ) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 }
  [System.IO.File]::WriteAllLines(
    (Join-Path $v1ForkDay 'rollout-v1-fork.jsonl'), $v1ForkRecords,
    [System.Text.UTF8Encoding]::new($false)
  )
  $v1ForkOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $v1ForkHome -SampleSeconds 1
  Assert-Match $v1ForkOutput " spawnForkAll=0 spawnForkAllDefaulted=0 spawnForkNone=1 spawnForkBounded=0 spawnForkUnknown=1 " `
    "V1 fork_context=false must mean none; missing V1 fork context must remain unknown."
  Assert-Match $v1ForkOutput " spawnSchemaV1=2 spawnSchemaV2=0 spawnSchemaUnknown=0 " `
    "V1 spawn records must retain their advertised schema."

  $ruleMissSessionDay = Join-Path (Join-Path (Join-Path $ruleMissHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $ruleMissSessionDay = Join-Path $ruleMissSessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $ruleMissSessionDay -Force | Out-Null
  $ruleMissPath = Join-Path $ruleMissSessionDay "rollout-rule-miss-regression.jsonl"
  $ruleMissRecords = [System.Collections.Generic.List[string]]::new()
  $ruleMissStart = [DateTimeOffset]::UtcNow.AddMinutes(-10)
  $ruleMissRecords.Add((@{
    timestamp = $ruleMissStart.ToString("o"); type = "session_meta"; payload = @{ id = "rule-miss-root" }
  } | ConvertTo-Json -Compress -Depth 8))
  foreach ($index in 0..306) {
    $requestId = "resolved-request-$index"
    $ruleMissRecords.Add((@{
      timestamp = $ruleMissStart.AddMilliseconds(3 * $index + 1).ToString("o")
      type = "event_msg"
      payload = @{
        type = "exec_approval_request"; approval_id = $requestId; approval_state = "pending"
        operation_class = "repository-read"; access_mode = "read"; boundary_cause = "policy-rule-miss"
        proposed_prefix = @("get-content", "synthetic-file")
      }
    } | ConvertTo-Json -Compress -Depth 8))
    $ruleMissRecords.Add((@{
      timestamp = $ruleMissStart.AddMilliseconds(3 * $index + 2).ToString("o")
      type = "event_msg"
      payload = @{ type = "approval_decision"; approval_id = $requestId; decision = "allow" }
    } | ConvertTo-Json -Compress -Depth 8))
    $ruleMissRecords.Add((@{
      timestamp = $ruleMissStart.AddMilliseconds(3 * $index + 3).ToString("o")
      type = "event_msg"
      payload = @{ type = "approval_resolved"; approval_id = $requestId; status = "resolved" }
    } | ConvertTo-Json -Compress -Depth 8))
  }
  [System.IO.File]::WriteAllLines($ruleMissPath, $ruleMissRecords, [System.Text.UTF8Encoding]::new($false))
  $ruleMissOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $ruleMissHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos repeated rule-miss regression failed." }
  Assert-Match $ruleMissOutput " approvalDecisionsObserved=307 approvalAllowedObserved=307 approvalDeniedObserved=0 approvalUnknownDecisions=0 approvalAllowPct=100 " `
    "Repeated allowed decisions were not aggregated."
  Assert-Match $ruleMissOutput " approvalResolvedRequests=307 approvalUnresolvedRequests=0 approvalResolutionObservation=observed_complete_outcomes " `
    "A fully resolved approval sample must report complete outcomes."
  Assert-Match $ruleMissOutput " approvalPersistenceRetries=0 approvalPersistenceFailures=0 approvalPersistenceDiagnosis=not_observed " `
    "Resolved approvals must not be classified as persistence failures."
  Assert-Match $ruleMissOutput " approvalRepeatedPrefixRequests=306 approvalLargestPrefixRepeat=307 approvalResolvedAllowedEquivalences=1 approvalLargestResolvedAllowedRepeat=307 approvalRuleMissDiagnosis=repeated_rule_miss_candidate approvalProblemClass=rule_miss_amplification " `
    "The exact 307-review prefix regression was not classified as a repeated rule miss."
  if (($ruleMissOutput -join "`n") -match "synthetic-file|resolved-request|rule-miss-root") {
    throw "Repeated rule-miss output exposed a prefix or local identifier."
  }

  $independentAllowDay = Join-Path (Join-Path (Join-Path $independentAllowHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $independentAllowDay = Join-Path $independentAllowDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $independentAllowDay -Force | Out-Null
  $independentAllowStart = [DateTimeOffset]::UtcNow.AddMinutes(-4)
  $independentAllowRecords = @(
    @{ timestamp=$independentAllowStart.ToString('o'); type='session_meta'; payload=@{ id='independent-root' } },
    @{ timestamp=$independentAllowStart.AddSeconds(1).ToString('o'); type='event_msg'; payload=@{
        type='exec_approval_request'; approval_id='request-a'; approval_state='pending'; operation_class='repository-read'; proposed_prefix=@('rg','safe') } },
    @{ timestamp=$independentAllowStart.AddSeconds(2).ToString('o'); type='event_msg'; payload=@{
        type='approval_decision'; approval_id='request-a'; decision='allow' } },
    @{ timestamp=$independentAllowStart.AddSeconds(3).ToString('o'); type='event_msg'; payload=@{
        type='approval_resolved'; approval_id='request-a'; status='resolved' } },
    @{ timestamp=$independentAllowStart.AddSeconds(4).ToString('o'); type='event_msg'; payload=@{
        type='exec_approval_request'; approval_id='request-b'; approval_state='pending'; operation_class='repository-read'; proposed_prefix=@('rg','safe') } },
    @{ timestamp=$independentAllowStart.AddSeconds(5).ToString('o'); type='event_msg'; payload=@{
        type='approval_resolved'; approval_id='request-b'; status='resolved' } },
    @{ timestamp=$independentAllowStart.AddSeconds(6).ToString('o'); type='event_msg'; payload=@{
        type='exec_approval_request'; approval_id='request-c'; approval_state='pending'; operation_class='repository-read' } },
    @{ timestamp=$independentAllowStart.AddSeconds(7).ToString('o'); type='event_msg'; payload=@{
        type='approval_decision'; approval_id='request-c'; decision='allow' } },
    @{ timestamp=$independentAllowStart.AddSeconds(8).ToString('o'); type='event_msg'; payload=@{
        type='approval_resolved'; approval_id='request-c'; status='resolved' } },
    @{ timestamp=$independentAllowStart.AddSeconds(9).ToString('o'); type='event_msg'; payload=@{
        type='exec_approval_request'; approval_id='request-d'; approval_state='pending'; operation_class='repository-read' } },
    @{ timestamp=$independentAllowStart.AddSeconds(10).ToString('o'); type='event_msg'; payload=@{
        type='approval_decision'; approval_id='request-d'; decision='allow' } },
    @{ timestamp=$independentAllowStart.AddSeconds(11).ToString('o'); type='event_msg'; payload=@{
        type='approval_resolved'; approval_id='request-d'; status='resolved' } }
  ) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 }
  [System.IO.File]::WriteAllLines(
    (Join-Path $independentAllowDay 'rollout-independent-allow.jsonl'),
    $independentAllowRecords,
    [System.Text.UTF8Encoding]::new($false)
  )
  $independentAllowOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $independentAllowHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos independent ALLOW regression failed." }
  Assert-Match $independentAllowOutput " approvalDecisionsObserved=3 approvalAllowedObserved=3 approvalDeniedObserved=0 approvalUnknownDecisions=0 approvalAllowPct=100 " `
    "Explicit approval decisions were not counted independently."
  Assert-Match $independentAllowOutput " approvalResolvedRequests=4 approvalUnresolvedRequests=0 approvalResolutionObservation=observed_complete_outcomes " `
    "The independent ALLOW fixture must have four terminal request outcomes."
  Assert-Match $independentAllowOutput " approvalResolvedAllowedEquivalences=1 approvalLargestResolvedAllowedRepeat=1 approvalRuleMissDiagnosis=not_observed " `
    "A request without its own ALLOW or without a supported prefix must not qualify for rule-miss advice."

  $forkSessionDay = Join-Path (Join-Path (Join-Path $forkReplayHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $forkSessionDay = Join-Path $forkSessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $forkSessionDay -Force | Out-Null
  function New-ForkTokenRecord([string]$Timestamp, [long]$InputTokens) {
    @{
      timestamp = $Timestamp
      type = "event_msg"
      payload = @{
        type = "token_count"
        info = @{
          model_context_window = 100000
          total_token_usage = @{
            input_tokens = $InputTokens
            cached_input_tokens = 0
            cache_write_input_tokens = 0
            output_tokens = 1000
            reasoning_output_tokens = 100
            total_tokens = $InputTokens + 1000
          }
          last_token_usage = @{ total_tokens = 1000 }
        }
      }
    } | ConvertTo-Json -Compress -Depth 8
  }
  $sharedForkToken = New-ForkTokenRecord "2026-08-01T12:00:00Z" 10000000L
  $childForkToken = New-ForkTokenRecord "2026-08-01T12:01:00Z" 12000000L
  $primaryTurn = @{
    timestamp = "2026-08-01T11:59:00Z"
    type = "turn_context"
    payload = @{ model = "gpt-primary"; effort = "medium" }
  } | ConvertTo-Json -Compress -Depth 8
  $parentForkPath = Join-Path $forkSessionDay "rollout-parent.jsonl"
  [System.IO.File]::WriteAllLines(
    $parentForkPath, @($primaryTurn, $sharedForkToken), [System.Text.UTF8Encoding]::new($false)
  )
  Start-Sleep -Milliseconds 20
  $childForkPath = Join-Path $forkSessionDay "rollout-child.jsonl"
  [System.IO.File]::WriteAllLines(
    $childForkPath, @($primaryTurn, $sharedForkToken, $childForkToken),
    [System.Text.UTF8Encoding]::new($false)
  )
  $forkOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $forkReplayHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos fork replay inspection failed." }
  Assert-Match $forkOutput " tokenFiles=2 tokenSamples=3 tokenSessionInputM=12([.,]0)? " `
    "Exact inherited token snapshots must contribute only the child's observed delta."
  Assert-Match $forkOutput " tokenInheritedSnapshots=1 tokenLineageDeltaFiles=1 " `
    "Exact inherited snapshot and lineage-delta counts were not reported."
  Assert-Match $forkOutput " rolloutCrossFileDuplicateRecords=2 " `
    "Exact duplicated turn and token records should be counted across rollouts."

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
  Assert-Match $largeTailOutput " tokenTailTruncatedFiles=1 tokenUnreadableFiles=0 tokenCoverageContinuity=partial " `
    "A bounded tail must disclose partial continuity."
  Assert-Match $largeTailOutput " quotaConfidence=low " `
    "A truncated token sample must not support high quota confidence."
  Assert-Match $largeTailOutput " rolloutGrowthObservation=suppressed_partial_coverage rolloutProjected24hMiB=unknown " `
    "Partial rollout coverage must suppress the 24-hour projection."
  Assert-Match $largeTailOutput " rolloutProjectionComparable=false " `
    "A truncated rollout projection must be explicitly incomparable."
  Assert-Match $largeTailOutput " rolloutAgeObservation=partial_head_metadata rolloutAgeFilesystemFallbackFiles=1 rolloutHeadTruncatedFiles=1 rolloutHeadMetadataUnavailableFiles=1 " `
    "A bounded head without session metadata must disclose partial task-age coverage."
  $largeHeadRecord = @{
    timestamp = [DateTimeOffset]::UtcNow.AddDays(-10).ToString('o')
    type = 'session_meta'
    payload = @{ id = 'large-head-session'; multi_agent_version = 2 }
  } | ConvertTo-Json -Compress -Depth 8
  $largeHeadStream = [System.IO.File]::Open(
    $largeSessionPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::Read
  )
  try {
    $largeHeadBytes = [System.Text.Encoding]::UTF8.GetBytes($largeHeadRecord + "`n")
    $largeHeadStream.Write($largeHeadBytes, 0, $largeHeadBytes.Length)
    $largeHeadStream.Flush()
  } finally { $largeHeadStream.Dispose() }
  $largeHeadOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $largeTailHome -SampleSeconds 1
  Assert-Match $largeHeadOutput " rolloutAgeObservation=observed rolloutAgeFilesystemFallbackFiles=0 rolloutHeadTruncatedFiles=1 rolloutHeadMetadataUnavailableFiles=0 " `
    "A large rollout must use its bounded head session timestamp instead of filesystem creation time."

  $v2SessionDay = Join-Path (Join-Path (Join-Path $v2CoverageHome "sessions") `
    (Get-Date -Format "yyyy")) (Get-Date -Format "MM")
  $v2SessionDay = Join-Path $v2SessionDay (Get-Date -Format "dd")
  New-Item -ItemType Directory -Path $v2SessionDay -Force | Out-Null
  $v2SessionPath = Join-Path $v2SessionDay "rollout-v2-fixture.jsonl"
  $v2Records = @(
    @{
      type = "session_meta"
      payload = @{ multi_agent_version = 2 }
    },
    @{
      type = "event_msg"
      payload = @{
        type = "token_count"
        info = @{
          model_context_window = 100000
          total_token_usage = @{
            input_tokens = 10000000
            cached_input_tokens = 8000000
            cache_write_input_tokens = 0
            output_tokens = 1000
            reasoning_output_tokens = 100
            total_tokens = 10001000
          }
          last_token_usage = @{ total_tokens = 1000 }
        }
      }
    }
  ) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 }
  Set-Content -LiteralPath $v2SessionPath -Value $v2Records
  $v2Output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $chronosScript -Action inspect -CodexHome $v2CoverageHome -SampleSeconds 1
  if ($LASTEXITCODE -ne 0) { throw "Chronos Multi-Agent V2 coverage inspection failed." }
  Assert-Match $v2Output " quotaRisk=ELEVATED " `
    "The frozen ten-million-input threshold should remain elevated."
  Assert-Match $v2Output " tokenSpawnCalls=0 " "No unsupported spawn event should be invented."
  Assert-Match $v2Output " tokenCoverageContinuity=complete tokenSpawnObservation=unsupported tokenCompactionObservation=not_observed_in_window " `
    "Numeric zero must distinguish unsupported V2 spawn format from a complete no-compaction observation."
  Assert-Match $v2Output " tokenQuotaContributors=input-10m tokenAdvice=none(\r?\n|$)" `
    "Elevated risk without advice must still explain its contributing threshold."

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
  Assert-Match $scriptText "EnumerateFileSystemEntries" `
    "Session inventory must stream directory entries instead of materializing whole directories."
  Assert-Match $scriptText "inventoryEntryLimit = 20000" `
    "Session inventory must retain a deterministic total-entry bound."
  if ($scriptText -match 'Get-ChildItem\s+-LiteralPath\s+\$directory') {
    throw "Session inventory regressed to eager per-directory materialization."
  }
  Assert-Match $scriptText "function Get-SafeProcessSample" `
    "Process property access must remain isolated from process-exit races."
  Assert-Match $scriptText '(?s)function Get-Candidates.*?foreach \(\$process.*?try \{.*?\$startTime = \$process\.StartTime.*?catch \{\s*continue' `
    "Legacy advisory candidates must also isolate process-exit races."
  Assert-Match $scriptText "ProcessSampleObservation" `
    "Partial process samples must lower reported observation confidence."

  $skillText = Get-Content -LiteralPath $chronosSkill -Raw
  if ($skillText -match "stop starting new work") {
    throw "Chronos skill must not gate new work."
  }
  Assert-Match $skillText "Never use a Chronos status to\s+refuse, suspend, cancel, or stop" `
    "Chronos skill must explicitly prohibit status-based task blocking."
  Assert-Match $skillText "advise a full Windows\s+restart" `
    "Chronos skill must advise a full PC restart for an unusable helper."
  Assert-Match $skillText '(?s)## Complete status request.*?Inspector, supervision\s+status, and Heartbeat status' `
    "Chronos skill must define the complete status starter-prompt behavior."
  Assert-Match $skillText 'status-only request must not create a\s+Governor task, recurrence, worker, Heartbeat event, or task wake' `
    "Complete status must remain observational and wake-free."
  Assert-Match $skillText 'configuration evidence, not proof that the command\s+executed' `
    "Chronos skill must distinguish hook configuration from observed execution."

  Write-Output "Chronos tests passed."
} finally {
  if ($writer -and -not $writer.HasExited) {
    Stop-Process -Id $writer.Id -Force -ErrorAction SilentlyContinue
    $writer.WaitForExit()
  }
  $reparseSessions = Join-Path $reparseHome "sessions"
  if (Test-Path -LiteralPath $reparseSessions) {
    [System.IO.Directory]::Delete($reparseSessions)
  }
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
}
