#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$DOTFILES_DIR/config"

echo "Enabling multilib repository for 32-bit gaming packages..."
# Uncomment [multilib] and the Include line directly below it
sudo sed -i '/^#\[multilib\]/s/^#//' /etc/pacman.conf
sudo sed -i '/^\[multilib\]/,/^#Include/s/^#Include/Include/' /etc/pacman.conf

echo "Syncing repositories and installing prerequisites..."
sudo pacman -Sy --needed --noconfirm base-devel git

# The repo is public: enable the privacy pre-commit hook (.githooks/pre-commit) for this clone
git -C "$DOTFILES_DIR" config core.hooksPath .githooks

echo "Setting up yay..."
if ! command -v yay &>/dev/null; then
  echo "Installing yay from AUR..."
  rm -rf /tmp/yay
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd -
fi

echo "Installing packages..."

# Define all packages in an array so we can cleanly use comments and newlines
PACKAGES=(
  # Base development tools
  wget curl neovim vim btop ffmpeg python nodejs jq php mariadb redis yarn
  libappindicator-gtk3 ddcutil tailscale tableplus

  # Fonts & Theming
  ttf-comic-shanns-nerd noto-fonts noto-fonts-cjk
  gnome-themes-extra qt5-wayland qt6-wayland dconf

  # Terminal & Shell
  zellij rust rust-wasm fzf wl-clipboard cliphist kitty zsh starship fastfetch bash-completion zsh-completions
  zsh-autosuggestions zsh-syntax-highlighting libqalculate

  # Hyprland Ecosystem
  quickshell imagemagick hyprland hyprpaper hypridle hyprlock hyprpolkitagent hyprshot wf-recorder slurp
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal-gnome
  bibata-cursor-theme

  # GUI Apps (Swapped appimagelauncher for gearlever)
  thunderbird mpv pavucontrol network-manager-applet yazi nautilus
  gnome-disk-utility libreoffice-fresh ark zip unzip unrar p7zip gzip
  playerctl anki

  # Security & Network
  ufw 1password brave-bin firefox epiphany

  # Graphics & Gaming
  mangohud gamescope steam gamemode

  # Containers & Virtualization
  docker docker-compose

  # Flatpak
  flatpak

  # Misc
  tldr

  # Services
  blueman bluez bluez-utils
)

# Install all packages directly with yay
yay -S --needed --noconfirm "${PACKAGES[@]}"

# Enable system services
echo "Enabling system services..."
sudo systemctl enable bluetooth
sudo systemctl enable --now tailscaled
sudo systemctl enable --now docker
sudo systemctl enable ufw

# Configure Firewall
echo "Configuring UFW Firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

# Setup Docker permissions
echo "Configuring Docker permissions..."
sudo usermod -aG docker "$USER"

# Setup Flathub and install Flatpak apps
echo "Configuring Flathub and installing Discord & Spotify..."
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.discordapp.Discord
flatpak install -y flathub com.spotify.Client
flatpak install -y flathub org.jellyfin.JellyfinDesktop
flatpak install -y flathub com.vysp3r.ProtonPlus

# System-wide Environment Variable setup via Hostname
RAW_HOSTNAME=$(cat /etc/hostname | tr -d '\n')
FORMATTED_HOST=$(echo "$RAW_HOSTNAME" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | sed 's/-/_/g' | tr '[:lower:]' '[:upper:]')
HOST_VAR="HOST_${FORMATTED_HOST}"

echo "Detected hostname '$RAW_HOSTNAME'. Setting system-wide environment variables..."
sudo sed -i '/^HOST_/d' /etc/environment
sudo sed -i '/^QT_QPA_PLATFORMTHEME/d' /etc/environment
echo "$HOST_VAR=1" | sudo tee -a /etc/environment
echo "QT_QPA_PLATFORMTHEME=gtk3" | sudo tee -a /etc/environment # Forces Qt to use GTK styling

# Symlink config files with backup logic
echo "Symlinking config files..."
mkdir -p "$HOME/.config"

CONFIG_APPS=("hypr" "nvim" "kitty" "zellij" "theme" "quickshell" "opencode" "wivrn")

