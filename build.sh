#!/bin/zsh
# Builds "Stand Up.app" next to this script. Usage: ./build.sh [--install]
set -e
cd "$(dirname "$0")"
APP="Stand Up.app"
rm -rf "$APP" build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -o "$APP/Contents/MacOS/StandUp" Sources/*.swift

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
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"

if [[ "$1" == "--install" ]]; then
  pkill -x StandUp 2>/dev/null || true
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  open "/Applications/$APP"
  echo "Installed to /Applications and launched."
fi
