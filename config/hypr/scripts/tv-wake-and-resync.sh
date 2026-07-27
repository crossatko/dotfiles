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
for i in $(seq 1 10); do
	out="$(~/.local/state/androidtv-remote/venv/bin/python3 ~/.local/state/androidtv-remote/wol.py "$MAC" 2>&1)"
	echo "$(date +%s.%N) WOL[$i] $out" >>"$DEBUG_LOG"
	sleep 1
done
