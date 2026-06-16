#!/bin/bash
# Build script for OpenSearch Core 3.5.0
# This script builds the OpenSearch distribution tarball from source

set -e

# Clone opensearch-build repository and checkout ppc64le-manifest-update branch
if [ ! -d "opensearch-build/.git" ]; then
    echo "Setting up opensearch-build repository..."
    # Remove non-git files but preserve mounted directories
    if [ -d "opensearch-build" ]; then
        find opensearch-build -mindepth 1 -maxdepth 1 ! -name 'tar' -exec rm -rf {} +
    fi
    echo "Cloning opensearch-build repository..."
    git clone https://github.com/irapandey/opensearch-build.git opensearch-build-temp
    # Move git content to opensearch-build, preserving tar directory
    mv opensearch-build-temp/.git opensearch-build/
    mv opensearch-build-temp/* opensearch-build/ 2>/dev/null || true
    rm -rf opensearch-build-temp
    cd opensearch-build
    git checkout ppc64le-manifest-update
else
    echo "opensearch-build directory already exists, updating..."
    cd opensearch-build
    git fetch origin
    git checkout ppc64le-manifest-update
    git pull origin ppc64le-manifest-update
fi

# Install required dependencies (skip if running in container where packages are pre-installed)
if command -v sudo &> /dev/null; then
    sudo yum install -y git gcc gcc-c++ make patch \
        java-21-openjdk-devel \
        python3.9 python3.9-devel \
        bzip2-devel zlib-devel openssl-devel
else
    echo "Running in container - dependencies already installed"
fi

# Setup Python environment (skip pyenv in container)
if [ ! -d "$HOME/.pyenv" ] && command -v sudo &> /dev/null; then
    curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash
    export PYENV_ROOT="$HOME/.pyenv"
fi

# Setup pip and pipenv (already done in container)
if command -v pipenv &> /dev/null; then
    echo "pipenv already installed"
else
    if command -v sudo &> /dev/null; then
        sudo ln -sf /usr/bin/pip3 /usr/bin/pip
    fi
    pip install pipenv
    python3 -m pipenv --python /usr/bin/python3
fi

# Copy patches to the opensearch-build directory
echo "Copying patches..."
cp /build/common-utils.patch .

# Note: Edit src/build_workflow/build_args.py if needed before building
# vi src/build_workflow/build_args.py

# Build OpenSearch with all plugins (snapshot only)
# Use --continue-on-error to skip plugins that fail on ppc64le
./build.sh manifests/3.5.0/opensearch-3.5.0.yml -s --continue-on-error

# Alternative: Build with continue-on-error flag
# ./build.sh manifests/3.5.0/opensearch-3.5.0.yml --continue-on-error

