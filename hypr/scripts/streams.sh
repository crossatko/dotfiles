#!/bin/bash

streams=$(
  cat <<'EOF'
Ainrun|https://twitch.tv/Ainrun|https://www.twitch.tv/popout/Ainrun/chat?popout=
AntiElitz|https://twitch.tv/AntiElitz|https://www.twitch.tv/popout/AntiElitz/chat?popout=
Asmongold|https://twitch.tv/Asmongold|https://www.twitch.tv/popout/Asmongold/chat?popout=
Baalorlord|https://twitch.tv/Baalorlord|https://www.twitch.tv/popout/Baalorlord/chat?popout=
Bruno_Simon_Dev|https://twitch.tv/Bruno_Simon_Dev|https://www.twitch.tv/popout/Bruno_Simon_Dev/chat?popout=
Captain_Domo|https://twitch.tv/Captain_Domo|https://www.twitch.tv/popout/Captain_Domo/chat?popout=
ChaseTheBroYT|https://twitch.tv/ChaseTheBroYT|https://www.twitch.tv/popout/ChaseTheBroYT/chat?popout=
ChrisTitusTech|https://twitch.tv/ChrisTitusTech|https://www.twitch.tv/popout/ChrisTitusTech/chat?popout=
CodingGarden|https://twitch.tv/CodingGarden|https://www.twitch.tv/popout/CodingGarden/chat?popout=
CohhCarnage|https://twitch.tv/CohhCarnage|https://www.twitch.tv/popout/CohhCarnage/chat?popout=
DDRJake|https://twitch.tv/DDRJake|https://www.twitch.tv/popout/DDRJake/chat?popout=
DaniMilkman|https://twitch.tv/DaniMilkman|https://www.twitch.tv/popout/DaniMilkman/chat?popout=
Distortion2|https://twitch.tv/Distortion2|https://www.twitch.tv/popout/Distortion2/chat?popout=
DougDoug|https://twitch.tv/DougDoug|https://www.twitch.tv/popout/DougDoug/chat?popout=
ESAMarathon|https://twitch.tv/ESAMarathon|https://www.twitch.tv/popout/ESAMarathon/chat?popout=
Elajjaz|https://twitch.tv/Elajjaz|https://www.twitch.tv/popout/Elajjaz/chat?popout=
FanHOTS|https://twitch.tv/FanHOTS|https://www.twitch.tv/popout/FanHOTS/chat?popout=
GamesDoneQuick|https://twitch.tv/GamesDoneQuick|https://www.twitch.tv/popout/GamesDoneQuick/chat?popout=
GinoMachino|https://twitch.tv/GinoMachino|https://www.twitch.tv/popout/GinoMachino/chat?popout=
Grubby|https://twitch.tv/Grubby|https://www.twitch.tv/popout/Grubby/chat?popout=
Iron_Pineapple|https://twitch.tv/Iron_Pineapple|https://www.twitch.tv/popout/Iron_Pineapple/chat?popout=
Kitboga|https://twitch.tv/Kitboga|https://www.twitch.tv/popout/Kitboga/chat?popout=
Laeppa|https://twitch.tv/Laeppa|https://www.twitch.tv/popout/Laeppa/chat?popout=
LieutenantEddy|https://twitch.tv/LieutenantEddy|https://www.twitch.tv/popout/LieutenantEddy/chat?popout=
LilAggy|https://twitch.tv/LilAggy|https://www.twitch.tv/popout/LilAggy/chat?popout=
LobosJr|https://twitch.tv/LobosJr|https://www.twitch.tv/popout/LobosJr/chat?popout=
LokiTheFallen|https://twitch.tv/LokiTheFallen|https://www.twitch.tv/popout/LokiTheFallen/chat?popout=
Maarionete|https://twitch.tv/Maarionete|https://www.twitch.tv/popout/Maarionete/chat?popout=
Melkey|https://twitch.tv/Melkey|https://www.twitch.tv/popout/Melkey/chat?popout=
Mikehendi|https://twitch.tv/Mikehendi|https://www.twitch.tv/popout/Mikehendi/chat?popout=
Mitchriz|https://twitch.tv/Mitchriz|https://www.twitch.tv/popout/Mitchriz/chat?popout=
Nefrums|https://twitch.tv/Nefrums|https://www.twitch.tv/popout/Nefrums/chat?popout=
Nemz38|https://twitch.tv/Nemz38|https://www.twitch.tv/popout/Nemz38/chat?popout=
NikNocturnal|https://twitch.tv/NikNocturnal|https://www.twitch.tv/popout/NikNocturnal/chat?popout=
Nilaus|https://twitch.tv/Nilaus|https://www.twitch.tv/popout/Nilaus/chat?popout=
NuclearPastaTom|https://twitch.tv/NuclearPastaTom|https://www.twitch.tv/popout/NuclearPastaTom/chat?popout=
Peeve|https://twitch.tv/Peeve|https://www.twitch.tv/popout/Peeve/chat?popout=
Pixlriffs|https://twitch.tv/Pixlriffs|https://www.twitch.tv/popout/Pixlriffs/chat?popout=
Seki|https://twitch.tv/Seki|https://www.twitch.tv/popout/Seki/chat?popout=
Shamona1|https://twitch.tv/Shamona1|https://www.twitch.tv/popout/Shamona1/chat?popout=
Squillakilla|https://twitch.tv/Squillakilla|https://www.twitch.tv/popout/Squillakilla/chat?popout=
StaydMcMuffin|https://twitch.tv/StaydMcMuffin|https://www.twitch.tv/popout/StaydMcMuffin/chat?popout=
TheDementedSalad|https://twitch.tv/TheDementedSalad|https://www.twitch.tv/popout/TheDementedSalad/chat?popout=
ThePrimeagen|https://twitch.tv/ThePrimeagen|https://www.twitch.tv/popout/ThePrimeagen/chat?popout=
The_Happy_Hob|https://twitch.tv/The_Happy_Hob|https://www.twitch.tv/popout/The_Happy_Hob/chat?popout=
Tsoding|https://twitch.tv/Tsoding|https://www.twitch.tv/popout/Tsoding/chat?popout=
Vswed|https://twitch.tv/Vswed|https://www.twitch.tv/popout/Vswed/chat?popout=
Wirtual|https://twitch.tv/Wirtual|https://www.twitch.tv/popout/Wirtual/chat?popout=
YoJosherino|https://twitch.tv/YoJosherino|https://www.twitch.tv/popout/YoJosherino/chat?popout=
ZeroLenny|https://twitch.tv/ZeroLenny|https://www.twitch.tv/popout/ZeroLenny/chat?popout=
Zoodle|https://twitch.tv/Zoodle|https://www.twitch.tv/popout/Zoodle/chat?popout=
adef|https://twitch.tv/adef|https://www.twitch.tv/popout/adef/chat?popout=
catalystz|https://twitch.tv/catalystz|https://www.twitch.tv/popout/catalystz/chat?popout=
dinossindgeil|https://twitch.tv/dinossindgeil|https://www.twitch.tv/popout/dinossindgeil/chat?popout=
heyZeusHeresToast|https://twitch.tv/heyZeusHeresToast|https://www.twitch.tv/popout/heyZeusHeresToast/chat?popout=
ilmango|https://twitch.tv/ilmango|https://www.twitch.tv/popout/ilmango/chat?popout=
iskall85|https://twitch.tv/iskall85|https://www.twitch.tv/popout/iskall85/chat?popout=
itzCBD|https://twitch.tv/itzCBD|https://www.twitch.tv/popout/itzCBD/chat?popout=
lProd_|https://twitch.tv/lProd_|https://www.twitch.tv/popout/lProd_/chat?popout=
randy|https://twitch.tv/randy|https://www.twitch.tv/popout/randy/chat?popout=
shroud|https://twitch.tv/shroud|https://www.twitch.tv/popout/shroud/chat?popout=
skumnut|https://twitch.tv/skumnut|https://www.twitch.tv/popout/skumnut/chat?popout=
star0chris|https://twitch.tv/star0chris|https://www.twitch.tv/popout/star0chris/chat?popout=
teej_dv|https://twitch.tv/teej_dv|https://www.twitch.tv/popout/teej_dv/chat?popout=
zackrawrr|https://twitch.tv/zackrawrr|https://www.twitch.tv/popout/zackrawrr/chat?popout=
EOF
)

selector="fzf"
if [ -n "$1" ]; then
  selector="$1"
fi

if ! command -v "$selector" >/dev/null 2>&1; then
  echo "Error: '$selector' is not installed or not found in PATH. Exiting."
  exit 1
fi

channel=$(echo "$streams" | awk -F'|' '{print $1}' | "$selector")
if [ -z "$channel" ]; then
  echo "No channel selected. Exiting."
  exit 1
fi

stream_url=$(echo "$streams" | grep "^$channel|" | cut -d"|" -f2)
chat_url=$(echo "$streams" | grep "^$channel|" | cut -d"|" -f3)

killall streamlink
brave-browser --app="$chat_url" &&
  streamlink "$stream_url" --default-stream "best,720p,480p,360p" --twitch-disable-ads --player mpv --player-args="--volume=30 --hwdec=vaapi" &
