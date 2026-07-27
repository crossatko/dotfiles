#!/bin/bash
# Resolves the current `ddcutil --bus` number for a monitor by matching its
# EDID model string via `ddcutil detect`, since the DP connector enumeration
# order on this GPU/driver isn't guaranteed stable across boots -- the same
# monitor can silently land on a different I2C bus next time.

model="$1"

# `ddcutil detect` takes ~2s (it probes I2C buses), which is unacceptable to
# pay on every Hyprland reload/start -- the bus only changes across reboots,
# so cache the result for the current boot (boot_id keys the cache path so a
# reboot can never see a stale value).
boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
cache_file="/tmp/ddc-bus-cache-${boot_id}-${model}"

if [ -s "$cache_file" ]; then
	cat "$cache_file"
	exit 0
fi

bus="$(ddcutil detect 2>/dev/null | awk -v model="$model" '
	/I2C bus:/ { bus = $3; sub(/.*-/, "", bus) }
	/Model:/ && tolower($0) ~ tolower(model) { print bus; exit }
')"

if [ -n "$bus" ]; then
	echo "$bus" >"$cache_file"
fi

echo "$bus"
