#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product Deeeep

app="$root/Deeeep.app"
"$root/scripts/bundle-app.sh" "$root/.build/release/Deeeep" "$app"

echo "Built $app"
