#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-universal}"
if [[ "$MODE" != "universal" && "$MODE" != "native" ]]; then echo "Usage: $0 [universal|native]" >&2; exit 1; fi
APP_VERSION="$(cat VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then echo "Invalid VERSION or BUILD_NUMBER" >&2; exit 1; fi
ROOT="$PWD"
BUILD="${TMPDIR:-/tmp}/umamibar-release"
# Start from an empty bundle so files from earlier builds never ship.
rm -rf "$ROOT/dist/UmamiBar.app"
mkdir -p "$ROOT/dist/UmamiBar.app/Contents/MacOS" "$BUILD"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SOURCES=(Sources/UmamiBar/*.swift)
if [[ "$MODE" == "universal" ]]; then
  xcrun swiftc -O -parse-as-library -swift-version 5 -sdk "$SDK" -module-cache-path /tmp/umamibar-module-cache -target x86_64-apple-macosx10.15 "${SOURCES[@]}" -o "$BUILD/UmamiBar-intel"
  xcrun swiftc -O -parse-as-library -swift-version 5 -sdk "$SDK" -module-cache-path /tmp/umamibar-module-cache -target arm64-apple-macosx11.0 "${SOURCES[@]}" -o "$BUILD/UmamiBar-arm"
  lipo -create "$BUILD/UmamiBar-intel" "$BUILD/UmamiBar-arm" -output "$ROOT/dist/UmamiBar.app/Contents/MacOS/UmamiBar"
else
  xcrun swiftc -O -parse-as-library -swift-version 5 -sdk "$SDK" -module-cache-path /tmp/umamibar-module-cache "${SOURCES[@]}" -o "$ROOT/dist/UmamiBar.app/Contents/MacOS/UmamiBar"
fi
cat > "$ROOT/dist/UmamiBar.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.umamibar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>UmamiBar</string>
<key>CFBundleExecutable</key><string>UmamiBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$ROOT/dist/UmamiBar.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$ROOT/dist/UmamiBar.app/Contents/Info.plist"
mkdir -p "$ROOT/dist/UmamiBar.app/Contents/Resources"
cp assets/AppIcon.icns "$ROOT/dist/UmamiBar.app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$ROOT/dist/UmamiBar.app"
echo "Built: $ROOT/dist/UmamiBar.app"
