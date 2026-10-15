#!/bin/bash
# Claude Code status line installed by ClaudeBar. Hands the input to the bridge in the
# background, then prints the status line the user had before. Installs before 0.2 also put
# it where there was none; those still get a minimal line.

IFS= read -r -d '' input
root="$HOME/Library/Application Support/ClaudeBar"
# The same per-profile name configure.sh saved the user's status line under.
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config=${config%/}
original="$root/statusline-original"
if [ "$config" != "$HOME/.claude" ]; then
    original="$original-$(md5 -q -s "$config")"
fi

# The redirect keeps the background job from holding the status line's output open.
printf '%s' "$input" | "$root/bin/statusline-bridge.sh" >/dev/null 2>&1 &

if [ -s "$original" ]; then
    # /bin/sh, the shell Claude Code itself runs a status line command with.
    printf '%s' "$input" | /bin/sh -c "$(cat "$original")"
else
    jq -r '"\(.model.display_name // "Claude") · \((.workspace.current_dir // .cwd // "") | split("/") | last)"' <<<"$input"
fi
