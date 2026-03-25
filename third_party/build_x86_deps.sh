#!/bin/bash
# x86_64 static dependency builder — Intel Mac cross-compile
# Tüm bağımlılıkları kaynak koddan -arch x86_64 ile derler.
# Intel Homebrew veya sudo gerektirmez.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$SCRIPT_DIR/imagemagick/x86_64"
SRC="$SCRIPT_DIR/imagemagick/src/x86_deps"
SDK=$(xcrun --sdk macosx --show-sdk-path)
MIN="10.15"
ARCH="x86_64"
JOBS=$(sysctl -n hw.logicalcpu)

CFLAGS_BASE="-arch $ARCH -mmacosx-version-min=$MIN -isysroot $SDK -O2"
CXXFLAGS_BASE="$CFLAGS_BASE"
LDFLAGS_BASE="-arch $ARCH -mmacosx-version-min=$MIN -isysroot $SDK"

mkdir -p "$PREFIX/lib" "$PREFIX/include" "$PREFIX/lib/pkgconfig" "$SRC"

log() { echo ""; echo "══ $1 ══"; }
ok()  { echo "  ✓ $1"; }

# ── 1. zlib (macOS system — sadece header/stub) ──────────────────────────────
log "zlib (system)"
cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
prefix=/usr
exec_prefix=/usr
libdir=/usr/lib
includedir=/usr/include
Name: zlib
Description: zlib
Version: 1.2.12
Libs: -lz
Cflags:
EOF
ok "zlib stub oluşturuldu"

# ── 2. liblzma (xz) ──────────────────────────────────────────────────────────
XZ_VER="5.8.2"
XZ_TAR="xz-$XZ_VER.tar.gz"
log "liblzma $XZ_VER"
cd "$SRC"
if [ ! -f "$XZ_TAR" ]; then
    curl -fSL "https://github.com/tukaani-project/xz/releases/download/v$XZ_VER/$XZ_TAR" -o "$XZ_TAR"
fi
rm -rf "xz-$XZ_VER"
tar -xf "$XZ_TAR"
cd "xz-$XZ_VER"
CFLAGS="$CFLAGS_BASE" LDFLAGS="$LDFLAGS_BASE" \
./configure --prefix="$PREFIX" --enable-static --disable-shared \
    --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo \
    --disable-scripts --disable-doc --disable-nls --host="$ARCH-apple-darwin" \
    >/dev/null
make -j"$JOBS" install >/dev/null
ok "liblzma built"

# ── 3. zstd ──────────────────────────────────────────────────────────────────
ZSTD_VER="1.5.7"
ZSTD_TAR="zstd-$ZSTD_VER.tar.gz"
log "libzstd $ZSTD_VER"
cd "$SRC"
if [ ! -f "$ZSTD_TAR" ]; then
    curl -fSL "https://github.com/facebook/zstd/releases/download/v$ZSTD_VER/$ZSTD_TAR" -o "$ZSTD_TAR"
fi
rm -rf "zstd-$ZSTD_VER"
tar -xf "$ZSTD_TAR"
cd "zstd-$ZSTD_VER/build/cmake"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_BUILD_PROGRAMS=OFF \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "libzstd built"

# ── 4. jpeg-turbo ────────────────────────────────────────────────────────────
JPEG_VER="3.1.3"
JPEG_TAR="libjpeg-turbo-$JPEG_VER.tar.gz"
log "libjpeg-turbo $JPEG_VER"
cd "$SRC"
if [ ! -f "$JPEG_TAR" ]; then
    curl -fSL "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VER/$JPEG_TAR" -o "$JPEG_TAR"
fi
rm -rf "libjpeg-turbo-$JPEG_VER"
tar -xf "$JPEG_TAR"
cd "libjpeg-turbo-$JPEG_VER"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DENABLE_SHARED=OFF \
    -DENABLE_STATIC=ON \
    -DWITH_TURBOJPEG=OFF \
    -DWITH_JPEG8=ON \
    -DCMAKE_ASM_NASM_COMPILER=/opt/homebrew/bin/nasm \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "libjpeg-turbo built"

