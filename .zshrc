zmodload zsh/zprof
source ~/Developer/zsh-defer/zsh-defer.plugin.zsh
# 1. Homebrewのパスを判定
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  export BREW_PREFIX="/home/linuxbrew/.linuxbrew"
elif [[ -x /usr/local/bin/brew ]]; then
  export BREW_PREFIX="/usr/local/bin"
fi

# 2. 補完システムの高速初期化
PS1="%F{12}%~%f "
RPS1="%F{240}loading%f"
setopt promp_subst

zsh-defer autoload -Uz compinit
zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"

# セキュリティチェックをスキップし、かつ読み込みを高速化
# -i: 不適切な権限のファイルを無視
# -C: キャッシュが新しい場合はチェックをスキップ
if [[ -f "$zcompdump" && $(date -r "$zcompdump" +%s) -gt $(( $(date +%s) - 86400 )) ]]; then
  zsh-defer compinit -C -d "$zcompdump"
else
  zsh-defer compinit -i -d "$zcompdump"
  touch "$zcompdump"
fi

# 補完設定
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
setopt prompt_subst

# tmuxの設定
if [ -z "$TMUX" ] && [ -z "$SSH_CONNECTION" ] && [ -z "$KRGPI_FROM_TMUX" ]; then
  exec tmux
fi

# PATH設定
export PATH="$BREW_PREFIX/bin:$PATH"
export PATH="$HOME/.asdf/shims:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

# prompt / vcs_info
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr "%F{yellow}!"
zstyle ':vcs_info:git:*' unstagedstr "%F{red}+"
zstyle ':vcs_info:*' formats "%F{green}%c%u[%b]%f"
precmd() { vcs_info }
PROMPT='%F{red}%*%f:%F{magenta}$(uname -p)%f %F{cyan}%.%f $ '
RPROMPT='${vcs_info_msg_0_}'

# alias
alias la='ls -a'
alias ll='ls -l'
alias lg='lazygit'

# 3. asdf / Cargo (ファイル存在チェックを維持)
[[ -f "$BREW_PREFIX/opt/asdf/libexec/asdf.sh" ]] && . "$BREW_PREFIX/opt/asdf/libexec/asdf.sh"
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"


# gh completion の高速化（コマンド呼び出しを減らす）
if (( $+commands[gh] )); then
  # 補完関数が未定義の場合のみ読み込む、または簡易的に eval
  compdef _gh gh 2>/dev/null || eval "$(gh completion -s zsh)"
fi

# 5. fzf-tab (最後に読み込む)
[[ -f ~/Developer/fzf-tab/fzf-tab.plugin.zsh ]] && zsh-defer source ~/Developer/fzf-tab/fzf-tab.plugin.zsh

eval "$(starship init zsh)"
eval "$(direnv hook zsh)"
zprof
