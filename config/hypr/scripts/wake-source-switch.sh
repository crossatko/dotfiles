#!/bin/bash
# Picks which session to be in after a resume, based on *which device woke the
# machine*: a controller wake means "I sat down on the sofa" -> gamescope-
# session on the TV; a keyboard/mouse wake means "I sat down at the desk" ->
# Hyprland. Either way the other session is ended outright -- explicitly fine
# per the user, nothing is ever left unsaved on the desktop side (but see the
# game-progress note under `apply` below, which is a different thing).
#
# Driven by gamescope-sleep-signal-listener.sh, which already owns both halves
# of logind's PrepareForSleep and, crucially, runs on default.target rather
# than graphical-session.target -- so it survives the very session switch this
# script performs. Three verbs:
#
#   snapshot            on PrepareForSleep (true,)  -- before suspend
#   decide              on PrepareForSleep (false,) -- after resume; PRINTS
#                       stay | switch:gamescope | switch:hyprland, no effects
#   apply <session>     actually performs the switch
#   report              human-readable dump of the raw counters, for debugging
#
# decide is deliberately side-effect free so it can be dry-run, and so the
# listener can use its answer to decide whether its own TV wake work is even
# worth doing (it isn't, if we're about to leave gamescope-session).
#
# ATTRIBUTION MECHANISM
# There is no single "what woke me" file in the kernel. /sys/power/pm_wakeup_irq
# gives an IRQ, but the Logitech receiver and the Steam Puck sit on the same
# xHCI controller (0e:00.4), so an IRQ can't separate the mouse from the
# controller dongle. What does work is per-device wakeup accounting: snapshot
# the counters before suspending, diff them after resuming, and whichever
# device moved is the one that woke us.
#
# Which counter, though, matters -- measured on this hardware, from a real
# controller wake out of Hyprland:
#
#   28de:1304  count 0->0   active 0->1   last_time_ms 0->1073770
#
# power/wakeup_count -- the obvious candidate, and the one the sysfs docs make
# sound authoritative -- does NOT move at all. Only wakeup_active_count does,
# plus wakeup_last_time_ms becoming non-zero. So active_count is the real
# signal here and count is the unreliable one; both are checked (either moving
# counts as a mover) because relying on count alone silently classifies every
# wake as "unknown" and the whole feature quietly does nothing.
#
# Only these three devices on this machine have power/wakeup == enabled, i.e.
# are physically capable of waking it at all:
#
#   4653:0001  foostan Corne           split keyboard      -> desk
#   046d:c54d  Logitech USB Receiver   mouse (Unifying)    -> desk
#   28de:1304  Valve Steam Controller Puck  wireless dongle -> sofa
#
# Keyed by idVendor:idProduct rather than USB path (3-2 / 5-1 / 5-2 today)
# because the paths move if anything is replugged into a different port.
#
# Note the MSI "Gaming Controller" (1462:3fa4) is NOT a gamepad -- it is the
# monitor's own HID endpoint. It has no power/wakeup file at all and its parent
# hub is disabled, so it can neither wake the machine nor be confused for one.

set -u

declare -A DEVICE_CLASS=(
	[4653:0001]=desk       # foostan Corne
	[046d:c54d]=desk       # Logitech USB Receiver (mouse)
	[28de:1304]=controller # Valve Steam Controller Puck
)

STATE_DIR="$HOME/.local/state/wake-source"
SNAPSHOT="$STATE_DIR/snapshot"
LOG="$STATE_DIR/log"
# Kill switch: touch this and every resume becomes "stay", without having to
# unpick the listener wiring. Worth having for something that changes what
# happens on *every* wake.
DISABLED="$STATE_DIR/disabled"
# Set to 1 to make the listener log its decision without acting on it. Left on
# until a real suspend/resume cycle proved the attribution above is correct on
# this hardware -- the counters were all still 0 when this was written (no
# suspend had happened that boot), so it was plausible but unverified.
DRY_RUN_FILE="$STATE_DIR/dry-run"

GAMESCOPE_MARKER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamescope-environment"
NEXT_SESSION="$HOME/.local/state/next-session"

mkdir -p "$STATE_DIR"

