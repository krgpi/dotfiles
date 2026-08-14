source ~/Developer/zsh-defer/zsh-defer.plugin.zsh

if [[ -x /opt/homebrew/bin/brew ]]; then
    export BREW_PREFIX="/opt/homebrew"
elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    export BREW_PREFIX="/home/linuxbrew/.linuxbrew"
elif [[ -x /usr/local/bin/brew ]]; then
    export BREW_PREFIX="/usr/local"
fi

setopt prompt_subst
export PATH="$BREW_PREFIX/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"
export EDITOR="nvim"

autoload -Uz vcs_info
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr "%F{yellow} %f"
zstyle ':vcs_info:git:*' unstagedstr "%F{red} %f"
zstyle ':vcs_info:*' formats "%F{green} %b%f%c%u"
zstyle ':vcs_info:*' actionformats "%F{green} %b|%a%f%c%u"
_git_remote_status() {
    git rev-parse --is-inside-work-tree &>/dev/null || return
    local upstream=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null) || return
    local counts=$(git rev-list --count --left-right "${upstream}...HEAD" 2>/dev/null) || return
    local behind=${counts%%	*}
    local ahead=${counts##*	}
    local result=""
    [[ "$behind" -gt 0 ]] && result+="%F{magenta}⇣${behind}%f"
    [[ "$ahead" -gt 0 ]] && result+="%F{magenta}⇡${ahead}%f"
    echo "$result"
}

_git_fetch_bg() {
    git rev-parse --is-inside-work-tree &>/dev/null || return
    local git_dir=$(git rev-parse --git-dir 2>/dev/null) || return
    local fetch_marker="${git_dir}/.last_bg_fetch"
    local now=$(date +%s)
    local last_fetch=0
    [[ -f "$fetch_marker" ]] && last_fetch=$(cat "$fetch_marker" 2>/dev/null)
    if (( now - last_fetch > 300 )); then
        echo "$now" > "$fetch_marker"
        git fetch --quiet &>/dev/null &!
    fi
}

precmd() {
    vcs_info
    _git_fetch_bg
    _GIT_REMOTE_STATUS=$(_git_remote_status)
}
PROMPT='%F{red}%*%f %F{cyan}%1~%f ${vcs_info_msg_0_}${_GIT_REMOTE_STATUS} %F{yellow}%m%f
 > '
RPROMPT=''


deferred_settings() {
    zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

    autoload -Uz compinit
    local zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
    local zcompdump_age=0
    if [[ -f "$zcompdump" ]]; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            zcompdump_age=$(date -r "$zcompdump" +%s)
        else
            zcompdump_age=$(stat -c %Y "$zcompdump")
        fi
    fi
    if [[ -f "$zcompdump" && $zcompdump_age -gt $(( $(date +%s) - 86400 )) ]]; then
        compinit -C -d "$zcompdump"
    else
        compinit -i -d "$zcompdump"
        touch "$zcompdump"
    fi

    eval "$(direnv hook zsh)"
    
    [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

    if (( $+commands[gh] )); then
        eval "$(gh completion -s zsh)"
    fi

    [[ -f ~/Developer/fzf-tab/fzf-tab.plugin.zsh ]] && source ~/Developer/fzf-tab/fzf-tab.plugin.zsh
    eval "$(mise activate zsh)"    
}

zsh-defer deferred_settings

alias la='ls -a'
alias ll='ls -l'
alias lg='lazygit'
alias cl='claude'
alias clt='CLAUDE_CONFIG_DIR=~/.claude-work claude'
paseo-work() { paseo run --env "CLAUDE_CONFIG_DIR=$HOME/.claude-work" "$@"; }
alias nv='nvim'
if (( $+commands[brew] )); then
    alias bu='brew upgrade'
fi
dev() {
    ~/Developer/dotfiles/tmux-dev-layout.sh "$@"
}

cd() {
    if [[ $# -eq 0 ]]; then
        builtin cd ~/Developer
    else
        builtin cd "$@"
    fi
}

[[ -f "$HOME/Developer/dotfiles/.env" ]] && source "$HOME/Developer/dotfiles/.env"

if [[ "$(uname -s)" == "Darwin" ]]; then
    alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"
else
    alias pbcopy="xclip -selection clipboard"
    alias pbpaste="xclip -selection clipboard -o"
fi

export PATH="$HOME/.deno/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

[[ -f "$HOME/Developer/dotfiles/.zshrc.local" ]] && source "$HOME/Developer/dotfiles/.zshrc.local"

