#!/bin/bash
# Polls the TV's currently active input over ADB and enables/disables the
# Hyprland output it's plugged into (see monitors.lua's tv.output) to match.
# There's no push-based signal for "the TV was manually pointed at this
# input" -- no CEC on this GPU, and this TV's HDMI hot-plug-detect doesn't
# reflect input selection either -- so polling is the only way to pick this
# up. Talks to scripts/tv-manual-connect.lua via `hyprctl eval`, not
# scripts/steam-tv-dim.lua, which is left untouched.
#
# Also caches reachability to a file: steam-tv-dim.lua's is_tv_reachable()
# used to call `adb connect` directly, which blocks for however long the OS
# takes to time out an unreachable host (many seconds) -- and since that ran
# synchronously inside Hyprland's own Lua execution, it froze the entire
# compositor while the TV was off. Reading this file is instant/local-only;
# the actual network check stays confined to this already-running poller.
#
# This is also the SOLE trigger for hypr_tv_dim_force_resync() on a
# reachability transition -- scripts/tv-wake-and-resync.sh deliberately does
# NOT also call it after sending its WoL packet. It used to, and that raced
# with this poller's own transition detection (both firing within ~1s of
# each other), causing two overlapping/racing tv-input.sh hdmi2 invocations
# that left the TV's input framework in limbo instead of landing on HDMI2.

TV=192.168.0.128:5555
HDMI2_INPUT_ID='com.tcl.tvinput/.TvPassThroughService/HW16'
POLL_INTERVAL=2
# 4, not 2: confirmed live that switching the TV's input over ADB
# (tv-input.sh) itself causes a brief ADB connectivity blip on the TV's
# side, which a 2-failure (~4s) threshold misreads as "the TV genuinely
# went offline" -- disable_tv_monitor() fired seconds after
# enable_tv_monitor() had just run, undoing it and dropping the game
# workspace back onto the desktop monitor. ~8s stays comfortably under the
# 10s offline-detection latency this whole poller was built around, while
# giving enough room for that switch-induced blip to pass on its own.
FAIL_THRESHOLD=4
STATE_DIR="$HOME/.local/state/androidtv-remote"
REACHABLE_FILE="$STATE_DIR/reachable"
DEBUG_LOG="$STATE_DIR/poll-debug.log"

mkdir -p "$STATE_DIR"

# Single-instance guard: autostart.lua's hl.on("hyprland.start", ...) fires
# this on every Hyprland startup, and it's also been restarted manually
# many times across debugging sessions -- confirmed live that duplicates
# pile up silently (multiple pollers each independently hitting the TV over
# ADB and calling hyprctl eval, racing each other). A held, non-blocking
# flock means any second launch just exits immediately instead of stacking.
#
# NOTE: if you ever kill a running instance of this script by hand, its adb
# server child inherits fd 201 and keeps holding this lock even after the
# script itself is dead -- confirmed live, a relaunch silently no-ops until
# that orphaned `adb ... fork-server server` process is also killed.
exec 201>"$STATE_DIR/tv-input-poll.lock"
flock -n 201 || exit 0

# This poller is a long-lived background loop (started once from
# hyprland.start in autostart.lua) that outlives any single Hyprland
# process -- confirmed live: Hyprland restarted underneath an already-running
# instance of this script, which kept the OLD HYPRLAND_INSTANCE_SIGNATURE it
# inherited at launch, so every `hyprctl eval` call below silently targeted a
# dead compositor (stderr discarded) while still correctly detecting HDMI2
# over adb -- the TV was never actually switched over in Hyprland, and with
# no signal reaching it the TV's own passthrough view eventually gave up and
# fell back to its home launcher. `hyprctl instances -j` doesn't depend on
# the caller's own (possibly stale) signature -- it reads the live
# control-socket directory directly -- so re-resolving it fresh every loop
# iteration (~2ms measured here, negligible next to the adb calls already in
# this loop) keeps every hyprctl call below targeting whichever compositor is
# actually running right now. Picks the instance with the highest "time" if
# more than one is somehow live; empty (no live instance at all, e.g. mid
# gamescope-only session) if none.
current_instance_signature() {
	hyprctl instances -j 2>/dev/null | jq -r 'sort_by(.time) | last | .instance // empty'
}

consecutive_failures=0
# Empty, not 0/1: forces the first loop iteration to treat whatever it finds
# as a transition, so state (workspace/dim/audio) gets reconciled at least
# once on startup instead of assuming a prior poller already left it correct.
was_reachable=""
was_hdmi2=""
# Empty, not a real signature: same reasoning as was_reachable above --
# forces the first iteration's signature "change" check below to fire too.
last_synced_signature=""

