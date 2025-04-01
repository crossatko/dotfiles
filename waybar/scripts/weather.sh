#!/bin/bash

response=$(curl -s https://wttr.in?format=1)

if [[ "$response" == *"Unknown location"* ]]; then
  echo "{\"text\": \"🌩️❓\"}" # Weather-related error emoji
else
  remove_spaces=${response// /}
  echo "{\"text\": \"$remove_spaces\"}"
fi
