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
	hl.exec_cmd("quickshell") -- bar + wallpaper picker (config/quickshell)
	-- notifications are served by quickshell now (config/quickshell/Notifs.qml); swaync is no longer started
	hl.exec_cmd("hyprctl setcursor Oxygen-White 24")
	-- Kept running only as the NetworkManager secret agent and the bluez pairing agent; their tray
	-- icons are hidden in the bar, whose network / bluetooth popups do the everyday work.
	hl.exec_cmd("nm-applet --indicator &")
	hl.exec_cmd("blueman-applet &")

	if host.is_battlestation then
		hl.exec_cmd("steam -silent")
		hl.exec_cmd("bash ~/.config/hypr/scripts/tv-input-poll.sh &")
	end
end)
