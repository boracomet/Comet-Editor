#!/bin/bash
# Minimal FFmpeg build script for CometVideoCodec (CVC)
# Compiles universal static libraries for macOS (arm64 & x86_64)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_DIR="${SCRIPT_DIR}/third_party/ffmpeg_src"
BUILD_DIR="${SCRIPT_DIR}/third_party/ffmpeg_build"
INSTALL_DIR="${SCRIPT_DIR}/third_party/ffmpeg_install"
FFMPEG_VERSION="7.0"

echo "================================================"
echo "    CometVideoCodec: FFmpeg Static Builder      "
echo "================================================"
echo "Source dir: ${FFMPEG_DIR}"
echo "Build dir:  ${BUILD_DIR}"
echo "Install dir: ${INSTALL_DIR}"
echo "================================================"

# 1. Download FFmpeg if not present
if [ ! -d "${FFMPEG_DIR}" ]; then
    echo "Downloading FFmpeg ${FFMPEG_VERSION}..."
    mkdir -p "${SCRIPT_DIR}/third_party"
    curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2" -o "${SCRIPT_DIR}/third_party/ffmpeg.tar.bz2"
    tar -xf "${SCRIPT_DIR}/third_party/ffmpeg.tar.bz2" -C "${SCRIPT_DIR}/third_party"
    mv "${SCRIPT_DIR}/third_party/ffmpeg-${FFMPEG_VERSION}" "${FFMPEG_DIR}"
    rm "${SCRIPT_DIR}/third_party/ffmpeg.tar.bz2"
fi

# Minimal configure flags: 
# We disable almost everything. We only need demuxers and decoders to read files and extract raw frames.
# NO ENCODERS. AVFoundation will do the encoding.
COMMON_FLAGS=(
    "--disable-shared"
    "--enable-static"
    "--disable-doc"
    "--disable-programs"
    "--disable-avdevice"
    "--disable-avformat"
    "--disable-swresample"
    "--disable-postproc"
    "--disable-avfilter"
    "--disable-network"
    "--disable-everything"
    "--enable-decoder=h264,hevc,vp8,vp9,mpeg4,mp3,aac,flac,opus,vorbis"
    "--enable-demuxer=mov,mp4,m4a,3gp,3g2,mj2,avi,matroska,webm,flv,mpegts,wav,ogg,flac"
    "--enable-parser=h264,hevc,vp8,vp9,mpeg4video,aac,opus,vorbis"
    "--enable-protocol=file"
    "--enable-avformat"
    "--enable-swscale"
    "--enable-swresample"
    "--disable-x86asm" # To avoid yasm/nasm dependency for now, we rely on Apple's clang optimizations and FFmpeg's C fallbacks if asm is disabled. We can enable it later if needed.
    "--enable-cross-compile"
    "--target-os=darwin"
)

build_arch() {
    local arch=$1
    local extra_flags=()
    local cc="clang"
    local cxx="clang++"

    echo ""
    echo ">>> Building FFmpeg for Architecture: ${arch} <<<"
    echo ""

    local out_dir="${BUILD_DIR}/${arch}"
    local inst_dir="${INSTALL_DIR}/${arch}"
    
    mkdir -p "${out_dir}"
    cd "${FFMPEG_DIR}" # FFmpeg configure is best run from source dir or with specific setup, but lets do out-of-tree:
    
    # Actually, FFmpeg supports out-of-tree builds
    cd "${out_dir}"

    if [ "${arch}" == "arm64" ]; then
        extra_flags+=("--arch=aarch64" "--cpu=apple-m1")
    elif [ "${arch}" == "x86_64" ]; then
        extra_flags+=("--arch=x86_64")
    fi

    # Run configure
    "${FFMPEG_DIR}/configure" \
        --prefix="${inst_dir}" \
        --cc="${cc} -arch ${arch} -mmacosx-version-min=13.0" \
        --cxx="${cxx} -arch ${arch} -mmacosx-version-min=13.0" \
        "${COMMON_FLAGS[@]}" \
        "${extra_flags[@]}"

    # Compile and install
    make -j$(sysctl -n hw.ncpu)
    make install
}

# Clean old build data to avoid conflicts
rm -rf "${BUILD_DIR}"
rm -rf "${INSTALL_DIR}"

# Compile for both architectures
build_arch "arm64"
build_arch "x86_64"

# Merge into Universal Binaries
echo ""
echo ">>> Merging into Universal Binaries (Fat Lipo) <<<"
echo ""

FINAL_INSTALL_DIR="${INSTALL_DIR}/universal"
mkdir -p "${FINAL_INSTALL_DIR}/lib"
mkdir -p "${FINAL_INSTALL_DIR}/include"

# Copy headers from one of the archs (they are identical)
cp -R "${INSTALL_DIR}/arm64/include/" "${FINAL_INSTALL_DIR}/include/"

# Find all .a files and lipo them
for lib in "${INSTALL_DIR}/arm64/lib/"*.a; do
    libname=$(basename "$lib")
    if [ -f "${INSTALL_DIR}/x86_64/lib/${libname}" ]; then
        echo "Lipo: ${libname}"
        lipo -create -output "${FINAL_INSTALL_DIR}/lib/${libname}" \
            "${INSTALL_DIR}/arm64/lib/${libname}" \
            "${INSTALL_DIR}/x86_64/lib/${libname}"
    else
        echo "Copying arm64 only: ${libname}"
        cp "${INSTALL_DIR}/arm64/lib/${libname}" "${FINAL_INSTALL_DIR}/lib/${libname}"
    fi
done

echo ""
echo "================================================"
echo "   FFmpeg Build Complete!                       "
echo "   Universal Libraries at: ${FINAL_INSTALL_DIR}/lib "
echo "================================================"

# Verify universal binaries
for lib in "${FINAL_INSTALL_DIR}"/lib/*.a; do
    if [ -f "$lib" ]; then
        echo "Checking: $(basename "$lib")"
        lipo -info "$lib"
    fi
done

echo "Done!"
