#!/bin/bash
# Posts gamescope-session's start/end state to a Home Assistant webhook.
# Wired as a second ExecStart=/ExecStop= line on gamescope-session-wake.
# service, alongside its existing TV wake/sleep commands -- kept as its
# own script rather than folded into gamescope-session-wake.sh/tv-sleep.sh
# so this concern (session-state notification) stays independent of TV
# power state (see tv-webhook-notify.sh for the analogous TV-connected/
# disconnected notification, same pattern).
#
# URL lives in .secrets, not hardcoded here: this dotfiles repo is public.
SECRETS="$HOME/.config/hypr/.secrets"
[ -f "$SECRETS" ] && source "$SECRETS"

if [ -z "$HA_GAMESCOPE_WEBHOOK_URL" ]; then
	exit 0
fi

if [ "$1" = "true" ]; then
	payload='{"active": true}'
else
	payload='{"active": false}'
fi

timeout 5 curl -sS -X POST "$HA_GAMESCOPE_WEBHOOK_URL" -H "Content-Type: application/json" -d "$payload" -o /dev/null
