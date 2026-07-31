param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $repoRoot "scripts\build-release.ps1"
$manifestPath = Join-Path $repoRoot "plugins\chronos\.codex-plugin\plugin.json"
$version = [string](Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json).version
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("chronos-release-tests-" + [guid]::NewGuid())
$first = Join-Path $testRoot "first"
$second = Join-Path $testRoot "second"

try {
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
  Write-Output "Chronos release tests passed. Reproducibility: 2/2 identical builds."
} finally {
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit 0
