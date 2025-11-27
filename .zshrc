# for wsl
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
export PATH="$HOME/.asdf/asdf.sh:$PATH"
export PATH="$HOME/.asdf/completions/asdf.bash:$PATH"
# end

source $(brew --prefix)/share/google-cloud-sdk/path.zsh.inc
source $(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc

export PKG_CONFIG_PATH="$(brew --prefix)/opt/openssl@3/lib/pkgconfig"
export PATH="$(brew --prefix)/bin:/usr/local/bin:$PATH"
export PATH="$(brew --prefix)/opt/openssl@3/bin:~/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH=$HOME/.asdf/shims:$PATH

# eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

export PATH=$(go env GOPATH)/bin:$PATH

setopt prompt_subst
# prompt
PROMPT='%F{red}%*%f:%F{magenta}$(uname -p)%f %F{cyan}%.%f $ '
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
HISTFILE=~/.zsh_history_macmini
HISTSIZE=1000000
SAVEHIST=1000000
# resolve conflicts
disable r
# alias
alias la='ls -a'
alias ll='ls -l'
alias lg='lazygit'
# show git branch
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr "%F{yellow}!"
zstyle ':vcs_info:git:*' unstagedstr "%F{red}+"
zstyle ':vcs_info:*' formats "%F{green}%c%u[%b]%f"
zstyle ':vcs_info:*' actionformats '[%b|%a]'
precmd () { vcs_info }
RPROMPT=$RPROMPT'${vcs_info_msg_0_}'

#show current selected gcp project name
is_first=true
function gcp_project_id() {
  if [ -f "$HOME/.config/gcloud/active_config" ]; then
    gcp_profile=$(cat $HOME/.config/gcloud/active_config)
    project_id=$(awk '/project/{print $3}' $HOME/.config/gcloud/configurations/config_$gcp_profile)

    if "${is_first}"; then
      is_first=false
      RPROMPT=${RPROMPT}%F{039}'${project_id}'%f
    fi
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd gcp_project_id

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"; fi

. $(brew --prefix)/opt/asdf/libexec/asdf.sh
. "$HOME/.cargo/env"
eval "$(starship init zsh)"
eval "$(direnv hook zsh)"
eval "$(gh completion -s zsh)"


source ~/Developer/fzf-tab/fzf-tab.plugin.zsh

# zsh-autocompleteと組み合わせる場合、いい感じに補完をするために以下の設定を追加
# my-fzf-tab() {
#   functions[compadd]=$functions[-ftb-compadd]
#   zle fzf-tab-complete
# }
# zle -N my-fzf-tab
# bindkey "^I" my-fzf-tab

if [ -z "$SSH_CONNECTION" ] && [ -z "$KRGPI_FROM_TMUX" ]; then
  tmux
fi
