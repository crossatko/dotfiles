#!/bin/bash
# Split the focused pane along its longer side: side by side when it is wide, stacked when it is tall.
# A terminal cell is about twice as tall as it is wide, so compare width against twice the height.
herd=${HERDR_BIN_PATH:-herdr}
pane=${HERDR_ACTIVE_PANE_ID:?}

read -r w h < <("$herd" pane edges --pane "$pane" |
  jq -r --arg p "$pane" '.result.edges.layout.panes[] | select(.pane_id == $p) | "\(.rect.width) \(.rect.height)"')
[ -n "$h" ] || exit 1

if [ "$w" -ge $((h * 2)) ]; then dir=right; else dir=down; fi
exec "$herd" pane split --pane "$pane" --direction "$dir" --focus
