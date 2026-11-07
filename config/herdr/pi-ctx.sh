#!/bin/bash
# Pi context-usage reporter: publish "π NN%" to the herdr sidebar row of this pane as the $ctx token.
# Usage: pi-ctx.sh <percent>   (called by a Pi extension on every turn)
# In the desktop app (HC_TERMINAL_ID) it also sets the terminal label ctx=NN for the agent card.
# Silent no-op outside herdr; herdr is called in the background and only when the value changed.
[ -n "${HERDR_PANE_ID:-}${HC_TERMINAL_ID:-}" ] || exit 0
[ -n "${1:-}" ] || exit 0
num=$(printf '%.0f' "$1" 2>/dev/null) || exit 0
val="π $num%"

state=${XDG_RUNTIME_DIR:-/tmp}/herdr-pi-ctx
mkdir -p "$state" 2>/dev/null
# Skip when unchanged and refreshed within the last 5 minutes.
fresh() { [ "$(cat "$1" 2>/dev/null)" = "$2" ] && [ -n "$(find "$1" -mmin -5 2>/dev/null)" ]; }

if [ -n "${HERDR_PANE_ID:-}" ]; then
  f=$state/${HERDR_PANE_ID//[^A-Za-z0-9_.-]/_}
  if ! fresh "$f" "$val"; then
    printf '%s' "$val" >"$f"
    herd=${HERDR_BIN_PATH:-herdr}
    "$herd" pane report-metadata "$HERDR_PANE_ID" --source pi-ctx --token "ctx=$val" >/dev/null 2>&1 &
  fi
fi

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  f=$state/hc-${HC_TERMINAL_ID//[^A-Za-z0-9_.-]/_}
  if ! fresh "$f" "$num"; then
    printf '%s' "$num" >"$f"
    # A failed label drops the cache so the next update retries.
    { "${HC_BIN:-$HOME/.local/bin/hc}" label "$HC_TERMINAL_ID" "ctx=$num" || rm -f "$f"; } >/dev/null 2>&1 &
  fi
fi
exit 0
