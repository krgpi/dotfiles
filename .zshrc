if [ -z "$TMUX" ] && [ -z "$SSH_CONNECTION" ] && [ -z "$KRGPI_FROM_TMUX" ]; then
  exec tmux
fi

source ~/Developer/zsh-defer/zsh-defer.plugin.zsh

if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    export BREW_PREFIX="/home/linuxbrew/.linuxbrew"
elif [[ -x /usr/local/bin/brew ]]; then
    export BREW_PREFIX="/usr/local/bin"
fi

setopt prompt_subst
export PATH="$BREW_PREFIX/bin:$HOME/.asdf/shims:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

autoload -Uz vcs_info
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:*' formats "%F{green}[%b]%f"
precmd() { vcs_info }

PROMPT='%F{red}%*%f:%F{magenta}$(uname -p)%f %F{cyan}%~%f $ '
RPROMPT='${vcs_info_msg_0_}'


deferred_settings() {
    zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

    autoload -Uz compinit
    local zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
    if [[ -f "$zcompdump" && $(date -r "$zcompdump" +%s) -gt $(( $(date +%s) - 86400 )) ]]; then
        compinit -C -d "$zcompdump"
    else
        compinit -i -d "$zcompdump"
        touch "$zcompdump"
    fi

    eval "$(direnv hook zsh)"
    
    [[ -f "$BREW_PREFIX/opt/asdf/libexec/asdf.sh" ]] && . "$BREW_PREFIX/opt/asdf/libexec/asdf.sh"
    [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

    if (( $+commands[gh] )); then
        eval "$(gh completion -s zsh)"
    fi

    [[ -f ~/Developer/fzf-tab/fzf-tab.plugin.zsh ]] && source ~/Developer/fzf-tab/fzf-tab.plugin.zsh
}

zsh-defer deferred_settings

alias la='ls -a'
alias ll='ls -l'
alias lg='lazygit'
