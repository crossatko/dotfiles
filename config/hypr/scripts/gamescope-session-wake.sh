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

# Runs in the background: tv-input.sh's own internal retry loop can take up
# to ~130s in the worst case (TV genuinely slow to wake), and that must not
# delay the VT bounce below -- the whole point of this script is to get
# gamescope's own picture visible quickly, independent of how long the TV
# itself takes to wake and switch input.
(
	~/.config/hypr/scripts/tv-wake-and-resync.sh
	~/.config/hypr/scripts/tv-input.sh hdmi2
) &

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
# frame to actually display -- confirmed live tonight that gamescope-
# session's own picture doesn't show up until *something* forces a VT
# refresh, both via SDDM autologin and a raw manual TTY launch. The short
# sleep gives gamescope a moment to finish its own initial setup first.
sleep 2
sudo -n chvt 6
sleep 1
sudo -n chvt 1
