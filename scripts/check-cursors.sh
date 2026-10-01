#!/bin/bash
# Fails if a clickable control does not use the shared pointing-hand style or modifier.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, re, sys

root = pathlib.Path("Sources")
clickable = re.compile(r"\bButton\s*[\(\{]|\.onTapGesture\b|\bIconPlate\s*\(")
shared = re.compile(r"pointingHandCursor|PointingHandButtonStyle")
exempt = re.compile(r"cursor-exempt")
failures = []

for path in sorted(root.rglob("*.swift")):
    if path.name == "PointingHand.swift":
        continue
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        if not clickable.search(line):
            continue
        previous = "\n".join(lines[max(0, index - 3): index + 1])
        if exempt.search(previous):
            continue
        following = "\n".join(lines[index: index + 50])
        if shared.search(following):
            continue
        failures.append(f"{path}:{index + 1}: clickable control is missing pointingHandCursor or PointingHandButtonStyle")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("check-cursors: ok")
PY
