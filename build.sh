#!/bin/bash
# Builds Eyesaver.app, optionally installing it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Eyesaver"
ID="fr.nicolasgarnier.eyesaver"
APP="build/$NAME.app"

# Swift's shared module cache is what makes a rebuild take seconds instead of a
# minute: compiling this file is 5 s against a warm cache and 45 s against an
# empty one, and AppKit is most of that. Leave it where Swift puts it, shared
# with every other project on the machine. EYESAVER_MODULE_CACHE overrides it
# for sandboxed environments that cannot write to the default location.
compile() {
  if [ -n "${EYESAVER_MODULE_CACHE:-}" ]; then
    mkdir -p "$EYESAVER_MODULE_CACHE"
    swiftc "$@" -module-cache-path "$EYESAVER_MODULE_CACHE"
  else
    swiftc "$@"
  fi
}

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- Icon: Resources/icon.png if you made one, the 👀 emoji otherwise -------
if [ ! -f "Resources/$NAME.icns" ]; then
  mkdir -p Resources "build/$NAME.iconset"
  if [ -f Resources/icon.png ]; then
    # A hand-made icon wins. Expects a square PNG, 1024x1024, with the rounded
    # square already drawn in: macOS does not round app icons for you.
    # Not `set -- $pair`: that overwrites the positional parameters, and the
    # --install test at the bottom of this script reads $1. It only bites on a
    # first build, which is the one where someone is installing.
    for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
                "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
      pixels="${pair% *}"
      label="${pair#* }"
      sips -z "$pixels" "$pixels" Resources/icon.png --out "build/$NAME.iconset/icon_$label.png" >/dev/null
    done
  else
    compile -O -o build/makeicon Tools/makeicon.swift
    ./build/makeicon "build/$NAME.iconset"
  fi
  iconutil -c icns -o "Resources/$NAME.icns" "build/$NAME.iconset"
fi
cp "Resources/$NAME.icns" "$APP/Contents/Resources/"
# Share-card template, and the pixel font its number is set in.
cp Resources/card.jpg Resources/Jersey15-Regular.ttf Resources/Jersey15-OFL.txt "$APP/Contents/Resources/"

# --- Binary -----------------------------------------------------------------
compile -O -target arm64-apple-macos13.0 \
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
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
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
  # Quit every running copy, wherever it was started from. Replacing the bundle
  # under a live process leaves it on the old code, and a copy still running out
  # of build/ would give you a second menu bar icon doing the same job.
  if pkill -f "$NAME.app/Contents/MacOS/$NAME" 2>/dev/null; then
    # LaunchServices answers -609 to an `open` that follows the kill too
    # closely, and nothing starts.
    sleep 2
  fi
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" "/Applications/"
  # Leave exactly one bundle on the disk. Two with the same identifier and
  # LaunchServices is free to open whichever it likes.
  rm -rf "$APP"
  open "/Applications/$NAME.app"
  echo "→ installed in /Applications and started"
  echo "  It has no window and no Dock icon: look for the timer in the menu bar,"
  echo "  at the top right of the screen, next to the clock."
else
  echo "→ $(pwd)/$APP"
fi
