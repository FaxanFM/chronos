param(
  [string]$Version = "",
  [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot "plugins\chronos"
$manifestPath = Join-Path $pluginRoot ".codex-plugin\plugin.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$manifestVersion = [string]$manifest.version
if (-not $Version) { $Version = $manifestVersion }
$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must use semantic version form." }
if ($Version -ne $manifestVersion) { throw "Requested version does not match plugin manifest version $manifestVersion." }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "dist" }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$artifactName = "chronos-v$Version.zip"
$artifactPath = Join-Path $OutputDirectory $artifactName
$checksumPath = Join-Path $OutputDirectory "chronos-v$Version.sha256"
$releaseManifestPath = Join-Path $OutputDirectory "chronos-v$Version.release.json"
Remove-Item -LiteralPath $artifactPath, $checksumPath, $releaseManifestPath -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files = @(Get-ChildItem -LiteralPath $pluginRoot -File -Recurse | Where-Object {
  $_.Name -ne '.gitignore'
} | Sort-Object {
  $_.FullName.Substring($pluginRoot.Length + 1).Replace('\', '/')
})
if ($files.Count -eq 0) { throw "Plugin package has no files." }
foreach ($file in $files) {
  if ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    throw "Release source contains a reparse point."
  }
}

$stream = [System.IO.File]::Open($artifactPath, 'CreateNew', 'ReadWrite', 'None')
try {
  $archive = [System.IO.Compression.ZipArchive]::new(
    $stream,
    [System.IO.Compression.ZipArchiveMode]::Create,
    $false,
    [System.Text.Encoding]::UTF8
  )
  try {
    $fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    foreach ($file in $files) {
      $relative = $file.FullName.Substring($pluginRoot.Length + 1).Replace('\', '/')
      $entry = $archive.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = $fixedTimestamp
      $entryStream = $entry.Open()
      try {
        $isText = $file.Name -eq 'LICENSE' -or $file.Extension.ToLowerInvariant() -in @(
          '.json', '.md', '.ps1', '.yaml', '.yml', '.txt'
        )
        if ($isText) {
          $content = [System.IO.File]::ReadAllText($file.FullName)
          $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
            $content.Replace("`r`n", "`n").Replace("`r", "`n")
          )
          $entryStream.Write($bytes, 0, $bytes.Length)
        } else {
          $sourceStream = [System.IO.File]::Open($file.FullName, 'Open', 'Read', 'Read')
          try { $sourceStream.CopyTo($entryStream) } finally { $sourceStream.Dispose() }
        }
      } finally {
        $entryStream.Dispose()
      }
    }
  } finally {
    $archive.Dispose()
  }
} finally {
  $stream.Dispose()
}

$artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText(
  $checksumPath,
  "$artifactHash  $artifactName`n",
  [System.Text.UTF8Encoding]::new($false)
)
$releaseManifest = [ordered]@{
  schema_version = 1
  plugin = "chronos"
  version = $Version
  artifact = $artifactName
  sha256 = $artifactHash
  packaged_files = $files.Count
  reproducible_timestamp = "1980-01-01T00:00:00Z"
  packaged_text_line_endings = "LF"
}
[System.IO.File]::WriteAllText(
  $releaseManifestPath,
  (($releaseManifest | ConvertTo-Json -Depth 4) + "`n"),
  [System.Text.UTF8Encoding]::new($false)
)

Write-Output ("CHRONOS RELEASE version={0} artifact={1} sha256={2} files={3}" -f `
  $Version, $artifactPath, $artifactHash, $files.Count)
