#!/bin/bash
# Sends a WoL magic packet to wake the TV. Detecting when it actually comes
# back online and completing the enable/dim/input-switch sequence is
# entirely tv-input-poll.sh's job (it's already polling every 2s and fires
# hypr_tv_dim_force_resync() itself on a confirmed reachability transition).
#
# This script used to ALSO independently wait for reachability and call
# hypr_tv_dim_force_resync() itself -- which raced with the poller's own
# transition-triggered call (both firing within ~1s of each other in
# practice, confirmed via debug logging), causing two overlapping/racing
# tv-input.sh hdmi2 invocations (adb shares one server process across every
# call) that left the TV's own input framework in limbo -- dumpsys tv_input
# reported no active session at all afterward, and the TV visibly sat on
# its home screen instead of HDMI2. Sending the packet here and letting the
# poller do everything else, exactly once, fixes that.

MAC="7c:01:3e:f4:0b:6c"
TV_ADB="192.168.0.128:5555"
DEBUG_LOG="$HOME/.local/state/androidtv-remote/poll-debug.log"
mkdir -p "$(dirname "$DEBUG_LOG")"

# Called right after a system resume, when this machine's own network
# interface hasn't necessarily reconnected yet -- the driver/link needs to
# come back and NetworkManager needs to re-associate (WiFi) or renegotiate
# (ethernet) before there's even a route to broadcast on, and that can
# take longer than a couple seconds. Wait for a default route first
# instead of guessing a fixed delay.
for i in $(seq 1 30); do
	ip route show default 2>/dev/null | grep -q . && break
	sleep 1
done

# Sent silently for years with no way to tell if it actually worked --
# fixed now that a real failure mode showed up (see above). WoL packets
# are cheap, harmless to resend, and idempotent -- a few retries here is
# just extra margin in case the route above appeared before the interface
# was fully usable.
#
# Stops as soon as the TV is actually up, and checks BEFORE sending, so an
# already-awake TV costs one ping and nothing else. This loop used to run all
# ten iterations unconditionally, and because gamescope-session-wake.sh chained
# the HDMI input switch *behind* this script, those ten seconds were the single
# largest source of "the TV lit up instantly but stayed on the wrong input
# until after Steam's intro had played" -- worst precisely when the TV was
# already on and the wake was pointless.
#
# Two things the readiness check must NOT be, both measured here:
#
#   wol.py's own exit status. It does sendto() on a broadcast socket and then
#   prints "sent magic packet" unconditionally -- no response to read, no error
#   path, and every historical log line is identical. Breaking on that would
#   send exactly one packet every time, which is the behaviour this retry loop
#   exists to avoid: a frame sent while the interface is still settling is
#   silently lost.
#
#   Network reachability (ping / adb connect). This TV has two distinct
#   "off" states and reachability cannot tell them apart. After tv-sleep.sh's
#   KEYCODE_SLEEP the panel is dark but the Android stack stays fully up, so it
#   answers ping and adb happily while showing nothing -- and WoL is exactly
#   what wakes it from there (confirmed: mWakefulness went Asleep -> Awake
#   within 2s of a single packet, with no keyevent involved). Breaking on
#   reachability would therefore skip the packet that does the work and leave
#   the panel dark.
#
# The panel's own power state is the real event, and the only signal that
# distinguishes those two cases. Unreachable (genuinely powered down) makes this
# fail fast and fall through to sending, which is correct -- that is the case
# WoL is actually for.
tv_awake() {
	timeout 2 adb connect "$TV_ADB" >/dev/null 2>&1 || return 1
	timeout 5 adb -s "$TV_ADB" shell dumpsys power 2>/dev/null |
		grep -q 'mWakefulness=Awake'
}

for i in $(seq 1 10); do
	if tv_awake; then
		echo "$(date +%s.%N) WOL[$i] panel already awake, stopping early" >>"$DEBUG_LOG"
		break
	fi
	out="$(~/.local/state/androidtv-remote/venv/bin/python3 ~/.local/state/androidtv-remote/wol.py "$MAC" 2>&1)"
	echo "$(date +%s.%N) WOL[$i] $out" >>"$DEBUG_LOG"
	sleep 1
done