log() { echo "$(date +%s.%N) WAKE-SOURCE $*" >>"$LOG"; }

# Emits "vid:pid<TAB>syspath<TAB>count<TAB>active_count<TAB>last_time_ms" for
# every known device that is currently wakeup-enabled.
read_counters() {
	local d v p key
	for d in /sys/bus/usb/devices/*/; do
		v=$(cat "$d/idVendor" 2>/dev/null) || continue
		p=$(cat "$d/idProduct" 2>/dev/null) || continue
		[ -n "$v" ] && [ -n "$p" ] || continue
		key="$v:$p"
		[ -n "${DEVICE_CLASS[$key]:-}" ] || continue
		[ "$(cat "$d/power/wakeup" 2>/dev/null)" = "enabled" ] || continue
		printf '%s\t%s\t%s\t%s\t%s\n' \
			"$key" "$(basename "$d")" \
			"$(cat "$d/power/wakeup_count" 2>/dev/null || echo 0)" \
			"$(cat "$d/power/wakeup_active_count" 2>/dev/null || echo 0)" \
			"$(cat "$d/power/wakeup_last_time_ms" 2>/dev/null || echo 0)"
	done
}

current_session() {
	[ -e "$GAMESCOPE_MARKER" ] && echo gamescope || echo hyprland
}

# Steam wraps every game launch in `reaper SteamLaunch AppId=NNN`, which is a
# much better marker than hunting for .exe processes -- Proton leaves assorted
# helper .exes around whose presence says nothing about whether a game is up.
#
# The bracket around the space is the standard self-match guard: it makes the
# pattern not match a command line that literally contains "SteamLaunch AppId="
# -- such as any shell or editor that happens to be inspecting this check.
game_running() {
	pgrep -f "SteamLaunch[ ]AppId=" >/dev/null 2>&1
}

# Prints the winning class: controller | desk | unknown
classify_wake() {
	[ -s "$SNAPSHOT" ] || {
		log "no snapshot (listener restarted mid-suspend?) -> unknown"
		echo unknown
		return
	}

	local key path count active last
	local -A before_count=() before_active=() before_last=()
	while IFS=$'\t' read -r key path count active last; do
		[ -n "${key:-}" ] || continue
		before_count[$key]=$count
		before_active[$key]=$active
		before_last[$key]=$last
	done <"$SNAPSHOT"

	# Either counter moving makes a device a mover. In practice on this box it
	# is always active_count and never count -- see the header -- but checking
	# both costs nothing and keeps this working if that ever differs per device
	# or across a kernel bump. Tiebreak among multiple movers: most recent
	# wakeup_last_time_ms wins.
	local winner=unknown best_last=-1 movers=0
	while IFS=$'\t' read -r key path count active last; do
		[ -n "${key:-}" ] || continue
		local bc=${before_count[$key]:-0} ba=${before_active[$key]:-0} bl=${before_last[$key]:-0}
		local dc=$((count - bc)) da=$((active - ba))
		if [ "$dc" -gt 0 ] || [ "$da" -gt 0 ]; then
			movers=$((movers + 1))
			log "mover: $key ($path) count $bc->$count active $ba->$active last_ms $bl->$last class=${DEVICE_CLASS[$key]}"
			if [ "$last" -gt "$best_last" ]; then
				best_last=$last
				winner=${DEVICE_CLASS[$key]}
			fi
		else
			log "idle:  $key ($path) count $bc->$count active $ba->$active"
		fi
	done <<<"$(read_counters)"

	[ "$movers" -gt 1 ] && log "WARNING $movers devices moved; picked most recent (last_ms=$best_last)"
	echo "$winner"
}

case "${1:-}" in
snapshot)
	read_counters >"$SNAPSHOT"
	log "snapshot taken in session=$(current_session): $(tr '\n' ';' <"$SNAPSHOT")"
	;;

decide)
	if [ -e "$DISABLED" ]; then
		log "decide: kill switch present ($DISABLED) -> stay"
		echo stay
		exit 0
	fi

	class=$(classify_wake)
	current=$(current_session)
	case "$class" in
	controller) want=gamescope ;;
	desk) want=hyprland ;;
	*) want=$current ;; # unknown -> never move; a spurious/RTC/network wake
		# must not yank the user into another session
	esac

	if [ "$want" = "$current" ]; then
		log "decide: class=$class current=$current -> stay"
		echo stay
	elif [ -e "$DRY_RUN_FILE" ]; then
		log "decide: class=$class current=$current -> WOULD switch:$want (dry-run)"
		echo stay
	else
		log "decide: class=$class current=$current -> switch:$want"
		echo "switch:$want"
	fi
	;;

apply)
	target="${2:-}"
	log "apply: $target (from $(current_session))"
	case "$target" in
	gamescope)
		echo gamescope >"$NEXT_SESSION"
		# session-supervisor.sh's loop re-reads that marker as soon as the
		# current session's process exits, so ending Hyprland is the whole
		# switch. -i 0 because this runs from a service started before
		# Hyprland existed: it has no HYPRLAND_INSTANCE_SIGNATURE, and
		# systemctl --user import-environment only affects units started
		# afterwards. Verified that -i 0 resolves the instance with
		# WAYLAND_DISPLAY/DISPLAY/HIS all unset.
		if ! hyprctl -i 0 dispatch exit >/dev/null 2>&1; then
			log "apply: hyprctl exit failed, falling back to SIGTERM"
			pkill -x Hyprland
		fi
		;;
	hyprland)
		echo hyprland >"$NEXT_SESSION"
		# Mirrors the 'plasma' case of the locally-patched
		# /usr/bin/steamos-session-select (what Steam's own "Switch to
		# Desktop" runs), replicated inline rather than calling it: that
		# script ends in a pkexec block which cannot work from a service
		# with no way to prompt.
		#
		# Get the TV dark immediately instead of letting it display the
		# teardown. Without this you watch it paint Steam, sit there for the
		# whole shutdown wait, and only go to standby at the very end via the
		# target's ExecStop -- ~24s of theatre on the way to the desk.
		# KEYCODE_SLEEP always sleeps rather than toggling (see tv-sleep.sh),
		# so ExecStop firing it again shortly after is a harmless no-op.
		/home/kreejzak/.config/hypr/scripts/tv-sleep.sh &

		# NOTE this is the one direction that can cost something -- stopping
		# the target takes gamescope and any running game down with it, so a
		# game's progress since its last autosave is gone. Asking Steam to shut
		# down first is what gives it a chance to close the game cleanly, but
		# that wait is only worth paying when there IS a game: with none
		# running it was just a long pause staring at Steam.
		if game_running; then
			log "apply: game running, asking Steam to shut down first"
			steam -shutdown >/dev/null 2>&1 || true
			waited=0
			while [ "$waited" -lt 30 ] && pgrep -x steam >/dev/null; do
				sleep 1
				waited=$((waited + 1))
			done
			if pgrep -x steam >/dev/null; then
				log "apply: Steam still up after ${waited}s, stopping target anyway"
			else
				log "apply: Steam exited after ${waited}s"
			fi
		else
			log "apply: no game running, stopping target immediately"
		fi
		systemctl --user stop gamescope-session.target
		;;
	*)
		log "apply: unknown target '$target', doing nothing"
		exit 1
		;;
	esac
	;;

report)
	echo "session:  $(current_session)"
	echo "kill switch: $([ -e "$DISABLED" ] && echo PRESENT || echo absent)"
	echo "dry run:     $([ -e "$DRY_RUN_FILE" ] && echo ON || echo off)"
	echo
	printf '%-11s %-6s %-24s %8s %8s %12s\n' VID:PID PATH CLASS COUNT ACTIVE LAST_MS
	while IFS=$'\t' read -r key path count active last; do
		printf '%-11s %-6s %-24s %8s %8s %12s\n' \
			"$key" "$path" "${DEVICE_CLASS[$key]}" "$count" "$active" "$last"
	done <<<"$(read_counters)"
	echo
	if [ -s "$SNAPSHOT" ]; then
		echo "snapshot from before last suspend:"
		sed 's/^/  /' "$SNAPSHOT"
	else
		echo "no snapshot yet (no suspend since this script was installed)"
	fi
	;;

*)
	echo "usage: $(basename "$0") snapshot|decide|apply <gamescope|hyprland>|report" >&2
	exit 1
	;;
esac
