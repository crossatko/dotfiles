local host = require("hyprland.host")

hl.on("hyprland.start", function()
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")
	hl.exec_cmd(
		"systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR"
	)
	hl.exec_cmd("systemctl --user start hyprpolkitagent")
	hl.exec_cmd("hyprpaper")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("1password --silent")
	hl.exec_cmd("bash ~/.config/waybar/waybar.sh")
	hl.exec_cmd("swaync")
	hl.exec_cmd("hyprctl setcursor Oxygen-White 24")
	hl.exec_cmd("nm-applet --indicator &")
	hl.exec_cmd("blueman-applet &")

	if host.is_battlestation then
		hl.exec_cmd("steam -silent")
		hl.exec_cmd("bash ~/.config/hypr/scripts/tv-input-poll.sh &")
	end
end)
