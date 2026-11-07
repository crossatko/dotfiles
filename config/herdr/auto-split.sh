#!/bin/bash
# Split the focused pane along its longer side: side by side when it is wide, stacked when it is tall.
# A terminal cell is about twice as tall as it is wide, so compare width against twice the height.
# Arguments, if any, are a command to run in the new pane; the pane closes when that command exits.
herd=${HERDR_BIN_PATH:-herdr}
pane=${HERDR_ACTIVE_PANE_ID:?}

read -r w h < <("$herd" pane edges --pane "$pane" |
  jq -r --arg p "$pane" '.result.edges.layout.panes[] | select(.pane_id == $p) | "\(.rect.width) \(.rect.height)"')
[ -n "$h" ] || exit 1

if [ "$w" -ge $((h * 2)) ]; then dir=right; else dir=down; fi
new=$("$herd" pane split --pane "$pane" --direction "$dir" --cwd "$PWD" --focus | jq -r '.result.pane.pane_id')
[ $# -eq 0 ] || exec "$herd" pane run "$new" "exec $*"
