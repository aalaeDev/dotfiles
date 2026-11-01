#!/usr/bin/env bash

# Claude Code sessions in Waybar (custom/claude) and the notification center (nc-daemon.sh).
# Hooks keep one state file per session; a notification says when a turn is over or needs you.
#
# Progress comes from the model when it reports steps through the step tool (claude-widget-mcp.py).
# Until then it's an estimate, marked ~: the share of past turns that were over after this long.
#
#   claude-widget.sh --hook <event>    Called by Claude Code, with the hook's JSON on stdin
#   claude-widget.sh --status          Waybar JSON, with a placeholder for the animated spark
#   claude-widget.sh --watch           Waybar stream: --status, animated
#   claude-widget.sh --next|--previous Show another session in the pill
#   claude-widget.sh --nc              Active sessions as JSON, for nc-daemon.sh
#   claude-widget.sh --install-hooks   Add the hooks and the step tool to Claude Code. Safe to rerun

# --- Configuration ---
BIN="$(dirname "$(readlink -f "$0")")"
# shellcheck source=/dev/null
source "$BIN/rice-env.sh"
STATE="${XDG_RUNTIME_DIR:-/tmp}/claude-widget"
SELECTED="$STATE/.selected"          # The session the pill shows
SWITCH_GAP=300                       # Milliseconds between session switches
NC_CARDS=4                           # Sessions with a card in the notification center
HISTORY="$RICE_CACHE/claude-turns"   # Seconds per finished turn, one a line
CLAUDE_HOME="$HOME/.claude"
HISTORY_SIZE=200
MIN_NOTIFY=15     # Seconds; shorter turns are still on your screen
DONE_LINGER=60    # Seconds a finished session stays visible
STALE_GRACE=10    # Seconds before Claude Code's own session list is trusted over a fresh hook
MIN_SAMPLES=10    # Turns of history before the estimate uses them
FALLBACK_TAU=60   # Seconds; time constant of the estimate without history
SPARK=(✢ ✳ ✻ ✽ ✻ ✳)  # Claude Code's spinner. All from one font: ✶ isn't, and would make the pill jump
FRAME="@spark@"       # Stands in for the spark until --watch fills it in
FRAME_SECONDS=0.2
FRAMES_PER_READ=5     # So the state is read once a second
CHECK="<span size='130%' rise='-1451'>󰄬</span>"
BAR_CELLS=10
NAME_WIDTH=26         # Characters of the session's name in the bar
HOOK_EVENTS=(UserPromptSubmit PreToolUse PostToolUse Notification Stop SessionEnd)
STEP_TOOL="mcp__claude-widget__step"
STEP_HINT="If this request takes several steps, call $STEP_TOOL (load it with ToolSearch if needed) with total set to your plan's size and done 0 before starting, then again with done and a few-word note as each step finishes. It only draws a progress bar. Skip it for quick answers."

# --- Helpers ---
duration() {
    local seconds=$1
    if (( seconds >= 60 )); then
        printf '%dm %ds' $(( seconds / 60 )) $(( seconds % 60 ))
    else
        printf '%ds' "$seconds"
    fi
}

# Replaces its own earlier notification, so "needs you" doesn't stay next to "done"
notify() {
    notify-send -a "Claude Code" -i claude -h "string:x-canonical-private-synchronous:claude-$1" "$2" "$3"
}

refresh_widgets() {
    pkill -USR1 -f '^(/usr/bin/env )?(/[^ ]*/)?bash [^ ]*/nc-daemon\.sh$'
}

