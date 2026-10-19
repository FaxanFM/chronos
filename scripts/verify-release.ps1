param(
  [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [ValidateSet('Full', 'Directory')][string]$Edition = 'Directory',
  [string]$CheckoutPath = (Split-Path -Parent $PSScriptRoot),
  [string]$DownloadDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('chronos-verify-' + [guid]::NewGuid().ToString('N'))),
  [string]$CodexPath,
  [switch]$SkipInstalledCheck
)
$ErrorActionPreference = 'Stop'
$repo = 'FaxanFM/chronos'
$checkout = (Resolve-Path -LiteralPath $CheckoutPath).ProviderPath
$signers = Join-Path $PSScriptRoot '..\docs\security\allowed_signers'
$tag = 'v' + $Version
$suffix = if ($Edition -eq 'Directory') { '-skills-only' } else { '' }
$zipName = 'chronos-v' + $Version + $suffix + '.zip'
$checksumName = 'chronos-v' + $Version + $suffix + '.sha256'
function Require-Success([string]$Message) { if ($LASTEXITCODE -ne 0) { throw $Message } }
function Verify-SshSignature([string]$Kind, [string]$Ref) {
  $previous = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & git -C $checkout -c gpg.format=ssh -c "gpg.ssh.allowedSignersFile=$signers" $Kind $Ref 2>&1 | Out-String
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $previous }
  if ($code -ne 0) { throw ($Kind + ' failed against the published Chronos signer: ' + $output) }
  Write-Output $output.Trim()
}
& git -C $checkout fetch origin ('refs/tags/{0}:refs/tags/{0}' -f $tag)
Require-Success 'Release tag fetch failed; previews cannot pass release verification.'
$type = (& git -C $checkout cat-file -t $tag | Out-String).Trim()
Require-Success 'Tag lookup failed.'
if ($type -ne 'tag') { throw 'Expected a signed annotated tag.' }
Verify-SshSignature 'verify-tag' $tag
$commit = (& git -C $checkout rev-parse "$tag^{commit}" | Out-String).Trim()
Require-Success 'Release commit lookup failed.'
Verify-SshSignature 'verify-commit' $commit
$manifest = (& git -C $checkout show "$($tag):plugins/chronos/.codex-plugin/plugin.json" | Out-String) | ConvertFrom-Json
Require-Success 'Signed manifest lookup failed.'
if ($manifest.version -ne $Version) { throw 'Tag and signed source manifest versions differ.' }
New-Item -ItemType Directory -Path $DownloadDirectory -ErrorAction Stop | Out-Null
& gh release verify $tag --repo $repo
Require-Success 'Immutable release verification failed.'
& gh release download $tag --repo $repo --pattern $zipName --pattern $checksumName --dir $DownloadDirectory
Require-Success 'Release asset download failed.'
$zip = Join-Path $DownloadDirectory $zipName
$line = (Get-Content -Raw -LiteralPath (Join-Path $DownloadDirectory $checksumName)).Trim()
if ($line -notmatch ('^([a-fA-F0-9]{64})\s+\*?' + [regex]::Escape($zipName) + '$')) { throw 'Checksum filename or format mismatch.' }
$expected = $Matches[1].ToLowerInvariant()
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) { throw 'Release checksum mismatch.' }
& gh release verify-asset $tag $zip --repo $repo
Require-Success 'Immutable asset binding failed.'
& gh attestation verify $zip --repo $repo --signer-workflow "$repo/.github/workflows/release.yml" --source-digest $commit --source-ref "refs/tags/$tag" --deny-self-hosted-runners
Require-Success 'Artifact attestation does not match the signed release commit, tag and workflow.'
if (-not $SkipInstalledCheck) {
  if (-not $CodexPath) { throw 'Pass the absolute supported Codex executable path, or explicitly skip the installed check.' }
  $installed = & $CodexPath plugin list --json | ConvertFrom-Json
  Require-Success 'Plugin-manager state lookup failed.'
  $plugins = @($installed.installed | Where-Object { $_.name -eq 'chronos' -and $_.enabled })
  $expectedIdentity = if ($Edition -eq 'Directory') { 'chronos@openai-curated-remote' } else { 'chronos@chronos' }
  if ($plugins.Count -ne 1 -or $plugins[0].version -ne $Version -or $plugins[0].pluginId -ne $expectedIdentity) { throw 'Expected exactly one enabled Chronos plugin at the verified release version and edition identity.' }
}
[ordered]@{ result = 'PASS'; version = $Version; edition = $Edition; commit = $commit; sha256 = $expected; installedCheck = if ($SkipInstalledCheck) { 'skipped_explicitly' } else { 'PASS' } } | ConvertTo-Json -Compress
