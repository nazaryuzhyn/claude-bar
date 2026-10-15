#!/bin/bash
# Tests for hook.sh and statusline-bridge.sh against a scratch CLAUDEBAR_DIR.
set -u
cd "$(dirname "$0")"

# A broken edit once left hook.sh holding this harness, which then ran itself until the
# user's process limit was gone. A nested start stops at once instead.
if [ -n "${CLAUDEBAR_HOOK_TESTS:-}" ]; then
    echo "test-hooks.sh started from inside itself; is hook.sh overwritten?" >&2
    exit 1
fi
export CLAUDEBAR_HOOK_TESTS=1

for script in hook.sh statusline-bridge.sh; do
    bash -n "$script" || { echo "FAIL $script does not parse" >&2; exit 1; }
done

CLAUDEBAR_DIR=$(mktemp -d)
export CLAUDEBAR_DIR
trap 'rm -rf "$CLAUDEBAR_DIR"' EXIT
events="$CLAUDEBAR_DIR/events"
limits="$CLAUDEBAR_DIR/limits"
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

# Runs a script with a payload; records its stdout and exit code.
run() {
    local script=$1 payload=$2
    output=$(printf '%s' "$payload" | "./$script")
    status=$?
}

field() {
    jq -r "$2" "$1" 2>/dev/null
}

long=$(printf 'line one\nline two %.0s' {1..40})

# hook.sh
run hook.sh '{"session_id":"s1","hook_event_name":"SessionStart","cwd":"/Users/me/api-gateway","session_title":"Add rate limiting","source":"startup"}'
check "SessionStart exits 0" 0 "$status"
check "SessionStart prints nothing" "" "$output"
check "SessionStart state" working "$(field "$events/s1.json" .state)"
check "SessionStart title" "Add rate limiting" "$(field "$events/s1.json" .title)"
check "SessionStart cwd" /Users/me/api-gateway "$(field "$events/s1.json" .cwd)"
check "host is a bundle id or absent" true "$(field "$events/s1.json" '(.host // "") | test("^[A-Za-z0-9.-]*$")')"

run hook.sh '{"session_id":"s7","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/web"}'
jq '.host = "com.example.Terminal"' "$events/s7.json" >"$events/s7.tmpjson" && mv "$events/s7.tmpjson" "$events/s7.json"
run hook.sh '{"session_id":"s7","hook_event_name":"Stop","cwd":"/Users/me/web","last_assistant_message":"ok"}'
check "a known host is kept, not looked up again" com.example.Terminal "$(field "$events/s7.json" .host)"
check "SessionStart has no message" null "$(field "$events/s1.json" .message)"
check "at is a number" number "$(field "$events/s1.json" '.at | type')"
check "events folder is private" 700 "$(stat -f %Lp "$events")"
check "event file is private" 600 "$(stat -f %Lp "$events/s1.json")"

CLAUDE_PROJECT_DIR=/Users/me/api-gateway run hook.sh '{"session_id":"s1","hook_event_name":"Notification","cwd":"/Users/me/api-gateway/src/deep","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}'
check "the project folder names the session, not the current cd" /Users/me/api-gateway "$(field "$events/s1.json" .cwd)"
check "permission prompt waits" waiting "$(field "$events/s1.json" .state)"
check "permission prompt message" "Claude needs your permission to use Bash" "$(field "$events/s1.json" .message)"
check "title survives later events" "Add rate limiting" "$(field "$events/s1.json" .title)"

run hook.sh '{"session_id":"s1","hook_event_name":"PostToolUse","cwd":"/Users/me/api-gateway","tool_name":"Bash"}'
check "PostToolUse works again" working "$(field "$events/s1.json" .state)"
check "PostToolUse clears the message" null "$(field "$events/s1.json" .message)"

run hook.sh "$(jq -n --arg m "$long" '{session_id:"s1",hook_event_name:"Stop",cwd:"/Users/me/api-gateway",last_assistant_message:$m}')"
check "Stop is done" done "$(field "$events/s1.json" .state)"
check "Stop message is clipped to 150" 150 "$(field "$events/s1.json" '.message | length')"
check "Stop message has no line breaks" false "$(field "$events/s1.json" '.message | test("[\r\n]")')"

