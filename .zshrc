## If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="/home/florian/.oh-my-zsh"
export PATH="$PATH:/bin:/usr/bin"

# VS Codium Flatpak Fixes
if [[ "$TERM_PROGRAM" == "vscodium" ]]; then
  # Ensure critical paths
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
  alias sudo='sudo -S'  
  # Initialize direnv
  if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
  fi
fi

if [[ "$TERM_PROGRAM" == "vscode" || -n "$VSCODE_INJECTION" ]]; then
    # Remove Snap's GIO modules path (fixes "undefined symbol" errors)
    unset GIO_MODULE_DIR
    # Remove GTK modules path (fixes "Failed to load module" warnings)
    unset GTK_MODULES
    # Optional: specific fixes for other Snap quirks
    unset GTK_IM_MODULE
fi

# Rest of your normal configuration...


# Docker "Nuke" Function
dkr() {
    if [ -z "$1" ]; then
        echo "Usage: dkr <name>"
    else
        echo "Stopping, removing, and deleting image for: $1..."
        docker stop "$1" 2>/dev/null && \
        docker rm "$1" 2>/dev/null && \
        docker rmi "$1"
    fi
}

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# direnv: load in and out environment when you cd
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi


# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
   git
   zsh-autosuggestions
   )

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
#
alias python=/usr/local/bin/python3.12
alias python3=/usr/local/bin/python3.12
alias pip=pip3
alias kitten='kitty +kitten'

# ~/.zshrc: your interactive zsh startup

# 1) Only run for interactive shells
[[ $- != *i* ]] && return

# 2) PATH
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

# Keep Python bytecode out of the stowed config dirs (~/.config/qtile, ranger
# plugins are symlinks into ~/.dotfiles, so __pycache__ would land in the repo).
export PYTHONPYCACHEPREFIX="$HOME/.cache/python-pycache"

# Supply-chain cooldown for uv: refuse Python packages published in the last
# 3 days. UV_EXCLUDE_NEWER is uv's global knob (applies to every uv command); it
# wants a fixed timestamp, so recompute it at each shell start to keep it a
# rolling ~3-day window without a per-command wrapper.
export UV_EXCLUDE_NEWER="$(date -v-3d +%Y-%m-%dT%H:%M:%SZ)"

# 3) History settings
HISTSIZE=1000
SAVEHIST=2000
setopt hist_ignore_dups      # no duplicate entries
setopt hist_ignore_space     # no entries starting with space
setopt append_history        # append, don’t overwrite
setopt inc_append_history    # write each command as you go


# 5) (Optional) recursive globstar
# setopt globstar

# 6) make less nicer
[[ -x /opt/bin/lesspipe ]] && eval "$(SHELL=/system/bin/sh lesspipe)"

# 7) Prompt
if (( EUID == 0 )); then
  PS1='%K{#DD4B39} $ %K{#0087AF}%F{#ffffff} %m %K{#535555}%F{#ffffff} %~ %K{#535555}%k%f '
else
  PS1='%K{#FF0000} $ %K{#800080}%K{#800080} %n@%m %K{#535555}%F{#ffffff} %~ %K{#535555}%k%f '
fi

# 8) Aliases
alias cp="cp -i"
alias df='df -h'
alias more=less

# FreeBSD base ls uses -G for colour (GNU's --color is rejected by base ls).
alias ls='ls -aG'
alias ll='ls -alFG'
alias la='ls -aG'
alias l='ls -CFG'

# system update (FreeBSD pkg; replaces the old dnf/flatpak/snap chain)
alias pkgu='sudo pkg update && sudo pkg upgrade'

# qtile helpers. qtile is a pkg (/usr/local/bin/qtile on PATH) - no venv here.
alias qcheck='qtile check'
alias qconf='vim ~/.config/qtile/config.py'
alias qlogs='tail -f ~/.local/share/qtile/qtile.log'
alias qstart='qtile start'
alias qrefresh='qtile cmd-obj -o . -f reload_config'

alias denv='nano ./.env'
alias treex="tree -I 'node_modules|dist|.git|.sonar|.scannerwork' --prune -a -C"

# 9) ex – archive extractor
ex() {
  if [[ -f $1 ]]; then
    case $1 in
      *.tar.bz2)   tar xjf $1 ;;
      *.tar.gz)    tar xzf $1 ;;
      *.bz2)       bunzip2 $1 ;;
      *.rar)       unrar x $1 ;;
      *.gz)        gunzip $1 ;;
      *.tar)       tar xf  $1 ;;
      *.tbz2)      tar xjf $1 ;;
      *.tgz)       tar xzf $1 ;;
      *.zip)       unzip  $1 ;;
      *.Z)         uncompress $1 ;;
      *.7z)        7z x $1 ;;
      *)           echo "'$1' cannot be extracted via ex()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# 10) colour support. FreeBSD colours ls via CLICOLOR (set above with -G); BSD
# grep does support --color=auto.
export CLICOLOR=1
alias grep='grep --color=auto'

# 11) source additional aliases if present
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases

# 12) enable bash-style completion (if you really need it)
if [[ -f /opt/etc/bash_completion ]]; then
  source /opt/etc/bash_completion
fi


# node/npm come from pkg on FreeBSD; nvm, bun and linuxbrew are not used here.

# fzf keybindings + completion (pkg fzf >= 0.48 ships the --zsh integration).
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh) 2>/dev/null

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

# system info banner on interactive shells (skip inside kitty's scrollback dumps)
command -v fastfetch >/dev/null 2>&1 && fastfetch

# opencode
export PATH=/home/florian/.opencode/bin:$PATH

# docker-ce-cli and docker-compose-plugin are still installed; the docker DAEMON
# is not. Point them at rootless podman's Docker-compatible API so the 19 compose
# files and 10+ project scripts keep working unmodified.
export DOCKER_HOST="unix:///run/user/1000/podman/podman.sock"

# Use podman's native build (buildah) instead of a containerized BuildKit.
# Compose v2 otherwise spins up moby/buildkit in a container, which has no access
# to the host trust store and therefore cannot verify the internal issuing CA
# that signs the private registry -> "x509: certificate signed by unknown authority".
# Podman builds on the host and uses /etc/pki/ca-trust directly.
# Verified: RUN --mount=type=cache still works through podman's compat API.
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0

# Maschinenlokale Werte (Secrets, interne Hosts/IPs), nicht im Repo.
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
