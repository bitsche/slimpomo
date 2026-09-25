#!/bin/bash
# Builds and launches SlimPomo Dev.app. Never quits or writes the release app.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

usage() {
    echo "Usage: scripts/dev.sh [--seed | --seed-large | --clear-history | --stale-done | --reset | --tour]" >&2
    exit 1
}

flag=""
case "${1:-}" in
    "") ;;
    --seed) flag="-seedHistory" ;;
    --seed-large) flag="-seedHistoryLarge" ;;
    --clear-history) flag="-clearHistory" ;;
    --stale-done) flag="-staleDone" ;;
    --reset) flag="-resetAll" ;;
    --tour) flag="-resetTour" ;;
    *) usage ;;
esac
if [[ $# -gt 1 ]]; then
    usage
fi

swift build -c debug --product SlimPomo -Xswiftc -DSLIMPOMO_DEV

app="$root/SlimPomo Dev.app"
# The executable name is still SlimPomo, so match the dev bundle path only.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pids="$(pgrep -f '/SlimPomo Dev\.app/Contents/MacOS/SlimPomo' || true)"
    [[ -z "$pids" ]] && break
    kill $pids 2>/dev/null || true
    sleep 0.2
done

"$root/scripts/bundle-app.sh" "$root/.build/debug/SlimPomo" "$app"

plist="$app/Contents/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${bundle_id}.dev" "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName SlimPomo Dev' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName SlimPomo Dev' "$plist"
codesign --force --sign - "$app/Contents/MacOS/SlimPomo"
codesign --force --sign - "$app"

if [[ -n "$flag" ]]; then
    open "$app" --args "$flag"
else
    open "$app"
fi

echo "Launched $app${flag:+ $flag}"