run hook.sh '{"session_id":"s1","hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"idle_prompt"}'
check "idle prompt is ignored" done "$(field "$events/s1.json" .state)"

run hook.sh '{"session_id":"s1","hook_event_name":"UserPromptSubmit","cwd":"/Users/me/api-gateway","prompt":"secret prompt text"}'
check "UserPromptSubmit prints nothing" "" "$output"
check "UserPromptSubmit works" working "$(field "$events/s1.json" .state)"
check "the prompt is not stored" no "$(grep -q 'secret prompt text' "$events/s1.json" && echo yes || echo no)"

run hook.sh '{"session_id":"s1","hook_event_name":"PostToolUse","cwd":"/Users/me/api-gateway","tool_name":"Read"}'
check "a tool call right after does not rewrite a working session" UserPromptSubmit "$(field "$events/s1.json" .event)"

jq '.at -= 120' "$events/s1.json" >"$events/s1.tmpjson" && mv "$events/s1.tmpjson" "$events/s1.json"
run hook.sh '{"session_id":"s1","hook_event_name":"PostToolUse","cwd":"/Users/me/api-gateway","tool_name":"Read"}'
check "a tool call a minute later refreshes the time" PostToolUse "$(field "$events/s1.json" .event)"

jq --arg at "a[\$(touch $CLAUDEBAR_DIR/pwned)]" '.at = $at' "$events/s1.json" >"$events/s1.tmpjson" && mv "$events/s1.tmpjson" "$events/s1.json"
run hook.sh '{"session_id":"s1","hook_event_name":"PostToolUse","cwd":"/Users/me/api-gateway","tool_name":"Read"}'
check "a crafted time in the file runs no command" no "$( [ -e "$CLAUDEBAR_DIR/pwned" ] && echo yes || echo no)"
check "a crafted time is replaced by a real one" number "$(field "$events/s1.json" '.at | type')"

run hook.sh '{"session_id":"s1","hook_event_name":"PreCompact"}'
check "unknown event exits 0" 0 "$status"
check "unknown event changes nothing" working "$(field "$events/s1.json" .state)"

run hook.sh '{"session_id":"s1","hook_event_name":"SessionEnd","reason":"prompt_input_exit"}'
check "SessionEnd removes the file" no "$( [ -e "$events/s1.json" ] && echo yes || echo no)"

run hook.sh '{"session_id":"../escape","hook_event_name":"Stop"}'
check "path-like session id exits 0" 0 "$status"
check "path-like session id writes nothing" 0 "$(find "$CLAUDEBAR_DIR" -name '*escape*' | wc -l | tr -d ' ')"

run hook.sh 'not json at all'
check "broken stdin exits 0" 0 "$status"

printf '{"broken' >"$events/s2.json"
run hook.sh '{"session_id":"s2","hook_event_name":"Stop","last_assistant_message":"Done."}'
check "a corrupt previous file is replaced" done "$(field "$events/s2.json" .state)"

printf '{"state":"working","at":1}{}' >"$events/s9.json"
run hook.sh '{"session_id":"s9","hook_event_name":"Stop","last_assistant_message":"Done."}'
check "a file with two JSON values is replaced" done "$(field "$events/s9.json" .state)"

printf '{"state":"working\u001f09","at":1,"title":"Kept"}' >"$events/s10.json"
run hook.sh '{"session_id":"s10","hook_event_name":"PostToolUse"}'
check "a separator inside the stored state shifts no field" PostToolUse "$(field "$events/s10.json" .event)"
check "the record survives a cleaned summary" Kept "$(field "$events/s10.json" .title)"

# The sandboxed app can write into events/; the hook runs outside the sandbox.
outside=$(mktemp -d)
printf '{"state":"working","at":1,"title":"Secret from outside"}' >"$outside/private.json"
ln -s "$outside" "$events/s11.json"
run hook.sh '{"session_id":"s11","hook_event_name":"Stop","last_assistant_message":"Done."}'
check "a symlink to a folder gets nothing written into that folder" "private.json" "$(ls -A "$outside" | tr '\n' ' ' | sed 's/ $//')"
check "a symlink to a folder is replaced by the record" "regular done" "$([ -L "$events/s11.json" ] && echo link || echo regular) $(field "$events/s11.json" .state)"
ln -s "$outside/private.json" "$events/s12.json"
run hook.sh '{"session_id":"s12","hook_event_name":"Notification","message":"Allow?"}'
check "a symlinked file is not read" null "$(field "$events/s12.json" .title)"
check "a symlinked file is left as it was" "Secret from outside" "$(field "$outside/private.json" .title)"
rm -rf "$outside"

