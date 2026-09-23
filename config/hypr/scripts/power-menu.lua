local actions = {
	-- Not a bare `systemctl suspend`: suspend.sh releases the TV's input first
	-- and only then requests the suspend. Doing it the other way round cannot
	-- work -- NetworkManager tears the network down ~1ms after the request, so
	-- anything hooked on PrepareForSleep (hypridle's before_sleep_cmd included)
	-- is already too late to reach the TV. See suspend.sh's header.
	sleep = "~/.config/hypr/scripts/suspend.sh",
	shutdown = "hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown now'",
	reboot = "hyprshutdown -t 'Restarting...' --post-cmd 'reboot'",
	["exit hyprland"] = "hyprshutdown",
	-- Writes the session-supervisor's marker file *before* exiting, not
	-- after (as a hyprshutdown --post-cmd) -- if the write ever failed,
	-- better to notice while still in this session than land at a shell
	-- prompt with no way to tell why. No sudo needed for this anymore --
	-- SDDM (and its account-wide autologin config) is gone entirely;
	-- session-supervisor.sh just reads this plain file under $HOME.
	["switch to gamescope"] = "echo gamescope > ~/.local/state/next-session"
		.. " && hyprshutdown -t 'Switching to Gamescope...'",
	["switch to kde"] = "echo kde > ~/.local/state/next-session"
		.. " && hyprshutdown -t 'Switching to KDE...'",
}

local options = {
	"sleep",
	"shutdown",
	"reboot",
	"exit hyprland",
	"switch to gamescope",
	"switch to kde",
}

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function build_menu_command()
	local quoted_options = {}
	local case_branches = {}

	for _, option in ipairs(options) do
		table.insert(quoted_options, shell_quote(option))
		table.insert(case_branches, shell_quote(option) .. ") " .. actions[option] .. " ;;")
	end

	return "choice=$(printf '%s\\n' "
		.. table.concat(quoted_options, " ")
		.. " | tofi --prompt-text 'Power: '); case \"$choice\" in "
		.. table.concat(case_branches, " ")
		.. " esac"
end

local function show_power_menu()
	-- Do not use io.popen here. Running tofi synchronously from the Hyprland Lua
	-- callback blocks Hyprland's event loop and can freeze the whole desktop.
	hl.exec_cmd("sh -c " .. shell_quote(build_menu_command()))
end

return {
	actions = actions,
	show_power_menu = show_power_menu,
}
