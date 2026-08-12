#!/bin/bash

# Copyright OpenSearch Contributors
# SPDX-License-Identifier: Apache-2.0
#
# The OpenSearch Contributors require contributions made to
# this file be licensed under the Apache-2.0 license or a
# compatible open source license.
#
# opensearch-remote-metadata-sdk's build.gradle lists the OpenSearch CI snapshot
# repository (ci.opensearch.org/ci/dbc/snapshots/maven/) before mavenCentral() in
# all repository blocks.  The spotlessJava/spotlessCheck tasks create a detached
# Gradle configuration that resolves google-java-format's transitive dependency on
# com.google.guava:guava:32.1.3-jre.  When the CI snapshot repo returns 503 (Service
# Unavailable) Gradle marks it as broken for the entire build session and the task
# fails with "Could not resolve all files for configuration ':detachedConfiguration2'".
#
# Spotless is a code-formatting check only – it produces no build artifacts.  We skip
# the spotlessCheck and spotlessJava tasks so the artifact build is not blocked by an
# intermittently unavailable repository.

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

# Skip spotlessCheck and spotlessJava: these tasks resolve com.google.guava:guava
# from the CI snapshot repository before falling through to mavenCentral(), causing
# an intermittent 503-driven build failure.  Spotless produces no artifacts.
./gradlew build -x test -x spotlessCheck -x spotlessJava \
    -Dopensearch.version=$VERSION \
    -Dbuild.snapshot=$SNAPSHOT \
    -Dbuild.version_qualifier=$QUALIFIER

./gradlew publishMavenJavaPublicationToMavenLocal \
    -Dopensearch.version=$VERSION \
    -Dbuild.snapshot=$SNAPSHOT \
    -Dbuild.version_qualifier=$QUALIFIER

./gradlew publishMavenJavaPublicationToStagingRepository \
    -Dopensearch.version=$VERSION \
    -Dbuild.snapshot=$SNAPSHOT \
    -Dbuild.version_qualifier=$QUALIFIER

mkdir -p $OUTPUT/maven/org/opensearch
cp -r ./build/local-staging-repo/org/opensearch/. $OUTPUT/maven/org/opensearch
