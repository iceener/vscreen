#!/bin/bash
# Build vscreen in release mode, wrap it in a minimal vscreen.app bundle
# (bundle id com.overment.vscreen), sign it with the stable local identity,
# install it at ~/Applications/vscreen.app, and link ~/.local/bin/vscreen to its executable.
#
# TCC keys bundles by bundle id + designated requirement, so one Accessibility and one
# Screen Recording grant cover every rebuild and every terminal or agent host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${VSCREEN_APP:-$HOME/Applications/vscreen.app}"
LINK="${VSCREEN_LINK:-$HOME/.local/bin/vscreen}"
VERSION="$(sed -n 's/^let vscreenVersion = "\(.*\)"$/\1/p' "$ROOT/Sources/vscreen/main.swift")"

cd "$ROOT"
swift build -c release --product vscreen >&2
BIN="$(swift build -c release --show-bin-path)/vscreen"

STAGE="$(mktemp -d)/vscreen.app"
trap 'rm -rf "$(dirname "$STAGE")"' EXIT
mkdir -p "$STAGE/Contents/MacOS"
cp "$BIN" "$STAGE/Contents/MacOS/vscreen"
cat > "$STAGE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.overment.vscreen</string>
  <key>CFBundleName</key><string>vscreen</string>
  <key>CFBundleExecutable</key><string>vscreen</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
"$ROOT/scripts/sign.sh" "$STAGE" >&2
codesign --verify --strict "$STAGE"

# Replace the bundle by rename so a running daemon keeps its old, still-valid executable.
mkdir -p "$(dirname "$APP")" "$(dirname "$LINK")"
OLD="$(dirname "$APP")/.vscreen.app.old.$$"
[ -e "$APP" ] && mv "$APP" "$OLD"
mv "$STAGE" "$APP"
rm -rf "$OLD"
ln -sfn "$APP/Contents/MacOS/vscreen" "$LINK"

echo "installed $APP" >&2
echo "linked $LINK -> $APP/Contents/MacOS/vscreen" >&2
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /designated requirement: /p' >&2
