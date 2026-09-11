#!/bin/bash
# Builds Eyesaver.app, optionally installing it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Eyesaver"
ID="fr.nicolasgarnier.eyesaver"
APP="build/$NAME.app"
CACHE="build/.modulecache"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"

# --- Icon: Resources/icon.png if you made one, the 👀 emoji otherwise -------
if [ ! -f "Resources/$NAME.icns" ]; then
  mkdir -p Resources "build/$NAME.iconset"
  if [ -f Resources/icon.png ]; then
    # A hand-made icon wins. Expects a square PNG, 1024x1024, with the rounded
    # square already drawn in: macOS does not round app icons for you.
    for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
                "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
      set -- $pair
      sips -z "$1" "$1" Resources/icon.png --out "build/$NAME.iconset/icon_$2.png" >/dev/null
    done
  else
    swiftc -O -module-cache-path "$CACHE" -o build/makeicon Tools/makeicon.swift
    ./build/makeicon "build/$NAME.iconset"
  fi
  iconutil -c icns -o "Resources/$NAME.icns" "build/$NAME.iconset"
fi
cp "Resources/$NAME.icns" "$APP/Contents/Resources/"
# Share-card template, and the pixel font its number is set in.
cp Resources/card.jpg Resources/Jersey15-Regular.ttf Resources/Jersey15-OFL.txt "$APP/Contents/Resources/"

# --- Binary -----------------------------------------------------------------
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$CACHE" \
  -o "$APP/Contents/MacOS/$NAME" Sources/main.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleIconFile</key><string>$NAME</string>
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
# so a rebuild never costs the user anything. See README, "Permissions".
codesign --force --sign - --identifier "$ID" "$APP"

# --- Install ----------------------------------------------------------------
if [ "${1:-}" = "--install" ]; then
  # Replacing the bundle under a running copy leaves that copy on the old code,
  # so the install looks like it did nothing at all.
  if pkill -f "/Applications/$NAME.app/Contents/MacOS/$NAME" 2>/dev/null; then
    # LaunchServices answers -609 to an `open` that follows the kill too
    # closely, and nothing starts.
    sleep 2
  fi
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" "/Applications/"
  open "/Applications/$NAME.app"
  echo "→ /Applications/$NAME.app (running)"
else
  echo "→ $(pwd)/$APP"
fi
