#!/bin/bash
# Puts the living room TV to sleep on the way out of a gamescope-session
# (see gamescope-session-wake.service's ExecStop). Same adb address as
# tv-input.sh/tv-input-poll.sh. KEYCODE_SLEEP forces standby regardless of
# current state -- unlike KEYCODE_POWER, which just toggles -- so this is
# always "off", never an accidental wake.

TV=192.168.0.128:5555

timeout 3 adb connect "$TV" >/dev/null 2>&1 && timeout 3 adb -s "$TV" shell input keyevent KEYCODE_SLEEP >/dev/null 2>&1
