# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Bash port of .zshrc (kept in the repo so switching back is just chsh to zsh).
# Skipped on purpose: Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, bun's zsh completions.

# History: large, appended on every prompt (shared between shells), deduped, leading space = not saved
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
shopt -s histappend cmdhist

shopt -s checkwinsize globstar autocd 2>/dev/null

# Enable completions
if [ -r /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi

# Sudo: press Esc twice to prepend sudo to the current line (like the Oh My Zsh sudo plugin, without the toggle)
bind '"\e\e": "\C-asudo \C-e"'

# Aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias l='ls -lah'
alias la='ls -lAh'
alias ll='ls -lh'
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

# Git (the common Oh My Zsh git plugin aliases)
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gb='git branch'
alias gc='git commit --verbose'
alias gcmsg='git commit --message'
alias gco='git checkout'
alias gd='git diff'
alias gf='git fetch'
alias gl='git pull'
alias glog='git log --oneline --decorate --graph'
alias gp='git push'
alias gst='git status'
alias gsw='git switch'

# Zellij
# Auto-rename tab to current directory name
_zellij_last_pwd=
function _zellij_tab_name_update() {
  if [[ -n "$ZELLIJ" && "$PWD" != "$_zellij_last_pwd" ]]; then
    _zellij_last_pwd=$PWD
    local tab_name=${PWD##*/}
    [[ "$tab_name" == "" ]] && tab_name="/"
    command zellij action rename-tab "$tab_name"
  fi
}

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

  cat >"$filepath" <<EOF2
[Desktop Entry]
Version=1.0
Name=$app_name
Exec=brave --app="$app_url"
Terminal=false
Type=Application
Categories=Network;WebBrowser;
Icon=$app_icon
StartupNotify=true
EOF2
}

# Convert all images in current directory to WebP
webp-all() {
  if ! command -v magick &> /dev/null; then
    echo "Error: ImageMagick is not installed."
    return 1
  fi

  # Case-insensitive globbing and no "no matches" literal; restored on return
  local old_nocase old_null
  old_nocase=$(shopt -p nocaseglob); old_null=$(shopt -p nullglob)
  shopt -s nocaseglob nullglob
  local files=(*.jpg *.jpeg *.png *.tiff)
  eval "$old_nocase; $old_null"

  if (( ${#files[@]} == 0 )); then
    echo "No matching images found in the current directory."
    return 0
  fi

  local file output
  for file in "${files[@]}"; do
    output="${file%.*}.webp"
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
eval "$(starship init bash)"

# Prompt hooks (added after starship, which rewrites PROMPT_COMMAND): append history after every command,
# and rename the zellij tab (bash has no chpwd hook, so check on every prompt; also covers shell startup)
PROMPT_COMMAND+=("history -a" _zellij_tab_name_update)

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Added by LM Studio CLI (lms)
case ":$PATH:" in
  *:"$HOME/.lmstudio/bin":*) ;;
  *) export PATH="$PATH:$HOME/.lmstudio/bin" ;;
esac
# End of LM Studio CLI section

if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then . "$HOME/.nix-profile/etc/profile.d/nix.sh"; fi
export PATH="$HOME/.local/bin:$PATH"

# OpenRouter API key (used by minuet-ai.nvim for AI autocomplete in Neovim)
# The actual key lives in ~/.config/secrets/env (gitignored, not in the public dotfiles repo).
# Get one at: https://openrouter.ai/keys
[[ -f "$HOME/.config/secrets/env" ]] && source "$HOME/.config/secrets/env"

# Update system (yay) and flatpaks. Prompts for confirmation unless -y is passed.
update() {
  if [[ "$1" != "-y" ]]; then
    read -n 1 -p "Update system and flatpaks? [Y/n] " REPLY
    [[ -n "$REPLY" ]] && echo
    [[ "$REPLY" == [nN] ]] && return 1
  fi
  yay -Syu --noconfirm && flatpak update -y
}
# >>> Photon CLI >>>
case ":$PATH:" in
  *:"$HOME/.photon/bin":*) ;;
  *) export PATH="$PATH:$HOME/.photon/bin" ;;
esac
# <<< Photon CLI <<<
export ANDROID_HOME=/opt/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

# zoxide must stay last: its doctor warns if anything after it touches PROMPT_COMMAND.
# Claude Code's shell snapshot keeps the `cd=z` alias but not the hook, so mute the doctor there.
[[ -n "$CLAUDECODE" ]] && export _ZO_DOCTOR=0
eval "$(zoxide init bash)"
