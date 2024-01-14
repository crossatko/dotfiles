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

# system
alias sleep="systemctl suspend"
alias :q="exit"
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

# docker
alias up="make build.all && make up.d"
alias down="make down"
alias on="up"
alias off="down"
alias startdocker="systemctl --user start docker-desktop"

#other
alias cc="clear"
alias ai="PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.6,max_split_size_mb:128 HSA_OVERRIDE_GFX_VERSION=10.3.0 python3 ~/code/ai/Fooocus/entry_with_update.py"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm

function calc() {
  echo "$*" | bc -l
}

eval "$(starship init zsh)"

eval "$(atuin init zsh)"
