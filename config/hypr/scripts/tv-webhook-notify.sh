#!/bin/bash
# Posts the TV's Hyprland-active/inactive state to a Home Assistant webhook.
# Called from tv.lua's handle_tv_connected()/handle_tv_disconnected() via
# hl.exec_cmd, which already backgrounds it (`&`) -- never invoke curl
# synchronously from Hyprland's own Lua execution (a blocking network call
# there has frozen the compositor before, see steam-tv-dim.lua's
# is_tv_reachable comment for the same lesson learned with adb).
#
# URL lives in .secrets, not hardcoded here: this dotfiles repo is public.
SECRETS="$HOME/.config/hypr/.secrets"
[ -f "$SECRETS" ] && source "$SECRETS"

if [ -z "$HA_TV_WEBHOOK_URL" ]; then
	exit 0
fi

if [ "$1" = "true" ]; then
	payload='{"connected": true}'
else
	payload='{"connected": false}'
fi

timeout 5 curl -sS -X POST "$HA_TV_WEBHOOK_URL" -H "Content-Type: application/json" -d "$payload" -o /dev/null
