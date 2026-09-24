#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

developer="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
frameworks="$developer/Library/Developer/Frameworks"
interop="$developer/Library/Developer/usr/lib"
plugins="$developer/usr/lib/swift/host/plugins"

# Command Line Tools ship Swift Testing as a framework. `swift test` does not
# pass -F for that framework, so the generated runner never sees the module.
swift test --disable-xctest --enable-swift-testing \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xswiftc -plugin-path -Xswiftc "$plugins" \
    -Xswiftc -plugin-path -Xswiftc "$plugins/testing" \
    -Xlinker -F -Xlinker "$frameworks" \
    -Xlinker -framework -Xlinker Testing \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$interop"
