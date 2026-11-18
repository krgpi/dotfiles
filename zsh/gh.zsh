gh() {
    local -a args
    if [[ "$1" == "co" ]]; then
        args=("${@:2}")
    elif [[ "$1 $2" == "pr checkout" ]]; then
        args=("${@:3}")
    else
        command gh "$@"
        return
    fi
    local branch number root dir
    read -r branch number < <(command gh pr view "$args[1]" --json headRefName,number -q '"\(.headRefName) \(.number)"') || return
    dir=$(git worktree list --porcelain | awk -v b="branch refs/heads/$branch" '/^worktree /{w=substr($0,10)} $0==b{print w; exit}')
    if [[ -z "$dir" ]]; then
        root=$(git rev-parse --path-format=absolute --git-common-dir) || return
        root=${root:h}
        dir="${root:h}/${root:t}-worktrees/${branch//\//-}"
        git worktree add --detach "$dir" || return
        if ! (builtin cd "$dir" && command gh pr checkout "${args[@]}"); then
            git worktree remove --force "$dir"
            return 1
        fi
        if (( $+commands[orca] )); then
            orca worktree set --worktree "path:$dir" --pr "$number" >/dev/null
            orca terminal create --worktree "path:$dir" --focus >/dev/null
        fi
    fi
    builtin cd "$dir" && echo "→ $dir"
}
