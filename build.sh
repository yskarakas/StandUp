#!/bin/zsh
# Builds "Stand Up.app" next to this script.
#   ./build.sh             build for this Mac
#   ./build.sh --install   build, copy to /Applications and launch
#   ./build.sh --release   universal build (Apple silicon + Intel) zipped into dist/
set -e
cd "$(dirname "$0")"
APP="Stand Up.app"
VERSION="1.1"
BUILD_NUMBER="2"
MODE="$1"

rm -rf "$APP" build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$MODE" == "--release" ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
      -o "build/StandUp-$arch" Sources/*.swift
  done
  lipo -create build/StandUp-arm64 build/StandUp-x86_64 -output "$APP/Contents/MacOS/StandUp"
else
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    -o "$APP/Contents/MacOS/StandUp" Sources/*.swift
fi

swift make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Stand Up</string>
  <key>CFBundleDisplayName</key><string>Stand Up</string>
  <key>CFBundleIdentifier</key><string>local.standup.app</string>
  <key>CFBundleExecutable</key><string>StandUp</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"

if [[ "$MODE" == "--install" ]]; then
  pkill -x StandUp 2>/dev/null || true
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  open "/Applications/$APP"
  echo "Installed to /Applications and launched."
fi

if [[ "$MODE" == "--release" ]]; then
  mkdir -p dist
  ZIP="dist/StandUp-$VERSION-macOS.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  shasum -a 256 "$ZIP"
  echo "Release zip: $(pwd)/$ZIP"
fi
