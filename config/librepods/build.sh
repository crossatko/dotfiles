#!/bin/bash
# Builds the librepods AirPods daemon from upstream omarchy-pods (pinned) plus the patches in ./patches
# and installs it to ~/.local. Idempotent. See README.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/thisisgm/omarchy-pods"
PIN="fff7fec600a5b9a61cdb40e93eccbcceb4b8f824"
SRC="${LIBREPODS_SRC:-$HOME/code/crossatko/upstream/omarchy-pods}"
PREFIX="$HOME/.local"
BRANCH="dotfiles-patches"

missing=()
command -v git >/dev/null || missing+=(git)
command -v cmake >/dev/null || missing+=(cmake)
command -v ninja >/dev/null || missing+=(ninja)
pacman -Q qt6-connectivity >/dev/null 2>&1 || missing+=(qt6-connectivity)
if [ ${#missing[@]} -gt 0 ]; then
  echo "librepods: missing build dependencies: ${missing[*]}" >&2
  exit 1
fi

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone "$REPO_URL" "$SRC"
fi
cd "$SRC"

if ! git cat-file -e "$PIN^{commit}" 2>/dev/null; then
  git fetch origin
fi

# Marker: pin + hash of the patch series, kept in .git so it never shows up in the work tree.
series="$PIN $(cat "$HERE"/patches/*.patch | sha256sum | cut -d' ' -f1)"
marker="$(git rev-parse --git-dir)/dotfiles-patches-applied"
if [ "$(cat "$marker" 2>/dev/null)" != "$series" ] || [ "$(git rev-parse --abbrev-ref HEAD)" != "$BRANCH" ]; then
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "librepods: $SRC has local changes, refusing to reset it" >&2
    exit 1
  fi
  git checkout -q -B "$BRANCH" "$PIN"
  # Patch authors are neutral; committer identity only matters locally.
  if ! git -c user.name="dotfiles" -c user.email="noreply@example.com" am -q "$HERE"/patches/*.patch; then
    git am --abort || true
    git checkout -q -B "$BRANCH" "$PIN"
    echo "librepods: patches in $HERE/patches do not apply to $PIN, rebase them (see README.md)" >&2
    exit 1
  fi
  echo "$series" >"$marker"
  echo "librepods: applied patches on ${PIN:0:7}"
fi

build="$SRC/build-daemon"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! { cmake -S daemon -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" &&
  cmake --build "$build"; } >"$log" 2>&1; then
  tail -n 40 "$log" >&2
  echo "librepods: build failed" >&2
  exit 1
fi

bin="$PREFIX/bin/librepods"
before="$(sha256sum "$bin" 2>/dev/null | cut -d' ' -f1 || true)"
cmake --install "$build" >/dev/null
# The unit is linked from the dotfiles (install.sh); the copy cmake drops would shadow it.
rm -f "$PREFIX/share/systemd/user/librepods.service"
rmdir "$PREFIX/share/systemd/user" 2>/dev/null || true
after="$(sha256sum "$bin" | cut -d' ' -f1)"

systemctl --user daemon-reload
if [ "$before" != "$after" ] && systemctl --user is-active --quiet librepods.service; then
  systemctl --user restart librepods.service
  echo "librepods: installed new build, service restarted"
fi
