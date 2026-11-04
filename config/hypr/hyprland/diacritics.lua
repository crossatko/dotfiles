-- The "fix Czech diacritics" key (Settings > Diacritics, Quickshell DiacriticsPrefs.qml). One press-to-run key: it runs
-- M.COMMAND (the one place the command is set; QS_DIACRITICS_CMD overrides it, tests only, Hyprland must have the same
-- environment as the shell for that). Quickshell writes the key the user chose to a generated state file OUTSIDE the repo,
-- '#' lines are comments:
--   <keys>|<description>        e.g.  SUPER + SHIFT + D|Fix Czech diacritics
-- keys may be a mouse button (mouse:<evdev code>). Only the first well-formed line binds. No file / no line = no key.
-- ${XDG_STATE_HOME:-~/.local/state}/quickshell/diacritics-binds.txt (QS_DIACRITICS_BINDS_FILE overrides). Read at every
-- config load (so a reload or restart keeps the key) and again by `hyprctl eval 'diacritics_apply()'`, which Quickshell
-- runs after it rewrote the file: the bind made here is removed by its own handle (Keybind:remove), never by
-- hl.unbind(keys), which would also drop any other bind on that key. Same mechanism as ptt.lua.
-- Required with pcall from binds.lua: an error here must not cost the other binds.
local M = {}

M.COMMAND = "diacritics run"
M.MAX_BYTES = 4096

function M.command()
	local c = os.getenv("QS_DIACRITICS_CMD")
	if c ~= nil and c ~= "" then
		return c
	end
	return M.COMMAND
end

function M.path()
	local p = os.getenv("QS_DIACRITICS_BINDS_FILE")
	if p ~= nil and p ~= "" then
		return p
	end
	local state = os.getenv("XDG_STATE_HOME")
	if state == nil or state == "" then
		state = (os.getenv("HOME") or "") .. "/.local/state"
	end
	return state .. "/quickshell/diacritics-binds.txt"
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Pure: file text -> { keys, desc } of the first well-formed line, or nil
function M.parse(text)
	for line in (text or ""):gmatch("[^\r\n]+") do
		if not line:match("^%s*#") then
			local keys, desc = line:match("^([^|]*)|?(.*)$")
			keys, desc = trim(keys or ""), trim((desc or ""):gsub("|.*$", ""))
			if keys:match("^[%w_ +:]+$") and keys:match("%w") then
				return { keys = keys, desc = desc ~= "" and desc or "Fix Czech diacritics" }
			end
		end
	end
	return nil
end

function M.read()
	local f = io.open(M.path(), "r")
	if not f then
		return ""
	end
	local text = f:read(M.MAX_BYTES) or ""
	f:close()
	-- a last line without its newline may be cut off (the file is longer than the cap, or was caught mid-write): drop it
	return (text:match("^(.*\n)") or "")
end

-- handle of the bind made by the last apply (this Lua state only: a reload starts empty and binds from the file)
M.handle = nil

-- drop our bind, bind the file's line; -> number of binds made (0 or 1)
function M.apply()
	if M.handle ~= nil then
		pcall(function()
			M.handle:remove()
		end)
		M.handle = nil
	end
	local b = M.parse(M.read())
	if b == nil then
		return 0
	end
	local ok, h = pcall(function()
		return hl.bind(b.keys, hl.dsp.exec_cmd(M.command()), { description = b.desc })
	end)
	if ok and h ~= nil then
		M.handle = h
		return 1
	end
	return 0
end

rawset(_G, "diacritics_apply", function()
	return M.apply()
end)

M.apply()

return M
