#!/bin/bash
# Shared bundle steps for Deeeep.app and Deeeep Dev.app.
# Usage: scripts/bundle-app.sh <binary> <app-path>
set -euo pipefail

binary="$1"
app="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/Deeeep"
cp "$root/Info.plist" "$app/Contents/Info.plist"
chmod +x "$app/Contents/MacOS/Deeeep"

if [[ "$app" == *" Dev.app" ]]; then
    iconset="$root/Resources/AppIcon-dev.iconset"
else
    iconset="$root/Resources/AppIcon.iconset"
fi
mkdir -p "$app/Contents/Resources"
cp "$root/Resources/glow-work-done.wav" "$root/Resources/glow-break-over.wav" "$app/Contents/Resources/"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app/Contents/MacOS/Deeeep"
codesign --force --sign - "$app"