for app in "${CONFIG_APPS[@]}"; do
  TARGET="$HOME/.config/$app"
  SOURCE="$CONFIG_DIR/$app"

  if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    echo "  Backing up existing $app to ${app}_backup..."
    rm -rf "${TARGET}_backup"
    mv "$TARGET" "${TARGET}_backup"
  fi

  echo "  Symlinking $app..."
  ln -s "$SOURCE" "$TARGET"
done

# Zellij claude-tabs plugin (tab bar with a Claude icon / ding / agent counts): standalone package, its own
# repo, checked out at ~/code/crossatko/zellij-wc3cz-claude (override: CLAUDE_TABS_DIR). Its setup.sh links
# ~/.config/zellij/plugins/claude-tabs to the checkout, installs the WC3 icon font, pre-grants the plugin
# permissions and adds the Claude Code hooks. Without the checkout zellij needs default_layout "compact".
CLAUDE_TABS_DIR=${CLAUDE_TABS_DIR:-$HOME/code/crossatko/zellij-wc3cz-claude}
if [ -f "$CLAUDE_TABS_DIR/setup.sh" ]; then
  sh "$CLAUDE_TABS_DIR/setup.sh" || echo "  claude-tabs setup failed (use default_layout 'compact' as a fallback)"
else
  echo "  claude-tabs package not found at $CLAUDE_TABS_DIR: clone it and run its setup.sh, or set default_layout 'compact' in config/zellij/config.kdl"
fi

