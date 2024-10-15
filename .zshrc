export EDITOR="nvim"
export VISUAL="nvim"

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
	PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH="$HOME/.config/emacs/bin:$PATH"
export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$HOME/.cargo/bin
export PATH=$PATH:$HOME/.local/bin
export PATH=$PATH:$HOME/go/bin


export MOZ_DBUS_REMOTE=1

plugins=(git)

source $ZSH/oh-my-zsh.sh

pokemon-colorscripts -r --no-title

alias brave="brave-browser"

# system
alias sleep="systemctl suspend"
alias :q="exit"
alias dnfu="sudo dnf update"
alias dnfi="sudo dnf install"
# alias sudo="sudo "
# alias dnf="dnf5"

# dev
unset rc
alias lg="lazygit"
alias a="php artisan"
alias cu="composer update"
alias ci="composer install"
alias sa="cd ../api && a serve"
alias sail="./vendor/bin/sail"
alias vim="nvim"
alias v="nvim"
alias z="zellij"
alias "??"="gh copilot suggest"
alias "???"="gh copilot explain"

_code_completion() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local projects=$(ls "$HOME/code")

    COMPREPLY=($(compgen -W "$projects" -- "$cur"))
}

complete -F _code_completion code

code() {
    local project_path="$HOME/code/$1"
    if [ -d "$project_path" ]; then
        cd "$project_path" || return
        nvim
    else
        echo "Project not found in code folder."
    fi
}

# docker

# make build.all && 
alias up="make up.d"
alias down="make down"
alias on="up"
alias off="down"
alias startdocker="systemctl --user start docker-desktop"

#other
alias cc="clear"
alias ai="PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.6,max_split_size_mb:128 HSA_OVERRIDE_GFX_VERSION=10.3.0 python3 ~/code/ai/Fooocus/entry_with_update.py"
alias ls="lsd"
alias ll="lsd -la"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm

function calc() {
  echo "$*" | bc -l
}

# Function alias for yay
yay() {
  case "$1" in
    -S)
      shift
      sudo dnf install "$@"
      ;;
    -R)
      shift
      sudo dnf remove "$@"
      ;;
    -Sy)
      sudo dnf check-update
      ;;
    -Syu)
      sudo dnf update
      ;;
    -Ss)
      shift
      dnf search "$@"
      ;;
    -Su)
      sudo dnf upgrade "$@"
      ;;
    *)
      echo "Command not recognized: yay $@"
      ;;
  esac
}


imgs() {
    local width=${1:-}         # Optional width (first argument)
    local height               # To be set based on input
    local output_format         # To be set based on input (either third or second argument)

    # If the second argument is a number, it's height, otherwise it's the output format
    if [[ "$2" =~ ^[0-9]+$ ]]; then
        height=$2
        output_format=$3
    elif [[ -n "$1" && -n "$2" ]]; then
        height=$width  # If second argument is not a number, assume it's the format, so height defaults to width
        output_format=$2
    else
        height=$width  # If only one size is provided, assume square dimensions
    fi

    # If only output format is provided as first argument
    if [[ -z "$width" && -n "$1" ]]; then
        output_format=$1
    fi


    mkdir -p new

    for img in *.*(jpg|jpeg|png|gif|bmp|tiff|webp); do
        ext="${img##*.}"               # Get the original file extension
        filename="${img%.*}"           # Get the filename without extension
        output_ext=${output_format:-$ext}  # Use specified output format or original if not specified

        # Apply resizing if width (and height, automatically) are provided, otherwise just convert
        if [[ -n "$width" && -n "$height" ]]; then
            magick "$img" -resize "${width}x${height}>" "./new/${filename}.${output_ext}"
        else
            magick "$img" "./new/${filename}.${output_ext}"
        fi
    done
}

eval "$(starship init zsh)"

# eval "$(atuin init zsh)"
# eval "$(zellij setup --generate-auto-start zsh)"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
# eval "$(gh copilot alias -- zsh)"

# bun completions
[ -s "/home/crossatko/.bun/_bun" ] && source "/home/crossatko/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
