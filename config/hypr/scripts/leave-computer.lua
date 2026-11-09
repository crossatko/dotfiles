local function leave_computer()
	local cleanup_cmd = "pkill -9 -x Discord & "
		.. "pkill -9 -x brave & "
		.. "pkill -9 -x geary & "
		.. "docker stop $(docker ps -q) 2>/dev/null &killall discord & "
		.. "sleep 1"

	hl.exec_cmd(cleanup_cmd)
	hl.exec_cmd("loginctl lock-session")
end

return {
	leave_computer = leave_computer,
}
