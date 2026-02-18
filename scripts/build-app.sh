#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MiddleClick"
BUNDLE_ID="com.jon.middleclick"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
BIN_PATH="$ROOT_DIR/.build/release/${APP_NAME}"
INSTALL_APP_DIR="/Applications/${APP_NAME}.app"
INSTALL_TO_APPLICATIONS=false

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_TO_APPLICATIONS=true
fi

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Give the bundle a stable code identity for TCC checks.
codesign --force --deep --sign - --timestamp=none "$APP_DIR"

echo "Built app bundle: $APP_DIR"
if [[ "$INSTALL_TO_APPLICATIONS" == "true" ]]; then
  rm -rf "$INSTALL_APP_DIR"
  cp -R "$APP_DIR" "$INSTALL_APP_DIR"
  codesign --force --deep --sign - --timestamp=none "$INSTALL_APP_DIR"
  echo "Installed app bundle: $INSTALL_APP_DIR"
  echo "Launch with: open '$INSTALL_APP_DIR'"
else
  echo "Launch with: open '$APP_DIR'"
  echo "Tip: use './scripts/build-app.sh --install' for a stable /Applications install."
fi
