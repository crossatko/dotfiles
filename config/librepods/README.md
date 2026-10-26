# librepods (AirPods daemon)

Patched build of the daemon from [omarchy-pods](https://github.com/thisisgm/omarchy-pods) (a modified
LibrePods, GPL-3.0). Only `daemon/` is built; the QML shell reads its `status.json` and calls `librepods-ctl`.

- Pinned upstream commit: `PIN` in `build.sh` (currently `fff7fec`).
- `build.sh` clones to `~/code/crossatko/upstream/omarchy-pods` (override: `LIBREPODS_SRC`), checks out the local
  branch `dotfiles-patches` at the pin, applies `patches/` with `git am`, builds out of tree (`build-daemon/`),
  installs to `~/.local`, removes the unit copy cmake installs (the unit is `config/systemd/user/librepods.service`,
  linked by `install.sh`), and restarts the service only when it is active and the binary changed. Re-running it
  is a no-op. Needs git, cmake, ninja, gcc, pkgconf, `qt6-base`, `qt6-declarative`, `qt6-connectivity`, `qt6-tools` (LinguistTools),
  `vulkan-headers` (Qt6Gui's WrapVulkanHeaders), `openssl`, `libpulse` (reports everything missing at once, installs
  nothing; the packages stage of `install.sh` installs them first). The upstream unit tests are not built.
  `install.sh` runs it as an optional step.

## Patches

1. `case:refresh` ctl verb (one short BLE burst for the case battery) and `case_seen_at` in status.
2. Burst state flag fix (a single-shot timer is inactive inside its own timeout).
3. Start the A2DP activation and make the AirPods the default output when the BlueZ card appears.
4. Conversational awareness speech flag `0x02` ducks like `0x01` (`0x03` = stopped) instead of falling through to "voice ended".
5. Conversational awareness flags `08`/`09` mean normal volume (the buds send them around listening-mode changes and when a bud comes out): restore a duck in progress instead of dropping the saved volume.

The patches are derived from GPL-3.0 code and are licensed GPL-3.0 as well
([upstream LICENSE](https://github.com/thisisgm/omarchy-pods/blob/main/LICENSE)).

## Updating

Bump `PIN` in `build.sh`, run it. If a patch no longer applies the script aborts the `git am`, leaves the
checkout on the new pin and says so; then in the checkout: `git checkout -B dotfiles-patches <newpin>`, apply
and fix the patches by hand (`git am --3way`), `git format-patch -o config/librepods/patches <newpin>..HEAD`
(set the author to a noreply address, the repo is public), re-run `build.sh`.
