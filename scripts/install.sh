#!/bin/bash
# Builds and installs ClaudeBar and wires it into Claude Code. Safe to run again to update.
set -euo pipefail
cd "$(dirname "$0")"

command -v swift >/dev/null || { echo "Swift is required: install Xcode or run xcode-select --install" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required: brew install jq" >&2; exit 1; }

root="$HOME/Library/Application Support/ClaudeBar"
bin="$root/bin"

# The scripts run on every tool call and status line refresh, and configure.sh edits
# settings.json, so copies that fail their tests are never installed.
echo "==> Testing the scripts Claude Code runs and the installer"
./test-hooks.sh | tail -n 1
./test-install.sh | tail -n 1

echo "==> Building ClaudeBar.app"
./bundle.sh

echo "==> Installing the scripts Claude Code runs"
mkdir -p -m 700 "$root" "$bin"
install -m 700 hook.sh statusline-bridge.sh statusline.sh configure.sh "$bin/"
echo "Installed to $bin"

echo "==> Connecting Claude Code"
./configure.sh install

open -g "$HOME/Applications/ClaudeBar.app"
cat <<'EOF'

Done. ClaudeBar is in the menu bar.
- Allow notifications when macOS asks, or later in System Settings > Notifications > ClaudeBar.
- Limits appear after the next reply in any Claude Code session.
- Optional: set "preferredNotifChannel": "notifications_disabled" in ~/.claude/settings.json to hear one sound, not two.
EOF
