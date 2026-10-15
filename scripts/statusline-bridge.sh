#!/bin/bash
# Status line bridge for ClaudeBar: reads Claude Code's status line JSON on stdin and
# records limits and cost in limits/<session_id>.json. Call it in the background from
# the status line script; it prints nothing and always exits 0.

umask 077
IFS= read -r -d '' payload
exec >/dev/null 2>&1
command -v jq || exit 0

root="${CLAUDEBAR_DIR:-$HOME/Library/Application Support/ClaudeBar}"
dir="$root/limits"

session=$(jq -r '.session_id // empty' <<<"$payload")
# The id becomes a file name: anything else could escape the folder.
[[ "$session" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
file="$dir/$session.json"

mkdir -p -m 700 "$root" "$dir" || exit 0
# The sandboxed app can write into limits/ and this script runs outside the sandbox. A check
# before opening could be raced, so the file is opened once without following a symlink and
# without waiting on a FIFO, and read only if that open is a regular file.
previous=''
if [ -e "$file" ]; then
    previous=$(perl -MFcntl -e 'sysopen(my $f, $ARGV[0], O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or exit; -f $f or exit; read($f, my $b, 65536); print $b' "$file")
fi

# Private mode, switched on in the app: the session name Claude generated is not stored.
private=false
[ -e "$root/events/private-mode" ] && private=true
# Another profile, often another account: its limits must not mix with the default one's.
config_dir=${CLAUDE_CONFIG_DIR:-}
config_dir=${config_dir%/}
[ "$config_dir" == "$HOME/.claude" ] && config_dir=''

# The payload goes in on stdin: on the command line a large one would exceed ARG_MAX.
# -e: no output (nothing new to record) is a failure and leaves the file alone.
record=$(jq -c -e --arg previous "$previous" --argjson private "$private" --arg config_dir "$config_dir" '
    def number: if type == "number" then . else 0 end;
    . as $payload
    | ($previous | try fromjson catch {} | if type == "object" then . else {} end) as $previous
    | (now | floor) as $now
    | (now | localtime | strftime("%F")) as $day
    | ($payload.cost.total_cost_usd | number) as $cost
    | {
        session_id: $payload.session_id,
        observed_at: $now,
        cost: $cost,
        day: $day,
        # A session seen for the first time may be a resumed one that carries the cost of
        # earlier days, so only what it spends from now on counts.
        day_start_cost: (
            if $previous.day == $day then ($previous.day_start_cost | number)
            elif $previous.day != null then ($previous.cost | number)
            else $cost end
        ),
        # The name Claude Code shows: set with --name or /rename, else its generated title.
        session_name: (if $private then null else ($payload.session_name | if type == "string" and . != "" then .[0:120] else null end) end),
        config_dir: (if $config_dir == "" then null else $config_dir end),
        # Limits come only after the first API response, so until then their absence says nothing.
        answered: (if ($payload.cost.total_api_duration_ms | number) > 0 then true else null end),
        rate_limits: (
            { five_hour: $payload.rate_limits.five_hour, seven_day: $payload.rate_limits.seven_day }
            # A window without both numbers has not started or is incomplete: leave it out.
            | with_entries(select(
                (.value | type) == "object"
                and (.value.used_percentage | type) == "number"
                and (.value.resets_at | type) == "number"
            ))
            | map_values({ used_percentage, resets_at })
        )
    }
    | if .rate_limits == {} then del(.rate_limits) else . end
    | if .session_name == null then del(.session_name) else . end
    | if .config_dir == null then del(.config_dir) else . end
    | if .answered == null then del(.answered) else . end
    # The status line refreshes many times a minute and every write wakes ClaudeBar. A record
    # that differs only in time and cost waits until the next refresh a minute or more after
    # the last write; until then the stored cost stays behind.
    | if ($previous.observed_at | number) > $now - 60
        and del(.observed_at, .cost) == ($previous | del(.observed_at, .cost))
      then empty else . end
' <<<"$payload") || exit 0

# Written next to limits/, where the app cannot reach, then renamed in: a temporary file
# inside limits/ could be swapped for a symlink before the write, and creating it would
# wake the app even when nothing is renamed in. -h replaces a symlinked target itself.
tmp="$root/.$session.limits.$$"
printf '%s\n' "$record" >"$tmp" && mv -fh "$tmp" "$file" || rm -f "$tmp"
exit 0
