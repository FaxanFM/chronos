param([string]$PluginRoot = '')
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Run under inbox Windows PowerShell 5.1 Desktop.' }
if (-not $PluginRoot) { $PluginRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'plugins\chronos' }
$wrapper = Join-Path $PluginRoot 'skills\chronos\scripts\chronos.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $tempRoot ('chronos-removal-' + [guid]::NewGuid().ToString('N'))
$homeA = Join-Path $fixture 'home-a'
$homeB = Join-Path $fixture 'home-b'
New-Item -ItemType Directory -Path $homeA, $homeB -Force | Out-Null
function Hash([string]$Text) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}
function Invoke-Removal([string]$HomePath, [string]$Mode = 'data-plan', [string[]]$Extra = @()) {
  $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -Action $Mode -CodexHome $HomePath @Extra
  $code = $LASTEXITCODE
  $data = ($output -join "`n") | ConvertFrom-Json
  return [pscustomobject]@{ code = $code; data = $data }
}
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Root([string]$HomePath, [int]$Slot = 0) {
  $scope = '{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), ([IO.Path]::GetFullPath($HomePath)).ToUpperInvariant()
  return Join-Path $tempRoot ('Chronos-Supervision-v3-{0}-{1}' -f (Hash $scope).Substring(0,24), $Slot)
}
$rootA = Root $homeA
$rootB = Root $homeB
$rootA1 = Root $homeA 1
$priorHash = Hash ('{0}|{1}' -f $env:COMPUTERNAME, [IO.Path]::GetFullPath($homeA))
$priorA = Join-Path $tempRoot ('Chronos\Supervision-v2\' + $priorHash)
$scopeA = '{0}|{1}' -f $env:COMPUTERNAME.ToUpperInvariant(), ([IO.Path]::GetFullPath($homeA)).ToUpperInvariant()
$inboxA = Join-Path $tempRoot ('Chronos-Supervision-Inbox-v1-' + (Hash $scopeA).Substring(0,24))
$heartbeatA = Join-Path $tempRoot ('Chronos\Heartbeat-v2\' + (Hash (ConvertTo-Json -InputObject $scopeA -Compress)))
$allRoots = @($rootA, $rootB, $rootA1, $priorA, $inboxA, $heartbeatA, $fixture)
try {
  $empty = Invoke-Removal $homeA
  Assert ($empty.code -eq 0 -and $empty.data.fileCount -eq 0) 'Empty plan failed.'
  Assert (-not (Test-Path -LiteralPath $rootA)) 'Dry-run plan created state.'
  New-Item -ItemType Directory -Path $rootA, $rootB, $rootA1, $priorA, $inboxA, $heartbeatA -Force | Out-Null
  foreach ($root in @($rootA, $rootA1, $priorA, $rootB)) {
    [IO.File]::WriteAllText((Join-Path $root 'installation-scope.json'), '{"schema":1,"id":"01234567890123456789012345678901"}')
    [IO.File]::WriteAllText((Join-Path $root 'session-registry.json'), '{"fixture":"owned"}')
  }
  $pending = Join-Path $rootA 'session-registry.json.pending'
  New-Item -ItemType Directory -Path $pending | Out-Null
  [IO.File]::WriteAllText((Join-Path $pending 'pending-slot-001.json'), '{}')
  [IO.File]::WriteAllText((Join-Path $inboxA 'pending-slot-002.json'), '{}')
  [IO.File]::WriteAllText((Join-Path $heartbeatA 'heartbeat-state.json'), '{}')
  $foreignBefore = (Get-FileHash -LiteralPath (Join-Path $rootB 'session-registry.json')).Hash
  $plan = Invoke-Removal $homeA
  Assert ($plan.code -eq 0 -and $plan.data.fileCount -eq 9) 'Owned scope plan did not enumerate all slots, inbox and prior state.'
  $noConsent = Invoke-Removal $homeA 'data-remove' @('-RemovalPlanHash', $plan.data.planHash)
  Assert ($noConsent.code -ne 0 -and $noConsent.data.error -eq 'removal_confirmation_required') 'Missing confirmations did not fail closed.'
  $confirm = @('-ConfirmRecurrencesStopped', '-ConfirmHooksDisabled', '-ConfirmLocalDataRemoval')
  [IO.File]::AppendAllText((Join-Path $rootA 'session-registry.json'), ' ')
  $stale = Invoke-Removal $homeA 'data-remove' (@('-RemovalPlanHash', $plan.data.planHash) + $confirm)
  Assert ($stale.code -ne 0 -and $stale.data.error -eq 'removal_plan_changed') 'Changed plan was accepted.'
  $unknown = Join-Path $rootA 'user-notes.txt'
  [IO.File]::WriteAllText($unknown, 'preserve')
  $blocked = Invoke-Removal $homeA
  Assert ($blocked.code -ne 0 -and $blocked.data.error -eq 'removal_unknown_entry') 'Unknown file did not fail closed.'
  Remove-Item -LiteralPath $unknown
  $hardlink = Join-Path $rootA 'installation-scope.json'
  $hardlinkTarget = Join-Path $fixture 'foreign-anchor.json'
  Remove-Item -LiteralPath $hardlink
  [IO.File]::WriteAllText($hardlinkTarget, '{}')
  New-Item -ItemType HardLink -Path $hardlink -Target $hardlinkTarget | Out-Null
  $linked = Invoke-Removal $homeA
  Assert ($linked.code -ne 0 -and $linked.data.error -eq 'removal_hardlink_path') 'Hardlink was not rejected.'
  Remove-Item -LiteralPath $hardlink
  [IO.File]::WriteAllText($hardlink, '{}')
  $junction = Join-Path $rootA 'session-registry.json.pending'
  Remove-Item -LiteralPath (Join-Path $junction 'pending-slot-001.json')
  [IO.Directory]::Delete($junction)
  New-Item -ItemType Junction -Path $junction -Target $rootB | Out-Null
  $linkedDirectory = Invoke-Removal $homeA
  Assert ($linkedDirectory.code -ne 0 -and $linkedDirectory.data.error -eq 'removal_reparse_path') 'Junction was not rejected.'
  [IO.Directory]::Delete($junction)
  $plan = Invoke-Removal $homeA
  $removed = Invoke-Removal $homeA 'data-remove' (@('-RemovalPlanHash', $plan.data.planHash) + $confirm)
  Assert ($removed.code -eq 0 -and $removed.data.removed) 'Scoped removal failed.'
  foreach ($path in @($rootA, $rootA1, $priorA, $inboxA, $heartbeatA)) { Assert (-not (Test-Path -LiteralPath $path)) 'Owned root survived removal.' }
  Assert ((Get-FileHash -LiteralPath (Join-Path $rootB 'session-registry.json')).Hash -eq $foreignBefore) 'Foreign scope changed.'
  $after = Invoke-Removal $homeA
  Assert ($after.code -eq 0 -and $after.data.fileCount -eq 0 -and @($after.data.directories).Count -eq 0) 'Removal resurrected state.'
  Assert (Test-Path -LiteralPath $hardlinkTarget) 'Foreign hardlink target removed.'
  $repository = Join-Path $fixture 'repository'
  New-Item -ItemType Directory -Path $repository | Out-Null
  & git init -q $repository
  if ($LASTEXITCODE -ne 0) { throw 'Fixture Git init failed.' }
  $common = (& git -C $repository rev-parse --path-format=absolute --git-common-dir | Out-String).Trim()
  $common = [IO.Path]::GetFullPath($common)
  $governorRoot = Join-Path $tempRoot ('Chronos\Governor\' + (Hash $common.ToLowerInvariant()))
  $allRoots += $governorRoot
  New-Item -ItemType Directory -Path $governorRoot -Force | Out-Null
  $governorState = Join-Path $governorRoot 'governor-state.json'
  [IO.File]::WriteAllText($governorState, '{"version":4,"tasks":{},"leases":{"active":{"status":"working"}}}')
  $repoSelection = @('-RemovalRepositories', $repository)
  $liveLease = Invoke-Removal $homeA 'data-plan' $repoSelection
  Assert ($liveLease.code -ne 0 -and $liveLease.data.error -eq 'removal_active_lease') ('Active lease was not rejected: ' + ($liveLease.data | ConvertTo-Json -Compress))
  [IO.File]::WriteAllText($governorState, '{"version":4,"tasks":{},"leases":[]}')
  $invalidLeaseMap = Invoke-Removal $homeA 'data-plan' $repoSelection
  Assert ($invalidLeaseMap.code -ne 0 -and $invalidLeaseMap.data.error -eq 'removal_governor_state_invalid') 'Malformed lease map was treated as no active leases.'
  [IO.File]::WriteAllText($governorState, '{"version":4,"tasks":{},"leases":{}}')
  $repoPlan = Invoke-Removal $homeA 'data-plan' $repoSelection
  $repoRemoved = Invoke-Removal $homeA 'data-remove' (@('-RemovalPlanHash', $repoPlan.data.planHash) + $confirm + $repoSelection)
  Assert ($repoRemoved.code -eq 0 -and -not (Test-Path -LiteralPath $governorRoot)) 'Explicit inactive repository removal failed.'
  'Chronos scoped removal tests passed.'
} finally {
  foreach ($path in $allRoots) {
    $full = [IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped TEMP.' }
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
  }
}
