#!/bin/bash
# Builds Eyesaver.app, optionally installing it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

NOM="Eyesaver"
ID="fr.nicolasgarnier.eyesaver"
APP="build/$NOM.app"
CACHE="build/.modulecache"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"

# --- Icon (👀 emoji on a dark rounded square) --------------------------------
if [ ! -f "Resources/$NOM.icns" ]; then
  mkdir -p Resources
  swiftc -O -module-cache-path "$CACHE" -o build/makeicon Tools/makeicon.swift
  ./build/makeicon "build/$NOM.iconset"
  iconutil -c icns -o "Resources/$NOM.icns" "build/$NOM.iconset"
fi
cp "Resources/$NOM.icns" "$APP/Contents/Resources/"

# --- Binary -----------------------------------------------------------------
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$CACHE" \
  -o "$APP/Contents/MacOS/$NOM" Sources/main.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NOM</string>
  <key>CFBundleDisplayName</key><string>$NOM</string>
  <key>CFBundleExecutable</key><string>$NOM</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleIconFile</key><string>$NOM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Agent app: no Dock icon, no application menu bar. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature with a stable identifier. Eyesaver needs no TCC permission,
# so a rebuild never costs the user anything — see README, "Permissions".
codesign --force --sign - --identifier "$ID" "$APP"

# --- Install ----------------------------------------------------------------
if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/$NOM.app"
  cp -R "$APP" "/Applications/"
  echo "→ /Applications/$NOM.app"
else
  echo "→ $(pwd)/$APP"
fi
