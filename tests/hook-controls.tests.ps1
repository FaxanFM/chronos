param([Parameter(Mandatory = $true)][string]$CodexPath)
$ErrorActionPreference = 'Stop'
$codex = (Resolve-Path -LiteralPath $CodexPath).ProviderPath
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('chronos-hook-control-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$prior = $env:CODEX_HOME
try {
  $env:CODEX_HOME = $fixture
  [IO.File]::WriteAllText((Join-Path $fixture 'config.toml'), "[features]`ncollaboration_modes = false`n")
  $version = (& $codex --version | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'Version unavailable.' }
  & $codex features enable hooks | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Supported hooks enable command unavailable.' }
  $on = (& $codex features list | Out-String)
  if ($LASTEXITCODE -ne 0 -or $on -notmatch '(?m)^hooks\s+\S+\s+true\s*$') { throw 'Hooks enabled state not verified.' }
  & $codex features disable hooks | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Supported hooks disable command unavailable.' }
  $off = (& $codex features list | Out-String)
  if ($LASTEXITCODE -ne 0 -or $off -notmatch '(?m)^hooks\s+\S+\s+false\s*$') { throw 'Hooks disabled state not verified in a new process.' }
  $config = Get-Content -Raw -LiteralPath (Join-Path $fixture 'config.toml')
  if ($config -notmatch 'hooks\s*=\s*false' -or $config -notmatch 'collaboration_modes\s*=\s*false') { throw 'Persistent setting or unrelated feature preservation failed.' }
  [ordered]@{ result = 'PASS'; codex = $version; control = 'features_hooks_global'; effectiveState = 'false'; newProcess = $true; productionConfigChanged = $false; trustChanged = $false; desktopReloadOrDispatch = 'not_evaluated' } | ConvertTo-Json -Compress
} finally {
  $env:CODEX_HOME = $prior
  $full = [IO.Path]::GetFullPath($fixture)
  $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if (-not $full.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture escaped TEMP.' }
  Remove-Item -LiteralPath $full -Recurse -Force
}