run hook.sh '{"session_id":"s13","hook_event_name":"Notification","message":"Allow?"}'
head -c 1200000 /dev/zero | tr '\0' a | jq -Rs '{session_id: "s13", hook_event_name: "PostToolUse", tool_response: {content: .}}' >"$CLAUDEBAR_DIR/big.json"
run hook.sh "$(cat "$CLAUDEBAR_DIR/big.json")"
check "a payload over 1 MB is read" working "$(field "$events/s13.json" .state)"
rm -f "$CLAUDEBAR_DIR/big.json"

before=$(stat -f %Fm "$events")
run hook.sh '{"session_id":"s13","hook_event_name":"PostToolUse"}'
check "a throttled tool call leaves the events folder untouched" "$before" "$(stat -f %Fm "$events")"

: >"$events/private-mode"
run hook.sh '{"session_id":"s14","hook_event_name":"SessionStart","session_title":"Secret plan","cwd":"/Users/me/web"}'
run hook.sh "$(jq -n --arg m 'Secret answer' '{session_id:"s14",hook_event_name:"Stop",last_assistant_message:$m}')"
check "private mode stores no title" null "$(field "$events/s14.json" .title)"
check "private mode stores no message" null "$(field "$events/s14.json" .message)"
check "private mode still records the state and folder" "done /Users/me/web" "$(field "$events/s14.json" '"\(.state) \(.cwd)"')"
rm -f "$events/private-mode"

# Output goes to /dev/null rather than a capture: a hook stuck on the FIFO would leave a
# reader holding the capture's pipe, and this harness would hang instead of failing.
mkfifo "$events/s15.json"
printf '%s' '{"session_id":"s15","hook_event_name":"Stop"}' | perl -e 'alarm 5; exec @ARGV' ./hook.sh >/dev/null 2>&1
status=$?
[ -p "$events/s15.json" ] && : <>"$events/s15.json"
check "a FIFO in place of the record does not hang the hook" 0 "$status"
# Reading a FIFO that is still there would block, so its type is checked first.
check "the FIFO is replaced by the record" "regular done" "$(if [ -p "$events/s15.json" ]; then echo fifo; else echo "regular $(field "$events/s15.json" .state)"; fi)"

# Limits > Turn on in Settings leaves a request that the next hook event hands to configure.sh.
mkdir -p "$CLAUDEBAR_DIR/bin"
printf '#!/bin/bash\necho "$@" >>"%s/configure-calls"\n' "$CLAUDEBAR_DIR" >"$CLAUDEBAR_DIR/bin/configure.sh"
chmod 700 "$CLAUDEBAR_DIR/bin/configure.sh"
run hook.sh '{"session_id":"s16","hook_event_name":"PostToolUse"}'
check "without a request configure.sh is not run" no "$([ -e "$CLAUDEBAR_DIR/configure-calls" ] && echo yes || echo no)"
: >"$events/statusline-request"
run hook.sh '{"session_id":"s16","hook_event_name":"PostToolUse"}'
check "a request runs configure.sh add-statusline" add-statusline "$(cat "$CLAUDEBAR_DIR/configure-calls" 2>/dev/null)"
check "the request is removed" no "$([ -e "$events/statusline-request" ] && echo yes || echo no)"
check "the hook still prints nothing" "" "$output"
rm -rf "$CLAUDEBAR_DIR/bin" "$CLAUDEBAR_DIR/configure-calls"

check "no temporaries are left in events" "" "$(find "$events" -name '.*' -type f)"
check "no temporaries are left next to the folders" "" "$(find "$CLAUDEBAR_DIR" -maxdepth 1 -name '.*' -type f)"

