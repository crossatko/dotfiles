#!/usr/bin/env bash

pkill -x waybar >/dev/null 2>&1

sleep 2

config_dir="$(dirname "$(readlink -f "$0")")"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
config_out="$runtime_dir/waybar-config.jsonc"

hostname="$(cat /proc/sys/kernel/hostname 2>/dev/null || hostname 2>/dev/null || uname -n)"

if [[ "${hostname^^}" == *WORKSTATION* ]]; then
  cp "$config_dir/config.jsonc" "$config_out"
else
  awk '
    /\/\/ WORKSTATION-ONLY-START/ { skip=1; next }
    /\/\/ WORKSTATION-ONLY-END/ { skip=0; next }
    !skip
  ' "$config_dir/config.jsonc" > "$config_out"
fi

waybar -c "$config_out" -s "$config_dir/style.css" &
