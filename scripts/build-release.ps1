param(
  [string]$Version = "",
  [string]$OutputDirectory = "",
  [ValidateSet('Full', 'Directory')][string]$Edition = 'Full',
  [string]$PolicyCommit = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot "plugins\chronos"
$manifestPath = Join-Path $pluginRoot ".codex-plugin\plugin.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.hooks -ne './hooks/hooks.json') { throw 'Manifest must explicitly bind the audited hooks.' }
$manifestVersion = [string]$manifest.version
if (-not $Version) { $Version = $manifestVersion }
$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must use semantic version form." }
if ($Version -ne $manifestVersion) { throw "Requested version does not match plugin manifest version $manifestVersion." }
$policySourceRef = "v$Version"
if ($PolicyCommit) {
  $PolicyCommit = $PolicyCommit.Trim()
  if ($PolicyCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'PolicyCommit must be a full 40-hex commit SHA.' }
  $resolvedPolicyCommit = (& git -C $repoRoot rev-parse --verify "$PolicyCommit^{commit}" 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or $resolvedPolicyCommit -notmatch '^[0-9a-f]{40}$') { throw "PolicyCommit does not resolve to a commit: $PolicyCommit" }
  & git -C $repoRoot merge-base --is-ancestor $resolvedPolicyCommit HEAD 2>$null
  if ($LASTEXITCODE -ne 0) { throw "PolicyCommit must be an ancestor of the current HEAD: $resolvedPolicyCommit" }
  foreach ($policyFile in @('PRIVACY.md', 'TERMS.md')) {
    & git -C $repoRoot cat-file -e "${resolvedPolicyCommit}:$policyFile" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "PolicyCommit is missing ${policyFile}: $resolvedPolicyCommit" }
  }
  $policySourceRef = $resolvedPolicyCommit
}
$payload = Get-Content -Raw -LiteralPath (Join-Path $pluginRoot 'skills\chronos-control-room\scripts\runtime\payload.json') | ConvertFrom-Json
if ($payload.schemaVersion -ne 1 -or [string]$payload.pluginVersion -ne $manifestVersion) {
  throw 'Control Room payload must be regenerated for the declared plugin version.'
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "dist" }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$artifactStem = if ($Edition -eq 'Directory') { "chronos-v$Version-skills-only" } else { "chronos-v$Version" }
$artifactName = "$artifactStem.zip"
$artifactPath = Join-Path $OutputDirectory $artifactName
$checksumPath = Join-Path $OutputDirectory "$artifactStem.sha256"
$releaseManifestPath = Join-Path $OutputDirectory "$artifactStem.release.json"
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
if ($Edition -eq 'Directory') {
  $files = @($files | Where-Object {
    $relative = $_.FullName.Substring($pluginRoot.Length + 1).Replace('\', '/')
    $relative -ne 'hooks/hooks.json' -and $relative -ne 'skills/chronos/scripts/hook-intake.ps1'
  })
}
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

function Get-NormalizedSourceBytes {
  param([System.IO.FileInfo]$File)
  if ($File.Name -eq 'LICENSE' -or $File.Extension.ToLowerInvariant() -in @('.cmd', '.json', '.md', '.ps1', '.yaml', '.yml', '.txt', '.mjs', '.js', '.css', '.html')) {
    $text = [IO.File]::ReadAllText($File.FullName).Replace("`r`n", "`n").Replace("`r", "`n")
    return ,([Text.UTF8Encoding]::new($false).GetBytes($text))
  }
  return ,([IO.File]::ReadAllBytes($File.FullName))
}

function Get-PackagedBytes {
  param([System.IO.FileInfo]$File)
  $isText = $File.Name -eq 'LICENSE' -or $File.Extension.ToLowerInvariant() -in @(
    '.cmd', '.json', '.md', '.ps1', '.yaml', '.yml', '.txt', '.mjs', '.js', '.css', '.html'
  )
  if ($isText) {
    $content = [System.IO.File]::ReadAllText($File.FullName)
    $relative = $File.FullName.Substring($pluginRoot.Length + 1).Replace('\', '/')
    if ($relative -eq 'README.md') {
      $content = $content.Replace('https://github.com/FaxanFM/chronos/blob/main/', "https://github.com/FaxanFM/chronos/blob/$policySourceRef/")
      $content = $content.Replace('--ref v0.9.3', "--ref v$Version")
    }
    if ($relative -eq '.codex-plugin/plugin.json') {
      $versionedManifest = $content | ConvertFrom-Json
      $versionedManifest.interface.privacyPolicyURL = "https://github.com/FaxanFM/chronos/blob/$policySourceRef/PRIVACY.md"
      $versionedManifest.interface.termsOfServiceURL = "https://github.com/FaxanFM/chronos/blob/$policySourceRef/TERMS.md"
      $content = ($versionedManifest | ConvertTo-Json -Depth 12) + "`n"
    }
    if ($Edition -eq 'Directory') {
      $relative = $File.FullName.Substring($pluginRoot.Length + 1).Replace('\', '/')
      if ($relative -eq '.codex-plugin/plugin.json') {
        $directoryManifest = $content | ConvertFrom-Json
        $directoryManifest.PSObject.Properties.Remove('hooks')
        $directoryManifest.description = 'Skills-only edition: guided local Control Room setup, model and thinking-level controls, managed workflows and optional learning, with Windows diagnostics. No lifecycle hooks.'
        $directoryManifest.interface.longDescription = $directoryManifest.interface.longDescription + ' Lifecycle hooks are not included or auto-installed.'
        $directoryManifest.extensions.'com.openai'.onboardingSkill = './skills/chronos-control-room/SKILL.md'
        $content = ($directoryManifest | ConvertTo-Json -Depth 12) + "`n"
      } elseif ($relative -eq 'README.md') {
        $content = @"
# Chronos for Codex - Skills-Only Edition

Version $Version. This Plugin Directory candidate contains the packaged local
Control Room, chronos, and chronos-governor skills plus optional Windows
diagnostics. It has no
lifecycle hook definitions or hook installer. Core governance uses current
local host statuses; missing health evidence remains partial or unsupported.

Start with: Turn my goal and selected framework files into a ready-to-review
Chronos Control Room workflow. Recommend models and thinking levels, explain
permissions, and open it paused.

Setup starts and reopens the local dashboard without a manual server command.
It needs a local Codex executor and Node 22+; the onboarding skill prefers bundled
host tools and reports unsupported prerequisites explicitly. No npm install,
hook patch or scheduled Governor is needed for Control Room. Execution and
isolated writes require session consent; learning pipelines are optional.
Model and thinking-level options come from the connected Codex host. Suggestions
are explicit choices, not cost or quality guarantees. Hover or focus a control
for help; guided setup can prepare the process before you use the editor.
Existing-chat Governor monitoring and Windows diagnostics are separate opt-ins.

Chronos sends no publisher runtime telemetry. Bounded local metadata stays on
this host; compact chat summaries use OpenAI's account data controls. Downloads
and voluntary public support reports reach GitHub. No signup or API key is needed.

The separate GitHub full edition includes five optional reviewed hooks. This
Directory skill does not download or install them after review. Choose that
edition independently through supported controls; never enable both sources.
See https://github.com/FaxanFM/chronos for source, privacy, and installation guidance.
Fully quit and reopen Codex, then use a fresh chat after an install or upgrade.
"@ + "`n"
      } elseif ($relative -like 'skills/*/SKILL.md') {
        if ($relative -eq 'skills/chronos/SKILL.md') {
          $pattern = '(?s)<!-- FULL_EDITION_HOOK_CHOICE_START -->.*?<!-- FULL_EDITION_HOOK_CHOICE_END -->'
          if ([regex]::Matches($content, $pattern).Count -ne 1) { throw 'Missing edition-specific hook choice boundary.' }
          $content = [regex]::Replace($content, $pattern,
            'Directory hook disclosure: no lifecycle hooks are included; fresh session, completed-turn, and subagent event evidence is unavailable. Do not ask the full-edition hook trust question.')
        }
        $heading = ($content -split "`n" | Where-Object { $_ -match '^# ' } | Select-Object -First 1)
        if (-not $heading) { throw "Skill is missing a top-level heading: $relative" }
        $notice = "**Installed edition: skills-only.** No lifecycle hooks or hook installer are included. Use current-host task status and compatible authorized Inspector evidence for core governance. Missing coverage stays partial or unsupported. Do not download or auto-install GitHub hooks from this Directory skill; optional hooks require a separate independent user-directed installation. Hook trust and execution are unavailable in this edition.`n"
        if ($relative -eq 'skills/chronos-control-room/SKILL.md') {
          $notice = "**Installed edition: skills-only.** Control Room and its local launcher are included; lifecycle hooks and a hook installer are not. No hooks or scheduled Governor are needed for this dashboard. Do not download or auto-install GitHub hooks from this Directory skill. Local execution prerequisites and session consent still apply.`n"
        }
        if (-not $content.Contains('**Installed edition: skills-only.**')) {
          $content = $content.Replace("$heading`r`n", "$heading`r`n`r`n$notice").Replace("$heading`n", "$heading`n`n$notice")
        }
      }
    }
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
          source_sha256 = Get-BytesHash (Get-NormalizedSourceBytes $file)
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
  schema_version = 3
  plugin = "chronos"
  version = $Version
  edition = if ($Edition -eq 'Directory') { 'skills_only' } else { 'full' }
  lifecycle_hooks_included = ($Edition -eq 'Full')
  artifact = $artifactName
  sha256 = $artifactHash
  packaged_files = $files.Count
  packaged_bytes = $packagedBytesTotal
  package_limits = [ordered]@{
    files = $maximumFiles
    file_bytes = $maximumFileBytes
    package_bytes = $maximumPackageBytes
  }
  distribution = [ordered]@{
    repository = 'FaxanFM/chronos'
    canonical_identity = 'chronos@openai-curated-remote'
    canonical_source = 'openai-curated-remote'
    legacy_git_identity = 'chronos@chronos'
    plugin_directory_listing = 'plugins_6a79c882cf488191b8f62ee20e0e2571'
  }
  files = @($packagedFileManifest)
  reproducible_timestamp = "1980-01-01T00:00:00Z"
  packaged_text_line_endings = "LF"
}
if ($PolicyCommit) { $releaseManifest.policy_source_ref = $policySourceRef }
[System.IO.File]::WriteAllText(
  $releaseManifestPath,
  (($releaseManifest | ConvertTo-Json -Depth 4) + "`n"),
  [System.Text.UTF8Encoding]::new($false)
)

Write-Output ("CHRONOS RELEASE version={0} artifact={1} sha256={2} files={3}" -f `
  $Version, $artifactPath, $artifactHash, $files.Count)