# statusline-bridge.sh
today=$(date +%F)
run statusline-bridge.sh '{"session_id":"s1","cost":{"total_cost_usd":1.25},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1791900000},"seven_day":{"used_percentage":41,"resets_at":1792300000}}}'
check "bridge exits 0" 0 "$status"
check "bridge prints nothing" "" "$output"
check "bridge keeps five_hour" 23.5 "$(field "$limits/s1.json" .rate_limits.five_hour.used_percentage)"
check "bridge keeps seven_day reset" 1792300000 "$(field "$limits/s1.json" .rate_limits.seven_day.resets_at)"
check "bridge cost" 1.25 "$(field "$limits/s1.json" .cost)"
check "bridge day" "$today" "$(field "$limits/s1.json" .day)"
check "a session seen for the first time counts from its current cost" 1.25 "$(field "$limits/s1.json" .day_start_cost)"
check "limits file is private" 600 "$(stat -f %Lp "$limits/s1.json")"

check "no session_name leaves the key out" false "$(field "$limits/s1.json" 'has("session_name")')"

run statusline-bridge.sh '{"session_id":"s4","session_name":"Fix flaky login test","cost":{"total_cost_usd":1}}'
check "bridge keeps Claude Code's session name" "Fix flaky login test" "$(field "$limits/s4.json" .session_name)"
run statusline-bridge.sh "$(jq -n --arg n "$(printf 'x%.0s' {1..300})" '{session_id:"s5",session_name:$n}')"
check "a long session name is cut to 120" 120 "$(field "$limits/s5.json" '.session_name | length')"
run statusline-bridge.sh '{"session_id":"s6","session_name":""}'
check "an empty session name is left out" false "$(field "$limits/s6.json" 'has("session_name")')"

run statusline-bridge.sh '{"session_id":"s1","cost":{"total_cost_usd":2.5}}'
check "same day keeps the day start" 1.25 "$(field "$limits/s1.json" .day_start_cost)"
check "no rate_limits leaves the key out" false "$(field "$limits/s1.json" 'has("rate_limits")')"

jq '.day = "2000-01-01" | .cost = 5' "$limits/s1.json" >"$limits/s1.tmpjson" && mv "$limits/s1.tmpjson" "$limits/s1.json"
run statusline-bridge.sh '{"session_id":"s1","cost":{"total_cost_usd":7}}'
check "a new day starts from the last cost" 5 "$(field "$limits/s1.json" .day_start_cost)"

run statusline-bridge.sh '{"session_id":"s3","rate_limits":{"five_hour":{"used_percentage":0,"resets_at":null},"seven_day":{"used_percentage":12,"resets_at":1792300000}}}'
check "a window without a reset is left out" '["seven_day"]' "$(field "$limits/s3.json" '.rate_limits | keys | tojson')"
check "missing cost counts as 0" 0 "$(field "$limits/s3.json" .cost)"

steady='{"session_id":"s8","session_name":"Steady","cost":{"total_cost_usd":1},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1791900000}}}'
observed_ago() {
    jq --argjson at $(($(date +%s) - $1)) '.observed_at = $at' "$limits/s8.json" >"$limits/s8.tmpjson" && mv "$limits/s8.tmpjson" "$limits/s8.json"
    marker=$(field "$limits/s8.json" .observed_at)
}
run statusline-bridge.sh "$steady"
observed_ago 10
before=$(stat -f %Fm "$limits")
run statusline-bridge.sh "$(jq -c '.cost.total_cost_usd = 2' <<<"$steady")"
check "only a new cost within a minute leaves the file alone" "$marker" "$(field "$limits/s8.json" .observed_at)"
check "a skipped write leaves the limits folder untouched" "$before" "$(stat -f %Fm "$limits")"
check "the skipped write keeps the old cost" 1 "$(field "$limits/s8.json" .cost)"
run statusline-bridge.sh "$(jq -c '.rate_limits.five_hour.used_percentage = 31' <<<"$steady")"
check "a new limit is written at once" 31 "$(field "$limits/s8.json" .rate_limits.five_hour.used_percentage)"
observed_ago 10
run statusline-bridge.sh "$(jq -c '.rate_limits.five_hour.used_percentage = 31 | .session_name = "Renamed"' <<<"$steady")"
check "a new session name is written at once" Renamed "$(field "$limits/s8.json" .session_name)"
observed_ago 61
run statusline-bridge.sh "$(jq -c '.rate_limits.five_hour.used_percentage = 31 | .session_name = "Renamed"' <<<"$steady")"
check "after a minute the time moves on unchanged data" true "$(field "$limits/s8.json" ".observed_at > $marker")"

