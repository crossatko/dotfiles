local apps = require("hyprland.apps")
local workspaces = require("hyprland.workspaces")
local leave_computer = require("scripts.leave-computer").leave_computer
local show_power_menu = require("scripts.power-menu").show_power_menu
local show_sound_output_menu = require("scripts.sound-output-menu").show_sound_output_menu
local focus_direction = require("scripts.focus-direction")
local switch_workspace = require("scripts.switch-workspace")

local mod = "SUPER"
local alt = "ALT"

local exec = hl.dsp.exec_cmd

local bind = function(keys, action, opts)
	local key_str
	if type(keys) == "table" then
		key_str = table.concat(keys, " + ")
	else
		key_str = keys
	end
	hl.bind(key_str, action, opts)
end

local myPin = function()
	hl.dispatch(hl.dsp.window.float({ action = true }))
	hl.dispatch(hl.dsp.window.pin({ action = true }))
	hl.dispatch(hl.dsp.window.resize({ x = 866, y = 1416 }))
	hl.dispatch(hl.dsp.window.move({ x = 2560, y = 12 }))
end

bind({ mod, "SHIFT", "P" }, myPin)

bind("Print", exec(apps.screenshot))
bind({ mod, "D" }, exec(apps.menu))
-- bind({ mod, "SHIFT", "V" }, exec("cliphist list | tofi | cliphist decode | wl-copy"))
bind({ mod, "Return" }, exec(apps.terminal))
bind({ mod, "B" }, exec(apps.browser))
bind({ mod, "E" }, exec(apps.filemanager))
bind({ mod, "W" }, exec(apps.whatsapp))
bind({ mod, "M" }, exec(apps.messages))

bind({ mod, "SHIFT", "Q" }, hl.dsp.window.close())
bind({ mod, "SHIFT", "Escape" }, leave_computer)

bind({ mod, "SHIFT", "L" }, exec("hyprlock"))

bind({ mod, "F" }, hl.dsp.window.fullscreen({ action = "toggle" }))
bind({ mod, "V" }, hl.dsp.window.float({ action = "toggle" }))
bind({ mod, "P" }, hl.dsp.window.pin({ action = "toggle" }))
bind({ mod, "X" }, hl.dsp.layout("togglesplit"))

bind({ mod, "G" }, hl.dsp.group.toggle())
bind({ mod, "TAB" }, hl.dsp.group.next())

bind({ mod, "SHIFT", "E" }, show_power_menu)
bind({ mod, "SHIFT", "S" }, show_sound_output_menu)

local directions = {
	h = "left",
	j = "down",
	k = "up",
	l = "right",
}

for key, dir in pairs(directions) do
	bind({ mod, key }, function()
		focus_direction(dir)
	end)
	bind({ mod, alt, key }, hl.dsp.window.move({ direction = dir, group_aware = true }))
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
		hl.dsp.window.resize({ x = coords[1], y = coords[2], relative = true }),
		{ repeating = true }
	)
end

for _, ws in ipairs(workspaces.workspaces) do
	local ws_num = tonumber(ws.id) or ws.id
	bind({ alt, ws.key }, function()
		switch_workspace(ws_num)
	end)
	bind({ mod, alt, ws.key }, hl.dsp.window.move({ workspace = ws_num }))
end

bind({ mod, "mouse:272" }, hl.dsp.window.drag(), { mouse = true })
bind({ mod, "mouse:273" }, hl.dsp.window.resize(), { mouse = true })

local media_controls = {
	{ "XF86AudioRaiseVolume", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 1%+", { locked = true } },
	{ "XF86AudioLowerVolume", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-", { locked = true } },
	{ "XF86AudioMute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", { locked = true, repeating = true } },
	{ "XF86AudioMicMute", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", { locked = true, repeating = true } },

	{ "XF86MonBrightnessUp", "brightnessctl -e4 -n2 set 5%+", { locked = true, repeating = true } },
	{ "XF86MonBrightnessDown", "brightnessctl -e4 -n2 set 5%-", { locked = true, repeating = true } },

	{ "XF86AudioNext", "playerctl next", { locked = true } },
	{ "XF86AudioPrev", "playerctl previous", { locked = true } },
	{ "XF86AudioPause", "playerctl play-pause", { locked = true } },
	{ "XF86AudioPlay", "playerctl play-pause", { locked = true } },
}

for _, control in ipairs(media_controls) do
	local key, cmd, opts = control[1], control[2], control[3]
	bind(key, exec(cmd), opts)
end
