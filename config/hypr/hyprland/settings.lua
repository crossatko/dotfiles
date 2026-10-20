local theme = require("hyprland.theme")

hl.config({
	render = {
		direct_scanout = 1,
		send_content_type = 1,
		cm_auto_hdr = 1,
		use_fp16 = true,
	},
	ecosystem = {
		no_donation_nag = true,
		enforce_permissions = false,
	},
})
hl.config({ cursor = { no_warps = true, no_hardware_cursors = true } })
hl.config({ xwayland = { force_zero_scaling = true } })

hl.config({
	general = {
		gaps_in = 0,
		gaps_out = 0,
		border_size = theme.glass.border_size,
		col = {
			active_border = {
				colors = theme.active.border_gradient,
				angle = 45,
			},
			inactive_border = theme.active.inactive_border,
		},
		resize_on_border = false,
		allow_tearing = false,
		layout = "dwindle",
	},
})

hl.config({
	group = {
		col = {
			border_active = {
				colors = theme.active.border_gradient,
				angle = 45,
			},
			border_inactive = theme.active.inactive_border,
			border_locked_active = theme.active.locked_active,
			border_locked_inactive = theme.active.locked_inactive,
		},
		groupbar = {
			enabled = true,
			gradients = true,
			render_titles = false,
			height = 6,
			indicator_height = 0,
			stacked = false,
			gaps_in = 0,
			gaps_out = 0,
			keep_upper_gap = true,
			rounding = theme.glass.group_rounding,
			rounding_power = theme.glass.group_rounding_power,
			gradient_rounding = theme.glass.gradient_rounding,
			gradient_rounding_power = theme.glass.gradient_rounding_power,
			round_only_edges = true,
			gradient_round_only_edges = true,
			col = {
				active = theme.active.locked_active,
				inactive = theme.active.groupbar_inactive,
				locked_active = theme.active.locked_active,
				locked_inactive = theme.active.locked_inactive,
			},
		},
	},
})

hl.config({
	decoration = {
		rounding = theme.glass.window_rounding,
		rounding_power = theme.glass.window_rounding_power,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		dim_inactive = true,
		dim_strength = 0.5,
		shadow = {
			enabled = true,
			range = 24,
			render_power = 3,
			color = theme.active.shadow,
			offset = { 3, 3 },
		},
		-- blur = {
		-- 	enabled = true,
		-- 	size = 4,
		-- 	passes = 3,
		-- 	xray = false,
		-- 	new_optimizations = true,
		-- 	-- vibrancy = 0.1696,
		-- },
	},
})

-- =====================================================================
-- Blur variants from Hyprland PR #15661 (unmerged, open with conflicts
-- as of 2026-08-18 -- vaxerski/Hyprland branch
-- "more-blur-XDDDDDDDDDDDDDDDDDDDDDD"). These decoration:blur:* keys
-- only exist in that experimental build, ~/code/hyprland-blur-test.
-- Keep this whole section commented out for the real hyprland-git
-- session on tty1 -- it will not recognize these keys.
--
-- To test: uncomment ONE variant block below (the `variant` line plus
-- its matching options table), save, then from the test session (tty2)
-- run `hyprctl reload`. Re-comment and reload again before switching
-- back to daily use.
-- =====================================================================

-- hl.config({ decoration = { blur = { variant = "kawase" } } }) -- default, no extra options

-- hl.config({ decoration = { blur = { variant = "frost" } } })
-- hl.config({
-- 	decoration = {
-- 		blur = {
-- 			glass = {
-- 				refraction = 20.0, -- max refraction displacement (px), range 0-20, default 3.0
-- 				size = 32.0, -- pattern size (px), range 4-512, default 48.0
-- 				roughness = 0.1, -- relief shading strength, range 0-1, default 0.4
-- 			},
-- 		},
-- 	},
-- })