# Applies a jq filter to a session's state through a temp file, so readers never see half of it
update_state() {
    local file=$1 filter=$2
    shift 2
    jq "$@" "$filter" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

record_duration() {
    echo "$1" >> "$HISTORY"
    tail -n "$HISTORY_SIZE" "$HISTORY" > "$HISTORY.tmp" && mv "$HISTORY.tmp" "$HISTORY"
}

# The session's title, as in Claude Code's own session list: from /rename, else generated
transcript_title() {
    grep -a -E '^\{"type":"(custom|ai)-title"' "$1" 2> /dev/null | tail -n 1 | jq -r '.customTitle // .aiTitle // empty'
}

# The title is generated a little into the first turn, so look until there is one
fill_title() {
    local file=$1 transcript=$2 title
    [[ "$(jq -r '.title // ""' "$file")" == "" ]] || return 0
    title=$(transcript_title "$transcript")
    [[ -n "$title" ]] || return 0
    update_state "$file" '.title = $title' --arg title "$title"
    refresh_widgets
}

# --- Hooks ---
hook() {
    local event=$1 input session cwd file state started tools now notification transcript
    input=$(cat)
    session=$(jq -r '.session_id // empty' <<< "$input")
    [[ -n "$session" ]] || return 0
    file="$STATE/$session.json"
    transcript=$(jq -r '.transcript_path // ""' <<< "$input")
    now=$(date +%s)
    mkdir -p "$STATE"
    # Tools can run in parallel, and each one fires its hooks
    exec 8> "$STATE/.lock"
    flock 8

    case "$event" in
        UserPromptSubmit)
            cwd=$(jq -r '.cwd // ""' <<< "$input")
            # The repo's name, also from a subfolder
            cwd=$(git -C "$cwd" rev-parse --show-toplevel 2> /dev/null || echo "$cwd")
            jq -n --arg session "$session" --arg project "${cwd##*/}" --arg title "$(transcript_title "$transcript")" --argjson now "$now" \
                '{session: $session, project: $project, title: $title, state: "running", started: $now, updated: $now, tools: 0}' \
                > "$file.tmp" && mv "$file.tmp" "$file"
            refresh_widgets
            echo "$STEP_HINT"
            ;;
        PreToolUse | PostToolUse)
            [[ -f "$file" ]] || return 0
            fill_title "$file" "$transcript"
            state=$(jq -r .state "$file")
            # The permission prompt comes after PreToolUse, so PostToolUse is what ends the wait
            local filter='.updated = $now'
            [[ "$state" == waiting ]] && filter+=' | .state = "running"'
            [[ "$event" == PreToolUse ]] && filter+=' | .tools += 1'
            # Only the main session reports, like savvy-progress: a worker's steps aren't the whole turn
            if [[ "$event" == PostToolUse ]] && jq -e --arg tool "$STEP_TOOL" \
                '.tool_name == $tool and (.agent_id == null)' <<< "$input" > /dev/null; then
                filter+=' | .done = ($input.tool_input.done // .done) | .total = ($input.tool_input.total // .total) | .note = ($input.tool_input.note // .note)'
                update_state "$file" "$filter" --argjson now "$now" --argjson input "$input"
                refresh_widgets
                return 0
            fi
            update_state "$file" "$filter" --argjson now "$now"
            # An if, not &&: this ends the hook, and a failed test would become its exit status
            if [[ "$state" == waiting ]]; then
                refresh_widgets
            fi
            ;;
        Notification)
            [[ -f "$file" ]] || return 0
            notification=$(jq -r '"\(.notification_type // "") \(.message // "")"' <<< "$input")
            [[ "$notification" == *permission* ]] || return 0
            update_state "$file" '.state = "waiting" | .updated = $now' --argjson now "$now"
            refresh_widgets
            notify "$session" "Needs you · $(jq -r 'if (.title // "") != "" then .title else .project end' "$file")" "$(jq -r '.message // "Waiting for permission"' <<< "$input")"
            ;;
        Stop)
            [[ -f "$file" ]] || return 0
            fill_title "$file" "$transcript"
            state=$(jq -r .state "$file")
            [[ "$state" == done ]] && return 0
            started=$(jq -r .started "$file")
            tools=$(jq -r .tools "$file")
            update_state "$file" '.state = "done" | .updated = $now | .finished = $now' --argjson now "$now"
            record_duration $(( now - started ))
            refresh_widgets
            if (( now - started >= MIN_NOTIFY )); then
                notify "$session" "Done · $(jq -r 'if (.title // "") != "" then .title else .project end' "$file")" "Finished in $(duration $(( now - started ))) · $tools tool$( (( tools == 1 )) || echo s)"
            fi
            ;;
        SessionEnd)
            rm -f "$file"
            refresh_widgets
            ;;
    esac
}

