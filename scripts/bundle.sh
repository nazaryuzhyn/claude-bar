#!/bin/bash
# Builds ClaudeBar.app, signs it ad hoc with App Sandbox and installs it to ~/Applications.
# The build lives outside ~/Desktop: iCloud's file provider stamps bundles there with
# com.apple.FinderInfo, which codesign rejects as "detritus".
set -euo pipefail
cd "$(dirname "$0")/.."

scratch="$HOME/Library/Caches/ClaudeBar/build"
app="$HOME/Library/Caches/ClaudeBar/ClaudeBar.app"
installed="$HOME/Applications/ClaudeBar.app"

swift build -c release --scratch-path "$scratch"
binary="$(swift build -c release --scratch-path "$scratch" --show-bin-path)/ClaudeBar"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/ClaudeBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
# A new build number per build. Banner icons are cached per bundle id regardless: a changed
# icon needs a new CFBundleIdentifier (see CLAUDE.md).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$app/Contents/Info.plist"
cp Resources/Sounds/done.wav Resources/Sounds/waiting.wav Resources/Icons/claude.pdf Resources/Icons/ClaudeBarIcon.icns THIRD_PARTY_NOTICES "$app/Contents/Resources/"

codesign --force --options runtime --entitlements Resources/ClaudeBar.entitlements --sign - "$app"
codesign --verify --strict --verbose=2 "$app"

was_running=false
if pgrep -x ClaudeBar >/dev/null; then
    was_running=true
    pkill -x ClaudeBar
    while pgrep -x ClaudeBar >/dev/null; do sleep 0.2; done
fi

mkdir -p "$HOME/Applications"
rm -rf "$installed"
cp -R "$app" "$installed"
# Notification banners take the app icon from Launch Services, which caches it by bundle.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed"
echo "Installed $installed"

if $was_running; then
    open "$installed"
fi
