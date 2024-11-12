#!/bin/bash

# File to track recording state
RECORDING_STATE_FILE="/tmp/wf-recording-state"

# Output file for the recording
OUTPUT_FILE=~/Videos/screen_recording_$(date +%F_%T).mp4

# Check if wf-recorder is already running
if [ -f "$RECORDING_STATE_FILE" ]; then
  # If wf-recorder is running, stop it and copy the video to the clipboard
  pkill -INT wf-recorder
  rm "$RECORDING_STATE_FILE"

  # Wait for a moment to ensure the recording process finishes
  sleep 1

  # Copy the recorded video to the clipboard
  wl-copy <"$OUTPUT_FILE"
  notify-send "Recording stopped and copied to clipboard"

else
  # If wf-recorder is not running, start a new recording
  touch "$RECORDING_STATE_FILE"
  wf-recorder -g "$(slurp)" -f "$OUTPUT_FILE" &
  notify-send "Recording started"
fi
