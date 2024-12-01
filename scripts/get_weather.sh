#!/bin/bash

# Define cache file and cache duration (in seconds)
CACHE_FILE="$HOME/.weather_cache"
CACHE_EXPIRY=3600 # 1 hour

# Check if the cache exists and is still valid
if [ -f "$CACHE_FILE" ]; then
  LAST_MODIFIED=$(stat -c %Y "$CACHE_FILE") # Last modification time
  CURRENT_TIME=$(date +%s)                  # Current time
  TIME_DIFF=$((CURRENT_TIME - LAST_MODIFIED))

  if [ "$TIME_DIFF" -lt "$CACHE_EXPIRY" ]; then
    exit 0 # Cache is valid; no need to fetch new data
  fi
fi

# Fetch new weather data and update the cache
curl -s "https://wttr.in/olomouc?0" >"$CACHE_FILE" &
