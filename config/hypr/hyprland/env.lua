local host = require("hyprland.host")

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Oxygen_White")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland")
-- The KDE platform theme reads ~/.config/kdeglobals (colors, fonts, icons, style), which
-- ~/.config/theme/theme.py keeps in sync with the wallpaper. qt6ct made KDE apps such as Dolphin
-- fall back to stock Breeze Light. Qt 5 has no such plugin here, so Qt 5 apps lose theming (only a
-- few utilities such as qrenderdoc use it).
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- ~/.local/bin first. Hyprland's own PATH lacks it, so anything spawned from a keybind or
-- the quickshell launcher would skip user shims (brave -> theme shim). Guarded so
-- config reloads don't keep prepending it.
do
	local bin = os.getenv("HOME") .. "/.local/bin"
	local path = os.getenv("PATH") or ""
	if not path:find(bin, 1, true) then
		hl.env("PATH", bin .. ":" .. path)
	end
end

if host.is_battlestation then
	hl.env("PROTON_LOW_LATENCY", "1")
	-- PROTON_ENABLE_WAYLAND deliberately left unset -- tried it, and while
	-- it does fix HDR (XWayland can't negotiate Wayland's color-management
	-- protocol at all), it breaks Steam Big Picture's own controller-focus
	-- tracking: confirmed live via controller_ui.txt that
	-- OnFocusWindowChanged never fires for a native-Wayland game window, so
	-- Steam Input never switches away from the Big Picture UI's own config --
	-- both windows receive controller input at once. Confirmed this isn't
	-- Ubisoft Connect-specific: it's any title with a splash/launcher window
	-- separate from the real game window. Dropping HDR for now entirely
	-- rather than re-litigating this trade -- a later attempt at switching
	-- the TV's cm live per-game also turned out to have real crash risk
	-- (Hyprland/Aquamarine DRM backend abort on rapid cm changes while
	-- gamescope is actively rendering, confirmed via coredumpctl), on top of
	-- the focus-tracking cost.
	hl.env("PROTON_FSR4_UPGRADE", "1")
	hl.env("DISABLE_LSFG", "1")
end
