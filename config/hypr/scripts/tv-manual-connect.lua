local monitors = require("hyprland.monitors")

local TV_OUTPUT = monitors.tv.output

local function is_tv_connected()
	return hl.get_monitor(TV_OUTPUT) ~= nil
end

-- Own copy of steam-tv-dim.lua's is_big_picture_window -- see its comment
-- for why class/title and initial_class/initial_title are both checked
-- independently rather than one preferred over the other (a plain Steam
-- window's current title can go stale at shutdown, but a gamescope-wrapped
-- session is the opposite: it maps as initial_class/initial_title
-- "gamescope" and only gets its real title once Steam starts inside it).
local function is_big_picture_running()
	for _, win in ipairs(hl.get_windows()) do
		local class_a = (win.class or ""):lower()
		local class_b = (win.initial_class or ""):lower()
		local title_a = (win.title or ""):lower()
		local title_b = (win.initial_title or ""):lower()
		local class_ok = class_a:find("steam", 1, true) ~= nil or class_a == "gamescope"
			or class_b:find("steam", 1, true) ~= nil or class_b == "gamescope"
		local title_ok = title_a:find("big picture", 1, true) ~= nil or title_a:find("gamepadui", 1, true) ~= nil
			or title_b:find("big picture", 1, true) ~= nil or title_b:find("gamepadui", 1, true) ~= nil
		if class_ok and title_ok then
			return true
		end
	end
	return false
end

-- Tracks whether the TV's current Hyprland-enabled state was THIS script's
-- doing, not Big Picture's own enable_tv_monitor() (scripts/steam-tv-dim.lua)
-- -- exposed via hypr_tv_is_manual_connect_active() so that script's resync
-- path can tell the difference and avoid fighting a manual connection it
-- doesn't own (see the comment there for the confirmed-live failure mode).
local manual_connect_active = false

function hypr_tv_is_manual_connect_active()
	return manual_connect_active
end

-- Called externally via `hyprctl eval` from scripts/tv-input-poll.sh, which
-- polls the TV's own currently-selected input over ADB -- there's no
-- push-based signal for "the TV was manually pointed at this input" (no CEC
-- on this GPU, and this TV's HDMI hot-plug-detect doesn't reflect input
-- selection either). Deliberately just the raw connect/disconnect, no
-- dimming/workspace/focus side effects (that's scripts/steam-tv-dim.lua's
-- concern for actual Big Picture sessions), and this won't disable out from
-- under an active one.
function hypr_tv_set_manual_connect(connected)
	if connected then
		if not is_tv_connected() then
			local spec = { disabled = false }
			for k, v in pairs(monitors.tv) do
				spec[k] = v
			end
			hl.monitor(spec)
		end
		manual_connect_active = true
	else
		if is_tv_connected() and not is_big_picture_running() then
			hl.monitor({ output = TV_OUTPUT, disabled = true })
		end
		manual_connect_active = false
	end
end
