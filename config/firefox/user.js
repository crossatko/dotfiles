// Managed by dotfiles (config/firefox). Symlinked into the profile by install.sh.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// Let the compositor see through the window chrome (Wayland alpha + no opaque region).
user_pref("widget.wayland.opaque-region.enabled", false);
user_pref("widget.transparent-windows", true);
user_pref("browser.tabs.allow_transparent_browser", false);
// Dark chrome so text stays readable on the translucent header.
user_pref("browser.theme.toolbar-theme", 0);
