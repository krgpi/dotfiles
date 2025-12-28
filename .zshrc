zmodload zsh/zprof
source ~/Developer/zsh-defer/zsh-defer.plugin.zsh

# 1. Homebrewのパス判定 (ここは最速で通すべき)
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    export BREW_PREFIX="/home/linuxbrew/.linuxbrew"
elif [[ -x /usr/local/bin/brew ]]; then
    export BREW_PREFIX="/usr/local/bin"
fi

# 2. 補完システムの高速初期化
# ※ prompt_subst のタイポを修正
setopt prompt_subst
PS1="%F{12}%~%f "
RPS1="%F{240}loading%f"

setup_completions() {
    autoload -Uz compinit
    if [[ -f "$zcompdump" && $(date -r "$zcompdump" +%s) -gt $(( $(date +%s) - 86400 )) ]]; then
        compinit -C -d "$zcompdump"
    else
        compinit -i -d "$zcompdump"
        touch "$zcompdump"
    fi
}
zsh-defer setup_completions

# 補完設定
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# tmuxの設定 (execするのでここより下は実行されない)
if [ -z "$TMUX" ] && [ -z "$SSH_CONNECTION" ] && [ -z "$KRGPI_FROM_TMUX" ]; then
    exec tmux
fi

# PATH設定
export PATH="$BREW_PREFIX/bin:$PATH"
export PATH="$HOME/.asdf/shims:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

# prompt / vcs_info
autoload -Uz vcs_info
setopt prompt_subst
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:*' formats "%F{green}[%b]%f"
precmd() { vcs_info }

PROMPT='%F{red}%*%f:%F{magenta}$(uname -p)%f %F{cyan}%~%f $ '
RPROMPT='${vcs_info_msg_0_}'
# alias
alias la='ls -a'
alias ll='ls -l'
alias lg='lazygit'
# 3. 外部ツールの初期化を defer 化
# starship と direnv は add-zsh-hook を多用するため、ここを遅延させると zprof の数値が下がります
# eval "$(starship init zsh)"
zsh-defer eval "$(direnv hook zsh)"

# 4. asdf / Cargo
zsh-defer source "$BREW_PREFIX/opt/asdf/libexec/asdf.sh" 2>/dev/null
[[ -f "$HOME/.cargo/env" ]] && zsh-defer source "$HOME/.cargo/env"

# 5. gh completion
if (( $+commands[gh] )); then
    # eval を直接 zsh-defer に渡す
    zsh-defer eval "$(gh completion -s zsh)"
fi

# 6. fzf-tab
[[ -f ~/Developer/fzf-tab/fzf-tab.plugin.zsh ]] && zsh-defer source ~/Developer/fzf-tab/fzf-tab.plugin.zsh

# 最後に zprof を表示
zsh-defer zprof
