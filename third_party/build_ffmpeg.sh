#!/bin/bash
# build_ffmpeg.sh — FFmpeg statik binary build scripti
# macOS arm64 + x86_64 universal binary üretir.
# Tüm codec'ler statik link edilir; yalnızca macOS system framework'lerine bağımlıdır.
# 0 Homebrew / 0 dış dylib bağımlılığı.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFMPEG_DIR="$SCRIPT_DIR/ffmpeg"
SRC="$FFMPEG_DIR/src"
ARM64_PREFIX="$FFMPEG_DIR/arm64"
X86_PREFIX="$FFMPEG_DIR/x86_64"
UNIVERSAL_DIR="$FFMPEG_DIR/universal"
SDK=$(xcrun --sdk macosx --show-sdk-path)
JOBS=$(sysctl -n hw.logicalcpu)

FFMPEG_VER="7.1.1"
FFMPEG_TAR="ffmpeg-$FFMPEG_VER.tar.xz"

# Bağımlılıklar: x264, x265, libvpx, opus, lame (mp3), fdk-aac
# Bunları da statik derleyeceğiz.
X264_VER="stable"
X265_VER="4.1"
VPX_VER="1.15.1"
OPUS_VER="1.5.2"
LAME_VER="3.100"

MACOS_MIN_ARM="11.0"
MACOS_MIN_X86="10.15"

log() { echo ""; echo "══════════════════════════════════════"; echo "  $1"; echo "══════════════════════════════════════"; }
ok()  { echo "  ✓ $1"; }

mkdir -p "$SRC" "$ARM64_PREFIX" "$X86_PREFIX" "$UNIVERSAL_DIR"

# ─── Kaynak indir ─────────────────────────────────────────────────────────────
download_sources() {
    cd "$SRC"

    if [ ! -f "$FFMPEG_TAR" ]; then
        log "FFmpeg $FFMPEG_VER indiriliyor..."
        curl -fSL "https://ffmpeg.org/releases/$FFMPEG_TAR" -o "$FFMPEG_TAR"
    fi

    if [ ! -d "x264" ]; then
        log "x264 indiriliyor..."
        git clone --depth=1 https://code.videolan.org/videolan/x264.git x264 2>/dev/null || \
        git clone --depth=1 https://github.com/mirror/x264.git x264
    fi

    if [ ! -f "x265_$X265_VER.tar.gz" ]; then
        log "x265 $X265_VER indiriliyor..."
        curl -fSL "https://bitbucket.org/multicoreware/x265_git/downloads/x265_$X265_VER.tar.gz" \
            -o "x265_$X265_VER.tar.gz" || \
        curl -fSL "https://github.com/videolan/x265/archive/refs/tags/$X265_VER.tar.gz" \
            -o "x265_$X265_VER.tar.gz"
    fi

    if [ ! -f "libvpx-$VPX_VER.tar.gz" ]; then
        log "libvpx $VPX_VER indiriliyor..."
        curl -fSL "https://github.com/webmproject/libvpx/archive/v$VPX_VER.tar.gz" \
            -o "libvpx-$VPX_VER.tar.gz"
    fi

    if [ ! -f "opus-$OPUS_VER.tar.gz" ]; then
        log "Opus $OPUS_VER indiriliyor..."
        curl -fSL "https://downloads.xiph.org/releases/opus/opus-$OPUS_VER.tar.gz" \
            -o "opus-$OPUS_VER.tar.gz"
    fi

    if [ ! -f "lame-$LAME_VER.tar.gz" ]; then
        log "LAME $LAME_VER indiriliyor..."
        curl -fSL "https://downloads.sourceforge.net/project/lame/lame/$LAME_VER/lame-$LAME_VER.tar.gz" \
            -o "lame-$LAME_VER.tar.gz"
    fi
}

