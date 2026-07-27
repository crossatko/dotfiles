#!/bin/bash
# Sets DDC brightness with retry: ddcutil/I2C communication can fail
# transiently (bus contention/timing -- seen elsewhere this session too),
# and a single unverified call left one monitor stuck at the wrong
# brightness while a sibling call for the other monitor succeeded, with no
# retry and no way to notice.

BUS="$1"
LEVEL="$2"

for _ in 1 2 3; do
	if ddcutil --bus "$BUS" setvcp 0x10 "$LEVEL" >/dev/null 2>&1; then
		exit 0
	fi
	sleep 0.3
done
exit 1
