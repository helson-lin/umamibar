# Releases and Homebrew

## Pipelines

- **CI** runs on branch pushes, pull requests, manual dispatch, and as a reusable release prerequisite. Swift tests and universal packaging run on Apple Silicon (`macos-15`) and Intel (`macos-15-intel`). Artifacts are retained for 14 days.
- **Release** runs for stable tags such as `v0.1.0`. The tag must match `VERSION`. After CI passes, it publishes a universal ZIP, `SHA256SUMS`, and a generated `umamibar.rb` Cask.
- **Homebrew update** opens a PR adding/updating `Casks/umamibar.rb` on the default branch, with the exact release URL and archive SHA-256. Merge the PR to update the tap. No checksum placeholder is used.
- **Dependabot** proposes weekly updates to GitHub Actions; actions are pinned by commit SHA.

The workflows use the repository's `GITHUB_TOKEN`, with read-only permissions by default. Only publishing and Cask update jobs request write permissions. Fork PRs do not receive release secrets or write tokens.

## Repository setup

Repository: <https://github.com/helson-lin/umamibar>

1. Enable GitHub Actions.
2. Under Settings → Actions → General → Workflow permissions, enable **Allow GitHub Actions to create and approve pull requests** if you want automatic Cask PR creation. The workflow does not approve or merge PRs.
3. For branch protection, require both `Test and build` jobs. Permit the automation to push its own `automation/homebrew-v*` branches.
4. Protect version tags so only maintainers can trigger public releases.

No personal access token or separate tap repository is needed. The source repository doubles as a Homebrew tap via an explicit URL.

## Publish a version

Update `VERSION` and commit your changes first. Use stable numeric versions only; prerelease tags are intentionally rejected.

```sh
git add VERSION
git commit -m "chore: release 0.1.0"
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

The commands above illustrate the first release. Skip the version commit if that version is already committed. For the next release, use `0.1.1` / `v0.1.1` consistently. Never move a published version tag or change an existing release archive; publish a new version instead.

`CFBundleShortVersionString` comes from `VERSION`; `CFBundleVersion` comes from the Actions run number (local builds default to `1`). The app ZIP preserves the bundle structure and signature using `ditto`.

After the release workflow finishes, review and merge the Homebrew update PR. GitHub may suppress new workflow runs for PRs created using `GITHUB_TOKEN`; run CI manually if branch rules require a fresh check on that automation PR.

If Cask PR creation is disabled or blocked, the release itself remains published. Download `umamibar.rb` from that release, commit it to `Casks/`, and open a PR manually. Do not substitute a local build's checksum for a published archive's checksum.

## Install and upgrade

After the first release and Cask PR are published/merged:

```sh
brew tap helson-lin/umamibar https://github.com/helson-lin/umamibar
brew install --cask helson-lin/umamibar/umamibar
```

Upgrade:

```sh
brew update
brew upgrade --cask helson-lin/umamibar/umamibar
```

Uninstall:

```sh
brew uninstall --cask helson-lin/umamibar/umamibar
```

`brew uninstall --cask --zap helson-lin/umamibar/umamibar` additionally removes app preferences. The API key in macOS Keychain is not deleted by the Cask.

The app's Intel binary targets macOS 10.15. Homebrew's own supported-system policy is separate; installation through Homebrew is not a promise that Homebrew itself supports Catalina. Older systems can use the release ZIP directly.

## Signing and distribution limits

Current builds are **ad-hoc signed and not notarized**. GitHub CI and SHA-256 verify build integrity, not Apple developer identity or Gatekeeper acceptance. The Cask does not disable quarantine, strip security attributes, or weaken system protections. macOS may block launch.

For a notarized public distribution, add a Developer ID signing identity and Apple notarization credentials through repository secrets, sign with hardened runtime, submit with `notarytool`, and staple the result **before creating the release ZIP and checksum**. This signing/notarization path is not yet automated; do not present the current release as notarized.

## Local verification

```sh
./scripts/build-app.sh
./scripts/package-release.sh
python3 scripts/generate-cask.py \
  --repository helson-lin/umamibar \
  --version "$(cat VERSION)" \
  --archive "dist/UmamiBar-$(cat VERSION)-universal.zip"
ruby -c dist/umamibar.rb
python3 -m unittest discover -s tests-release -v
```

The Cask generated locally is a validation artifact. Publish the exact ZIP before committing a Cask that points to it. CI checks both architectures, minimum deployment versions, bundle version, signature, icon, and absence of a WebKit dependency.
