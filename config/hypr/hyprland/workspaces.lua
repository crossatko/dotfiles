local apps = require("hyprland.apps")
local monitors = require("hyprland.monitors")
local host = require("hyprland.host")

local monitor1 = monitors.primary
local monitor2 = monitors.secondary
local tv = monitors.tv

local is_battlestation = host.is_battlestation
local is_workstation = host.is_workstation

local mediaWorkspaceOutput = monitor1.output
if tv ~= nil and tv.output ~= nil and hl.get_monitor(tv.output) ~= nil then
	mediaWorkspaceOutput = tv.output
end

local workspaces = {
	{ id = "1", key = "a", monitor = monitor1.output },
	{ id = "2", key = "s", monitor = monitor1.output },
	{ id = "3", key = "d", monitor = monitor1.output, app = apps.browser, default = true },
	{ id = "4", key = "f", monitor = monitor1.output, app = apps.terminal },

	{ id = "5", key = "q", monitor = monitor2.output },
	{ id = "6", key = "w", monitor = monitor2.output },
	{ id = "7", key = "e", monitor = monitor2.output, app = apps.discord, default = true },
	{ id = "8", key = "r", monitor = monitor2.output, app = apps.mail },

	-- monocle: whatever's focused fills the screen, inherently, unlike a
	-- per-window `fullscreen = true` rule (rules.lua) which only applies
	-- once at match time and doesn't re-assert itself when a sibling
	-- window (e.g. a game) closes -- that's what left Big Picture's own
	-- window windowed instead of fullscreen after quitting a game.
	{
		id = "9",
		key = "z",
		monitor = mediaWorkspaceOutput,
		layout = "monocle",
		no_border = true,
		gaps_in = 0,
		gaps_out = 0,
	},
	{ id = "10", key = "x", monitor = mediaWorkspaceOutput },
	{ id = "11", key = "c", monitor = mediaWorkspaceOutput },
	{ id = "12", key = "v", monitor = mediaWorkspaceOutput },
}

for _, ws in ipairs(workspaces) do
	hl.workspace_rule({
		workspace = ws.id,
		monitor = ws.monitor,
		layout = ws.layout,
		no_border = ws.no_border,
		gaps_in = ws.gaps_in,
		gaps_out = ws.gaps_out,
		on_created_empty = ws.app,
		default = ws.default or false,
		persistent = ws.persistent or false,
	})
end

-- Workspace 9 (monocle): tiled windows are square; floating ones (quickshell cards etc.) keep their
-- rounding. A workspace rule's no_rounding would square the floating ones too.
hl.window_rule({ name = "monocle-square", rounding = 0, match = { float = false, workspace = "9" } })

-- Battlestation: the right strip reserved for the pinned video window is a monitor reserved_area
-- toggled by scripts/pip-reserve.lua (a w[p1-9] workspace rule only matched the workspace that owns the
-- pinned window, so it was missing on the monitor's other workspaces).
-- Both monitors' reservations for pinned PiP/mpv windows are now handled
-- dynamically at runtime via reserved_area (hyprland/monitors.lua), toggled
-- by scripts/pip-orientation.lua - not static per-workspace gaps.

return {
	workspaces = workspaces,
}
