param()

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') {
  throw 'Usability validation requires inbox Windows PowerShell 5.1.'
}
$repo = Split-Path -Parent $PSScriptRoot
function Read-Text([string]$Path) { [IO.File]::ReadAllText((Join-Path $repo $Path)) }
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$manifest = Read-Text 'plugins/chronos/.codex-plugin/plugin.json' | ConvertFrom-Json
$fullPrompt = [string]$manifest.interface.defaultPrompt[0]
$directoryPrompt = 'Set up Chronos for my active chats: explain privacy, configure one Governor, and verify scope and Heartbeat coverage.'
$core = Read-Text 'plugins/chronos/skills/chronos/SKILL.md'
$governor = Read-Text 'plugins/chronos/skills/chronos-governor/SKILL.md'
$onboarding = Read-Text 'docs/ONBOARDING.md'
$docs = @('README.md', 'plugins/chronos/README.md') + @(
  Get-ChildItem -LiteralPath (Join-Path $repo 'docs') -Filter '*.md' -File |
    Where-Object { $_.Name -notmatch 'AUDIT|SUBMISSION|^RELEASE-' } |
    ForEach-Object { 'docs/' + $_.Name }
)
foreach ($path in $docs) {
  $text = Read-Text $path
  foreach ($line in ($text -split '\r?\n')) {
    if ($line -match '^\s*(?:codex(?:\.cmd)?|&\s+\$codex)\s+plugin marketplace add FaxanFM/chronos\b') {
      Require ($line -match '\s--ref\s+\S+') "Unpinned installation example: $path"
    }
  }
  $normalized = ($text -replace '(?m)^\s*>\s*', '' -replace '\*\*', '' -replace '\s+', ' ')
  foreach ($match in [regex]::Matches($normalized, 'Set up Chronos[^.!?]*[.!?]')) {
    Require ($match.Value -eq $fullPrompt -or $match.Value -eq $directoryPrompt) "Setup prompt differs from its edition: $path; $($match.Value)"
  }
}
foreach ($text in @($core, $governor)) {
  Require ($text.Contains('automaticDiagnosticsAllowed=yes')) 'Missing affirmative diagnostics gate.'
  Require (($text -replace '\s+', ' ').Contains('setup chat before')) 'Onboarding must finish in the setup chat.'
}
Require ($core.Contains('Skip briefing plus on-request')) 'Skipped briefing regression scenario missing.'
Require ($core.Contains('A one-off briefing is not standing permission')) 'One-off consent must not become standing consent.'
Require ($governor.Contains('Absent diagnostic permission means no')) 'Governor assignment must fail closed on missing diagnostic permission.'
Require ($core.Contains('If Sol is not advertised')) 'Missing supported-model fallback choice.'
Require ($governor.Contains('final approved supported model')) 'Governor creation ignores the chosen model.'
foreach ($term in @('overall health', 'quota risk', 'top contributor', 'recommended action', 'what was not checked',
  'agent stalls', 'runaway review', 'unusual usage burn', 'session growth', 'test regressions', 'machine drift',
  'task dependencies', 'build-state changes', 'Eight unsupported families means eight not evaluated', 'Check or pause:')) {
  Require ($core.Contains($term)) "Missing human-facing result or coverage term: $term"
}
Require (-not $core.Contains('Return only the compact')) 'Raw output must not be the default user answer.'
Require ($onboarding.Contains('Health evidence:') -and $onboarding.Contains('Check or pause:')) 'Human receipt missing from onboarding guide.'
foreach ($path in @('README.md', 'plugins/chronos/README.md', 'docs/ARCHITECTURE.md')) {
  $text = Read-Text $path
  Require (-not ($text -match 'request asynchronous|no machine-derived data')) "Stale hook or identity claim: $path"
}
$issue = Read-Text '.github/ISSUE_TEMPLATE/bug-report.yml'
Require ($issue.Contains('placeholder: ' + $manifest.version)) 'Bug report version is stale.'
foreach ($field in @('codex_version', 'edition', 'hook_state')) {
  Require ($issue.Contains('id: ' + $field)) "Missing support field: $field"
}
Require ($issue.Contains('installation failure')) 'Install failures must be reportable.'
Require ((Read-Text 'PRIVACY.md').Contains('unsalted SHA-256 hashes of the Windows account SID')) 'Missing hash privacy disclosure.'
Require ($manifest.description.Contains('Windows only')) 'Listing must disclose platform support.'
Require ((Read-Text 'CHANGELOG.md').Contains('## v0.9.3')) 'Missing v0.9.3 changelog.'
Require ((Read-Text 'CHANGELOG.md') -match '(?s)## v0\.9\.4.*?Hooks: unchanged') 'Missing current hook-change notice.'
Require ($core.Contains('336-cycle or 14-day') -and $core.Contains('recurrence pauses')) 'Rotation disclosure missing.'
Require ((Read-Text '.github/ISSUE_TEMPLATE/question.yml').Contains('This is public')) 'Question route must disclose public sharing.'

foreach ($path in @('plugins/chronos/skills/chronos/scripts/chronos.ps1',
  'plugins/chronos/skills/chronos/scripts/session-registry.ps1', 'scripts/build-release.ps1')) {
  $errors = $null
  [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $path), [ref]$null, [ref]$errors) | Out-Null
  Require (-not $errors) "PowerShell parse failure: $path"
}

# Recommendation availability is explicit in a fresh native status, with no real account state.
$root = Join-Path ([IO.Path]::GetTempPath()) ('chronos-usability-' + [guid]::NewGuid().ToString('N'))
$fixtureHome = Join-Path $root 'home'
New-Item -ItemType Directory -Path $fixtureHome -Force | Out-Null
$oldHome = $env:CODEX_HOME
try {
  $env:CODEX_HOME = $fixtureHome
  $native = Join-Path $repo 'plugins/chronos/skills/chronos/scripts/chronos.ps1'
  $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $native -Action supervise -SupervisionAction status)
  Require ($LASTEXITCODE -eq 0) 'Fresh native status failed.'
  $payload = ($output -join "`n").Substring('CHRONOS SUPERVISION '.Length) | ConvertFrom-Json
  Require ($payload.ok -and $payload.recommendedGovernorModelRequiresHostAdvertisement) 'Native recommendation lacks availability caveat.'
} finally { $env:CODEX_HOME = $oldHome }
Write-Output 'PASS: usability contracts, edition prompts, consent, output, privacy, support and native recommendation caveat.'
