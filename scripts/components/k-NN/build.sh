#!/bin/bash

# Copyright OpenSearch Contributors
# SPDX-License-Identifier: Apache-2.0
#
# The OpenSearch Contributors require contributions made to
# this file be licensed under the Apache-2.0 license or a
# compatible open source license.

# Wrapper build script for k-NN on ppc64le.
#
# The k-NN plugin compiles JNI native libraries (Faiss, NMSLIB, SIMD) via CMake.
# The upstream build script notes "Linux versions already have OpenBlas in the runner"
# — true for x64/arm64 runners, but ppc64le runners do not have these packages
# pre-installed.  We install the required native build dependencies here before
# delegating to the upstream build script that lives in the cloned k-NN repository.
#
# Required packages:
#   cmake          - build system used by the JNI CMakeLists.txt
#   openblas-devel - BLAS/LAPACK implementation; Faiss requires find_package(BLAS/LAPACK REQUIRED);
#                    on RHEL 9 ppc64le this package also provides the LAPACK headers so lapack-devel
#                    is not separately available and not needed
#   gcc-gfortran   - Fortran compiler; Faiss calls enable_language(Fortran)
#   libgomp        - OpenMP runtime; Faiss links OpenMP::OpenMP_CXX
#
# Note: openblas-static and lapack-devel are NOT available in the RHEL 9 ppc64le repositories
# and are therefore not listed here.
#
# ppc64le compiler-flag fix:
#   nmslib's CMakeLists.txt sets -march=native which is an x86/arm GCC flag.  On ppc64le
#   GCC does not accept -march at all.
#
#   We cannot patch the source file directly: the k-NN repo's cmake/init-nmslib.cmake
#   applies a git patch to nmslib via "git apply" after submodule init.  If the working
#   tree has been modified (even by sed), git apply fails with:
#     error: similarity_search/CMakeLists.txt: does not match index
#
#   We also cannot use -mcpu=native: GCC resolves "native" by querying the kernel, and
#   on a Power11 host running GCC 11 (RHEL 9) the kernel reports "power11" which GCC 11
#   does not know yet (its highest is "power10").  The result is:
#     unsupported cpu name returned from kernel for '-mcpu=native': power11
#
#   Solution: install a thin compiler wrapper that replaces -march=native with
#   -mcpu=power10 (the newest micro-arch GCC 11 knows; power10 code runs correctly on
#   power11 due to ISA backward compatibility).  The wrapper is a small shell script
#   created in a per-build temp dir; it does not touch any source file and is completely
#   transparent to git.  cmake picks up $CXX/$CC from the environment and records the
#   wrapper path in CMakeCache.txt, so every cmake invocation uses it.

set -ex

[ -z "$ARCHITECTURE" ] && ARCHITECTURE=$(uname -m)

if [ "$ARCHITECTURE" = "ppc64le" ]; then
    PKG_MANAGER=""
    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    fi

    if [ -n "$PKG_MANAGER" ]; then
        MISSING_PKGS=()
        command -v cmake        &>/dev/null || MISSING_PKGS+=(cmake)
        rpm -q openblas-devel   &>/dev/null || MISSING_PKGS+=(openblas-devel)
        rpm -q gcc-gfortran     &>/dev/null || MISSING_PKGS+=(gcc-gfortran)
        rpm -q libgomp          &>/dev/null || MISSING_PKGS+=(libgomp)

        if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
            echo "Installing missing native build dependencies on ppc64le: ${MISSING_PKGS[*]}"
            $PKG_MANAGER install -y "${MISSING_PKGS[@]}"
        fi
    fi

    # On ppc64le the kernel thread limit is tighter than on x86_64/arm64.
    # Cap Gradle worker count to stay within pthread resource limits.
    export GRADLE_OPTS="${GRADLE_OPTS} -Dorg.gradle.workers.max=4"

    # Install a compiler wrapper that rewrites -march=native -> -mcpu=native.
    # This avoids touching any source file (which would break the upstream git-apply
    # patch in cmake/init-nmslib.cmake).  The wrapper delegates to the real c++
    # compiler after substituting the flag.
    _CXX_WRAPPER_DIR=$(mktemp -d)
    _REAL_CXX=$(command -v c++)
    cat > "$_CXX_WRAPPER_DIR/c++" <<'WRAPPER'
#!/bin/bash
# ppc64le shim: replace -march=native with -mcpu=power10.
# -march=native is x86-only; -mcpu=native would work but GCC 11 on RHEL 9 does not
# recognise 'power11' returned by the kernel on Power11 hosts.  power10 is the newest
# micro-arch GCC 11 knows and runs correctly on power11 (ISA backward compatibility).
REAL_CXX="@REAL_CXX@"
args=()
for arg in "$@"; do
    args+=("${arg/-march=native/-mcpu=power10}")
done
exec "$REAL_CXX" "${args[@]}"
WRAPPER
    # Substitute the real compiler path into the wrapper.
    sed -i "s|@REAL_CXX@|${_REAL_CXX}|g" "$_CXX_WRAPPER_DIR/c++"
    chmod +x "$_CXX_WRAPPER_DIR/c++"

    # Also wrap 'cc' / 'gcc' in case cmake probes the C compiler for the same flag.
    _REAL_CC=$(command -v cc)
    cat > "$_CXX_WRAPPER_DIR/cc" <<'WRAPPER'
#!/bin/bash
# ppc64le shim: same flag replacement as the c++ wrapper above.
REAL_CC="@REAL_CC@"
args=()
for arg in "$@"; do
    args+=("${arg/-march=native/-mcpu=power10}")
done
exec "$REAL_CC" "${args[@]}"
WRAPPER
    sed -i "s|@REAL_CC@|${_REAL_CC}|g" "$_CXX_WRAPPER_DIR/cc"
    chmod +x "$_CXX_WRAPPER_DIR/cc"

    # Point cmake at the wrappers via CXX/CC env vars (cmake reads these before
    # probing PATH, and records them in CMakeCache.txt so subsequent cmake --build
    # invocations also use the wrappers).  Also prepend to PATH as a fallback.
    export CXX="$_CXX_WRAPPER_DIR/c++"
    export CC="$_CXX_WRAPPER_DIR/cc"
    export PATH="$_CXX_WRAPPER_DIR:$PATH"
    echo "Installed ppc64le compiler wrapper in $_CXX_WRAPPER_DIR (real CXX: $_REAL_CXX)"
fi

# Delegate to the k-NN repository's own build script.
exec bash scripts/build.sh "$@"