# ── 5. libpng ────────────────────────────────────────────────────────────────
PNG_VER="1.6.55"
PNG_TAR="libpng-$PNG_VER.tar.gz"
log "libpng $PNG_VER"
cd "$SRC"
if [ ! -f "$PNG_TAR" ]; then
    curl -fSL "https://download.sourceforge.net/libpng/libpng-$PNG_VER.tar.gz" -o "$PNG_TAR"
fi
rm -rf "libpng-$PNG_VER"
tar -xf "$PNG_TAR"
cd "libpng-$PNG_VER"
CFLAGS="$CFLAGS_BASE" LDFLAGS="$LDFLAGS_BASE" \
./configure --prefix="$PREFIX" --enable-static --disable-shared \
    --host="$ARCH-apple-darwin" \
    >/dev/null
make -j"$JOBS" install >/dev/null
ok "libpng built"

# ── 6. libtiff ───────────────────────────────────────────────────────────────
TIFF_VER="4.7.0"
TIFF_TAR="tiff-$TIFF_VER.tar.gz"
log "libtiff $TIFF_VER"
cd "$SRC"
if [ ! -f "$TIFF_TAR" ]; then
    curl -fSL "https://download.osgeo.org/libtiff/tiff-$TIFF_VER.tar.gz" -o "$TIFF_TAR"
fi
rm -rf "tiff-$TIFF_VER"
tar -xf "$TIFF_TAR"
cd "tiff-$TIFF_VER"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DBUILD_SHARED_LIBS=OFF \
    -Dtiff-tools=OFF \
    -Dtiff-tests=OFF \
    -Dtiff-docs=OFF \
    -Dtiff-contrib=OFF \
    -DZLIB_ROOT="$PREFIX" \
    -DZSTD_ROOT="$PREFIX" \
    -DLIBLZMA_INCLUDE_DIR="$PREFIX/include" \
    -DLIBLZMA_LIBRARY="$PREFIX/lib/liblzma.a" \
    -Dlibdeflate=OFF \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "libtiff built"

# ── 7. giflib ────────────────────────────────────────────────────────────────
GIF_VER="5.2.2"
GIF_TAR="giflib-$GIF_VER.tar.gz"
log "giflib $GIF_VER"
cd "$SRC"
if [ ! -f "$GIF_TAR" ]; then
    curl -fSL "https://downloads.sourceforge.net/giflib/giflib-$GIF_VER.tar.gz" -o "$GIF_TAR"
fi
rm -rf "giflib-$GIF_VER"
tar -xf "$GIF_TAR"
cd "giflib-$GIF_VER"
# giflib Makefile tabanlı araçlara bakıyor, lib objelerini elle derle
clang -arch "$ARCH" -mmacosx-version-min="$MIN" -isysroot "$SDK" -O2 -c dgif_lib.c -o _dgif.o
clang -arch "$ARCH" -mmacosx-version-min="$MIN" -isysroot "$SDK" -O2 -c egif_lib.c -o _egif.o
clang -arch "$ARCH" -mmacosx-version-min="$MIN" -isysroot "$SDK" -O2 -c gif_err.c  -o _gerr.o
clang -arch "$ARCH" -mmacosx-version-min="$MIN" -isysroot "$SDK" -O2 -c gif_font.c -o _gfont.o
clang -arch "$ARCH" -mmacosx-version-min="$MIN" -isysroot "$SDK" -O2 -c gif_hash.c -o _ghash.o
clang -arch "$ARCH" -mmacosx-version-min="$MIN" -isysroot "$SDK" -O2 -c gifalloc.c -o _galloc.o
clang -arch "$ARCH" -mmacosx-version-min="$MIN" -isysroot "$SDK" -O2 -c openbsd-reallocarray.c -o _grealloc.o
ar rcs libgif.a _dgif.o _egif.o _gerr.o _gfont.o _ghash.o _galloc.o _grealloc.o
cp libgif.a "$PREFIX/lib/"
cp gif_lib.h "$PREFIX/include/"
ok "giflib built"

