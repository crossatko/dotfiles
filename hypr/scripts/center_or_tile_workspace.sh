#!/bin/bash

# Get the current workspace information
CURRENT_WORKSPACE=$(hyprctl activeworkspace -j)

# Extract the workspace ID and window count from the current workspace information
CURRENT_WORKSPACE_ID=$(echo "$CURRENT_WORKSPACE" | jq '.id')
WINDOW_COUNT=$(echo "$CURRENT_WORKSPACE" | jq '.windows')

# Get the list of open clients on the current workspace
OPEN_CLIENTS=$(hyprctl clients -j | jq --argjson ws "$CURRENT_WORKSPACE_ID" '.[] | select(.workspace.id == $ws)')

# Output the results
echo "Current Workspace ID: $CURRENT_WORKSPACE_ID"
echo "Window Count: $WINDOW_COUNT"
echo "Open Clients: $OPEN_CLIENTS"

if [ "$WINDOW_COUNT" -eq 1 ]; then
  hyprctl dispatch setfloating active
  hyprctl dispatch resizeactive exact 2200 1392
  hyprctl dispatch centerwindow
  hyprctl dispatch moveactive 0 -17
else
  echo "$OPEN_CLIENTS" | jq -r '.address' | while read -r client_address; do
    hyprctl dispatch settiled address:"$client_address"
  done
fi
