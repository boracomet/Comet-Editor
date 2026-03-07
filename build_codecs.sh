#!/bin/bash
# Build script for codec libraries
# Builds libwebp and libavif as universal static libraries

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/third_party/build"
INSTALL_DIR="${SCRIPT_DIR}/third_party/install"

echo "Building codec libraries..."
echo "Build directory: ${BUILD_DIR}"
echo "Install directory: ${INSTALL_DIR}"

# Clean previous build
# rm -rf "${BUILD_DIR}"
# rm -rf "${INSTALL_DIR}"

build_arch() {
    local arch=$1
    local out_dir="${BUILD_DIR}/${arch}"
    local inst_dir="${INSTALL_DIR}/${arch}"
    
    local aom_cpu="${arch}"
    local webp_simd="ON"
    local yuv_simd="ON"
    if [ "${arch}" == "x86_64" ]; then
        if ! command -v yasm &> /dev/null && ! command -v nasm &> /dev/null; then
            aom_cpu="generic"
        fi
        
        # When cross compiling on arm64 host, webp/yuv CMake incorrectly tests for NEON and enables it for x86_64
        if [ "$(uname -m)" == "arm64" ]; then
            webp_simd="OFF"
            yuv_simd="OFF"
        fi
    fi
    
    local cflags="-O3 -flto=thin -fembed-bitcode=off"
    local cxxflags="-O3 -flto=thin -fembed-bitcode=off"
    if [ "${arch}" == "x86_64" ]; then
        cflags="${cflags} -D_Float16=float"
        cxxflags="${cxxflags} -D_Float16=float"
    fi
    
    echo "Building for architecture: ${arch} (AOM Target: ${aom_cpu}, WEBP SIMD: ${webp_simd})..."
    mkdir -p "${out_dir}"
    cd "${out_dir}"
    
    cmake ../.. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_PROCESSOR="${arch}" \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
        -DCMAKE_INSTALL_PREFIX="${inst_dir}" \
        -DCMAKE_C_FLAGS_RELEASE="${cflags}" \
        -DCMAKE_CXX_FLAGS_RELEASE="${cxxflags}" \
        -DAOM_TARGET_CPU="${aom_cpu}" \
        -DWEBP_ENABLE_SIMD="${webp_simd}" \
        -DENABLE_NEON="${yuv_simd}" \
        -DENABLE_SVE="${yuv_simd}" \
        -DENABLE_SME="${yuv_simd}" \
        -DBUILD_SHARED_LIBS=OFF
        
    # FIX: Native FetchContent of libyuv ignores CMAKE_OSX_ARCHITECTURES and reads CMAKE_SYSTEM_PROCESSOR 
    # as arm64 on Apple Silicon hosts, throwing armv8 compilation errors on x86_64.
    if [ "${arch}" == "x86_64" ] && [ "$(uname -m)" == "arm64" ]; then
        if [ -f "_deps/libyuv-src/CMakeLists.txt" ]; then
            sed -i '' 's/if(arch_lowercase STREQUAL "aarch64" OR arch_lowercase STREQUAL "arm64")/if(FALSE)/g' _deps/libyuv-src/CMakeLists.txt
            sed -i '' 's/if(arch_lowercase MATCHES "^arm" AND NOT arch_lowercase STREQUAL "arm64")/if(FALSE)/g' _deps/libyuv-src/CMakeLists.txt
        fi
    fi
        
    cmake --build . --config Release -j$(sysctl -n hw.ncpu)
    cmake --install . --config Release
}

build_arch "arm64"
# build_arch "x86_64"

echo "Merging into Universal Binaries..."
mkdir -p "${INSTALL_DIR}/lib"
mkdir -p "${INSTALL_DIR}/include"

cp -R "${INSTALL_DIR}/arm64/include/" "${INSTALL_DIR}/include/"

for lib in "${INSTALL_DIR}/arm64/lib/"*.a; do
    libname=$(basename "$lib")
    if [ -f "${INSTALL_DIR}/x86_64/lib/${libname}" ]; then
        echo "Lipo: ${libname}"
        lipo -create -output "${INSTALL_DIR}/lib/${libname}" \
            "${INSTALL_DIR}/arm64/lib/${libname}" \
            "${INSTALL_DIR}/x86_64/lib/${libname}"
    else
        echo "Copying arm64 only: ${libname}"
        cp "${INSTALL_DIR}/arm64/lib/${libname}" "${INSTALL_DIR}/lib/${libname}"
    fi
done

echo ""
echo "Build complete!"
echo "Libraries installed to: ${INSTALL_DIR}/lib"
echo ""
echo "Verifying universal binaries..."

# Verify universal binaries
for lib in "${INSTALL_DIR}"/lib/*.a; do
    if [ -f "$lib" ]; then
        echo "Checking: $(basename "$lib")"
        lipo -info "$lib"
    fi
done

echo ""
echo "Done!"