# ── 8. libwebp ───────────────────────────────────────────────────────────────
WEBP_VER="1.6.0"
WEBP_TAR="libwebp-$WEBP_VER.tar.gz"
log "libwebp $WEBP_VER"
cd "$SRC"
if [ ! -f "$WEBP_TAR" ]; then
    curl -fSL "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VER.tar.gz" -o "$WEBP_TAR"
fi
rm -rf "libwebp-$WEBP_VER"
tar -xf "$WEBP_TAR"
cd "libwebp-$WEBP_VER"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_CWEBP=OFF \
    -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF \
    -DWEBP_BUILD_WEBPMUX=ON \
    -DWEBP_BUILD_EXTRAS=OFF \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "libwebp built"

# ── 9. little-cms2 ───────────────────────────────────────────────────────────
LCMS_VER="2.18"
LCMS_TAR="lcms2-$LCMS_VER.tar.gz"
log "little-cms2 $LCMS_VER"
cd "$SRC"
if [ ! -f "$LCMS_TAR" ]; then
    curl -fSL "https://github.com/mm2/Little-CMS/releases/download/lcms$LCMS_VER/$LCMS_TAR" -o "$LCMS_TAR"
fi
rm -rf "lcms2-$LCMS_VER"
tar -xf "$LCMS_TAR"
cd "lcms2-$LCMS_VER"
CFLAGS="$CFLAGS_BASE" LDFLAGS="$LDFLAGS_BASE" \
./configure --prefix="$PREFIX" --enable-static --disable-shared \
    --host="$ARCH-apple-darwin" \
    >/dev/null
make -j"$JOBS" install >/dev/null
ok "lcms2 built"

# ── 10. openjpeg ─────────────────────────────────────────────────────────────
OPJ_VER="2.5.4"
OPJ_TAR="openjpeg-$OPJ_VER.tar.gz"
log "openjpeg $OPJ_VER"
cd "$SRC"
if [ ! -f "$OPJ_TAR" ]; then
    curl -fSL "https://github.com/uclouvain/openjpeg/archive/refs/tags/v$OPJ_VER.tar.gz" -o "$OPJ_TAR"
fi
rm -rf "openjpeg-$OPJ_VER"
tar -xf "$OPJ_TAR"
cd "openjpeg-$OPJ_VER"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_CODEC=OFF \
    -DBUILD_DOC=OFF \
    -DBUILD_TESTING=OFF \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "openjpeg built"

# ── 11. libde265 ─────────────────────────────────────────────────────────────
DE265_VER="1.0.16"
DE265_TAR="libde265-$DE265_VER.tar.gz"
log "libde265 $DE265_VER"
cd "$SRC"
if [ ! -f "$DE265_TAR" ]; then
    curl -fSL "https://github.com/strukturag/libde265/releases/download/v$DE265_VER/$DE265_TAR" -o "$DE265_TAR"
fi
rm -rf "libde265-$DE265_VER"
tar -xf "$DE265_TAR"
cd "libde265-$DE265_VER"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_DECODER=ON \
    -DENABLE_ENCODER=OFF \
    -DBUILD_TESTING=OFF \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "libde265 built"

# ── 12. x265 ─────────────────────────────────────────────────────────────────
X265_VER="4.1"
X265_TAR="x265-$X265_VER.tar.gz"
log "x265 $X265_VER"
cd "$SRC"
if [ ! -f "$X265_TAR" ]; then
    curl -fSL "https://bitbucket.org/multicoreware/x265_git/downloads/x265_$X265_VER.tar.gz" -o "$X265_TAR" || \
    curl -fSL "https://github.com/videolan/x265/archive/refs/tags/$X265_VER.tar.gz" -o "$X265_TAR"
