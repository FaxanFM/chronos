param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$governorScript = Join-Path $repoRoot "plugins\chronos\skills\chronos-governor\scripts\governor.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-governor-tests-" + [guid]::NewGuid())
$fixtureRepo = Join-Path $testRoot "repo"
$runtimeModels = "gpt-5.6-sol=low,medium,high,xhigh,max,ultra|cost=20;gpt-5.6-terra=low,medium,high,xhigh,max,ultra|cost=10;gpt-5.6-luna=low,medium,high,xhigh,max|cost=1"
$validatedScenarios = 0
$stateDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Register-SafetyControl([string]$Name) {
  $script:validatedScenarios++
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
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = @(& powershell.exe @command 2>&1)
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  [pscustomobject]@{ ExitCode = $exitCode; Text = ($output -join "`n") }
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

function Get-StatePath {
  param([string]$Repo = $fixtureRepo)
  $status = Invoke-Governor @('-Action', 'status') $Repo
  Assert-Success $status 'Governor status failed while resolving state identity.'
  $repositoryId = (Get-GovernorData $status).repository_id
  $directory = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'Chronos\Governor') $repositoryId
  $null = $stateDirectories.Add([System.IO.Path]::GetFullPath($directory))
  Join-Path $directory 'governor-state.json'
}

