#!/bin/bash
# Tests for configure.sh and statusline.sh against a scratch HOME, never the real ~/.claude.
set -u
cd "$(dirname "$0")"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export HOME="$scratch/home"
unset CLAUDE_CONFIG_DIR CLAUDEBAR_DIR
# The machine's own organization policy must not leak into the results.
export CLAUDEBAR_MANAGED_DIR="$scratch/managed" CLAUDEBAR_MDM_DIR="$scratch/mdm"
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
output=$(./configure.sh install 2>&1)
check "install on a fresh setup exits 0" 0 "$?"
check "hooks for six events" 6 "$(jq "$ours" "$settings")"
check "the notification hook is narrowed to prompts" "permission_prompt|elicitation_dialog" "$(jq -r '.hooks.Notification[0].matcher' "$settings")"
check "hooks are async" true "$(jq '[.hooks[][].hooks[].async] | all' "$settings")"
check "no status line is added where there was none" false "$(jq 'has("statusLine")' "$settings")"
check "the install says how to get limits" 1 "$(grep -c 'Limits > Turn on' <<<"$output")"
check "nothing is saved to restore later" no "$([ -e "$root/statusline-original" ] && echo yes || echo no)"
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

# Organization policy that blinds ClaudeBar is named during the install.
rm -f "$settings"
mkdir -p "$CLAUDEBAR_MANAGED_DIR/managed-settings.d" "$CLAUDEBAR_MDM_DIR"
echo '{"allowManagedHooksOnly": true}' >"$CLAUDEBAR_MANAGED_DIR/managed-settings.json"
echo '{"statusLine": {"type": "command", "command": "corp-status"}}' >"$CLAUDEBAR_MANAGED_DIR/managed-settings.d/20-ui.json"
output=$(./configure.sh install 2>&1)
check "managed hooks only is named" 1 "$(grep -c 'allows only its own hooks' <<<"$output")"
check "a managed status line from a drop-in is named" 1 "$(grep -c 'sets the status line' <<<"$output")"
echo '{"disableAllHooks": true}' | plutil -convert binary1 -o "$CLAUDEBAR_MDM_DIR/com.anthropic.claudecode.plist" -
output=$(./configure.sh install 2>&1)
check "hooks turned off by an MDM profile are named" 1 "$(grep -c 'turns off hooks' <<<"$output")"
rm -rf "$CLAUDEBAR_MANAGED_DIR" "$CLAUDEBAR_MDM_DIR"
output=$(./configure.sh install 2>&1)
check "without a policy there is no warning" 0 "$(grep -c warning <<<"$output")"
configure uninstall

# Two profiles: each keeps its own status line, and uninstall-all reaches both.
work="$HOME/.claude-work"
mkdir -p "$work"
echo '{"statusLine": {"type": "command", "command": "cat >/dev/null; echo personal"}}' >"$settings"
echo '{"statusLine": {"type": "command", "command": "cat >/dev/null; echo work"}}' >"$work/settings.json"
configure install
CLAUDE_CONFIG_DIR="$work" ./configure.sh install >/dev/null 2>&1
check "the default profile's status line is kept" personal "$(printf '%s' "$payload" | "$root/bin/statusline.sh")"
check "the work profile's status line is kept apart" work "$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$work" "$root/bin/statusline.sh")"
check "both profiles are listed" 2 "$(grep -c . "$root/profiles")"
./configure.sh uninstall-all >/dev/null 2>&1
check "uninstall-all restores the default profile" "cat >/dev/null; echo personal" "$(jq -r .statusLine.command "$settings")"
check "uninstall-all restores the work profile" "cat >/dev/null; echo work" "$(jq -r .statusLine.command "$work/settings.json")"
check "uninstall-all removes the work profile's hooks" 0 "$(jq "$ours" "$work/settings.json")"
check "no profile is left listed" 0 "$(grep -c . "$root/profiles")"

