local apps = require("hyprland.apps")
local workspaces = require("hyprland.workspaces")
local leave_computer = require("scripts.leave-computer").leave_computer
local focus_direction = require("scripts.focus-direction")
local switch_workspace = require("scripts.switch-workspace")
local side_pin = require("scripts.side-pin")

local mod = "SUPER"
local alt = "ALT"

local exec = hl.dsp.exec_cmd

-- bind(keys, desc, action[, opts]): `desc` becomes the bind's `description`, which the Quickshell cheat sheet
-- (launcher section `binds`, SUPER + /) lists. Supported by both the fork and stock Hyprland.
local bind = function(keys, desc, action, opts)
	local key_str
	if type(keys) == "table" then
		key_str = table.concat(keys, " + ")
	else
		key_str = keys
	end
	local o = { description = desc }
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	hl.bind(key_str, action, o)
end

-- pin into the right strip; flush + square while a lone tiled window has no gaps (scripts/side-pin.lua)
bind({ mod, "SHIFT", "P" }, "Pin window into the side strip", side_pin.pin)

-- screen recording (scripts/screenrec.sh, wf-recorder + slurp): one key. While recording it stops;
-- otherwise it opens the Quickshell mode menu (region / window / screen + desktop audio), and if the shell
-- is down it records a region (scripts/screenrec-key.sh)
bind({ "SHIFT", "Print" }, "Screen recording (stop if running)", exec("$HOME/.config/hypr/scripts/screenrec-key.sh"))
-- screenshots (scripts/screenshot.sh, grim + slurp; saved + copied): Print = region shot straight away,
-- CTRL+Print = Quickshell menu region / window / screen (scripts/screenshot-key.sh; region shot if the shell is down)
bind("Print", "Screenshot: region", exec("$HOME/.config/hypr/scripts/screenshot.sh region"))
bind({ "CTRL", "Print" }, "Screenshot menu", exec("$HOME/.config/hypr/scripts/screenshot-key.sh"))
bind({ mod, "slash" }, "Keybind cheat sheet", exec("qs ipc call launcher section binds"))
bind({ mod, "D" }, "Launcher", exec(apps.menu))
bind({ mod, "T" }, "Wallpaper and theme picker", exec("qs ipc call picker toggle")) -- wallpaper + theme picker
bind({ mod, "SHIFT", "V" }, "Clipboard history", exec("qs ipc call launcher query 'v '")) -- clipboard history (launcher, prefilled "v ")
bind({ mod, "Return" }, "Terminal", exec(apps.terminal))
bind({ mod, "B" }, "Browser", exec(apps.browser))
bind({ mod, "E" }, "File manager", exec(apps.filemanager))
bind({ mod, "W" }, "WhatsApp", exec(apps.whatsapp))
bind({ mod, "M" }, "Messages", exec(apps.messages))

bind({ mod, "SHIFT", "Q" }, "Close window", hl.dsp.window.close())
bind({ mod, "SHIFT", "Escape" }, "Leave computer", leave_computer)

bind({ mod, "SHIFT", "L" }, "Lock screen", exec("hyprlock"))

