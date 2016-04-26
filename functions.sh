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
    # What to return if the repo is definitely missing.
    return_if_missing=1
    if [ $1 = 'missing-ok' ]; then
        return_if_missing=0
        shift 1
    fi

    # Note this is all in a subshell, so I can turn off -e
    (
        set +e
        for try in `seq 1 10`; do
            local msg=""
            msg="$(git fetch -q $@ 2>&1)"
            case $? in
                0)
                    return 0
                    ;;
                *)
                    case "$msg" in
                        *"Repository not found"*)
                            #warn "No repo while fetching $@"
                            return $return_if_missing
                            ;;
                        *"Couldn't find remote ref"*)
                            #warn "No branch while fetching $@"
                            return $return_if_missing
                            ;;
                        *"Permission denied"*)
                            die "Permission denied while fetching $@. Fix permissions." || return 1
                            ;;
                        *)
                            warn "Try $try/10 failed, could not contact remote [$msg]"
                            sleep 10
                            continue
                            ;;
                        esac
                    ;;
            esac
        done
        die "Timed out while calling git_retry_fetch $@"
    )
}

git_retry_tag() {
    if test $# -ne 3; then
        die "git_retry_tag <owner> <tag> <message>" || return 1
    fi

    git tag "$2" -a -m "$3"

    # Note this is all in a subshell, so I can turn off -e
    (
        set +e
        for try in `seq 1 10`; do
            local msg=""
            msg="$(git push "$1" "$2" 2>&1)"
            case $? in
                0)
                    return 0
                    ;;
                *)
                    case "$msg" in
                        *"Permission denied"*)
                            die "Permission denied while pushing to $1. Fix permissions." || return 1
                            ;;
                        *)
                            warn "Try $try/10 failed, could not push to remote remote [$msg]"
                            sleep 10
                            continue
                            ;;
                        esac
                    ;;
            esac
        done
        die "Timed out while calling git_retry_tag $@"
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
            echo "$fullbranch"
            return 0
        fi
    done
    die "Could not find any branches to use for $OWNER/$REPO/$BRANCH with fallback $FALLBACK" || return 1
}