# ─── Tek mimari için tüm bağımlılıkları + FFmpeg derle ────────────────────────
build_for_arch() {
    local ARCH=$1
    local PREFIX=$2
    local MIN=$3

    local CFLAGS_BASE="-arch $ARCH -mmacosx-version-min=$MIN -isysroot $SDK -O2"
    local CXXFLAGS_BASE="$CFLAGS_BASE"
    local LDFLAGS_BASE="-arch $ARCH -mmacosx-version-min=$MIN -isysroot $SDK"

    log "═══ Bağımlılıklar derlenıyor: $ARCH ═══"

    mkdir -p "$PREFIX/lib" "$PREFIX/include" "$PREFIX/lib/pkgconfig"

    cd "$SRC"

    # ── x264 ──────────────────────────────────────────────────────────────────
    log "x264 ($ARCH)"
    rm -rf "x264_build_$ARCH"
    cp -r x264 "x264_build_$ARCH"
    cd "x264_build_$ARCH"
    # x265 CMP0025 benzeri cmake sorunları yok, x264 autoconf tabanlı
    # x86_64 cross-compile için --host gerekiyor ama tek makine
    CC="clang" CFLAGS="$CFLAGS_BASE" LDFLAGS="$LDFLAGS_BASE" \
    ./configure \
        --prefix="$PREFIX" \
        --enable-static \
        --disable-shared \
        --disable-cli \
        --disable-opencl \
        --host="$ARCH-apple-darwin" \
        --extra-cflags="$CFLAGS_BASE" \
        --extra-ldflags="$LDFLAGS_BASE" \
        >/dev/null 2>&1
    make -j"$JOBS" >/dev/null 2>&1
    make install >/dev/null 2>&1
    ok "x264 done"
    cd "$SRC"

    # ── x265 ──────────────────────────────────────────────────────────────────
    log "x265 $X265_VER ($ARCH)"
    rm -rf "x265_$X265_VER"
    tar -xf "x265_$X265_VER.tar.gz" 2>/dev/null || true
    local X265_DIR
    X265_DIR=$(ls -d x265_* x265-* 2>/dev/null | grep -v ".tar" | head -1)
    if [ -z "$X265_DIR" ]; then
        echo "x265 kaynak dizini bulunamadı, atlanıyor..."
    else
        cd "$X265_DIR/source"
        rm -rf "build_$ARCH"
        # cmake policy fix
        sed -i '' 's/cmake_policy(SET CMP0025 OLD)/cmake_policy(SET CMP0025 NEW)/' CMakeLists.txt 2>/dev/null || true
        sed -i '' 's/cmake_policy(SET CMP0054 OLD)/cmake_policy(SET CMP0054 NEW)/' CMakeLists.txt 2>/dev/null || true
        cmake -S . -B "build_$ARCH" \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
            -DENABLE_SHARED=OFF \
            -DENABLE_CLI=OFF \
            -DENABLE_ASSEMBLY=OFF \
            >/dev/null 2>&1
        cmake --build "build_$ARCH" -j"$JOBS" >/dev/null 2>&1
        cmake --install "build_$ARCH" >/dev/null 2>&1
        ok "x265 done"
        cd "$SRC"
    fi

    # ── libvpx ────────────────────────────────────────────────────────────────
    log "libvpx $VPX_VER ($ARCH)"
    rm -rf "libvpx-$VPX_VER"
    tar -xf "libvpx-$VPX_VER.tar.gz"
    cd "libvpx-$VPX_VER"

    local VPX_TARGET
    if [ "$ARCH" = "arm64" ]; then
        VPX_TARGET="arm64-darwin22-gcc"
    else
        VPX_TARGET="x86_64-darwin17-gcc"
    fi

    CC="clang" CXX="clang++" \
    CFLAGS="$CFLAGS_BASE" CXXFLAGS="$CXXFLAGS_BASE" \
    LDFLAGS="$LDFLAGS_BASE" \
    ./configure \
        --prefix="$PREFIX" \
        --target="$VPX_TARGET" \
        --disable-shared \
        --enable-static \
        --disable-examples \
        --disable-tools \
        --disable-docs \
        --disable-unit-tests \
        >/dev/null 2>&1
    make -j"$JOBS" >/dev/null 2>&1
    make install >/dev/null 2>&1
    ok "libvpx done"
    cd "$SRC"

    # ── Opus ──────────────────────────────────────────────────────────────────
    log "Opus $OPUS_VER ($ARCH)"
    rm -rf "opus-$OPUS_VER"
    tar -xf "opus-$OPUS_VER.tar.gz"
    cd "opus-$OPUS_VER"
    CFLAGS="$CFLAGS_BASE" LDFLAGS="$LDFLAGS_BASE" \
    ./configure \
        --prefix="$PREFIX" \
        --enable-static \
        --disable-shared \
        --disable-doc \
        --disable-extra-programs \
        >/dev/null 2>&1
    make -j"$JOBS" >/dev/null 2>&1
    make install >/dev/null 2>&1
    ok "Opus done"
    cd "$SRC"

    # ── LAME (mp3) ────────────────────────────────────────────────────────────
    log "LAME $LAME_VER ($ARCH)"
    rm -rf "lame-$LAME_VER"
    tar -xf "lame-$LAME_VER.tar.gz"
    cd "lame-$LAME_VER"
    local LAME_HOST
    if [ "$ARCH" = "arm64" ]; then
        LAME_HOST="aarch64-apple-darwin"
    else
        LAME_HOST="x86_64-apple-darwin"
    fi
    CFLAGS="$CFLAGS_BASE" LDFLAGS="$LDFLAGS_BASE" \
    ./configure \
        --prefix="$PREFIX" \
        --enable-static \
        --disable-shared \
        --disable-frontend \
        --host="$LAME_HOST" \
        >/dev/null 2>&1
    make -j"$JOBS" >/dev/null 2>&1
    make install >/dev/null 2>&1
    # LAME pkg-config stub
    cat > "$PREFIX/lib/pkgconfig/mp3lame.pc" <<PCEOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libmp3lame
Description: MPEG Audio Layer III encoder
Version: 3.100
Libs: -L\${libdir} -lmp3lame
Libs.private: -lm
Cflags: -I\${includedir}
PCEOF
    ok "LAME done"
    cd "$SRC"

    # ── FFmpeg ────────────────────────────────────────────────────────────────
    log "FFmpeg $FFMPEG_VER ($ARCH)"
    # Her mimari için ayrı build dizini kullan (nesne dosyaları karışmasın)
    local FFMPEG_BUILD_DIR="/tmp/ffmpeg_build_$ARCH"
    rm -rf "$FFMPEG_BUILD_DIR"
    mkdir -p "$FFMPEG_BUILD_DIR"
    tar -xf "$FFMPEG_TAR" -C "$FFMPEG_BUILD_DIR"
    cd "$FFMPEG_BUILD_DIR/ffmpeg-$FFMPEG_VER"

    # ffmpeg'in kendi pkg-config'inin bağımlılık prefix'ini bilmesi için
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    CC="clang" CXX="clang++" \
    CFLAGS="$CFLAGS_BASE -I$PREFIX/include" \
    LDFLAGS="$LDFLAGS_BASE -L$PREFIX/lib" \
    ./configure \
        --prefix="$PREFIX" \
        --arch="$ARCH" \
        --target-os=darwin \
        --cc="clang" \
        --extra-cflags="$CFLAGS_BASE -I$PREFIX/include" \
        --extra-ldflags="$LDFLAGS_BASE -L$PREFIX/lib -liconv" \
        --pkg-config-flags="--static" \
        --disable-shared \
        --enable-static \
        --disable-debug \
        --disable-doc \
        --disable-htmlpages \
        --disable-manpages \
        --disable-podpages \
        --disable-txtpages \
        --enable-gpl \
        --enable-version3 \
        --enable-nonfree \
        --disable-autodetect \
        --enable-pthreads \
        --enable-zlib \
        --enable-bzlib \
        --enable-iconv \
        --enable-videotoolbox \
        --enable-audiotoolbox \
        --enable-coreimage \
        --enable-avfoundation \
        --disable-openssl \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libvpx \
        --enable-libopus \
        --enable-libmp3lame \
        --enable-decoder=aac,aac_latm,ac3,mp3,mp3float,vorbis,flac,opus,h264,hevc,vp8,vp9,mpeg1video,mpeg2video,mpeg4,mjpeg,png,gif,tiff,bmp \
        --enable-encoder=libx264,libx265,libvpx_vp8,libvpx_vp9,libopus,libmp3lame,aac,mpeg4,mjpeg,png,gif,tiff,bmp,mpeg2video,mp2 \
        --enable-demuxer=mov,mp4,matroska,avi,flv,mpegps,mpegts,webm,m4v,ogg,wav,aiff,flac,mp3,3gp,3g2 \
        --enable-muxer=mp4,mov,matroska,avi,flv,mpegts,webm,ogg,wav,aiff,flac,mp3,adts,3gp,3g2,m4v,ipod,mpeg1video,mpeg2video,asf \
        --enable-protocol=file,pipe,crypto,data \
        --enable-filter=scale,fps,setpts,aresample,pan,volume,loudnorm,crop,pad,hflip,vflip,transpose,rotate,trim,format,null,anull \
        --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc \
        --disable-network \
        --disable-avdevice \
        --disable-postproc \
        >/dev/null 2>&1

    make -j"$JOBS" >/dev/null 2>&1
    make install >/dev/null 2>&1
    ok "FFmpeg done"

    echo ""
    echo "✓ FFmpeg ($ARCH) tamamlandı: $PREFIX/bin/ffmpeg"
    "$PREFIX/bin/ffmpeg" -version 2>/dev/null | head -2
    echo "  Bağımlılıklar:"
    otool -L "$PREFIX/bin/ffmpeg" | grep -v "^$PREFIX/bin/ffmpeg" | head -10
    rm -rf "$FFMPEG_BUILD_DIR"
    cd "$SRC"
}

