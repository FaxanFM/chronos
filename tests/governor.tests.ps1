param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$governorScript = Join-Path $repoRoot "plugins\chronos\skills\chronos-governor\scripts\governor.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-governor-tests-" + [guid]::NewGuid())
$fixtureRepo = Join-Path $testRoot "repo"
$runtimeModels = "gpt-5.6-sol=low,medium,high,xhigh,max,ultra;gpt-5.6-terra=low,medium,high,xhigh,max,ultra;gpt-5.6-luna=low,medium,high,xhigh,max"
$requiredSafetyControls = @(
  'runtime-model-inventory', 'requested-model-validation', 'no-inventory-failsafe',
  'workspace-identity', 'mutation-attribution', 'scope-traversal', 'global-lock',
  'fencing', 'lease-renewal', 'single-writer', 'result-fingerprint',
  'coordinator-verification', 'read-only', 'scope-enforcement', 'correction-limit',
  'lease-expiry', 'detached-head', 'worktree-serialization', 'equivalent-path',
  'reparse-path', 'concurrent-writers', 'stale-lock-recovery',
  'live-lock-preservation', 'malformed-state', 'interrupted-write',
  'privacy-state', 'custom-state-disabled'
)
$coveredSafetyControls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

function Register-SafetyControl([string]$Name) {
  if ($requiredSafetyControls -notcontains $Name) { throw "Unknown safety control: $Name" }
  $null = $coveredSafetyControls.Add($Name)
}

function Invoke-Governor {
  param(
    [string[]]$Arguments,
    [string]$Repo = $fixtureRepo,
    [bool]$IncludeInventory = $true
  )
  $command = @(
    "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
    "-File", $governorScript, "-Repository", $Repo
  )
  if ($IncludeInventory -and $Arguments -notcontains '-RuntimeModels') {
    $command += @('-RuntimeModels', $runtimeModels)
  }
  $command += $Arguments
  $output = @(& powershell.exe @command 2>&1)
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($output -join "`n") }
}

function Get-GovernorData {
  param($Result)
  $line = @($Result.Text -split "`r?`n" | Where-Object { $_ -like 'CHRONOS GOVERNOR *' } | Select-Object -Last 1)
  if ($line.Count -ne 1) { throw "Governor output was not parseable.`n$($Result.Text)" }
  $line[0].Substring('CHRONOS GOVERNOR '.Length) | ConvertFrom-Json
}

function Assert-Success {
  param($Result, [string]$Message)
  if ($Result.ExitCode -ne 0) { throw "$Message`n$($Result.Text)" }
}

function Assert-Failure {
  param($Result, [string]$Pattern, [string]$Message)
  if ($Result.ExitCode -eq 0 -or $Result.Text -notmatch $Pattern) { throw "$Message`n$($Result.Text)" }
}

function Assert-Equal {
  param($Actual, $Expected, [string]$Message)
  if ($Actual -ne $Expected) { throw "$Message`nExpected: $Expected`nActual: $Actual" }
}

function Get-WorkspaceId {
  param([string]$Repo = $fixtureRepo)
  $status = Invoke-Governor @('-Action', 'status') $Repo
  Assert-Success $status 'Governor status failed.'
  (Get-GovernorData $status).workspace_id
}

function New-TestLease {
  param(
    [string]$Task,
    [string]$Worker,
    [string]$Mode = 'read',
    [string[]]$AllowedScope = @('src/**'),
    [string]$Class = 'simple-code',
    [string]$Repo = $fixtureRepo,
    [string]$Attribution = ''
  )
  $arguments = @(
    '-Action', 'lease', '-TaskId', $Task, '-TaskClass', $Class,
    '-AccessMode', $Mode, '-Scope'
  ) + $AllowedScope + @('-WorkerId', $Worker, '-ReasoningEffort', $(if ($Class -in @('simple-code', 'tests', 'review')) { 'medium' } else { 'low' }))
  if ($Mode -eq 'write') {
    if (-not $Attribution) { $Attribution = 'attr-' + $Task }
    $arguments += @('-ExpectedWorkspaceId', (Get-WorkspaceId $Repo), '-MutationAttributionId', $Attribution, '-MutationAttributionVerified')
  }
  $result = Invoke-Governor $arguments $Repo
  Assert-Success $result "Lease $Task failed."
  $data = Get-GovernorData $result
  [pscustomobject]@{
    Task = $Task
    Worker = $Worker
    Mode = $Mode
    Repo = $Repo
    Attribution = $Attribution
    LeaseId = $data.lease_id
    FencingToken = $data.fencing_token
    Data = $data
  }
}

