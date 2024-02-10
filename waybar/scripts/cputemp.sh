#!/bin/bash

# Get the temperature value in millidegrees Celsius
temp=$(cat /sys/class/thermal/thermal_zone4/temp)

# Convert millidegrees Celsius to degrees Celsius
temperature=$(echo "scale=0; $temp / 1000" | bc)

# Check if temperature is hot (over 80 degrees Celsius)
if [ "$temperature" -gt 80 ]; then
	alt="hot"
elif [ "$temperature" -gt 50 ]; then
	alt="warm"
else
	alt="cool"
fi

echo '{ 
    "text": "'"$temperature"'", 
    "alt": "'"$alt"'",
    "class": "'"$alt"'"
}' | jq --unbuffered --compact-output
