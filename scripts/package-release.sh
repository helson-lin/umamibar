#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/verify-app.sh
DMG_PYTHON="${DMG_PYTHON:-python3}"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$(printf '%s' "$SIGNING_IDENTITY" | python3 -c 'import sys; print(sys.stdin.read().strip())')"
fi
if ! "$DMG_PYTHON" -c 'import dmgbuild' 2>/dev/null; then
  echo 'Install DMG tooling: python3 -m venv /tmp/umamibar-dmg-tools && /tmp/umamibar-dmg-tools/bin/pip install -r scripts/requirements-dmg.txt' >&2
  echo 'Then run with DMG_PYTHON=/tmp/umamibar-dmg-tools/bin/python' >&2
  exit 1
fi
VERSION="$(cat VERSION)"
ARCHIVE="UmamiBar-${VERSION}-universal.zip"
DMG="UmamiBar-${VERSION}-universal.dmg"
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  : "${SIGNING_IDENTITY:?Developer ID Application signing identity required}"
  : "${NOTARY_PROFILE:?Notarytool keychain profile required}"
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then echo 'Notarization requires Developer ID signing' >&2; exit 1; fi
  codesign --verify --strict --deep -R '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' dist/UmamiBar.app
  # Notarize and staple the app before creating either distribution container.
  ditto -c -k --keepParent --norsrc dist/UmamiBar.app dist/notary-app.zip
  ./scripts/notarize.sh dist/notary-app.zip dist/UmamiBar.app
  rm dist/notary-app.zip
  spctl --assess --type execute --verbose=2 dist/UmamiBar.app
fi
# Keep the app bundle and signature intact; avoid Finder resource files.
ditto -c -k --keepParent --norsrc dist/UmamiBar.app "dist/$ARCHIVE"
# dmgbuild writes Finder metadata without requiring a GUI session in CI.
"$DMG_PYTHON" -m dmgbuild -s scripts/dmg-settings.py "UmamiBar $VERSION" "dist/$DMG"
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  SIGNING_ARGS=(--force --timestamp --sign "$SIGNING_IDENTITY")
  if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then SIGNING_ARGS+=(--keychain "$SIGNING_KEYCHAIN"); fi
  codesign "${SIGNING_ARGS[@]}" "dist/$DMG"
  codesign --verify --strict "dist/$DMG"
  ./scripts/notarize.sh "dist/$DMG" "dist/$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "dist/$DMG"
fi
hdiutil verify "dist/$DMG"
(cd dist && shasum -a 256 "$ARCHIVE" "$DMG" > SHA256SUMS)
if [[ -n "${RELEASE_TAG:-}" ]]; then
  : "${RELEASE_REPOSITORY:?RELEASE_REPOSITORY is required when generating a release appcast}"
  : "${SPARKLE_EDDSA_PRIVATE_KEY:?SPARKLE_EDDSA_PRIVATE_KEY is required to sign update archives}"
  TOOL="$(find "${TMPDIR:-/tmp}/umamibar-release/spm-intel/artifacts" -path '*/Sparkle/bin/generate_appcast' -print -quit)"
  if [[ -z "$TOOL" ]]; then echo 'Sparkle generate_appcast tool not found' >&2; exit 1; fi
  rm -rf dist/updates dist/appcast.xml
  mkdir -p dist/updates
  cp "dist/$ARCHIVE" dist/updates/
  printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" | "$TOOL" --ed-key-file - --maximum-deltas 0 --download-url-prefix "https://github.com/$RELEASE_REPOSITORY/releases/download/$RELEASE_TAG/" dist/updates
  cp dist/updates/appcast.xml dist/appcast.xml
fi
echo "Packaged dist/$ARCHIVE and dist/$DMG"