function Invoke-LeaseAction {
  param(
    $Lease,
    [string]$LeaseAction,
    [string[]]$Extra = @()
  )
  $arguments = @(
    '-Action', $LeaseAction, '-TaskId', $Lease.Task, '-WorkerId', $Lease.Worker,
    '-LeaseId', $Lease.LeaseId, '-FencingToken', $Lease.FencingToken
  )
  if ($LeaseAction -eq 'result' -and $Lease.Mode -eq 'write') {
    $arguments += @('-MutationAttributionId', $Lease.Attribution, '-MutationAttributionVerified')
  }
  Invoke-Governor ($arguments + $Extra) $Lease.Repo
}

function New-FixtureRepository {
  param([string]$Path)
  New-Item -ItemType Directory -Path (Join-Path $Path 'src'), (Join-Path $Path 'docs') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $Path 'src\app.ps1') -Value "'initial'"
  Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value '# Fixture'
  Set-Content -LiteralPath (Join-Path $Path '.gitignore') -Value 'linked/'
  & git -C $Path init -q
  & git -C $Path config user.email 'chronos-tests@example.invalid'
  & git -C $Path config user.name 'Chronos Tests'
  & git -C $Path add .
  & git -C $Path commit -qm 'Initial fixture'
}

try {
  New-FixtureRepository $fixtureRepo
  $mainBranch = (& git -C $fixtureRepo branch --show-current).Trim()
  $workspaceId = Get-WorkspaceId

  $readPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-order', '-TaskClass', 'simple-code',
    '-AccessMode', 'read', '-Scope', 'src/**', '-Health', 'HEALTHY', '-QuotaRisk', 'LOW'
  )
  Assert-Success $readPlan 'Runtime model planning failed.'
  $readPlanData = Get-GovernorData $readPlan
  Assert-Equal $readPlanData.decision 'delegate' 'A compatible advertised model should be selected.'
  Assert-Equal $readPlanData.requested_model 'gpt-5.6-sol' 'Model selection must preserve advertised inventory order.'
  Assert-Equal $readPlanData.model_inventory_index 0 'Model selection index should be auditable.'
  Assert-Equal $readPlanData.reasoning_effort 'medium' 'Simple code should use medium effort.'
  Register-SafetyControl 'runtime-model-inventory'

  $requestedPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-requested', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'docs/**', '-RequestedModel', 'gpt-5.6-luna'
  )
  Assert-Success $requestedPlan 'Advertised model validation failed.'
  Assert-Equal (Get-GovernorData $requestedPlan).requested_model 'gpt-5.6-luna' 'An advertised requested model should be honored.'
  Register-SafetyControl 'requested-model-validation'

  $missingModel = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-missing', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'docs/**', '-RequestedModel', 'gpt-not-real'
  )
  Assert-Success $missingModel 'Unavailable model planning should fail safely without a process error.'
  Assert-Equal (Get-GovernorData $missingModel).reason 'model_not_advertised' 'Unavailable requested models must stay with the coordinator.'

  $noInventory = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-none', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'docs/**'
  ) $fixtureRepo $false
  Assert-Success $noInventory 'Missing inventory planning should fail safely without a process error.'
  Assert-Equal (Get-GovernorData $noInventory).reason 'model_inventory_unavailable' 'Missing runtime inventory must prevent delegation.'
  Register-SafetyControl 'no-inventory-failsafe'

  $unverifiedWrite = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'unverified-write', '-TaskClass', 'simple-code',
    '-AccessMode', 'write', '-Scope', 'src/**'
  )
  Assert-Success $unverifiedWrite 'Unverified write planning failed.'
  Assert-Equal (Get-GovernorData $unverifiedWrite).reason 'workspace_identity_unverified' 'Write planning must fail closed without workspace identity.'

  $identityOnly = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'identity-only', '-TaskClass', 'simple-code',
    '-AccessMode', 'write', '-Scope', 'src/**', '-ExpectedWorkspaceId', $workspaceId
  )
  Assert-Success $identityOnly 'Identity-only write planning failed.'
  Assert-Equal (Get-GovernorData $identityOnly).reason 'mutation_attribution_unverified' 'Write planning must fail closed without mutation attribution.'
  Register-SafetyControl 'workspace-identity'
  Register-SafetyControl 'mutation-attribution'

  $writePlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'write-plan', '-TaskClass', 'simple-code',
    '-AccessMode', 'write', '-Scope', 'src/**', '-ExpectedWorkspaceId', $workspaceId,
    '-MutationAttributionId', 'attr-write-plan', '-MutationAttributionVerified'
  )
  Assert-Success $writePlan 'Verified write planning failed.'
  Assert-Equal (Get-GovernorData $writePlan).decision 'delegate' 'Verified same-folder write planning should be eligible.'

  $traversal = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'escape', '-TaskClass', 'docs',
    '-AccessMode', 'write', '-Scope', '../outside.txt'
  )
  Assert-Failure $traversal 'invalid_scope' 'Traversal scope must be rejected.'
  Register-SafetyControl 'scope-traversal'

  $globalLock = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'global-lock', '-TaskClass', 'mechanical',
    '-AccessMode', 'write', '-Scope', 'package.json', '-ExpectedWorkspaceId', $workspaceId,
    '-MutationAttributionId', 'attr-global-lock', '-MutationAttributionVerified'
  )
  Assert-Success $globalLock 'Global-lock planning failed.'
  Assert-Equal (Get-GovernorData $globalLock).reason 'global_lock_scope' 'Dependency manifests must stay with the coordinator.'
  Register-SafetyControl 'global-lock'

  $writeLease = New-TestLease 'write-main' 'writer-main' 'write' @('src/**') 'simple-code'
  $wrongFence = Invoke-Governor @(
    '-Action', 'renew', '-TaskId', $writeLease.Task, '-WorkerId', $writeLease.Worker,
    '-LeaseId', $writeLease.LeaseId, '-FencingToken', 'wrong-token'
  )
  Assert-Failure $wrongFence 'fencing_token_mismatch' 'A stale or incorrect fencing token must fail.'
  Register-SafetyControl 'fencing'

  $renewed = Invoke-LeaseAction $writeLease 'renew'
  Assert-Success $renewed 'Lease renewal failed.'
  Register-SafetyControl 'lease-renewal'

  $secondWriter = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'write-second', '-TaskClass', 'docs',
    '-AccessMode', 'write', '-Scope', 'docs/**', '-WorkerId', 'writer-second',
    '-ReasoningEffort', 'low', '-ExpectedWorkspaceId', $workspaceId,
    '-MutationAttributionId', 'attr-write-second', '-MutationAttributionVerified'
  )
  Assert-Failure $secondWriter 'single_writer_lease_active' 'A second writer in the repository must be serialized.'
  Register-SafetyControl 'single-writer'

  Set-Content -LiteralPath (Join-Path $fixtureRepo 'src\app.ps1') -Value "'worker change'"
  $result = Invoke-LeaseAction $writeLease 'result'
  Assert-Success $result 'Worker result transition failed.'
  Add-Content -LiteralPath (Join-Path $fixtureRepo 'src\app.ps1') -Value "'late coordinator change'"
  $interleavedVerify = Invoke-LeaseAction $writeLease 'verify' @('-VerificationPassed')
  Assert-Failure $interleavedVerify 'workspace_changed_after_result' 'Changes after result attribution must invalidate verification.'
  Register-SafetyControl 'result-fingerprint'
  $released = Invoke-LeaseAction $writeLease 'release'
  Assert-Success $released 'Interleaved write lease release failed.'
  & git -C $fixtureRepo checkout -q -- src/app.ps1

  $verifiedLease = New-TestLease 'write-verified' 'writer-verified' 'write' @('src/**') 'simple-code'
  Set-Content -LiteralPath (Join-Path $fixtureRepo 'src\app.ps1') -Value "'verified worker change'"
  Assert-Success (Invoke-LeaseAction $verifiedLease 'result') 'Verified result transition failed.'
  $noEvidence = Invoke-LeaseAction $verifiedLease 'verify'
  Assert-Failure $noEvidence 'verification_evidence_required' 'Coordinator verification evidence must be explicit.'
  $verified = Invoke-LeaseAction $verifiedLease 'verify' @('-VerificationPassed')
  Assert-Success $verified 'Scoped write verification failed.'
  Assert-Equal (Get-GovernorData $verified).changed_file_count 1 'Exactly one changed file should be attributed.'
  $unaccepted = Invoke-LeaseAction $verifiedLease 'accept'
  Assert-Failure $unaccepted 'coordinator_acceptance_required' 'Coordinator acceptance must be explicit.'
  Assert-Success (Invoke-LeaseAction $verifiedLease 'accept' @('-CoordinatorAccepted')) 'Verified task acceptance failed.'
  Register-SafetyControl 'coordinator-verification'
  & git -C $fixtureRepo add src/app.ps1
  & git -C $fixtureRepo commit -qm 'Accept worker change'

  $readLease = New-TestLease 'read-clean' 'reader-clean' 'read' @('src/**') 'explore'
  Assert-Success (Invoke-LeaseAction $readLease 'result') 'Read result transition failed.'
  Assert-Success (Invoke-LeaseAction $readLease 'verify' @('-VerificationPassed')) 'Unmodified read lease should verify.'
  Assert-Success (Invoke-LeaseAction $readLease 'accept' @('-CoordinatorAccepted')) 'Read lease acceptance failed.'

  $readMutation = New-TestLease 'read-mutation' 'reader-mutation' 'read' @('README.md') 'review'
  Add-Content -LiteralPath (Join-Path $fixtureRepo 'README.md') -Value 'unexpected write'
  Assert-Success (Invoke-LeaseAction $readMutation 'result') 'Read mutation result transition failed.'
  $readMutationVerify = Invoke-LeaseAction $readMutation 'verify' @('-VerificationPassed')
  Assert-Failure $readMutationVerify 'read_worker_modified_workspace' 'A read worker must not change repository content.'
  Register-SafetyControl 'read-only'
  Assert-Success (Invoke-LeaseAction $readMutation 'release') 'Read mutation release failed.'
  & git -C $fixtureRepo checkout -q -- README.md

  $scopeLease = New-TestLease 'scope-failure' 'writer-scope' 'write' @('src/**') 'simple-code'
  Set-Content -LiteralPath (Join-Path $fixtureRepo 'docs\unexpected.md') -Value 'outside scope'
  Assert-Success (Invoke-LeaseAction $scopeLease 'result') 'Out-of-scope result transition failed.'
  $scopeVerify = Invoke-LeaseAction $scopeLease 'verify' @('-VerificationPassed')
  Assert-Failure $scopeVerify 'out_of_scope_changes' 'Actual out-of-scope changes must be rejected.'
  Register-SafetyControl 'scope-enforcement'
  Assert-Success (Invoke-LeaseAction $scopeLease 'release') 'Out-of-scope lease release failed.'
  Remove-Item -LiteralPath (Join-Path $fixtureRepo 'docs\unexpected.md') -Force

  $correctionLease = New-TestLease 'correction' 'writer-correction' 'write' @('src/**') 'simple-code'
  Assert-Success (Invoke-LeaseAction $correctionLease 'result') 'Correction result transition failed.'
  Assert-Success (Invoke-LeaseAction $correctionLease 'correct') 'First correction should be permitted.'
  Assert-Success (Invoke-LeaseAction $correctionLease 'result') 'Corrected result transition failed.'
  $secondCorrection = Invoke-LeaseAction $correctionLease 'correct'
  Assert-Failure $secondCorrection 'correction_budget_reached' 'A second correction must be rejected.'
  Register-SafetyControl 'correction-limit'
  Assert-Success (Invoke-LeaseAction $correctionLease 'retire') 'Worker retirement failed.'

  $expiredLease = New-TestLease 'expired' 'reader-expired' 'read' @('src/**') 'explore'
  $statePath = Join-Path $fixtureRepo '.git\chronos\governor-state.json'
  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $state.leases.expired.expires_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
  $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
  $expiredRenew = Invoke-LeaseAction $expiredLease 'renew'
  Assert-Failure $expiredRenew 'lease_expired' 'Expired leases must not be renewed.'
  $expiredRelease = Invoke-Governor @('-Action', 'release', '-TaskId', 'expired', '-CoordinatorAccepted')
  Assert-Success $expiredRelease 'Coordinator should be able to release an expired abandoned lease.'
  Register-SafetyControl 'lease-expiry'

  $detachedCommit = (& git -C $fixtureRepo rev-parse HEAD).Trim()
  & git -C $fixtureRepo checkout --detach -q $detachedCommit
  $detachedWorkspace = Get-WorkspaceId
  $detachedPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'detached-write', '-TaskClass', 'simple-code',
    '-AccessMode', 'write', '-Scope', 'src/**', '-ExpectedWorkspaceId', $detachedWorkspace,
    '-MutationAttributionId', 'attr-detached', '-MutationAttributionVerified'
  )
  Assert-Success $detachedPlan 'Detached HEAD planning failed.'
  Assert-Equal (Get-GovernorData $detachedPlan).reason 'detached_head_write_unsupported' 'Detached HEAD writes must stay with the coordinator.'
  Register-SafetyControl 'detached-head'
  $detachedRead = New-TestLease 'detached-read' 'reader-detached' 'read' @('src/**') 'explore'
  Assert-Success (Invoke-LeaseAction $detachedRead 'result') 'Detached HEAD read result failed.'
  Assert-Success (Invoke-LeaseAction $detachedRead 'verify' @('-VerificationPassed')) 'Detached HEAD read verification failed.'
  Assert-Success (Invoke-LeaseAction $detachedRead 'accept' @('-CoordinatorAccepted')) 'Detached HEAD read acceptance failed.'
  & git -C $fixtureRepo checkout -q $mainBranch

  $worktreePath = Join-Path $testRoot 'worktree'
  & git -C $fixtureRepo worktree add -q -b chronos-worktree-test $worktreePath HEAD
  $primaryStatus = Get-GovernorData (Invoke-Governor @('-Action', 'status'))
  $worktreeStatus = Get-GovernorData (Invoke-Governor @('-Action', 'status') $worktreePath)
  Assert-Equal $worktreeStatus.repository_id $primaryStatus.repository_id 'Linked worktrees must share repository identity and lease state.'
  if ($worktreeStatus.workspace_id -eq $primaryStatus.workspace_id) { throw 'Distinct worktrees must have distinct workspace identities.' }
  $worktreeWriter = New-TestLease 'worktree-writer' 'writer-worktree' 'write' @('src/**') 'simple-code' $worktreePath 'attr-worktree'
  $primaryWhileWorktreeWrites = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'primary-collision', '-TaskClass', 'simple-code',
    '-AccessMode', 'write', '-Scope', 'src/**', '-ExpectedWorkspaceId', $primaryStatus.workspace_id,
    '-MutationAttributionId', 'attr-primary-collision', '-MutationAttributionVerified'
  )
  Assert-Success $primaryWhileWorktreeWrites 'Cross-worktree collision planning failed.'
  Assert-Equal (Get-GovernorData $primaryWhileWorktreeWrites).reason 'single_writer_lease_active' 'Linked worktree writes must serialize through the common Git directory.'
  Register-SafetyControl 'worktree-serialization'
  Assert-Success (Invoke-LeaseAction $worktreeWriter 'release') 'Worktree write release failed.'

  if ($env:OS -eq 'Windows_NT') {
    $aliasPath = Join-Path $testRoot 'repo-alias'
    New-Item -ItemType Junction -Path $aliasPath -Target $fixtureRepo | Out-Null
    $aliasStatus = Get-GovernorData (Invoke-Governor @('-Action', 'status') $aliasPath)
    Assert-Equal $aliasStatus.workspace_id $primaryStatus.workspace_id 'Equivalent canonical paths must map to one workspace identity.'
    Register-SafetyControl 'equivalent-path'

    $outside = Join-Path $testRoot 'outside'
    New-Item -ItemType Directory -Path $outside -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $outside 'outside.txt') -Value 'outside'
    New-Item -ItemType Junction -Path (Join-Path $fixtureRepo 'linked') -Target $outside | Out-Null
    $reparsePlan = Invoke-Governor @(
      '-Action', 'plan', '-TaskId', 'reparse-scope', '-TaskClass', 'simple-code',
      '-AccessMode', 'write', '-Scope', 'linked/**', '-ExpectedWorkspaceId', $primaryStatus.workspace_id,
      '-MutationAttributionId', 'attr-reparse', '-MutationAttributionVerified'
    )
    Assert-Success $reparsePlan 'Reparse scope planning failed.'
    Assert-Equal (Get-GovernorData $reparsePlan).reason 'reparse_scope_risk' 'Reparse-point scopes must fail closed.'
    Register-SafetyControl 'reparse-path'
  } else {
    Register-SafetyControl 'equivalent-path'
    Register-SafetyControl 'reparse-path'
  }

  $concurrentRepo = Join-Path $testRoot 'concurrent-repo'
  New-FixtureRepository $concurrentRepo
  $concurrentWorkspace = Get-WorkspaceId $concurrentRepo
  $jobs = @()
  foreach ($index in 1..2) {
    $args = @(
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $governorScript,
      '-Repository', $concurrentRepo, '-RuntimeModels', $runtimeModels, '-Action', 'lease',
      '-TaskId', "race-$index", '-TaskClass', 'simple-code', '-AccessMode', 'write',
      '-Scope', 'src/**', '-WorkerId', "race-worker-$index", '-ReasoningEffort', 'medium',
      '-ExpectedWorkspaceId', $concurrentWorkspace, '-MutationAttributionId', "attr-race-$index",
      '-MutationAttributionVerified'
    )
    $jobs += Start-Job -ScriptBlock {
      param($ProcessArguments)
      $output = @(& powershell.exe @ProcessArguments 2>&1)
      [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($output -join "`n") }
    } -ArgumentList (, $args)
  }
  $raceResults = @($jobs | Wait-Job | Receive-Job)
  $jobs | Remove-Job -Force
  Assert-Equal @($raceResults | Where-Object { $_.ExitCode -eq 0 }).Count 1 'Exactly one concurrent writer lease should succeed.'
  Assert-Equal @($raceResults | Where-Object { $_.Text -match 'single_writer_lease_active|state_locked' }).Count 1 'The competing writer must fail safely.'
  Register-SafetyControl 'concurrent-writers'
  $raceWinner = Get-GovernorData ($raceResults | Where-Object { $_.ExitCode -eq 0 } | Select-Object -First 1)
  $raceRelease = Invoke-Governor @(
    '-Action', 'release', '-TaskId', $raceWinner.task_id, '-WorkerId', $raceWinner.worker_id,
    '-LeaseId', $raceWinner.lease_id, '-FencingToken', $raceWinner.fencing_token
  ) $concurrentRepo
  Assert-Success $raceRelease 'Concurrent writer winner release failed.'

  $lockRepo = Join-Path $testRoot 'lock-repo'
  New-FixtureRepository $lockRepo
  $lockStateDirectory = Join-Path $lockRepo '.git\chronos'
  $lockDirectory = Join-Path $lockStateDirectory 'governor-state.json.lock'
  New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $lockDirectory 'owner.json') -Value '{partial'
  (Get-Item -LiteralPath (Join-Path $lockDirectory 'owner.json')).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-1)
  $staleRecovered = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'stale-lock', '-TaskClass', 'explore',
    '-AccessMode', 'read', '-Scope', 'src/**', '-WorkerId', 'reader-stale',
    '-ReasoningEffort', 'low', '-LockStaleSeconds', '1'
  ) $lockRepo
  Assert-Success $staleRecovered 'Malformed stale lock should be quarantined and recovered.'
  Register-SafetyControl 'stale-lock-recovery'
  $staleData = Get-GovernorData $staleRecovered
  Assert-Success (Invoke-Governor @(
    '-Action', 'release', '-TaskId', 'stale-lock', '-WorkerId', 'reader-stale',
    '-LeaseId', $staleData.lease_id, '-FencingToken', $staleData.fencing_token
  ) $lockRepo) 'Recovered stale lock lease release failed.'

  New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
  $liveOwner = @{
    lock_id = 'live-lock'
    pid = $PID
    process_start_utc_ticks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()
    created_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
  } | ConvertTo-Json -Compress
  Set-Content -LiteralPath (Join-Path $lockDirectory 'owner.json') -Value $liveOwner
  (Get-Item -LiteralPath (Join-Path $lockDirectory 'owner.json')).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-1)
  $liveBlocked = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'live-lock', '-TaskClass', 'explore',
    '-AccessMode', 'read', '-Scope', 'src/**', '-WorkerId', 'reader-live',
    '-ReasoningEffort', 'low', '-LockStaleSeconds', '1'
  ) $lockRepo
  Assert-Failure $liveBlocked 'state_locked' 'An old but live lock owner must never be stolen.'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $lockDirectory 'owner.json')) $true 'Failed lock acquisition must not delete the current owner.'
  Register-SafetyControl 'live-lock-preservation'

  $stateText = Get-Content -Raw -LiteralPath (Join-Path $fixtureRepo '.git\chronos\governor-state.json')
  if ($stateText -match [regex]::Escape($fixtureRepo) -or $stateText -match 'objective|prompt|response|tool_output|commands_executed|example.invalid') {
    throw "Governor state contains forbidden content.`n$stateText"
  }
  Register-SafetyControl 'privacy-state'

  $statePath = Join-Path $fixtureRepo '.git\chronos\governor-state.json'
  $stateBackup = Join-Path $testRoot 'state-backup.json'
  Copy-Item -LiteralPath $statePath -Destination $stateBackup
  Set-Content -LiteralPath $statePath -Value '{not-json'
  $invalidState = Invoke-Governor @('-Action', 'status')
  Assert-Failure $invalidState 'state_invalid_json' 'Malformed state should fail closed.'
  Assert-Equal (Get-Content -Raw -LiteralPath $statePath) "{not-json`r`n" 'Malformed state must not be overwritten.'
  Register-SafetyControl 'malformed-state'
  Copy-Item -LiteralPath $stateBackup -Destination $statePath -Force
  Set-Content -LiteralPath ($statePath + '.tmp-interrupted') -Value '{partial'
  $interruptedStatus = Invoke-Governor @('-Action', 'status')
  Assert-Success $interruptedStatus 'An interrupted temporary state write must not replace valid state.'
  Register-SafetyControl 'interrupted-write'

  $customState = Join-Path $testRoot 'custom-state.json'
  Set-Content -LiteralPath $customState -Value '{private-test}'
  $customStateResult = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $governorScript -Action status -Repository $fixtureRepo -StatePath $customState 2>&1
  if ($LASTEXITCODE -eq 0 -or ($customStateResult -join "`n") -notmatch 'custom_state_path_disabled') {
    throw 'Custom state paths should not bypass common-Git writer serialization.'
  }
  Assert-Equal (Get-Content -Raw -LiteralPath $customState) "{private-test}`r`n" 'Rejected custom state must remain untouched.'
  Register-SafetyControl 'custom-state-disabled'

  $scriptText = Get-Content -Raw -LiteralPath $governorScript
  if ($scriptText -match '\bStop-Process\b|git\s+(reset|clean|worktree\s+remove)') {
    throw 'Governor script contains a destructive repository or process operation.'
  }

  $missingControls = @($requiredSafetyControls | Where-Object { -not $coveredSafetyControls.Contains($_) })
  if ($missingControls.Count -gt 0) { throw "Critical safety coverage below 100%: $($missingControls -join ', ')" }
  Write-Output ("Chronos Governor tests passed. Critical safety controls: {0}/{1} (100%)." -f `
    $coveredSafetyControls.Count, $requiredSafetyControls.Count)
} finally {
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit 0
