return {
	menu = "qs ipc call launcher toggle", -- quickshell launcher (config/quickshell/Launcher.qml)
	terminal = "ghostty", -- kitty stays installed as a fallback
	browser = "brave",
	whatsapp = "brave --app='https://web.whatsapp.com'",
	messages = "brave --app='https://messages.google.com'",
	discord = "vesktop", -- Vesktop (the official discord package stays installed; class `vesktop`)
	signal = "flatpak run org.signal.Signal",
	mail = "geary",
	filemanager = "nautilus --new-window",
	jellyfin = "flatpak run org.jellyfin.JellyfinDesktop",
}
