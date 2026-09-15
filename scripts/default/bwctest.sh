#!/bin/bash

# Copyright OpenSearch Contributors
# SPDX-License-Identifier: Apache-2.0
#
# The OpenSearch Contributors require contributions made to
# this file be licensed under the Apache-2.0 license or a
# compatible open source license.

set -e

function usage() {
  echo ""
    echo "This script is used to run Backwards Compatibility tests"
    echo "--------------------------------------------------------------------------"
    echo "Usage: $0 [args]"
    echo ""
    echo "Required arguments:"
    echo "None"
    echo ""
    echo -e "-h\tPrint this message."
    echo "--------------------------------------------------------------------------"
}

while getopts ":h" arg; do
    case $arg in
        h)
            usage
            exit 1
            ;;
        ?)
            echo "Invalid option: -${OPTARG}"
            exit 1
            ;;
    esac
done

# On ppc64le, the kernel thread limit is tighter than on x86_64/arm64.
# Gradle's default worker count (= CPU cores) combined with JVM GC threads
# exhausts pthread resources, causing "pthread_create failed (EAGAIN)" and
# preventing subprocesses such as javadoc from starting.  Cap workers to 4
# to stay well within the limit on constrained ppc64le CI runners.
if [ "$(uname -m)" = "ppc64le" ]; then
    export GRADLE_OPTS="${GRADLE_OPTS} -Dorg.gradle.workers.max=4"
fi

./gradlew --console=plain bwcTestSuite -Dtests.security.manager=false -PcustomDistributionDownloadType=bundle
