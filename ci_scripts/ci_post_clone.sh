#!/bin/bash

# Xcode Cloud post-clone script
# This script runs after the repository is cloned but before the build starts

set -e

echo "=========================================="
echo "Xcode Cloud Build Preparation"
echo "=========================================="

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Verifying ImageMagick (universal) static libs..."

if [ ! -d "third_party/imagemagick/universal/include/ImageMagick-7" ]; then
    echo "ERROR: third_party/imagemagick/universal/include/ImageMagick-7 not found!"
    exit 1
fi

if [ ! -d "third_party/imagemagick/universal/lib" ]; then
    echo "ERROR: third_party/imagemagick/universal/lib not found!"
    exit 1
fi

echo "✓ ImageMagick headers and libs:"
ls -la third_party/imagemagick/universal/lib/*.a 2>/dev/null | head -5 || true

echo ""
echo "=========================================="
echo "Build preparation complete!"
echo "=========================================="
