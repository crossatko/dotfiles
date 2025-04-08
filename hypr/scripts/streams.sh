#!/bin/bash

streams=$(
  cat <<'EOF'
Ainrun|https://player.twitch.tv?channel=Ainrun&parent=twitch.tv|https://www.twitch.tv/popout/Ainrun/chat?popout=
AntiElitz|https://player.twitch.tv?channel=AntiElitz&parent=twitch.tv|https://www.twitch.tv/popout/AntiElitz/chat?popout=
Asmongold|https://player.twitch.tv?channel=Asmongold&parent=twitch.tv|https://www.twitch.tv/popout/Asmongold/chat?popout=
Baalorlord|https://player.twitch.tv?channel=Baalorlord&parent=twitch.tv|https://www.twitch.tv/popout/Baalorlord/chat?popout=
Bruno_Simon_Dev|https://player.twitch.tv?channel=Bruno_Simon_Dev&parent=twitch.tv|https://www.twitch.tv/popout/Bruno_Simon_Dev/chat?popout=
Captain_Domo|https://player.twitch.tv?channel=Captain_Domo&parent=twitch.tv|https://www.twitch.tv/popout/Captain_Domo/chat?popout=
ChaseTheBroYT|https://player.twitch.tv?channel=ChaseTheBroYT&parent=twitch.tv|https://www.twitch.tv/popout/ChaseTheBroYT/chat?popout=
ChrisTitusTech|https://player.twitch.tv?channel=ChrisTitusTech&parent=twitch.tv|https://www.twitch.tv/popout/ChrisTitusTech/chat?popout=
CodingGarden|https://player.twitch.tv?channel=CodingGarden&parent=twitch.tv|https://www.twitch.tv/popout/CodingGarden/chat?popout=
CohhCarnage|https://player.twitch.tv?channel=CohhCarnage&parent=twitch.tv|https://www.twitch.tv/popout/CohhCarnage/chat?popout=
DDRJake|https://player.twitch.tv?channel=DDRJake&parent=twitch.tv|https://www.twitch.tv/popout/DDRJake/chat?popout=
DaniMilkman|https://player.twitch.tv?channel=DaniMilkman&parent=twitch.tv|https://www.twitch.tv/popout/DaniMilkman/chat?popout=
Distortion2|https://player.twitch.tv?channel=Distortion2&parent=twitch.tv|https://www.twitch.tv/popout/Distortion2/chat?popout=
DougDoug|https://player.twitch.tv?channel=DougDoug&parent=twitch.tv|https://www.twitch.tv/popout/DougDoug/chat?popout=
ESAMarathon|https://player.twitch.tv?channel=ESAMarathon&parent=twitch.tv|https://www.twitch.tv/popout/ESAMarathon/chat?popout=
Elajjaz|https://player.twitch.tv?channel=Elajjaz&parent=twitch.tv|https://www.twitch.tv/popout/Elajjaz/chat?popout=
FanHOTS|https://player.twitch.tv?channel=FanHOTS&parent=twitch.tv|https://www.twitch.tv/popout/FanHOTS/chat?popout=
GamesDoneQuick|https://player.twitch.tv?channel=GamesDoneQuick&parent=twitch.tv|https://www.twitch.tv/popout/GamesDoneQuick/chat?popout=
GinoMachino|https://player.twitch.tv?channel=GinoMachino&parent=twitch.tv|https://www.twitch.tv/popout/GinoMachino/chat?popout=
Grubby|https://player.twitch.tv?channel=Grubby&parent=twitch.tv|https://www.twitch.tv/popout/Grubby/chat?popout=
Iron_Pineapple|https://player.twitch.tv?channel=Iron_Pineapple&parent=twitch.tv|https://www.twitch.tv/popout/Iron_Pineapple/chat?popout=
Kitboga|https://player.twitch.tv?channel=Kitboga&parent=twitch.tv|https://www.twitch.tv/popout/Kitboga/chat?popout=
Laeppa|https://player.twitch.tv?channel=Laeppa&parent=twitch.tv|https://www.twitch.tv/popout/Laeppa/chat?popout=
LieutenantEddy|https://player.twitch.tv?channel=LieutenantEddy&parent=twitch.tv|https://www.twitch.tv/popout/LieutenantEddy/chat?popout=
LilAggy|https://player.twitch.tv?channel=LilAggy&parent=twitch.tv|https://www.twitch.tv/popout/LilAggy/chat?popout=
LobosJr|https://player.twitch.tv?channel=LobosJr&parent=twitch.tv|https://www.twitch.tv/popout/LobosJr/chat?popout=
LokiTheFallen|https://player.twitch.tv?channel=LokiTheFallen&parent=twitch.tv|https://www.twitch.tv/popout/LokiTheFallen/chat?popout=
Maarionete|https://player.twitch.tv?channel=Maarionete&parent=twitch.tv|https://www.twitch.tv/popout/Maarionete/chat?popout=
Melkey|https://player.twitch.tv?channel=Melkey&parent=twitch.tv|https://www.twitch.tv/popout/Melkey/chat?popout=
Mikehendi|https://player.twitch.tv?channel=Mikehendi&parent=twitch.tv|https://www.twitch.tv/popout/Mikehendi/chat?popout=
Mitchriz|https://player.twitch.tv?channel=Mitchriz&parent=twitch.tv|https://www.twitch.tv/popout/Mitchriz/chat?popout=
Nefrums|https://player.twitch.tv?channel=Nefrums&parent=twitch.tv|https://www.twitch.tv/popout/Nefrums/chat?popout=
Nemz38|https://player.twitch.tv?channel=Nemz38&parent=twitch.tv|https://www.twitch.tv/popout/Nemz38/chat?popout=
NikNocturnal|https://player.twitch.tv?channel=NikNocturnal&parent=twitch.tv|https://www.twitch.tv/popout/NikNocturnal/chat?popout=
Nilaus|https://player.twitch.tv?channel=Nilaus&parent=twitch.tv|https://www.twitch.tv/popout/Nilaus/chat?popout=
NuclearPastaTom|https://player.twitch.tv?channel=NuclearPastaTom&parent=twitch.tv|https://www.twitch.tv/popout/NuclearPastaTom/chat?popout=
Peeve|https://player.twitch.tv?channel=Peeve&parent=twitch.tv|https://www.twitch.tv/popout/Peeve/chat?popout=
Pixlriffs|https://player.twitch.tv?channel=Pixlriffs&parent=twitch.tv|https://www.twitch.tv/popout/Pixlriffs/chat?popout=
Seki|https://player.twitch.tv?channel=Seki&parent=twitch.tv|https://www.twitch.tv/popout/Seki/chat?popout=
Shamona1|https://player.twitch.tv?channel=Shamona1&parent=twitch.tv|https://www.twitch.tv/popout/Shamona1/chat?popout=
Squillakilla|https://player.twitch.tv?channel=Squillakilla&parent=twitch.tv|https://www.twitch.tv/popout/Squillakilla/chat?popout=
StaydMcMuffin|https://player.twitch.tv?channel=StaydMcMuffin&parent=twitch.tv|https://www.twitch.tv/popout/StaydMcMuffin/chat?popout=
TheDementedSalad|https://player.twitch.tv?channel=TheDementedSalad&parent=twitch.tv|https://www.twitch.tv/popout/TheDementedSalad/chat?popout=
ThePrimeagen|https://player.twitch.tv?channel=ThePrimeagen&parent=twitch.tv|https://www.twitch.tv/popout/ThePrimeagen/chat?popout=
The_Happy_Hob|https://player.twitch.tv?channel=The_Happy_Hob&parent=twitch.tv|https://www.twitch.tv/popout/The_Happy_Hob/chat?popout=
Tsoding|https://player.twitch.tv?channel=Tsoding&parent=twitch.tv|https://www.twitch.tv/popout/Tsoding/chat?popout=
Vswed|https://player.twitch.tv?channel=Vswed&parent=twitch.tv|https://www.twitch.tv/popout/Vswed/chat?popout=
Wirtual|https://player.twitch.tv?channel=Wirtual&parent=twitch.tv|https://www.twitch.tv/popout/Wirtual/chat?popout=
YoJosherino|https://player.twitch.tv?channel=YoJosherino&parent=twitch.tv|https://www.twitch.tv/popout/YoJosherino/chat?popout=
ZeroLenny|https://player.twitch.tv?channel=ZeroLenny&parent=twitch.tv|https://www.twitch.tv/popout/ZeroLenny/chat?popout=
Zoodle|https://player.twitch.tv?channel=Zoodle&parent=twitch.tv|https://www.twitch.tv/popout/Zoodle/chat?popout=
adef|https://player.twitch.tv?channel=adef&parent=twitch.tv|https://www.twitch.tv/popout/adef/chat?popout=
catalystz|https://player.twitch.tv?channel=catalystz&parent=twitch.tv|https://www.twitch.tv/popout/catalystz/chat?popout=
dinossindgeil|https://player.twitch.tv?channel=dinossindgeil&parent=twitch.tv|https://www.twitch.tv/popout/dinossindgeil/chat?popout=
heyZeusHeresToast|https://player.twitch.tv?channel=heyZeusHeresToast&parent=twitch.tv|https://www.twitch.tv/popout/heyZeusHeresToast/chat?popout=
ilmango|https://player.twitch.tv?channel=ilmango&parent=twitch.tv|https://www.twitch.tv/popout/ilmango/chat?popout=
iskall85|https://player.twitch.tv?channel=iskall85&parent=twitch.tv|https://www.twitch.tv/popout/iskall85/chat?popout=
itzCBD|https://player.twitch.tv?channel=itzCBD&parent=twitch.tv|https://www.twitch.tv/popout/itzCBD/chat?popout=
lProd_|https://player.twitch.tv?channel=lProd_&parent=twitch.tv|https://www.twitch.tv/popout/lProd_/chat?popout=
randy|https://player.twitch.tv?channel=randy&parent=twitch.tv|https://www.twitch.tv/popout/randy/chat?popout=
shroud|https://player.twitch.tv?channel=shroud&parent=twitch.tv|https://www.twitch.tv/popout/shroud/chat?popout=
skumnut|https://player.twitch.tv?channel=skumnut&parent=twitch.tv|https://www.twitch.tv/popout/skumnut/chat?popout=
star0chris|https://player.twitch.tv?channel=star0chris&parent=twitch.tv|https://www.twitch.tv/popout/star0chris/chat?popout=
teej_dv|https://player.twitch.tv?channel=teej_dv&parent=twitch.tv|https://www.twitch.tv/popout/teej_dv/chat?popout=
zackrawrr|https://player.twitch.tv?channel=zackrawrr&parent=twitch.tv|https://www.twitch.tv/popout/zackrawrr/chat?popout=
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
brave --app="$chat_url" && brave --app="$stream_url"
# --default-stream "best,720p,480p,360p" --twitch-disable-ads --player mpv --player-args="--volume=30" &
