local function read_trimmed_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local out = file:read("*a")
	file:close()
	if not out then
		return nil
	end

	out = out:gsub("^%s+", ""):gsub("%s+$", "")
	if out == "" then
		return nil
	end

	return out
end

local function read_hostname_cmd(cmd)
	local p = io.popen(cmd)
	if not p then
		return nil
	end

	local out = p:read("*a")
	p:close()
	if not out then
		return nil
	end

	out = out:gsub("^%s+", ""):gsub("%s+$", "")
	if out == "" then
		return nil
	end

	return out
end

local raw = os.getenv("HOSTNAME")
	or os.getenv("HOST")
	or read_trimmed_file("/proc/sys/kernel/hostname")
	or read_trimmed_file("/etc/hostname")
	or read_hostname_cmd("hostname 2>/dev/null")
	or read_hostname_cmd("uname -n 2>/dev/null")
	or ""

local upper = raw:upper()

return {
	raw = raw,
	upper = upper,
	is_battlestation = upper:find("BATTLESTATION", 1, true) ~= nil,
	is_workstation = upper:find("WORKSTATION", 1, true) ~= nil,
	is_archlinux = upper == "ARCHLINUX",
	is_vm = upper:match("VM$") ~= nil, -- any hostname ending in -vm (e.g. xyz-vm)
}