-- hl.config({ decoration = { blur = { variant = "ripple" } } })
-- hl.config({
-- 	decoration = {
-- 		blur = {
-- 			ripple = {
-- 				strength = 6.0, -- max refraction displacement of click ripples (px), range 0-32, default 6.0
-- 				radius = 180.0, -- max ripple radius (px), range 1-1000, default 180.0
-- 				width = 24.0, -- ripple wave width (px), range 1-200, default 24.0
-- 				duration = 0.45, -- ripple duration (s), range 0.05-5, default 0.45
-- 			},
-- 		},
-- 	},
-- })

-- hl.config({ decoration = { blur = { variant = "drops" } } })
-- hl.config({
-- 	decoration = {
-- 		blur = {
-- 			drops = {
-- 				speed = 0.6, -- animation speed, range 0-10, default 0 (disabled). NOTE: enabling significantly increases GPU usage
-- 			},
-- 		},
-- 	},
-- })

-- hl.config({ decoration = { blur = { variant = "water" } } })
-- hl.config({
-- 	decoration = {
-- 		blur = {
-- 			water = {
-- 				strength = 12.0, -- refraction + injection strength (px), range 0-32, default 12.0
-- 				radius = 180.0, -- pointer radius (px), range 1-1000, default 180.0
-- 				speed = 1.0, -- propagation speed, range 0-10, default 1.0
-- 				damping = 0.995, -- decay damping, range 0-1, default 0.995
-- 				duration = 12.0, -- max animation duration (s), range 0.5-60, default 12.0
-- 			},
-- 		},
-- 	},
-- })

-- hl.config({ decoration = { blur = { variant = "fluid_jar" } } })
-- hl.config({ decoration = { blur = { fluid_jar = {
-- 	color = "rgba(cc3399ff)",  -- fluid color, default 0xCC3399FF
-- 	speed = 1.0,               -- animation speed, range 0-10, default 1.0
-- 	fill_amount = 0.4,         -- fill level, range 0-1, default 0.4
-- 	mass = 1.0,                -- inertial mass, range 0.1-10, default 1.0
-- 	precision = 1.0,           -- sim precision multiplier, range 0.5-8, default 1.0
-- 	turbulence = 1.0,          -- interior turbulence multiplier, range 0-5, default 1.0
-- 	distortion = 1.0,          -- refraction distortion multiplier, range 0-10, default 1.0
-- } } } })

-- hl.config({ decoration = { blur = { variant = "prism" } } }) -- triangular refraction, no extra options

-- hl.config({ decoration = { blur = { variant = "heat_shimmer" } } })
-- hl.config({
-- 	decoration = {
-- 		blur = {
-- 			heat_shimmer = {
-- 				speed = 1.0, -- animation speed, range not specified upstream, default 1.0, 0 disables. NOTE: increases GPU usage
-- 			},
-- 		},
-- 	},
-- })

-- hl.config({ decoration = { blur = { variant = "acrylic" } } })
-- hl.config({
-- 	decoration = {
-- 		blur = {
-- 			acrylic = {
-- 				refraction = 24.0, -- max lens displacement (px), range 0-48, default 24.0
-- 				bulb = 48.0, -- width of curved acrylic edge (px), range 4-256, default 48.0
-- 				clarity = 0.82, -- amount of sharp backdrop transmitted through surface, range 0-1, default 0.82
-- 				aberration = 0.025, -- relative chromatic separation in the lens, range 0-0.25, default 0.025
-- 				tint = "rgba(14eef5ff)", -- tint color, alpha controls optical absorption, default 0x14EEF5FF
-- 			},
-- 		},
-- 	},
-- })

-- solid_glass: a from-scratch reworking of acrylic (only exists in this
-- ~/code/hyprland-blur-test build, patched locally -- not upstream) aimed at an
-- Apple-style "liquid glass" look, with depth/edge_curve/light_angle/specular_*/
-- sheen/saturation on top of acrylic's original refraction/bulb/clarity/aberration/tint.
local host = require("hyprland.host")

