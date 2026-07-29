#!/bin/bash
# Posts gamescope-session's state to a Home Assistant webhook. "active" means
# "gamescope is on the TV right now", which is deliberately narrower than "a
# gamescope-session exists" -- a suspended session counts as inactive, exactly
# like the TV it drives is in standby.
#
# Called from FOUR places, which together are all the transitions there are:
#
#   gamescope-webhook-notify.service   ExecStart -> true    session start
#                                      ExecStop  -> false   session end
#   gamescope-sleep-signal-listener.sh (true,)   -> false   suspend
#                                      (false,)  -> true    resume
#
# The unit only covers start/end: suspend/resume never stops graphical-
# session.target, so a RemainAfterExit=yes oneshot sees nothing at all for it.
# The listener covers those two by watching logind's PrepareForSleep directly,
# guarded by the same %t/gamescope-environment marker so it stays silent when
# the suspend happened under Hyprland instead.
#
# Kept as its own script rather than folded into gamescope-session-wake.sh /
# tv-sleep.sh so this concern (session-state notification) stays independent of
# TV power state -- see tv-webhook-notify.sh for the analogous TV-connected/
# disconnected notification, same pattern.
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
