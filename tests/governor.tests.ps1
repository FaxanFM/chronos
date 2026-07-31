param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$governorScript = Join-Path $repoRoot "plugins\chronos\skills\chronos-governor\scripts\governor.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-governor-tests-" + [guid]::NewGuid())
$fixtureRepo = Join-Path $testRoot "repo"
$statePath = Join-Path $testRoot "governor-state.json"

function Invoke-Governor {
  param([string[]]$Arguments)
  $command = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $governorScript,
    "-Repository",
    $fixtureRepo,
    "-StatePath",
    $statePath
  ) + $Arguments
  $output = @(& powershell.exe @command 2>&1)
  [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Text = ($output -join "`n")
  }
}

function Assert-Success {
  param($Result, [string]$Message)
  if ($Result.ExitCode -ne 0) { throw "$Message`n$($Result.Text)" }
}

function Assert-Failure {
  param($Result, [string]$Pattern, [string]$Message)
  if ($Result.ExitCode -eq 0 -or $Result.Text -notmatch $Pattern) {
    throw "$Message`n$($Result.Text)"
  }
}

function Assert-Match {
  param([string]$Value, [string]$Pattern, [string]$Message)
  if ($Value -notmatch $Pattern) { throw "$Message`n$Value" }
}

try {
  New-Item -ItemType Directory -Path (Join-Path $fixtureRepo "src"), `
    (Join-Path $fixtureRepo "docs") -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $fixtureRepo "src\app.ps1") -Value "'initial'"
  Set-Content -LiteralPath (Join-Path $fixtureRepo "README.md") -Value "# Fixture"
  & git -C $fixtureRepo init -q
  & git -C $fixtureRepo config user.email "chronos-tests@example.invalid"
  & git -C $fixtureRepo config user.name "Chronos Tests"
  & git -C $fixtureRepo add .
  & git -C $fixtureRepo commit -qm "Initial fixture"

  $plan = Invoke-Governor @(
    "-Action", "plan", "-TaskId", "simple-1", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-Health", "HEALTHY", "-QuotaRisk", "LOW"
  )
  Assert-Success $plan "Simple-code planning failed."
  Assert-Match $plan.Text '"decision":"delegate"' "Simple code should be delegated."
  Assert-Match $plan.Text '"requested_model":"gpt-5.6-luna"' "Luna should be the bounded default."
  Assert-Match $plan.Text '"reasoning_effort":"medium"' "Simple code should use medium effort."
  Assert-Match $plan.Text '"fork_context":false' "Worker should not inherit the full parent context."

  $risky = Invoke-Governor @(
    "-Action", "plan", "-TaskId", "risky-1", "-TaskClass", "risky",
    "-AccessMode", "read", "-Scope", "src/**"
  )
  Assert-Success $risky "Risk planning failed."
  Assert-Match $risky.Text '"decision":"coordinator"' "Risky work must remain with the coordinator."

  $critical = Invoke-Governor @(
    "-Action", "plan", "-TaskId", "critical-1", "-TaskClass", "docs",
    "-AccessMode", "read", "-Scope", "docs/**", "-Health", "CRITICAL"
  )
  Assert-Success $critical "Critical-health planning failed."
  Assert-Match $critical.Text 'health_advises_no_new_worker' "Critical health should advise coordinator execution."

  $traversal = Invoke-Governor @(
    "-Action", "plan", "-TaskId", "escape-1", "-TaskClass", "docs",
    "-AccessMode", "write", "-Scope", "../outside.txt"
  )
  Assert-Failure $traversal 'invalid_scope' "Traversal scope must be rejected."

  $globalLock = Invoke-Governor @(
    "-Action", "plan", "-TaskId", "lock-1", "-TaskClass", "mechanical",
    "-AccessMode", "write", "-Scope", "package.json"
  )
  Assert-Success $globalLock "Global-lock planning failed."
  Assert-Match $globalLock.Text 'global_lock_scope' "Dependency manifests must stay with the coordinator."

  $lease = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "simple-1", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-WorkerId", "worker-1",
    "-RequestedModel", "gpt-5.6-luna", "-ReasoningEffort", "medium"
  )
  Assert-Success $lease "Write lease failed."

  $secondWriter = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "simple-2", "-TaskClass", "docs",
    "-AccessMode", "write", "-Scope", "docs/**", "-WorkerId", "worker-2"
  )
  Assert-Failure $secondWriter 'single_writer_lease_active' "A second writer must be rejected."

  Set-Content -LiteralPath (Join-Path $fixtureRepo "src\app.ps1") -Value "'worker change'"
  $result = Invoke-Governor @("-Action", "result", "-TaskId", "simple-1", "-WorkerId", "worker-1")
  Assert-Success $result "Worker result transition failed."

  $noEvidence = Invoke-Governor @("-Action", "verify", "-TaskId", "simple-1", "-WorkerId", "worker-1")
  Assert-Failure $noEvidence 'verification_evidence_required' "Verification evidence must be explicit."

  $verified = Invoke-Governor @(
    "-Action", "verify", "-TaskId", "simple-1", "-WorkerId", "worker-1", "-VerificationPassed"
  )
  Assert-Success $verified "Scoped write verification failed."
  Assert-Match $verified.Text 'src/app.ps1' "Actual changed files should be reported."

  $unaccepted = Invoke-Governor @("-Action", "accept", "-TaskId", "simple-1", "-WorkerId", "worker-1")
  Assert-Failure $unaccepted 'coordinator_acceptance_required' "Coordinator acceptance must be explicit."

  $accepted = Invoke-Governor @(
    "-Action", "accept", "-TaskId", "simple-1", "-WorkerId", "worker-1", "-CoordinatorAccepted"
  )
  Assert-Success $accepted "Verified task acceptance failed."
  Assert-Match $accepted.Text '"automatic_cleanup":false' "Acceptance must not clean worker state or files."

  $stateText = Get-Content -Raw -LiteralPath $statePath
  Assert-Match $stateText '"repository_id"' "State should contain a hashed repository identity."
  if ($stateText -match [regex]::Escape($fixtureRepo) -or
      $stateText -match 'objective|prompt|response|tool_output|commands_executed|example.invalid') {
    throw "Governor state contains forbidden content.`n$stateText"
  }

  & git -C $fixtureRepo add src/app.ps1
  & git -C $fixtureRepo commit -qm "Accept worker change"

  $reusePlan = Invoke-Governor @(
    "-Action", "plan", "-TaskId", "simple-reuse", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-RequestedModel", "gpt-5.6-luna"
  )
  Assert-Success $reusePlan "Reusable-worker planning failed."
  Assert-Match $reusePlan.Text '"reuse_worker_id":"worker-1"' "Compatible idle worker should be reused."

  $attemptTwo = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "simple-1", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-WorkerId", "worker-attempt-2"
  )
  Assert-Success $attemptTwo "Second task attempt should be permitted."
  $attemptTwoRelease = Invoke-Governor @(
    "-Action", "release", "-TaskId", "simple-1", "-WorkerId", "worker-attempt-2"
  )
  Assert-Success $attemptTwoRelease "Second task attempt release failed."
  $attemptThree = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "simple-1", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-WorkerId", "worker-attempt-3"
  )
  Assert-Success $attemptThree "Third task attempt should be permitted."
  $attemptThreeRelease = Invoke-Governor @(
    "-Action", "release", "-TaskId", "simple-1", "-WorkerId", "worker-attempt-3"
  )
  Assert-Success $attemptThreeRelease "Third task attempt release failed."
  $attemptFour = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "simple-1", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-WorkerId", "worker-attempt-4"
  )
  Assert-Failure $attemptFour 'attempt_budget_reached' "A fourth task attempt must be rejected."

  $directGlobalLock = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "direct-lock", "-TaskClass", "mechanical",
    "-AccessMode", "write", "-Scope", "package.json", "-WorkerId", "worker-lock"
  )
  Assert-Failure $directGlobalLock 'global_lock_scope' "A direct global-lock lease must fail closed."

  $readOne = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "read-1", "-TaskClass", "explore",
    "-AccessMode", "read", "-Scope", "src/**", "-WorkerId", "reader-1"
  )
  Assert-Success $readOne "First read lease failed."
  $readTwo = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "read-2", "-TaskClass", "review",
    "-AccessMode", "read", "-Scope", "docs/**", "-WorkerId", "reader-2"
  )
  Assert-Success $readTwo "Second read lease failed."
  $readThree = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "read-3", "-TaskClass", "explore",
    "-AccessMode", "read", "-Scope", "README.md", "-WorkerId", "reader-3"
  )
  Assert-Failure $readThree 'concurrency_budget_reached' "Worker concurrency must be capped at two."

  $readResult = Invoke-Governor @("-Action", "result", "-TaskId", "read-1", "-WorkerId", "reader-1")
  Assert-Success $readResult "Read result transition failed."
  $readVerified = Invoke-Governor @(
    "-Action", "verify", "-TaskId", "read-1", "-WorkerId", "reader-1", "-VerificationPassed"
  )
  Assert-Success $readVerified "Unmodified read lease should verify."
  $readAccepted = Invoke-Governor @(
    "-Action", "accept", "-TaskId", "read-1", "-WorkerId", "reader-1", "-CoordinatorAccepted"
  )
  Assert-Success $readAccepted "Read lease acceptance failed."
  $readReleased = Invoke-Governor @("-Action", "release", "-TaskId", "read-2", "-WorkerId", "reader-2")
  Assert-Success $readReleased "Read lease release failed."

  $readMutationLease = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "read-mutation", "-TaskClass", "review",
    "-AccessMode", "read", "-Scope", "README.md", "-WorkerId", "reader-mutation"
  )
  Assert-Success $readMutationLease "Read-mutation fixture lease failed."
  Add-Content -LiteralPath (Join-Path $fixtureRepo "README.md") -Value "unexpected write"
  $readMutationResult = Invoke-Governor @(
    "-Action", "result", "-TaskId", "read-mutation", "-WorkerId", "reader-mutation"
  )
  Assert-Success $readMutationResult "Read-mutation result transition failed."
  $readMutationVerify = Invoke-Governor @(
    "-Action", "verify", "-TaskId", "read-mutation", "-WorkerId", "reader-mutation", "-VerificationPassed"
  )
  Assert-Failure $readMutationVerify 'read_worker_modified_workspace' `
    "A read worker must not change repository status."
  $readMutationRelease = Invoke-Governor @(
    "-Action", "release", "-TaskId", "read-mutation", "-WorkerId", "reader-mutation"
  )
  Assert-Success $readMutationRelease "Read-mutation lease release failed."
  & git -C $fixtureRepo add README.md
  & git -C $fixtureRepo commit -qm "Record read-mutation fixture"

  $correctionLease = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "correction-1", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-WorkerId", "worker-correction"
  )
  Assert-Success $correctionLease "Correction fixture lease failed."
  $correctionOne = Invoke-Governor @(
    "-Action", "correct", "-TaskId", "correction-1", "-WorkerId", "worker-correction"
  )
  Assert-Success $correctionOne "First correction should be permitted."
  Assert-Match $correctionOne.Text '"reuse_same_worker":true' "Correction should reuse the same worker."
  $correctionTwo = Invoke-Governor @(
    "-Action", "correct", "-TaskId", "correction-1", "-WorkerId", "worker-correction"
  )
  Assert-Failure $correctionTwo 'correction_budget_reached' "A second correction must be rejected."
  $retired = Invoke-Governor @(
    "-Action", "retire", "-TaskId", "correction-1", "-WorkerId", "worker-correction"
  )
  Assert-Success $retired "Failed worker retirement failed."
  Assert-Match $retired.Text '"automatic_cleanup":false' "Retirement must preserve files and state."

  $outOfScopeLease = Invoke-Governor @(
    "-Action", "lease", "-TaskId", "scope-1", "-TaskClass", "simple-code",
    "-AccessMode", "write", "-Scope", "src/**", "-WorkerId", "worker-scope"
  )
  Assert-Success $outOfScopeLease "Out-of-scope fixture lease failed."
  Set-Content -LiteralPath (Join-Path $fixtureRepo "docs\unexpected.md") -Value "outside scope"
  $outOfScopeResult = Invoke-Governor @("-Action", "result", "-TaskId", "scope-1", "-WorkerId", "worker-scope")
  Assert-Success $outOfScopeResult "Out-of-scope result transition failed."
  $outOfScopeVerify = Invoke-Governor @(
    "-Action", "verify", "-TaskId", "scope-1", "-WorkerId", "worker-scope", "-VerificationPassed"
  )
  Assert-Failure $outOfScopeVerify 'out_of_scope_changes' "Actual out-of-scope changes must be rejected."
  $outOfScopeRelease = Invoke-Governor @("-Action", "release", "-TaskId", "scope-1", "-WorkerId", "worker-scope")
  Assert-Success $outOfScopeRelease "Failed result lease release failed."

  $scriptText = Get-Content -Raw -LiteralPath $governorScript
  if ($scriptText -match '\bStop-Process\b|git\s+(reset|clean|worktree\s+remove)|Remove-Item[^\r\n]+-Recurse') {
    throw "Governor script contains a destructive path."
  }

  $invalidStatePath = Join-Path $testRoot "invalid-state.json"
  Set-Content -LiteralPath $invalidStatePath -Value '{not-json'
  $originalInvalidState = Get-Content -Raw -LiteralPath $invalidStatePath
  $invalidState = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $governorScript -Action status -Repository $fixtureRepo -StatePath $invalidStatePath 2>&1
  if ($LASTEXITCODE -eq 0 -or ($invalidState -join "`n") -notmatch 'state_invalid_json') {
    throw "Malformed state should fail closed without replacement."
  }
  if ((Get-Content -Raw -LiteralPath $invalidStatePath) -ne $originalInvalidState) {
    throw "Malformed state was overwritten."
  }

  Write-Output "Chronos Governor tests passed."
} finally {
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit 0
