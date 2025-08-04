#!/bin/bash

getxkblayout() {
  LAYOUT=$(hyprctl devices -j | jq -r '.keyboards[] | .active_keymap' | head -n1 | cut -c1-2 | tr 'a-z' 'A-Z')
  echo "{\"text\": \"$LAYOUT\", \"tooltip\": \"Current Layout: $LAYOUT\"}"
}

switchxkblayout() {
  hyprctl --batch "$(
    hyprctl devices -j |
      jq -r '.keyboards[] | .name' |
      while IFS= read -r keyboard; do
        printf '%s %s %s;' 'switchxkblayout' "${keyboard}" 'next'
      done
  )"
  getxkblayout
}

case "$1" in
switch)
  switchxkblayout
  ;;
get)
  getxkblayout
  ;;
*)
  echo "{\"text\": \"ERR\", \"tooltip\": \"Invalid action\"}"
  ;;
esac
