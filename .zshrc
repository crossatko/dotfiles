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
alias cd="z"
alias claudep='CLAUDE_CONFIG_DIR=~/.claude-personal claude --dangerously-skip-permissions'
alias claudew='CLAUDE_CONFIG_DIR=~/.claude claude --dangerously-skip-permissions'

# Zellij
# Auto-rename tab to current directory name
function _zellij_tab_name_update() {
  if [[ -n "$ZELLIJ" ]]; then
    local tab_name=${PWD##*/}
    [[ "$tab_name" == "" ]] && tab_name="/"
    command zellij action rename-tab "$tab_name"
  fi
}
add-zsh-hook chpwd _zellij_tab_name_update
# Also set on shell startup
_zellij_tab_name_update

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

# Convert all images in current directory to WebP
webp-all() {
  # Enable extended globbing (for #i) and nullglob (to avoid "no matches" errors)
  # 'localoptions' ensures these settings don't affect your whole shell session
  setopt localoptions extendedglob nullglob

  if ! command -v magick &> /dev/null; then
    echo "Error: ImageMagick is not installed."
    return 1
  fi

  # Find files. Now this will silently skip if a format is missing.
  local files=(*.(#i)(jpg|jpeg|png|tiff))

  if (( ${#files} == 0 )); then
    echo "No matching images found in the current directory."
    return 0
  fi

  for file in "${files[@]}"; do
    local output="${file%.*}.webp"
    echo "Converting: $file -> $output"
    magick "$file" -quality 75 "$output"
  done

  echo "Conversion complete!"
}

# Set NVM's home directory
export NVM_DIR="$HOME/.nvm"

# Source the nvm script provided by the Arch package
[ -s "/usr/share/nvm/init-nvm.sh" ] && . "/usr/share/nvm/init-nvm.sh"

# (Optional) This enables bash completion for nvm
[ -s "/usr/share/nvm/bash_completion" ] && . "/usr/share/nvm/bash_completion"

# Initialize Starship
eval "$(starship init zsh)"

# bun completions
[ -s "/home/kreejzak/.bun/_bun" ] && source "/home/kreejzak/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/kreejzak/.lmstudio/bin"
# End of LM Studio CLI section


if [ -e /home/kreejzak/.nix-profile/etc/profile.d/nix.sh ]; then . /home/kreejzak/.nix-profile/etc/profile.d/nix.sh; fi
export PATH="$HOME/.local/bin:$PATH"




# OpenRouter API key (used by minuet-ai.nvim for AI autocomplete in Neovim)
# The actual key lives in ~/.config/secrets/env (gitignored, not in the public dotfiles repo).
# Get one at: https://openrouter.ai/keys
[[ -f "$HOME/.config/secrets/env" ]] && source "$HOME/.config/secrets/env"

# Update system (yay) and flatpaks. Prompts for confirmation unless -y is passed.
update() {
  if [[ "$1" != "-y" ]]; then
    read -k 1 "REPLY?Update system and flatpaks? [Y/n] "
    [[ "$REPLY" != $'\n' ]] && echo
    [[ "$REPLY" == [nN] ]] && return 1
  fi
  yay -Syu --noconfirm && flatpak update -y
}
# >>> Photon CLI >>>
case ":$PATH:" in
  *:'/home/kreejzak/.photon/bin':*) ;;
  *) export PATH="$PATH":'/home/kreejzak/.photon/bin' ;;
esac
# <<< Photon CLI <<<
export ANDROID_HOME=/opt/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

# zoxide must stay last: its doctor warns if anything after it touches the chpwd hooks.
# Claude Code's shell snapshot keeps the `cd=z` alias but not the hook array, so mute the doctor there.
[[ -n "$CLAUDECODE" ]] && export _ZO_DOCTOR=0
eval "$(zoxide init zsh)"