fi
rm -rf "x265_$X265_VER" "x265-$X265_VER"
tar -xf "$X265_TAR" || true
# Dizin adı değişkenlik gösterebilir
X265_DIR=$(ls -d x265_* x265-* 2>/dev/null | head -1)
cd "$X265_DIR/source"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DENABLE_SHARED=OFF \
    -DENABLE_CLI=OFF \
    -DENABLE_ASSEMBLY=OFF \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "x265 built"

# ── 13. aom ──────────────────────────────────────────────────────────────────
AOM_VER="3.13.1"
AOM_TAR="aom-$AOM_VER.tar.gz"
log "aom $AOM_VER"
cd "$SRC"
if [ ! -f "$AOM_TAR" ]; then
    curl -fSL "https://storage.googleapis.com/aom-releases/libaom-$AOM_VER.tar.gz" -o "$AOM_TAR" || \
    curl -fSL "https://aomedia.googlesource.com/aom/+archive/v$AOM_VER.tar.gz" -o "$AOM_TAR"
fi
rm -rf "aom-$AOM_VER"
mkdir -p "aom-$AOM_VER" && cd "aom-$AOM_VER"
tar -xf "../$AOM_TAR" 2>/dev/null || true
# Eğer doğrudan kaynak geldiyse
[ ! -f CMakeLists.txt ] && tar -xf "../$AOM_TAR" --strip-components=1 2>/dev/null || true
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_TOOLS=OFF \
    -DENABLE_DOCS=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DAOM_TARGET_CPU="x86_64" \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "aom built"

# ── 14. libvmaf ──────────────────────────────────────────────────────────────
VMAF_VER="3.0.0"
VMAF_TAR="vmaf-$VMAF_VER.tar.gz"
log "libvmaf $VMAF_VER"
cd "$SRC"
if [ ! -f "$VMAF_TAR" ]; then
    curl -fSL "https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VER.tar.gz" -o "$VMAF_TAR"
fi
rm -rf "vmaf-$VMAF_VER"
tar -xf "$VMAF_TAR"
cd "vmaf-$VMAF_VER/libvmaf"
meson setup build_x86 \
    --prefix="$PREFIX" \
    --buildtype=release \
    --default-library=static \
    -Denable_tests=false \
    -Denable_docs=false \
    -Denable_avx512=false \
    --cross-file <(cat <<CROSSFILE
[host_machine]
system = 'darwin'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'

[properties]
c_args = ['-arch', 'x86_64', '-mmacosx-version-min=10.15', '-isysroot', '$SDK']
cpp_args = ['-arch', 'x86_64', '-mmacosx-version-min=10.15', '-isysroot', '$SDK']
c_link_args = ['-arch', 'x86_64', '-mmacosx-version-min=10.15', '-isysroot', '$SDK']
cpp_link_args = ['-arch', 'x86_64', '-mmacosx-version-min=10.15', '-isysroot', '$SDK']
CROSSFILE
) >/dev/null 2>&1
ninja -C build_x86 -j"$JOBS" >/dev/null 2>&1
ninja -C build_x86 install >/dev/null 2>&1
ok "libvmaf built"

# ── 15. libheif ──────────────────────────────────────────────────────────────
HEIF_VER="1.21.2"
HEIF_TAR="libheif-$HEIF_VER.tar.gz"
log "libheif $HEIF_VER"
cd "$SRC"
if [ ! -f "$HEIF_TAR" ]; then
    curl -fSL "https://github.com/strukturag/libheif/releases/download/v$HEIF_VER/$HEIF_TAR" -o "$HEIF_TAR"