# settings.json keeps its mode and a symlink to it survives.
rm -f "$settings"
echo '{"model": "opus"}' >"$settings"
chmod 600 "$settings"
configure install
check "a private settings.json stays private" 600 "$(stat -f %Lp "$settings")"
configure uninstall
check "and after uninstall too" 600 "$(stat -f %Lp "$settings")"
mkdir -p "$HOME/dotfiles"
mv "$settings" "$HOME/dotfiles/settings.json"
ln -s "$HOME/dotfiles/settings.json" "$settings"
configure install
check "a symlinked settings.json stays a symlink" link "$([ -L "$settings" ] && echo link || echo file)"
check "the file it points to gets the hooks" 6 "$(jq "$ours" "$HOME/dotfiles/settings.json")"
configure uninstall
check "uninstall goes through the symlink too" 0 "$(jq "$ours" "$HOME/dotfiles/settings.json")"
rm -f "$settings"

# Status lines and hooks of shapes ClaudeBar does not own are left exactly as they were.
echo '{"statusLine": {"type": "static", "text": "mine", "padding": 2}}' >"$settings"
configure install
check "a status line that is not a command is left alone" static "$(jq -r .statusLine.type "$settings")"
configure uninstall
check "and survives uninstall" '{"type":"static","text":"mine","padding":2}' "$(jq -c .statusLine "$settings")"
echo '{"hooks": {"PreCompact": [], "PreToolUse": [{"matcher": "x"}], "Stop": [{"matcher": "y"}]}, "x": 1}' >"$settings"
configure install
configure uninstall
check "uninstall copes with a group without hooks" 0 "$status"
check "the user's own empty and odd entries are restored exactly" '{"hooks":{"PreCompact":[],"PreToolUse":[{"matcher":"x"}],"Stop":[{"matcher":"y"}]},"x":1}' "$(jq -cS . "$settings")"
jq -n '{statusLine: {type: "command", command: "echo hi\n"}}' >"$settings"
configure install
configure uninstall
check "a status line command keeps its trailing newline" '"echo hi\n"' "$(jq .statusLine.command "$settings")"

# A status line that already feeds the bridge is recognised however it names the script.
mkdir -p "$HOME/sp ace"
printf 'printf %%s x | "$HOME/Library/Application Support/ClaudeBar/bin/statusline-bridge.sh" &\n' >"$HOME/sp ace/sl.sh"
for command in 'bash $HOME/sp\ ace/sl.sh' 'bash "${HOME}/sp ace/sl.sh"'; do
    jq -n --arg command "$command" '{statusLine: {type: "command", command: $command}}' >"$settings"
    configure install
    check "recognised: $command" "$command" "$(jq -r .statusLine.command "$settings")"
done
jq -n '{statusLine: {type: "command", command: "cat >/dev/null; echo status *"}}' >"$settings"
configure install
check "a * in the command does not match files in the current folder" true "$(jq '.statusLine.command | contains("ClaudeBar")' "$settings")"
configure uninstall
rm -f "$settings"

