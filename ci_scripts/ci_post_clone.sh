#!/bin/bash

# Xcode Cloud post-clone script
# This script runs after the repository is cloned but before the build starts

set -e

echo "=========================================="
echo "Xcode Cloud Build Preparation"
echo "=========================================="

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Verify pre-built libraries exist
echo "Verifying pre-built libraries..."

if [ ! -d "third_party/install/include" ]; then
    echo "ERROR: third_party/install/include not found!"
    exit 1
fi

if [ ! -d "third_party/ffmpeg_install/universal/include" ]; then
    echo "ERROR: third_party/ffmpeg_install/universal/include not found!"
    exit 1
fi

echo "✓ Image codec headers found:"
ls -la third_party/install/include/

echo ""
echo "✓ Video codec headers found:"
ls -la third_party/ffmpeg_install/universal/include/

echo ""
echo "=========================================="
echo "Build preparation complete!"
echo "=========================================="