fi
rm -rf "libheif-$HEIF_VER"
tar -xf "$HEIF_TAR"
cd "libheif-$HEIF_VER"
cmake -S . -B build_x86 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_TESTING=OFF \
    -DWITH_DAV1D=OFF \
    -DWITH_RAV1E=OFF \
    -DWITH_SvtEnc=OFF \
    -DWITH_FFMPEG_DECODER=OFF \
    -DWITH_OpenJPEG_DECODER=OFF \
    -DWITH_OPENJPH_DECODER=OFF \
    -DWITH_VVDEC=OFF \
    -DWITH_VVENC=OFF \
    -DWITH_X265=ON \
    -DWITH_X264=OFF \
    -DWITH_AOM_ENCODER=OFF \
    -DWITH_LIBDE265=ON \
    -DX265_ROOT="$PREFIX" \
    -DLIBDE265_ROOT="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    >/dev/null
cmake --build build_x86 -j"$JOBS" >/dev/null
cmake --install build_x86 >/dev/null
ok "libheif built"

# ── pkg-config stub'ları ─────────────────────────────────────────────────────
log "pkg-config stub'ları"

cat > "$PREFIX/lib/pkgconfig/libopenjp2.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libopenjp2
Description: OpenJPEG codec
Version: 2.5.4
Libs: -L\${libdir} -lopenjp2
Cflags: -I\${includedir}/openjpeg-2.5
EOF

cat > "$PREFIX/lib/pkgconfig/libheif.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libheif
Description: HEIF codec
Version: 1.21.2
Libs: -L\${libdir} -lheif -lde265 -lx265 -lc++
Cflags: -I\${includedir}
EOF

cat > "$PREFIX/lib/pkgconfig/libaom.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libaom
Description: AV1 codec
Version: 3.13.1
Libs: -L\${libdir} -laom
Cflags: -I\${includedir}
EOF

cat > "$PREFIX/lib/pkgconfig/libwebp.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libwebp
Description: WebP codec
Version: 1.6.0
Libs: -L\${libdir} -lwebp -lsharpyuv
Cflags: -I\${includedir}
EOF

cat > "$PREFIX/lib/pkgconfig/libwebpmux.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libwebpmux
Description: WebP mux/demux
Version: 1.6.0
Requires: libwebp
Libs: -L\${libdir} -lwebpmux -lwebpdemux -lwebp -lsharpyuv
Cflags: -I\${includedir}
EOF

cat > "$PREFIX/lib/pkgconfig/libjpeg.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libjpeg
Description: JPEG codec
Version: 3.1.3
Libs: -L\${libdir} -ljpeg
Cflags: -I\${includedir}
EOF

cat > "$PREFIX/lib/pkgconfig/libtiff-4.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libtiff
Description: TIFF library
Version: 4.7.0
Libs: -L\${libdir} -ltiff -lz
Cflags: -I\${includedir}
EOF

ok "Stub'lar oluşturuldu"

# ── Özet ─────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "✅ x86_64 bağımlılıkları derlendi!"
echo "   Prefix: $PREFIX"
echo ""
echo "Derlenen lib'ler:"
for lib in libjpeg libpng16 libtiff libgif libwebp libwebpmux libwebpdemux libsharpyuv liblcms2 libopenjp2 libde265 libx265 libheif libaom libvmaf libzstd liblzma; do
    if [ -f "$PREFIX/lib/$lib.a" ]; then
        SIZE=$(du -sh "$PREFIX/lib/$lib.a" 2>/dev/null | cut -f1)
        ARCHS=$(lipo -info "$PREFIX/lib/$lib.a" 2>/dev/null | grep -o "x86_64" | head -1 || echo "?")
        echo "  ✓ $lib.a ($SIZE, $ARCHS)"
    else
        echo "  ✗ $lib.a — BULUNAMADI"
    fi
done
echo "══════════════════════════════════════════════"
echo ""
echo "Sonraki adım: bash third_party/rebuild_im_only.sh"
