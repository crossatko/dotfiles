#!/bin/bash

# Configuration
TWITCH_USERNAME="crossatko"                  # Replace with your Twitch username
CLIENT_ID="hqa6g06mxbanwfp2d9yrohcuqatx6z"   # Get this from Twitch Developer Console
OAUTH_TOKEN="qa4m3uhf3yufl3v41sw4ur31ijoi2a" # Get this from Twitch API

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Temporary file to store API responses
TEMP_FILE="/tmp/twitch_response.json"

# Function to check if jq and curl are installed
check_dependencies() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install it with 'sudo apt-get install jq' or 'brew install jq'"
    exit 1
  fi
  if ! command -v curl &>/dev/null; then
    echo "Error: curl is required. Install it with 'sudo apt-get install curl' or 'brew install curl'"
    exit 1
  fi
}

# Function to get your user ID
get_user_id() {
  local user_id
  user_id=$(curl -s -H "Client-ID: $CLIENT_ID" \
    -H "Authorization: Bearer $OAUTH_TOKEN" \
    -X GET "https://api.twitch.tv/helix/users?login=$TWITCH_USERNAME" |
    jq -r '.data[0].id')

  if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
    echo "Error: Could not get user ID for $TWITCH_USERNAME. Check your username, Client ID, and OAuth token."
    exit 1
  fi
  echo "$user_id"
}

# Function to get followed channels
get_followed_channels() {
  local user_id="$1"
  curl -s -H "Client-ID: $CLIENT_ID" \
    -H "Authorization: Bearer $OAUTH_TOKEN" \
    -X GET "https://api.twitch.tv/helix/channels/followed?user_id=$user_id&first=100" \
    >"$TEMP_FILE"

  if ! jq -e '.data' "$TEMP_FILE" >/dev/null 2>&1; then
    echo "Error: Failed to fetch followed channels. Check your OAuth token and permissions."
    cat "$TEMP_FILE"
    exit 1
  fi
}

# Function to check live status
check_live_status() {
  echo "Checking your followed Twitch channels..."
  echo "----------------------------------------"

  # Get list of followed channel IDs
  followed_ids=$(jq -r '.data[].broadcaster_id' "$TEMP_FILE" | tr '\n' '&id=')
  followed_ids=${followed_ids%&id=} # Remove trailing '&id='

  if [ -z "$followed_ids" ]; then
    echo "No followed channels found. Do you follow any channels?"
    exit 0
  fi

  # Get live status for all followed channels
  live_response=$(curl -s -H "Client-ID: $CLIENT_ID" \
    -H "Authorization: Bearer $OAUTH_TOKEN" \
    -X GET "https://api.twitch.tv/helix/streams?$followed_ids")

  # Create a list of live channels
  live_channels=$(echo "$live_response" | jq -r '.data[].user_name')

  # Check each followed channel against live status
  jq -r '.data[].broadcaster_name' "$TEMP_FILE" | while read -r channel; do
    if echo "$live_channels" | grep -q "^$channel$"; then
      echo -e "${GREEN}$channel is LIVE${NC}"
    else
      echo -e "${RED}$channel is offline${NC}"
    fi
  done
}

# Main execution
check_dependencies
user_id=$(get_user_id)
get_followed_channels "$user_id"
check_live_status

# Cleanup
rm -f "$TEMP_FILE"
