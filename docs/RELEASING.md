# Releases and Homebrew

## Pipelines

- **CI** runs on branch pushes, pull requests, manual dispatch, and as a reusable release prerequisite. Swift tests and universal packaging run on Apple Silicon (`macos-15`) and Intel (`macos-15-intel`). Artifacts are retained for 14 days.
- **Release** runs for stable tags such as `v0.1.0`. The tag must match `VERSION`. After CI passes, it publishes a universal DMG, ZIP, `SHA256SUMS`, and a generated `umamibar.rb` Cask.
- **Homebrew update** opens a PR adding/updating `Casks/umamibar.rb` on the default branch, with the exact release URL and archive SHA-256. Merge the PR to update the tap. No checksum placeholder is used.
- **Dependabot** proposes weekly updates to GitHub Actions; actions are pinned by commit SHA.

The workflows use the repository's `GITHUB_TOKEN`, with read-only permissions by default. Only publishing and Cask update jobs request write permissions. Fork PRs do not receive release secrets or write tokens.

## Download a CI build

Push any branch, open a pull request, or open Actions → CI → **Run workflow** and select a branch. No version tag or signing secrets are required for CI packaging. After a successful run, use the download links in the run summary or the **Artifacts** section. GitHub requires signing in to download artifacts.

Choose `UmamiBar-macos-15` or `UmamiBar-macos-15-intel`; each contains an Intel + Apple Silicon universal DMG, ZIP, and `SHA256SUMS`. Extract the artifact first, then verify the packages with `shasum -a 256 -c SHA256SUMS` from that directory. Open the DMG and drag `UmamiBar.app` to the Applications shortcut. The ZIP remains available for Homebrew and manual extraction. CI artifacts expire after 14 days; tagged releases provide persistent downloads. CI builds use the same ad-hoc signing described below.

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

## Download and install

Download `UmamiBar-<version>-universal.dmg` from [GitHub Releases](https://github.com/helson-lin/umamibar/releases/latest). Open it, drag **UmamiBar.app** onto **Applications**, then eject the disk image and launch the app from Applications. The DMG supports both Intel and Apple Silicon. New releases use the signed and notarized pipeline below once credentials are configured. Existing unnotarized builds may still be blocked by macOS.

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

## Developer ID signing and notarization

Public tagged releases require an Apple Developer Program membership and a **Developer ID Application** certificate with its private key. Export that identity from Keychain Access as a password-protected `.p12`. Do not use an Apple Development or Mac App Distribution certificate.

Configure these repository Actions secrets (never commit the files or credentials):

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | Base64 of the exported `.p12` (for example, `base64 -i DeveloperID.p12 | pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `MACOS_SIGNING_IDENTITY` | Full `Developer ID Application: Name (TEAMID)` identity or its SHA-1 fingerprint from `security find-identity -v -p codesigning` |
| `APPLE_ID` | Apple developer account email |
| `APPLE_TEAM_ID` | Developer team ID matching the certificate |
| `APPLE_APP_PASSWORD` | Apple ID app-specific password for notarization |

The release job imports the identity into a temporary keychain, enables Hardened Runtime and secure timestamps, and checks the certificate's team. It submits the app ZIP with `notarytool`, requires `Accepted`, staples and validates the app ticket, then creates the final ZIP and DMG. It signs, notarizes, and staples the DMG too. Gatekeeper assessments must pass before checksums and publication. Credentials are deleted with an `always()` cleanup step. Missing secrets or failed notarization stop the release; there is no ad-hoc fallback for public releases.

Ordinary CI and local builds remain ad-hoc signed and unnotarized by default. For a local notarized build, import the Developer ID certificate and store credentials with `xcrun notarytool store-credentials umamibar-release`. Export `SIGNING_IDENTITY` and `NOTARY_PROFILE=umamibar-release`, build the app, then run packaging with `NOTARIZE=1` and the `DMG_PYTHON` below. If using a custom keychain, export its path as `SIGNING_KEYCHAIN` and add it to your keychain search list first.

See Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). The Cask never disables quarantine or changes security settings. Existing releases remain unchanged; publish a new version to distribute notarized packages.

## Local verification

```sh
./scripts/build-app.sh
python3 -m venv /tmp/umamibar-dmg-tools
/tmp/umamibar-dmg-tools/bin/python -m pip install -r scripts/requirements-dmg.txt
DMG_PYTHON=/tmp/umamibar-dmg-tools/bin/python ./scripts/package-release.sh
python3 scripts/generate-cask.py \
  --repository helson-lin/umamibar \
  --version "$(cat VERSION)" \
  --archive "dist/UmamiBar-$(cat VERSION)-universal.zip"
ruby -c dist/umamibar.rb
python3 -m unittest discover -s tests-release -v
```

The Cask generated locally is a validation artifact. Publish the exact ZIP before committing a Cask that points to it. CI checks both architectures, minimum deployment versions, bundle version, signature, icon, and absence of a WebKit dependency.

The DMG includes a Retina background with bilingual drag-to-install instructions and fixed icon positions. Its Finder layout is written by `dmgbuild` without a GUI session. To regenerate the background after editing `scripts/generate-dmg-background.swift`:

```sh
xcrun swiftc -module-cache-path /tmp/umamibar-module-cache scripts/generate-dmg-background.swift -o /tmp/umamibar-dmg-background
/tmp/umamibar-dmg-background
```
