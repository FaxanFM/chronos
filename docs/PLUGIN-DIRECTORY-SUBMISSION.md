# OpenAI Plugin Directory Submission Packet

Status: ready for publisher submission; official listing not yet approved.

OpenAI describes the Plugin Directory as the primary discovery surface across
ChatGPT and Codex. Chronos remains installable from its public Codex marketplace
while directory review is pending.

## Listing

Name: Chronos

Category: Productivity

Tagline: Codex diagnostics and read-worker coordination for Windows.

Short description:

> Detect runaway auto-review, approval loops, quota and context amplification,
> broken permission rules, rollout duplication, diagnostic SQLite churn, and
> Windows degradation. Coordinate bounded read-only workers with no telemetry.

Long description:

> Chronos is an on-demand local diagnostic and coordination plugin for people
> running long-lived or parallel Codex work on Windows. It separates current
> machine health from workflow, quota, rule, rollout, and diagnostic-database
> conditions; reports explicit evidence windows and unavailable data; recommends
> proportionate recovery; and coordinates bounded read-only workers selected
> from the active runtime inventory. Chronos does not modify Codex, terminate
> processes, stop tasks, alter SQLite, run in the background, or send telemetry.

Publisher: FaxanFM

Repository: https://github.com/FaxanFM/chronos

Privacy: https://github.com/FaxanFM/chronos/blob/main/PRIVACY.md

Terms: https://github.com/FaxanFM/chronos/blob/main/TERMS.md

Support: https://github.com/FaxanFM/chronos/issues

License: MIT

Platforms: Windows; Codex plugin runtime.

## Reviewer prompts

1. `Use Chronos to inspect current Codex health.`
2. `Use Chronos to explain the difference between machine health and overall diagnostics.`
3. `Use Chronos Governor to plan one bounded read-only documentation review.`

The third prompt requires an active Git repository and a runtime-advertised
compatible worker model. A coordinator decision is an expected safe outcome
when those prerequisites are unavailable.

## Assets

- Composer icon: `plugins/chronos/assets/chronos-mark.png`
- Social preview: `assets/chronos-social-preview.png`
- 9:16 sanitized proof card: `assets/chronos-proof-card.png`
- Proof-card source: `assets/chronos-proof-card.html`

The proof card is synthetic and contains no real machine, account, repository,
task, or session data.

## Review evidence

- Plugin manifest: `plugins/chronos/.codex-plugin/plugin.json`
- Privacy policy: `PRIVACY.md`
- Terms: `TERMS.md`
- Architecture and safety model: `docs/ARCHITECTURE.md`
- Deterministic validation inventory: `docs/TEST-COVERAGE.md`
- Reproducible release and rollback: `docs/OPERATIONS.md`
- Security reporting: `SECURITY.md`

Release artifacts include a checksum and per-file manifest. The GitHub release
workflow requires a GitHub-verified signed commit and signed annotated tag,
builds reproducibly, creates an artifact attestation, and verifies the release
after publication.

## Publisher checklist

- Submit the repository through the current authenticated Plugin Directory
  publisher interface.
- Use the listing text and assets above without adding unsupported performance,
  SSD-wear, billing, or predictive claims.
- Confirm that the directory resolves the marketplace plugin `chronos@chronos`.
- Exercise all three reviewer prompts on Windows.
- Record the submission URL, review status, and any reviewer feedback below.

Submission URL: pending

Submitted at: pending

Review status: not submitted

OpenAI reviewer notes: none

The public OpenAI help article describes directory discovery but does not expose
a stable unauthenticated publisher-form URL. The final publisher action must use
the current authenticated product interface; this document deliberately does
not invent or preserve an unverified submission endpoint.
