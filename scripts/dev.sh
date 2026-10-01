#!/bin/bash
# Builds and launches Deeeep Dev.app. Never quits or writes the release app.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

usage() {
    echo "Usage: scripts/dev.sh [--seed | --seed-large | --clear-history | --stale-done | --reset | --tour | --later | --export-menubar-icons <dir>]" >&2
    exit 1
}

flag=""
export_dir=""
case "${1:-}" in
    "") ;;
    --seed) flag="-seedHistory" ;;
    --seed-large) flag="-seedHistoryLarge" ;;
    --clear-history) flag="-clearHistory" ;;
    --stale-done) flag="-staleDone" ;;
    --reset) flag="-resetAll" ;;
    --tour) flag="-resetTour" ;;
    --later) flag="-seedLater" ;;
    --export-menubar-icons)
        export_dir="${2:-}"
        [[ -n "$export_dir" ]] || usage
        flag="-exportMenuBarIcons"
        ;;
    *) usage ;;
esac
if [[ -n "$export_dir" ]]; then
    [[ $# -eq 2 ]] || usage
elif [[ $# -gt 1 ]]; then
    usage
fi

swift build -c debug --product Deeeep -Xswiftc -DSLIMPOMO_DEV

app="$root/Deeeep Dev.app"
# Match the dev bundle only. A release Deeeep.app must keep running.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pids="$(pgrep -f '/Deeeep Dev\.app/Contents/MacOS/Deeeep' || true)"
    [[ -z "$pids" ]] && break
    kill $pids 2>/dev/null || true
    sleep 0.2
done

"$root/scripts/bundle-app.sh" "$root/.build/debug/Deeeep" "$app"

plist="$app/Contents/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${bundle_id}.dev" "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Deeeep Dev' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Deeeep Dev' "$plist"
codesign --force --sign - "$app/Contents/MacOS/Deeeep"
codesign --force --sign - "$app"

if [[ "$flag" == "-exportMenuBarIcons" ]]; then
    "$app/Contents/MacOS/Deeeep" -exportMenuBarIcons "$export_dir"
    echo "Exported menu-bar icons to $export_dir"
elif [[ -n "$flag" ]]; then
    open "$app" --args "$flag"
    echo "Launched $app $flag"
else
    open "$app"
    echo "Launched $app"
fi
