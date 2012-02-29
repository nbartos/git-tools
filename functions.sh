#!/bin/bash

die() {
    echo "$@" >&2
    exit 1
}

git_fallback() {
    if test $# -ne 3 -o -z "$1" -o -z "$2" -o -z "$3"; then
        die "git_update_submodules <owner> <branch> [fallback-owner]"
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

git_build_fetches() {
    if test $# -ne 3 -o -z "$1" -o -z "$2" -o -z "$3"; then
        die "git_update_submodules <owner> <branch> [fallback-owner]"
    fi

    OWNER="$1"
    BRANCH="$2"
    FALLBACK="$3"

    local first="1"
    git_fallback $OWNER $BRANCH $FALLBACK | while read remote branch; do
        if ! test $first = "1"; then
            echo -n " || "
        fi
        first=0
        echo "git fetch git@github.com:$remote/\$name $branch"
    done
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

git_update_submodules() {
    # clone_update <owner> <branch> [fallback-owner]
    if test $# -gt 3 -o $# -lt 2; then
        die "git_update_submodules <owner> <branch> [fallback-owner]"
    fi

    if test "$(git rev-parse --git-dir)" != ".git"; then
        die "git_update_submodules: CWD must be the top level of a git repo"
    fi

    local OWNER="$1"
    local BRANCH="$2"
    local FALLBACK="${3:-${OWNER}}"
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
        die "Failed to check out branch $OWNER/$BRANCH or fallbacks"
    fi

    git submodule update --init

    # Make sure we don't have a preexisting FETCH_HEAD
    git submodule foreach 'git update-ref -d FETCH_HEAD'

    fetches="$(git_build_fetches $OWNER $BRANCH $FALLBACK) || die 'Could not fetch any branch'"

    git submodule foreach $fetches
    git submodule foreach "git reset --hard FETCH_HEAD"
    git submodule foreach "git clean -f -d -x"
}