function New-TestPlan {
  param(
    [string]$Task,
    [string]$Mode = 'read',
    [string[]]$AllowedScope = @('src/**'),
    [string]$Class = 'simple-code',
    [string]$Repo = $fixtureRepo,
    [string]$Attribution = '',
    [string[]]$Extra = @()
  )
  $arguments = @(
    '-Action', 'plan', '-TaskId', $Task, '-TaskClass', $Class,
    '-AccessMode', $Mode, '-Scope'
  ) + $AllowedScope
  if ($Mode -eq 'write') {
    if (-not $Attribution) { $Attribution = 'attr-' + $Task }
    $arguments += @('-ExpectedWorkspaceId', (Get-WorkspaceId $Repo), '-MutationAttributionId', $Attribution, '-MutationAttributionVerified')
  }
  Invoke-Governor ($arguments + $Extra) $Repo
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
  if ($Mode -eq 'write' -and -not $Attribution) { $Attribution = 'attr-' + $Task }
  $planResult = New-TestPlan $Task $Mode $AllowedScope $Class $Repo $Attribution
  Assert-Success $planResult "Plan $Task failed."
  $plan = Get-GovernorData $planResult
  Assert-Equal $plan.decision 'delegate' "Plan $Task did not authorize delegation."
  if (-not $plan.plan_token) { throw "Plan $Task did not return an opaque token." }
  $arguments = @('-Action', 'lease', '-TaskId', $Task, '-WorkerId', $Worker, '-PlanToken', $plan.plan_token)
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

function Close-TestReadPlan {
  param([string]$Task, $PlanResult, [string]$Repo = $fixtureRepo)
  $plan = Get-GovernorData $PlanResult
  if ($plan.decision -ne 'delegate') { return }
  $worker = "/root/close-$Task"
  $leaseResult = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', $Task, '-WorkerId', $worker,
    '-PlanToken', $plan.plan_token
  ) $Repo
  Assert-Success $leaseResult "Could not consume test plan $Task."
  $lease = Get-GovernorData $leaseResult
  Assert-Success (Invoke-Governor @(
    '-Action', 'release', '-TaskId', $Task, '-WorkerId', $worker,
    '-LeaseId', $lease.lease_id, '-FencingToken', $lease.fencing_token
  ) $Repo) "Could not release test plan $Task."
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
  $fixtureStatePath = Get-StatePath
  $versionStatus = Get-GovernorData (Invoke-Governor @('-Action', 'status'))
  Assert-Equal $versionStatus.plugin_version '0.9.2' 'Governor must report the active packaged plugin version.'
  $gitCommonDirectory = [System.IO.Path]::GetFullPath((& git -C $fixtureRepo rev-parse --path-format=absolute --git-common-dir).Trim())
  if ($fixtureStatePath.StartsWith($gitCommonDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Governor runtime state must not be stored beneath Git metadata.'
  }
  Register-SafetyControl 'state-store-outside-git'

  $blockedLegacyPath = Join-Path $fixtureRepo '.git\chronos'
  Set-Content -LiteralPath $blockedLegacyPath -Value 'Git metadata intentionally unavailable for Governor writes.'
  $metadataReadOnlyLease = New-TestLease 'metadata-readonly' '/root/metadata-reader' 'read' @('README.md') 'review'
  Assert-Success (Invoke-LeaseAction $metadataReadOnlyLease 'release') 'Governor should work when its former Git-metadata path is unwritable.'
  Remove-Item -LiteralPath $blockedLegacyPath -Force
  Register-SafetyControl 'git-metadata-readonly'
  Register-SafetyControl 'canonical-worker-id'
  Register-SafetyControl 'plan-token'

  $cancelPlanResult = New-TestPlan 'cancel-before-lease' 'read' @('README.md') 'review'
  Assert-Success $cancelPlanResult 'Cancelable plan creation failed.'
  $cancelPlan = Get-GovernorData $cancelPlanResult
  $statusWithPlan = Get-GovernorData (Invoke-Governor @('-Action', 'status'))
  Assert-Equal $statusWithPlan.pending_plans 1 'An unexpired issued plan must reserve pending capacity.'
  $cancelResult = Invoke-Governor @(
    '-Action', 'cancel-plan', '-TaskId', 'cancel-before-lease', '-PlanToken', $cancelPlan.plan_token
  )
  Assert-Success $cancelResult 'Token-authenticated plan cancellation failed.'
  $cancelData = Get-GovernorData $cancelResult
  Assert-Equal $cancelData.status 'canceled' 'Canceled plan must enter a terminal canceled state.'
  Assert-Equal $cancelData.capacity_released $true 'Canceled plan must explicitly release pending capacity.'
  Assert-Equal (Get-GovernorData (Invoke-Governor @('-Action', 'status'))).pending_plans 0 `
    'Canceled plans must not remain pending.'
  Assert-Failure (Invoke-Governor @(
      '-Action', 'lease', '-TaskId', 'cancel-before-lease', '-WorkerId', '/root/canceled-plan',
      '-PlanToken', $cancelPlan.plan_token
    )) 'plan_already_consumed' 'A canceled plan token must never authorize a lease.'
  Register-SafetyControl 'cancel-plan-terminal'

  $preLeaseMutationPlanResult = New-TestPlan 'pre-lease-mutation' 'read' @('src/**') 'review'
  Assert-Success $preLeaseMutationPlanResult 'Pre-lease mutation plan creation failed.'
  $preLeaseMutationPlan = Get-GovernorData $preLeaseMutationPlanResult
  Add-Content -LiteralPath (Join-Path $fixtureRepo 'src\app.ps1') -Value "'changed before lease'"
  Assert-Failure (Invoke-Governor @(
      '-Action', 'lease', '-TaskId', 'pre-lease-mutation', '-WorkerId', '/root/pre-lease-mutator',
      '-PlanToken', $preLeaseMutationPlan.plan_token
    )) 'workspace_changed_since_plan' `
    'A Git-visible mutation between plan and lease must invalidate the plan baseline.'
  Assert-Success (Invoke-Governor @(
      '-Action', 'cancel-plan', '-TaskId', 'pre-lease-mutation', '-PlanToken', $preLeaseMutationPlan.plan_token
    )) 'The invalidated pre-lease plan must remain cancelable.'
  & git -C $fixtureRepo restore -- src/app.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Could not restore the pre-lease mutation fixture.' }
  Register-SafetyControl 'plan-to-lease-workspace-baseline'

  $expiredPlanResult = New-TestPlan 'expired-before-lease' 'read' @('README.md') 'review'
  Assert-Success $expiredPlanResult 'Expiring plan creation failed.'
  $expiredPlan = Get-GovernorData $expiredPlanResult
  $expiredState = Get-Content -Raw -LiteralPath $fixtureStatePath | ConvertFrom-Json
  $expiredState.plans.'expired-before-lease'.expires_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
  [System.IO.File]::WriteAllText(
    $fixtureStatePath,
    ($expiredState | ConvertTo-Json -Compress -Depth 20),
    [System.Text.UTF8Encoding]::new($false)
  )
  $expiredStatus = Get-GovernorData (Invoke-Governor @('-Action', 'status'))
  Assert-Equal $expiredStatus.pending_plans 0 'Expired plans must not reserve pending capacity.'
  Assert-Equal $expiredStatus.expired_plans 1 'Status must report expired issued plans separately.'
  Assert-Success (Invoke-Governor @(
      '-Action', 'cancel-plan', '-TaskId', 'expired-before-lease', '-PlanToken', $expiredPlan.plan_token
    )) 'An expired plan must remain explicitly cancelable with its opaque token.'
  Register-SafetyControl 'expired-plan-accounting'

  $filterRepo = Join-Path $testRoot 'filter-repo'
  New-FixtureRepository $filterRepo
  $filterProbe = Join-Path $filterRepo 'src\probe.filterprobe'
  $filterScript = Join-Path $testRoot 'filter-driver.ps1'
  $filterMarker = Join-Path $testRoot 'filter-executed.marker'
  Set-Content -LiteralPath $filterProbe -Value 'initial filter probe'
  & git -C $filterRepo add src/probe.filterprobe
  & git -C $filterRepo commit -qm 'Add filter probe'
  Set-Content -LiteralPath (Join-Path $filterRepo '.gitattributes') -Value '*.filterprobe filter=chronos-audit'
  @'
param([string]$Marker)
$input | ForEach-Object { $_ }
[System.IO.File]::WriteAllText($Marker, 'executed')
'@ | Set-Content -LiteralPath $filterScript
  $filterScriptForGit = $filterScript.Replace('\', '/')
  $filterMarkerForGit = $filterMarker.Replace('\', '/')
  $filterCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + $filterScriptForGit + ' -Marker ' + $filterMarkerForGit
  & git -C $filterRepo config filter.chronos-audit.clean $filterCommand
  & git -C $filterRepo hash-object --path=src/probe.filterprobe --filters src/probe.filterprobe | Out-Null
  if (-not (Test-Path -LiteralPath $filterMarker -PathType Leaf)) {
    throw 'Clean-filter fixture did not execute during its positive control.'
  }
  Remove-Item -LiteralPath $filterMarker -Force
  Add-Content -LiteralPath $filterProbe -Value 'working tree change'
  $filterLease = New-TestLease 'clean-filter-safe' '/root/filter-reader' 'read' @('src/probe.filterprobe') 'review' $filterRepo
  if (Test-Path -LiteralPath $filterMarker) {
    throw 'Governor fingerprinting executed a configured Git clean filter.'
  }
  Assert-Success (Invoke-LeaseAction $filterLease 'release') 'Clean-filter probe lease release failed.'
  Register-SafetyControl 'git-clean-filter-not-executed'

  $flattenedPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'flattened-scopes', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'README.md,docs/**'
  )
  Assert-Success $flattenedPlan 'Flattened scope planning failed.'
  $flattenedPlanData = Get-GovernorData $flattenedPlan
  Assert-Equal @($flattenedPlanData.scopes).Count 2 'Comma-flattened scopes must normalize to two entries.'
  $flattenedLease = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'flattened-scopes', '-WorkerId', '/root/flattened',
    '-PlanToken', $flattenedPlanData.plan_token
  )
  Assert-Success $flattenedLease 'Flattened scope plan token should lease without reparsing scopes.'
  $flattenedLeaseData = Get-GovernorData $flattenedLease
  Assert-Success (Invoke-Governor @(
    '-Action', 'release', '-TaskId', 'flattened-scopes', '-WorkerId', '/root/flattened',
    '-LeaseId', $flattenedLeaseData.lease_id, '-FencingToken', $flattenedLeaseData.fencing_token
  )) 'Flattened scope lease release failed.'
  Register-SafetyControl 'flattened-scopes'

  $readPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-order', '-TaskClass', 'simple-code',
    '-AccessMode', 'read', '-Scope', 'src/**', '-Health', 'HEALTHY', '-QuotaRisk', 'LOW'
  )
  Assert-Success $readPlan 'Runtime model planning failed.'
  $readPlanData = Get-GovernorData $readPlan
  Assert-Equal $readPlanData.decision 'delegate' 'A compatible advertised model should be selected.'
  Assert-Equal $readPlanData.requested_model 'gpt-5.6-luna' 'Verified runtime cost rank should select the lightest compatible model.'
  Assert-Equal $readPlanData.model_inventory_index 2 'Model selection index should be auditable.'
  Assert-Equal $readPlanData.model_cost_rank 1 'Runtime cost rank should be auditable.'
  Assert-Equal $readPlanData.model_selection_reason 'runtime_cost_rank' 'Ranked selection should expose its reason.'
  Assert-Equal $readPlanData.reasoning_effort 'medium' 'Simple code should use medium effort.'
  Register-SafetyControl 'runtime-model-inventory'
  Close-TestReadPlan 'model-order' $readPlan

  $unrankedPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-unranked', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'docs/**',
    '-RuntimeModels', 'runtime-first=low,medium;runtime-second=low,medium'
  )
  Assert-Success $unrankedPlan 'Unranked runtime model planning failed.'
  $unrankedData = Get-GovernorData $unrankedPlan
  Assert-Equal $unrankedData.requested_model 'runtime-first' 'Unranked models must preserve runtime inventory order.'
  Assert-Equal $unrankedData.model_selection_reason 'runtime_inventory_order_unranked' 'Unranked fallback reason should be explicit.'
  Close-TestReadPlan 'model-unranked' $unrankedPlan

  $mixedRankPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-mixed-rank', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'docs/**',
    '-RuntimeModels', 'runtime-first=low,medium;runtime-ranked=low,medium|cost=0'
  )
  Assert-Success $mixedRankPlan 'Mixed rank runtime model planning failed.'
  Assert-Equal (Get-GovernorData $mixedRankPlan).requested_model 'runtime-first' `
    'Partial ranking metadata must not silently outrank an unranked compatible model.'
  Close-TestReadPlan 'model-mixed-rank' $mixedRankPlan

  $requestedPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-requested', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'docs/**', '-RequestedModel', 'gpt-5.6-luna'
  )
  Assert-Success $requestedPlan 'Advertised model validation failed.'
  Assert-Equal (Get-GovernorData $requestedPlan).requested_model 'gpt-5.6-luna' 'An advertised requested model should be honored.'
  Register-SafetyControl 'requested-model-validation'
  Close-TestReadPlan 'model-requested' $requestedPlan

  $modelContractPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'model-contract', '-TaskClass', 'docs',
    '-AccessMode', 'read', '-Scope', 'docs/**', '-RequestedModel', 'gpt-5.6-sol'
  )
  Assert-Success $modelContractPlan 'Model-contract plan failed.'
  $modelContractData = Get-GovernorData $modelContractPlan
  $modelMismatchLease = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'model-contract', '-WorkerId', '/root/model-contract',
    '-PlanToken', $modelContractData.plan_token, '-EffectiveModel', 'gpt-5.6-luna'
  )
  Assert-Failure $modelMismatchLease 'model_plan_mismatch' 'A mismatched effective model must fail at worker binding.'
  $modelContractLeaseOutput = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'model-contract', '-WorkerId', '/root/model-contract',
    '-PlanToken', $modelContractData.plan_token, '-EffectiveModel', 'gpt-5.6-sol'
  )
  Assert-Success $modelContractLeaseOutput 'An exactly matching effective model should lease.'
  $modelContractLeaseData = Get-GovernorData $modelContractLeaseOutput
  $modelContractLease = @{
    Task = 'model-contract'; Worker = '/root/model-contract'; Mode = 'read'; Repo = $fixtureRepo
    LeaseId = $modelContractLeaseData.lease_id; FencingToken = $modelContractLeaseData.fencing_token
  }
  Assert-Failure (Invoke-LeaseAction $modelContractLease 'result' @('-EffectiveModel', 'gpt-5.6-luna')) `
    'model_plan_mismatch' 'A later conflicting effective-model report must fail explicitly.'
  Assert-Success (Invoke-LeaseAction $modelContractLease 'release') 'Model-contract lease release failed.'
  Register-SafetyControl 'model-plan-contract'

  $capacityPlanA = New-TestPlan 'capacity-plan-a' 'read' @('src/**') 'explore'
  $capacityPlanB = New-TestPlan 'capacity-plan-b' 'read' @('docs/**') 'review'
  Assert-Equal (Get-GovernorData $capacityPlanA).decision 'delegate' 'First pending plan should reserve capacity.'
  Assert-Equal (Get-GovernorData $capacityPlanB).decision 'delegate' 'Second pending plan should reserve capacity.'
  Assert-Equal (Get-GovernorData $capacityPlanA).capacity_reserved $true `
    'A successful delegated plan must report its concurrency reservation.'
  Assert-Equal (Get-GovernorData $capacityPlanB).capacity_reserved $true `
    'Each issued delegated plan must report its concurrency reservation.'
  $capacityPlanC = New-TestPlan 'capacity-plan-c' 'read' @('README.md') 'docs'
  Assert-Equal (Get-GovernorData $capacityPlanC).reason 'concurrency_budget_reached' `
    'Issued plans must reserve the concurrency budget before workers bind.'
  Assert-Equal (Get-GovernorData $capacityPlanC).capacity_reserved $false `
    'A coordinator decision must not claim reserved worker capacity.'
  Close-TestReadPlan 'capacity-plan-a' $capacityPlanA
  Close-TestReadPlan 'capacity-plan-b' $capacityPlanB
  Register-SafetyControl 'pending-plan-capacity'

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

  $writePlan = New-TestPlan 'write-disabled' 'write' @('src/**') 'simple-code' $fixtureRepo 'attr-write-disabled'
  Assert-Success $writePlan 'Write containment planning failed.'
  $writePlanData = Get-GovernorData $writePlan
  Assert-Equal $writePlanData.decision 'coordinator' 'Shared-folder writes must remain with the coordinator.'
  Assert-Equal $writePlanData.reason 'shared_folder_write_delegation_disabled' 'Write containment reason must be explicit.'
  Assert-Equal $writePlanData.write_delegation_enabled $false 'Write delegation must be visibly disabled.'
  Assert-Equal $writePlanData.security_boundary $false 'Governor must not claim to be a security boundary.'
  Assert-Equal $writePlanData.spawn_contract 'multi_agent_v2' 'Governor must emit the current V2 spawn contract.'
  Assert-Equal $writePlanData.fork_turns 'none' 'V2 workers must receive fork_turns=none.'
  if ($writePlanData.PSObject.Properties['fork_context']) { throw 'V2 plans must not emit fork_context.' }
  Register-SafetyControl 'shared-folder-write-disabled'
  Register-SafetyControl 'v2-spawn-contract'

  $traversal = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'escape', '-TaskClass', 'docs',
    '-AccessMode', 'write', '-Scope', '../outside.txt'
  )
  Assert-Failure $traversal 'invalid_scope' 'Traversal scope must be rejected.'
  Register-SafetyControl 'scope-traversal'

  $readLease = New-TestLease 'read-clean' 'reader-clean' 'read' @('src/**') 'explore'
  $wrongFence = Invoke-Governor @(
    '-Action', 'renew', '-TaskId', $readLease.Task, '-WorkerId', $readLease.Worker,
    '-LeaseId', $readLease.LeaseId, '-FencingToken', 'wrong-token'
  )
  Assert-Failure $wrongFence 'fencing_token_mismatch' 'A stale or incorrect fencing token must fail.'
  Register-SafetyControl 'fencing'
  Assert-Success (Invoke-LeaseAction $readLease 'renew') 'Read lease renewal failed.'
  Register-SafetyControl 'lease-renewal'
  Assert-Success (Invoke-LeaseAction $readLease 'result') 'Read result transition failed.'
  Assert-Success (Invoke-LeaseAction $readLease 'verify' @('-VerificationPassed')) 'Unmodified read lease should verify.'
  Assert-Success (Invoke-LeaseAction $readLease 'accept' @('-CoordinatorAccepted')) 'Read lease acceptance failed.'
  Assert-Failure (Invoke-LeaseAction $readLease 'release') 'invalid_lifecycle_transition' 'Accepted leases must not be rewritten.'
  Register-SafetyControl 'lifecycle-transition'

  $singleWorkerLease = New-TestLease 'worker-one-active-a' '/root/single-worker' 'read' @('src/**') 'explore'
  $secondWorkerPlan = New-TestPlan 'worker-one-active-b' 'read' @('docs/**') 'review'
  $secondWorkerPlanData = Get-GovernorData $secondWorkerPlan
  $secondWorkerLease = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'worker-one-active-b', '-WorkerId', '/root/single-worker',
    '-PlanToken', $secondWorkerPlanData.plan_token
  )
  Assert-Failure $secondWorkerLease 'worker_already_leased' 'One worker ID must not own two active leases.'
  Assert-Success (Invoke-LeaseAction $singleWorkerLease 'release') 'Single-worker probe lease release failed.'
  Register-SafetyControl 'worker-one-active-lease'

  $readMutation = New-TestLease 'read-mutation' 'reader-mutation' 'read' @('README.md') 'review'
  Add-Content -LiteralPath (Join-Path $fixtureRepo 'README.md') -Value 'unexpected write'
  Assert-Success (Invoke-LeaseAction $readMutation 'result') 'Read mutation result transition failed.'
  $readMutationVerify = Invoke-LeaseAction $readMutation 'verify' @('-VerificationPassed')
  Assert-Failure $readMutationVerify 'read_worker_modified_workspace' 'A read worker must not change repository content.'
  Register-SafetyControl 'read-only'
  Assert-Success (Invoke-LeaseAction $readMutation 'release') 'Read mutation release failed.'
  & git -C $fixtureRepo checkout -q -- README.md

  $expiredLease = New-TestLease 'expired' 'reader-expired' 'read' @('src/**') 'explore'
  $statePath = Get-StatePath
  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $state.leases.expired.expires_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
  $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
  $expiredRenew = Invoke-LeaseAction $expiredLease 'renew'
  Assert-Failure $expiredRenew 'lease_expired' 'Expired leases must not be renewed.'
  $expiredRelease = Invoke-Governor @('-Action', 'release', '-TaskId', 'expired', '-CoordinatorAccepted')
  Assert-Success $expiredRelease 'Coordinator should be able to release an expired abandoned lease.'
  Register-SafetyControl 'lease-expiry'

  $expiredVerified = New-TestLease 'expired-verified' 'reader-expired-verified' 'read' @('src/**') 'verification'
  Assert-Success (Invoke-LeaseAction $expiredVerified 'result') 'Verified-expiry result transition failed.'
  Assert-Success (Invoke-LeaseAction $expiredVerified 'verify' @('-VerificationPassed')) 'Verified-expiry verification failed.'
  $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $state.leases.'expired-verified'.expires_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
  $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
  $verifiedRelease = Invoke-Governor @('-Action', 'release', '-TaskId', 'expired-verified', '-CoordinatorAccepted')
  Assert-Success $verifiedRelease 'Coordinator should be able to abandon an expired verified lease.'
  Register-SafetyControl 'expired-verified-release'

  $detachedCommit = (& git -C $fixtureRepo rev-parse HEAD).Trim()
  & git -C $fixtureRepo checkout --detach -q $detachedCommit
  $detachedWorkspace = Get-WorkspaceId
  $detachedPlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'detached-write', '-TaskClass', 'simple-code',
    '-AccessMode', 'write', '-Scope', 'src/**', '-ExpectedWorkspaceId', $detachedWorkspace,
    '-MutationAttributionId', 'attr-detached', '-MutationAttributionVerified'
  )
  Assert-Success $detachedPlan 'Detached HEAD planning failed.'
  Assert-Equal (Get-GovernorData $detachedPlan).reason 'shared_folder_write_delegation_disabled' 'Detached HEAD writes must stay with the coordinator.'
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
  $worktreeWrite = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'primary-collision', '-TaskClass', 'simple-code',
    '-AccessMode', 'write', '-Scope', 'src/**', '-ExpectedWorkspaceId', $primaryStatus.workspace_id,
    '-MutationAttributionId', 'attr-primary-collision', '-MutationAttributionVerified'
  ) $worktreePath
  Assert-Success $worktreeWrite 'Cross-worktree containment planning failed.'
  Assert-Equal (Get-GovernorData $worktreeWrite).reason 'shared_folder_write_delegation_disabled' 'Linked-worktree writes must be disabled.'
  Register-SafetyControl 'worktree-serialization'

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
    Assert-Equal (Get-GovernorData $reparsePlan).reason 'shared_folder_write_delegation_disabled' 'Reparse-point writes must fail closed.'
    Register-SafetyControl 'reparse-path'
  } else {
    Register-SafetyControl 'equivalent-path'
    Register-SafetyControl 'reparse-path'
  }

  $concurrentRepo = Join-Path $testRoot 'concurrent-repo'
  New-FixtureRepository $concurrentRepo
  $racePlans = @()
  foreach ($index in 1..2) {
    $racePlanResult = New-TestPlan "race-$index" 'write' @('src/**') 'simple-code' $concurrentRepo "attr-race-$index"
    Assert-Success $racePlanResult "Concurrent writer plan $index failed."
    $racePlanData = Get-GovernorData $racePlanResult
    Assert-Equal $racePlanData.decision 'coordinator' "Concurrent writer plan $index must stay with the coordinator."
    Assert-Equal $racePlanData.reason 'shared_folder_write_delegation_disabled' "Concurrent writer plan $index must fail closed."
    $racePlans += $racePlanData
  }
  Register-SafetyControl 'concurrent-writers'

  $lockRepo = Join-Path $testRoot 'lock-repo'
  New-FixtureRepository $lockRepo
  $lockStatePath = Get-StatePath $lockRepo
  $lockDirectory = $lockStatePath + '.lock'
  New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $lockDirectory 'owner.json') -Value '{partial'
  (Get-Item -LiteralPath (Join-Path $lockDirectory 'owner.json')).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-1)
  $stalePlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'stale-lock', '-TaskClass', 'explore',
    '-AccessMode', 'read', '-Scope', 'src/**', '-LockStaleSeconds', '1'
  ) $lockRepo
  Assert-Success $stalePlan 'Malformed stale lock should be quarantined and recovered during planning.'
  $stalePlanData = Get-GovernorData $stalePlan
  Assert-Equal $stalePlanData.decision 'delegate' 'Recovered stale lock should permit delegation.'
  $staleRecovered = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'stale-lock', '-WorkerId', 'reader-stale',
    '-PlanToken', $stalePlanData.plan_token, '-LockStaleSeconds', '1'
  ) $lockRepo
  Assert-Success $staleRecovered 'Recovered plan token should lease.'
  $replayedPlan = Invoke-Governor @(
    '-Action', 'lease', '-TaskId', 'stale-lock', '-WorkerId', 'reader-replay',
    '-PlanToken', $stalePlanData.plan_token
  ) $lockRepo
  Assert-Failure $replayedPlan 'plan_already_consumed' 'A plan token must be single use.'
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
    '-Action', 'plan', '-TaskId', 'live-lock', '-TaskClass', 'explore',
    '-AccessMode', 'read', '-Scope', 'src/**', '-LockStaleSeconds', '1'
  ) $lockRepo
  Assert-Success $liveBlocked 'A live lock should produce a safe coordinator decision.'
  Assert-Equal (Get-GovernorData $liveBlocked).reason 'state_lock_unavailable' 'An old but live lock owner must never be stolen.'
  Assert-Equal (Test-Path -LiteralPath (Join-Path $lockDirectory 'owner.json')) $true 'Failed lock acquisition must not delete the current owner.'
  Register-SafetyControl 'live-lock-preservation'

  $stateText = Get-Content -Raw -LiteralPath (Get-StatePath)
  if ($stateText -match [regex]::Escape($fixtureRepo) -or $stateText -match 'objective|prompt|response|tool_output|commands_executed|example.invalid') {
    throw "Governor state contains forbidden content.`n$stateText"
  }
  Register-SafetyControl 'privacy-state'

  $statePath = Get-StatePath
  $stateBackup = Join-Path $testRoot 'state-backup.json'
  Copy-Item -LiteralPath $statePath -Destination $stateBackup
  Set-Content -LiteralPath $statePath -Value '{not-json'
  $invalidState = Invoke-Governor @('-Action', 'status')
  Assert-Failure $invalidState 'state_invalid_json' 'Malformed state should fail closed.'
  Assert-Equal (Get-Content -Raw -LiteralPath $statePath) "{not-json`r`n" 'Malformed state must not be overwritten.'
  Register-SafetyControl 'malformed-state'

  foreach ($ambiguousState in @(
    '{"version":4,"version":4,"state_revision":0,"workers":{},"tasks":{},"leases":{},"plans":{}}',
    '{"version":4,"Version":4,"state_revision":0,"workers":{},"tasks":{},"leases":{},"plans":{}}'
  )) {
    [IO.File]::WriteAllText($statePath, $ambiguousState, [Text.UTF8Encoding]::new($false))
    Assert-Failure (Invoke-Governor @('-Action', 'status')) 'state_invalid_json' 'Duplicate or case-colliding Governor state keys must fail closed.'
    Assert-Equal (Get-Content -Raw -LiteralPath $statePath) $ambiguousState 'Ambiguous Governor state was overwritten.'
  }
  Register-SafetyControl 'ambiguous-state-keys'

  $oversizedState = '{"version":4,"state_revision":0,"workers":{},"tasks":{},"leases":{},"plans":{},"padding":"' + ('x' * 270000) + '"}'
  [IO.File]::WriteAllText($statePath, $oversizedState, [Text.UTF8Encoding]::new($false))
  Assert-Failure (Invoke-Governor @('-Action', 'status')) 'state_invalid_json' 'Oversized Governor state must fail closed.'
  Assert-Equal (Get-Item -LiteralPath $statePath).Length ([Text.Encoding]::UTF8.GetByteCount($oversizedState)) 'Oversized Governor state was overwritten.'
  Register-SafetyControl 'state-size-boundary'

  @{
    version = 4
    state_revision = 1
    workers = @()
    tasks = @{}
    leases = @{}
    plans = @{}
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath
  $invalidShape = Invoke-Governor @('-Action', 'status')
  Assert-Failure $invalidShape 'state_schema_invalid' 'Parseable state with a non-map collection must fail explicitly.'
  Register-SafetyControl 'state-schema-shape'

  @{
    version = 4
    state_revision = '9223372036854775808'
    workers = @{}
    tasks = @{}
    leases = @{}
    plans = @{}
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath
  $revisionOverflow = Invoke-Governor @('-Action', 'status')
  Assert-Failure $revisionOverflow 'state_schema_invalid' 'Out-of-range state revision must not become an opaque integer overflow.'
  Register-SafetyControl 'state-revision-boundary'

  Copy-Item -LiteralPath $stateBackup -Destination $statePath -Force
  $hardLinkPath = $statePath + '.hardlink'
  try {
    New-Item -ItemType HardLink -Path $hardLinkPath -Target $statePath -ErrorAction Stop | Out-Null
    Assert-Failure (Invoke-Governor @('-Action', 'status')) 'state_path_invalid' 'Hard-linked Governor state must fail closed.'
    Register-SafetyControl 'state-hardlink-containment'
  } finally {
    Remove-Item -LiteralPath $hardLinkPath -Force -ErrorAction SilentlyContinue
  }

  $junctionRepo = Join-Path $testRoot 'state-junction-repo'
  New-FixtureRepository $junctionRepo
  $junctionStatePath = Get-StatePath $junctionRepo
  $junctionDirectory = Split-Path -Parent $junctionStatePath
  $junctionTarget = Join-Path $testRoot 'state-junction-target'
  New-Item -ItemType Directory -Path $junctionTarget -Force | Out-Null
  $resolvedGovernorRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'Chronos\Governor'))
  $resolvedJunctionDirectory = [IO.Path]::GetFullPath($junctionDirectory)
  if (-not $resolvedJunctionDirectory.StartsWith($resolvedGovernorRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Junction fixture escaped the Governor test root.' }
  Remove-Item -LiteralPath $junctionDirectory -Recurse -Force
  New-Item -ItemType Junction -Path $junctionDirectory -Target $junctionTarget | Out-Null
  try {
    Assert-Failure (Invoke-Governor @('-Action', 'status') $junctionRepo) 'state_path_invalid' 'A reparse parent beneath the Governor state root must fail closed.'
    if (Test-Path -LiteralPath (Join-Path $junctionTarget 'governor-state.json')) { throw 'Rejected reparse state path created an external state file.' }
    Register-SafetyControl 'state-reparse-containment'
  } finally {
    Remove-Item -LiteralPath $junctionDirectory -Force -ErrorAction SilentlyContinue
  }

  $scriptText = Get-Content -Raw -LiteralPath $governorScript
  foreach ($diagnosticField in @('failure_stage', 'exception_type', 'continue_as_coordinator_and_report')) {
    if (-not $scriptText.Contains($diagnosticField)) {
      throw "Unknown Governor failures must retain privacy-safe diagnostic field: $diagnosticField"
    }
  }
  Register-SafetyControl 'privacy-safe-unknown-error-contract'

  Copy-Item -LiteralPath $stateBackup -Destination $statePath -Force
  Set-Content -LiteralPath ($statePath + '.tmp-interrupted') -Value '{partial'
  $interruptedStatus = Invoke-Governor @('-Action', 'status')
  Assert-Success $interruptedStatus 'An interrupted temporary state write must not replace valid state.'
  Register-SafetyControl 'interrupted-write'

  $unwritableRepo = Join-Path $testRoot 'unwritable-store-repo'
  New-FixtureRepository $unwritableRepo
  $unwritableStatePath = Get-StatePath $unwritableRepo
  $unwritableDirectory = Split-Path -Parent $unwritableStatePath
  New-Item -ItemType Directory -Path (Split-Path -Parent $unwritableDirectory) -Force | Out-Null
  $unwritableFull = [IO.Path]::GetFullPath($unwritableDirectory)
  $governorRootFull = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'Chronos\Governor')).TrimEnd('\')
  if (-not $unwritableFull.StartsWith($governorRootFull + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unwritable-store fixture escaped the Governor TEMP root.' }
  Remove-Item -LiteralPath $unwritableDirectory -Recurse -Force
  Set-Content -LiteralPath $unwritableDirectory -Value 'A file deliberately blocks Governor state-directory creation.'
  $unwritablePlan = Invoke-Governor @(
    '-Action', 'plan', '-TaskId', 'unwritable-store', '-TaskClass', 'explore',
    '-AccessMode', 'read', '-Scope', 'src/**'
  ) $unwritableRepo
  Assert-Success $unwritablePlan 'Unwritable state store should fail closed without a process error.'
  Assert-Equal (Get-GovernorData $unwritablePlan).decision 'coordinator' 'Unwritable state store must prevent delegation.'
  Assert-Equal (Get-GovernorData $unwritablePlan).reason 'state_store_unwritable' 'Unwritable state store must be explainable.'
  Remove-Item -LiteralPath $unwritableDirectory -Force
  Register-SafetyControl 'state-store-preflight'

  $legacyRepo = Join-Path $testRoot 'legacy-state-repo'
  New-FixtureRepository $legacyRepo
  $legacyStatePath = Join-Path $legacyRepo '.git\chronos\governor-state.json'
  New-Item -ItemType Directory -Path (Split-Path -Parent $legacyStatePath) -Force | Out-Null
  @{
    version = 2; state_revision = 7; workers = @{}; tasks = @{}; leases = @{}
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $legacyStatePath
  $legacyPlan = New-TestPlan 'legacy-migration' 'read' @('src/**') 'explore' $legacyRepo
  Assert-Success $legacyPlan 'Inactive legacy state migration failed.'
  Assert-Equal (Get-GovernorData $legacyPlan).decision 'delegate' 'Inactive legacy state should migrate before delegation.'
  $migratedStatePath = Get-StatePath $legacyRepo
  Assert-Equal (Get-Content -Raw -LiteralPath $migratedStatePath | ConvertFrom-Json).version 4 'Migrated state must use version 4.'
  Register-SafetyControl 'legacy-state-migration'

  $activeLegacyRepo = Join-Path $testRoot 'active-legacy-state-repo'
  New-FixtureRepository $activeLegacyRepo
  $activeLegacyStatePath = Join-Path $activeLegacyRepo '.git\chronos\governor-state.json'
  New-Item -ItemType Directory -Path (Split-Path -Parent $activeLegacyStatePath) -Force | Out-Null
  @{
    version = 2
    state_revision = 7
    workers = @{}
    tasks = @{}
    leases = @{ legacy = @{ status = 'working' } }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $activeLegacyStatePath
  $activeLegacyPlan = New-TestPlan 'active-legacy' 'read' @('src/**') 'explore' $activeLegacyRepo
  Assert-Failure $activeLegacyPlan 'state_migration_active_leases' 'Active legacy leases must fail closed during migration.'
  Register-SafetyControl 'legacy-active-failsafe'

  $version3Repo = Join-Path $testRoot 'version3-write-repo'
  New-FixtureRepository $version3Repo
  $version3Status = Get-GovernorData (Invoke-Governor @('-Action', 'status') $version3Repo)
  $version3StatePath = Get-StatePath $version3Repo
  New-Item -ItemType Directory -Path (Split-Path -Parent $version3StatePath) -Force | Out-Null
  $legacyTask = 'version3-write'
  $legacyWorker = '/root/version3-writer'
  @{
    version = 3
    state_revision = 9
    workers = @{
      $legacyWorker = @{
        worker_id = $legacyWorker; repository_id = $version3Status.repository_id
        workspace_id = $version3Status.workspace_id; access_mode = 'write'; status = 'leased'
      }
    }
    tasks = @{
      $legacyTask = @{
        task_id = $legacyTask; repository_id = $version3Status.repository_id
        workspace_id = $version3Status.workspace_id; access_mode = 'write'; status = 'working'
      }
    }
    leases = @{
      $legacyTask = @{
        task_id = $legacyTask; worker_id = $legacyWorker; lease_id = 'legacy-lease'
        fencing_token = 'legacy-fence'; repository_id = $version3Status.repository_id
        workspace_id = $version3Status.workspace_id; access_mode = 'write'; status = 'working'
        expires_at = [DateTimeOffset]::UtcNow.AddMinutes(30).ToString('o')
      }
    }
    plans = @{}
  } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $version3StatePath -Encoding UTF8
  $quarantinedStatus = Get-GovernorData (Invoke-Governor @('-Action', 'status') $version3Repo)
  Assert-Equal $quarantinedStatus.state_version 4 'Version-3 state must migrate to version 4.'
  Assert-Equal $quarantinedStatus.blocked_legacy_write_leases 1 'Active version-3 writes must be quarantined.'
  $persistedQuarantine = Get-Content -Raw -LiteralPath $version3StatePath | ConvertFrom-Json
  Assert-Equal $persistedQuarantine.version 4 'Status did not persist the Governor state migration.'
  Assert-Equal $persistedQuarantine.leases.$legacyTask.status 'blocked_legacy_write' 'Status did not persist the quarantined lease state.'
  foreach ($blockedAction in @('renew', 'result', 'verify', 'correct', 'accept')) {
    $blockedResult = Invoke-Governor @(
      '-Action', $blockedAction, '-TaskId', $legacyTask, '-WorkerId', $legacyWorker,
      '-LeaseId', 'legacy-lease', '-FencingToken', 'legacy-fence'
    ) $version3Repo
    Assert-Failure $blockedResult 'legacy_write_lease_disabled' "Legacy write action $blockedAction must fail closed."
  }
  $blockedReadPlan = New-TestPlan 'blocked-by-legacy-write' 'read' @('src/**') 'explore' $version3Repo
  Assert-Success $blockedReadPlan 'Planning around a quarantined write should return a safe decision.'
  Assert-Equal (Get-GovernorData $blockedReadPlan).reason 'legacy_write_lease_disabled' 'Quarantined writes must block new delegation.'
  $legacyRelease = Invoke-Governor @('-Action', 'release', '-TaskId', $legacyTask, '-CoordinatorAccepted') $version3Repo
  Assert-Success $legacyRelease 'Coordinator-approved legacy write quarantine release failed.'
  Assert-Equal (Get-GovernorData $legacyRelease).fingerprint_executed $false 'Legacy write disposal must not fingerprint the repository.'
  Assert-Equal (Get-GovernorData (Invoke-Governor @('-Action', 'status') $version3Repo)).blocked_legacy_write_leases 0 `
    'Legacy write quarantine should clear after explicit release.'
  Register-SafetyControl 'version3-write-quarantine'

  $customState = Join-Path $testRoot 'custom-state.json'
  Set-Content -LiteralPath $customState -Value '{private-test}'
  $customStateResult = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $governorScript -Action status -Repository $fixtureRepo -StatePath $customState 2>&1
  if ($LASTEXITCODE -eq 0 -or ($customStateResult -join "`n") -notmatch 'custom_state_path_disabled') {
    throw 'Custom state paths should not bypass canonical read-coordination state.'
  }
  Assert-Equal (Get-Content -Raw -LiteralPath $customState) "{private-test}`r`n" 'Rejected custom state must remain untouched.'
  Register-SafetyControl 'custom-state-disabled'

  if ($scriptText -match '\bStop-Process\b|git\s+(reset|clean|worktree\s+remove)') {
    throw 'Governor script contains a destructive repository or process operation.'
  }
  if ($scriptText -match "Invoke-Git\s+@\('diff'|git\s+diff") {
    throw 'Governor fingerprinting must not invoke working-tree git diff.'
  }

  Write-Output ("Chronos Governor deterministic validations passed. Scenarios: {0}. This checklist is not a security-coverage percentage." -f `
    $validatedScenarios)
} finally {
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
  $governorTempRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'Chronos\Governor'))
  foreach ($stateDirectory in $stateDirectories) {
    $resolvedStateDirectory = [System.IO.Path]::GetFullPath($stateDirectory)
    if ($resolvedStateDirectory.StartsWith($governorTempRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolvedStateDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

exit 0
