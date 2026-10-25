# librepods (AirPods daemon)

Patched build of the daemon from [omarchy-pods](https://github.com/thisisgm/omarchy-pods) (a modified
LibrePods, GPL-3.0). Only `daemon/` is built; the QML shell reads its `status.json` and calls `librepods-ctl`.

- Pinned upstream commit: `PIN` in `build.sh` (currently `fff7fec`).
- `build.sh` clones to `~/code/crossatko/upstream/omarchy-pods` (override: `LIBREPODS_SRC`), checks out the local
  branch `dotfiles-patches` at the pin, applies `patches/` with `git am`, builds out of tree (`build-daemon/`),
  installs to `~/.local`, removes the unit copy cmake installs (the unit is `config/systemd/user/librepods.service`,
  linked by `install.sh`), and restarts the service only when it is active and the binary changed. Re-running it
  is a no-op. Needs `qt6-connectivity`, cmake, ninja (reports what is missing, installs nothing).
  `install.sh` runs it as an optional step.

## Patches

1. `case:refresh` ctl verb (one short BLE burst for the case battery) and `case_seen_at` in status.
2. Burst state flag fix (a single-shot timer is inactive inside its own timeout).
3. Start the A2DP activation and make the AirPods the default output when the BlueZ card appears.

The patches are derived from GPL-3.0 code and are licensed GPL-3.0 as well
([upstream LICENSE](https://github.com/thisisgm/omarchy-pods/blob/main/LICENSE)).

## Updating

Bump `PIN` in `build.sh`, run it. If a patch no longer applies the script aborts the `git am`, leaves the
checkout on the new pin and says so; then in the checkout: `git checkout -B dotfiles-patches <newpin>`, apply
and fix the patches by hand (`git am --3way`), `git format-patch -3 -o config/librepods/patches <newpin>`
(set the author to a noreply address, the repo is public), re-run `build.sh`.
