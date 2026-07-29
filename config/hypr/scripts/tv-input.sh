#!/bin/bash
# Switches the living room TV (TCL 75C6K) input via adb. Requires Developer
# options + Network debugging enabled on the TV, and this host already
# authorized (adb keys persist in ~/.android once accepted on-screen once).
#
# The TV drops its network interface entirely in standby, so this only works
# while the TV is already on -- there is no way to wake it from here.

TV=192.168.0.128:5555
HDMI2_INPUT_ID='com.tcl.tvinput/.TvPassThroughService/HW16'
LOCK_DIR="$HOME/.local/state/androidtv-remote"
LOCK="$LOCK_DIR/tv-input.lock"

action="$1"

# Multiple independent triggers (Big Picture's own window.open event and the
# reachability poller's transition detection) can legitimately fire around
# the same moment -- without this, two near-simultaneous invocations send
# two concurrent adb commands (adb shares one server process across every
# call on this machine), and the TV's input framework has been observed
# landing on neither input as a result, stuck showing its home screen
# instead. Waiting for any in-flight invocation to finish, rather than
# racing it, is what actually fixes that -- not just deduplicating one
# specific pair of trigger paths.
mkdir -p "$LOCK_DIR"
DEBUG_LOG="$LOCK_DIR/poll-debug.log"
CALL_ID="$$-$action"
echo "$(date +%s.%N) TV-INPUT[$CALL_ID] waiting for lock" >>"$DEBUG_LOG"
exec 9>"$LOCK"
flock -w 200 9 || {
	echo "$(date +%s.%N) TV-INPUT[$CALL_ID] LOCK TIMEOUT" >>"$DEBUG_LOG"
	exit 1
}
echo "$(date +%s.%N) TV-INPUT[$CALL_ID] lock acquired, action=$action" >>"$DEBUG_LOG"

# `home` is a tidy-up for abandoning OUR input on the way into sleep -- it must
# never yank the TV away from something actually being watched. Firing it
# unconditionally meant that going to sleep while the TV was on YouTube (or any
# other app) interrupted it and dumped the TV on its dashboard. If the TV is not
# currently on our HDMI2 passthrough, or the current input cannot be read at
# all, leave it completely alone.
if [ "$action" = home ]; then
	timeout 2 adb connect "$TV" >/dev/null 2>&1
	current="$(timeout 5 adb -s "$TV" shell dumpsys tv_input 2>/dev/null | grep "inputId:" | tail -1 | awk '{print $2}')"
	if [ "$current" != "$HDMI2_INPUT_ID" ]; then
		echo "$(date +%s.%N) TV-INPUT[$CALL_ID] home: TV is on [$current], not our input -- leaving it alone" >>"$DEBUG_LOG"
		exit 0
	fi
fi

run() {
	case "$action" in
	hdmi2)
		timeout 3 adb -s "$TV" shell am start -a android.intent.action.VIEW \
			-d "content://android.media.tv/passthrough/${HDMI2_INPUT_ID//\//%2F}" >/dev/null 2>&1
		;;
	home)
		timeout 3 adb -s "$TV" shell input keyevent KEYCODE_HOME >/dev/null 2>&1
		;;
	wakeup)
		# Counterpart to tv-sleep.sh's KEYCODE_SLEEP. That only puts the
		# screen into standby -- the network/Android stack stays fully up,
		# so adb reachability and even an `am start` input-switch intent
		# both succeed immediately while the screen stays dark. Confirmed
		# live: switching input after a KEYCODE_SLEEP never brought the
		# picture back on its own across 3 real tests, all logged SUCCESS.
		# Only the direct wake keyevent actually un-blanks the screen.
		timeout 3 adb -s "$TV" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
		;;
	*)
		echo "usage: tv-input.sh hdmi2|home|wakeup" >&2
		exit 1
		;;
	esac
}

# Right after system wake, adb connectivity comes back before the TV's own
# tv_input framework is actually ready to act on an input-switch intent --
# confirmed via debug logging across multiple wakes: `adb connect` succeeds
# and stays reachable while `dumpsys tv_input` still reports no active
# session at all, and the `am start` intent fails fast (not a timeout) every
# one of those attempts. The readiness delay isn't a fixed value -- one wake
# cleared in ~12s, another took over two minutes (confirmed: a manual retry
# succeeded on the first try once dumpsys finally showed a session, ~125s
# after the TV became network-reachable) -- so the retry budget needs a wide
# margin rather than a number tuned to a single observation. 150 retries
# (~150s at the common fast-fail pace) covers that with room to spare.
# `timeout` still wraps each attempt as a hard backstop (adb's own
# connect-to-unreachable failure isn't instant, and without a bound, a call
# queued while the TV is off can run far longer than expected -- starving a
# legitimate subsequent call waiting on the lock above).
# `am start` exiting 0 is not proof the input actually changed -- that is
# precisely the failure mode documented above, where the intent reported success
# while `dumpsys tv_input` showed no active session at all and the TV sat on its
# home screen. So for hdmi2 specifically, confirm the end state rather than
# trusting the command, and keep retrying if it didn't take. Bounded at 3
# attempts because the framework can lag a beat behind the intent; treating
# that lag as failure would re-send `am start` needlessly.
verify_hdmi2() {
	local active
	for _ in 1 2 3; do
		active="$(timeout 5 adb -s "$TV" shell dumpsys tv_input 2>/dev/null | grep "inputId:" | tail -1 | awk '{print $2}')"
		[ "$active" = "$HDMI2_INPUT_ID" ] && return 0
		sleep 1
	done
	echo "$(date +%s.%N) TV-INPUT[$CALL_ID] verify: active=[$active] wanted=[$HDMI2_INPUT_ID]" >>"$DEBUG_LOG"
	return 1
}

# Per-action retry budget. The wide 150-attempt window above is about hdmi2 (and
# wakeup) right after the TV comes back, and is wrong for `home`, which only ever
# runs from hypridle's before_sleep_cmd. At that moment NetworkManager has
# already torn the network down (~1ms after the suspend request -- see
# gamescope-wrapper/dbus-send), so the call fails; the retry loop is then frozen
# mid-suspend and CONTINUES ON THE NEXT RESUME, landing a KEYCODE_HOME seconds
# after the machine is back. Measured three times, e.g.:
#
#   1785366000.492  [27738-home] waiting for lock   <- going to sleep
#   1785366020.614  PrepareForSleep (false,)        <- woken 20s later
#   1785366027.772  [27738-home] SUCCESS            <- TV yanked to dashboard
#
# and one that landed 89 minutes late off a long suspend. A single attempt makes
# it work now or not at all, which is the right shape for a best-effort tidy-up
# on the way down: it cannot outlive the suspend that triggered it.
case "$action" in
home) MAX_ATTEMPTS=1 ;;
*) MAX_ATTEMPTS=150 ;;
esac

for _ in $(seq 1 "$MAX_ATTEMPTS"); do
	if timeout 2 adb connect "$TV" >/dev/null 2>&1 && run; then
		if [ "$action" != hdmi2 ] || verify_hdmi2; then
			echo "$(date +%s.%N) TV-INPUT[$CALL_ID] SUCCESS" >>"$DEBUG_LOG"
			exit 0
		fi
		echo "$(date +%s.%N) TV-INPUT[$CALL_ID] intent ok but input not HDMI2, retrying" >>"$DEBUG_LOG"
	fi
	sleep 1
done
echo "$(date +%s.%N) TV-INPUT[$CALL_ID] FAILED after 150 attempts" >>"$DEBUG_LOG"
