local host = require("hyprland.host")
local is_battlestation = host.is_battlestation
local is_workstation = host.is_workstation
local monitors = require("hyprland.monitors")

local monitor2 = monitors.secondary

hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

if is_battlestation then
	hl.window_rule({
		name = "cb-pip",
		float = true,
		pin = true,
		opaque = true,
		no_dim = true,
		-- workspace = "7 silent",
		monitor = monitor2.output,
		move = "(monitor_w-1580) (monitor_h-926)",
		size = "1568 882",
		match = { initial_title = "Picture in picture" },
	})

	hl.window_rule({
		name = "cb-mpv",
		float = true,
		pin = true,
		no_dim = true,
		monitor = monitor2.output,
		move = "(monitor_w-1568) (monitor_h-914)",
		size = "1568 882",
		match = { initial_class = "^(mpv)$" },
	})
elseif is_workstation then
	-- Placement (monitor/move/size) is handled dynamically in scripts/pip-orientation.lua
	-- based on the video's aspect ratio. Pinning also happens there, AFTER the
	-- window is moved - pinning it here immediately at open time latches its
	-- monitor/workspace ownership to wherever it originally spawned (often the
	-- wrong monitor), even though its pixels get moved correctly right after.
	hl.window_rule({
		name = "cw-pip",
		float = true,
		no_initial_focus = true,
		opacity = "1 override 1 override",
		no_dim = true,
		rounding = 0,
		group = "barred",
		match = { title = "^(Picture in picture)$" },
	})

	hl.window_rule({
		name = "cw-mpv",
		float = true,
		no_initial_focus = true,
		no_dim = true,
		match = { initial_class = "^(mpv)$" },
	})
end

hl.window_rule({
	name = "jellyfin-media-player",
	no_dim = true,
	opaque = true,
	workspace = "12",
	match = { class = "^(org.jellyfin.JellyfinDesktop)$" },
})

hl.window_rule({
	name = "memento",
	no_dim = true,
	opaque = true,
	monitor = monitor2.output,
	match = { class = "^(memento)$" },
})

hl.window_rule({
	name = "obs",
	no_dim = true,
	opacity = "1 override 1 override",
	match = { class = "obs" },
})

hl.window_rule({
	name = "pinned",
	border_size = 0,
	no_initial_focus = true,
	focus_on_activate = false,
	match = { pin = true },
})

hl.window_rule({
	name = "fullscreen",
	border_size = 0,
	opacity = "1 override 1 override",
	no_dim = true,
	idle_inhibit = "fullscreen",
	match = { fullscreen = true },
})

hl.window_rule({
	name = "steam-input-osk",
	float = true,
	pin = true,
	size = "1280 360",
	move = "((monitor_w-1280)/2) (monitor_h-360)",
	no_dim = true,
	opaque = true,
	match = {
		class = "^steam",
		title = "^(Steam Input On-screen Keyboard)$",
	},
})

hl.window_rule({
	name = "steam",
	workspace = "1",
	match = {
		class = "^steam$",
		title = "^(Steam)$",
	},
})

hl.window_rule({
	name = "steam-activate-follow",
	focus_on_activate = true,
	match = {
		class = "^steam$",
	},
})

if is_battlestation then
	-- Kept on the same workspace as an actual launched game (9), not a
	-- separate one (10) -- controller-only navigation can't switch
	-- workspaces, so Big Picture itself and any game launched from it must
	-- always land in the same place.
	hl.window_rule({
		name = "steam-big-picture-media-workspace",
		workspace = "9",
		float = false,
		fullscreen = true,
		no_dim = true,
		opaque = true,
		focus_on_activate = true,
		match = {
			initial_title = "Steam Big Picture Mode",
		},
	})
end

hl.window_rule({
	name = "steam-game",
	workspace = "9",
	float = false,
	fullscreen = true,
	no_dim = true,
	opaque = true,
	focus_on_activate = true,
	match = { class = "^steam_app_\\d+$" },
})

hl.window_rule({
	name = "hyprland-share-picker",
	float = true,
	pin = true,
	size = "1000 900",
	center = true,
	match = { class = "hyprland-share-picker" },
	focus_on_activate = true,
})

hl.window_rule({
	name = "pavucontrol",
	float = true,
	size = "1000 900",
	center = true,
	match = { class = "^(org.pulseaudio.pavucontrol)$" },
})

hl.window_rule({
	name = "portal-stuff",
	float = true,
	size = "1000 900",
	center = true,
	match = { class = "xdg-desktop-portal-gtk" },
})

hl.window_rule({
	name = "savefile",
	float = true,
	size = "1000 900",
	center = true,
	match = { title = "^(Save File)$" },
})
hl.window_rule({
	name = "openfile",
	float = true,
	size = "1000 900",
	center = true,
	match = { title = "^(Open File)$" },
})
hl.window_rule({
	name = "blueman",
	float = true,
	size = "1000 900",
	center = true,
	match = { class = "^(.blueman-manager-wrapped)$" },
})

hl.window_rule({
	name = "discord",
	workspace = "7",
	match = { class = "discord" },
})
hl.window_rule({ name = "thunderbird", workspace = "8", match = { class = "thunderbird" } })
hl.window_rule({ name = "whatsapp", workspace = "7", match = { class = "^(brave-web\\.whatsapp\\.com__-Default)$" } })
hl.window_rule({ name = "messages", workspace = "7", match = { class = "^(brave-messages\\.google\\.com__-Default)$" } })
hl.window_rule({ name = "signal", workspace = "7", match = { class = "^(org\\.signal\\.Signal)$" } })

hl.window_rule({
	name = "tuifin-mpv",
	workspace = "11",
	float = false,
	fullscreen = true,
	match = { class = "^(tuifin-mpv)$" },
	no_dim = true,
	opaque = true,
})

hl.window_rule({
	name = "jellydeck",
	workspace = "11",
	float = false,
	fullscreen = true,
	match = { title = "JellyDeck" },
	no_dim = true,
	opaque = true,
})

hl.window_rule({
	name = "blender-save-file",
	float = true,
	fullscreen = false,
	size = "1400 1000",
	center = true,
	no_dim = true,
	opaque = true,
	match = {
		class = "^(blender)$",
		initial_title = "^(File Browser)$",
	},
})

hl.layer_rule({ match = { namespace = "waybar" }, blur = true })
hl.layer_rule({ match = { namespace = "launcher" }, blur = true })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, blur = true })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, animation = "slide right" })
hl.layer_rule({ match = { namespace = "swaync-notification-center" }, blur = true })
hl.layer_rule({ match = { namespace = "swaync-notification-center" }, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "swaync-notification-center" }, animation = "slide right" })
