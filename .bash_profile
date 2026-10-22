# Autologin on TTY1 (see /etc/systemd/system/getty@tty1.service.d/) lands
# here before dropping to an interactive shell -- exec straight into the
# session supervisor instead, which is what now owns "start Hyprland or
# gamescope-session, and restart the other one when either exits" now that
# SDDM is disabled. Guarded to TTY1 specifically and only when no graphical
# session is already running, so a manual login on another VT (e.g. for
# recovery/debugging) still drops to a normal shell as expected.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
	exec ~/.config/hypr/scripts/session-supervisor.sh
fi

# Login shells read ~/.bashrc too
[[ -f ~/.bashrc ]] && . ~/.bashrc
