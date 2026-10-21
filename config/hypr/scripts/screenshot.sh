#!/usr/bin/env bash
# Screenshot (grim + slurp). Print (hyprland/binds.lua, region), CTRL+Print (via screenshot-key.sh) and the
# Quickshell launcher screenshot section call it.
#
#   screenshot.sh region   drag a rectangle with slurp
#   screenshot.sh window   click a window (boxes of the windows on the visible workspaces)
#   screenshot.sh output   whole monitor: the only one, else click the monitor with slurp
#
# Saves ~/Pictures/Screenshots/shot-YYYY-MM-DD_HH-MM-SS.png (XDG PICTURES dir), copies it to the
# clipboard (wl-copy) and sends a notification (click = open the folder with the file selected).
# Test overrides: SHOT_GEOM="x,y WxH" (skip slurp), SHOT_OUTPUT=<monitor>, SHOT_DIR (save dir),
# SHOT_NOTIFY=0 (print to stderr instead of notifying), SHOT_CLIP=0 (no wl-copy).
set -uo pipefail

pics=$(xdg-user-dir PICTURES 2>/dev/null)
[ -n "$pics" ] && [ "$pics" != "$HOME" ] || pics=$HOME/Pictures
OUT_DIR=${SHOT_DIR:-$pics/Screenshots}
APP="Screenshot"

notify() { # notify <urgency> <summary> <body>
	if [ "${SHOT_NOTIFY:-1}" = 0 ] || ! command -v notify-send >/dev/null; then
		printf '%s: %s\n' "$2" "$3" >&2
	else
		notify-send -a "$APP" -i camera-photo -u "$1" "$2" "$3"
	fi
}
need() { command -v "$1" >/dev/null || { notify critical "Can't take a screenshot" "$2 is missing"; exit 1; }; }

cmd=${1:-}
case $cmd in
region | window | output) ;;
*) echo "usage: ${0##*/} region|window|output" >&2; exit 2 ;;
esac

# one selection at a time: a second press while slurp is up does nothing (Escape cancels slurp)
RUN_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
exec 9>"$RUN_DIR/screenshot.lock"
flock -n 9 || exit 0

need grim grim
need hyprctl hyprland
need jq jq

geom="" output=""
case $cmd in
region)
	if [ -n "${SHOT_GEOM:-}" ]; then geom=$SHOT_GEOM; else
		need slurp slurp
		geom=$(slurp -d) || exit 0
	fi
	;;
window)
	if [ -n "${SHOT_GEOM:-}" ]; then geom=$SHOT_GEOM; else
		need slurp slurp
		# same boxes as screenrec.sh: windows on every monitor's visible workspace (+ pinned ones)
		geom=$(hyprctl clients -j | jq -r --argjson ws "$(hyprctl monitors -j | jq '[.[] | .activeWorkspace.id, .specialWorkspace.id] | map(select(. != 0))')" \
			'.[] | select(.mapped and (.hidden | not) and (.pinned or (.workspace.id as $w | $ws | index($w))))
			 | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | awk '!seen[$0]++' | slurp -r) || exit 0
	fi
	;;
output)
	output=${SHOT_OUTPUT:-}
	if [ -z "$output" ]; then
		count=$(hyprctl monitors -j | jq 'length')
		if [ "${count:-0}" -gt 1 ]; then
			need slurp slurp
			output=$(slurp -o -r -f '%o') || exit 0   # click a monitor
		else
			output=$(hyprctl monitors -j | jq -r '.[0].name')
		fi
	fi
	[ -n "$output" ] || { notify critical "Can't take a screenshot" "No monitor found"; exit 1; }
	;;
esac
[ "$cmd" = output ] || [ -n "$geom" ] || exit 0

mkdir -p "$OUT_DIR"
file=$OUT_DIR/shot-$(date +%F_%H-%M-%S).png
if [ -n "$output" ]; then grim -o "$output" "$file"; else grim -g "$geom" "$file"; fi || { notify critical "Screenshot failed" "grim returned an error"; exit 1; }
[ -s "$file" ] || { rm -f "$file"; notify critical "Screenshot failed" "empty file"; exit 1; }

if [ "${SHOT_CLIP:-1}" != 0 ] && command -v wl-copy >/dev/null; then
	wl-copy --type image/png <"$file"
fi

if [ "${SHOT_NOTIFY:-1}" = 0 ] || ! command -v notify-send >/dev/null; then
	echo "saved $file" >&2
else
	# detached: waits for a click on the toast; default action opens the folder with the file selected
	(
		act=$(notify-send -w -a "$APP" -i "$file" -u low -A default="Open folder" "Screenshot saved" "Copied to the clipboard · ${file##*/}") &&
			[ "$act" = default ] && nautilus --new-window --select "$file" >/dev/null 2>&1
	) >/dev/null 2>&1 &
	disown
fi
