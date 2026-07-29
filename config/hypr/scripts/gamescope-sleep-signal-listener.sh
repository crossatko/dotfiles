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
# Written by gamescope-wrapper/dbus-send when it has already put the TV to sleep
# ahead of the suspend request. Its presence (and freshness) is what stops the
# handler below from redundantly retrying that over a network that is, by then,
# already gone.
PREEMPT_STAMP="/run/user/$(id -u)/tv-slept-preemptively"
DEBUG_LOG="/home/kreejzak/.local/state/androidtv-remote/poll-debug.log"
mkdir -p "$(dirname "$DEBUG_LOG")"
echo "$(date +%s.%N) SIGNAL-LISTENER started (pid $$)" >>"$DEBUG_LOG"

# --- suspend inhibitor ------------------------------------------------------
# Subscribing to PrepareForSleep is not enough on its own: the signal is an
# announcement, not a request for permission. Measured here, "PM: suspend
# entry (deep)" lands *3ms* after logind broadcasts it -- so the first version
# of this got frozen mid-adb and tv-sleep.sh only returned 24s later, after
# the resume, having left the TV awake on a "no input" screen the whole time.
#
# A mode=delay inhibitor is what actually buys a window: logind waits for every
# delay lock to be released before entering sleep, up to InhibitDelayMaxSec
# (5s by default -- see system/etc/systemd/logind.conf.d/ for raising it, since
# tv-sleep.sh's two `timeout 3 adb` calls can exceed that in the worst case).
# Exceeding the cap is not a regression: logind just proceeds, i.e. exactly
# today's behaviour.
#
# The lock lives as long as the systemd-inhibit child does, so taking it is
# "spawn and keep the pid" and releasing it is "kill the pid".
INHIBIT_WHO="gamescope-tv-automation"
LOCK_PID=

take_lock() {
	systemd-inhibit --what=sleep --mode=delay \
		--who="$INHIBIT_WHO" \
		--why="Put the TV into standby and record the wake-source baseline" \
		sleep infinity >/dev/null 2>&1 &
	LOCK_PID=$!
}

release_lock() {
	[ -n "$LOCK_PID" ] || return 0
	kill "$LOCK_PID" 2>/dev/null
	LOCK_PID=
}

# No stale-lock cleanup needed on startup: the inhibit child lives in this
# unit's cgroup, and systemd's default KillMode=control-group reaps it whenever
# the unit is stopped or restarted -- even on SIGKILL, where the trap below
# never runs. (An earlier version opened with a `pkill -f
# "systemd-inhibit.*$INHIBIT_WHO"` for this; don't reintroduce it. `pkill -f`
# matches any process whose *command line* merely contains the pattern, so it
# promptly killed the interactive shell that was grepping for that same string
# while testing this.)
trap release_lock EXIT
take_lock

# True when gamescope-wrapper/dbus-send has just handled the TV, within the last
# minute. Explicit mtime arithmetic rather than `find -newermt '-60 seconds'`:
# find does not parse that relative form the way it reads, and the version that
# used it silently never matched, so the "skip" branch was dead code.
preempt_stamp_fresh() {
	local mtime
	mtime=$(stat -c %Y "$PREEMPT_STAMP" 2>/dev/null) || return 1
	[ "$(($(date +%s) - mtime))" -lt 60 ]
}