# ─── Ana akış ─────────────────────────────────────────────────────────────────
download_sources

log "ARM64 build başlıyor..."
build_for_arch arm64 "$ARM64_PREFIX" "$MACOS_MIN_ARM"

log "x86_64 build başlıyor..."
build_for_arch x86_64 "$X86_PREFIX" "$MACOS_MIN_X86"

# ─── Universal binary oluştur ─────────────────────────────────────────────────
log "Universal binary oluşturuluyor..."
mkdir -p "$UNIVERSAL_DIR"

for binary in ffmpeg ffprobe; do
    ARM_BIN="$ARM64_PREFIX/bin/$binary"
    X86_BIN="$X86_PREFIX/bin/$binary"
    OUT="$UNIVERSAL_DIR/$binary"

    if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
        lipo -create "$ARM_BIN" "$X86_BIN" -output "$OUT"
        chmod +x "$OUT"
        echo "✓ Universal: $binary"
        lipo -info "$OUT"
    elif [ -f "$ARM_BIN" ]; then
        cp "$ARM_BIN" "$OUT"
        chmod +x "$OUT"
        echo "⚠ arm64 only: $binary"
    else
        echo "✗ $binary bulunamadı"
    fi
done

echo ""
echo "✅ FFmpeg universal binary hazır!"
echo "   $UNIVERSAL_DIR/ffmpeg"
echo "   $UNIVERSAL_DIR/ffprobe"
echo ""
echo "Bağımlılıklar (sadece system framework'ler olmalı):"
otool -L "$UNIVERSAL_DIR/ffmpeg" 2>/dev/null | grep -v "^$UNIVERSAL_DIR" | head -15
