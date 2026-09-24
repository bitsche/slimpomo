#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product SlimPomo

app="$root/SlimPomo.app"
"$root/scripts/bundle-app.sh" "$root/.build/release/SlimPomo" "$app"

echo "Built $app"
