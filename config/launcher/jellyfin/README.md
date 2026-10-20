# jellyfin-qs

Small Jellyfin CLI for the Quickshell launcher (python3 stdlib only) plus an mpv reporting script.

- Setup: `jellyfin-qs login` in a terminal (asks server URL, e.g. `http://jellyfin.example:8096`, user, password).
  Server URL is stored in `~/.config/jellyfin-qs/config.json`, token/user id in
  `${XDG_STATE_HOME:-~/.local/state}/jellyfin-qs/token.json` (0600). The password is never stored.
- Commands (JSON on stdout): `status [--json]`, `resume`, `nextup`, `latest [--library ID]`, `libraries`,
  `search <q> [--limit N] [--types ...]`, `children <id>`, `item <id>`, `playlists`,
  `play <id> [--resume] [--shuffle]`, `logout`.
- Exit codes: 0 ok, 1 usage/missing program, 2 not configured/logged in/token rejected, 3 network or
  server error (also "server unreachable (is Tailscale connected?)"), 4 not found.
- Timeouts: 3 s connect, 10 s total. Direct play only (`static=true`), no transcoding.
- `play` writes per-session files (mpv include with the auth header, curl config, optional m3u, IPC socket)
  mode 0600 under `$XDG_RUNTIME_DIR/jellyfin-qs/`; the token is never in argv or URLs.
  `mpv/jellyfin-report.lua` reports Playing/Progress/Stopped and removes the files on exit.
- Tests: `python3 -m unittest discover -s config/launcher/jellyfin/tests` (fake server, needs mpv for one test).
  Env overrides: `JELLYFIN_QS_CONFIG_DIR`, `JELLYFIN_QS_STATE_DIR`, `JELLYFIN_QS_MPV`, `JELLYFIN_QS_MPV_ARGS`.
