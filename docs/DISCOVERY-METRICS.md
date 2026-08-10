# Discovery Metrics

Chronos does not collect install or usage telemetry. Adoption checks use only
aggregate GitHub repository metrics and public opt-in signals.

## Baseline

Recorded August 9, 2026 from GitHub Insights for the preceding 14 days:

| Signal | Count |
| --- | ---: |
| Clones | 212 |
| Unique cloners | 94 |
| Repository views | 104 |
| Unique visitors | 7 |
| Stars | 1 |
| Forks | 0 |

Referrers with at least one recorded visit included GitHub, `t.co`, Bing, and
Google.

## Interpretation Boundaries

- A clone is not an installation or an active user.
- Unique cloners can include CI runners, marketplace refreshes, automation,
  cache misses, disposable environments, and people cloning more than once
  through identities GitHub counts separately.
- Repository views and unique visitors measure GitHub pages, not local plugin
  execution.
- Stars, forks, and sanitized-result issues are public opt-in signals, not
  comprehensive usage measures.
- Do not estimate users, retention, savings, incidents prevented, or conversion
  rates from clone counts alone.

## Checkpoints

At 7 and 14 days after the v0.7.2 discovery update, record:

- the same six GitHub signals;
- search rank for `Chronos for Codex` and `chronos codex diagnostics windows`;
- Plugin Directory draft, review, approval, and publication status;
- count of privacy-checked public result reports;
- material referrer changes without recording visitor identities.

Chronos itself must remain telemetry-free. Do not add an analytics endpoint,
install beacon, background task, unique identifier, or phone-home behavior to
improve these measurements.

## Metadata Correction

On August 10, 2026, the public GitHub About description was corrected from the
v0.2 helper-process-only copy to the current diagnostics and worker-governance
scope. Discovery topics were expanded without adding telemetry. Immediately
after the update, GitHub repository search returned `FaxanFM/chronos` for
`Codex diagnostics worker governance Windows`; it had returned no results for
the comparable generic query before the correction. Search indexing can change,
so this is a point-in-time discoverability check rather than an adoption claim.
