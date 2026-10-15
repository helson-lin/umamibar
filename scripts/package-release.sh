#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/verify-app.sh
VERSION="$(cat VERSION)"
ARCHIVE="UmamiBar-${VERSION}-universal.zip"
# Keep the app bundle and signature intact; avoid Finder resource files.
ditto -c -k --keepParent --norsrc dist/UmamiBar.app "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
echo "Packaged dist/$ARCHIVE"
