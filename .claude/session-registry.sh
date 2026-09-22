#!/usr/bin/env bash
# Records which Claude Code sessions are open, so restore-sessions.sh can bring
# them back after a reboot.
#
# SessionStart writes one file per session, SessionEnd deletes it. A session
# killed by a restart never fires SessionEnd, so whatever is left behind in the
# registry is exactly the set that died with the machine.

REGISTRY="${CLAUDE_SESSION_REGISTRY:-$HOME/.claude/live-sessions}"

# Track interactive sessions only. -p and SDK runs come through as sdk-cli and
# would leave entries behind whenever one is killed mid-run.
case "${CLAUDE_CODE_ENTRYPOINT:-cli}" in
    cli) ;;
    *) exit 0 ;;
esac

input=$(cat)
[ -n "$input" ] || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$id" ] || exit 0

case "$event" in
    SessionStart)
        mkdir -p "$REGISTRY" 2>/dev/null || exit 0
        # session_title is the name at startup only; /rename after this point
        # lands in the transcript, which is where restore-sessions.sh reads it.
        printf '%s' "$input" \
            | jq -c '{session_id, cwd, title: (.session_title // ""), recorded_at: (now | floor)}' \
                > "$REGISTRY/.$id.tmp" 2>/dev/null \
            && mv -f "$REGISTRY/.$id.tmp" "$REGISTRY/$id.json" 2>/dev/null
        ;;
    SessionEnd)
        # Not a delete: a restart SIGTERMs every session, and Claude Code fires
        # SessionEnd for that too, so deleting here would empty the registry at
        # exactly the wrong moment. Record how and when it ended instead and let
        # restore-sessions.sh decide.
        [ -f "$REGISTRY/$id.json" ] || exit 0
        reason=$(printf '%s' "$input" | jq -r '.reason // "unknown"' 2>/dev/null)
        jq -c --arg reason "$reason" '. + {ended_at: (now | floor), end_reason: $reason}' \
            "$REGISTRY/$id.json" > "$REGISTRY/.$id.tmp" 2>/dev/null \
            && mv -f "$REGISTRY/.$id.tmp" "$REGISTRY/$id.json" 2>/dev/null
        ;;
esac

exit 0
