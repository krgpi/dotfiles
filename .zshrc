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

autoload -Uz vcs_info
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr "%F{yellow} %f"
zstyle ':vcs_info:git:*' unstagedstr "%F{red} %f"
zstyle ':vcs_info:*' formats "%F{green} %b%f%c%u"
zstyle ':vcs_info:*' actionformats "%F{green} %b|%a%f%c%u"
precmd() { vcs_info }
PROMPT='%F{red}%*%f %F{cyan}%1~%f ${vcs_info_msg_0_}
 > '
RPROMPT=''


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
alias cc='claude'
alias nv='nvim'
alias bu='brew upgrade'
alias dev="~/Developer/dotfiles/tmux-dev-layout.sh"

[[ -f "$HOME/Developer/dotfiles/.env" ]] && source "$HOME/Developer/dotfiles/.env"
