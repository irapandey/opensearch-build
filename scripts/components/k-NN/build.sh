#!/bin/bash

# Copyright OpenSearch Contributors
# SPDX-License-Identifier: Apache-2.0
#
# The OpenSearch Contributors require contributions made to
# this file be licensed under the Apache-2.0 license or a
# compatible open source license.
#
# This script overrides the upstream k-NN build.sh to add ppc64le support.
# On ppc64le the cmake/JNI native library build is skipped because:
#   - The upstream CMakeLists.txt has no ppc64le MACH_ARCH mapping
#   - AVX2/AVX512 SIMD instructions do not exist on ppc64le (VSX/VMX are different ISA)
#   - The standard CI runner for ppc64le does not install cmake
# The Java plugin artifact is built normally; the native JNI libs are simply absent.

set -ex

function usage() {
    echo "Usage: $0 [args]"
    echo ""
    echo "Arguments:"
    echo -e "-v VERSION\t[Required] OpenSearch version."
    echo -e "-q QUALIFIER\t[Optional] Version qualifier."
    echo -e "-s SNAPSHOT\t[Optional] Build a snapshot, default is 'false'."
    echo -e "-p PLATFORM\t[Optional] Platform, ignored."
    echo -e "-a ARCHITECTURE\t[Optional] Build architecture."
    echo -e "-o OUTPUT\t[Optional] Output path, default is 'artifacts'."
    echo -e "-j NPROC_COUNT\t[Optional] Number of CPUs to use when building JNI library. Default is 1."
    echo -e "-h help"
}

while getopts ":h:v:q:s:o:p:a:j:" arg; do
    case $arg in
        h)
            usage
            exit 1
            ;;
        v)
            VERSION=$OPTARG
            ;;
        s)
            SNAPSHOT=$OPTARG
            ;;
        q)
            QUALIFIER=$OPTARG
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
        j)
            NPROC_COUNT=$OPTARG
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

work_dir=$PWD

# Pull library submodule explicitly. While "cmake ." actually pulls the submodule if its not there, we
# need to pull it before calling cmake. Also, we need to call it from the root git directory.
# Otherwise, the submodule update call may fail on earlier versions of git.
git submodule update --init -- jni/external/nmslib
git submodule update --init -- jni/external/faiss

if [ "$JAVA_HOME" = "" ]; then
    export JAVA_HOME=`/usr/libexec/java_home`
    echo "SET JAVA_HOME=$JAVA_HOME"
fi

# ppc64le: skip cmake/JNI native library compilation entirely.
# The upstream CMakeLists.txt does not define MACH_ARCH for ppc64le and the AVX/NEON
# SIMD flags used by the faiss/nmslib targets are x64/arm64-only.  cmake is also
# not guaranteed to be installed on the ppc64le CI runner.
if [ "$ARCHITECTURE" = "ppc64le" ]; then
    echo "ppc64le detected: skipping JNI native library build (cmake not required)"

    # Build the Java plugin only (no native lib, no integTest, no unit test)
    ./gradlew build --no-daemon --refresh-dependencies -x integTest -x test \
        -Dopensearch.version=$VERSION \
        -Dbuild.snapshot=$SNAPSHOT \
        -Dbuild.version_qualifier=$QUALIFIER \
        -Dbuild.lib.commit_patches=false

