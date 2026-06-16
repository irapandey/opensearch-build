# Docker Build Guide for OpenSearch Core 3.5.0

This guide explains how to build OpenSearch Core 3.5.0 using Docker containers.

## Prerequisites

- Docker installed and running
- At least 8GB of RAM allocated to Docker
- At least 20GB of free disk space

## Quick Start

### 1. Build the Docker Image

```bash
docker build -t opensearch-builder:3.5.0 .
```

This creates a container image with all required dependencies:
- AlmaLinux 8 base
- Java 21 OpenJDK
- Python 3.9 with pipenv
- Build tools (gcc, make, git, etc.)

### 2. Run the Build

**Option A: Automated build with output volume**
```bash
docker run -it --rm \
  -v $(pwd)/output:/build/opensearch-build/tar \
  opensearch-builder:3.5.0 \
  /build/opensearch-core.sh
```

This will:
- Clone the opensearch-build repository
- Checkout the `ppc64le-manifest-update` branch
- Build OpenSearch Core 3.5.0 snapshot
- Save artifacts to `./output` directory on your host

**Option B: Interactive mode**
```bash
docker run -it --rm opensearch-builder:3.5.0
```

Then inside the container:
```bash
./opensearch-core.sh
```

### 3. Access Build Artifacts

After successful build, artifacts will be in:
```
output/
├── builds/opensearch/
│   ├── manifest.yml
│   ├── maven/
│   ├── dist/
│   └── core-plugins/
└── dist/
    └── opensearch-3.5.0-SNAPSHOT-linux-x64.tar.gz
```

## Build Script Details

The [`opensearch-core.sh`](opensearch-core.sh:1) script performs:

1. **Repository Setup**
   - Clones `opensearch-build` repository
   - Checks out `ppc64le-manifest-update` branch

2. **Dependency Installation**
   - System packages (gcc, make, etc.)
   - Python environment setup
   - pipenv installation

3. **Build Execution**
   - Builds OpenSearch with all available plugins for ppc64le
   - Uses `--continue-on-error` to skip plugins that don't support ppc64le
   - Creates snapshot build (`-s` flag)
   - Uses manifest: `manifests/3.5.0/opensearch-3.5.0.yml`
   - Note: Some plugins may not build on ppc64le architecture

## Customization

### Build Different Components

Edit the build command in [`opensearch-core.sh`](opensearch-core.sh:26):

```bash
# Build all available plugins (default - continues on errors for ppc64le)
./build.sh manifests/3.5.0/opensearch-3.5.0.yml -s --continue-on-error

# Build only OpenSearch core (no plugins - fastest option)
./build.sh manifests/3.5.0/opensearch-3.5.0.yml -s -c OpenSearch

# Build specific plugins that support ppc64le
./build.sh manifests/3.5.0/opensearch-3.5.0.yml -s -c OpenSearch -c security -c k-NN

# Strict build (fails on first error - not recommended for ppc64le)
./build.sh manifests/3.5.0/opensearch-3.5.0.yml -s
```

### Use Different Branch

Modify the git checkout in [`opensearch-core.sh`](opensearch-core.sh:13):

```bash
git checkout main  # or any other branch
```

### Adjust Memory Limits

```bash
docker run -it --rm \
  --memory=8g \
  --memory-swap=8g \
  -v $(pwd)/output:/build/opensearch-build/tar \
  opensearch-builder:3.5.0 \
  /build/opensearch-core.sh
```

## Troubleshooting

### Build Fails with Out of Memory

Increase Docker memory allocation:
```bash
docker run -it --rm --memory=16g ...
```

### Permission Issues with Output Directory

Create output directory first:
```bash
mkdir -p output
chmod 777 output
```

### Build Script Not Found

Ensure you're running from the directory containing `opensearch-core.sh`:
```bash
ls -la opensearch-core.sh Dockerfile
```

### Git Clone Fails

Check network connectivity and GitHub access:
```bash
docker run -it --rm opensearch-builder:3.5.0 git ls-remote https://github.com/opensearch-project/opensearch-build.git
```

## Advanced Usage

### Keep Container Running for Debugging

```bash
docker run -it --rm \
  -v $(pwd)/output:/build/opensearch-build/tar \
  opensearch-builder:3.5.0 \
  /bin/bash
```

### Mount Local opensearch-build Repository

If you already have the repository locally:
```bash
docker run -it --rm \
  -v $(pwd):/build/opensearch-build \
  -w /build/opensearch-build \
  opensearch-builder:3.5.0 \
  ./build.sh manifests/3.5.0/opensearch-3.5.0.yml -s -c OpenSearch
```

### Multi-stage Build for Smaller Image

See `Dockerfile.multistage` for a production-optimized build that only includes artifacts.

## Build Time

Expected build times:
- First build (with dependency downloads): 30-60 minutes
- Subsequent builds (with cache): 15-30 minutes

Times vary based on:
- CPU cores available
- Network speed (for dependency downloads)
- Disk I/O performance

## Related Files

- [`Dockerfile`](Dockerfile:1) - Container image definition
- [`opensearch-core.sh`](opensearch-core.sh:1) - Build script
- [`manifests/3.5.0/opensearch-3.5.0.yml`](manifests/3.5.0/opensearch-3.5.0.yml:1) - Build manifest
- [`opensearch-core.patch`](opensearch-core.patch:1) - Source patches applied during build