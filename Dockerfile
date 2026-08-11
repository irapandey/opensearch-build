# Dockerfile for building OpenSearch 3.7.0 with all plugins on ppc64le
# This container provides all dependencies needed to run the opensearch-build pipeline

FROM registry.access.redhat.com/ubi9/ubi

# Set working directory
WORKDIR /opensearch-build

# Install system dependencies
RUN yum install -y --allowerasing \
    git \
    gcc \
    gcc-c++ \
    gcc-gfortran \
    make \
    patch \
    tar \
    unzip \
    zip \
    which \
    curl \
    jq \
    python3 \
    python3-devel \
    python3-pip \
    bzip2-devel \
    zlib-devel \
    openssl-devel \
    libffi-devel \
    xz-devel \
    rpm-build \
    && yum clean all

# Install Temurin JDK 25 for ppc64le (required by the 3.7.0 manifest)
RUN curl -LfsSo /tmp/jdk25.tar.gz \
    "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25%2B36/OpenJDK25U-jdk_ppc64le_linux_hotspot_25_36.tar.gz" && \
    echo "b060bb12b3a192a0599f03ebb9495492f78c48cb61e291e336a8b00e7798ffb0  /tmp/jdk25.tar.gz" | sha256sum -c - && \
    mkdir -p /opt/java/openjdk-25 && \
    tar -xf /tmp/jdk25.tar.gz --strip-components=1 -C /opt/java/openjdk-25 && \
    rm -f /tmp/jdk25.tar.gz

# Set Java environment
ENV JAVA_HOME=/opt/java/openjdk-25
ENV PATH=$JAVA_HOME/bin:$PATH

# Install Maven
RUN MAVEN_URL=$(curl -s https://maven.apache.org/download.cgi \
        | grep -Eo '["\047].*.bin.tar.gz["\047]' | tr -d "\"'" | uniq | head -n 1) && \
    mkdir -p /usr/local/apache-maven && \
    curl -s "$MAVEN_URL" | tar xzf - --strip-components=1 -C /usr/local/apache-maven && \
    ln -sfn /usr/local/apache-maven/bin/mvn /usr/local/bin/mvn

# Install pipenv (pin setuptools+virtualenv to avoid packaging incompatibility with pipenv 2023.6.12)
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --ignore-installed \
        "setuptools==67.8.0" \
        "virtualenv==20.24.5" \
        "pipenv==2023.6.12"

# Copy the build repo
COPY . .

# Pre-install Python dependencies
RUN python3 -m pipenv install --deploy --ignore-pipfile

# Set default command
CMD ["/bin/bash"]

# Usage:
# Build the image:
#   docker build -t opensearch-build:3.7.0-ppc64le .
#
# Run the full build (all plugins, continue past individual failures):
#   docker run --rm -v $(pwd)/artifacts:/opensearch-build/tar opensearch-build:3.7.0-ppc64le \
#     ./build.sh manifests/3.7.0/opensearch-3.7.0.yml -a ppc64le --continue-on-error
#
# Output on the host after the run:
#   ./artifacts/builds/opensearch/plugins/*.zip   <- plugin zip files
#   ./artifacts/builds/opensearch/maven/          <- Maven artifacts
#   ./artifacts/builds/opensearch/manifest.yml    <- build manifest (lists every artifact + git sha)
#
# Build a single component:
#   docker run --rm -v $(pwd)/artifacts:/opensearch-build/tar opensearch-build:3.7.0-ppc64le \
#     ./build.sh manifests/3.7.0/opensearch-3.7.0.yml -a ppc64le --component cross-cluster-replication
#
# Interactive mode (inspect output without removing the container):
#   docker run -it --rm opensearch-build:3.7.0-ppc64le

# Made with Bob
