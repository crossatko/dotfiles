# dotfiles

My personal setup: a Hyprland + Quickshell desktop on Arch Linux, with a smaller macOS setup
maintained alongside it. Linux is the main target. Feel free to borrow anything you like.

## Layout

```
config/       app configs, linked into ~/.config (one directory per app)
system/       root-owned files (udev rules, ...), installed only on request
packages/     pacman.txt, aur.txt, flatpak.txt
install.sh    the Arch Linux installer
AGENTS.md     how everything works
```

## Install (Arch Linux)

```sh
git clone <this repo> ~/dotfiles
cd ~/dotfiles
./install.sh --dry-run   # see what it would do, changes nothing
./install.sh
```

The installer works in stages: `repos`, `packages`, `links` and `system`. It is safe to re-run. `repos` and `system`
are opt-in: `repos` adds the third-party CachyOS and Chaotic-AUR repos to `pacman.conf` (`--repos`, nothing in
`packages/*.txt` needs it); `system` touches root-owned files (`--system`). `./install.sh --help` lists the rest.

A few things, like the Hyprland fork and licensed fonts, are manual. The comments in `packages/*.txt`
say which.

## macOS

Run `./install-mac.sh` (`--dry-run` to preview) to symlink the Mac configs (aerospace, karabiner, ghostty,
kitty, nvim, ...). It only links: no brew, no `defaults`, no sudo.

## Good to know

- `AGENTS.md` explains how the pieces fit together and how to work on them.
- A git hook keeps machine-specific details out of this public repo.
- Third-party assets are credited in `config/quickshell/assets/CREDITS.md`.
