local monitors = require("hyprland.monitors")

local TV_OUTPUT = monitors.tv.output
local FALLBACK_OUTPUT = monitors.primary.output
local MEDIA_WORKSPACES = { "9", "10", "11", "12" }
local MEDIA_WORKSPACE_SET = { ["9"] = true, ["10"] = true, ["11"] = true, ["12"] = true }

-- Matched by EDID monitor name (via ALSA ELD), not a fragile "HDMI N" port
-- number: this GPU's audio codec exposes 4 pins for its DP/HDMI outputs,
-- and only one can be the card's active profile at a time, but WHICH pin
-- the TV lands on isn't stable -- it silently changed from "HDMI 4" to
-- "HDMI 3" the last time the TV moved to a different physical GPU port,
-- and the hardcoded match string went stale (audio just stopped switching,
-- with no visible error).
local TV_AUDIO_MODEL = "Beyond TV"
local TV_AUDIO_CARD = "alsa_card.pci-0000_03_00.1"
local TV_AUDIO_PCI = TV_AUDIO_CARD:match("pci%-(.+)"):gsub("_", ":")

local audioOutputBeforeTV = ""
local tvConnected = false

local function cmd_output(cmd)
	local handle = io.popen(cmd)
	if handle == nil then
		return ""
	end
	local result = handle:read("*a") or ""
	handle:close()
	return result:gsub("%s+", "")
end

local function get_default_sink_id()
	return cmd_output("wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep '\\*' | grep -oE '[0-9]+' | head -n 1")
end

local function get_tv_sink_id()
	local profile =
		cmd_output("bash ~/.config/hypr/scripts/tv-audio-profile.sh '" .. TV_AUDIO_MODEL .. "' '" .. TV_AUDIO_PCI .. "'")
	if profile == "" then
		return ""
	end

	-- Only one of the card's 4 audio pins can be active at once -- switching
	-- to the TV's profile (a no-op if already active) is what actually makes
	-- its sink exist/appear at all, not just a naming lookup.
	os.execute("pactl set-card-profile " .. TV_AUDIO_CARD .. " " .. profile .. " >/dev/null 2>&1")
	os.execute("sleep 0.3")
	return cmd_output("wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep 'Navi 48.*HDMI' | grep -oE '[0-9]+' | head -n 1")
end

local function move_workspace_to_output(workspace, output)
	hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor " .. workspace .. " " .. output)
end

local function apply_media_workspace_rules(output)
	for _, ws in ipairs(MEDIA_WORKSPACES) do
		hl.workspace_rule({ workspace = ws, monitor = output })
	end
end

local function move_media_workspaces(output)
	for _, ws in ipairs(MEDIA_WORKSPACES) do
		move_workspace_to_output(ws, output)
	end
end

local function normalize_tv_workspace()
	local tv_monitor = hl.get_monitor(TV_OUTPUT)
	if tv_monitor == nil or tv_monitor.active_workspace == nil then
		return
	end

	local active_ws = tostring(tv_monitor.active_workspace.id or "")
	if active_ws ~= "" and not MEDIA_WORKSPACE_SET[active_ws] then
		move_workspace_to_output(active_ws, FALLBACK_OUTPUT)
	end
end

local function enable_tv_audio()
	local current_default = get_default_sink_id()
	local tv_id = get_tv_sink_id()

	if tv_id == "" then
		return
	end

	if current_default ~= "" and current_default ~= tv_id then
		audioOutputBeforeTV = current_default
	end

	if current_default ~= tv_id then
		os.execute("wpctl set-default " .. tv_id)
	end
end

local function restore_audio_before_tv()
	if audioOutputBeforeTV == "" then
		return
	end

	local current_default = get_default_sink_id()
	if current_default ~= audioOutputBeforeTV then
		os.execute("wpctl set-default " .. audioOutputBeforeTV)
	end
	audioOutputBeforeTV = ""
end

local function handle_tv_connected(notify)
	apply_media_workspace_rules(TV_OUTPUT)
	normalize_tv_workspace()
	move_media_workspaces(TV_OUTPUT)
	enable_tv_audio()
	if notify ~= false then
		hl.notification.create({ text = "TV connected", timeout = 3000 })
	end
end

local function handle_tv_disconnected(notify)
	apply_media_workspace_rules(FALLBACK_OUTPUT)
	move_media_workspaces(FALLBACK_OUTPUT)
	restore_audio_before_tv()
	if notify ~= false then
		hl.notification.create({ text = "TV disconnected", timeout = 3000 })
	end
end

local function reconcile_tv_state(notify)
	local connected_now = hl.get_monitor(TV_OUTPUT) ~= nil
	if connected_now and not tvConnected then
		tvConnected = true
		handle_tv_connected(notify)
	elseif not connected_now and tvConnected then
		tvConnected = false
		handle_tv_disconnected(notify)
	end
end

hl.on("hyprland.start", function()
	tvConnected = hl.get_monitor(TV_OUTPUT) ~= nil
	if tvConnected then
		handle_tv_connected(false)
	else
		handle_tv_disconnected(false)
	end
end)

hl.on("monitor.added", function()
	reconcile_tv_state(true)
end)

hl.on("monitor.removed", function()
	reconcile_tv_state(true)
end)

hl.on("monitor.layout_changed", function()
	reconcile_tv_state(false)
end)

hl.timer(function()
	reconcile_tv_state(false)
end, { timeout = 3000, type = "repeat" })
