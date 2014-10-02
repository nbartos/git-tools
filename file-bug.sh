#!/bin/bash

set -x
set -e
set -o pipefail

if [ -z "$FILESERVER" -o -z "$RELEASE_VERSION" -o -z "$GITHUB_OWNER" -o -z "$TEST_BUILD_NUMBER" -o -z "$PIVOTAL_TOKEN" -o -z "$PIVOTAL_PROJECT_ID" -o -z "$PIVOTAL_OWNER_ID" ]
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



read -r -d '' json <<-EOF || true
{"story_type": "bug",
 "name": "Test Failure: $RELEASE_VERSION [$TEST_BUILD_NUMBER] [automatically filed by Jenkins]",
 "owner_ids": [$PIVOTAL_OWNER_ID],
 "label_ids": [5803519],
 "description": "https://albino.piston.cc/job/Functional_Tests/$TEST_BUILD_NUMBER/console\nhttp://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log\nhttp://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log.gz"
}
EOF

echo "Filing Pivotal bug for $RELEASE_VERSION"
curl --retry 5 --retry-delay 5 -H "X-TrackerToken: $PIVOTAL_TOKEN" -X POST -H "Content-type: application/json" \
         -d "$json" https://www.pivotaltracker.com/services/v5/projects/$PIVOTAL_PROJECT_ID/stories
