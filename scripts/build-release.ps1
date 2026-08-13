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
$trackedPaths = @(& git -C $repoRoot ls-files -- plugins/chronos)
if ($LASTEXITCODE -ne 0) { throw "Could not enumerate tracked plugin files." }
$untrackedPaths = @(& git -C $repoRoot ls-files --others --exclude-standard -- plugins/chronos)
if ($LASTEXITCODE -ne 0) { throw "Could not inspect untracked plugin files." }
if ($untrackedPaths.Count -gt 0) { throw "Plugin source contains untracked files: $($untrackedPaths -join ', ')" }
$files = @($trackedPaths | Where-Object { $_ -and $_ -notmatch '/\.gitignore$' } | ForEach-Object {
  Get-Item -LiteralPath (Join-Path $repoRoot $_) -Force
} | Sort-Object {
  $_.FullName.Substring($pluginRoot.Length + 1).Replace('\', '/')
})
if ($files.Count -eq 0) { throw "Plugin package has no files." }
$maximumFiles = 256
$maximumFileBytes = 8MB
$maximumPackageBytes = 32MB
if ($files.Count -gt $maximumFiles) { throw "Plugin package exceeds the $maximumFiles-file limit." }
$sourceBytes = [long](@($files | Measure-Object Length -Sum).Sum)
if ($sourceBytes -gt $maximumPackageBytes) { throw "Plugin source exceeds the 32 MiB package limit." }
foreach ($file in $files) {
  if ([long]$file.Length -gt $maximumFileBytes) {
    throw "Release source file exceeds the 8 MiB limit: $($file.FullName)"
  }
  $current = $file
  while ($current -and $current.FullName.StartsWith($pluginRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    if ($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
      throw "Release source contains a reparse point: $($file.FullName)"
    }
    $current = $current.Directory
  }
}

function Get-PackagedBytes {
  param([System.IO.FileInfo]$File)
  $isText = $File.Name -eq 'LICENSE' -or $File.Extension.ToLowerInvariant() -in @(
    '.cmd', '.json', '.md', '.ps1', '.yaml', '.yml', '.txt'
  )
  if ($isText) {
    $content = [System.IO.File]::ReadAllText($File.FullName)
    return ,([System.Text.UTF8Encoding]::new($false).GetBytes(
      $content.Replace("`r`n", "`n").Replace("`r", "`n")
    ))
  }
  ,([System.IO.File]::ReadAllBytes($File.FullName))
}

function Get-BytesHash {
  param([byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

$packagedFileManifest = [System.Collections.Generic.List[object]]::new()
$packagedBytesTotal = 0L
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
        $bytes = Get-PackagedBytes $file
        $packagedBytesTotal += [long]$bytes.Length
        if ($packagedBytesTotal -gt $maximumPackageBytes) {
          throw "Normalized plugin package exceeds the 32 MiB package limit."
        }
        $entryStream.Write($bytes, 0, $bytes.Length)
        $packagedFileManifest.Add([ordered]@{
          path = $relative
          bytes = [long]$bytes.Length
          sha256 = Get-BytesHash $bytes
        })
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
  schema_version = 2
  plugin = "chronos"
  version = $Version
  artifact = $artifactName
  sha256 = $artifactHash
  packaged_files = $files.Count
  packaged_bytes = $packagedBytesTotal
  package_limits = [ordered]@{
    files = $maximumFiles
    file_bytes = $maximumFileBytes
    package_bytes = $maximumPackageBytes
  }
  files = @($packagedFileManifest)
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
