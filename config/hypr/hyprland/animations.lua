-- Hand-written animation curves and leaves (moved out of settings.lua so managed.lua can read them).
-- Edit the values here as usual. Settings > Animations (Quickshell, animations.json) only scales / swaps
-- them at runtime in managed.lua (M.apply_anim); with no animations.json nothing here is changed.
--
-- Current Hyprland (0.55+) animation syntax (wiki/default style)
local A = {}

-- What "1x" means, for Hyprland AND Quickshell (Motion.qml baseMs, same value): every animation below runs
-- BASE_MS at 1x. Hyprland's `speed` is in deciseconds (measured: speed 3 + linear = 300 ms), so speed = BASE_MS / 100.
-- Until 2026-10-20 every leaf was speed 0.5 (50 ms); unified with the 200 ms popups on user request.
A.BASE_MS = 200
local SPEED = A.BASE_MS / 100

A.curves = {
	{ "easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } } },
	{ "linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } } },
	{ "almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } } },
	{ "quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } } },
	{ "easy", { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 } },
}

-- order matters: a parent leaf first, then its children (a parent resets children that were not set)
A.leaves = {
	{ leaf = "global", enabled = true, speed = SPEED, bezier = "default" },
	{ leaf = "border", enabled = true, speed = SPEED, bezier = "easeOutQuint" },
	{ leaf = "windows", enabled = true, speed = SPEED, bezier = "quick" },
	{ leaf = "windowsMove", enabled = true, speed = SPEED, bezier = "quick" },
	{ leaf = "windowsIn", enabled = true, speed = SPEED, bezier = "quick", style = "popin 87%" },
	{ leaf = "windowsOut", enabled = true, speed = SPEED, bezier = "linear", style = "popin 87%" },
	{ leaf = "fadeIn", enabled = true, speed = SPEED, bezier = "almostLinear" },
	{ leaf = "fadeOut", enabled = true, speed = SPEED, bezier = "almostLinear" },
	{ leaf = "fade", enabled = true, speed = SPEED, bezier = "quick" },
	{ leaf = "layers", enabled = true, speed = SPEED, bezier = "easeOutQuint" },
	{ leaf = "layersIn", enabled = true, speed = SPEED, bezier = "easeOutQuint", style = "fade" },
	{ leaf = "layersOut", enabled = true, speed = SPEED, bezier = "linear", style = "fade" },
	{ leaf = "fadeLayersIn", enabled = true, speed = SPEED, bezier = "almostLinear" },
	{ leaf = "fadeLayersOut", enabled = true, speed = SPEED, bezier = "almostLinear" },
	{ leaf = "workspaces", enabled = true, speed = SPEED, bezier = "almostLinear", style = "slidefade 5%" },
	{ leaf = "workspacesIn", enabled = true, speed = SPEED, bezier = "almostLinear", style = "slidefade 5%" },
	{ leaf = "workspacesOut", enabled = true, speed = SPEED, bezier = "almostLinear", style = "slidefade 5%" },
	{ leaf = "specialWorkspace", enabled = true, speed = SPEED, bezier = "quick", style = "fade" }, -- scratchpad (SUPER+R)
	{ leaf = "zoomFactor", enabled = true, speed = SPEED, bezier = "quick" },
}

for _, c in ipairs(A.curves) do
	hl.curve(c[1], c[2])
end
for _, a in ipairs(A.leaves) do
	hl.animation(a)
end

return A
