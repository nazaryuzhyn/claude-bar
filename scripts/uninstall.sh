#!/bin/bash
# Removes ClaudeBar: its Claude Code settings, the app, and its data folder.
set -euo pipefail
cd "$(dirname "$0")"

./configure.sh uninstall-all

if pgrep -x ClaudeBar >/dev/null; then
    pkill -x ClaudeBar
fi
rm -rf "$HOME/Applications/ClaudeBar.app"
rm -rf "$HOME/Library/Application Support/ClaudeBar"
echo "Removed ~/Applications/ClaudeBar.app and ~/Library/Application Support/ClaudeBar"

cat <<'EOF'

macOS keeps two things the script cannot remove:
- the sandbox folder ~/Library/Containers/local.claudebar.menubar (delete it in Finder);
- the login item, if you turned on "launch at login" (System Settings > General > Login Items).
EOF
