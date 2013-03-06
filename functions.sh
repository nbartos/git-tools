#!/bin/sh

warn() {
    echo "$@" >&2
}

die() {
    echo "$@" >&2
    exit 1
}

git_fallback() {
    if test $# -ne 3 -o -z "$1" -o -z "$2" -o -z "$3"; then
        die "git_fallback <owner> <branch> [fallback-owner]" || return 1
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

    printf "$try\n"
}

git_fallback_remote() {
    git_fallback "$@" | while read remote branch; do echo "$remote"; done | uniq
}

git_fallback_branch() {
    git_fallback "$@" | while read remote branch; do printf "$remote/$branch "; done
}

git_last_fallback_branch() {
    git_fallback "$@" | while read remote branch; do echo "$remote/$branch"; done | tail -n1
}

git_has_substring() {
    if test $# -ne 2 -o -z "$1" -o -z "$2"; then
        die "git_has_substring <substring> <string>" || return 1
    fi

    echo "$2" | grep -q "$1" >/dev/null 2>&1
}

git_retry_fetch() {
    # Note this is all in a subshell, so I can turn off -e
    (
        set +e
        for try in `seq 1 5`; do
            local msg
            msg="$(git fetch $@ 2>&1)"
            case $? in
                0)
                    warn "git fetch $@ succeeded"
                    return 0
                    ;;
                *)
                    case "$msg" in
                        *"Repository not found"*)
                            warn "No repo while fetching $@"
                            return 1
                            ;;
                        *"Couldn't find remote ref"*)
                            warn "No branch while fetching $@"
                            return 1
                            ;;
                        *"Permission denied"*)
                            die "Permission denied while fetching $@. Fix permissions." || return 1
                            ;;
                        *)
                            warn "Try $try/5 failed, could not contact remote [$msg]"
                            sleep 1
                            continue
                            ;;
                        esac
                    ;;
            esac
        done
        warn "Timed out while calling git_retry_fetch $@"
        return 254
    )
}

git_select_branch() {
    if test $# -ne 3 -o -z "$1" -o -z "$2" -o -z "$3"; then
        die "git_select_branch <owner> <branch> <fallback-owner>" || return 1
    fi

    OWNER="$1"
    BRANCH="$2"
    FALLBACK="$3"
    local REPO=$(basename $PWD)

    for fullbranch in $(git_fallback_branch $OWNER $BRANCH $FALLBACK); do
        if git rev-parse --quiet --verify "$fullbranch" > /dev/null; then
            warn "Choosing $REPO/$fullbranch"
            echo "$fullbranch"
            return 0
        fi
    done
    die "Could not find any branches to use for $OWNER/$REPO/$BRANCH with fallback $FALLBACK" || return 1
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
    if test $# -gt 3 -o $# -lt 2; then
        die "git_init_parent <owner> <branch> [<fallback-owner>]" || return 1
    fi

    if test "$(git rev-parse --git-dir)" != ".git"; then
        die "git_init_parent: CWD must be the top level of a git repo" || return 1
    fi

    local OWNER="$1"
    local BRANCH="$2"
    local FALLBACK="${3:-${OWNER}}"
    local REPO=$(basename $PWD)

    git clean -f -f -d -x
    # This can fail on a new repo
    git reset --hard || true

    # Remove all remotes, which also nukes all the branch tags
    git remote | xargs -n1 git remote rm

    # Add remotes and fetch them
    for remote in $(git_fallback_remote $OWNER $BRANCH $FALLBACK); do
        git remote add $remote "git@github.com:$remote/$REPO.git"
        git_retry_fetch $remote || true
    done

    git checkout "$(git_last_fallback_branch $OWNER $BRANCH $FALLBACK)"
    git clean -f -f -d -x

    # Add child remotes and fetch them
    for name in $(git submodule foreach -q 'echo "$name"'); do
    (
        cd $name
        echo "Entering '$name'"

        # Remove the remotes for the submodule
        git remote | xargs -n1 git remote rm

        for remote in $(git_fallback_remote $OWNER $BRANCH $FALLBACK); do
            git remote add $remote "git@github.com:$remote/$name.git"
            git_retry_fetch $remote || true
        done
    ) done
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

    # This can fail if the branch in question is old. The log message will be
    # weird, but that's okay.
    git submodule update --init --recursive || true

    for name in $(git submodule foreach -q 'echo "$name"'); do
        branch=$(cd $name && git_select_branch $OWNER $BRANCH $FALLBACK)
        (
            cd $name
            git tag -d BUILD_TARGET || true
            git tag -m "$branch" BUILD_TARGET "$branch"
        )
        git config -f .gitmodules "submodule.$name.url" "git@github.com:${branch%%/*}/$name.git"
    done
    git submodule foreach "git reset --hard BUILD_TARGET"
    git submodule foreach "git clean -f -f -d -x"
}

