#!/bin/bash

# Set the preset file
PRESET_FILE="$HOME/.mic_preset"

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
  amixer set 'Capture' 0%
  echo "$MUTE_PRESET" >"$PRESET_FILE"

else
  amixer set 'Capture' 110%
  echo "$MIC_PRESET" >"$PRESET_FILE"
fi
