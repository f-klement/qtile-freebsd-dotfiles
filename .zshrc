# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="/home/admin/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

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
# COMPLETION_WAITING_DOTS="true"

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
alias python=/usr/bin/python3.12
alias python3=/usr/bin/python3.12
alias pip=pip3

# ~/.zshrc: your interactive zsh startup

# 1) Only run for interactive shells
[[ $- != *i* ]] && return

# 2) PATH
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

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
  PS1='%K{#DD4B39} $ %K{#0087AF}%K{#ffffff} %m %K{#535555}%K{#ffffff} %~ %K{#535555}%k%f '
else
  PS1='%K{#FF0000} $ %K{#800080}%K{#800080} %n@%m %K{#535555}%K{#ffffff} %~ %K{#535555}%k%f '
fi

# 8) Aliases
alias cp="cp -i"
alias df='df -h'
alias free='free -m'
alias more=less

alias ll='ls -alF'
alias la='ls -a'
alias l='ls -CF'
alias ls='ls --color=auto -a'

alias qenv='source ~/.local/venvs/qtile/bin/activate'
alias qcheck='~/.local/venvs/qtile/bin/qtile check'
alias qconf='vim ~/.config/qtile/config.py'
alias qvalid='( source ~/.local/venvs/qtile/bin/activate && qtile check )'
alias qlogs='tail -f ~/.local/share/qtile/qtile.log'
alias qstart='~/.local/venvs/qtile/bin/qtile start'

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

# 10) enable color support for ls/grep if dircolors exists
if [[ -x /opt/bin/dircolors ]]; then
  [[ -r ~/.dircolors ]] && eval "$(dircolors -b ~/.dircolors)" \
                      || eval "$(dircolors -b)"
  alias ls='ls --color=auto -a'
  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# 11) source additional aliases if present
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases

# 12) enable bash-style completion (if you really need it)
if [[ -f /opt/etc/bash_completion ]]; then
  source /opt/etc/bash_completion
fi

