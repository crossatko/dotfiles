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

# CARD_INDEX=$(aplay -l | grep "Scarlett Solo" | awk '{print $2}' | sed 's/://')
# amixer -c "$CARD_INDEX" cset numid=15 on
# echo "Card index: $CARD_INDEX"

# Toggle between 'mic' and 'mute'
if [ "$CURRENT_PRESET" == "$MIC_PRESET" ]; then
	amixer set 'Capture' 0%
	# amixer -c "$CARD_INDEX" cset numid=22 off
	$EASY_EFFECTS_PATH -l $MUTE_PRESET
	echo "$MUTE_PRESET" >"$PRESET_FILE"

else
	amixer set 'Capture' 100%
	# amixer -c "$CARD_INDEX" cset numid=22 on
	$EASY_EFFECTS_PATH -l $MIC_PRESET
	echo "$MIC_PRESET" >"$PRESET_FILE"
fi
