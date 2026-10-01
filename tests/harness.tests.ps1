param(
  [Parameter(Mandatory = $true)][string]$CodexPath,
  [string]$PluginRoot = '',
  [string]$EvidenceDirectory = '',
  [switch]$CompatibilityOnly,
  [string]$InstalledAccountRoot = '',
  [switch]$RunModelTurn,
  [switch]$VerifySandboxBoundary
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $PluginRoot) { $PluginRoot = Join-Path $repo 'plugins\chronos' }
$PluginRoot = (Resolve-Path -LiteralPath $PluginRoot).ProviderPath
$CodexPath = (Resolve-Path -LiteralPath $CodexPath).ProviderPath
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $repo ('dist\harness-' + [guid]::NewGuid().ToString('N')) }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$fixture = Join-Path $EvidenceDirectory 'marketplace'
$accountRoot = Join-Path $EvidenceDirectory 'codex-home'
$workspace = Join-Path $EvidenceDirectory 'workspace'
$temporary = Join-Path $EvidenceDirectory 'temp'
foreach ($directory in @($fixture, $accountRoot, $workspace, $temporary)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
Copy-Item -LiteralPath $PluginRoot -Destination (Join-Path $fixture 'plugin') -Recurse
if ($CompatibilityOnly -and (Test-Path -LiteralPath (Join-Path $fixture 'plugin\plugin.json'))) { Remove-Item -LiteralPath (Join-Path $fixture 'plugin\plugin.json') }
$catalogDirectory = Join-Path $fixture '.agents\plugins'
New-Item -ItemType Directory -Path $catalogDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\harness-marketplace.json') -Destination (Join-Path $catalogDirectory 'marketplace.json')
$priorAccount = $env:CODEX_HOME
$priorTemp = $env:TEMP
$priorTmp = $env:TMP
$server = $null
$script:requestId = 0
$script:notifications = New-Object 'Collections.Generic.List[object]'
$script:pendingLine = $null
$script:approvedCommands = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$script:allowedCommands = @()

function Handle-ServerRequest {
  param($Message)
  if (-not $Message.PSObject.Properties['id']) { return $false }
  $approved = $Message.method -eq 'item/commandExecution/requestApproval' -and
    $Message.params.threadId -eq $threadId -and $Message.params.cwd -eq $workspace -and
    [string]$Message.params.command -in $script:allowedCommands -and
    (-not $Message.params.kind -or $Message.params.kind -eq 'command') -and
    -not $Message.params.networkApprovalContext
  $server.StandardInput.WriteLine((@{ id = $Message.id; result = @{ decision = if ($approved) { 'accept' } else { 'decline' } } } | ConvertTo-Json -Depth 4 -Compress))
  if (-not $approved) { throw ('harness_unapproved_server_request:' + $Message.method) }
  [void]$script:approvedCommands.Add([string]$Message.params.command)
  return $true
}

function Read-Message {
  param([int]$TimeoutMilliseconds = 30000, [switch]$AllowTimeout)
  if (-not $script:pendingLine) { $script:pendingLine = $server.StandardOutput.ReadLineAsync() }
  if (-not $script:pendingLine.Wait($TimeoutMilliseconds)) {
    if ($AllowTimeout) { return $null }
    throw 'harness_response_timeout'
  }
  $line = $script:pendingLine.Result
  $script:pendingLine = $null
  if ($null -eq $line) { throw 'harness_closed_output' }
  return ($line | ConvertFrom-Json -ErrorAction Stop)
}

function Send-Request {
  param([string]$Method, $Parameters)
  $script:requestId++
  $id = $script:requestId
  $server.StandardInput.WriteLine((@{ id = $id; method = $Method; params = $Parameters } | ConvertTo-Json -Depth 15 -Compress))
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  while ([DateTime]::UtcNow -lt $deadline) {
    $message = Read-Message ([Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds))
    if ($message.PSObject.Properties['id'] -and $message.id -eq $id) {
      if ($message.PSObject.Properties['error']) { throw ('harness_request_failed:{0}:{1}' -f $Method, ($message.error | ConvertTo-Json -Compress)) }
      return $message.result
    }
    if (Handle-ServerRequest $message) { continue }
    $script:notifications.Add($message)
  }
  throw 'harness_response_timeout'
}

try {
  # This disposable same-machine account is not the live Desktop inventory.
  # It contains no credentials, remote services, trust bypasses, or model turns.
  $env:CODEX_HOME = if ($InstalledAccountRoot) { (Resolve-Path -LiteralPath $InstalledAccountRoot).ProviderPath } else { $accountRoot }
  $env:TEMP = $temporary
  $env:TMP = $temporary
  $version = (& $CodexPath --version | Out-String).Trim()
  if (-not $InstalledAccountRoot) {
    $added = & $CodexPath plugin marketplace add $fixture --json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "harness_marketplace_failed:$added" }
    $installed = & $CodexPath plugin add chronos@chronos-harness --json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "harness_install_failed:$installed" }
  }
  if ($RunModelTurn -and -not $InstalledAccountRoot) { throw 'Model smoke test requires an existing account; credentials are never copied into a fixture.' }
  if ($VerifySandboxBoundary -and -not $RunModelTurn) { throw 'Sandbox-boundary verification requires an installed-account model turn.' }
  $pluginId = if ($InstalledAccountRoot) { 'chronos@chronos' } else { 'chronos@chronos-harness' }
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = $CodexPath
  $info.Arguments = '--enable hooks --enable plugins app-server --listen stdio://'
  $info.WorkingDirectory = $workspace
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $server = [Diagnostics.Process]::Start($info)
  $stderrTask = $server.StandardError.ReadToEndAsync()
  $null = Send-Request 'initialize' @{ clientInfo = @{ name = 'chronos-harness-test'; version = '1.0.0' }; capabilities = @{ experimentalApi = $true } }
  $server.StandardInput.WriteLine('{"method":"initialized"}')
  $listing = Send-Request 'hooks/list' @{ cwds = @($workspace) }
  $hooks = @($listing.data[0].hooks | Where-Object { $_.pluginId -eq $pluginId })
  if ($hooks.Count -ne 5 -or $listing.data[0].errors.Count) {
    throw ('harness_plugin_hooks_not_discovered:matched={0}:total={1}:errors={2}' -f $hooks.Count, @($listing.data[0].hooks).Count, ($listing.data[0].errors | ConvertTo-Json -Depth 4 -Compress))
  }
  # Persist review of these exact definitions through Codex's configuration API.
  # Never approve an unrelated hook or use --dangerously-bypass-hook-trust.
  foreach ($hook in $hooks) {
    if (-not $hook.enabled -or $hook.handlerType -ne 'command') { throw 'harness_hook_configuration_invalid' }
    $null = Send-Request 'config/value/write' @{ keyPath = ('hooks.state."{0}".trusted_hash' -f $hook.key); value = $hook.currentHash; mergeStrategy = 'upsert' }
  }
  $listing = Send-Request 'hooks/list' @{ cwds = @($workspace) }
  $hooks = @($listing.data[0].hooks | Where-Object { $_.pluginId -eq $pluginId })
  if (@($hooks | Where-Object { $_.trustStatus -ne 'trusted' }).Count) { throw 'harness_hooks_not_trusted' }
  $started = Send-Request 'thread/start' @{ cwd = $workspace; ephemeral = $false; approvalPolicy = 'on-request'; sandbox = 'workspace-write' }
  $threadId = $started.thread.id
  $loaded = Send-Request 'thread/loaded/list' @{ limit = 100 }
  if ($loaded.data -notcontains $threadId -or $loaded.nextCursor) { throw 'harness_loaded_thread_missing' }
  if ($RunModelTurn) {
    $installedRoots = @($hooks.sourcePath | ForEach-Object { Split-Path -Parent (Split-Path -Parent $_) } | Select-Object -Unique)
    if ($installedRoots.Count -ne 1) { throw 'harness_installation_root_ambiguous' }
    $launcher = Join-Path $installedRoots[0] 'skills\chronos\scripts\chronos.cmd'
    $script:allowedCommands = @("& '$launcher' -Action install-status", "& '$launcher' -Action supervise -SupervisionAction status", "& '$launcher' -Action heartbeat")
    $prompt = "Local Chronos smoke test. Execute these three exact commands separately through exec_command, with sandbox_permissions=require_escalated for each: " + ($script:allowedCommands -join "`n") + "`nThese native diagnostics must run as the desktop Windows user, not the sandbox account, because lifecycle IDs use current-user DPAPI. Only these exact commands are preauthorized. Do not combine commands, add wrappers, create or change recurrences, bootstrap, contact tasks, run Inspector, or modify files. Report the three compact native results and distinguish unsupported coverage from healthy."
    if ($VerifySandboxBoundary) {
      $prompt = "First execute this exact read-only command once through exec_command with sandbox_permissions=use_default (do not escalate): " + $script:allowedCommands[1] + ". This is a negative test: expect supervision_hook_identity_mismatch, not a degraded registry or successful merge. Then perform the three approved host-account diagnostics below. Do not retry the negative test or reset anything.`n" + $prompt
    }
    $null = Send-Request 'turn/start' @{ threadId = $threadId; model = 'gpt-6.1-sol'; effort = 'low'; input = @(@{ type = 'text'; text = $prompt; text_elements = @() }) }
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    while (-not @($script:notifications | Where-Object { $_.method -eq 'turn/completed' }).Count) {
      if ([DateTime]::UtcNow -ge $deadline) { throw 'harness_model_turn_not_completed' }
      $message = Read-Message ([Math]::Min(30000, [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds))) -AllowTimeout
      if ($message -and -not (Handle-ServerRequest $message)) { $script:notifications.Add($message) }
    }
    $turn = @($script:notifications | Where-Object { $_.method -eq 'turn/completed' })[-1].params.turn
    if ($turn.status -ne 'completed') { throw ('harness_model_turn_failed:' + ($turn.error | ConvertTo-Json -Compress)) }
    $nativeOutput = @($script:notifications | Where-Object { $_.method -eq 'item/completed' } | ForEach-Object {
      if ($_.params.item.type -eq 'commandExecution' -and $_.params.item.exitCode -eq 0) { $_.params.item.aggregatedOutput }
      elseif ($_.params.item.type -eq 'functionCallOutput') { $_.params.item.output | ConvertTo-Json -Depth 15 -Compress }
    }) -join "`n"
    foreach ($receipt in @('CHRONOS INSTALL ', 'CHRONOS SUPERVISION ', 'CHRONOS HEARTBEATS ')) {
      if (-not $nativeOutput.Contains($receipt)) {
        $failedCommands = @($script:notifications | Where-Object { $_.method -eq 'item/completed' -and $_.params.item.type -eq 'commandExecution' -and $_.params.item.exitCode -ne 0 } | ForEach-Object { @{ exitCode = $_.params.item.exitCode; output = ([string]$_.params.item.aggregatedOutput).Substring(0, [Math]::Min(1200, ([string]$_.params.item.aggregatedOutput).Length)) } })
        throw ('harness_native_action_not_observed:' + $receipt + ':' + ($failedCommands | ConvertTo-Json -Compress))
      }
    }
    if ($VerifySandboxBoundary) {
      $guardOutput = @($script:notifications | Where-Object { $_.method -eq 'item/completed' } | ForEach-Object {
        if ($_.params.item.type -eq 'commandExecution' -and $_.params.item.exitCode -ne 0) { $_.params.item.aggregatedOutput }
        elseif ($_.params.item.type -eq 'functionCallOutput') { $_.params.item.output | ConvertTo-Json -Depth 15 -Compress }
      }) -join "`n"
      if (-not $guardOutput.Contains('supervision_hook_identity_mismatch')) { throw 'harness_sandbox_identity_guard_not_observed' }
    }
    foreach ($eventName in @('sessionStart', 'stop')) {
      $observed = @($script:notifications | Where-Object { $_.method -eq 'hook/completed' -and $_.params.run.eventName -eq $eventName -and $_.params.run.source -eq 'plugin' -and $_.params.run.sourcePath -in $hooks.sourcePath })
      if ($observed.Count -ne 1 -or $observed[0].params.run.status -ne 'completed' -or $observed[0].params.run.entries.Count) {
        $details = @($observed | ForEach-Object { @{ status = $_.params.run.status; durationMs = $_.params.run.durationMs; entries = $_.params.run.entries } })
        throw ('harness_model_hook_failed:{0}:{1}' -f $eventName, ($details | ConvertTo-Json -Depth 4 -Compress))
      }
    }
  }
  $null = Send-Request 'thread/archive' @{ threadId = $threadId }
  $archived = $true
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while (-not @($script:notifications | Where-Object { $_.method -eq 'hook/completed' -and $_.params.run.eventName -eq 'sessionEnd' }).Count) {
    if ([DateTime]::UtcNow -ge $deadline) { throw 'harness_session_end_not_dispatched' }
    $script:notifications.Add((Read-Message ([Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds))))
  }
  $completed = @($script:notifications | Where-Object { $_.method -eq 'hook/completed' -and $_.params.run.eventName -eq 'sessionEnd' })
  if ($completed.Count -ne 1 -or $completed[0].params.run.status -ne 'completed' -or $completed[0].params.run.entries.Count) { throw ('harness_session_end_failed:' + ($completed | ConvertTo-Json -Depth 8 -Compress)) }
  $inbox = @(Get-ChildItem -LiteralPath $temporary -Directory -Filter 'Chronos-Supervision-Inbox-v1-*')
  $records = @($inbox | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File -Filter 'pending-slot-*.json' } | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json })
  if (@($records | Where-Object { $_.event -eq 'SessionEnd' }).Count -ne 1) { throw 'harness_session_end_not_persisted' }
  if ($RunModelTurn) {
    foreach ($eventName in @('Stop')) {
      if (@($records | Where-Object { $_.event -eq $eventName }).Count -ne 1) { throw ('harness_event_not_persisted:' + $eventName) }
    }
    $registry = @(Get-ChildItem -LiteralPath $temporary -Recurse -File -Filter 'session-registry.json')
    if ($registry.Count -ne 1) { throw 'harness_native_registry_not_observed' }
    $registryState = Get-Content -LiteralPath $registry[0].FullName -Raw | ConvertFrom-Json
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $threadHash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($threadId)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($registryState.health.droppedEntries -ne 0 -or $registryState.health.hookRuns -lt 1 -or -not $registryState.sessions.PSObject.Properties[$threadHash]) { throw 'harness_session_start_not_merged_by_native_account' }
  }
  $hookRuns = @($script:notifications | Where-Object { $_.method -eq 'hook/completed' -and $_.params.run.sourcePath -in $hooks.sourcePath } | ForEach-Object {
    [ordered]@{ event = $_.params.run.eventName; status = $_.params.run.status; durationMs = $_.params.run.durationMs }
  })
  $evidence = [ordered]@{
    runtime = $version; machineScope = 'local'; source = 'installed_plugin'; hookCount = $hooks.Count; trusted = $true
    sessionStart = if ($RunModelTurn) { 'runtime_completed_and_native_registry_observed' } else { 'not_evaluated_without_model_turn' }
    stop = if ($RunModelTurn) { 'runtime_completed_and_inbox_observed' } else { 'not_evaluated' }
    sessionEnd = 'runtime_completed_and_inbox_observed'; hookRuns = $hookRuns
    nativeActions = if ($RunModelTurn) { @('install-status', 'supervise/status', 'heartbeat/status') } else { @() }
    nativeCommandApprovals = $script:approvedCommands.Count
    sandboxIdentityGuard = if ($VerifySandboxBoundary) { 'native_error_and_subsequent_lossless_host_merge' } else { 'not_evaluated' }
    modelTurns = if ($RunModelTurn) { 1 } else { 0 }; desktopInventory = 'not_evaluated'; trustBypass = $false
  }
  $evidence | ConvertTo-Json -Compress
  [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'evidence.json'), ($evidence | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
} catch {
  $diagnostics = @($script:notifications | Where-Object { $_.method -eq 'item/completed' } | ForEach-Object {
    $item = $_.params.item
    if ($item.type -eq 'commandExecution') {
      $output = [string]$item.aggregatedOutput
      @{ type = $item.type; exitCode = $item.exitCode; command = $item.command; output = $output.Substring(0, [Math]::Min(2400, $output.Length)) }
    } elseif ($item.type -eq 'functionCallOutput') {
      $output = [string]($item.output | ConvertTo-Json -Depth 10 -Compress)
      @{ type = $item.type; output = $output.Substring(0, [Math]::Min(2400, $output.Length)) }
    }
  })
  [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'failure.json'), (@{ error = $_.Exception.Message; diagnostics = $diagnostics } | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
  throw
} finally {
  if ($server) {
    if ($threadId -and -not $archived -and -not $server.HasExited) {
      try { $null = Send-Request 'thread/archive' @{ threadId = $threadId } } catch { Write-Warning 'Test thread could not be archived before closing its own runtime.' }
    }
    $server.StandardInput.Close()
    if (-not $server.WaitForExit(5000)) { $server.Kill(); $server.WaitForExit() }
    $server.Dispose()
  }
  $env:CODEX_HOME = $priorAccount
  $env:TEMP = $priorTemp
  $env:TMP = $priorTmp
}