# Nautilus right-click scripts (Scripts -> Send via LocalSend)
mkdir -p "$HOME/.local/share/nautilus/scripts"
for s in "$CONFIG_DIR"/nautilus/scripts/*; do
  ln -sfn "$s" "$HOME/.local/share/nautilus/scripts/$(basename "$s")"
done


# Launcher script commands (executable scripts with "# @launcher.*" headers, see config/quickshell/launcher/ScriptSource.qml).
# Only the commands dir is linked: ~/.config/launcher also holds the user's config.json.
mkdir -p "$HOME/.config/launcher"
ln -sfn "$CONFIG_DIR/launcher/commands" "$HOME/.config/launcher/commands"

# Portal routing (screen sharing pinned to hyprland, file dialogs -> Nautilus chooser) and the GNOME portal
# unit override: Hyprland never activates graphical-session.target, which the packaged unit requires
mkdir -p "$HOME/.config/xdg-desktop-portal" "$HOME/.config/systemd/user"
ln -sfn "$CONFIG_DIR/xdg-desktop-portal/portals.conf" "$HOME/.config/xdg-desktop-portal/portals.conf"
ln -sfn "$CONFIG_DIR/systemd/user/xdg-desktop-portal-gnome.service" "$HOME/.config/systemd/user/xdg-desktop-portal-gnome.service"

# Launcher shim: applies the wallpaper theme to Brave's profile just before it starts
mkdir -p "$HOME/.local/bin"
ln -sfn "$CONFIG_DIR/theme/bin/brave" "$HOME/.local/bin/brave"
# Jellyfin helper for the launcher (config: ~/.config/jellyfin-qs, login: jellyfin-qs login)
ln -sfn "$CONFIG_DIR/launcher/jellyfin/bin/jellyfin-qs" "$HOME/.local/bin/jellyfin-qs"

# Firefox: translucent header (userChrome.css + user.js) in the install-default profile, if one exists
FF_PROFILE_DIR="$HOME/.config/mozilla/firefox"
if [ -f "$FF_PROFILE_DIR/profiles.ini" ]; then
  FF_PROFILE="$(awk -F= '/^\[Install/{i=1} i&&/^Default=/{print $2; exit}' "$FF_PROFILE_DIR/profiles.ini")"
  if [ -n "$FF_PROFILE" ] && [ -d "$FF_PROFILE_DIR/$FF_PROFILE" ]; then
    mkdir -p "$FF_PROFILE_DIR/$FF_PROFILE/chrome"
    ln -sfn "$CONFIG_DIR/firefox/userChrome.css" "$FF_PROFILE_DIR/$FF_PROFILE/chrome/userChrome.css"
    ln -sfn "$CONFIG_DIR/firefox/user.js" "$FF_PROFILE_DIR/$FF_PROFILE/user.js"
  fi
fi

# Generate every app's colors from the wallpaper (see config/theme/README.md)
python3 -I "$CONFIG_DIR/theme/theme.py" render || true

# Chromium 141+ enables the WaylandWpColorManagerV1 protocol by default,
# which fights with Hyprland's own dcip3 color management and makes
# Brave render bland/shifted colors. brave-flags.conf disables it.
if [ -e "$HOME/.config/brave-flags.conf" ] || [ -L "$HOME/.config/brave-flags.conf" ]; then
  rm -f "$HOME/.config/brave-flags.conf"
fi
ln -s "$CONFIG_DIR/brave-flags.conf" "$HOME/.config/brave-flags.conf"

# --- THEMING SETUP ---
echo "Applying GTK Dark Theme and Icons..."
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

# 1. Legacy GTK 3 & 4 settings.ini (Still needed for some older apps)
cat >"$HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-application-prefer-dark-theme=1
EOF

cp "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"

cat >"$HOME/.gtkrc-2.0" <<EOF
gtk-theme-name="Adwaita-dark"
gtk-icon-theme-name="Adwaita"
gtk-cursor-theme-name="Bibata-Modern-Classic"
EOF

# 2. Modern GTK4 / libadwaita standard gsettings (This fixes GTK4 dark mode)
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'

# GTK bookmarks
cat >"$HOME/.config/gtk-3.0/bookmarks" <<'EOF'
file:///home/kreejzak/Documents
file:///home/kreejzak/Downloads
file:///home/kreejzak/Music
file:///home/kreejzak/Pictures
file:///home/kreejzak/Videos
file:///home/kreejzak/code
EOF

# Create user directories
mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/Music" "$HOME/Pictures" "$HOME/Videos" "$HOME/code"

# --- ZSH & STARSHIP SETUP ---
echo "Configuring Zsh, Oh My Zsh, and Starship..."

# Install Oh My Zsh non-interactively
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Generate .zshrc
cat >"$HOME/.zshrc" <<'EOF'
# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
plugins=(git sudo)
source $ZSH/oh-my-zsh.sh

# Arch Linux specific plugin paths for syntax highlighting and autosuggestions
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Enable completions
autoload -Uz compinit
compinit

# Aliases
alias udd="update-desktop-database ~/.local/share/applications"

# Nix-specific Alias (Only works if Nix package manager is installed on this Arch system)
alias nix-cleanup="sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +5 && sudo nix-collect-garbage -d"

alias :q="exit"
alias vim="nvim"
alias up="make up"
alias upd="make up.d"
alias down="make down"
alias killdocker='docker kill $(docker ps -q)'
alias kd='docker kill $(docker ps -q)'

# Initialize Starship
eval "$(starship init zsh)"
EOF

# Generate starship.toml
cat >"$HOME/.config/starship.toml" <<'EOF'
add_newline = true
EOF

# Set default shell to zsh
echo "Changing default shell to zsh..."
chsh -s /bin/zsh

# --- WEB APPS SETUP ---
echo "Creating Brave Web Apps..."

create_brave_webapp() {
  local app_name="$1"
  local app_url="$2"
  # Default to the brave icon if a specific one isn't passed
  local app_icon="${3:-brave}"

  # Format the filename to be lowercase and replace spaces with underscores
  local filename=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
  local filepath="$HOME/.local/share/applications/webapp_${filename}.desktop"

  echo "  Adding $app_name ($app_url)..."
  mkdir -p "$HOME/.local/share/applications"

  cat >"$filepath" <<EOF
[Desktop Entry]
Version=1.0
Name=$app_name
Exec=brave --app="$app_url"
Terminal=false
Type=Application
Categories=Network;WebBrowser;
Icon=$app_icon
StartupNotify=true
EOF
}

# Create specific web apps here
create_brave_webapp "Figma" "https://www.figma.com"
create_brave_webapp "Linear" "https://linear.app"

# Update desktop database so the new web apps (and anything else) appear in your launcher
echo "Updating desktop database..."
update-desktop-database ~/.local/share/applications 2>/dev/null || true

# Clean up package cache to free up space
echo "Cleaning up yay cache..."
yay -Sc --noconfirm
# The WC3 icon font (pairs with the symbol_map line in kitty.conf) is installed to ~/.local/share/fonts by
# the claude-tabs setup.sh call above.
fc-cache -fv

echo "Installation complete!"
echo "You may need to log out and log back in (required to apply Docker permissions, theming, and the new $HOST_VAR environment variable)"
