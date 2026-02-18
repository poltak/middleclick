#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MiddleClick"
BUNDLE_ID="com.jon.middleclick"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
BIN_PATH="$ROOT_DIR/.build/release/${APP_NAME}"
INSTALL_APP_DIR="/Applications/${APP_NAME}.app"
INSTALL_TO_APPLICATIONS=false
VERSION="1.0.0"
BUILD_NUMBER="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_TO_APPLICATIONS=true
      shift
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--install] [--version X.Y.Z] [--build-number N]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "--version and --build-number must be non-empty when provided." >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release
./scripts/generate-icon.sh

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

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
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
