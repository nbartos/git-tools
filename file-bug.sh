#!/bin/bash

set -e
set -x
set -o pipefail


FILESERVER_LINKS=()

if [ -z "$JIRA_TOKEN" -o -z "$JIRA_PROJECT_ID" -o -z "$BUILD_NUMBER" \
     -o -z "$BUILD_URL" -o -z "$TEST_BUILD_NUMBER" \
     -o -z "$TEST_BUILD_URL" -z "$FILESERVER" -o -z "$RELEASE_VERSION" \
     -o -z "$GITHUB_OWNER" -o -z "$CI_URL" -o -z "$JIRA_URL" ]; then
    echo "Required variable not set" >&2
    exit 1
fi

PRODUCT_URL="https://${CI_URL}/job/The_Product/"

JOB_TYPE=$(echo "$TEST_BUILD_URL" | grep -Po "\/job\/(.*)\/\d+" | cut -d / -f 3)
echo "CI Job Type: $JOB_TYPE"

if [ -z "$JOB_TYPE" ]; then
    echo "Error: CI Job type was not found from URL: $TEST_BUILD_URL" >&2
    exit 1
fi

if [ "$GITHUB_OWNER" != "piston" ]; then
    echo "Repo owner is not piston, no bug will be filed."
    exit 0
fi

if [ -n "$TEST_GITHUB_OWNER" ] && [ "$TEST_GITHUB_OWNER" != "piston" ]; then
    echo "Test repo owner is not piston, no bug will be filed."
    exit 0
fi

FILESERVER_LINKS+=("http://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log"
                   "http://$FILESERVER/builds/$GITHUB_OWNER/$GITHUB_BRANCH/debug/functional-test-$RELEASE_VERSION-$TEST_BUILD_NUMBER.log.gz")

RELEASE_BUILD_NUMBER=$(echo "$RELEASE_VERSION" | cut -d '.' -f 3)
RELEASE_BUILD_LINK="Release Build: ${PRODUCT_URL%/}/${RELEASE_BUILD_NUMBER}/console"
FILEBUG_LINK="Bug Filer Job: ${BUILD_URL%/}/console"
JOB_RESPONSIBLE="Failed Job: ${TEST_BUILD_URL%/}/console"
DESCRIPTION="$RELEASE_BUILD_LINK\n$FILEBUG_LINK\n$JOB_RESPONSIBLE\n"

for LINK in "${FILESERVER_LINKS[@]}"; do
    # If we get anything that's not a 200 or a 404 there's something really wrong, file a bug on
    # the whole system
    case "$(curl -I -H 'Accept-Encoding: gzip' -o /dev/null --silent -w '%{http_code}' $LINK)" in
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
{
    "fields": {
        "project": {"key": "$JIRA_PROJECT_ID"},
        "issuetype": {"name": "Bug"},
        "summary": "$JOB_TYPE Failure: $RELEASE_VERSION [$TEST_BUILD_NUMBER] [Automatically filed by Jenkins]",
        "labels": ["jenkins"],
        "description": "$DESCRIPTION"
    }
}
EOF

echo "Filing JIRA bug for $RELEASE_VERSION"
curl --retry 5 --retry-delay 5 -H "Authorization: Basic $JIRA_TOKEN" \
    -X POST -H "Content-type: application/json" -d "$json" https://$JIRA_URL/rest/api/2/issue

