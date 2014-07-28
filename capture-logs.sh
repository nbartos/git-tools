#!/bin/bash

set -x
set -e
set -o pipefail

if [ -z "$RELEASE_VERSION" -o -z "$BUILD_NUMBER" -o -z "$GITHUB_OWNER" -o -z "$GITHUB_BRANCH" -o
    -z "$WORKSPACE" -o -z "$FILE_SERVER" -o -z "$FILE_SERVER_USER" -o -z "$SYSLOG_SERVER" -o
    -z "$SYSLOG_SERVER_USER" -o -z "$CLUSTER" ]
then
    echo "Required variable not set" >&2
    exit 1
fi

RELEASE_VERSION_ESCAPED=$(echo "$RELEASE_VERSION" | sed -e 's|\.|\\\.|g')

nc -w0 -u "$SYSLOG_SERVER" 514 <<< "automated-build$CLUSTER: Build $RELEASE_VERSION ($BUILD_NUMBER) finish"

ssh "$SYSLOG_SERVER_USER@$SYSLOG_SERVER" "zcat /var/log/$CLUSTER-messages.1.gz | cat - /var/log/$CLUSTER-messages | awk '/ automated-build$CLUSTER: Build $RELEASE_VERSION_ESCAPED \($BUILD_NUMBER\) start/,/ automated-build$CLUSTER: Build $RELEASE_VERSION_ESCAPED \($BUILD_NUMBER\) finish$/' | gzip -c > automated-build.log.gz"

scp -q "$SYSLOG_SERVER_USER@$SYSLOG_SERVER:automated-build.log.gz" .

scp -q automated-build.log.gz "$FILE_SERVER_USER@$FILE_SERVER:/home/shared/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$BUILD_NUMBER.log.gz"

if [ -n "$EXECUTOR_NUMBER" -a -d "/tmp/teacup-artifacts-$EXECUTOR_NUMBER" ]
then
    rsync -rltgoD --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r "/tmp/teacup-artifacts-$EXECUTOR_NUMBER/" "$FILE_SERVER_USER@$FILE_SERVER:/home/shared/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/teacup-artifacts-$RELEASE_VERSION-$BUILD_NUMBER/"
    rm -rf "/tmp/teacup-artifacts-$EXECUTOR_NUMBER"
fi

set +x

echo
echo
echo "Errors in the log:"

if test -x "$WORKSPACE"/teacup/tools/extract-errors.py
then
    zcat automated-build.log.gz | "$WORKSPACE"/teacup/tools/extract-errors.py
else
    zcat automated-build.log.gz | awk '/^Traceback \(most recent/,/^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/'
fi
echo

cat <<EOF
Options to view the log:
http://$FILE_SERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$BUILD_NUMBER.log
http://$FILE_SERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$BUILD_NUMBER.log.gz
http://$FILE_SERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/teacup-artifacts-$RELEASE_VERSION-$BUILD_NUMBER/
scp $FILE_SERVER:/home/shared/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$BUILD_NUMBER.log.gz .

EOF