while true; do
	sig="$(current_instance_signature)"
	export HYPRLAND_INSTANCE_SIGNATURE="$sig"
	# A compositor swap can happen with no accompanying reachability or
	# input-state change at all -- that's exactly what broke this originally
	# (Hyprland restarted, nothing on the ADB side ever moved). Forcing both
	# transition trackers to fire below is what actually re-asserts state
	# into a freshly-(re)started Hyprland, instead of trusting was_reachable/
	# was_hdmi2 flags that were only ever confirmed true against the
	# previous, now-dead, compositor.
	if [ "$sig" != "$last_synced_signature" ]; then
		was_reachable=""
		was_hdmi2=""
		last_synced_signature="$sig"
	fi

	# Every adb call here is timeout-wrapped: a single hung call (adb shares
	# one background server process across every invocation on this machine,
	# including any manual ad-hoc adb commands run elsewhere) must never be
	# able to freeze this loop forever -- that already happened once (cache
	# file went 100+ seconds stale despite a 3s interval, silently feeding a
	# wrong "unreachable" answer to steam-tv-dim.lua's staleness guard).
	if timeout 2 adb connect "$TV" >/dev/null 2>&1; then
		echo "$(date +%s.%N) POLLER CONNECT_OK" >>"$DEBUG_LOG"
		consecutive_failures=0
		echo 1 >"$REACHABLE_FILE"
		# steam-tv-dim.lua's stale-state correction (disable the TV output
		# and fall back to the primary monitor if it goes offline mid-Big
		# Picture-session) only ever runs on a "steam"-classed window open/
		# close event -- nothing else re-checks it, so a TV going dark with
		# no window event happening around the same time would otherwise
		# never get noticed. Firing the resync here specifically on a
		# confirmed transition (not every poll tick) catches that case
		# without turning this into a "fights manual use" continuous poll.
		if [ "$was_reachable" != "1" ]; then
			echo "$(date +%s.%N) POLLER FIRING_RESYNC (was_reachable=$was_reachable -> 1)" >>"$DEBUG_LOG"
			hyprctl eval 'hypr_tv_dim_force_resync()' >/dev/null 2>&1
		fi
		was_reachable=1
		current_input="$(timeout 5 adb -s "$TV" shell dumpsys tv_input 2>/dev/null | grep "inputId:" | tail -1 | awk '{print $2}')"
		echo "$(date +%s.%N) POLLER DUMPSYS current_input=[$current_input]" >>"$DEBUG_LOG"
		# Only called on an actual transition, not every 2s forever --
		# hypr_tv_set_manual_connect() already checks is_tv_connected() before
		# doing anything, so a repeat call with the same state was always a
		# silent no-op; skipping it here just cuts the redundant hyprctl
		# invocations in the (overwhelmingly common) steady-state case, with
		# no behavior change. The was_hdmi2="" reset above still forces this
		# to re-fire against a newly-(re)started compositor even when the
		# input itself never moved.
		if [ "$current_input" = "$HDMI2_INPUT_ID" ]; then
			if [ "$was_hdmi2" != "1" ]; then
				hyprctl eval 'hypr_tv_set_manual_connect(true)' >/dev/null 2>&1
				was_hdmi2=1
			fi
		else
			if [ "$was_hdmi2" != "0" ]; then
				hyprctl eval 'hypr_tv_set_manual_connect(false)' >/dev/null 2>&1
				was_hdmi2=0
			fi
		fi
	else
		consecutive_failures=$((consecutive_failures + 1))
		echo "$(date +%s.%N) POLLER CONNECT_FAIL count=$consecutive_failures" >>"$DEBUG_LOG"
		# Require sustained failure, not a single blip, before reporting
		# unreachable: one transient adb hiccup must not be able to kick the
		# TV off mid-session on its own.
		if [ "$consecutive_failures" -ge "$FAIL_THRESHOLD" ]; then
			echo 0 >"$REACHABLE_FILE"
			if [ "$was_reachable" != "0" ]; then
				echo "$(date +%s.%N) POLLER FIRING_RESYNC (was_reachable=$was_reachable -> 0)" >>"$DEBUG_LOG"
				hyprctl eval 'hypr_tv_dim_force_resync()' >/dev/null 2>&1
			fi
			was_reachable=0
		fi
	fi
	sleep "$POLL_INTERVAL"
done
