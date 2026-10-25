local host = require("hyprland.host")

hl.on("hyprland.start", function()
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")
	-- A previous session (gamescope/KDE) can leave XDG_DESKTOP_PORTAL_DIR exported but EMPTY in the
	-- systemd user manager, which makes xdg-desktop-portal load no backends at all (no ScreenCast,
	-- FileChooser, Settings...). Clear it, and restart the portal only if it had picked that up.
	hl.exec_cmd(
		"sh -c 'systemctl --user show-environment | grep -qx XDG_DESKTOP_PORTAL_DIR= && "
			.. "{ systemctl --user unset-environment XDG_DESKTOP_PORTAL_DIR; systemctl --user try-restart xdg-desktop-portal; }'"
	)
	hl.exec_cmd(
		"systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR"
	)
	-- freedesktop color-scheme from the chosen light/dark mode (state file of theme.py, default dark), set before
	-- 1Password / browsers start; theme.py apply / `theme.py mode` keep it too.
	hl.exec_cmd(
		[[sh -c 'm=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/theme/mode" 2>/dev/null); if [ "$m" = light ]; then s=prefer-light; else s=prefer-dark; fi; gsettings set org.gnome.desktop.interface color-scheme $s']]
	)
	hl.exec_cmd("systemctl --user start hyprpolkitagent")
	-- Not a bare `hyprpaper`: started 2 s after the compositor it raced the monitor setup and left every
	-- output black. The script waits for the outputs and retries once (scripts/start-hyprpaper.sh).
	hl.exec_cmd("$HOME/.config/hypr/scripts/start-hyprpaper.sh")
	-- Via systemd, not a bare `hypridle`, so that there is exactly one owner of
	-- the process. steam-streaming.lua and steam-tv-dim.lua already manage it
	-- with `systemctl --user stop/restart hypridle`; combined with a bare exec
	-- here, the first time either of them ran left TWO hypridle instances alive
	-- (confirmed: `hypridle` from this line plus `/usr/bin/hypridle` from the
	-- unit, each holding its own sleep inhibitor). Everything then fired twice
	-- -- two before_sleep_cmd, two after_sleep_cmd, two on-wake.sh per resume.
	-- `systemctl start` on an already-running unit is a no-op, so this cannot
	-- duplicate.
	--
	-- Deliberately started here rather than by enabling the unit: its
	-- WantedBy=graphical-session.target is useless under Hyprland (that target
	-- is never activated here) and actively wrong under gamescope, where it IS
	-- activated -- hypridle would start with a stale imported WAYLAND_DISPLAY,
	-- fail to reach a compositor, and Restart=on-failure would loop it.
	hl.exec_cmd("systemctl --user start hypridle")
	hl.exec_cmd("1password --silent")
	-- QSG_USE_SIMPLE_ANIMATION_DRIVER: Qt's default vsync-driven animation clock runs QML animations ~1.4x too fast on the
	-- 360 Hz monitor (measured 2026-10-20: 800 ms linear fade took ~580 ms; with this, ~780 ms; 60 Hz was right
	-- either way), so 1x would not mean the same time as Hyprland's animations (Settings > Animations)
	hl.exec_cmd("env QSG_USE_SIMPLE_ANIMATION_DRIVER=1 quickshell") -- bar + wallpaper picker (config/quickshell)
	-- notifications are served by quickshell now (config/quickshell/Notifs.qml)
	hl.exec_cmd("hyprctl setcursor Oxygen-White 24")
	-- Kept running only as the NetworkManager secret agent and the bluez pairing agent; their tray
	-- icons are hidden in the bar, whose network / bluetooth popups do the everyday work.
	-- Clipboard history for the Quickshell launcher (launcher/ClipboardSource.qml; `v ` / `clip ` prefix).
	-- One watcher per kind; cliphist keeps its own db (~/.cache/cliphist/db), capped at 500 entries.
	hl.exec_cmd("wl-paste --type text --watch cliphist -max-items 500 store")
	hl.exec_cmd("wl-paste --type image --watch cliphist -max-items 500 store")
	hl.exec_cmd("nm-applet --indicator &")
	hl.exec_cmd("blueman-applet &")

	if host.is_battlestation then
		hl.exec_cmd("steam -silent")
		hl.exec_cmd("bash ~/.config/hypr/scripts/tv-input-poll.sh &")
	end
end)

-- Video wallpapers (mpvpaper above hyprpaper; theme.py video, AGENTS.md "Video wallpapers"): a monitor that comes
-- or goes gets its player (re)started / reaped. The delay lets hyprpaper map its surface for the new output first
-- (the video layer has to be mapped after it); `video start` is a no-op for players that already run and for
-- setups without any video entry. At login start-hyprpaper.sh starts the players itself.
hl.on("monitor.added", function()
	hl.exec_cmd("sh -c 'sleep 3; python3 -I \"$HOME/.config/theme/theme.py\" video start'")
end)
hl.on("monitor.removed", function()
	hl.exec_cmd("sh -c 'sleep 1; python3 -I \"$HOME/.config/theme/theme.py\" video start'")
end)
