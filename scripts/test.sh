#!/usr/bin/env bash
# Command Line Tools ship no XCTest, and swiftc does not find the Swift Testing
# macro plugin there on its own. Full Xcode needs no extra flags.
# The build lives outside ~/Desktop: iCloud's file provider stamps bundles there
# with com.apple.FinderInfo, which codesign rejects as "detritus".
set -euo pipefail
cd "$(dirname "$0")/.."

scratch="$HOME/Library/Caches/ClaudeBar/build"
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    exec swift test --scratch-path "$scratch" -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test --scratch-path "$scratch" "$@"
