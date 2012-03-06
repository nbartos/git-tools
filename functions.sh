#!/bin/bash

warn() {
    echo "$@" >&2
}

die() {
    echo "$@" >&2
    exit 1
}

git_fallback() {
    if test $# -ne 3 -o -z "$1" -o -z "$2" -o -z "$3"; then
        die "git_update_submodules <owner> <branch> [fallback-owner]" || return 1
    fi

    OWNER="$1"
    BRANCH="$2"
    FALLBACK="$3"

    local try="$OWNER $BRANCH"

    if test "$FALLBACK" != "$OWNER"; then
        try="$try\n${FALLBACK} ${BRANCH}"
    fi

    BASE_BRANCH="$(basename $BRANCH)"
    DIR_BRANCH="$(dirname $BRANCH)"
    if test "$DIR_BRANCH" = "."; then
        DIR_BRANCH=""
    else
        DIR_BRANCH="$DIR_BRANCH/"
    fi

    if test "$BASE_BRANCH" != "master"; then
        try="$try\n${FALLBACK} ${DIR_BRANCH}master"
    fi

    echo $try
}

git_fallback_remote() {
    git_fallback "$@" | while read remote branch; do echo -n "$remote "; done
}

git_fallback_branch() {
    git_fallback "$@" | while read remote branch; do echo -n "$remote/$branch "; done
}

git_has_substring() {
    if test $# -ne 2 -o -z "$1" -o -z "$2"; then
        die "git_has_substring <substring> <string>" || return 1
    fi

    echo "$2" | grep -q "$1" >/dev/null 2>&1
}

git_build_fetch() {
    if test $# -ne 4 -o -z "$1" -o -z "$2" -o -z "$3" -o -z "$4"; then
        die "git_build_fetch <owner> <branch> <fallback-owner> <repository>" || return 1
    fi

    OWNER="$1"
    BRANCH="$2"
    FALLBACK="$3"
    REPO="$4"

    # Note this is all in a subshell, so I can turn off -e
    (
        set +e
        for fullbranch in $(git_fallback_branch $OWNER $BRANCH $FALLBACK); do
            IFS=/
            set -- $fullbranch
            local remote="$1"
            local branch="$2"

            for try in `seq 1 5`; do
                local msg
                msg="$(git ls-remote -h --exit-code git@github.com:$remote/$REPO $branch 2>&1)"
                case $? in
                    0)
                        warn "Choosing $remote/$REPO/$branch"
                        echo "git fetch git@github.com:$remote/$REPO $branch"
                        return 0
                        ;;
                    2)
                        warn "No branch $branch in $remote/$REPO"
                        continue 2
                        ;;
                    *)
                        # Network Error, or no such repo
                        if git_has_substring "Repository not found" "$msg"; then
                            warn "No repo $REPO owned by $remote"
                            continue 2
                        else
                            warn "Try $try/5 failed, could not contact remote"
                            continue 1
                        fi
                        ;;
                esac
            done
        done
        die "Could not find any branches to use for $OWNER/$REPO/$BRANCH with fallback $FALLBACK"
    )
}

# Fallback tests:
#echo "Given[upstream/master] Expected[upstream/master] Got[" `git_fallback_branch upstream master upstream` "]"
#echo "Given[upstream/dev] Expected[upstream/dev upstream/master] Got[" `git_fallback_branch upstream dev upstream` "]"
#echo "Given[bob/master] Expected[bob/master upstream/master] Got[" `git_fallback_branch bob master upstream` "]"
#echo "Given[bob/dev] Expected[bob/dev upstream/dev upstream/master] Got[" `git_fallback_branch bob dev upstream` "]"
#echo "Given[upstream/diablo/master] Expected[upstream/diablo/master] Got[" `git_fallback_branch upstream diablo/master upstream` "]"
#echo "Given[upstream/diablo/dev] Expected[upstream/diablo/dev upstream/diablo/master] Got[" `git_fallback_branch upstream diablo/dev upstream` "]"
#echo "Given[bob/diablo/master] Expected[bob/diablo/master upstream/diablo/master] Got[" `git_fallback_branch bob diablo/master upstream` "]"
#echo "Given[bob/diablo/dev] Expected[bob/diablo/dev upstream/diablo/dev upstream/diablo/master] Got[" `git_fallback_branch bob diablo/dev upstream` "]"

git_init_parent() {
    if test $# -ne 2; then
        die "git_init_parent <owner> <branch>" || return 1
    fi

    if test "$(git rev-parse --git-dir)" != ".git"; then
        die "git_init_parent: CWD must be the top level of a git repo" || return 1
    fi

    local OWNER="$1"
    local BRANCH="$2"
    local REPO=$(basename $PWD)

    git clean -f -d -x

    # The parent repo may only fall back to the same remote (thus the OWNER
    # repetition)
    local worked=0
    old_IFS="$IFS"
    for fullbranch in $(git_fallback_branch $OWNER $BRANCH $OWNER); do
        IFS=/
        set -- $fullbranch
        local remote="$1"
        local branch="$2"
        git remote add $remote "git@github.com:$remote/$REPO.git" || true
        git fetch $remote || continue
        git checkout "$remote/$branch" || continue
        worked=1
        break
    done
    IFS="$old_IFS"

    if test $worked -ne 1; then
        die "Failed to check out parent branch $OWNER/$BRANCH" || return 1
    fi
}

git_update_submodules() {
    if test $# -gt 3 -o $# -lt 2; then
        die "git_update_submodules <owner> <branch> [fallback-owner]" || return 1
    fi

    if test "$(git rev-parse --git-dir)" != ".git"; then
        die "git_update_submodules: CWD must be the top level of a git repo" || return 1
    fi

    local OWNER="$1"
    local BRANCH="$2"
    local FALLBACK="${3:-${OWNER}}"

    git submodule sync
    git submodule update --init

    # Make sure we don't have a preexisting FETCH_HEAD
    git submodule foreach 'git update-ref -d FETCH_HEAD'

    for name in $(git submodule foreach -q 'echo $name'); do
        fetchcmd="$(git_build_fetch $OWNER $BRANCH $FALLBACK $name)"
        (cd $name && $fetchcmd)
    done
    git submodule foreach "git reset --hard FETCH_HEAD"
    git submodule foreach "git clean -f -d -x"
}
