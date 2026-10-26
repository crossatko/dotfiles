#!/bin/bash
# macOS installer for these dotfiles: only symlinks the configs the Mac uses, nothing else (no brew, no
# defaults, no sudo). Idempotent; an existing real file or directory is moved to <name>.bak.<timestamp> once.
#
#   ./install-mac.sh [-n|--dry-run] [-h|--help]
#
# Not linked: swiftbar (needs `defaults write`, see AGENTS.md); run config/theme/bin/theme-seed by hand.
# DOTFILES_FORCE=1 skips the Darwin check (for tests; use with a throwaway HOME).
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$DOTFILES_DIR/config"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=0
CHANGED=0
SAME=0

case "${1:-}" in
  -n|--dry-run) DRY=1 ;;
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if [ "$(uname -s)" != Darwin ] && [ "${DOTFILES_FORCE:-}" != 1 ]; then
  echo "This installer is for macOS only (use install.sh on Arch)." >&2
  exit 1
fi

# link SRC DEST: make DEST a symlink to SRC
link() {
  local src="$1" dest="$2"
  if [ ! -e "$src" ]; then echo "missing source: $src" >&2; exit 1; fi
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "    ok      $dest"; SAME=$((SAME + 1)); return
  fi
  CHANGED=$((CHANGED + 1))
  if [ -L "$dest" ]; then
    echo "    relink  $dest -> $src (was $(readlink "$dest"))"
    [ "$DRY" = 1 ] || rm "$dest"
  elif [ -e "$dest" ]; then
    echo "    backup  $dest -> $dest.bak.$STAMP"
    [ "$DRY" = 1 ] || mv "$dest" "$dest.bak.$STAMP"
  else
    echo "    link    $dest -> $src"
  fi
  [ "$DRY" = 1 ] || { mkdir -p "$(dirname "$dest")" && ln -s "$src" "$dest"; }
}

for app in kitty nvim zellij herdr theme aerospace karabiner ghostty; do
  link "$CONFIG_DIR/$app" "$HOME/.config/$app"
done
# Ghostty reads this file on macOS only, after the shared config
link "$CONFIG_DIR/ghostty/macos.conf" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
link "$CONFIG_DIR/shell/zshrc" "$HOME/.zshrc"
link "$DOTFILES_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

# The repo is public: enable the privacy pre-commit hook for this clone
if [ "$(git -C "$DOTFILES_DIR" config --get core.hooksPath 2>/dev/null || true)" = .githooks ]; then
  echo "    ok      git core.hooksPath"
elif [ "$DRY" = 1 ]; then
  echo "    would set git core.hooksPath"
else
  git -C "$DOTFILES_DIR" config core.hooksPath .githooks && echo "    set     git core.hooksPath"
fi

echo "Done: $CHANGED changed, $SAME unchanged$([ "$DRY" = 1 ] && echo ' (dry run)')."
