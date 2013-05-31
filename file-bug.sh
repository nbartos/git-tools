#!/bin/bash

set -x
set -e
set -o pipefail

if [ -z "$FILESERVER" -o -z "$RELEASE_VERSION" -o -z "$GITHUB_OWNER" -o -z "$TEST_BUILD_NUMBER" -o -z "$PIVOTAL_TOKEN" -o -z "$PIVOTAL_PROJECT_ID" ]
then
    echo "Required variable not set" >&2
    exit 1
fi

if [ "$GITHUB_OWNER" != "piston" ]; then
    exit 0
fi

if ! [ "$TEST_GITHUB_OWNER" = "piston" -o -z "$TEST_GITHUB_OWNER" ]; then
    exit 0
fi

read -r -d '' xml <<-EOF || true
<story>
    <story_type>bug</story_type>
    <name>Test Failure: $RELEASE_VERSION [automatically filed by Jenkins]</name>
    <labels>jenkins</labels>
    <description>https://albino.pistoncloud.com/job/Functional_Tests/$TEST_BUILD_NUMBER/console
http://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log
http://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log.gz</description>
</story>
EOF

echo "Filing Pivotal bug for $RELEASE_VERSION"
curl --retry 5 --retry-delay 5 -H "X-TrackerToken: $PIVOTAL_TOKEN" -X POST -H "Content-type: application/xml" \
    -d "$xml" http://www.pivotaltracker.com/services/v3/projects/$PIVOTAL_PROJECT_ID/stories
