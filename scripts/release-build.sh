#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MiddleClick"
ARCHIVE_NAME="${APP_NAME}.app.zip"
ARCHIVE_PATH="$ROOT_DIR/dist/${ARCHIVE_NAME}"
CHECKSUM_PATH="$ROOT_DIR/dist/${ARCHIVE_NAME}.sha256"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="$ROOT_DIR/dist/${DMG_NAME}"
DMG_CHECKSUM_PATH="$ROOT_DIR/dist/${DMG_NAME}.sha256"
CASK_PATH="$ROOT_DIR/dist/middleclick.rb"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag> [build_number]" >&2
  exit 1
fi

BUILD_NUMBER="${2:-1}"
TAG_NAME="${TAG#refs/tags/}"
VERSION="$TAG_NAME"
VERSION="${VERSION#v}"

if [[ -z "$VERSION" ]]; then
  echo "Failed to derive version from tag: $TAG" >&2
  exit 1
fi

cd "$ROOT_DIR"
./scripts/build-app.sh --version "$VERSION" --build-number "$BUILD_NUMBER"

rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH" "$DMG_PATH" "$DMG_CHECKSUM_PATH" "$CASK_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/${APP_NAME}.app" "$ARCHIVE_PATH"
/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$ROOT_DIR/dist/${APP_NAME}.app" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$ARCHIVE_NAME" > "$CHECKSUM_PATH"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$DMG_SHA256" "$DMG_NAME" > "$DMG_CHECKSUM_PATH"

GITHUB_REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$GITHUB_REPO" ]]; then
  GITHUB_REPO="jon/middleclick"
fi
OWNER="${GITHUB_REPO%%/*}"

DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG_NAME}/${ARCHIVE_NAME}"

cat > "$CASK_PATH" <<CASK
cask "middleclick" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${DOWNLOAD_URL}",
      verified: "github.com/${OWNER}/"
  name "MiddleClick"
  desc "Three-finger trackpad click/tap to middle click remapper"
  homepage "https://github.com/${GITHUB_REPO}"

  app "MiddleClick.app"
end
CASK

echo "Release assets prepared:"
echo "- $ARCHIVE_PATH"
echo "- $CHECKSUM_PATH"
echo "- $DMG_PATH"
echo "- $DMG_CHECKSUM_PATH"
echo "- $CASK_PATH"
echo "- zip sha256: $SHA256"
echo "- dmg sha256: $DMG_SHA256"