run statusline-bridge.sh '{"session_id":"a b","cost":{"total_cost_usd":1}}'
check "bridge rejects a session id with a space" 0 "$(find "$limits" -name 'a*' | wc -l | tr -d ' ')"

printf '{"day":"2000-01-01","cost":3} {}' >"$limits/s9.json"
run statusline-bridge.sh '{"session_id":"s9","cost":{"total_cost_usd":4}}'
check "a limits file with two JSON values is replaced" 4 "$(field "$limits/s9.json" .day_start_cost)"

outside=$(mktemp -d)
printf '{"day":"%s","cost":1,"day_start_cost":0}' "$today" >"$outside/private.json"
ln -s "$outside" "$limits/s10.json"
run statusline-bridge.sh '{"session_id":"s10","cost":{"total_cost_usd":2}}'
check "bridge writes nothing into a symlinked folder" "private.json" "$(ls -A "$outside" | tr '\n' ' ' | sed 's/ $//')"
check "bridge replaces a symlink with the record" "regular 2" "$([ -L "$limits/s10.json" ] && echo link || echo regular) $(field "$limits/s10.json" .cost)"
ln -s "$outside/private.json" "$limits/s11.json"
run statusline-bridge.sh '{"session_id":"s11","cost":{"total_cost_usd":2}}'
check "bridge does not read a symlinked file" 2 "$(field "$limits/s11.json" .day_start_cost)"
rm -rf "$outside"

: >"$events/private-mode"
run statusline-bridge.sh '{"session_id":"s12","session_name":"Secret plan","cost":{"total_cost_usd":1}}'
check "private mode stores no session name" false "$(field "$limits/s12.json" 'has("session_name")')"
rm -f "$events/private-mode"

run statusline-bridge.sh '{"session_id":"s13","cost":{"total_cost_usd":1}}'
check "the default profile records no config_dir" false "$(field "$limits/s13.json" 'has("config_dir")')"
output=$(printf '%s' '{"session_id":"s13","cost":{"total_cost_usd":1}}' | CLAUDE_CONFIG_DIR=/Users/me/.claude-work/ ./statusline-bridge.sh)
check "another profile is recorded without a trailing slash" /Users/me/.claude-work "$(field "$limits/s13.json" .config_dir)"

output=$(printf '%s' '{"session_id":"s13","cost":{"total_cost_usd":1}}' | CLAUDE_CONFIG_DIR="$HOME/.claude/" ./statusline-bridge.sh)
check "an explicit default profile records no config_dir" false "$(field "$limits/s13.json" 'has("config_dir")')"

run statusline-bridge.sh '{"session_id":"s16","cost":{"total_cost_usd":0,"total_api_duration_ms":0}}'
check "no answer yet is not recorded" false "$(field "$limits/s16.json" 'has("answered")')"
run statusline-bridge.sh '{"session_id":"s16","cost":{"total_cost_usd":0.2,"total_api_duration_ms":2300}}'
check "the first answer is recorded" true "$(field "$limits/s16.json" .answered)"

mkfifo "$limits/s17.json"
printf '%s' '{"session_id":"s17","cost":{"total_cost_usd":1}}' | perl -e 'alarm 5; exec @ARGV' ./statusline-bridge.sh >/dev/null 2>&1
status=$?
[ -p "$limits/s17.json" ] && : <>"$limits/s17.json"
check "a FIFO in place of the limits record does not hang the bridge" 0 "$status"

check "no temporaries are left in limits" "" "$(find "$limits" -name '.*' -type f)"
check "no temporaries are left next to limits" "" "$(find "$CLAUDEBAR_DIR" -maxdepth 1 -name '.*' -type f)"

echo "$checks checks, $failures failed"
[ "$failures" -eq 0 ]
