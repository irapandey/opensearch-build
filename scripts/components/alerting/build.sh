#!/bin/bash

# Copyright OpenSearch Contributors
# SPDX-License-Identifier: Apache-2.0
#
# The OpenSearch Contributors require contributions made to
# this file be licensed under the Apache-2.0 license or a
# compatible open source source license.
#
# alerting's root build.gradle hardcodes common_utils.version to "3.7.0.0-SNAPSHOT"
# instead of using the computed opensearch_build variable.  This breaks non-snapshot
# builds (and snapshot builds where common-utils was built without a qualifier) because
# the locally-built common-utils artifact carries the resolved version string, not the
# hardcoded snapshot suffix.  Pass -Dcommon_utils.version explicitly so Gradle uses the
# same version string that was published to mavenLocal() by the earlier common-utils build.
# Ref: https://github.com/opensearch-project/alerting/blob/3.7.0.0/build.gradle#L18

set -ex

function usage() {
    echo "Usage: $0 [args]"
    echo ""
    echo "Arguments:"
    echo -e "-v VERSION\t[Required] OpenSearch version."
    echo -e "-q QUALIFIER\t[Optional] Version qualifier."
    echo -e "-s SNAPSHOT\t[Optional] Build a snapshot, default is 'false'."
    echo -e "-p PLATFORM\t[Optional] Platform, ignored."
    echo -e "-a ARCHITECTURE\t[Optional] Build architecture, ignored."
    echo -e "-o OUTPUT\t[Optional] Output path, default is 'artifacts'."
    echo -e "-h help"
}

while getopts ":h:v:q:s:o:p:a:" arg; do
    case $arg in
        h)
            usage
            exit 1
            ;;
        v)
            VERSION=$OPTARG
            ;;
        q)
            QUALIFIER=$OPTARG
            ;;
        s)
            SNAPSHOT=$OPTARG
            ;;
        o)
            OUTPUT=$OPTARG
            ;;
        p)
            PLATFORM=$OPTARG
            ;;
        a)
            ARCHITECTURE=$OPTARG
            ;;
        :)
            echo "Error: -${OPTARG} requires an argument"
            usage
            exit 1
            ;;
        ?)
            echo "Invalid option: -${arg}"
            exit 1
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Error: You must specify the OpenSearch version"
    usage
    exit 1
fi

[[ ! -z "$QUALIFIER" ]] && VERSION=$VERSION-$QUALIFIER
[[ "$SNAPSHOT" == "true" ]] && VERSION=$VERSION-SNAPSHOT
[ -z "$OUTPUT" ] && OUTPUT=artifacts

# Compute the plugin version the same way alerting's build.gradle does:
#   version_tokens[0] + '.0' [+ '-' + qualifier] [+ '-SNAPSHOT']
# This must match what common-utils published to mavenLocal().
PLUGIN_VERSION=$(echo $VERSION | cut -d'-' -f1).0
[[ ! -z "$QUALIFIER" ]] && PLUGIN_VERSION=$PLUGIN_VERSION-$QUALIFIER
[[ "$SNAPSHOT" == "true" ]] && PLUGIN_VERSION=$PLUGIN_VERSION-SNAPSHOT

./gradlew assemble --no-daemon --refresh-dependencies -DskipTests=true \
    -Dopensearch.version=$VERSION \
    -Dbuild.version_qualifier=$QUALIFIER \
    -Dbuild.snapshot=$SNAPSHOT \
    -Dcommon_utils.version=$PLUGIN_VERSION

[ -z "$OUTPUT" ] && OUTPUT=artifacts
mkdir -p $OUTPUT/plugins
cp ./alerting/build/distributions/*.zip $OUTPUT/plugins

./gradlew publishToMavenLocal \
    -Dopensearch.version=$VERSION -Dbuild.snapshot=$SNAPSHOT -Dbuild.version_qualifier=$QUALIFIER \
    -Dcommon_utils.version=$PLUGIN_VERSION
./gradlew publishShadowPublicationToStagingRepository \
    -Dopensearch.version=$VERSION -Dbuild.snapshot=$SNAPSHOT -Dbuild.version_qualifier=$QUALIFIER \
    -Dcommon_utils.version=$PLUGIN_VERSION
./gradlew publishPluginZipPublicationToZipStagingRepository \
    -Dopensearch.version=$VERSION -Dbuild.snapshot=$SNAPSHOT -Dbuild.version_qualifier=$QUALIFIER \
    -Dcommon_utils.version=$PLUGIN_VERSION
mkdir -p $OUTPUT/maven/org/opensearch
cp -r ./build/local-staging-repo/org/opensearch/. $OUTPUT/maven/org/opensearch
