#!/bin/bash

# Path to the PID file
PIDFILE="/tmp/hyprsunset.pid"

# Check if a parameter (temperature) is provided, default to 4000 if not
TEMP=${1:-4000}
ACTION=${2:-"status"} # Default action is "status"

if [[ "$ACTION" == "toggle" ]]; then
  # If the action is "toggle", start or stop the hyprsunset process

  if [[ -f "$PIDFILE" && -n "$(cat $PIDFILE)" && -e /proc/$(cat $PIDFILE) ]]; then
    # If the process is running, kill it and remove the PID file
    kill "$(cat $PIDFILE)"
    rm "$PIDFILE"

    # Output JSON for "OFF" state
    echo '{"alt": "off", "class": "off", "tooltip": "Hyprsunset is OFF"}'
  else
    # If the process is not running, start it and save the PID
    hyprsunset -t "$TEMP" &>/dev/null &
    echo $! >"$PIDFILE"

    # Output JSON for "ON" state
    echo '{"alt": "on", "class": "on", "tooltip": "Hyprsunset is ON"}'
  fi
else
  # If the action is not "toggle", just return the current state

  if [[ -f "$PIDFILE" && -n "$(cat $PIDFILE)" && -e /proc/$(cat $PIDFILE) ]]; then
    # If the process is running, return "ON" state
    echo '{"alt": "on", "class": "on", "tooltip": "Hyprsunset is ON"}'
  else
    # If the process is not running, return "OFF" state
    echo '{"alt": "off", "class": "off", "tooltip": "Hyprsunset is OFF"}'
  fi
fi
