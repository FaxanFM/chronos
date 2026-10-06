$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$signers = Join-Path $repo 'docs\security\allowed_signers'
$scriptText = Get-Content -Raw -LiteralPath (Join-Path $repo 'scripts\verify-release.ps1')
foreach ($required in @('verify-tag', 'verify-commit', 'allowedSignersFile', 'release verify', 'release verify-asset', 'Get-FileHash', '--signer-workflow', '--source-digest', '--source-ref', '--deny-self-hosted-runners', 'SkipInstalledCheck', 'plugin list --json')) {
  if (-not $scriptText.Contains($required)) { throw ('Verification contract missing: ' + $required) }
}
$allowed = Get-Content -Raw -LiteralPath $signers
if ($allowed.Trim() -ne '233208718+FaxanFM@users.noreply.github.com namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJSGVCpJAjkgAGkYLkJylJGwLKU/eSXRmfwcHH45WVd') { throw 'Signing trust changed without a reviewed rotation.' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('chronos-signature-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$priorGlobal = $env:GIT_CONFIG_GLOBAL
$priorSystem = $env:GIT_CONFIG_NOSYSTEM
$priorCount = $env:GIT_CONFIG_COUNT
$baseCount = if ($priorCount) { [int]$priorCount } else { 0 }
function Run-Git([string[]]$Arguments) {
  $previous = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & git @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ code = $LASTEXITCODE; text = $output }
  } finally { $ErrorActionPreference = $previous }
}
try {
  # No machine-private allowed_signers or global signing configuration.
  $env:GIT_CONFIG_GLOBAL = 'NUL'
  $env:GIT_CONFIG_NOSYSTEM = '1'
  # The local fixture fetch starts upload-pack under the sandbox account. Trust
  # only this already-selected source checkout and its .git, for this process.
  [Environment]::SetEnvironmentVariable(('GIT_CONFIG_KEY_' + $baseCount), 'safe.directory', 'Process')
  [Environment]::SetEnvironmentVariable(('GIT_CONFIG_VALUE_' + $baseCount), $repo.Replace('\', '/'), 'Process')
  [Environment]::SetEnvironmentVariable(('GIT_CONFIG_KEY_' + ($baseCount + 1)), 'safe.directory', 'Process')
  [Environment]::SetEnvironmentVariable(('GIT_CONFIG_VALUE_' + ($baseCount + 1)), (Join-Path $repo '.git').Replace('\', '/'), 'Process')
  $env:GIT_CONFIG_COUNT = [string]($baseCount + 2)
  $selected = $null
  $history = Run-Git @('-C', $repo, 'log', '-32', '--format=%H')
  if ($history.code -ne 0) { throw 'History unavailable.' }
  foreach ($commit in @($history.text.Trim() -split '\s+')) {
    $result = Run-Git @('-C', $repo, '-c', 'gpg.format=ssh', '-c', ('gpg.ssh.allowedSignersFile=' + $signers), 'verify-commit', $commit)
    if ($result.code -eq 0) { $selected = $commit; break }
  }
  if (-not $selected) { throw 'No source commit verified against the published Chronos signer.' }
  $checkout = Join-Path $fixture 'clean-checkout'
  $init = Run-Git @('init', '-q', $checkout)
  if ($init.code -ne 0) { throw 'Clean fixture init failed.' }
  $bundlePath = Join-Path $fixture 'source.bundle'
  $bundle = Run-Git @('-C', $repo, 'bundle', 'create', $bundlePath, 'HEAD')
  if ($bundle.code -ne 0) { throw ('Fixture bundle failed: ' + $bundle.text) }
  $fetch = Run-Git @('-C', $checkout, 'fetch', $bundlePath, 'HEAD')
  if ($fetch.code -ne 0) { throw ('Clean fixture fetch failed: ' + $fetch.text) }
  $copy = Join-Path $fixture 'allowed_signers'
  Copy-Item -LiteralPath $signers -Destination $copy
  $verified = Run-Git @('-C', $checkout, '-c', 'gpg.format=ssh', '-c', ('gpg.ssh.allowedSignersFile=' + $copy), 'verify-commit', $selected)
  if ($verified.code -ne 0 -or $verified.text -notmatch [regex]::Escape('SHA256:iQB6k+xQ+EhrKOgRhgc174hqe7FtJa/quyJ541iq1Gs')) { throw 'Clean-checkout signature verification failed.' }
  [IO.File]::WriteAllText($copy, $allowed.Replace('namespaces="git"', 'namespaces="unrelated"'))
  $wrong = Run-Git @('-C', $checkout, '-c', 'gpg.format=ssh', '-c', ('gpg.ssh.allowedSignersFile=' + $copy), 'verify-commit', $selected)
  if ($wrong.code -eq 0) { throw 'Incorrect signer namespace was trusted.' }
  [ordered]@{ result = 'PASS'; sourceSignature = $selected; cleanCheckout = $true; privateConfigRequired = $false; incorrectTrustRejected = $true; publishedCandidateAttestation = 'not_available_before_publication' } | ConvertTo-Json -Compress
} finally {
  $env:GIT_CONFIG_GLOBAL = $priorGlobal
  $env:GIT_CONFIG_NOSYSTEM = $priorSystem
  foreach ($index in @($baseCount, ($baseCount + 1))) {
    [Environment]::SetEnvironmentVariable(('GIT_CONFIG_KEY_' + $index), $null, 'Process')
    [Environment]::SetEnvironmentVariable(('GIT_CONFIG_VALUE_' + $index), $null, 'Process')
  }
  $env:GIT_CONFIG_COUNT = $priorCount
  $full = [IO.Path]::GetFullPath($fixture)
  if (-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Signature fixture escaped TEMP.' }
  Remove-Item -LiteralPath $full -Recurse -Force
}