gdbus monitor --system --dest org.freedesktop.login1 2>>"$DEBUG_LOG" | while IFS= read -r line; do
	case "$line" in
	*PrepareForSleep*)
		echo "$(date +%s.%N) SIGNAL-LISTENER saw: $line" >>"$DEBUG_LOG"
		;;
	esac
	case "$line" in
	*"PrepareForSleep (true,)"*)
		# Unguarded and first: this snapshots the per-device wakeup counters
		# that wake-source-switch.sh diffs after the resume to work out which
		# device woke us. Needed in *either* session (a controller wake from
		# Hyprland is just as meaningful as a keyboard wake from gamescope),
		# and it must happen before the machine actually goes down. Pure sysfs
		# reads, low single-digit ms, so it costs nothing in the tight and
		# uninhibited window this script has.
		/home/kreejzak/.config/hypr/scripts/wake-source-switch.sh snapshot

		if [ ! -e "$MARKER" ]; then
			echo "$(date +%s.%N) SIGNAL-LISTENER no marker, skipping sleep" >>"$DEBUG_LOG"
		elif preempt_stamp_fresh; then
			# gamescope-wrapper/dbus-send already did this, back when the
			# suspend was merely being *requested* and the network was still
			# up. Repeating it here would spend ~3s failing (NetworkManager has
			# torn the network down by now -- see that wrapper's header) while
			# holding the suspend open for nothing.
			echo "$(date +%s.%N) SIGNAL-LISTENER TV already slept pre-emptively by dbus-send wrapper, skipping" >>"$DEBUG_LOG"
			rm -f "$PREEMPT_STAMP"
		else
			# Fallback path, and still worth keeping: it covers any suspend
			# inside a gamescope session that does NOT come through Steam's
			# dbus-send (a lid event, `systemctl suspend` from a TTY, anything
			# else). It will usually fail for the network reason above, but
			# failing is strictly better than not trying.
			echo "$(date +%s.%N) SIGNAL-LISTENER marker present, no pre-empt stamp, firing tv-sleep.sh" >>"$DEBUG_LOG"
			/home/kreejzak/.config/hypr/scripts/gamescope-webhook-notify.sh false &
			WEBHOOK_PID=$!
			/home/kreejzak/.config/hypr/scripts/tv-sleep.sh
			# Captured immediately: `echo "... $?"` would report the exit status
			# of the $(date) command substitution in the same line, not
			# tv-sleep.sh's -- which is why this used to log "exited 0" for a
			# call that had in fact timed out.
			TV_SLEEP_RC=$?
			echo "$(date +%s.%N) SIGNAL-LISTENER tv-sleep.sh exited $TV_SLEEP_RC" >>"$DEBUG_LOG"
			# Specifically the webhook, NOT a bare `wait`: the inhibitor is held
			# by a `systemd-inhibit ... sleep infinity` background job of this
			# same shell, so a bare `wait` would block on it forever and the
			# release below would never run.
			wait "$WEBHOOK_PID" 2>/dev/null
		fi
		# Only now is it safe to let the machine actually go down. Releasing
		# unconditionally (and last) matters: holding the lock past this point
		# would just stall the suspend until logind's cap expires, and in the
		# no-marker case there is nothing to wait for at all.
		release_lock
		echo "$(date +%s.%N) SIGNAL-LISTENER inhibitor released, suspend may proceed" >>"$DEBUG_LOG"
		;;
	*"PrepareForSleep (false,)"*)
		# Re-arm for the *next* suspend straight away, before any of the
		# potentially slow work below -- the lock has no cost while awake, and
		# taking it late would leave a window where a quick re-suspend gets no
		# delay at all.
		take_lock

		# Which device woke us decides which session we should be in -- and
		# that answer also determines whether the TV work below is worth doing
		# at all, so it has to come first. Side-effect free and sub-100ms
		# (sysfs reads plus a stat of the gamescope marker), so putting it
		# ahead of the TV calls costs nothing.
		DECISION="$(/home/kreejzak/.config/hypr/scripts/wake-source-switch.sh decide)"
		echo "$(date +%s.%N) SIGNAL-LISTENER wake decision: $DECISION" >>"$DEBUG_LOG"

		case "$DECISION" in
		switch:*)
			# Deliberately skips the TV block below: both switch directions
			# already drive the TV through the session units themselves
			# (gamescope-session-wake.service's ExecStart wakes it on the way
			# in, its ExecStop sleeps it on the way out). Running both would
			# mean waking the TV a moment before tv-sleep.sh puts it straight
			# back into standby.
			/home/kreejzak/.config/hypr/scripts/wake-source-switch.sh apply "${DECISION#switch:}"
			;;
		*)
			if [ -e "$MARKER" ]; then
				echo "$(date +%s.%N) SIGNAL-LISTENER marker present, firing wake+input" >>"$DEBUG_LOG"
				# First, and backgrounded: the three TV calls below are
				# synchronous and tv-wake-and-resync.sh's own retry loop can
				# take ~130s worst case, so anything sequenced after them may
				# as well not fire at all. Nothing here depends on the TV
				# actually being awake -- gamescope is already displaying again
				# by this point, which is what active:true is reporting.
				/home/kreejzak/.config/hypr/scripts/gamescope-webhook-notify.sh true &
				/home/kreejzak/.config/hypr/scripts/tv-wake-and-resync.sh
				/home/kreejzak/.config/hypr/scripts/tv-input.sh wakeup
				/home/kreejzak/.config/hypr/scripts/tv-input.sh hdmi2
				echo "$(date +%s.%N) SIGNAL-LISTENER wake+input done" >>"$DEBUG_LOG"
				wait
			else
				echo "$(date +%s.%N) SIGNAL-LISTENER no marker, skipping wake" >>"$DEBUG_LOG"
			fi
			;;
		esac
		;;
	esac
done
echo "$(date +%s.%N) SIGNAL-LISTENER while-loop exited (gdbus monitor died?)" >>"$DEBUG_LOG"
