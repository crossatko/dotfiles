#!/bin/bash
# Claude Code statusLine command: publish the context-window usage to the herdr sidebar row of this pane
# as the $ctx token. Prints nothing, so the status line stays empty.
# Silent no-op outside herdr; herdr is called in the background and only when the value changed.
[ -n "${HERDR_PANE_ID:-}" ] || { cat >/dev/null; exit 0; }
pct=$(jq -r '.context_window.used_percentage // empty' 2>/dev/null) || exit 0
[ -n "$pct" ] || exit 0
val="$(printf '%.0f' "$pct")%"

state=${XDG_RUNTIME_DIR:-/tmp}/herdr-claude-ctx
mkdir -p "$state" 2>/dev/null
f=$state/${HERDR_PANE_ID//[^A-Za-z0-9_.-]/_}
# Skip when unchanged and refreshed within the last 5 minutes.
if [ "$(cat "$f" 2>/dev/null)" = "$val" ] && [ -n "$(find "$f" -mmin -5 2>/dev/null)" ]; then exit 0; fi
printf '%s' "$val" >"$f"

herd=${HERDR_BIN_PATH:-herdr}
"$herd" pane report-metadata "$HERDR_PANE_ID" --source claude-ctx --token "ctx=$val" >/dev/null 2>&1 &
exit 0