else
    # x64/arm64: use the full upstream build path

    # Setup knnlib build params
    cd jni

    # For x64, generalize arch so library is compatible for processors without simd instruction extensions
    if [ "$ARCHITECTURE" = "x64" ]; then
        NMSLIB_SIMD_FLAGS="x86-64"
    fi

    # For arm, march=native is broken in centos 7. Manually override to lowest version of armv8.
    if [ "$ARCHITECTURE" = "arm64" ]; then
        NMSLIB_SIMD_FLAGS="armv8-a"
    fi

    # Ensure gcc version is above the minimum required
    GCC_VERSION=`gcc --version | head -n 1 | cut -d ' ' -f3`
    if [ "$ARCHITECTURE" = "x64" ]; then
        GCC_REQUIRED_VERSION=12.4
    else
        GCC_REQUIRED_VERSION=9.0.0
    fi
    COMPARE_VERSION=`echo $GCC_REQUIRED_VERSION $GCC_VERSION | tr ' ' '\n' | sort -V | uniq | head -n 1`
    if [ "$COMPARE_VERSION" != "$GCC_REQUIRED_VERSION" ]; then
        echo "gcc version on this env is older than $GCC_REQUIRED_VERSION, exit 1"
        exit 1
    fi

    cd $work_dir
    ./gradlew build --no-daemon --refresh-dependencies -x integTest -x test -Dopensearch.version=$VERSION -Dbuild.snapshot=$SNAPSHOT -Dbuild.version_qualifier=$QUALIFIER -Dbuild.lib.commit_patches=false -Dnmslib_simd_flags=$NMSLIB_SIMD_FLAGS
    ./gradlew :buildJniLib -Pknn_libs=opensearchknn_faiss,opensearchknn_simd -Davx512.enabled=false -Davx512_spr.enabled=false -Davx2.enabled=false -Dbuild.lib.commit_patches=false -Dnproc.count=${NPROC_COUNT:-1} -Dbuild.snapshot=$SNAPSHOT

    if [ "$PLATFORM" != "windows" ] && [ "$ARCHITECTURE" = "x64" ]; then
        echo "Building k-NN library nmslib with gcc 10 on non-windows x64"
        rm -rf jni/build/CMakeCache.txt jni/build/CMakeFiles
        env CC=gcc10-gcc CXX=gcc10-g++ FC=gcc10-gfortran ./gradlew :buildJniLib -Pknn_libs=opensearchknn_nmslib -Dbuild.lib.commit_patches=false -Dbuild.lib.apply_patches=false -Dbuild.snapshot=$SNAPSHOT

        echo "Building k-NN library after enabling AVX2"
        rm -rf jni/build/CMakeCache.txt jni/build/CMakeFiles
        ./gradlew :buildJniLib -Pknn_libs=opensearchknn_faiss,opensearchknn_simd -Davx2.enabled=true -Davx512.enabled=false -Davx512_spr.enabled=false -Dbuild.lib.commit_patches=false -Dbuild.lib.apply_patches=false -Dbuild.snapshot=$SNAPSHOT

        echo "Building k-NN library after enabling AVX512"
        ./gradlew :buildJniLib -Pknn_libs=opensearchknn_faiss,opensearchknn_simd -Davx512.enabled=true -Davx512_spr.enabled=false -Dbuild.lib.commit_patches=false -Dbuild.lib.apply_patches=false -Dbuild.snapshot=$SNAPSHOT

        echo "Building k-NN library after enabling AVX512_SPR"
        ./gradlew :buildJniLib -Pknn_libs=opensearchknn_faiss,opensearchknn_simd -Davx512_spr.enabled=true -Dbuild.lib.commit_patches=false -Dbuild.lib.apply_patches=false -Dbuild.snapshot=$SNAPSHOT
    else
        ./gradlew :buildJniLib -Pknn_libs=opensearchknn_nmslib -Dbuild.lib.commit_patches=false -Dbuild.lib.apply_patches=false -Dbuild.snapshot=$SNAPSHOT
    fi
fi

./gradlew publishPluginZipPublicationToZipStagingRepository -Dopensearch.version=$VERSION -Dbuild.snapshot=$SNAPSHOT -Dbuild.version_qualifier=$QUALIFIER
./gradlew publishPluginZipPublicationToMavenLocal -Dbuild.snapshot=$SNAPSHOT -Dbuild.version_qualifier=$QUALIFIER -Dopensearch.version=$VERSION

# Add lib to zip (only for platforms that build native libs)
zipPath=$(find "$(pwd)/build/distributions" -path \*.zip)
distributions="$(dirname "${zipPath}")"

if [ "$ARCHITECTURE" != "ppc64le" ]; then
    mkdir -p $distributions/lib
    libPrefix="libopensearchknn"
    if [ "$PLATFORM" = "windows" ]; then
        libPrefix="opensearchknn"
        cp -v ./src/main/resources/windowsDependencies/libopenblas.dll $distributions/lib

        # Have to define $MINGW_BIN either in ENV VAR or User Provided Var
        cp -v "$MINGW_BIN/libgcc_s_seh-1.dll" $distributions/lib
        cp -v "$MINGW_BIN/libwinpthread-1.dll" $distributions/lib
        cp -v "$MINGW_BIN/libstdc++-6.dll" $distributions/lib
        cp -v "$MINGW_BIN/libgomp-1.dll" $distributions/lib
    else
        ompPath=$(ldconfig -p | grep libgomp | cut -d ' ' -f 4)
        cp -v $ompPath $distributions/lib
    fi
    cp -v ./jni/build/release/${libPrefix}* $distributions/lib
    ls -l $distributions/lib

    # Add lib directory to the k-NN plugin zip
    cd $distributions
    zip -ur $zipPath lib
    cd $work_dir
fi

echo "COPY ${distributions}/*.zip"
mkdir -p $OUTPUT/plugins
cp -v ${distributions}/*.zip $OUTPUT/plugins

mkdir -p $OUTPUT/maven/org/opensearch
cp -r ./build/local-staging-repo/org/opensearch/. $OUTPUT/maven/org/opensearch
