#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product SlimPomo

app="$root/SlimPomo.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/SlimPomo" "$app/Contents/MacOS/SlimPomo"
cp "$root/Info.plist" "$app/Contents/Info.plist"
chmod +x "$app/Contents/MacOS/SlimPomo"

iconset="$(mktemp -d)/AppIcon.iconset"
square="$(mktemp -d)/AppIcon-square.png"
mkdir -p "$iconset"
sips --cropToHeightWidth 766 766 "$root/Resources/AppIcon.png" --out "$square" >/dev/null
sips -z 16 16 "$square" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$square" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$square" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$square" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$square" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$square" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$square" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$square" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$square" --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$square" --out "$iconset/icon_512x512@2x.png" >/dev/null
mkdir -p "$app/Contents/Resources"
cp "$root/Resources/kalimba-work-done-short.wav" "$root/Resources/kalimba-break-over-short.wav" "$app/Contents/Resources/"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app/Contents/MacOS/SlimPomo"
codesign --force --sign - "$app"

echo "Built $app"