git_fetch_parent() {
    if test $# -gt 3 -o $# -lt 2; then
        die "git_fetch_parent <owner> <branch> [<fallback-owner>]" || return 1
    fi

    if test "$(git rev-parse --git-dir)" != ".git"; then
        die "git_fetch_parent: CWD must be the top level of a git repo" || return 1
    fi

    local OWNER="$1"
    local BRANCH="$2"
    local FALLBACK="${3:-${OWNER}}"
    local REPO=$(basename $PWD)

    warn "Creating base repo and fetching remotes"

    git clean -ffdxq
    # This can fail on a new repo
    git reset -q --hard || true

    # Remove all remotes, which also nukes all the branch tags
    git remote | xargs -n1 git remote rm || true

    # Add remotes and fetch them
    for remote in $(git_fallback_remote $OWNER $BRANCH $FALLBACK); do
        git remote add $remote "git@github.com:$remote/$REPO.git"
        git_retry_fetch missing-ok $remote
    done
}

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

    git_fetch_parent "$@"

    git checkout -q "$(git_select_branch $OWNER $BRANCH $FALLBACK)"
    git clean -ffdxq
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

    # 6 is the length of "master". The trailing 1 is for the / between the
    # remote and branch.
    branchwidth=$(expr \
        $(test ${#OWNER}  -gt ${#FALLBACK} && echo ${#OWNER} || echo ${#FALLBACK}) \
        + \
        $(test ${#BRANCH} -gt 6 && echo ${#BRANCH} || echo 6) \
        + \
        1
    )

    git clean -ffdqx

    warn "Syncing submodule list (tree reference errors are okay here if you rebased)"
    # This can fail if the branch in question is old (or if the repo checkout fails)
    # And that might be okay, as long as it's only the subtree checkout that
    # fails. Probably.
    # The list of submodules cannot be trusted until this command runs.
    git submodule -q sync
    git submodule -q update --init --recursive || true

    # Now the list of submodules should be up to date, but some of them may
    # still be old.  Add the remotes and fetch them, then update again (without
    # || true) to make sure we're synced.

    # Add child remotes and fetch them
    for name in $(git submodule foreach -q 'echo "$name"'); do
    (
        cd $name
        # Remove the remotes for the submodule
        git remote | xargs -n1 git remote rm || true

        for remote in $(git_fallback_remote $OWNER $BRANCH $FALLBACK); do
            git remote add $remote "git@github.com:$remote/$name.git"
            git_retry_fetch missing-ok $remote
        done
    )&
    done
    wait

    warn "Syncing submodule data (tree reference errors are okay here if you rebased)"
    # If there was a rebase (such that the current branch we're looking for
    # shares no history with the revision that pentos expects) we will get an
    # error here (fatal: reference is not a tree: <revid>). That's okay.
    git submodule -q sync
    git submodule -q update --init --recursive || true

    warn "Overlaying ${OWNER}/${BRANCH} on top of ${FALLBACK}"
    warn "These are the branches I chose:"

    used_branches=
    for name in $(git submodule foreach -q 'echo "$name"'); do
        branch=$(cd $name && git_select_branch $OWNER $BRANCH $FALLBACK)
        (
            cd $name
            git tag -d BUILD_TARGET &>/dev/null || true
            git tag BUILD_TARGET "$branch"
            git reset -q --hard BUILD_TARGET
            warn "$(printf "%15s %-${branchwidth}s" $name $branch) $(git show -s --oneline)"
        )
        used_branches="$used_branches\n$branch"
        git config -f .gitmodules "submodule.$name.url" "git@github.com:${branch%%/*}/$name.git"
    done
    git submodule foreach -q "git clean -ffdxq"
    if ! echo -e "$used_branches" | grep -q "^${OWNER}/${BRANCH}$"; then
        warn
        die "You told me to use ${OWNER}/${BRANCH} but I found no branches by that name"
    fi
}

git_submodule_commit_log() {
    set -x

    if test $# -ne 6; then
        die "git_submodule_commit_log <from> <to> <owner> <branch> <version> <formatter>" || return 1
    fi

    local FROMBASE="$1"
    local TOBASE="$2"
    local OWNER="$3"
    local BRANCH="$4"
    local VERSION="$5"
    local FORMATTER="$6"

    git clean -ffdxq
    git submodule -q foreach git clean -ffdxq

    local from="jenkins-tmp-tag-${OWNER}-${BRANCH}-from"
    local to="jenkins-tmp-tag-${OWNER}-${BRANCH}-to"

    git commit -q -a --allow-empty -m "interim commit message for build $VERSION"
    git tag -d "$to" 2>/dev/null || true
    git tag "$to" $TOBASE

    git tag -d "$from" 2>/dev/null || true
    git tag "$from" $FROMBASE

    git checkout -q $from
    git clean -ffdxq
    # If the first reset fails, the master repo points to a rev that no longer
    # exists in the child
    git submodule -q foreach 'git reset -q --hard $sha1 || (echo "REVISION $sha1 ON REPO $name DOES NOT EXIST. CHANGELOG WILL BE INACCURATE."; true)'
    git checkout -q "$to"
    git clean -ffdxq
    git submodule -q foreach 'git reset -q --hard $sha1'

    git clean -ffdxq
    git submodule -q foreach git clean -ffdxq

    local tmpfile=$(mktemp --suffix=.pentos-msg)
    for name in $(git submodule foreach -q 'echo "$name"'); do
    (
        cd $name
        echo "Entering '$name' ($(git branch -r --contains HEAD | sed -e 's/->.*//' | grep -v '/HEAD' | xargs echo | sed -e 's/^\s*\(.*\)\s*$/\1/g'))"
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
    git reset -q --hard "$rev"

    rm -f $tmpfile
    git tag -d "$from" "$to" >/dev/null

    git submodule foreach git tag -a -m version "v$VERSION"

    set +x
}

git_push_everything() {
    if test $# -ne 4; then
        die "git_push_everything <owner> <branch> <fallback> <version>" || return 1
    fi

    local OWNER="$1"
    local BRANCH="$2"
    local FALLBACK="$3"
    local VERSION="$4"

    # In the case of concurrent builds, there could be a conflict here; merge!
    git_retry_fetch "$OWNER"
    git rev-parse --quiet --verify "$OWNER/$BRANCH" && git merge --no-edit --ff -X ours -m "Merge: some changelogs may be duplicated in the next commit" "$OWNER/$BRANCH"

    if [ "$OWNER/$BRANCH" = "$(git_last_fallback_branch $OWNER $BRANCH $FALLBACK)" ]; then
        git submodule foreach git push "$OWNER" "v$VERSION"
    fi

    git push "$OWNER" "HEAD:refs/heads/$BRANCH"
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

git_select_version() {
    if test $# -ne 3; then
        die "git_select_version <owner> <branch> <fallback>" || return 1
    fi

    local OWNER="$1"
    local BRANCH="$2"
    local FALLBACK="$3"

    local branch="$(git_last_fallback_branch $OWNER $BRANCH $FALLBACK)"

    # Check for a version tag in the branch name
    version=$(expr match "$branch" '^[^/]\+/\([0-9]\+\.[0-9]\+\)/[^/]\+$') || true
    if test -n "$version"; then
        warn "Retrieved version $version from branch $branch"
    else
        # no version from branch. okay, is it the dev branch?
        if ! expr match "$branch" '^[^/]\+/[^/]\+$' >/dev/null; then
            die "Illegally-formatted branch name: $branch (expecting remote/branch or remote/\d+.\d+/branch"
        fi
        # Okay, it's a dev branch, extract the version from the bump tag
        local desc="$(git describe --match 'bump-*' "$branch")" || die 'Could not find a bump tag'

        version=$(expr match "$desc" '^bump-\([0-9]\+\.[0-9]\+\)') || die "Could not retrieve version from tag description $desc"
        warn "Retrieved version $version from tag description $desc"
    fi
    echo "$version"
}
