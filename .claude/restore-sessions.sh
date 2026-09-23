#!/usr/bin/env bash
# Bring back the Claude Code sessions that were open when this machine last went
# down. Pairs with session-registry.sh, wired up as SessionStart/SessionEnd
# hooks in settings.json.
#
#   claude-restore               pick with fzf (all preselected), a WezTerm tab each
#   claude-restore --all         skip the picker, resume everything
#   claude-restore --list        print what is resumable and exit
#   claude-restore --all-closed  widen the list to every session closed before the reboot
#   claude-restore --seed        record the sessions that are open right now
#
# What gets offered: the sessions that went down with the machine. Claude Code
# fires SessionEnd on SIGTERM and SIGHUP as well as on a real exit, so ending
# cleanly proves nothing; the tell is when it ended. Quitting WezTerm before a
# restart ends them all in the last few minutes before the reboot. Sessions
# closed since booting, or closed well before that, are treated as deliberate.
#
# A session stays resumable for as long as its transcript exists under
# ~/.claude/projects. Claude Code's retention sweep (cleanupPeriodDays, 30 by
# default) is what eventually deletes it; entries whose transcript is already
# gone are pruned from the registry here.

set -uo pipefail

REGISTRY="${CLAUDE_SESSION_REGISTRY:-$HOME/.claude/live-sessions}"
PROJECTS="$HOME/.claude/projects"
RUNNING="$HOME/.claude/sessions"
HISTORY="$HOME/.claude/history.jsonl"

# How long before the reboot a session can have ended and still count as part
# of that shutdown.
CLUSTER_WINDOW="${CLAUDE_RESTORE_CLUSTER:-600}"

