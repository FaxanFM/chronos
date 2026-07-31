# Release, Upgrade, And Rollback

## Reproducible Build

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1
```

The builder sorts package entries, assigns a fixed ZIP timestamp, excludes
repository-only files, and writes the ZIP, SHA-256 checksum, and release
manifest to `dist`. `tests/release.tests.ps1` builds twice and requires identical
artifact hashes.

## Published Release

A `vX.Y.Z` tag must exactly match `.codex-plugin/plugin.json`. The tag workflow
runs every test, rebuilds the package, creates an official GitHub artifact
attestation with `actions/attest@v4`, and publishes all artifacts. A failed test,
version mismatch, reproducibility failure, or attestation failure prevents the
release.

See GitHub's [artifact-attestation documentation](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
for the provenance and verification model.

Verify a downloaded artifact:

```powershell
Get-FileHash .\chronos-v0.5.2.zip -Algorithm SHA256
gh attestation verify .\chronos-v0.5.2.zip -R FaxanFM/chronos
```

Compare the first command with `chronos-v0.5.2.sha256`. Artifact attestations
prove GitHub Actions provenance; they do not replace local source review.

## Upgrade

Fully close Codex before replacing an installed plugin. Then refresh the public
marketplace and reinstall Chronos through the Codex plugin manager:

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new task and confirm that the installed plugin reports the expected
version. v0.5.2 automatically migrates inactive Governor v1 state. It fails
closed when legacy state contains an active lease; finish or release that work
with the previous version before retrying.

## Rollback

Fully close Codex. Install the desired prior tagged release or restore the prior
plugin cache, then open a new task. Do not edit Governor state to force a
rollback. v0.5.2 state is version 2 and older Governor versions may not
understand it; preserve it for audit and begin delegation only after confirming
the selected version's state behavior. Rollback never requires changing the
Codex diagnostic SQLite database or deleting user work.
