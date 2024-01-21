#!/bin/bash

# Set the path to the EasyEffects program
EASY_EFFECTS_PATH="easyeffects"

# Set the preset file
PRESET_FILE="$HOME/.easyeffects_preset"

# Set the presets
MIC_PRESET="mic"
MUTE_PRESET="mute"

# Check the current preset from the file or default to 'mic'
if [ -e "$PRESET_FILE" ]; then
	CURRENT_PRESET=$(cat "$PRESET_FILE")
else
	touch "$PRESET_FILE" && echo "$MIC_PRESET" >"$PRESET_FILE"
	CURRENT_PRESET=$MIC_PRESET
fi

# Toggle between 'mic' and 'mute'
if [ "$CURRENT_PRESET" == "$MIC_PRESET" ]; then
	amixer set Capture mute
	$EASY_EFFECTS_PATH -l $MUTE_PRESET
	echo "$MUTE_PRESET" >"$PRESET_FILE"
	echo "Switched to Mute preset"
else
	amixer set Capture unmute
	$EASY_EFFECTS_PATH -l $MIC_PRESET
	echo "$MIC_PRESET" >"$PRESET_FILE"
	echo "Switched to Mic preset"
fi
