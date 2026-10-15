#!/bin/bash
# Wires ClaudeBar into Claude Code, or takes it out again: `configure.sh install|uninstall`.
# Touches only ClaudeBar's own hook entries and status line in settings.json, keeps
# everything else, and backs the file up before it changes. Running it twice is harmless.
set -euo pipefail

action=${1:-}
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$config/settings.json"
root="$HOME/Library/Application Support/ClaudeBar"
hook="\"$root/bin/hook.sh\""
wrapper="\"$root/bin/statusline.sh\""
# The status line command that was there before ClaudeBar's, put back on uninstall. It lives
# next to bin/, where the sandboxed app cannot write, because statusline.sh runs it.
original="$root/statusline-original"

die() {
    echo "configure.sh: $*" >&2
    exit 1
}

command -v jq >/dev/null || die "jq is required (brew install jq)"
case "$action" in
    install | uninstall) ;;
    *) die "usage: configure.sh install|uninstall" ;;
esac

mkdir -p "$config"
current='{}'
if [ -f "$settings" ]; then
    jq -e 'type == "object"' "$settings" >/dev/null || die "$settings is not a JSON object; nothing changed"
    current=$(cat "$settings")
fi

# True when the user's own status line already feeds the bridge, as in a manual setup:
# the command, or a script file it names, mentions statusline-bridge.sh.
feeds_bridge() {
    local command=$1 word
    [[ "$command" == *statusline-bridge.sh* ]] && return 0
    for word in $command; do
        word=${word//\"/}
        word=${word//\'/}
        word=${word/#\~/$HOME}
        if [ -f "$word" ] && grep -q statusline-bridge.sh "$word"; then
            return 0
        fi
    done
    return 1
}

status_command=$(jq -r 'if .statusLine.type == "command" then .statusLine.command // "" else "" end' <<<"$current")

if [ "$action" == install ]; then
    updated=$(jq --arg hook "$hook" '
        def ours: any(.hooks[]?; (.command // "") | contains("ClaudeBar/bin/hook.sh"));
        def add($event; $matcher):
            if any(.hooks[$event][]?; ours) then .
            else .hooks[$event] = ((.hooks[$event] // []) + [
                {hooks: [{type: "command", command: $hook, async: true}]}
                + (if $matcher then {matcher: $matcher} else {} end)
            ])
            end;
        add("SessionStart"; null)
        | add("UserPromptSubmit"; null)
        | add("PostToolUse"; null)
        | add("Stop"; null)
        | add("SessionEnd"; null)
        | add("Notification"; "permission_prompt|elicitation_dialog")
    ' <<<"$current")

    if [[ "$status_command" == *ClaudeBar/bin/statusline.sh* ]]; then
        status_note="status line: already ClaudeBar's"
    elif [ -n "$status_command" ] && feeds_bridge "$status_command"; then
        status_note="status line: yours already feeds ClaudeBar, left as it is"
    else
        mkdir -p -m 700 "$root"
        printf '%s' "$status_command" >"$original"
        chmod 600 "$original"
        updated=$(jq --arg wrapper "$wrapper" '.statusLine = ((.statusLine // {}) + {type: "command", command: $wrapper})' <<<"$updated")
        if [ -n "$status_command" ]; then
            status_note="status line: ClaudeBar's, which still shows yours ($status_command)"
        else
            status_note="status line: ClaudeBar's minimal one (model and folder)"
        fi
    fi
else
    updated=$(jq '
        if .hooks then
            .hooks |= (
                map_values(
                    map(.hooks |= map(select((.command // "") | contains("ClaudeBar/bin/hook.sh") | not)))
                    | map(select(.hooks | length > 0))
                )
                | with_entries(select(.value | length > 0))
            )
            | if .hooks == {} then del(.hooks) else . end
        else . end
    ' <<<"$current")

    if [[ "$status_command" == *ClaudeBar/bin/statusline.sh* ]]; then
        previous=''
        [ -f "$original" ] && previous=$(cat "$original")
        if [ -n "$previous" ]; then
            updated=$(jq --arg command "$previous" '.statusLine.command = $command' <<<"$updated")
            status_note="status line: yours restored ($previous)"
        else
            updated=$(jq 'del(.statusLine)' <<<"$updated")
            status_note="status line: removed"
        fi
    elif [ -n "$status_command" ] && feeds_bridge "$status_command"; then
        status_note="status line: remove the statusline-bridge.sh line from your own script by hand"
    else
        status_note="status line: not ClaudeBar's, left as it is"
    fi
    rm -f "$original"
fi

if [ "$(jq -S . <<<"$updated")" == "$(jq -S . <<<"$current")" ]; then
    echo "Claude Code settings: no change needed ($settings)"
else
    if [ -f "$settings" ]; then
        # The process id keeps two runs within one second from overwriting each other's backup.
        backup="$settings.claudebar-backup-$(date +%Y%m%d-%H%M%S)-$$"
        cp -p "$settings" "$backup"
        echo "Backed up $settings to $backup"
    fi
    tmp="$settings.claudebar-tmp.$$"
    jq . <<<"$updated" >"$tmp" && mv -f "$tmp" "$settings"
    echo "Claude Code settings: updated $settings"
fi
echo "  $status_note"