bind({ mod, "F" }, "Toggle fullscreen", hl.dsp.window.fullscreen({ action = "toggle" }))
bind({ mod, "V" }, "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
bind({ mod, "P" }, "Toggle pin", hl.dsp.window.pin({ action = "toggle" }))
bind({ mod, "X" }, "Toggle split direction", hl.dsp.layout("togglesplit"))

bind({ mod, "G" }, "Toggle group", hl.dsp.group.toggle())
bind({ mod, "TAB" }, "Next window in group", hl.dsp.group.next())

-- Scratchpad terminal: a ghostty with its own class (GTK app ids need a dot, a plain "scratchpad" is ignored; kitty's old "scratchpad" class is still matched) on the special workspace "scratchpad" (rules.lua floats and
-- sizes it, and sends it there). Started on demand: the first press (or the first after it was closed) spawns it
-- and its workspace rule shows it; later presses toggle the special workspace.
local function toggle_scratchpad()
	for _, w in ipairs(hl.get_windows()) do
		if w.class == "dotfiles.scratchpad" or w.class == "scratchpad" then
			hl.dispatch(hl.dsp.workspace.toggle_special("scratchpad"))
			return
		end
	end
	hl.dispatch(exec(apps.terminal .. " --class=dotfiles.scratchpad"))
end
bind({ mod, "R" }, "Scratchpad terminal", toggle_scratchpad)

bind({ mod, "SHIFT", "E" }, "Power menu", exec("qs ipc call launcher section power"))
bind({ mod, "SHIFT", "S" }, "Sound output", exec("qs ipc call launcher section sound-output"))
bind({ mod, "SHIFT", "M" }, "Sound input", exec("qs ipc call launcher section sound-input"))
bind({ mod, "SHIFT", "T" }, "Twitch", exec("qs ipc call launcher section twitch"))
bind({ mod, "SHIFT", "J" }, "Jellyfin", exec("qs ipc call launcher section jellyfin"))
bind({ mod, "SHIFT", "N" }, "Replay notifications", exec("qs ipc call notif replay"))

local directions = {
	h = "left",
	j = "down",
	k = "up",
	l = "right",
}

for key, dir in pairs(directions) do
	bind({ mod, key }, "Focus " .. dir, function()
		focus_direction(dir)
	end)
	bind({ mod, alt, key }, "Move window " .. dir, hl.dsp.window.move({ direction = dir, group_aware = true }))
end

local res_step = 20
local resize_map = {
	h = { -res_step, 0 },
	j = { 0, res_step },
	k = { 0, -res_step },
	l = { res_step, 0 },
}

for key, coords in pairs(resize_map) do
	bind(
		{ mod, alt, "SHIFT", key },
		"Resize window " .. directions[key],
		hl.dsp.window.resize({ x = coords[1], y = coords[2], relative = true }),
		{ repeating = true }
	)
end

for _, ws in ipairs(workspaces.workspaces) do
	local ws_num = tonumber(ws.id) or ws.id
	bind({ alt, ws.key }, "Switch to workspace " .. ws.id, function()
		switch_workspace(ws_num)
	end)
	bind({ mod, alt, ws.key }, "Move window to workspace " .. ws.id, hl.dsp.window.move({ workspace = ws_num }))
end

bind({ mod, "mouse:272" }, "Drag window", hl.dsp.window.drag(), { mouse = true })
bind({ mod, "mouse:273" }, "Resize window with the mouse", hl.dsp.window.resize(), { mouse = true })

local media_controls = {
	{ "XF86AudioRaiseVolume", "Volume up", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 1%+", { locked = true } },
	{ "XF86AudioLowerVolume", "Volume down", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-", { locked = true } },
	{ "XF86AudioMute", "Mute output", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", { locked = true, repeating = true } },
	{ "XF86AudioMicMute", "Mute microphone", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", { locked = true, repeating = true } },

	-- Quickshell's Brightness backend (DDC/CI via ddcutil, or brightnessctl on a laptop panel): focused monitor, shows the OSD
	{ "XF86MonBrightnessUp", "Brightness up", "qs ipc call brightness step 5", { locked = true, repeating = true } },
	{ "XF86MonBrightnessDown", "Brightness down", "qs ipc call brightness step -5", { locked = true, repeating = true } },

	{ "XF86AudioNext", "Next track", "playerctl next", { locked = true } },
	{ "XF86AudioPrev", "Previous track", "playerctl previous", { locked = true } },
	{ "XF86AudioPause", "Play / pause", "playerctl play-pause", { locked = true } },
	{ "XF86AudioPlay", "Play / pause", "playerctl play-pause", { locked = true } },
}

for _, control in ipairs(media_controls) do
	local key, desc, cmd, opts = control[1], control[2], control[3], control[4]
	bind(key, desc, exec(cmd), opts)
end

-- Esc closes an open Quickshell bar popup. The popup surface has no keyboard focus right after opening (it can't
-- take Exclusive without breaking click-away / one-click chip switching), so catch Esc here. non_consuming: the
-- focused window still gets the key. The Lua check keeps it to a no-op unless a popup layer is mapped (qs-toast is the
-- notification stack, which is also the notification center: Popups.esc does nothing while no popup is open).
bind("Escape", "Close the open bar popup", function()
	if #hl.get_layers({ namespace = "qs-popup" }) > 0 or #hl.get_layers({ namespace = "qs-toast" }) > 0 then
		hl.exec_cmd("qs ipc call popup esc")
	end
end, { non_consuming = true })