# Profile folders: absolute only, names that cannot collide, every one reached on uninstall-all.
output=$(CLAUDE_CONFIG_DIR=relative ./configure.sh install 2>&1)
check "a relative CLAUDE_CONFIG_DIR is refused" 1 "$?"
check "and no folder is created for it" no "$([ -e relative ] && echo yes || echo no)"
echo '{"statusLine": {"type": "command", "command": "cat >/dev/null; echo dash"}}' >"$HOME/.claude-work/settings.json"
mkdir -p "$HOME/.claude work"
echo '{"statusLine": {"type": "command", "command": "cat >/dev/null; echo space"}}' >"$HOME/.claude work/settings.json"
CLAUDE_CONFIG_DIR="$HOME/.claude-work" ./configure.sh install >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$HOME/.claude work" ./configure.sh install >/dev/null 2>&1
check "two similar folder names keep two status lines" "dash space" "$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$HOME/.claude-work" "$root/bin/statusline.sh") $(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$HOME/.claude work" "$root/bin/statusline.sh")"
printf '{"broken' >"$HOME/.claude-work/settings.json"
mkdir -p "$HOME/gone"
CLAUDE_CONFIG_DIR="$HOME/gone" ./configure.sh install >/dev/null 2>&1
rm -rf "$HOME/gone"
output=$(cd / && "$OLDPWD/configure.sh" uninstall-all 2>&1)
check "uninstall-all reports a profile it could not clean" 1 "$?"
check "and still cleans the others" "cat >/dev/null; echo space" "$(jq -r .statusLine.command "$HOME/.claude work/settings.json")"
check "a profile folder that is gone is not created again" no "$([ -e "$HOME/gone" ] && echo yes || echo no)"
echo '{}' >"$HOME/.claude-work/settings.json"
./configure.sh uninstall-all >/dev/null 2>&1
rm -rf "$HOME/.claude work"

# A status line saved by v0.1.0 under the shared name is unknown to this profile now.
jq -n --arg wrapper "\"$root/bin/statusline.sh\"" '{statusLine: {type: "command", command: $wrapper}}' >"$HOME/.claude-work/settings.json"
output=$(CLAUDE_CONFIG_DIR="$HOME/.claude-work" ./configure.sh uninstall 2>&1)
check "an unknown original removes the wrapper" false "$(jq 'has("statusLine")' "$HOME/.claude-work/settings.json")"
check "and points to the backups" 1 "$(grep -c 'restore it from' <<<"$output")"

# A settings.json that cannot be written stops the install with an error.
rm -f "$settings"
chmod 555 "$HOME/.claude"
output=$(./configure.sh install 2>&1)
check "a write that fails exits non-zero" 1 "$?"
check "and does not claim an update" 0 "$(grep -c 'updated' <<<"$output")"
chmod 755 "$HOME/.claude"

# A broken policy file hides no warning of the others.
mkdir -p "$CLAUDEBAR_MANAGED_DIR/managed-settings.d"
echo '{"allowManagedHooksOnly": true}' >"$CLAUDEBAR_MANAGED_DIR/managed-settings.json"
echo '{"statusLine": ,}' >"$CLAUDEBAR_MANAGED_DIR/managed-settings.d/10-broken.json"
output=$(./configure.sh install 2>&1)
check "a broken drop-in leaves the other warnings" 1 "$(grep -c 'allows only its own hooks' <<<"$output")"
rm -rf "$CLAUDEBAR_MANAGED_DIR"
configure uninstall

# Limits > Turn on in Settings: the app leaves a request, the next hook event adds the status line.
rm -f "$settings"
configure install
cp hook.sh configure.sh "$root/bin/"
mkdir -p "$root/events"
: >"$root/events/statusline-request"
printf '%s' '{"session_id":"s1","hook_event_name":"UserPromptSubmit","cwd":"/x/web"}' | "$root/bin/hook.sh"
check "a requested status line is added on the next hook event" true "$(jq '.statusLine.command | contains("ClaudeBar/bin/statusline.sh")' "$settings")"
check "the request is used up" no "$([ -e "$root/events/statusline-request" ] && echo yes || echo no)"
check "the added status line is the minimal one" "Opus · web" "$(printf '%s' "$payload" | "$root/bin/statusline.sh")"
before=$(cat "$settings")
configure add-statusline
check "asking again changes nothing" "$before" "$(cat "$settings")"
configure uninstall
check "uninstall takes the added status line away" false "$(jq 'has("statusLine")' "$settings")"
echo '{"statusLine": {"type": "command", "command": "cat >/dev/null; echo mine"}}' >"$settings"
configure add-statusline
check "a status line of the user's own is never replaced by a request" "cat >/dev/null; echo mine" "$(jq -r .statusLine.command "$settings")"
rm -f "$settings" "$root/bin/hook.sh" "$root/bin/configure.sh"

# A broken settings.json is never overwritten.
printf '{"model": ' >"$settings"
configure install
check "a broken settings.json stops the install" 1 "$status"
check "a broken settings.json is left as it was" '{"model": ' "$(cat "$settings")"

echo "$checks checks, $failures failed"
[ "$failures" -eq 0 ]
