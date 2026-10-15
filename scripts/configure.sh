#!/bin/bash
# Wires ClaudeBar into Claude Code, or takes it out again: `configure.sh install|uninstall`
# for the profile in CLAUDE_CONFIG_DIR (default ~/.claude), `uninstall-all` for every profile.
# `add-statusline` adds ClaudeBar's minimal status line where there is none, so limits come in;
# hook.sh runs it when the app asks (Settings, Limits > Turn on).
# Touches only ClaudeBar's own hook entries and status line in settings.json, keeps
# everything else, and backs the file up before it changes. Running it twice is harmless.
set -euo pipefail

root="$HOME/Library/Application Support/ClaudeBar"
# Every profile ClaudeBar is connected to, one config folder per line, for uninstall-all.
profiles="$root/profiles"

die() {
    echo "configure.sh: $*" >&2
    exit 1
}

command -v jq >/dev/null || die "jq is required (brew install jq)"
action=${1:-}
case "$action" in
    install | uninstall | uninstall-all | add-statusline) ;;
    *) die "usage: configure.sh install|uninstall|uninstall-all|add-statusline" ;;
esac

if [ "$action" == uninstall-all ]; then
    # Every profile is tried, so one that fails does not keep ClaudeBar in the others.
    failed=0
    list=''
    [ -f "$profiles" ] && list=$(cat "$profiles")
    while IFS= read -r config; do
        [ -n "$config" ] || continue
        CLAUDE_CONFIG_DIR="$config" "$BASH" "${BASH_SOURCE[0]}" uninstall || failed=1
    done <<<"$list"
    # The default profile also when it was connected before profiles were listed.
    env -u CLAUDE_CONFIG_DIR "$BASH" "${BASH_SOURCE[0]}" uninstall || failed=1
    exit "$failed"
fi

