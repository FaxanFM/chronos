param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $repoRoot "scripts\build-release.ps1"
$manifestPath = Join-Path $repoRoot "plugins\chronos\.codex-plugin\plugin.json"
$releaseWorkflowPath = Join-Path $repoRoot ".github\workflows\release.yml"
$testWorkflowPath = Join-Path $repoRoot ".github\workflows\test.yml"
$version = [string](Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json).version
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-release-tests-" + [guid]::NewGuid())
$first = Join-Path $testRoot "first"
$second = Join-Path $testRoot "second"

try {
  $releaseWorkflow = Get-Content -Raw -LiteralPath $releaseWorkflowPath
  $testWorkflow = Get-Content -Raw -LiteralPath $testWorkflowPath
  foreach ($required in @(
    'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09',
    'os: [windows-2022, windows-latest]',
    'timeout-minutes: 25',
    'Parse PowerShell sources',
    'Parse JSON manifests'
  )) {
    if (-not $testWorkflow.Contains($required)) {
      throw "Ordinary CI is missing release-quality validation: $required"
    }
  }
  foreach ($required in @(
    'Require verified commit and annotated tag',
    'tagObject.verification.verified',
    'commit.commit.verification.verified',
    'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09',
    'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6',
    'timeout-minutes:',
    'gh attestation verify $Path --repo $env:GITHUB_REPOSITORY',
    '--draft',
    'gh release edit $env:GITHUB_REF_NAME --draft=false',
    'function Invoke-ReleaseVerification',
    'for ($attempt = 1; $attempt -le 12; $attempt++)',
    'Start-Sleep -Seconds 5',
    'gh release verify $env:GITHUB_REF_NAME',
    'gh release verify-asset $env:GITHUB_REF_NAME'
  )) {
    if (-not $releaseWorkflow.Contains($required)) {
      throw "Release workflow is missing supply-chain control: $required"
    }
  }
  $draftIndex = $releaseWorkflow.IndexOf('gh release create')
  $publishIndex = $releaseWorkflow.IndexOf('gh release edit $env:GITHUB_REF_NAME --draft=false')
  $preVerifyIndex = $releaseWorkflow.IndexOf('gh attestation verify $Path --repo $env:GITHUB_REPOSITORY')
  $verifyIndex = $releaseWorkflow.IndexOf('gh release verify $env:GITHUB_REF_NAME')
  if ($preVerifyIndex -lt 0 -or $draftIndex -le $preVerifyIndex -or $publishIndex -le $draftIndex -or $verifyIndex -le $publishIndex) {
    throw "Release workflow must verify the attestation, create a draft, publish it, and then verify the immutable release in that order."
  }

  $firstOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $builder -Version $version -OutputDirectory $first 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "First release build failed.`n$($firstOutput -join "`n")" }
  $secondOutput = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $builder -Version $version -OutputDirectory $second 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "Second release build failed.`n$($secondOutput -join "`n")" }

  $artifactName = "chronos-v$version.zip"
  $firstArtifact = Join-Path $first $artifactName
  $secondArtifact = Join-Path $second $artifactName
  $firstHash = (Get-FileHash -LiteralPath $firstArtifact -Algorithm SHA256).Hash
  $secondHash = (Get-FileHash -LiteralPath $secondArtifact -Algorithm SHA256).Hash
  if ($firstHash -ne $secondHash) { throw "Two clean release builds produced different SHA-256 hashes." }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($firstArtifact)
  try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    $sortedNames = @($names | Sort-Object)
    if (($names -join "`n") -ne ($sortedNames -join "`n")) { throw "Release entries are not deterministically ordered." }
    foreach ($entry in $archive.Entries) {
      if ($entry.LastWriteTime.DateTime -ne [DateTime]::new(1980, 1, 1, 0, 0, 0, [DateTimeKind]::Unspecified)) {
        throw "Release entry has a non-reproducible timestamp: $($entry.FullName)"
      }
      if ($entry.Name -eq 'LICENSE' -or [System.IO.Path]::GetExtension($entry.Name).ToLowerInvariant() -in @('.json', '.md', '.ps1', '.yaml', '.yml', '.txt')) {
        $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8)
        try { $entryText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($entryText.Contains("`r")) { throw "Packaged text is not normalized to LF: $($entry.FullName)" }
      }
    }
    foreach ($required in @('.codex-plugin/plugin.json', 'skills/chronos/SKILL.md', 'skills/chronos-governor/SKILL.md')) {
      if ($names -notcontains $required) { throw "Release is missing $required." }
    }
    if ($names -contains '.gitignore' -or $names -match '^docs/' -or $names -match '^tests/') {
      throw "Release contains repository-only files."
    }
  } finally {
    $archive.Dispose()
  }

  $checksum = (Get-Content -Raw -LiteralPath (Join-Path $first "chronos-v$version.sha256")).Trim()
  if ($checksum -ne ($firstHash.ToLowerInvariant() + "  " + $artifactName)) { throw "Checksum file does not match the artifact." }
  $releaseManifest = Get-Content -Raw -LiteralPath (Join-Path $first "chronos-v$version.release.json") | ConvertFrom-Json
  if ($releaseManifest.schema_version -ne 2 -or @($releaseManifest.files).Count -ne $releaseManifest.packaged_files) {
    throw "Release manifest must contain a versioned per-file inventory."
  }
  if (
    [long]$releaseManifest.packaged_bytes -gt [long]$releaseManifest.package_limits.package_bytes -or
    [int]$releaseManifest.packaged_files -gt [int]$releaseManifest.package_limits.files
  ) { throw "Release manifest violates its package limits." }
  $archive = [System.IO.Compression.ZipFile]::OpenRead($firstArtifact)
  try {
    foreach ($fileRecord in @($releaseManifest.files)) {
      $entry = $archive.GetEntry([string]$fileRecord.path)
      if (-not $entry) { throw "Release manifest references a missing entry: $($fileRecord.path)" }
      $sha = [System.Security.Cryptography.SHA256]::Create()
      $entryStream = $entry.Open()
      try {
        $entryHash = ([System.BitConverter]::ToString($sha.ComputeHash($entryStream))).Replace('-', '').ToLowerInvariant()
      } finally {
        $entryStream.Dispose()
        $sha.Dispose()
      }
      if ($entryHash -ne [string]$fileRecord.sha256 -or [long]$entry.Length -ne [long]$fileRecord.bytes) {
        throw "Release manifest hash or size mismatch: $($fileRecord.path)"
      }
    }
  } finally {
    $archive.Dispose()
  }
  Write-Output "Chronos release tests passed. Reproducibility: 2/2 identical builds."
} finally {
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit 0
