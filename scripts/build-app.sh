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
codesign --force --sign - "$app/Contents/MacOS/SlimPomo"
codesign --force --sign - "$app"

echo "Built $app"
