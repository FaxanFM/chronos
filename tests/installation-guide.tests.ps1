param(
  [Parameter(Mandatory = $true)][string]$CodexPath,
  [Parameter(Mandatory = $true)][string]$ReleaseManifestPath,
  [string]$Commit = '77ff0666c451e7ca6b81d4a0e9a598e057106afd'
)

$ErrorActionPreference = 'Stop'
if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'Guide test requires an exact commit.' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('cgi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fixtureHome = Join-Path $fixture 'codex-home'
$codex = (Resolve-Path -LiteralPath $CodexPath).ProviderPath
$expected = Get-Content -Raw -LiteralPath $ReleaseManifestPath | ConvertFrom-Json
$priorHome = $env:CODEX_HOME
$installed = $false
$catalogAdded = $false
New-Item -ItemType Directory -Path $fixtureHome -Force | Out-Null

function Invoke-PluginJson {
  param([string[]]$Arguments)
  $result = & $codex @Arguments
  if ($LASTEXITCODE -ne 0) { throw ('Guide plugin-manager command failed: ' + ($Arguments -join ' ')) }
  return ($result | ConvertFrom-Json)
}

function Get-NormalizedHash {
  param([IO.FileInfo]$File)
  $isText = $File.Name -eq 'LICENSE' -or $File.Extension.ToLowerInvariant() -in @('.cmd', '.json', '.md', '.ps1', '.yaml', '.yml', '.txt')
  if ($isText) {
    $text = [IO.File]::ReadAllText($File.FullName).Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  } else {
    $bytes = [IO.File]::ReadAllBytes($File.FullName)
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

try {
  # Test the documented GitHub commands with no live account, credentials, or model turn.
  $env:CODEX_HOME = $fixtureHome
  Push-Location $fixture
  try {
    $null = Invoke-PluginJson @('plugin', 'marketplace', 'add', 'FaxanFM/chronos', '--ref', $Commit, '--json')
    $catalogAdded = $true
    $catalogs = Invoke-PluginJson @('plugin', 'marketplace', 'list', '--json')
    $catalog = @($catalogs.marketplaces | Where-Object { $_.name -eq 'chronos' })
    if ($catalog.Count -ne 1) { throw 'Expected one isolated Chronos catalog.' }
    $resolvedCommit = (& git -C $catalog[0].root rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $resolvedCommit -ne $Commit) { throw 'Marketplace checkout did not preserve the pinned commit.' }
    $null = Invoke-PluginJson @('plugin', 'add', 'chronos@chronos', '--json')
    $installed = $true
    $list = Invoke-PluginJson @('plugin', 'list', '--json')
    $plugin = @($list.installed | Where-Object { $_.pluginId -eq 'chronos@chronos' })
    if ($plugin.Count -ne 1 -or $plugin[0].version -ne $expected.version -or -not $plugin[0].enabled) {
      throw 'Pinned guide install did not enable exactly the expected version.'
    }
    $cacheRoot = Join-Path $fixtureHome ('plugins\cache\chronos\chronos\' + $expected.version)
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $cacheRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
    if ($manifest.hooks -ne './hooks/hooks.json' -or $manifest.extensions.'com.openai'.onboardingSkill -ne './skills/chronos/SKILL.md') {
      throw 'The full install lost hooks or onboarding.'
    }
    foreach ($record in $expected.files) {
      $file = Get-Item -LiteralPath (Join-Path $cacheRoot $record.path)
      if ((Get-NormalizedHash $file) -ne $record.sha256) { throw ('Installed source mismatch: ' + $record.path) }
    }
    $files = @(Get-ChildItem -LiteralPath $cacheRoot -File -Recurse -Force | Where-Object { $_.Name -ne '.gitignore' })
    if ($files.Count -ne $expected.packaged_files) { throw 'Installed release-file count mismatch.' }
    $hookConfig = Get-Content -Raw -LiteralPath (Join-Path $cacheRoot 'hooks\hooks.json') | ConvertFrom-Json
    if (@($hookConfig.hooks.PSObject.Properties).Count -ne 5) { throw 'Expected five optional hook definitions.' }
    $null = Invoke-PluginJson @('plugin', 'remove', 'chronos@chronos', '--json')
    $installed = $false
    $null = Invoke-PluginJson @('plugin', 'marketplace', 'remove', 'chronos', '--json')
    $catalogAdded = $false
    $after = Invoke-PluginJson @('plugin', 'list', '--json')
    if (@($after.installed | Where-Object { $_.name -eq 'chronos' }).Count -ne 0) { throw 'Guide uninstall did not remove the isolated plugin.' }
    [ordered]@{
      result = 'PASS'; version = $expected.version; commit = $resolvedCommit
      normalizedReleaseFiles = $files.Count; hookDefinitions = 5; modelTurns = 0
      productionAccountChanged = $false; hookTrustChanged = $false
      hookExecution = 'not_evaluated'; scheduledExecution = 'not_evaluated'
      uninstallVerified = $true
    } | ConvertTo-Json -Compress
  } finally {
    if ($installed) { & $codex plugin remove chronos@chronos --json | Out-Null }
    if ($catalogAdded) { & $codex plugin marketplace remove chronos --json | Out-Null }
    Pop-Location
  }
} finally {
  $env:CODEX_HOME = $priorHome
}
