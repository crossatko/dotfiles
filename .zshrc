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


# shellcheck shell=bash

# =============================================================================
#
# Utility functions for zoxide.
#

# pwd based on the value of _ZO_RESOLVE_SYMLINKS.
function __zoxide_pwd() {
    \builtin pwd -L
}

# cd + custom logic based on the value of _ZO_ECHO.
function __zoxide_cd() {
    # shellcheck disable=SC2164
    \builtin cd -- "$@"
}

# =============================================================================
#
# Hook configuration for zoxide.
#

# Hook to add new entries to the database.
function __zoxide_hook() {
    # shellcheck disable=SC2312
    \command zoxide add -- "$(__zoxide_pwd)"
}

# Initialize hook.
\builtin typeset -ga precmd_functions
\builtin typeset -ga chpwd_functions
# shellcheck disable=SC2034,SC2296
precmd_functions=("${(@)precmd_functions:#__zoxide_hook}")
# shellcheck disable=SC2034,SC2296
chpwd_functions=("${(@)chpwd_functions:#__zoxide_hook}")
chpwd_functions+=(__zoxide_hook)

# Report common issues.
function __zoxide_doctor() {
    [[ ${_ZO_DOCTOR:-1} -ne 0 ]] || return 0
    [[ ${chpwd_functions[(Ie)__zoxide_hook]:-} -eq 0 ]] || return 0

    _ZO_DOCTOR=0
    \builtin printf '%s\n' \
        'zoxide: detected a possible configuration issue.' \
        'Please ensure that zoxide is initialized right at the end of your shell configuration file (usually ~/.zshrc).' \
        '' \
        'If the issue persists, consider filing an issue at:' \
        'https://github.com/ajeetdsouza/zoxide/issues' \
        '' \
        'Disable this message by setting _ZO_DOCTOR=0.' \
        '' >&2
}

# =============================================================================
#
# When using zoxide with --no-cmd, alias these internal functions as desired.
#

# Jump to a directory using only keywords.
function __zoxide_z() {
    __zoxide_doctor
    if [[ "$#" -eq 0 ]]; then
        __zoxide_cd ~
    elif [[ "$#" -eq 1 ]] && { [[ -d "$1" ]] || [[ "$1" = '-' ]] || [[ "$1" =~ ^[-+][0-9]+$ ]]; }; then
        __zoxide_cd "$1"
    elif [[ "$#" -eq 2 ]] && [[ "$1" = "--" ]]; then
        __zoxide_cd "$2"
    else
        \builtin local result
        # shellcheck disable=SC2312
        result="$(\command zoxide query --exclude "$(__zoxide_pwd)" -- "$@")" && __zoxide_cd "${result}"
    fi
}

# Jump to a directory using interactive search.
function __zoxide_zi() {
    __zoxide_doctor
    \builtin local result
    result="$(\command zoxide query --interactive -- "$@")" && __zoxide_cd "${result}"
}

# =============================================================================
#
# Commands for zoxide. Disable these using --no-cmd.
#

function z() {
    __zoxide_z "$@"
}

function zi() {
    __zoxide_zi "$@"
}

# Completions.
if [[ -o zle ]]; then
    __zoxide_result=''

    function __zoxide_z_complete() {
        # Only show completions when the cursor is at the end of the line.
        # shellcheck disable=SC2154
        [[ "${#words[@]}" -eq "${CURRENT}" ]] || return 0

        if [[ "${#words[@]}" -eq 2 ]]; then
            # Show completions for local directories.
            _cd -/

        elif [[ "${words[-1]}" == '' ]]; then
            # Show completions for Space-Tab.
            # shellcheck disable=SC2086
            __zoxide_result="$(\command zoxide query --exclude "$(__zoxide_pwd || \builtin true)" --interactive -- ${words[2,-1]})" || __zoxide_result=''

            # Set a result to ensure completion doesn't re-run
            compadd -Q ""

            # Bind '\e[0n' to helper function.
            \builtin bindkey '\e[0n' '__zoxide_z_complete_helper'
            # Sends query device status code, which results in a '\e[0n' being sent to console input.
            \builtin printf '\e[5n'

            # Report that the completion was successful, so that we don't fall back
            # to another completion function.
            return 0
        fi
    }

    function __zoxide_z_complete_helper() {
        if [[ -n "${__zoxide_result}" ]]; then
            # shellcheck disable=SC2034,SC2296
            BUFFER="z ${(q-)__zoxide_result}"
            __zoxide_result=''
            \builtin zle reset-prompt
            \builtin zle accept-line
        else
            \builtin zle reset-prompt
        fi
    }
    \builtin zle -N __zoxide_z_complete_helper

    [[ "${+functions[compdef]}" -ne 0 ]] && \compdef __zoxide_z_complete z
fi

# =============================================================================
#
# To initialize zoxide, add this to your shell configuration file (usually ~/.zshrc):
#
# eval "$(zoxide init zsh)"


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
