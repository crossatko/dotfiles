#!/bin/bash

# Check if MAC address is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <MAC_ADDRESS>"
  exit 1
fi

# Set the MAC address from the argument
DEVICE_MAC="$1"

# Helper function to get connection status
get_status() {
  # Check if device is connected
  if bluetoothctl info "$DEVICE_MAC" | grep -q "Connected: yes"; then
    echo '{"alt": "connected", "class": "connected", "tooltip": "Click to disconnect device"}'
  else
    echo '{"alt": "disconnected", "class": "disconnected", "tooltip": "Click to connect device"}'
  fi
}

# Function to toggle device connection
toggle_connection() {
  # Check current connection status
  if bluetoothctl info "$DEVICE_MAC" | grep -q "Connected: yes"; then
    # If connected, disconnect
    bluetoothctl disconnect "$DEVICE_MAC"
  else
    # If disconnected, connect
    bluetoothctl connect "$DEVICE_MAC"
  fi
}

# Main script logic
if [ "$2" == "toggle" ]; then
  toggle_connection
  sleep 1 # Give it a moment to update
  get_status
else
  get_status
fi
