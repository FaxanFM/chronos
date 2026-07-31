param(
  [ValidateSet("plan", "lease", "result", "verify", "correct", "accept", "retire", "release", "status")]
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
  [ValidateSet("low", "medium", "high")]
  [string]$ReasoningEffort = "low",
  [ValidateSet("HEALTHY", "WARNING", "CRITICAL", "UNAVAILABLE")]
  [string]$Health = "UNAVAILABLE",
  [ValidateSet("LOW", "ELEVATED", "HIGH", "UNAVAILABLE")]
  [string]$QuotaRisk = "UNAVAILABLE",
  [switch]$VerificationPassed,
  [switch]$CoordinatorAccepted,
  [int]$MaxConcurrentWorkers = 2,
  [int]$MaxTotalAttempts = 3,
  [int]$MaxCorrections = 1,
  [int]$StaleMinutes = 120
)

$ErrorActionPreference = "Stop"

function Write-GovernorOutput {
  param([hashtable]$Data)
  Write-Output ("CHRONOS GOVERNOR " + ($Data | ConvertTo-Json -Compress -Depth 8))
}

function Throw-GovernorError {
  param([string]$Code)
  throw [System.InvalidOperationException]::new($Code)
}

function Invoke-Git {
  param([string[]]$Arguments)
  $output = @(& git -C $script:RepositoryRoot @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { Throw-GovernorError "git_command_failed" }
  ($output -join "`n").Trim()
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

function Get-RepositoryId {
  param([string]$Path)
  $normalized = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/').ToLowerInvariant()
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
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

function Normalize-Identifier {
  param([string]$Value, [string]$ErrorCode)
  if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') {
    Throw-GovernorError $ErrorCode
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
  @($Scope | ForEach-Object { Normalize-Scope $_ } | Sort-Object -Unique)
}

function Test-PathInScope {
  param([string]$Path, [string[]]$AllowedScopes)
  $normalizedPath = (Normalize-Scope $Path)
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
  $fullPath = [System.IO.Path]::GetFullPath((Join-Path $script:RepositoryRoot $Path))
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
  $false
}

function New-State {
  @{
    version = 1
    workers = @{}
    tasks = @{}
    leases = @{}
  }
}

function Read-State {
  if (-not (Test-Path -LiteralPath $script:ResolvedStatePath -PathType Leaf)) {
    return New-State
  }
  try {
    $parsed = Get-Content -Raw -LiteralPath $script:ResolvedStatePath | ConvertFrom-Json -ErrorAction Stop
    $state = ConvertTo-Hashtable $parsed
  } catch {
    Throw-GovernorError "state_invalid_json"
  }
  if ($state.version -ne 1 -or $null -eq $state.workers -or $null -eq $state.tasks -or $null -eq $state.leases) {
    Throw-GovernorError "state_version_unsupported"
  }
  $state
}

function Write-State {
  param([hashtable]$State)
  $directory = Split-Path -Parent $script:ResolvedStatePath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  $temporary = $script:ResolvedStatePath + ".tmp-" + [guid]::NewGuid().ToString('N')
  $backup = $script:ResolvedStatePath + ".bak"
  try {
    $json = $State | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $script:ResolvedStatePath -PathType Leaf) {
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
      [System.IO.File]::Replace($temporary, $script:ResolvedStatePath, $backup, $true)
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    } else {
      [System.IO.File]::Move($temporary, $script:ResolvedStatePath)
    }
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
  }
}

function Acquire-StateLock {
  $lockPath = $script:ResolvedStatePath + ".lock"
  $directory = Split-Path -Parent $lockPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  foreach ($attempt in 1..20) {
    try {
      return [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
      )
    } catch [System.IO.IOException] {
      if ($attempt -eq 20) { Throw-GovernorError "state_locked" }
      Start-Sleep -Milliseconds 50
    }
  }
}

function Release-StateLock {
  param($LockStream)
  if ($LockStream) { $LockStream.Dispose() }
  $lockPath = $script:ResolvedStatePath + ".lock"
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

function Get-ActiveLeases {
  param([hashtable]$State)
  @($State.leases.Values | Where-Object { $_.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction') })
}

function Get-TaskChanges {
  param([string]$BaseCommit)
  $trackedText = Invoke-Git @('diff', '--name-only', '--diff-filter=ACDMRTUXB', $BaseCommit, '--')
  $untrackedText = Invoke-Git @('ls-files', '--others', '--exclude-standard')
  $paths = @()
  if ($trackedText) { $paths += @($trackedText -split "`r?`n") }
  if ($untrackedText) { $paths += @($untrackedText -split "`r?`n") }
  @($paths | Where-Object { $_ } | ForEach-Object { Normalize-Scope $_ } | Sort-Object -Unique)
}

try {
  $resolvedRepository = [System.IO.Path]::GetFullPath($Repository)
  if (-not (Test-Path -LiteralPath $resolvedRepository -PathType Container)) {
    Throw-GovernorError "repository_unavailable"
  }
  $script:RepositoryRoot = (& git -C $resolvedRepository rev-parse --show-toplevel 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $script:RepositoryRoot) { Throw-GovernorError "git_repository_required" }
  $script:RepositoryRoot = [System.IO.Path]::GetFullPath($script:RepositoryRoot)
  $repositoryId = Get-RepositoryId $script:RepositoryRoot

  if ($StatePath) {
    $script:ResolvedStatePath = [System.IO.Path]::GetFullPath($StatePath)
    $repoPrefix = $script:RepositoryRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($script:ResolvedStatePath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      Throw-GovernorError "custom_state_path_must_be_private"
    }
  } else {
    $gitStatePath = (& git -C $script:RepositoryRoot rev-parse --path-format=absolute --git-path chronos/governor-state.json 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $gitStatePath) { Throw-GovernorError "git_state_path_unavailable" }
    $script:ResolvedStatePath = [System.IO.Path]::GetFullPath($gitStatePath)
  }

  if ($MaxConcurrentWorkers -lt 1 -or $MaxConcurrentWorkers -gt 4) {
    Throw-GovernorError "invalid_concurrency_limit"
  }
  if ($MaxTotalAttempts -lt 1 -or $MaxTotalAttempts -gt 5) {
    Throw-GovernorError "invalid_attempt_limit"
  }
  if ($MaxCorrections -lt 0 -or $MaxCorrections -gt 2) {
    Throw-GovernorError "invalid_correction_limit"
  }
  if ($StaleMinutes -lt 15 -or $StaleMinutes -gt 1440) {
    Throw-GovernorError "invalid_stale_limit"
  }

  if ($Action -in @('plan', 'status')) {
    $state = Read-State
    $active = @(Get-ActiveLeases $state)
    if ($Action -eq 'status') {
      $staleCutoff = [DateTimeOffset]::UtcNow.AddMinutes(-$StaleMinutes)
      $stale = @($active | Where-Object {
        try { [DateTimeOffset]::Parse([string]$_.updated_at) -lt $staleCutoff } catch { $true }
      })
      Write-GovernorOutput @{
        ok = $true
        action = 'status'
        active_workers = $active.Count
        active_writers = @($active | Where-Object { $_.access_mode -eq 'write' }).Count
        idle_workers = @($state.workers.Values | Where-Object { $_.status -eq 'idle' }).Count
        stale_leases = $stale.Count
        tasks = $state.tasks.Count
        state_version = $state.version
        persistent_content = 'metadata-only'
      }
      exit 0
    }

    $task = Normalize-Identifier $TaskId 'invalid_task_id'
    $scopes = @(Get-NormalizedScopes)
    $role = if ($TaskClass -in @('review', 'verification', 'explore')) { 'analysis_worker' } else { 'implementation_worker' }
    $model = if ($RequestedModel) { $RequestedModel } else { 'gpt-5.6-luna' }
    $effort = if ($TaskClass -in @('simple-code', 'tests', 'review')) { 'medium' } else { 'low' }
    $decision = 'delegate'
    $reason = 'bounded_low_complexity_task'

    if ($TaskClass -eq 'risky') {
      $decision = 'coordinator'
      $reason = 'risk_requires_coordinator'
    } elseif ($Health -eq 'CRITICAL') {
      $decision = 'coordinator'
      $reason = 'health_advises_no_new_worker'
    } elseif ($active.Count -ge $MaxConcurrentWorkers) {
      $decision = 'coordinator'
      $reason = 'concurrency_budget_reached'
    } elseif ($AccessMode -eq 'write' -and @($active | Where-Object { $_.access_mode -eq 'write' }).Count -gt 0) {
      $decision = 'coordinator'
      $reason = 'single_writer_lease_active'
    }

    if ($AccessMode -eq 'write') {
      foreach ($scopeItem in $scopes) {
        if (Test-GlobalLockPath $scopeItem) {
          $decision = 'coordinator'
          $reason = 'global_lock_scope'
        }
      }
      $dirty = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')
      if ($dirty) {
        $decision = 'coordinator'
        $reason = 'same_folder_write_requires_clean_tree'
      }
    }

    if ($QuotaRisk -eq 'HIGH' -and $effort -eq 'medium' -and $TaskClass -notin @('simple-code', 'tests')) {
      $effort = 'low'
    }

    $reuse = @($state.workers.Values | Where-Object {
      $_.status -eq 'idle' -and $_.repository_id -eq $repositoryId -and
      $_.role -eq $role -and $_.requested_model -eq $model -and $_.access_mode -eq $AccessMode
    } | Select-Object -First 1)

    Write-GovernorOutput @{
      ok = $true
      action = 'plan'
      task_id = $task
      decision = $decision
      reason = $reason
      worker_role = $role
      requested_model = $model
      reasoning_effort = $effort
      access_mode = $AccessMode
      scopes = $scopes
      reuse_worker_id = if ($reuse.Count) { $reuse[0].worker_id } else { $null }
      fork_context = $false
      max_delegation_depth = 1
      nested_workers_allowed = $false
      final_coordinator_verification_required = $true
    }
    exit 0
  }

  $lock = Acquire-StateLock
  try {
    $state = Read-State
    $now = [DateTimeOffset]::UtcNow.ToString('o')
    $task = Normalize-Identifier $TaskId 'invalid_task_id'

    if ($Action -eq 'lease') {
      $worker = Normalize-Identifier $WorkerId 'invalid_worker_id'
      $scopes = @(Get-NormalizedScopes)
      $active = @(Get-ActiveLeases $state)
      $existingLease = if ($state.leases.ContainsKey($task)) { $state.leases[$task] } else { $null }
      if ($existingLease -and $existingLease.status -in @('leased', 'working', 'awaiting_verification', 'needs_correction')) {
        if ($existingLease.worker_id -eq $worker) {
          Write-GovernorOutput @{ ok = $true; action = 'lease'; task_id = $task; worker_id = $worker; idempotent = $true }
          exit 0
        }
        Throw-GovernorError "task_already_leased"
      }
      if ($active.Count -ge $MaxConcurrentWorkers) { Throw-GovernorError "concurrency_budget_reached" }
      if ($AccessMode -eq 'write' -and @($active | Where-Object { $_.access_mode -eq 'write' }).Count -gt 0) {
        Throw-GovernorError "single_writer_lease_active"
      }
      if ($AccessMode -eq 'write') {
        $dirty = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')
        if ($dirty) { Throw-GovernorError "same_folder_write_requires_clean_tree" }
        foreach ($scopeItem in $scopes) {
          if (Test-GlobalLockPath $scopeItem) { Throw-GovernorError "global_lock_scope" }
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
      if ($attempts -gt $MaxTotalAttempts) { Throw-GovernorError "attempt_budget_reached" }

      $baseCommit = Invoke-Git @('rev-parse', 'HEAD')
      $branchHash = Get-TextHash (Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD'))
      $baselineStatusHash = Get-TextHash (Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all'))
      $model = if ($RequestedModel) { $RequestedModel } else { 'gpt-5.6-luna' }
      $role = if ($TaskClass -in @('review', 'verification', 'explore')) { 'analysis_worker' } else { 'implementation_worker' }
      $state.tasks[$task] = @{
        task_id = $task
        repository_id = $repositoryId
        base_commit = $baseCommit
        branch_hash = $branchHash
        baseline_status_hash = $baselineStatusHash
        access_mode = $AccessMode
        scopes = $scopes
        attempts = $attempts
        corrections = $corrections
        status = 'working'
        created_at = $createdAt
        updated_at = $now
      }
      $state.workers[$worker] = @{
        worker_id = $worker
        repository_id = $repositoryId
        role = $role
        requested_model = $model
        effective_model = if ($EffectiveModel) { $EffectiveModel } else { $null }
        model_verification = if ($EffectiveModel) { 'reported' } else { 'runtime_not_exposed' }
        reasoning_effort = $ReasoningEffort
        access_mode = $AccessMode
        status = 'leased'
        updated_at = $now
      }
      $state.leases[$task] = @{
        task_id = $task
        worker_id = $worker
        repository_id = $repositoryId
        base_commit = $baseCommit
        branch_hash = $branchHash
        baseline_status_hash = $baselineStatusHash
        access_mode = $AccessMode
        scopes = $scopes
        status = 'working'
        created_at = $now
        updated_at = $now
      }
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'lease'
        task_id = $task
        worker_id = $worker
        base_commit = $baseCommit
        attempt = $attempts
        max_attempts = $MaxTotalAttempts
        max_delegation_depth = 1
        nested_workers_allowed = $false
      }
      exit 0
    }

    if (-not $state.leases.ContainsKey($task)) { Throw-GovernorError "lease_not_found" }
    $lease = $state.leases[$task]
    if ($WorkerId -and $lease.worker_id -ne $WorkerId) { Throw-GovernorError "worker_mismatch" }

    if ($Action -eq 'result') {
      if ($lease.status -notin @('working', 'needs_correction')) { Throw-GovernorError "lease_not_working" }
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
        worker_claims_are_untrusted = $true
      }
      exit 0
    }

    if ($Action -eq 'verify') {
      if ($lease.status -ne 'awaiting_verification') { Throw-GovernorError "result_not_ready" }
      $baseCommit = [string]$lease.base_commit
      $currentBranchHash = Get-TextHash (Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD'))
      if ($currentBranchHash -ne $lease.branch_hash) { Throw-GovernorError "branch_mismatch" }
      & git -C $script:RepositoryRoot merge-base --is-ancestor $baseCommit HEAD 2>$null
      if ($LASTEXITCODE -ne 0) { Throw-GovernorError "base_commit_mismatch" }
      $changed = @()
      if ($lease.access_mode -eq 'read') {
        $currentStatusHash = Get-TextHash (Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all'))
        if ($currentStatusHash -ne $lease.baseline_status_hash) {
          Throw-GovernorError "read_worker_modified_workspace"
        }
      } else {
        $changed = @(Get-TaskChanges $baseCommit)
        if ($changed.Count -eq 0) { Throw-GovernorError "no_changes_detected" }
        $outOfScope = @($changed | Where-Object {
          -not (Test-PathInScope -Path $_ -AllowedScopes @($lease.scopes))
        })
        $globalLocks = @($changed | Where-Object { Test-GlobalLockPath -Path $_ })
        if ($outOfScope.Count -gt 0) { Throw-GovernorError "out_of_scope_changes" }
        if ($globalLocks.Count -gt 0) { Throw-GovernorError "global_lock_change" }
        $reparseChanges = @($changed | Where-Object { Test-ReparsePath -Path $_ })
        if ($reparseChanges.Count -gt 0) { Throw-GovernorError "reparse_path_change" }
      }
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
        base_commit_valid = $true
        verification_passed = $true
      }
      exit 0
    }

    if ($Action -eq 'correct') {
      $corrections = [int]$state.tasks[$task].corrections + 1
      if ($corrections -gt $MaxCorrections) { Throw-GovernorError "correction_budget_reached" }
      $state.tasks[$task].corrections = $corrections
      $state.tasks[$task].status = 'needs_correction'
      $state.tasks[$task].updated_at = $now
      $lease.status = 'needs_correction'
      $lease.updated_at = $now
      $state.workers[$lease.worker_id].status = 'leased'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'correct'
        task_id = $task
        worker_id = $lease.worker_id
        correction = $corrections
        max_corrections = $MaxCorrections
        reuse_same_worker = $true
      }
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
      Write-GovernorOutput @{
        ok = $true
        action = 'accept'
        task_id = $task
        worker_id = $lease.worker_id
        status = 'accepted'
        worker_reusable = $true
        automatic_merge = $false
        automatic_cleanup = $false
      }
      exit 0
    }

    if ($Action -eq 'retire') {
      $lease.status = 'failed'
      $lease.updated_at = $now
      $state.tasks[$task].status = 'failed'
      $state.tasks[$task].updated_at = $now
      $state.workers[$lease.worker_id].status = 'retired'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'retire'
        task_id = $task
        worker_id = $lease.worker_id
        status = 'retired'
        automatic_cleanup = $false
      }
      exit 0
    }

    if ($Action -eq 'release') {
      $lease.status = 'released'
      $lease.updated_at = $now
      $state.tasks[$task].status = 'released'
      $state.tasks[$task].updated_at = $now
      $state.workers[$lease.worker_id].status = 'idle'
      $state.workers[$lease.worker_id].updated_at = $now
      Write-State $state
      Write-GovernorOutput @{
        ok = $true
        action = 'release'
        task_id = $task
        worker_id = $lease.worker_id
        automatic_merge = $false
        automatic_cleanup = $false
      }
      exit 0
    }
  } finally {
    Release-StateLock $lock
  }
} catch {
  $code = if ($_.Exception.Message -match '^[a-z0-9_]+$') { $_.Exception.Message } else { 'internal_error' }
  Write-GovernorOutput @{ ok = $false; action = $Action; error = $code }
  exit 1
}
