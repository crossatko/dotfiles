#!/usr/bin/env bash
# @launcher.title Open dotfiles in terminal
# @launcher.subtitle Shell in ~/dotfiles
# @launcher.aliases dotfiles, config
# @launcher.mode terminal
cd "$HOME/dotfiles" || exit 1
exec "${SHELL:-bash}"