# --- Reading ---
# Prints the active sessions with their percent, most urgent first, and drops the stale ones
sessions() {
    local files live history now result
    shopt -s nullglob
    files=("$STATE"/*.json)
    if (( ${#files[@]} == 0 )); then
        echo '[]'
        return
    fi
    local live_files=("$CLAUDE_HOME"/sessions/*.json)
    live=$(jq -s 'map({key: (.sessionId // ""), value: (.status // "")}) | from_entries' /dev/null "${live_files[@]}" 2> /dev/null)
    history=$(jq -Rs 'split("\n") | map(select(length > 0) | tonumber)' "$HISTORY" 2> /dev/null)
    now=$(date +%s)
    result=$(jq -s --argjson live "${live:-null}" --argjson history "${history:-[]}" --argjson now "$now" \
        --argjson linger "$DONE_LINGER" --argjson grace "$STALE_GRACE" \
        --argjson samples "$MIN_SAMPLES" --argjson tau "$FALLBACK_TAU" '
        def rounded: . / 5 | round * 5;
        def estimate($elapsed):
            if ($history | length) >= $samples then
                (($history | map(select(. <= $elapsed)) | length) / ($history | length) * 100)
            else
                ((1 - (($elapsed / $tau) * -1 | exp)) * 100)
            end;
        def stale:
            if $live == null or (now | floor) - .updated < $grace then false
            elif $live[.session] == null then true
            else .state == "running" and $live[.session] == "idle"
            end;
        map(
            .elapsed = ((.finished // $now) - .started)
            | .name = (if (.title // "") != "" then .title else .project end)
            | .reported = ((.total // 0) > 0)
            | .percent = (
                if .state == "done" then 100
                elif .reported then ((.done // 0) / .total * 100 | rounded | [., 95] | min)
                else (estimate(.elapsed) | rounded | [., 95] | min)
                end)
            | .gone = ((.state == "done" and $now - .finished >= $linger) or (.state != "done" and stale))
            | .rank = ({waiting: 0, running: 1, done: 2}[.state]))
        | sort_by(.rank, .percent)' "${files[@]}") || { echo '[]'; return; }
    jq -r '.[] | select(.gone) | .session' <<< "$result" | while read -r session; do
        rm -f "$STATE/$session.json"
    done
    jq 'map(select(.gone | not))' <<< "$result"
}

status() {
    local files
    shopt -s nullglob
    files=("$STATE"/*.json)
    # The usual case: no jq
    if (( ${#files[@]} == 0 )); then
        echo '{"text": ""}'
        return
    fi
    sessions | jq -c --arg selected "$(cat "$SELECTED" 2> /dev/null)" --arg frame "$FRAME" --arg check "$CHECK" \
        --argjson cells "$BAR_CELLS" --argjson width "$NAME_WIDTH" '
        def markup: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        def clock: if . >= 60 then "\(. / 60 | floor)m \(. % 60)s" else "\(.)s" end;
        def word: {running: "Working", waiting: "Needs you", done: "Done"}[.];
        def clip: if length > $width then .[:$width - 1] + "…" else . end;
        def dim: "<span alpha=\"45%\">\(.)</span>";
        # A slim line in the text color, so it follows the theme. The rest of it is the same color, faded
        def bar: (. * $cells / 100 | round) as $on
            | ("━" * $on // "") + ("<span alpha=\"25%\">" + ("━" * ($cells - $on) // "") + "</span>");
        if length == 0 then {text: ""}
        else
            # The session picked by scrolling while it lasts, else the most urgent one
            (map(select(.session == $selected))[0] // .[0]) as $top
            | (map(.session) | sort) as $order
            | ($top.name | clip | markup) as $name
            | any(.[]; .state == "waiting" and .session != $top.session) as $attention
            | {
                text: (
                    (if $top.state == "done" then "\($check)  \($name)  Done \("· \($top.elapsed | clock)" | dim)"
                     elif $top.state == "waiting" then "\($frame)  \($name)  Needs you"
                     else "\($frame)  \($name)  \($top.percent | bar)  "
                        + (if $top.reported then "" else ("~" | dim) end) + "\($top.percent)%"
                     end)
                    + (if length > 1 then "  " + ("\(($order | index($top.session)) + 1)/\(length)" | dim) else "" end)
                    + (if $attention then "  !" else "" end)),
                # Another session needs you: the pill says so without leaving the one you picked
                class: ([$top.state] + (if $attention then ["attention"] else [] end)),
                tooltip: ((sort_by(.session) | map(
                    (if .session == $top.session and ($order | length) > 1 then "● " else "" end)
                    + "\(.name | markup): \(.state | word) · \(if .reported or .state == "done" then "" else "~" end)\(.percent)% · \(.elapsed | clock) · \(.tools) tool\(if .tools == 1 then "" else "s" end)"
                    + (if .reported then "\n  \(.done // 0)/\(.total)\(if .note then " · \(.note | markup)" else "" end)" else "" end)
                ) | join("\n"))
                + (if length > 1 then "\n\nScroll or right-click: switch session" else "" end))
              }
        end'
}

# Moves the pill to the next (1) or previous (-1) session. Sessions keep their order, sorted by id,
# whatever their state, so scrolling always walks the same loop.
switch_session() {
    local next
    # A touchpad flick sends a burst of scroll events, and that should be one step
    if [[ -f "$SELECTED" ]] && (( $(date +%s%3N) - $(date -r "$SELECTED" +%s%3N) < SWITCH_GAP )); then
        return 0
    fi
    next=$(sessions | jq -r --arg selected "$(cat "$SELECTED" 2> /dev/null)" --argjson step "$1" '
        if length == 0 then empty
        else
            (map(select(.session == $selected))[0].session // .[0].session) as $current
            | (map(.session) | sort) as $order
            | $order[(($order | index($current)) + $step + ($order | length)) % ($order | length)]
        end')
    if [[ -n "$next" ]]; then
        echo "$next" > "$SELECTED"
    fi
}

# One line per change for Waybar. Animating only needs a printf, so jq runs once a second at most,
# and not at all with no session. read -t on an idle fd is a sleep without the fork.
watch_status() {
    local tick=0 line="" out="" last="" nap selected="" previous=""
    exec 7<> <(:)
    while true; do
        { read -r selected < "$SELECTED"; } 2> /dev/null
        # A switch shows right away, not at the next read
        if (( tick % FRAMES_PER_READ == 0 )) || [[ "$selected" != "$previous" ]]; then
            line=$(status)
            previous=$selected
        fi
        out=${line//"$FRAME"/${SPARK[tick % ${#SPARK[@]}]}}
        if [[ "$out" != "$last" ]]; then
            printf '%s\n' "$out" || exit 0
            last=$out
        fi
        if [[ "$line" == *class* ]]; then
            nap=$FRAME_SECONDS
            (( tick += 1 ))
        else
            nap=1
            (( tick += FRAMES_PER_READ - tick % FRAMES_PER_READ ))
        fi
        read -r -t "$nap" -u 7
    done
}

# --- Install ---
install_hooks() {
    local settings="$CLAUDE_HOME/settings.json" command="$HOME/.local/bin/claude-widget.sh" event filter
    filter='.permissions.allow = ((.permissions.allow // []) - [$tool] + [$tool])'
    for event in "${HOOK_EVENTS[@]}"; do
        filter+=" | .hooks.$event = (((.hooks.$event // []) | map(select(any(.hooks[]?; (.command // \"\") | test(\"claude-widget\\\\.sh\")) | not)))"
        filter+=" + [{hooks: [{type: \"command\", command: (\$command + \" --hook $event\"), timeout: 5}]}])"
    done
    jq --arg tool "$STEP_TOOL" --arg command "$command" "$filter" "$settings" > "$settings.tmp" \
        && mv "$settings.tmp" "$settings"

    if ! claude mcp get claude-widget &> /dev/null; then
        claude mcp add -s user claude-widget -- "$HOME/.local/bin/claude-widget-mcp.py"
    fi

    # Seed the estimate from the turns already in the transcripts
    if [[ ! -s "$HISTORY" ]]; then
        find "$CLAUDE_HOME/projects" -maxdepth 2 -name '*.jsonl' -print0 \
            | xargs -0 -r jq -r 'select(.subtype == "turn_duration") | .durationMs / 1000 | floor' 2> /dev/null \
            | tail -n "$HISTORY_SIZE" > "$HISTORY"
    fi
}

# --- Main ---
case "${1:-}" in
    --hook) hook "$2" ;;
    --watch) watch_status ;;
    --next) switch_session 1 ;;
    --previous) switch_session -1 ;;
    # The most urgent ones if they don't all fit, in a steady order. The slug names their widgets
    --nc) sessions | jq --argjson max "$NC_CARDS" '.[:$max] | sort_by(.session) | map(.slug = "claude-\(.session[:8])")' ;;
    --install-hooks) install_hooks ;;
    *) status ;;
esac