config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config=${config%/}
# Claude Code and uninstall-all, run from another folder, would resolve a relative one differently.
[[ "$config" == /* ]] || die "CLAUDE_CONFIG_DIR must be an absolute path, not $config"
settings="$config/settings.json"
hook="\"$root/bin/hook.sh\""
wrapper="\"$root/bin/statusline.sh\""
# The status line command that was there before ClaudeBar's, put back on uninstall. It lives
# next to bin/, where the sandboxed app cannot write, because statusline.sh runs it. Each
# profile keeps its own, named by the md5 of its folder (one name per folder, in any locale);
# statusline.sh derives the same name from CLAUDE_CONFIG_DIR.
original="$root/statusline-original"
if [ "$config" != "$HOME/.claude" ]; then
    original="$original-$(md5 -q -s "$config")"
fi

# Drops this profile from the list, and adds it back on install.
update_profiles() {
    local listed=''
    mkdir -p -m 700 "$root"
    [ -f "$profiles" ] && listed=$(grep -vxF -- "$config" "$profiles" || true)
    [ "$action" != uninstall ] && listed=$(printf '%s\n%s' "$listed" "$config")
    grep -v '^$' <<<"$listed" >"$profiles" || : >"$profiles"
}

if [ "$action" == uninstall ] && [ ! -d "$config" ]; then
    echo "Claude Code settings: no folder $config, nothing to remove"
    rm -f "$original"
    update_profiles
    exit 0
fi

# A symlinked settings.json (dotfiles) is changed where it points, and keeps its mode, which
# can be 0600 when the file holds API keys.
mkdir -p "$config"
target=$settings
mode=600
current='{}'
if [ -L "$settings" ]; then
    target=$(realpath "$settings" 2>/dev/null) || die "$settings is a broken symlink; nothing changed"
fi
if [ -f "$target" ]; then
    jq -e 'type == "object" and ((.hooks // {}) | type == "object")' "$target" >/dev/null \
        || die "$settings is not a JSON object with an object of hooks; nothing changed"
    current=$(cat "$target")
    mode=$(stat -f %Lp "$target")
fi

# A script path the status line names: quotes, ~, $HOME and ${HOME} as the shell would read them.
mentions_bridge() {
    local path=$1
    path=${path//\"/}
    path=${path//\'/}
    path=${path/#\~/$HOME}
    path=${path//\$\{HOME\}/$HOME}
    path=${path//\$HOME/$HOME}
    [ -f "$path" ] && grep -q statusline-bridge.sh "$path"
}

# True when the user's own status line already feeds the bridge, as in a manual setup:
# the command, or a script file it names, mentions statusline-bridge.sh. Globbing is off,
# or a `*` in the command would match files in the current folder.
feeds_bridge() {
    local command=$1 word rest
    [[ "$command" == *statusline-bridge.sh* ]] && return 0
    set -f
    # A backslash-escaped space belongs to the path, so it is kept out of the word splitting.
    for word in ${command//\\ /$'\x1f'}; do
        if mentions_bridge "${word//$'\x1f'/ }"; then
            set +f
            return 0
        fi
    done
    set +f
    rest=$command
    while [[ "$rest" =~ \"([^\"]+)\" ]]; do
        mentions_bridge "${BASH_REMATCH[1]}" && return 0
        rest=${rest#*"${BASH_REMATCH[0]}"}
    done
    return 1
}

has_status=$(jq 'has("statusLine")' <<<"$current")
# -j and the x keep a trailing newline of the command, which command substitution would drop.
status_command=$(jq -j 'if .statusLine.type == "command" then .statusLine.command // "" else "" end' <<<"$current"; printf x)
status_command=${status_command%x}
save_original=false
status_note=''

if [ "$action" == add-statusline ]; then
    updated=$current
    if [[ "$status_command" == *ClaudeBar/bin/statusline.sh* ]] || [ "$has_status" == true ]; then
        # The user's own status line is wrapped by install, never replaced here.
        status_note="status line: already there, left as it is"
    else
        save_original=true
        updated=$(jq --arg wrapper "$wrapper" '.statusLine = {type: "command", command: $wrapper}' <<<"$current")
        status_note="status line: ClaudeBar's minimal one (model and folder), so limits come in"
    fi
elif [ "$action" == install ]; then
    updated=$(jq --arg hook "$hook" '
        def ours: any(.hooks[]?; (.command // "") | tostring | contains("ClaudeBar/bin/hook.sh"));
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
    elif [ "$has_status" == true ] && [ -z "$status_command" ]; then
        status_note="status line: not a command ClaudeBar can wrap, left as it is; ClaudeBar will show no limits"
    elif [ -z "$status_command" ]; then
        # Not everyone wants a status line, so none is added; the app explains why limits are missing.
        status_note="status line: none, and ClaudeBar adds none; you get sessions and alerts. For limits, choose Limits > Turn on in ClaudeBar's Settings"
    elif feeds_bridge "$status_command"; then
        status_note="status line: yours already feeds ClaudeBar, left as it is"
    else
        save_original=true
        updated=$(jq --arg wrapper "$wrapper" '.statusLine.command = $wrapper' <<<"$updated")
        status_note="status line: ClaudeBar's, which still shows yours ($status_command)"
    fi
else
    # Only what ClaudeBar's entries leave empty is dropped; the user's own empty lists stay.
    updated=$(jq '
        def ours: (.command // "") | tostring | contains("ClaudeBar/bin/hook.sh");
        def has_ours: (.hooks | type) == "array" and any(.hooks[]; ours);
        if (.hooks | type) == "object" then
            .hooks as $before
            | .hooks |= with_entries(
                if (.value | type) == "array" and any(.value[]; has_ours) then
                    .value |= map(if has_ours then (.hooks |= map(select(ours | not))) | select(.hooks != []) else . end)
                    | select(.value != [])
                else . end
            )
            | if .hooks == {} and $before != {} then del(.hooks) else . end
        else . end
    ' <<<"$current")

    if [[ "$status_command" == *ClaudeBar/bin/statusline.sh* ]]; then
        if [ -f "$original" ]; then
            # The x keeps trailing newlines, which command substitution would drop.
            previous=$(cat "$original"; printf x)
            previous=${previous%x}
            if [ -n "$previous" ]; then
                updated=$(jq --arg command "$previous" '.statusLine.command = $command' <<<"$updated")
                status_note="status line: yours restored ($previous)"
            else
                updated=$(jq 'del(.statusLine)' <<<"$updated")
                status_note="status line: removed"
            fi
        else
            # Its scripts are about to go, so it cannot stay; what it replaced is in the backups.
            updated=$(jq 'del(.statusLine)' <<<"$updated")
            status_note="status line: removed; the one before ClaudeBar's is unknown, restore it from a settings.json.claudebar-backup-* file if you had one"
        fi
    elif [ -n "$status_command" ] && feeds_bridge "$status_command"; then
        status_note="status line: remove the statusline-bridge.sh line from your own script by hand"
    else
        status_note="status line: not ClaudeBar's, left as it is"
    fi
fi

# Organization policy that would keep ClaudeBar blind: managed-settings.json with its drop-in
# folder, and MDM profiles. Each file is read on its own, so a broken one hides no other.
# Settings delivered from the Claude admin console are not on disk.
policy_notes=''
if [ "$action" == install ]; then
    managed="${CLAUDEBAR_MANAGED_DIR:-/Library/Application Support/ClaudeCode}"
    mdm="${CLAUDEBAR_MDM_DIR:-/Library/Managed Preferences}"
    policy=$(
        {
            for file in "$managed/managed-settings.json" "$managed"/managed-settings.d/*.json; do
                [ -f "$file" ] && jq -c 'objects' "$file" 2>/dev/null
            done
            for file in "$mdm/com.anthropic.claudecode.plist" "$mdm/$(id -un)/com.anthropic.claudecode.plist"; do
                [ -f "$file" ] && plutil -convert json -o - "$file" 2>/dev/null | jq -c 'objects' 2>/dev/null
            done
            true
        } | jq -s .
    ) || policy='[]'
    if jq -e 'any(.[]; .disableAllHooks == true)' <<<"$policy" >/dev/null; then
        policy_notes+="  warning: your organization turns off hooks and custom status lines; ClaudeBar will receive nothing"$'\n'
    elif jq -e 'any(.[]; .allowManagedHooksOnly == true)' <<<"$policy" >/dev/null; then
        policy_notes+="  warning: your organization allows only its own hooks; ClaudeBar will show limits but no sessions or alerts"$'\n'
    fi
    if jq -e 'any(.[]; .statusLine != null)' <<<"$policy" >/dev/null; then
        policy_notes+="  warning: your organization sets the status line; ClaudeBar will show no limits"$'\n'
    fi
fi

# settings.json first: when it cannot be written, nothing else changes either.
if [ "$(jq -S . <<<"$updated")" == "$(jq -S . <<<"$current")" ]; then
    echo "Claude Code settings: no change needed ($settings)"
else
    if [ -f "$target" ]; then
        # The process id keeps two runs within one second from overwriting each other's backup.
        backup="$settings.claudebar-backup-$(date +%Y%m%d-%H%M%S)-$$"
        cp -p "$target" "$backup" || die "could not back up $settings; nothing changed"
        echo "Backed up $settings to $backup"
    fi
    tmp="$target.claudebar-tmp.$$"
    if ! { jq . <<<"$updated" >"$tmp" && chmod "$mode" "$tmp" && mv -f "$tmp" "$target"; }; then
        rm -f "$tmp"
        die "could not write $settings; nothing changed"
    fi
    echo "Claude Code settings: updated $settings"
fi

if [ "$save_original" == true ]; then
    mkdir -p -m 700 "$root"
    printf '%s' "$status_command" >"$original"
    chmod 600 "$original"
elif [ "$action" == uninstall ]; then
    rm -f "$original"
fi
update_profiles

echo "  $status_note"
printf '%s' "$policy_notes"
