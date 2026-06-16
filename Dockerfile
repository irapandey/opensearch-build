# Dockerfile for building OpenSearch Core 3.5.0
# This container provides all dependencies needed to build OpenSearch from source

FROM registry.access.redhat.com/ubi9/ubi

# Set working directory
WORKDIR /build

# Install system dependencies
RUN yum install -y \
    git \
    gcc \
    gcc-c++ \
    make \
    patch \
    java-21-openjdk-devel \
    python3 \
    python3-devel \
    python3-pip \
    bzip2-devel \
    zlib-devel \
    openssl-devel \
    which \
    && yum clean all

# Set Java environment
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk
ENV PATH=$JAVA_HOME/bin:$PATH

# Install pipenv (avoid upgrading system setuptools)
RUN python3 -m pip install --user --upgrade pip && \
    python3 -m pip install --user pipenv

# Add user pip binaries to PATH
ENV PATH="/root/.local/bin:$PATH"

# Create symbolic link for pip
RUN ln -sf /usr/bin/pip3 /usr/bin/pip

# Copy the build script and patches
COPY opensearch-core.sh /build/opensearch-core.sh
COPY common-utils.patch /build/common-utils.patch
RUN chmod +x /build/opensearch-core.sh

# Set default command
CMD ["/bin/bash"]

# Usage:
# Build the image:
#   docker build -t opensearch-builder:3.5.0 .
#
# Run the build:
#   docker run -it --rm -v $(pwd)/output:/build/opensearch-build/tar opensearch-builder:3.5.0 /build/opensearch-core.sh
#
# Interactive mode:
#   docker run -it --rm opensearch-builder:3.5.0
#   Then run: ./opensearch-core.sh

# Made with Bob
