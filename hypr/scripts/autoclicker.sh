#!/bin/bash

LOCK_FILE="/tmp/autoclicker.lock"

start_autoclicker() {
  echo "Starting autoclicker..."
  touch "$LOCK_FILE"
  while [ -f "$LOCK_FILE" ]; do
    wlrctl pointer click left
    sleep 0.01
  done
}

stop_autoclicker() {
  echo "Stopping autoclicker..."
  rm -f "$LOCK_FILE"
}

if [ -f "$LOCK_FILE" ]; then
  stop_autoclicker
else
  start_autoclicker &
fi
