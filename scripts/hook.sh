#!/bin/bash
# Claude Code hook for ClaudeBar: records each session's state in events/<session_id>.json.
# Registered as an async hook. It prints nothing (stdout of SessionStart and
# UserPromptSubmit hooks becomes model context) and always exits 0, so a failure
# here never reaches Claude Code.

umask 077
IFS= read -r -d '' payload
exec >/dev/null 2>&1
command -v jq || exit 0

root="${CLAUDEBAR_DIR:-$HOME/Library/Application Support/ClaudeBar}"
dir="$root/events"

# One jq call for the time and three fields; the unit separator keeps empty fields in place.
# The time comes first, so a separator inside a field cannot shift it.
IFS=$'\x1f' read -r now session event type < <(
    jq -r '[now | floor] + ([.session_id, .hook_event_name, .notification_type] | map(. // "" | tostring)) | map(tostring) | join("\u001f")' <<<"$payload"
)
# Bash arithmetic would evaluate anything else, including a command in an array index.
[[ "$now" =~ ^[0-9]+$ ]] || exit 0
# The id becomes a file name: anything else could escape the folder.
[[ "$session" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
file="$dir/$session.json"

# The app asked for a status line (Settings, Limits > Turn on) but cannot edit Claude Code's
# settings from its sandbox, so the next hook event does. The marker carries no data: only
# ClaudeBar's own status line is ever added, and only where there is none.
if [ -e "$dir/statusline-request" ]; then
    rm -f "$dir/statusline-request"
    [ -x "$root/bin/configure.sh" ] && "$root/bin/configure.sh" add-statusline >/dev/null 2>&1
fi

case "$event" in
    SessionEnd) rm -f "$file"; exit 0 ;;
    SessionStart | UserPromptSubmit | PostToolUse) state=working ;;
    Stop) state=done ;;
    Notification)
        # The settings matcher already narrows this; the check covers a payload that names its type.
        case "$type" in
            "" | permission_prompt | elicitation_dialog) state=waiting ;;
            *) exit 0 ;;
        esac
        ;;
    *) exit 0 ;;
esac

mkdir -p -m 700 "$root" "$dir" || exit 0
previous=''
previous_state=''
previous_at=0
previous_host=''
# The sandboxed app can write into events/ and this hook runs outside the sandbox. A check
# before opening could be raced, so the file is opened once without following a symlink and
# without waiting on a FIFO, and read only if that open is a regular file. One parse then gives
# the fields the checks below need, cleaned so none can hold a separator, and the record itself.
if [ -e "$file" ]; then
    raw=$(perl -MFcntl -e 'sysopen(my $f, $ARGV[0], O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or exit; -f $f or exit; read($f, my $b, 65536); print $b' "$file")
    { IFS=$'\x1f' read -r previous_state previous_at previous_host; IFS= read -r previous; } < <(
        jq -nrc --arg previous "$raw" '
            $previous | try fromjson catch {} | if type == "object" then . else {} end
            | "\(.state | if . == "working" or . == "waiting" or . == "done" then . else "" end)\u001f\(.at | if type == "number" and . >= 0 then floor else 0 end)\u001f\(.host | if type == "string" then gsub("[^A-Za-z0-9.-]"; "") else "" end)",
              tojson
        '
    )
fi
[ -n "$previous" ] || previous='{}'
[[ "$previous_at" =~ ^[0-9]+$ ]] || previous_at=0

# Private mode, switched on in the app: nothing Claude wrote or titled is stored.
private=false
[ -e "$dir/private-mode" ] && private=true

# Tool calls come in bursts. A session already shown as working only needs its time
# refreshed now and then, and every write wakes ClaudeBar.
if [ "$event" == PostToolUse ] && [ "$previous_state" == working ] && [ $((now - previous_at)) -lt 60 ]; then
    exit 0
fi

# The app the session runs in (PhpStorm, VS Code, Terminal…), found once by walking up
# the process tree: ClaudeBar shows no banner while that app is in front.
host_bundle_id() {
    local pid=$PPID parent command level
    for level in 1 2 3 4 5 6 7 8 9 10 11 12; do
        read -r parent command < <(ps -o ppid=,comm= -p "$pid") || return
        case "$command" in
            *.app/*)
                /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${command%%.app/*}.app/Contents/Info.plist"
                return
                ;;
        esac
        [ "${parent:-0}" -gt 1 ] || return
        pid=$parent
    done
}
host=''
if [ "$event" == SessionStart ] || { [ -z "$previous_host" ] && [ "$event" != PostToolUse ]; }; then
    host=$(host_bundle_id 2>/dev/null)
    [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || host=''
fi

# The payload goes in on stdin: on the command line a large one would exceed ARG_MAX.
record=$(jq -c -e \
    --argjson previous "$previous" \
    --arg state "$state" \
    --arg event "$event" \
    --arg project "${CLAUDE_PROJECT_DIR:-}" \
    --arg host "$host" \
    --argjson private "$private" \
    --argjson at "$now" '
    def clip: gsub("[\r\n]+"; " ") | .[0:150];
    . as $payload
    | {
        session_id: $payload.session_id,
        state: $state,
        event: $event,
        at: $at,
        # The project folder names the session; the payload cwd follows every cd the agent makes.
        cwd: (if $project != "" then $project else ($payload.cwd // $previous.cwd) end),
        title: (
            if $private then null
            elif $event == "SessionStart" then ($payload.session_title // $previous.title)
            else $previous.title end
        ),
        host: (if $host != "" then $host else $previous.host end),
        message: (
            if $private then null
            elif $event == "Stop" then (($payload.last_assistant_message // "") | clip)
            elif $event == "Notification" then (($payload.message // "") | clip)
            else null end
        )
    }
    | with_entries(select(.value != null and .value != ""))
' <<<"$payload") || exit 0

# Written next to events/, where the app cannot reach, then renamed in: a temporary file
# inside events/ could be swapped for a symlink before the write, and creating it would
# wake the app. -h replaces a symlinked target itself.
tmp="$root/.$session.event.$$"
printf '%s\n' "$record" >"$tmp" && mv -fh "$tmp" "$file" || rm -f "$tmp"

# The first session after a restart brings ClaudeBar back, in the background. Only with the
# default data folder: a custom CLAUDEBAR_DIR is a test or scratch run the app never reads.
if [ "$event" == SessionStart ] && [ -z "${CLAUDEBAR_DIR:-}" ] && ! pgrep -x ClaudeBar; then
    open -g -a ClaudeBar
fi
exit 0
