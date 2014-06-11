#!/bin/bash

set -e
set -x
set -o pipefail

ROOT="$(cd $(dirname $0) && pwd)"
WORKSPACE="${ROOT}/workspace"
GITHUB_OWNER=${1:?[$0 <owner> <branch>]}
GITHUB_BRANCH=${2:?[$0 <owner> <branch>]}

mkdir ${WORKSPACE} 2>/dev/null || true

. "${ROOT}/functions.sh"

cd "$WORKSPACE"
git init -q pentos
cd pentos

echo "Git init..."

time (
    git_init_parent "$GITHUB_OWNER" "$GITHUB_BRANCH" piston
    git_update_submodules "$GITHUB_OWNER" "$GITHUB_BRANCH" piston
)

echo "done"
