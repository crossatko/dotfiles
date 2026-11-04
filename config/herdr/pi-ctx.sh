#!/bin/bash
# Pi context-usage reporter: publish "Pi NN%" to the herdr sidebar row of this pane as the $ctx token.
# Usage: pi-ctx.sh <percent>   (called by a Pi extension on every turn)
# Silent no-op outside herdr; herdr is called in the background and only when the value changed.
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
[ -n "${1:-}" ] || exit 0
val="Pi $(printf '%.0f' "$1" 2>/dev/null)%" || exit 0

state=${XDG_RUNTIME_DIR:-/tmp}/herdr-pi-ctx
mkdir -p "$state" 2>/dev/null
f=$state/${HERDR_PANE_ID//[^A-Za-z0-9_.-]/_}
# Skip when unchanged and refreshed within the last 5 minutes.
if [ "$(cat "$f" 2>/dev/null)" = "$val" ] && [ -n "$(find "$f" -mmin -5 2>/dev/null)" ]; then exit 0; fi
printf '%s' "$val" >"$f"

herd=${HERDR_BIN_PATH:-herdr}
"$herd" pane report-metadata "$HERDR_PANE_ID" --source pi-ctx --token "ctx=$val" >/dev/null 2>&1 &
exit 0
