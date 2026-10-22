# jellyfin-qs

Small Jellyfin CLI for the Quickshell launcher (python3 stdlib only) plus an mpv reporting script.

- Setup: `jellyfin-qs login` in a terminal (asks server URL, e.g. `http://jellyfin.example:8096`, user, password).
  Server URL is stored in `~/.config/jellyfin-qs/config.json`, token/user id in
  `${XDG_STATE_HOME:-~/.local/state}/jellyfin-qs/token.json` (0600). The password is never stored.
- Commands (JSON on stdout): `status [--json]`, `resume [--library ID]`, `nextup [--library ID]`,
  `latest [--library ID]`, `libraries`, `search <q> [--limit N] [--types ...] [--parent ID]`,
  `children <id> [--types auto|T1,T2] [--sort name|added|year] [--start N] [--limit N] [--paged]`, `item <id>`,
  `playlists`, `play <id> [--resume] [--shuffle]`, `logout`.
- `--library` / `--parent` scope a list or search to one library (Jellyfin `ParentId`).
- `children` without options keeps the old output (direct children, sorted locally). With `--types` it lists a library
  recursively: `auto` = what the library shows (movies: `Movie,BoxSet`, tvshows: `Series`, music: album artists via
  `/Artists/AlbumArtists`, other collection types: direct children). `--sort`/`--start`/`--limit` are sent to the server
  (SortName order by default); series / seasons / artists / albums / playlists keep their own order and are paged
  locally. `--paged` prints `{"items": [...], "total": N, "start": N}` instead of the bare array.
- Exit codes: 0 ok, 1 usage/missing program, 2 not configured/logged in/token rejected, 3 network or
  server error (also "server unreachable (is Tailscale connected?)"), 4 not found.
- Timeouts: 3 s connect, 10 s total. Direct play only (`static=true`), no transcoding.
- `play` writes per-session files (mpv include with the auth header, curl config, optional m3u, IPC socket)
  mode 0600 under `$XDG_RUNTIME_DIR/jellyfin-qs/`; the token is never in argv or URLs.
  `mpv/jellyfin-report.lua` reports Playing/Progress/Stopped and removes the files on exit.
  `play` first stops any running jellyfin-qs player (`quit` over its IPC socket, so Stopped is reported;
  SIGTERM/SIGKILL to the socket's peer if it hangs), so a new playback replaces the old one.
- Tests: `python3 -m unittest discover -s config/launcher/jellyfin/tests` (fake server, needs mpv for one test).
  Env overrides: `JELLYFIN_QS_CONFIG_DIR`, `JELLYFIN_QS_STATE_DIR`, `JELLYFIN_QS_MPV`, `JELLYFIN_QS_MPV_ARGS`.
