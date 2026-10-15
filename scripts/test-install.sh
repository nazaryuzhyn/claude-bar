#!/bin/bash
# Tests for configure.sh and statusline.sh against a scratch HOME, never the real ~/.claude.
set -u
cd "$(dirname "$0")"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export HOME="$scratch/home"
unset CLAUDE_CONFIG_DIR CLAUDEBAR_DIR
mkdir -p "$HOME/.claude"
settings="$HOME/.claude/settings.json"
root="$HOME/Library/Application Support/ClaudeBar"
failures=0
checks=0

check() {
    local description=$1 expected=$2 actual=$3
    checks=$((checks + 1))
    if [ "$expected" == "$actual" ]; then
        echo "ok   $description"
    else
        echo "FAIL $description: expected [$expected], got [$actual]"
        failures=$((failures + 1))
    fi
}

configure() {
    ./configure.sh "$1" >/dev/null 2>&1
    status=$?
}

ours='[.hooks[]?[]?.hooks[]? | select(.command | contains("ClaudeBar/bin/hook.sh"))] | length'
backups() { find "$HOME/.claude" -name 'settings.json.claudebar-backup-*' | wc -l | tr -d ' '; }

# A fresh Claude Code: no settings.json yet.
configure install
check "install on a fresh setup exits 0" 0 "$status"
check "hooks for six events" 6 "$(jq "$ours" "$settings")"
check "the notification hook is narrowed to prompts" "permission_prompt|elicitation_dialog" "$(jq -r '.hooks.Notification[0].matcher' "$settings")"
check "hooks are async" true "$(jq '[.hooks[][].hooks[].async] | all' "$settings")"
check "the status line is ClaudeBar's" true "$(jq '.statusLine.command | contains("ClaudeBar/bin/statusline.sh")' "$settings")"
check "nothing to restore later" "" "$(cat "$root/statusline-original")"
before=$(cat "$settings")
configure install
check "a second install changes nothing" "$before" "$(cat "$settings")"
check "a fresh setup needs no backup" 0 "$(backups)"

configure uninstall
check "uninstall exits 0" 0 "$status"
check "uninstall leaves an empty object" '{}' "$(jq -c . "$settings")"

# An existing setup: other hooks, other keys, a status line of its own.
cat >"$settings" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard.sh"}]}]
  },
  "statusLine": {"type": "command", "command": "cat >/dev/null; echo mine", "padding": 1}
}
EOF
backups_before=$(backups)
configure install
check "the user's Stop hook stays" "say done" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$settings")"
check "ClaudeBar's Stop hook is added after it" true "$(jq '.hooks.Stop[1].hooks[0].command | contains("ClaudeBar")' "$settings")"
check "other hooks stay" guard.sh "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$settings")"
check "other keys stay" opus "$(jq -r .model "$settings")"
check "status line padding stays" 1 "$(jq .statusLine.padding "$settings")"
check "the user's status line is kept for later" "cat >/dev/null; echo mine" "$(cat "$root/statusline-original")"
check "an existing file gets its own backup" $((backups_before + 1)) "$(backups)"

# statusline.sh shows the user's own status line and feeds the bridge.
mkdir -p "$root/bin"
cp statusline.sh statusline-bridge.sh "$root/bin/"
payload='{"session_id":"s1","model":{"display_name":"Opus"},"workspace":{"current_dir":"/x/web"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1791990000}}}'
check "the wrapper prints the user's status line" mine "$(printf '%s' "$payload" | "$root/bin/statusline.sh")"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$root/limits/s1.json" ] && break; sleep 0.2; done
check "the wrapper feeds the bridge" 12 "$(jq '.rate_limits.five_hour.used_percentage' "$root/limits/s1.json" 2>/dev/null)"
: >"$root/statusline-original"
check "without one it prints model and folder" "Opus · web" "$(printf '%s' "$payload" | "$root/bin/statusline.sh")"
printf '%s' "cat >/dev/null; echo mine" >"$root/statusline-original"

configure uninstall
check "uninstall restores the user's status line" "cat >/dev/null; echo mine" "$(jq -r .statusLine.command "$settings")"
check "uninstall removes only ClaudeBar's hooks" 0 "$(jq "$ours" "$settings")"
check "uninstall keeps the user's hooks" "say done guard.sh" "$(jq -r '[.hooks.Stop[0].hooks[0].command, .hooks.PreToolUse[0].hooks[0].command] | join(" ")' "$settings")"
check "uninstall drops events left empty" '["PreToolUse","Stop"]' "$(jq -c '.hooks | keys' "$settings")"

# A manual setup: the user's own script already feeds the bridge.
printf '#!/bin/bash\ninput=$(cat)\nprintf %%s "$input" | "$HOME/Library/Application Support/ClaudeBar/bin/statusline-bridge.sh" &\necho mine\n' >"$HOME/.claude/statusline-command.sh"
jq --arg command "bash $HOME/.claude/statusline-command.sh" '.statusLine.command = $command' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
configure install
check "a status line that already feeds the bridge stays" "bash $HOME/.claude/statusline-command.sh" "$(jq -r .statusLine.command "$settings")"
configure uninstall
check "uninstall leaves that status line too" "bash $HOME/.claude/statusline-command.sh" "$(jq -r .statusLine.command "$settings")"

# A broken settings.json is never overwritten.
printf '{"model": ' >"$settings"
configure install
check "a broken settings.json stops the install" 1 "$status"
check "a broken settings.json is left as it was" '{"model": ' "$(cat "$settings")"

echo "$checks checks, $failures failed"
[ "$failures" -eq 0 ]
