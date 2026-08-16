# Releasing Bubbl

Bubbl is installed only from public, immutable releases in `BubbleBuffer/Bubbl`. Release archives are self-contained Codex marketplaces, and every downloadable asset is bound to its source commit by a GitHub artifact attestation.

## One-time repository setup

1. Create the public `BubbleBuffer/Bubbl` repository with `main` as its default branch.
2. Enable immutable releases.
3. Protect `main`: require pull requests, required CI checks, resolved reviews, and no force pushes or deletion.
4. Create a protected `release` environment and require a maintainer approval before deployment.
5. Enable secret scanning and push protection.
6. Permit GitHub Actions to create attestations. Keep the workflow's explicit `contents`, `id-token`, and `attestations` permissions; do not grant repository-wide write permissions.

These settings are part of the security model. Do not publish until they are active.

## Local release gate

Use only disposable canaries in tests, logs, and screenshots. The release commit must contain the same `X.Y.Z` version in `Cargo.toml`, `Cargo.lock`, `.codex-plugin/plugin.json`, and `CHANGELOG.md`.

```powershell
cargo fmt --all -- --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked --all-targets --all-features
cargo check --locked --all-targets
cargo audit
.\scripts\verify-release.ps1
```

The Rust plugin tests and `verify-release.ps1` validate the repository-owned manifest, hook, skill, and marketplace metadata without relying on a machine-specific Codex installation.

Simulate the Windows package and installer without touching the global Codex configuration:

```powershell
cargo build --release --locked --target x86_64-pc-windows-msvc
$commit = git rev-parse HEAD
.\scripts\package-plugin.ps1 -Target x86_64-pc-windows-msvc -Binary .\target\x86_64-pc-windows-msvc\release\bubl.exe -Format zip -SourceCommit $commit -SourceRef refs/tags/v1.0.5
.\scripts\validate-package.ps1 -PackageRoot .\target\package\bubbl-1.0.5-x86_64-pc-windows-msvc -ExpectedTarget x86_64-pc-windows-msvc -ExpectedCommit $commit
.\scripts\test-installers.ps1 -Archive .\dist\bubbl-1.0.5-x86_64-pc-windows-msvc.zip -ExpectedCommit $commit
```

## Publish

1. Merge the reviewed, green release commit into `main` and ensure the worktree is clean.
2. Create and push an annotated `vX.Y.Z` tag that points to that commit.
3. The tag-only `Release` workflow confirms the tag is on `main`, rebuilds all four targets on GitHub-hosted runners, validates each marketplace, creates checksums, attests every final asset, and creates a draft release.
4. Inspect the draft, then approve the protected `release` environment. The gated job verifies the draft asset set and publishes it. With immutable releases enabled, publication locks the tag and assets and adds GitHub's release attestation.
5. Verify from a clean directory, then perform the disposable canary flow in a new Codex task.

Publishing also starts the `Published release smoke` workflow on native Windows,
Linux, Intel macOS, and Apple Silicon macOS runners. It installs the public
release through the current Codex CLI, verifies the registered marketplace and
plugin, exercises hook sanitization plus stdin and environment delivery, rejects
reference reuse, and repeats the install in strict attestation mode. The same
matrix checks the latest release every Monday and can be run manually. A human
must still review and trust the hook in the Codex UI before the final canary.

Do not create a release manually, reuse assets from a local build, replace a published asset, or offer a repository clone as an installation route.

## Independent verification

For `v1.0.5` on Windows x64:

```powershell
gh release verify v1.0.5 --repo BubbleBuffer/Bubbl
gh release download v1.0.5 --repo BubbleBuffer/Bubbl --pattern bubbl-1.0.5-x86_64-pc-windows-msvc.zip --pattern SHA256SUMS.txt
gh release verify-asset v1.0.5 .\bubbl-1.0.5-x86_64-pc-windows-msvc.zip --repo BubbleBuffer/Bubbl
$commit = gh api repos/BubbleBuffer/Bubbl/commits/v1.0.5 --jq .sha
gh attestation verify .\bubbl-1.0.5-x86_64-pc-windows-msvc.zip --repo BubbleBuffer/Bubbl --signer-workflow github.com/BubbleBuffer/Bubbl/.github/workflows/release.yml --source-ref refs/tags/v1.0.5 --source-digest $commit --deny-self-hosted-runners
Get-FileHash -Algorithm SHA256 .\bubbl-1.0.5-x86_64-pc-windows-msvc.zip
```

Compare the resulting lowercase digest to the archive's line in `SHA256SUMS.txt`. The archive's `BUILD-INFO.json` must name `BubbleBuffer/Bubbl`, `v1.0.5`, the expected target, and the same full commit reported by `gh api repos/BubbleBuffer/Bubbl/commits/v1.0.5 --jq .sha`.
