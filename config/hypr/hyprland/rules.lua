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
	-- Pinned video windows fill the free strip right of the tiled area (workspaces.lua reserves 1588px
	-- there) at 16:9 (1588x893), sitting right on top of the 40px bar: y = monitor_h - 40 - 893.
	hl.window_rule({
		name = "cb-pip",
		float = true,
		pin = true,
		opaque = true,
		no_dim = true,
		-- workspace = "7 silent",
		monitor = monitor2.output,
		move = "(monitor_w-1588) (monitor_h-933)",
		size = "1588 893",
		match = { initial_title = "Picture in picture" },
	})

	hl.window_rule({
		name = "cb-mpv",
		float = true,
		pin = true,
		no_dim = true,
		monitor = monitor2.output,
		move = "(monitor_w-1588) (monitor_h-933)",
		size = "1588 893",
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

-- Twitch player (~/code/crossatko/twitch-qs-mpv): a Quickshell FloatingWindow, so the class is
-- always org.quickshell. Matched on class ONLY: the title ("Twitch - <channel>") is not yet set when
-- Hyprland evaluates window rules for a Quickshell window, so title/initial_title matches never fire.
-- (Any other Quickshell FloatingWindow would get this rule too, except the shell's own modal windows below: their
-- titles are "qs-<kind>", which the negative title match leaves out.)
-- Same treatment as the Picture-in-picture rules above (floating, never dimmed, per-host placement);
-- it keeps the screen awake while focused.
if is_battlestation then
	hl.window_rule({
		name = "twitch-player",
		float = true,
		pin = true,
		opaque = true,
		no_dim = true,
		idle_inhibit = "focus",
		monitor = monitor2.output,
		move = "(monitor_w-1588) (monitor_h-933)",
		size = "1588 893",
		match = { class = "^(org\\.quickshell)$", title = "negative:^qs-.*" },
	})
elseif is_workstation then
	hl.window_rule({
		name = "twitch-player",
		float = true,
		no_initial_focus = true,
		opacity = "1 override 1 override",
		no_dim = true,
		rounding = 0,
		idle_inhibit = "focus",
		match = { class = "^(org\\.quickshell)$", title = "negative:^qs-.*" },
	})
end
-- The shell's own modal windows (Settings.qml: title qs-settings): plain
-- floating cards. The card draws its own border; the window keeps the global rounding (= the Appearance radius, the
-- card's radius too), because the glass of a window is cut to the window's own rounded box, not to the card. Placement (always the centre of the focused monitor at the default size, nothing remembered; double-click on the header resets a dragged window) is
-- scripts/modal-windows.lua; the dragging itself is the normal SUPER+LMB bind.
hl.window_rule({
	name = "qs-modal",
	float = true,
	center = true,
	border_size = 0,
	no_shadow = true,
	no_dim = true,
	match = { class = "^(org\\.quickshell)$", title = "^qs-.*" },
})
-- Fallback when the embedded chat is unavailable: Brave's popout chat (class brave-www.twitch.tv__popout_<channel>_chat-Default)
hl.window_rule({
	name = "twitch-popout-chat",
	float = true,
	no_initial_focus = true,
	no_dim = true,
	size = "420 900",
	move = "(monitor_w-440) 60",
	match = { class = "^(brave-www\\.twitch\\.tv__popout_.*)$" },
})

-- A scratchpad terminal (ghostty --class=dotfiles.scratchpad; SUPER+R only toggles the workspace, it no longer spawns one): floating, centred, 60% of the monitor, on special:scratchpad.
hl.window_rule({
	name = "scratchpad-terminal",
	float = true,
	workspace = "special:scratchpad",
	size = "(monitor_w*0.6) (monitor_h*0.6)",
	center = true,
	match = { class = "^(dotfiles\\.scratchpad|scratchpad)$" },
})

hl.window_rule({
	name = "jellyfin-media-player",
	no_dim = true,
	opaque = true,
	workspace = "12",
	match = { class = "^(org.jellyfin.JellyfinDesktop)$" },
})

-- Figma (figma-linux-next desktop app, or the Brave web app of figma.com) always opens on workspace 2.
hl.window_rule({
	name = "figma-workspace",
	workspace = "2",
	match = { class = "^(figma-linux-next|brave-www\\.figma\\.com__.*)$" },
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
	name = "reaper",
	no_dim = true,
	opacity = "1 override 1 override",
	match = { class = "^(REAPER)$" },
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

-- Vesktop is the default Discord client (class `vesktop`); the official client (class `discord`) keeps the same rules
hl.window_rule({
	name = "discord",
	workspace = "7",
	match = { class = "^(discord|vesktop)$" },
})
hl.window_rule({
	name = "discord-popout-stream",
	no_dim = true,
	match = { class = "^(discord|vesktop)$", initial_title = "^(Discord Popout)$" },
})
hl.window_rule({ name = "geary", workspace = "8", match = { class = "^(org\\.gnome\\.Geary)$" } })
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

-- Quickshell (~/dotfiles/config/quickshell): the bar opts in to the global
-- decoration:blur:* settings (size/passes/vibrancy/variant all apply as-is).
-- ignore_alpha keeps the blur inside the drawn shape: fully transparent pixels
-- (the rounded corners) get no blur, so the blur follows the bar's rounding even
-- though layer surfaces have no rounding of their own. Keep it below
-- bar_opacity in ~/.config/theme/theme.toml.
-- EVERY Quickshell window (namespace qs-*: bar, toasts, popups, OSD, Settings, the launcher, anything
-- new) is blurred (the pattern must match the whole namespace: `qs-.*`, not `^qs-`) wherever it draws something at least 10% opaque; fully transparent pixels get no blur.
hl.layer_rule({ match = { namespace = "qs-.*" }, blur = true })
hl.layer_rule({ match = { namespace = "qs-.*" }, ignore_alpha = 0.1 })
-- Per-surface glass (Settings > Glass > Surfaces, fork builds with per-surface glass only): managed.lua adds named layer
-- rules "qs-glass-<id>" with a `glass` string for qs-bar / qs-popup / qs-launcher / qs-osd / qs-toast (M.SURFACE_LAYERS).
-- Bar popups animate themselves (PopupHost.qml: fade / scale / slide with Settings > Animations speed, curve, style).
-- Hyprland's own layer fade on map / unmap would run on top of it with the HYPRLAND speed and curve; off for them.
-- (The launcher's equivalent is switched with its "Like popups" setting in managed.lua.)
hl.layer_rule({ match = { namespace = "qs-popup" }, no_anim = true })
-- The shell's wallpaper (WallpaperLayer.qml, background layer; it cross-fades a change itself): no layer fade, so a
-- shell restart shows the new surface the frame it maps instead of fading it in from the background colour.
hl.layer_rule({ match = { namespace = "qs-wallpaper" }, no_anim = true })
-- Desktop clock (Quickshell DeskClock.qml, Settings > Desktop clock) sits on the bottom layer, like a video wallpaper's
-- mpvpaper (-l bottom): within a layer a NEGATIVE order is drawn on top (Renderer sorts by order, highest first), so the
-- clock stays above the wallpaper whichever maps last (a wallpaper change restarts mpvpaper). pcall: optional rule key.
pcall(hl.layer_rule, { match = { namespace = "qs-deskclock" }, order = -1 })
-- Fullscreen overlays with a card (Settings, ModalMenu kinds) are transparent around the card, so the 0.1 rule above
-- blurs only the card.
