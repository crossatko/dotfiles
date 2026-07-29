#!/bin/bash
# Fires automatically whenever a rootful gamescope-session starts (see the
# companion systemd unit, gamescope-session-wake.service) -- deliberately
# independent of Hyprland: Hyprland isn't running at all during a
# gamescope-session (that's the whole point of it being rootful, its own
# separate compositor), so none of steam-tv-dim.lua's Big-Picture-triggered
# TV automation applies here at all. Reuses the same underlying scripts
# instead of duplicating their retry/locking logic -- both are already
# fully Hyprland-independent (plain adb/flock/sleep, no hyprctl calls).

# Same TV audio identity tv.lua's get_tv_sink_id()/enable_tv_audio() use --
# keep these two in sync with TV_AUDIO_MODEL/TV_AUDIO_CARD there if the TV
# ever moves to a different GPU audio port again.
TV_AUDIO_MODEL="Beyond TV"
TV_AUDIO_CARD="alsa_card.pci-0000_03_00.1"
TV_AUDIO_PCI="0000:03:00.1"

# Both backgrounded, and crucially *in parallel* rather than chained. These
# used to run in sequence inside one subshell -- wake-and-resync, THEN the
# input switch -- which meant the input switch could not begin until the WoL
# loop had finished, i.e. never sooner than ~10s into the session, since that
# loop always ran its full ten iterations regardless of whether the TV was
# already awake. The visible result was the TV lighting up almost instantly and
# then sitting on the wrong input until well after Steam's intro movie had
# played and the VT bounce below had come and gone.
#
# Nothing about them is actually ordered: WoL is fire-and-forget UDP that the
# TV either needs or ignores, and tv-input.sh polls for the TV's input
# framework becoming ready on its own (and takes a flock, so overlapping
# callers serialise rather than race -- see its header for the failure that
# lock exists to prevent). Backgrounded so neither can delay the VT bounce
# below: tv-input.sh's retry budget runs to ~150s in the worst case, and the
# whole point of this script is to get gamescope's picture up promptly no
# matter how long the TV itself takes.
~/.config/hypr/scripts/tv-wake-and-resync.sh &
~/.config/hypr/scripts/tv-input.sh hdmi2 &

# Independent of the above: routing audio to the TV doesn't need it to
# actually be powered on -- the GPU's HDMI audio codec exposes ELD (and
# therefore its EDID monitor_name) as soon as the cable's hotplug-detect is
# asserted, which for this TV stays asserted even while it's off (the
# original quirk that started all the TV automation this session). So this
# can run right away rather than waiting on tv-wake-and-resync.sh.
(
	profile="$(~/.config/hypr/scripts/tv-audio-profile.sh "$TV_AUDIO_MODEL" "$TV_AUDIO_PCI")"
	if [ -n "$profile" ]; then
		pactl set-card-profile "$TV_AUDIO_CARD" "$profile" >/dev/null 2>&1
		sleep 0.3
		sink_id="$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep 'Navi 48.*HDMI' | grep -oE '[0-9]+' | head -n 1)"
		[ -n "$sink_id" ] && wpctl set-default "$sink_id"
	fi
) &

# Bounce a scratch VT (6, definitely unused) to force gamescope's first
# frame to actually display -- confirmed live that gamescope-session's own
# picture doesn't show up until *something* forces a VT refresh, both via SDDM
# autologin and a raw manual TTY launch.
#
# Waits on gamescope actually being up rather than guessing with a fixed
# `sleep 2`. The marker file this unit is conditioned on only proves the
# session launcher got as far as reading gamescope's ready-pipe; its X server
# answering a request is the first point at which there is genuinely something
# to bounce into view. Typically satisfied far sooner than 2s, and unlike a
# fixed sleep it still waits when the machine is having a slow start.
GS_ENV="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamescope-environment"
GS_DISPLAY="$(grep -m1 '^DISPLAY=' "$GS_ENV" 2>/dev/null | cut -d= -f2- | tr -d \"\')"
for _ in $(seq 1 100); do
	DISPLAY="${GS_DISPLAY:-:0}" timeout 1 xprop -root >/dev/null 2>&1 && break
	sleep 0.1
done

# No sleep between the two: chvt blocks on VT_WAITACTIVE, i.e. it has already
# waited for the VT to actually become active before it returns. (If a session
# ever comes up to a black screen again, re-adding a short settle here is the
# first thing to try -- this is the only place that timing was removed.)
sudo -n chvt 6
sudo -n chvt 1
