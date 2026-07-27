#!/bin/bash
# Resolves which pactl card profile the TV's audio is actually on, by
# matching its EDID monitor name via ALSA's ELD (EDID-Like Data) exposure --
# not hardcoded, since which of this card's 4 audio pins maps to which
# physical port isn't stable (this changed the last time the TV moved to a
# different GPU port: it was "HDMI 4", after the move it became "HDMI 3").

MODEL="$1"
PCI_ADDR="$2" # e.g. 0000:03:00.1 -- same address embedded in tv.lua's TV_AUDIO_CARD

# /proc/asound/cardN's own index is assigned by driver-probe order at boot,
# same as the DP-N connector naming that broke elsewhere in this config --
# confirmed stale here too: card1 was the GPU's HDMI controller once, and is
# now the USB headset. Resolved fresh via the PCI address every call instead
# of trusting a hardcoded index.
CARD=""
for dev in /sys/class/sound/card*/device; do
	if [[ "$(readlink -f "$dev")" == *"$PCI_ADDR" ]]; then
		CARD="$(basename "$(dirname "$dev")")"
		break
	fi
done

[[ -z "$CARD" ]] && exit 0

PROFILES=(output:hdmi-stereo output:hdmi-stereo-extra1 output:hdmi-stereo-extra2 output:hdmi-stereo-extra3)

for eld in /proc/asound/"$CARD"/eld#0.*; do
	if grep -qi "monitor_name.*$MODEL" "$eld" 2>/dev/null; then
		idx="${eld##*.}"
		echo "${PROFILES[$idx]}"
		exit 0
	fi
done