transcript_for() {
    local id=$1 f
    for f in "$PROJECTS"/*/"$id".jsonl; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# Both kinds of title record, in one pass over the transcript: these files run
# to several MB and the picker re-reads them on every preview.
title_records() {
    rg -N -e '"type":"custom-title"' -e '"type":"ai-title"' "$1" 2>/dev/null
}

# A name you set yourself, with -n or /rename. Empty if the session was only
# ever auto-titled.
user_title_for() {
    title_records "$1" \
        | jq -rs 'map(select(.type == "custom-title")) | last | .customTitle // empty' 2>/dev/null
}

# The current display name: your own name wins, then the auto-generated title,
# then whatever the session was called at startup.
name_for() {
    local transcript=$1 fallback=$2 name
    name=$(title_records "$transcript" | jq -rs '
        (map(select(.type == "custom-title")) | last | .customTitle)
        // (map(select(.type == "ai-title")) | last | .aiTitle)
        // empty' 2>/dev/null)
    printf '%s' "${name:-$fallback}"
}

# Sessions with a claude process still behind them, as "id<TAB>cwd<TAB>name".
# Claude Code keeps this directory itself, one file per process, and never
# sweeps it — entries outlive the processes they describe, so check that the
# pid is both alive and still a claude before believing it.
running_entries() {
    local f pid sid cwd name
    for f in "$RUNNING"/*.json; do
        [ -f "$f" ] || continue
        pid= sid= cwd= name=
        { read -r pid; read -r sid; read -r cwd; read -r name; } < <(
            jq -r 'select((.kind // "interactive") == "interactive")
                   | [.pid, .sessionId, .cwd, .name] | map(. // "") | .[]' "$f" 2>/dev/null)
        [ -n "$pid" ] && [ -n "$sid" ] || continue
        kill -0 "$pid" 2>/dev/null || continue
        case "$(ps -o comm= -p "$pid" 2>/dev/null)" in
            *claude*) printf '%s\t%s\t%s\n' "$sid" "$cwd" "$name" ;;
        esac
    done
}

running_ids() { running_entries | cut -f1; }

# Import the sessions that are already open into the registry. Needed once
# after installing the hooks, since sessions started before them were never
# recorded; harmless to re-run.
seed() {
    local id cwd name count=0
    mkdir -p "$REGISTRY" 2>/dev/null || return 1
    while IFS='	' read -r id cwd name; do
        [ -n "$id" ] || continue
        [ -f "$REGISTRY/$id.json" ] && continue
        jq -nc --arg id "$id" --arg cwd "$cwd" --arg title "$name" \
            '{session_id: $id, cwd: $cwd, title: $title}' \
            > "$REGISTRY/$id.json" && count=$(( count + 1 ))
    done < <(running_entries)
    printf 'seeded %d running session(s) into the registry\n' "$count"
}

human_age() {
    local secs=$(( $(date +%s) - $1 ))
    if [ "$secs" -lt 3600 ]; then printf '%dm ago' $(( secs / 60 ))
    elif [ "$secs" -lt 86400 ]; then printf '%dh ago' $(( secs / 3600 ))
    else printf '%dd ago' $(( secs / 86400 )); fi
}

short_path() {
    local tilde='~'
    printf '%s' "${1/#$HOME/$tilde}"
}

# fzf preview: what this session was actually doing.
preview() {
    local id=$1 transcript cwd branch
    transcript=$(transcript_for "$id") || { echo "transcript is gone"; return 0; }
    cwd=$(jq -r '.cwd // empty' "$REGISTRY/$id.json" 2>/dev/null)
    printf '\033[1m%s\033[0m\n' "$(name_for "$transcript" "${id:0:8}")"
    printf 'dir      %s\n' "$(short_path "$cwd")"
    if branch=$(git -C "$cwd" branch --show-current 2>/dev/null) && [ -n "$branch" ]; then
        printf 'branch   %s\n' "$branch"
    fi
    printf 'active   %s\n' "$(human_age "$(stat -f %m "$transcript")")"
    printf 'id       %s\n\n' "$id"
    printf '\033[1mrecent prompts\033[0m\n'
    rg -N --fixed-strings "\"sessionId\":\"$id\"" "$HISTORY" 2>/dev/null \
        | tail -5 | jq -r '(.display // empty) | gsub("\\s+"; " ")' 2>/dev/null \
        | cut -c1-300 | sed 's/^/  · /'
}

# Open one WezTerm tab per session, all in a fresh window, with claude itself as
# the pane's program. Handing wezterm the command beats spawning a bare shell
# and typing into it, which needs a guessed delay to be sure the shell is ready;
# the trailing exec leaves a normal prompt behind when claude exits.
resume_sessions() {
    local ids=("$@") id cwd transcript title cmd pane window="" count=0 spawn=()

    if ! wezterm cli list >/dev/null 2>&1; then
        echo "no WezTerm GUI to spawn into — run this from a WezTerm window" >&2
        printf 'or resume by hand:\n' >&2
        for id in "${ids[@]}"; do printf '  claude --resume %s\n' "$id" >&2; done
        return 1
    fi

    for id in "${ids[@]}"; do
        cwd=$(jq -r '.cwd // empty' "$REGISTRY/$id.json" 2>/dev/null)
        [ -d "$cwd" ] || cwd=$HOME

        # Resuming does not bring back the session name, so re-apply the one
        # you set. Auto-generated titles are left alone: they are meant to keep
        # tracking the conversation, and -n would freeze them.
        cmd="claude --resume $id"
        if transcript=$(transcript_for "$id"); then
            title=$(user_title_for "$transcript")
            [ -n "$title" ] && printf -v cmd '%s -n %q' "$cmd" "$title"
        fi

        # An interactive shell so the aliases and PATH from your rc files apply,
        # the same way they did when this was typed into a live pane.
        spawn=(--cwd "$cwd" -- "$SHELL" -ic "$cmd; exec $SHELL")
        if [ -z "$window" ]; then
            pane=$(wezterm cli spawn --new-window "${spawn[@]}" 2>/dev/null) || continue
            window=$(wezterm cli list --format json 2>/dev/null \
                | jq -r --arg p "$pane" '.[] | select((.pane_id|tostring) == $p) | .window_id' | head -1)
        else
            wezterm cli spawn --window-id "$window" "${spawn[@]}" >/dev/null 2>&1 || continue
        fi
        count=$(( count + 1 ))
    done

    printf 'resumed %d session(s)\n' "$count"
}

# kern.boottime reads "{ sec = 1790000000, usec = 4912 } ..." — anchor on the
# brace so the usec field cannot be picked up instead.
boot_epoch() { sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ *sec *= *\([0-9]*\).*/\1/p'; }

main() {
    # fzf calls back into this script for each preview; keep that off the
    # regular flag path so it cannot be confused by argument order.
    if [ "${1:-}" = --preview ]; then preview "${2:-}"; return 0; fi

    local mode=pick wide=0 arg
    for arg in "$@"; do
        case "$arg" in
            --seed) seed; return 0 ;;
            --all) mode=all ;;
            --list) mode=list ;;
            --all-closed) wide=1 ;;
            *) echo "usage: ${0##*/} [--all|--list|--seed|--all-closed]" >&2; return 2 ;;
        esac
    done

    [ -d "$REGISTRY" ] || { echo "nothing recorded yet ($REGISTRY)"; return 0; }

    local live boot rows="" f id cwd title ended transcript name mtime
    local gone=0 skipped=0 deliberate=0
    local ended_files=()
    boot=$(boot_epoch)
    live=$(running_ids)

    for f in "$REGISTRY"/*.json; do
        [ -f "$f" ] || continue
        id= cwd= title= ended=
        { read -r id; read -r cwd; read -r title; read -r ended; } < <(
            jq -r '[.session_id, .cwd, .title, .ended_at] | map(. // "") | .[]' "$f" 2>/dev/null)
        [ -n "$id" ] || { rm -f "$f"; continue; }
        # Anything with a clean SessionEnd has had its turn in the picker and is
        # dropped once the resume goes through, whether or not it was chosen.
        [ -n "$ended" ] && ended_files+=("$f")

        # No transcript means the retention sweep already took it: not resumable.
        if ! transcript=$(transcript_for "$id"); then
            rm -f "$f"
            gone=$(( gone + 1 ))
            continue
        fi
        if printf '%s\n' "$live" | rg -qxF "$id" 2>/dev/null; then
            skipped=$(( skipped + 1 ))
            continue
        fi
        # Ended since this machine booted, so you closed it on purpose today.
        if [ -n "$ended" ] && [ -n "$boot" ] && [ "$ended" -ge "$boot" ]; then
            deliberate=$(( deliberate + 1 ))
            continue
        fi
        # Of the sessions that ended before the reboot, keep the ones that went
        # down with it. A session with no end recorded at all was killed
        # outright, so it always counts.
        if [ "$wide" -eq 0 ] && [ -n "$ended" ] && [ -n "$boot" ] \
            && [ $(( boot - ended )) -gt "$CLUSTER_WINDOW" ]; then
            deliberate=$(( deliberate + 1 ))
            continue
        fi

        mtime=$(stat -f %m "$transcript")
        name=$(name_for "$transcript" "${title:-${id:0:8}}")
        rows+="$id	$mtime	$name	$cwd
"
    done

    [ "$gone" -gt 0 ] && printf 'dropped %d session(s) whose transcript expired\n' "$gone" >&2
    [ "$skipped" -gt 0 ] && printf 'skipped %d already running\n' "$skipped" >&2
    [ "$deliberate" -gt 0 ] && printf 'ignored %d closed on purpose (--all-closed to see them)\n' "$deliberate" >&2

    if [ -z "$rows" ]; then
        echo "no sessions to restore"
        return 0
    fi

    # id <TAB> display line, most recently active first.
    local lines
    lines=$(printf '%s' "$rows" | sort -t'	' -k2,2nr | while IFS='	' read -r id mtime name cwd; do
        printf '%s\t%-30s  %-8s  %s\n' "$id" "$name" "$(human_age "$mtime")" "$(short_path "$cwd")"
    done)

    if [ "$mode" = list ]; then
        printf '%s\n' "$lines" | cut -f2-
        return 0
    fi

    local chosen
    if [ "$mode" = all ]; then
        chosen=$(printf '%s\n' "$lines" | cut -f1)
    else
        chosen=$(printf '%s\n' "$lines" | fzf \
            --multi --delimiter='\t' --with-nth=2 --ansi --reverse --height=80% \
            --bind 'start:select-all' \
            --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
            --header 'tab: toggle · ctrl-a: all · ctrl-d: none · enter: resume' \
            --preview "$0 --preview {1}" \
            --preview-window 'right,50%,wrap' \
            | cut -f1)
    fi

    [ -n "$chosen" ] || { echo "nothing selected"; return 0; }

    local selected=()
    while IFS= read -r id; do [ -n "$id" ] && selected+=("$id"); done <<< "$chosen"
    # Resumed sessions re-register themselves from SessionStart, and the
    # transcripts stay put either way ("claude --resume" with no id finds them).
    if resume_sessions "${selected[@]}" && [ "${#ended_files[@]}" -gt 0 ]; then
        rm -f "${ended_files[@]}"
    fi
}

main "$@"
