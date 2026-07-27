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

~/.local/state/androidtv-remote/venv/bin/python3 ~/.local/state/androidtv-remote/wol.py "$MAC" >/dev/null 2>&1
