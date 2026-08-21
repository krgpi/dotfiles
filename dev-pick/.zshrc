# prefix + o のフォルダ選択ポップアップ専用の zsh 設定
# ZDOTDIR をここに向けて zsh を起動するので、通常の ~/.zshrc は読まれない
# （ポップアップの起動を速く保つため、補完と fzf-tab だけを立ち上げる）
#
# 操作:
#   Tab   選択中の候補までのパスを入力して、その先の補完を続ける
#   Enter 選択中のフォルダを dev で開く（ポップアップが閉じる）

DOTFILES="${${(%):-%x}:A:h:h}"

# 使い捨てのポップアップなので履歴は残さない（ZDOTDIR 配下に .zsh_history を作らせない）
HISTFILE=
SAVEHIST=0

autoload -Uz compinit
compinit -C -d "$HOME/.zcompdump"

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
# fzf-tab が曖昧な接頭辞を拾えるよう、zsh 側の補完メニューは出さない
zstyle ':completion:*' menu no

[[ -f "$HOME/Developer/fzf-tab/fzf-tab.plugin.zsh" ]] && source "$HOME/Developer/fzf-tab/fzf-tab.plugin.zsh"

# fzf-tab の --expect に渡されるキー名
zstyle ':fzf-tab:*' continuous-trigger 'tab'
zstyle ':fzf-tab:*' accept-line 'enter'
zstyle ':fzf-tab:*' fzf-flags --reverse --prompt='folder> ' --info=inline

# 入力行に "dev <path>" がそのまま見えるので、プロンプトは出さない
PROMPT=''
RPROMPT=''

# 開けたときだけポップアップを閉じる（失敗したらメッセージを読めるように残す）
dev() {
    "$DOTFILES/tmux-dev.sh" "$@" || return
    exit
}
compdef '_files -/' dev

# 補完を抜けたあとの Ctrl-C でポップアップごと閉じる
TRAPINT() { exit 130 }

# 起動直後に "dev <ルート>/" まで入力して補完を開く
# ホーム配下は ~ に畳んで、狭いポップアップで折り返さないようにする
_dev_pick_init() {
    local root="${TMUX_DEV_ROOTS%%:*}"
    root="${root:-$HOME/Developer}"
    BUFFER="dev ${root/#$HOME/~}/"
    CURSOR=$#BUFFER
    zle fzf-tab-complete
}
zle -N zle-line-init _dev_pick_init
