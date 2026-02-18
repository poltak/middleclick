#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
BASE_PNG="$ASSETS_DIR/AppIcon-1024.png"
ICNS_PATH="$ASSETS_DIR/AppIcon.icns"

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

SWIFT_FILE="$(mktemp /tmp/middleclick-icon-XXXXXX.swift)"
trap 'rm -f "$SWIFT_FILE"' EXIT

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let canvasRect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let bgPath = NSBezierPath(roundedRect: canvasRect.insetBy(dx: 36, dy: 36), xRadius: 230, yRadius: 230)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.09, green: 0.57, blue: 0.77, alpha: 1.0),
    NSColor(calibratedRed: 0.06, green: 0.38, blue: 0.62, alpha: 1.0)
])!
gradient.draw(in: bgPath, angle: -90)

// Three fingers.
let fingerWidth: CGFloat = 132
let fingerHeight: CGFloat = 620
let fingerY: CGFloat = 220
let xPositions: [CGFloat] = [286, 446, 606]
for x in xPositions {
    let finger = NSBezierPath(roundedRect: NSRect(x: x, y: fingerY, width: fingerWidth, height: fingerHeight), xRadius: 66, yRadius: 66)
    NSColor(calibratedWhite: 1.0, alpha: 0.96).setFill()
    finger.fill()
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let pngData = rep.representation(using: .png, properties: [:])
else {
    fputs("Failed to render icon PNG\n", stderr)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
SWIFT

swift "$SWIFT_FILE" "$BASE_PNG"

sips -z 16 16   "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64   "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Generated app icon: $ICNS_PATH"
