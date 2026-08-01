# Calibration Methodology

This document defines evidence required for a future calibration release. It
does not enable collection, telemetry, or threshold changes in v0.5.4.

## Freeze

Until the study below is complete, do not change warning thresholds, critical
thresholds, scoring weights, predictive claims, heuristic interpretation, or
other calibration-sensitive behavior. Reliability changes and calibration
changes must ship in separate releases.

## Study Window

Collect at least 14 consecutive days of manually initiated, labeled observations
from long-running sessions. Define labels before examining aggregate outcomes.
Chronos itself must not upload or retain observations.

## Labels

Each observation receives one operator label:

- `no_degradation`: normal interaction and filesystem response.
- `transient_lag`: a short delay that fully recovers without restart.
- `progressive_lag`: recurring delays whose duration or frequency increases.
- `filesystem_helper_failure`: known filesystem operations fail or remain
  unavailable.
- `app_restart_recovery`: fully quitting and reopening Codex restores operation.
- `pc_restart_recovery`: only a Windows restart restores filesystem operation.
- `unrelated_system_pressure`: evidence points to a non-Codex workload.
- `indeterminate`: evidence is insufficient or conflicting.

## Allowed Metadata

Record only the Chronos aggregate output plus coarse runtime version, model
class, reasoning effort, task count, session-duration band, workload category,
restart outcome, and operator label. Do not record source, prompts, responses,
tool arguments, tool output, secrets, personal data, usernames, absolute paths,
repository names, customer names, or proprietary identifiers.

Review every record before sharing. Replace task and machine references with
random study IDs, use coarse time bands, remove rare free text, and publish only
aggregates when small groups could be identifying.

## Evaluation

Predeclare the candidate thresholds and primary endpoint. Report confusion
matrices, precision, recall, false-positive rate, false-negative rate, threshold
sensitivity, sample counts, missing-data rate, runtime/workload strata, and the
operational cost of unnecessary versus missed restart advice.

Do not claim prediction when the data supports only association. Publish the
sanitized method, exclusions, limitations, and negative results. Any resulting
heuristic change belongs in a later calibration-only release.
