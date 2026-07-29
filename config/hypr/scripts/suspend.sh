#!/bin/bash
# The Hyprland session's suspend entry point: tidies the TV up first, and only
# then asks logind to suspend. Wired to power-menu.lua's "sleep" action.
#
# The ordering is the entire point and is not stylistic. Anything reacting to
# logind's PrepareForSleep broadcast is already too late to talk to the TV:
# NetworkManager holds a mode=delay inhibitor of its own ("NetworkManager needs
# to turn off networks") and uses it to tear the network down ~1ms after the
# suspend is requested, while a shell script needs ~40ms just to start.
# Measured, from a real suspend:
#
#   01:23:40.633779  logind: suspend requested
#   01:23:40.634852  NetworkManager: state is now DISABLED (ASLEEP)
#   01:23:40.635650  RTM_DELROUTE: default route via 192.168.0.1 deleted
#   01:23:40.677     a PrepareForSleep handler starts here -- network long gone
#
# Delay inhibitors run concurrently with no ordering between them, and
# NetworkManager has no option to opt out of its sleep handling, so this cannot
# be fixed by reacting faster -- only by acting before the request exists.
#
# That is why hypridle's before_sleep_cmd could never do this job: it fires on
# that same broadcast. Its tv-input.sh call failed on the dead network, sat in a
# retry loop, got frozen by the suspend, and then completed on the *next resume*
# -- landing a KEYCODE_HOME seconds (in one measured case 89 minutes) after the
# machine came back, yanking the TV to its dashboard out of whatever was
# playing. See tv-input.sh's own notes on the retry budget.
#
# gamescope-wrapper/dbus-send is the equivalent hook for the gamescope session,
# where Steam requests the suspend itself. That one puts the TV fully into
# standby rather than merely releasing its input, because there the TV *is* the
# session; here it is a shared living-room device that may well be in use by
# someone else, so we only get off its input.

SCRIPTS="$HOME/.config/hypr/scripts"

# tv-input.sh home self-guards: it reads the TV's current input first and does
# nothing at all unless the TV is actually sitting on our HDMI2 passthrough, so
# this can never interrupt something being watched. Bounded regardless -- a
# wedged adb must not be able to stop the machine from sleeping.
timeout 8 "$SCRIPTS/tv-input.sh" home

# SUSPEND_CMD exists so this script's real path can be exercised in a test
# without actually suspending the machine.
exec ${SUSPEND_CMD:-systemctl suspend}