git_submodule_commit_log() {

    if test $# -ne 6; then
        die "git_submodule_commit_log <from> <to> <owner> <branch> <version> <formatter>" || return 1
    fi

    local FROMBASE="$1"
    local TOBASE="$2"
    local OWNER="$3"
    local BRANCH="$4"
    local VERSION="$5"
    local FORMATTER="$6"

    git clean -dffx
    git submodule foreach git clean -dffx

    local from="jenkins-tmp-tag-${OWNER}-${BRANCH}-from"
    local to="jenkins-tmp-tag-${OWNER}-${BRANCH}-to"

    git commit -a --allow-empty -m "interim commit message for build $VERSION"
    git tag -d "$to" || true
    git tag "$to" $TOBASE

    git tag -d "$from" || true
    git tag "$from" $FROMBASE

    git checkout $from
    git clean -f -f -d -x
    # If the first reset fails, the master repo points to a rev that no longer
    # exists in the child
    git submodule foreach 'git reset --hard $sha1 || (echo "REVISION $sha1 ON REPO $name DOES NOT EXIST. CHANGELOG WILL BE INACCURATE."; true)'
    git checkout "$to"
    git clean -f -f -d -x
    git submodule foreach 'git reset --hard $sha1'

    git clean -dffx
    git submodule foreach git clean -dffx

    local tmpfile=$(mktemp --suffix=.pentos-msg)
    for name in $(git submodule foreach -q 'echo "$name"'); do
    (
        cd $name
        echo "Entering '$name' ($(git tag -l BUILD_TARGET -n1 | sed -e  's/.* //'))"
        git log --stat $(git merge-base ORIG_HEAD HEAD)..HEAD
    )
    done | $FORMATTER $OWNER $VERSION > $tmpfile

    # Create a new commit with the same tree as $to, but with different parents
    local tree=$(git rev-parse "$to^{tree}")
    if git rev-parse --quiet --verify "$GITHUB_OWNER/$GITHUB_BRANCH"; then
        rev=$(git commit-tree "$tree" -p "$from" -p "${OWNER}/${BRANCH}" < $tmpfile)
    else
        rev=$(git commit-tree "$tree" -p "$from" < $tmpfile)
    fi
    if [ -z "$rev" ]; then
        die "commit failed" || return 1
    fi
    git reset --hard "$rev"

    rm -f $tmpfile
    git tag -d "$from" "$to"
}

git_submodule_release_diff() {
    if test $# -ne 2; then
        die "git_submodule_release_diff <from-version> <to-version>" || return 1
    fi

    local FROM="$1"
    local TO="$2"

    local from_hash=$(git log --format='%h' --all --grep "Build ${FROM}")
    local to_hash=$(git log --format='%h' --all --grep "Build ${TO}")

    if test -z "$from_hash"; then
        die "git_submodule_release_diff: could not find commit for build ${FROM}" || return 1
    fi

    if test -z "$to_hash"; then
        die "git_submodule_release_diff: could not find commit for build ${TO}" || return 1
    fi

    git log --submodule=log ${from_hash}..${to_hash}
}

git_enable_cached_ssh() {
    local base="$(cd $(git rev-parse --git-dir) && pwd)"
    local path="$(cd $(git rev-parse --git-dir) && pwd)/git-ssh-wrapper.sh"
    local ssh_path="$base/piston-git-ssh-wrapper.sh"

    cat <<EOF > "$ssh_path"
#!/bin/sh
exec ssh -F/dev/null -oControlPersist=10m -oControlMaster=auto -oControlPath="$base/piston-controlmaster-%r@%h:%p" \$*
EOF
    chmod +x "$ssh_path"
    echo "export GIT_SSH=$ssh_path"
    # Why does this fix it? :(
    $ssh_path -N -f git@github.com
}
