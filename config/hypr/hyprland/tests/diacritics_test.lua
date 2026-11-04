-- Run: lua5.5 config/hypr/hyprland/tests/diacritics_test.lua
-- diacritics.lua (the diacritics key from Quickshell's state file) against a fake `hl`: hl.bind returns a handle whose
-- remove() drops only that bind, a bad key string raises. Never reads the user's files: QS_DIACRITICS_BINDS_FILE points
-- at a temp file.
local dir = arg[0]:match("^(.*)/hyprland/tests/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

local TMP = os.tmpname()
local env = { QS_DIACRITICS_BINDS_FILE = TMP }
local real_getenv = os.getenv
os.getenv = function(k)
	if env[k] ~= nil then
		return env[k] ~= false and env[k] or nil
	end
	return real_getenv(k)
end
local function write(t)
	local f = assert(io.open(TMP, "w"))
	f:write(t)
	f:close()
end

local binds = {}
_G.hl = {
	dsp = { exec_cmd = function(cmd) return { exec = cmd } end },
	bind = function(keys, action, opts)
		if keys:match("BAD") then
			error("invalid key")
		end
		local b = { keys = keys, cmd = action.exec, desc = opts and opts.description, alive = true }
		binds[#binds + 1] = b
		return { remove = function() b.alive = false end }
	end,
}
local function live()
	local out = {}
	for _, b in ipairs(binds) do
		if b.alive then
			out[#out + 1] = b.keys .. "=" .. tostring(b.cmd)
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end
local fails = 0
local function eq(got, want, what)
	if got ~= want then
		fails = fails + 1
		print("FAIL " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
end

hl.bind("SUPER + D", { exec = "launcher" }, {})

write("# generated\nSUPER + SHIFT + D|Fix Czech diacritics\n")
local dia = dofile(dir .. "/hyprland/diacritics.lua")
eq(live(), "SUPER + D=launcher,SUPER + SHIFT + D=diacritics run", "load binds the file with the command")
eq(type(rawget(_G, "diacritics_apply")), "function", "diacritics_apply global")

write("SUPER + mouse:276|Fix Czech diacritics\n")
eq(diacritics_apply(), 1, "apply count")
eq(live(), "SUPER + D=launcher,SUPER + mouse:276=diacritics run", "re-apply replaces only our bind")

env.QS_DIACRITICS_CMD = "echo test"
diacritics_apply()
eq(live(), "SUPER + D=launcher,SUPER + mouse:276=echo test", "command override")
env.QS_DIACRITICS_CMD = nil

write("")
eq(diacritics_apply(), 0, "empty file = no key")
eq(live(), "SUPER + D=launcher", "no key")

write("BAD|x\nF8|y\n")
eq(diacritics_apply(), 0, "a bad key binds nothing (the first line decides)")
write("F1 ; exec|x\nF9|second\n")
eq(diacritics_apply(), 1, "a malformed line is skipped, the next one binds")
eq(live(), "F9=diacritics run,SUPER + D=launcher", "after malformed")

write("F1|Fix\nF2|Fix\n")
diacritics_apply()
eq(live(), "F1=diacritics run,SUPER + D=launcher", "only the first line")

write("F3|Fix\nF4|cut off")
diacritics_apply()
eq(live(), "F3=diacritics run,SUPER + D=launcher", "an unterminated last line is dropped")

os.remove(TMP)
eq(diacritics_apply(), 0, "no file = no key")
eq(live(), "SUPER + D=launcher", "no file")

env.QS_DIACRITICS_BINDS_FILE = false
env.XDG_STATE_HOME = "/s"
eq(dia.path(), "/s/quickshell/diacritics-binds.txt", "path with XDG_STATE_HOME")
env.XDG_STATE_HOME = ""
env.HOME = "/home/u"
eq(dia.path(), "/home/u/.local/state/quickshell/diacritics-binds.txt", "HOME fallback")
os.getenv = real_getenv

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("ok")
