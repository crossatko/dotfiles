#!/bin/bash
# Replaces the /etc/systemd/system-sleep/ hook approach -- confirmed dead
# on this system: neither our own hook nor the pre-existing nvidia one
# (/usr/lib/systemd/system-sleep/nvidia) ever fired during multiple real
# suspend/resume cycles, despite correct permissions and a working script.
# Subscribes directly to logind's own PrepareForSleep signal instead --
# fires unconditionally on every suspend/resume regardless of what
# triggered it (our own keybind, Steam's own dbus-send from inside
# gamescope-session, a lid close, anything), so it doesn't depend on
# whatever is broken in the hook-script scanning path.
#
# gdbus monitor's plain signal subscription (not eavesdrop/monitor mode,
# which needs root) is enough to receive this broadcast signal as a
# regular user -- confirmed live.
#
# Runs as a --user service tied to default.target (not
# graphical-session.target), so it keeps running continuously across a
# Hyprland<->gamescope-session switch -- the user's systemd --user
# instance itself persists across that switch even though the compositor
# changes, and suspend needs covering during gamescope-session specifically
# (when Hyprland, and its own on-wake.sh/hyprctl eval path, isn't running
# at all).

MARKER="/run/user/$(id -u)/gamescope-environment"
DEBUG_LOG="/home/kreejzak/.local/state/androidtv-remote/poll-debug.log"
mkdir -p "$(dirname "$DEBUG_LOG")"
echo "$(date +%s.%N) SIGNAL-LISTENER started (pid $$)" >>"$DEBUG_LOG"

gdbus monitor --system --dest org.freedesktop.login1 2>>"$DEBUG_LOG" | while IFS= read -r line; do
	case "$line" in
	*PrepareForSleep*)
		echo "$(date +%s.%N) SIGNAL-LISTENER saw: $line" >>"$DEBUG_LOG"
		;;
	esac
	case "$line" in
	*"PrepareForSleep (true,)"*)
		if [ -e "$MARKER" ]; then
			echo "$(date +%s.%N) SIGNAL-LISTENER marker present, firing tv-sleep.sh" >>"$DEBUG_LOG"
			/home/kreejzak/.config/hypr/scripts/tv-sleep.sh
			echo "$(date +%s.%N) SIGNAL-LISTENER tv-sleep.sh exited $?" >>"$DEBUG_LOG"
		else
			echo "$(date +%s.%N) SIGNAL-LISTENER no marker, skipping sleep" >>"$DEBUG_LOG"
		fi
		;;
	*"PrepareForSleep (false,)"*)
		if [ -e "$MARKER" ]; then
			echo "$(date +%s.%N) SIGNAL-LISTENER marker present, firing wake+input" >>"$DEBUG_LOG"
			/home/kreejzak/.config/hypr/scripts/tv-wake-and-resync.sh
			/home/kreejzak/.config/hypr/scripts/tv-input.sh wakeup
			/home/kreejzak/.config/hypr/scripts/tv-input.sh hdmi2
			echo "$(date +%s.%N) SIGNAL-LISTENER wake+input done" >>"$DEBUG_LOG"
		else
			echo "$(date +%s.%N) SIGNAL-LISTENER no marker, skipping wake" >>"$DEBUG_LOG"
		fi
		;;
	esac
done
echo "$(date +%s.%N) SIGNAL-LISTENER while-loop exited (gdbus monitor died?)" >>"$DEBUG_LOG"
