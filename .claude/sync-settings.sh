#!/usr/bin/env bash
# Builds ~/.claude/settings.json from this repo's settings.json plus the untracked
# ~/.claude/work.settings.json. Claude Code has no user-level overlay of its own.
# Edits Claude Code makes to the live file are overwritten on the next run.
set -euo pipefail

BASE="$(dirname "$(realpath "$0")")/settings.json"
OVERLAY="$HOME/.claude/work.settings.json"
TARGET="$HOME/.claude/settings.json"

if [ -f "$OVERLAY" ]; then
    merged=$(jq -s '
        def merge($a; $b):
            if ($a | type) == "object" and ($b | type) == "object" then
                reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
            elif ($a | type) == "array" and ($b | type) == "array" then
                $a + $b
            else
                $b
            end;
        merge(.[0]; .[1])
    ' "$BASE" "$OVERLAY")
else
    merged=$(jq . "$BASE")
fi

# Keep the previous file around, and remove it before writing so an old stow
# symlink is replaced instead of written through into the repo.
if [ -e "$TARGET" ]; then
    cp -L "$TARGET" "$TARGET.pre-sync"
    rm -f "$TARGET"
fi
printf '%s\n' "$merged" > "$TARGET"

if [ -f "$OVERLAY" ]; then
    echo "Wrote $TARGET (base + $(basename "$OVERLAY"))"
else
    echo "Wrote $TARGET (base only)"
fi
