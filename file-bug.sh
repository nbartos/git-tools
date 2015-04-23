#!/bin/bash

set -e
set -x
set -o pipefail

CI_URL="albino.piston.cc"

# 'jenkins' label id in pivotal is: 5803519, which is minimal for labels for searching/sorting
LABEL_ID="5803519"
FILESERVER_LINKS=()

if [ -z "$PIVOTAL_TOKEN" -o -z "$PIVOTAL_PROJECT_ID" -o -z "$PIVOTAL_OWNER_ID" \
     -o -z "$BUILD_NUMBER" -o -z "$TEST_BUILD_NUMBER" -o -z "$TEST_BUILD_URL" ]; then
    echo "Required variable not set" >&2
    exit 1
fi

JOB_TYPE=$(echo "$TEST_BUILD_URL" | grep -Po "\/job\/(.*)\/\d+" | cut -d / -f 3)
echo "CI Job Type: $JOB_TYPE"

if [ -z "$JOB_TYPE" ]; then
    echo "Error: CI Job type was not found from URL: $TEST_BUILD_URL" >&2
    exit 1
fi

# Extra checks for all functional tests
if [ ! -z "$(echo "$JOB_TYPE" | egrep -i "(functional|upgrade|update).*tests")" ]; then
    if [ -z "$FILESERVER" -o -z "$RELEASE_VERSION" -o -z "$GITHUB_OWNER" ]; then
        echo "Required variable not set" >&2
        exit 1
    fi

    if [ "$GITHUB_OWNER" != "piston" ]; then
        echo "Repo owner is not piston, no bug will be filed."
        exit 0
    fi

    if ! [ "$TEST_GITHUB_OWNER" = "piston" -o -z "$TEST_GITHUB_OWNER" ]; then
        echo "Test repo owner is null or not piston, no bug will be filed."
        exit 0
    fi

    FILESERVER_LINKS+=("http://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log"
                       "http://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log.gz")
fi

FILEBUG_LINK="Bug Job: ${BUILD_URL%/}/console"
JOB_RESPONSIBLE="Failed Job: ${TEST_BUILD_URL%/}/console"
DESCRIPTION="$FILEBUG_LINK\n$JOB_RESPONSIBLE\n"

for LINK in "${FILESERVER_LINKS[@]}"; do
    # If we get anything that's not a 200 or a 404 there's something really wrong, file a bug on
    # the whole system
    case "$(curl -H 'Accept-Encoding: gzip' -o /dev/null --silent  --write-out '%{http_code}\n' $LINK)" in
        "200")
            DESCRIPTION="$DESCRIPTION\n$LINK"
            ;;                                                             
        "404")
            DESCRIPTION="$DESCRIPTION\n[404/NotFound] => $LINK\nDid the tests actually run??"
            ;;                                                             
        *)
            DESCRIPTION="Error: The log links didn't provide a return code we could parse!\n\Build system is currently unstable in its log reporting."
            ;;                                                             
    esac
done

read -r -d '' json <<-EOF || true
{"story_type": "bug",
 "name": "$JOB_TYPE Failure: $RELEASE_VERSION [$TEST_BUILD_NUMBER] [Automatically filed by Jenkins]",
 "owner_ids": [$PIVOTAL_OWNER_ID],
 "label_ids": [$LABEL_ID],
 "description": "$DESCRIPTION"
}
EOF

echo "Filing Pivotal bug for $RELEASE_VERSION"
curl --retry 5 --retry-delay 5 -H "X-TrackerToken: $PIVOTAL_TOKEN" -X POST -H "Content-type: application/json" \
     -d "$json" https://www.pivotaltracker.com/services/v5/projects/$PIVOTAL_PROJECT_ID/stories
