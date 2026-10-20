#!/usr/bin/env bash
# @launcher.title Copy IP address
# @launcher.subtitle Copy the local IPv4 address to the clipboard
# @launcher.icon edit-copy
# @launcher.aliases ip, address, network
# @launcher.mode toast
ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}')
[ -n "$ip" ] || { echo "No IPv4 address found"; exit 1; }
printf '%s' "$ip" | wl-copy
echo "Copied $ip"