-- Glass needs the patched Hyprland fork (only on the battlestation); everywhere else: plain blur.
if host.is_battlestation then
	hl.config({
		decoration = {
			blur = {
				size = 4,
				passes = 2,
				vibrancy = 0.8,
				popups = true,
				variant = "solid_glass",
				-- tune live with GlassTune (pen chip in the bar), then "Copy changed" and paste here
				solid_glass = {
					refraction = 48, -- max lens displacement (px), 0-48
					bulb = 57.03, -- width of the curved edge (px), 4-256
					clarity = 0.395, -- 1 = sharp interior (only `frost` blurs it), 0 = fully frosted, 0-1
					aberration = 0, -- chromatic split in the lens, 0-0.25
					tint = 0x00000000, -- AARRGGBB, alpha = absorption
					depth = 2.031, -- bend multiplier, 0-3
					edge_curve = 1.304, -- <1 bends right at the edge, >1 later (bevel), 0.2-5
					light_angle = 0, -- degrees, 0 = right, 90 = up
					specular_intensity = 0, -- synthetic rim/glint/sheen lighting, 0 = off, 0-3
					specular_power = 1, -- glint sharpness, 1-200
					sheen = 0, -- rim glint facing the light, 0-1
					saturation = 1.355, -- backdrop vividness, 0-3
					frost = 0, -- interior blur radius (px), 0-16
					darkening = 0.795, -- 0-1
				},
			},
		},
	})
else
	hl.config({
		decoration = {
			blur = {
				enabled = true,
				size = 4,
				passes = 2,
				new_optimizations = true,
				vibrancy = 0.1696,
			},
		},
	})
end

-- hl.config({ decoration = { blur = { variant = "aurora" } } })
-- hl.config({
-- 	decoration = {
-- 		blur = {
-- 			aurora = {
-- 				speed = 1.0, -- animation speed, default 1.0, 0 freezes it. NOTE: increases GPU usage
-- 				intensity = 0.35, -- strength of aurora color contribution, range 0-1, default 0.35
-- 				color1 = "rgba(29f0a0ff)", -- first curtain color, alpha controls contribution, default 0x29F0A0FF
-- 				color2 = "rgba(7a4dffff)", -- second curtain color, alpha controls contribution, default 0x7A4DFFFF
-- 			},
-- 		},
-- 	},
-- })

-- hl.config({ decoration = { blur = { variant = "haze" } } })
-- hl.config({ decoration = { blur = { haze = {
-- 	intensity = 0.35,     -- strength of pearlescent sheen, range 0-1, default 0.35
-- 	iridescence = 0.7,    -- strength of pearlescent color shift, range 0-1, default 0.7
-- } } } })

hl.config({
	animations = {
		enabled = true,
		workspace_wraparound = false,
	},
})

-- Current Hyprland (0.55) animation syntax (wiki/default style)
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("easy", { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global", enabled = true, speed = 0.5, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 0.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 0.5, bezier = "quick" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 0.5, bezier = "quick" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 0.5, bezier = "quick", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 0.5, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 0.5, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 0.5, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 0.5, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 0.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 0.5, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 0.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 0.5, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 0.5, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 0.5, bezier = "almostLinear", style = "slidefade 5%" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 0.5, bezier = "almostLinear", style = "slidefade 5%" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 0.5, bezier = "almostLinear", style = "slidefade 5%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 0.5, bezier = "quick", style = "fade" }) -- scratchpad (SUPER+R)
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 0.5, bezier = "quick" })

hl.config({
	dwindle = {
		preserve_split = true,
		force_split = 2,
		split_width_multiplier = 1.3,
	},
})

hl.config({ master = { new_status = "master" } })
hl.config({ scrolling = { fullscreen_on_one_column = true } })
hl.config({ misc = { force_default_wallpaper = -1, disable_hyprland_logo = true } })
