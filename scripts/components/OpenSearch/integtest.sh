#!/bin/bash

# Copyright OpenSearch Contributors
# SPDX-License-Identifier: Apache-2.0
#
# The OpenSearch Contributors require contributions made to
# this file be licensed under the Apache-2.0 license or a
# compatible open source license.

set -e

# On ppc64le, the kernel thread limit is tighter than on x86_64/arm64.
# Gradle's default worker count (= CPU cores) combined with JVM GC threads
# exhausts pthread resources, causing "pthread_create failed (EAGAIN)" and
# preventing subprocesses such as javadoc from starting.  Cap workers to 4
# to stay well within the limit on constrained ppc64le CI runners.
if [ "$(uname -m)" = "ppc64le" ]; then
    export GRADLE_OPTS="${GRADLE_OPTS} -Dorg.gradle.workers.max=4"
fi

echo "Check if distribution is deb or rpm on linux"
if [ "$OSTYPE" = "linux-gnu" ]; then
    if (dpkg -s opensearch > /dev/null 2>&1) || (rpm -q opensearch > /dev/null 2>&1); then
        echo "Run systemd integTest for OpenSearch core engine"
        ./gradlew --console=plain qa:systemd-test:integTest --tests org.opensearch.systemdinteg.SystemdIntegTests --console=plain
    else
        echo "No deb or rpm installed detected, skip test"
    fi
else
    echo "Not on linux host, skip test"
fi
