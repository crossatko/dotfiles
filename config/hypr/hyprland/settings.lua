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
		gaps_in = 4,
		gaps_out = 12,
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
			gaps_in = 2,
			gaps_out = 3,
			keep_upper_gap = true,
			rounding = theme.glass.group_rounding,
			rounding_power = theme.glass.group_rounding_power,
			gradient_rounding = theme.glass.gradient_rounding,
			gradient_rounding_power = theme.glass.gradient_rounding_power,
			round_only_edges = true,
			gradient_round_only_edges = true,
			col = {
				active = theme.active.locked_active,
				inactive = theme.active.inactive_border,
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
		inactive_opacity = 0.75,
		dim_inactive = true,
		dim_strength = 0.5,
		shadow = {
			enabled = true,
			range = 24,
			render_power = 3,
			color = theme.active.shadow,
			offset = "3 3",
		},
		blur = {
			enabled = true,
			size = 4,
			passes = 2,
			xray = true,
			new_optimizations = true,
			vibrancy = 0.1696,
		},
	},
})

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
