#!/bin/bash

# Set the MAC address of your AirPods (replace this with your AirPods' MAC address)
AIRPODS_MAC="70:8C:F2:72:B1:A0"

# Helper function to get connection status
get_status() {
  # Check if AirPods are connected
  if bluetoothctl info "$AIRPODS_MAC" | grep -q "Connected: yes"; then
    echo '{"alt": "connected", "class": "connected", "tooltip": "Click to disconnect AirPods"}'
  else
    echo '{"alt": "disconnected", "class": "disconnected", "tooltip": "Click to connect AirPods"}'
  fi
}

# Function to toggle AirPods connection
toggle_connection() {
  # Check current connection status
  if bluetoothctl info "$AIRPODS_MAC" | grep -q "Connected: yes"; then
    # If connected, disconnect
    bluetoothctl disconnect "$AIRPODS_MAC"
  else
    # If disconnected, connect
    bluetoothctl connect "$AIRPODS_MAC"
  fi
}

# Main script logic
if [ "$1" == "toggle" ]; then
  toggle_connection
  sleep 1 # Give it a moment to update
  get_status
else
  get_status
fi
