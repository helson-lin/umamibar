#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-dist/UmamiBar.app}"
BIN="$APP/Contents/MacOS/UmamiBar"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
ARCHS="$(lipo -archs "$BIN")"
for arch in x86_64 arm64; do
  case " $ARCHS " in *" $arch "*) ;; *) echo "Missing architecture: $arch" >&2; exit 1 ;; esac
done
for pair in 'x86_64 10.15' 'arm64 11.0'; do
  read -r arch minimum <<< "$pair"
  xcrun vtool -arch "$arch" -show-build "$BIN" | awk -v expected="$minimum" '$1 == "minos" { found=1; if ($2 != expected) exit 1 } END { if (!found) exit 1 }'
done
if otool -L "$BIN" | grep -q 'WebKit.framework'; then echo 'Unexpected WebKit dependency' >&2; exit 1; fi
ACTUAL="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
test "$ACTUAL" = "$(cat VERSION)"
test -s "$APP/Contents/Resources/AppIcon.icns"
echo "Universal app verification passed ($ACTUAL)."
