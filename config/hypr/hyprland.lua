-- Config
require("hyprland.apps")
require("hyprland.monitors")
require("hyprland.env")
require("hyprland.autostart")
require("hyprland.settings")
require("hyprland.input")
require("hyprland.binds")
require("hyprland.workspaces")
require("hyprland.rules")
require("hyprland.permissions")
pcall(require, "hyprland.managed") -- Settings > Appearance / Glass overrides (managed files): keep it after the modules above

-- Scripts
require("scripts.pip-fix")
require("scripts.pip-orientation")
require("scripts.pip-reserve")
require("scripts.tv")
require("scripts.steam-tv-dim")
require("scripts.tv-manual-connect")
require("scripts.steam-launcher-cleanup")
require("scripts.steam-streaming")
require("scripts.diacritics")
