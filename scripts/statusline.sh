#!/bin/bash
# Claude Code status line installed by ClaudeBar. Hands the input to the bridge in the
# background, then prints the status line the user had before, or a minimal one.

IFS= read -r -d '' input
root="$HOME/Library/Application Support/ClaudeBar"

# The redirect keeps the background job from holding the status line's output open.
printf '%s' "$input" | "$root/bin/statusline-bridge.sh" >/dev/null 2>&1 &

if [ -s "$root/statusline-original" ]; then
    printf '%s' "$input" | /bin/bash -c "$(cat "$root/statusline-original")"
else
    jq -r '"\(.model.display_name // "Claude") · \((.workspace.current_dir // .cwd // "") | split("/") | last)"' <<<"$input"
fi
