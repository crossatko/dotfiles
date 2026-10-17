-- Followed Twitch channels -> player window (embedded mpv + chat). The app lives in its own
-- project, ~/code/crossatko/twitch-qs-mpv (credentials in its .env); this is only the glue.
-- Absolute paths: Hyprland's PATH is not the interactive shell's.
local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function show_twitch_menu()
	-- hl.exec_cmd only: running the menu synchronously (io.popen) would block Hyprland's event loop.
	local menu_cmd = "$HOME/.config/quickshell/bin/qmenu --prompt-text 'Twitch: '"
	hl.exec_cmd(
		"sh -c "
			.. shell_quote(
				"TWITCH_QS_FONT='Paper Mono' TWITCH_QS_MENU_CMD=\""
					.. menu_cmd
					.. "\" \"$HOME/code/crossatko/twitch-qs-mpv/bin/twitch-qs-mpv\" menu"
			)
	)
end

return {
	show_twitch_menu = show_twitch_menu,
}
