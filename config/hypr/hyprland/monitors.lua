local host = require("hyprland.host")

-- Matched by EDID description, not the DRM connector name (DP-2/DP-3/...) --
-- that name is assigned by enumeration order at boot and isn't tied to a
-- physical port, so the same monitor can land on a different DP-N after a
-- reboot (confirmed: the Dell drifted from DP-3 to DP-5). desc: matching
-- stays stable across that. Get the exact string via `hyprctl monitors -j`.
local monitor1 = {
	output = "desc:Microstep MPG271QX OLED 0x01010101",
	mode = "2560x1440@360",
	position = "0x1440",
	scale = 1.0,
	bitdepth = 10,
	vrr = 2,
	cm = "srgb",
	supports_hdr = 1,
	supports_wide_color = 1,
	sdrbrightness = 1,
	sdrsaturation = 1.0,
	sdr_min_luminance = 0.005,
	sdr_max_luminance = 80,
}

local monitor2 = {
	output = "desc:Dell Inc. DELL U2515H 9X2VY5AK1D5L",
	mode = "2560x1440@60",
	position = "0x0",
	cm = "srgb",
	scale = 1.0,
}

-- cm = "auto": cm = "srgb" + render.cm_auto_hdr (settings.lua), same as
-- monitor1, was tried first, expecting it to engage HDR per-content -- but
-- with AC Shadows running fullscreen and in-game HDR enabled, it stayed
-- SDR on the actual TV. Root cause, confirmed via `hyprctl clients -j`: the
-- game's window had xwayland=true -- Wayland's color-management protocol
-- negotiates HDR directly with a native Wayland client surface, and an
-- XWayland-hosted window doesn't participate in that the same way.
-- PROTON_ENABLE_WAYLAND=1 (env.lua) fixes that: same game, same in-game
-- HDR setting, xwayland=false, and confirmed visually on the actual TV that
-- it switches into HDR right on launch. Note hyprctl monitors -j's own
-- colorManagementPreset field is NOT a reliable way to verify this -- it
-- kept reporting "srgb" even during the confirmed-working HDR session, so
-- don't trust it over an actual look at the screen.
local tv = {
	output = "desc:Technical Concepts Ltd Beyond TV 0x00010000",
	mode = "3840x2160@120",
	position = "2560x720",
	scale = 1.0,
	supports_hdr = 1,
	supports_wide_color = 1,
	vrr = 1,
	cm = "auto",
}

if host.is_archlinux or host.is_vm then
	monitor1 = {
		output = "Virtual-1",
		mode = "2560x1440",
		position = "0x0",
		scale = 1.0,
	}
	monitor2 = monitor1
elseif host.is_workstation then
	monitor1 = {
		output = "DP-2",
		mode = "3440x1440@100",
		position = "0x0",
		scale = 1.0,
		-- reserved_area is toggled at runtime by scripts/pip-orientation.lua,
		-- based on tiled window count and whether a pinned window is present.
		reserved_area = {
			top = 0,
			right = 0,
			bottom = 0,
			left = 0,
		},
	}
	monitor2 = {
		output = "HDMI-A-1",
		mode = "1920x1200@60",
		transform = 1,
		position = "-1200x-300",
		scale = 1.0,
		-- reserved_area is toggled at runtime by scripts/pip-orientation.lua,
		-- only while a pinned window is present on this monitor.
		reserved_area = {
			top = 0,
			right = 0,
			bottom = 0,
			left = 0,
		},
	}
end

hl.monitor(monitor1)
hl.monitor(monitor2)

-- The TV's HDMI hot-plug-detect stays asserted even when the physical set is
-- powered off (see steam-tv-dim.lua), so it must start disabled on every
-- config load/reload -- otherwise this unconditional registration re-enables
-- it regardless of whether a Big Picture session (steam-tv-dim.lua) or a
-- manual connect (tv-manual-connect.lua) actually warrants it, which is what
-- a plain `hyprctl reload` used to do. Built as a separate table, not by
-- adding `disabled` to `tv` itself: both of those enable paths spread
-- `monitors.tv`'s fields over their own `disabled = false` default, and a
-- `disabled` key on `tv` would clobber that back to true.
local tv_initial = { disabled = true }
for k, v in pairs(tv) do
	tv_initial[k] = v
end
hl.monitor(tv_initial)

-- That disable is a blind default -- it doesn't know whether Big Picture is
-- already running on the TV right now, which a plain `hyprctl reload` mid-
-- session would otherwise kill with nothing to bring it back. Correcting
-- that is steam-tv-dim.lua's hypr_tv_dim_force_resync(), but it's defined
-- later in hyprland.lua's require chain and isn't callable yet from here --
-- deferred one tick via a oneshot timer, which fires after the whole config
-- (all requires) has finished loading, by which point it exists.
hl.timer(function()
	if hypr_tv_dim_force_resync then
		hypr_tv_dim_force_resync()
	end
end, { timeout = 100, type = "oneshot" })

return {
	primary = monitor1,
	secondary = monitor2,
	tv = tv,
}
