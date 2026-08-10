# Release, Upgrade, And Rollback

## Reproducible Build

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1
```

The builder packages only tracked plugin files, rejects untracked plugin input
and reparse ancestors, sorts entries, assigns a fixed ZIP timestamp, and writes
the ZIP, SHA-256 checksum, and a per-file hash/size manifest to `dist`.
`tests/release.tests.ps1` builds twice and requires identical artifact hashes.

## Published Release

A `vX.Y.Z` tag must exactly match `.codex-plugin/plugin.json`. Before creating a
tag, enable **Release immutability** in the repository's GitHub settings. This
setting applies only to releases published after it is enabled.

See GitHub's [immutable-release settings](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes)
and [immutable-release model](https://docs.github.com/en/enterprise-cloud@latest/code-security/concepts/supply-chain-security/immutable-releases)
for the repository control and its guarantees.

The release commit and annotated tag must both carry cryptographic signatures
that GitHub reports as `Verified`. The tag workflow rejects lightweight tags,
unverified tag signatures, and unverified release commits. Verify locally before
pushing when the signer's public key is available:

```powershell
git verify-commit HEAD
git verify-tag v0.7.4
```

See GitHub's [commit and tag signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
for supported signing formats and the meaning of `Verified`.

The workflow runs every test on two Windows runner labels in an unprivileged
job. A separate publication job rebuilds the package, creates an official
GitHub artifact attestation with a commit-pinned action, and verifies that
attestation before creating a draft release. It publishes the complete draft
once and then verifies the immutable release and each asset. Release immutability then
prevents its tag or assets from being moved, modified, or deleted while the
release exists. A failed signature check, test, version check, reproducibility
check, or attestation prevents publication.

See GitHub's [artifact-attestation documentation](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
for the provenance and verification model.

Verify a downloaded artifact:

```powershell
Get-FileHash .\chronos-v0.7.4.zip -Algorithm SHA256
gh attestation verify .\chronos-v0.7.4.zip -R FaxanFM/chronos
gh release verify v0.7.4 -R FaxanFM/chronos
gh release verify-asset v0.7.4 .\chronos-v0.7.4.zip -R FaxanFM/chronos
```

The `gh release` checks follow GitHub's [release-integrity verification](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/verify-release-integrity)
procedure.

Compare the first command with `chronos-v0.7.4.sha256`. These controls prove
different things: commit and tag signatures identify the signer; reproducible
builds and checksums bind source to bytes; artifact attestations record the
GitHub Actions build provenance; and release immutability binds the published
tag, commit, and assets. None replaces local source review.

## Upgrade

Fully close Codex before replacing an installed plugin. Then refresh the public
marketplace and reinstall Chronos through the Codex plugin manager:

```powershell
codex.cmd plugin marketplace add FaxanFM/chronos
codex.cmd plugin add chronos@chronos
```

Open a new task and confirm that the installed plugin reports the expected
version. Open tasks can retain the versioned skill locator captured when the
task started. If an older task reports that its former cache path is missing,
that is stale task catalog state rather than evidence that the newly listed
version is absent. Chronos cannot repair this from inside a skill that did not
load. Do not create a compatibility copy, junction, or symbolic link under the
old version because that would execute newer code under a false version label.

v0.7.4 retains disabled shared-folder write delegation. Inactive Governor
version 1 or 2 state can migrate from Git
metadata into its sandbox-writable per-user state store. It fails closed when
legacy state contains an active lease; finish or release that work with the
previous version before retrying.

If Governor returns `state_store_unreadable`, `state_read_failed`,
`state_invalid_json`, or `state_schema_invalid`, preserve its state and continue
the task as coordinator. Do not delete or edit state to force recovery. Report
the compact result only. An `internal_error` now includes a privacy-safe
`failure_stage` and exception class, but never the exception message, local
path, or state content.

## Rollback

Fully close Codex. Install the desired prior tagged release or restore the prior
plugin cache, then open a new task. Do not edit Governor state to force a
rollback. v0.5.4 state is version 3 and older Governor versions may not
understand it; preserve it for audit and begin delegation only after confirming
the selected version's state behavior. Rollback never requires changing the
Codex diagnostic SQLite database or deleting user work.
