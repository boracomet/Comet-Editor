#!/bin/bash
# ImageMagick'i JP2 (OpenJP2), HEIC (libheif) ve WebP desteğiyle derler.
# Apple Silicon (arm64) ve Intel (x86_64) için gerçek universal binary üretir.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/imagemagick"
SRC="$ROOT/src"
ARM64_PREFIX="$ROOT/arm64"
X86_PREFIX="$ROOT/x86_64"
UNIVERSAL="$ROOT/universal"

MACOS_MIN_ARM="11.0"
MACOS_MIN_X86="10.15"
XCODE_SDK=$(xcrun --sdk macosx --show-sdk-path)
JOBS=$(sysctl -n hw.logicalcpu)

IM_VER="7.1.1-47"
IM_TAR="ImageMagick-$IM_VER.tar.gz"

# Homebrew prefix — Apple Silicon: /opt/homebrew, Intel: /usr/local
ARM64_BREW="/opt/homebrew"
X86_BREW="/usr/local"

mkdir -p "$SRC"

# Daha önce indirilmemişse indir
if [ ! -f "$SRC/$IM_TAR" ]; then
    echo "→ İndiriliyor: $IM_TAR"
    curl -L "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/$IM_VER.tar.gz" -o "$SRC/$IM_TAR"
fi

# Verilen Homebrew prefix'inden static lib ve header'ları kopyala
copy_static_deps() {
    local PREFIX=$1
    local BREW=$2

    mkdir -p "$PREFIX/lib" "$PREFIX/include"

    # Static lib'ler
    cp "$BREW/opt/jpeg-turbo/lib/libjpeg.a"      "$PREFIX/lib/" 2>/dev/null || \
        cp "$BREW/opt/jpeg/lib/libjpeg.a"         "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/libpng/lib/libpng16.a"          "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/libtiff/lib/libtiff.a"          "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/giflib/lib/libgif.a"            "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/webp/lib/libwebp.a"             "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/webp/lib/libwebpdemux.a"        "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/webp/lib/libwebpmux.a"          "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/webp/lib/libsharpyuv.a"         "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/little-cms2/lib/liblcms2.a"     "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/openjpeg/lib/libopenjp2.a"      "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/libheif/lib/libheif.a"          "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/libde265/lib/libde265.a"        "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/x265/lib/libx265.a"             "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/aom/lib/libaom.a"               "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/libvmaf/lib/libvmaf.a"          "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/zstd/lib/libzstd.a"             "$PREFIX/lib/" 2>/dev/null || true
    cp "$BREW/opt/xz/lib/liblzma.a"               "$PREFIX/lib/" 2>/dev/null || true

    # Headers
    cp -R "$BREW/opt/webp/include/webp"                  "$PREFIX/include/"  2>/dev/null || true
    cp -R "$BREW/opt/jpeg-turbo/include/."               "$PREFIX/include/"  2>/dev/null || \
        cp -R "$BREW/opt/jpeg/include/."                 "$PREFIX/include/"  2>/dev/null || true
    cp -R "$BREW/opt/libpng/include/libpng16"            "$PREFIX/include/"  2>/dev/null || true
    cp    "$BREW/opt/libpng/include/png.h"               "$PREFIX/include/"  2>/dev/null || true
    cp    "$BREW/opt/libpng/include/pngconf.h"           "$PREFIX/include/"  2>/dev/null || true
    cp    "$BREW/opt/libpng/include/pnglibconf.h"        "$PREFIX/include/"  2>/dev/null || true
    cp -R "$BREW/opt/libtiff/include/."                  "$PREFIX/include/"  2>/dev/null || true
    cp    "$BREW/opt/giflib/include/gif_lib.h"           "$PREFIX/include/"  2>/dev/null || true
    cp    "$BREW/opt/little-cms2/include/lcms2.h"        "$PREFIX/include/"  2>/dev/null || true
    cp -R "$BREW/opt/openjpeg/include/openjpeg-2.5"      "$PREFIX/include/"  2>/dev/null || true
    cp -R "$BREW/opt/libheif/include/libheif"            "$PREFIX/include/"  2>/dev/null || true
    cp -R "$BREW/opt/aom/include/aom"                    "$PREFIX/include/"  2>/dev/null || true

    # pkg-config stub'ları
    mkdir -p "$PREFIX/lib/pkgconfig"

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

    cat > "$PREFIX/lib/pkgconfig/libopenjp2.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libopenjp2
Description: OpenJPEG codec
Version: 2.5.0
Libs: -L$PREFIX/lib -lopenjp2
Cflags: -I$PREFIX/include/openjpeg-2.5
EOF

    cat > "$PREFIX/lib/pkgconfig/libheif.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libheif
Description: HEIF codec
Version: 1.21.2
Libs: -L$PREFIX/lib -lheif -lde265 -lx265 -lc++
Cflags: -I$PREFIX/include
EOF

    cat > "$PREFIX/lib/pkgconfig/libaom.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libaom
Description: AV1 codec (AVIF)
Version: 3.13.1
Libs: -L$PREFIX/lib -laom
Cflags: -I$PREFIX/include
EOF

    local WEBP_VER
    WEBP_VER=$("$BREW/bin/pkg-config" --modversion libwebp 2>/dev/null || echo "1.5.0")
    cat > "$PREFIX/lib/pkgconfig/libwebp.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libwebp
Description: WebP codec
Version: $WEBP_VER
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
Version: $WEBP_VER
Requires: libwebp
Libs: -L\${libdir} -lwebpmux -lwebpdemux -lwebp -lsharpyuv
Cflags: -I\${includedir}
EOF

    local JPEG_VER
    JPEG_VER=$("$BREW/bin/pkg-config" --modversion libjpeg 2>/dev/null || echo "9.5.0")
    cat > "$PREFIX/lib/pkgconfig/libjpeg.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libjpeg
Description: JPEG codec
Version: $JPEG_VER
Libs: -L\${libdir} -ljpeg
Cflags: -I\${includedir}
EOF

    local TIFF_VER
    TIFF_VER=$("$BREW/bin/pkg-config" --modversion libtiff-4 2>/dev/null || echo "4.7.0")
    cat > "$PREFIX/lib/pkgconfig/libtiff-4.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libtiff
Description: TIFF library
Version: $TIFF_VER
Libs: -L\${libdir} -ltiff -lz
Cflags: -I\${includedir}
EOF

    local PNG_VER
    PNG_VER=$("$BREW/bin/pkg-config" --modversion libpng 2>/dev/null || echo "1.6.44")
    cat > "$PREFIX/lib/pkgconfig/libpng.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: libpng
Description: PNG image codec
Version: $PNG_VER
Libs: -L\${libdir} -lpng16 -lz
Cflags: -I\${includedir}
EOF
    cp "$PREFIX/lib/pkgconfig/libpng.pc" "$PREFIX/lib/pkgconfig/libpng16.pc" 2>/dev/null || true

    cat > "$PREFIX/lib/pkgconfig/giflib.pc" <<EOF
prefix=$PREFIX
exec_prefix=$PREFIX
libdir=$PREFIX/lib
includedir=$PREFIX/include
Name: giflib
Description: GIF image codec
Version: 5.2.2
Libs: -L\${libdir} -lgif
Cflags: -I\${includedir}
EOF
}

build_imagemagick() {
    local ARCH=$1
    local PREFIX=$2
    local MIN=$3
    local BREW=$4
    # SKIP_DEPS=1 ise copy_static_deps atlanır (önceden derlenmiş lib'ler varsa)
    local SKIP_DEPS=${5:-0}
    local FLAGS="-arch $ARCH -mmacosx-version-min=$MIN -isysroot $XCODE_SDK"

    echo ""; echo "═══ ImageMagick ($ARCH) — derleme ═══"

    if [ "$SKIP_DEPS" = "0" ]; then
        copy_static_deps "$PREFIX" "$BREW"
    else
        echo "  → Bağımlılıklar önceden derlenmiş, kopyalama atlandı."
        # Sadece pkg-config stub'larını oluştur
        mkdir -p "$PREFIX/lib/pkgconfig"
        cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<ZEOF
prefix=/usr
exec_prefix=/usr
libdir=/usr/lib
includedir=/usr/include
Name: zlib
Description: zlib
Version: 1.2.12
Libs: -lz
Cflags:
ZEOF
    fi

    rm -rf "$SRC/build_im_$ARCH"
    mkdir -p "$SRC/build_im_$ARCH"
    cd "$SRC/build_im_$ARCH"
    tar -xf "../$IM_TAR"
    cd "ImageMagick-$IM_VER"

    # x86_64 cross-compile için cache dosyası (cpuid ve jpeg test bypass)
    if [ "$ARCH" = "x86_64" ]; then
        cat > config.cache <<CACHEOF
ac_cv_lib_jpeg_jpeg_read_header=yes
ac_cv_header_jpeglib_h=yes
ax_cv_gcc_x86_cpuid_0=756e6547:6c65746e:49656e69:756e6547
ax_cv_gcc_x86_cpuid_1=000906ea:00100800:7ffafbbf:bfebfbff
CACHEOF
        HOST_FLAG="--host=x86_64-apple-darwin --cache-file=config.cache"
    else
        HOST_FLAG=""
    fi

    env -i \
        HOME="$HOME" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin" \
        DEVELOPER_DIR="$(xcode-select -p)" \
        PKG_CONFIG="$BREW/bin/pkg-config" \
        PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
        PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
        CC="clang" \
        CXX="clang++" \
        CFLAGS="$FLAGS -I$PREFIX/include" \
        CPPFLAGS="-I$PREFIX/include" \
        LDFLAGS="$FLAGS -L$PREFIX/lib -lsharpyuv -laom -lvmaf -lzstd -llzma -lz -lm -lc++" \
        PNG_CFLAGS="-I$PREFIX/include/libpng16" \
        PNG_LIBS="-L$PREFIX/lib -lpng16" \
        TIFF_CFLAGS="-I$PREFIX/include" \
        TIFF_LIBS="-L$PREFIX/lib -ltiff -lz" \
        WEBP_CFLAGS="-I$PREFIX/include" \
        WEBP_LIBS="-L$PREFIX/lib -lwebp -lwebpmux -lwebpdemux -lsharpyuv" \
        GIF_CFLAGS="-I$PREFIX/include" \
        GIF_LIBS="-L$PREFIX/lib -lgif" \
        LCMS2_CFLAGS="-I$PREFIX/include" \
        LCMS2_LIBS="-L$PREFIX/lib -llcms2" \
        JPEG_CFLAGS="-I$PREFIX/include" \
        JPEG_LIBS="-L$PREFIX/lib -ljpeg" \
        OPENJP2_CFLAGS="-I$PREFIX/include/openjpeg-2.5" \
        OPENJP2_LIBS="-L$PREFIX/lib -lopenjp2" \
        HEIF_CFLAGS="-I$PREFIX/include" \
        HEIF_LIBS="-L$PREFIX/lib -lheif -lde265 -lx265 -lc++" \
        AOM_CFLAGS="-I$PREFIX/include" \
        AOM_LIBS="-L$PREFIX/lib -laom" \
    ./configure \
        --prefix="$PREFIX" \
        $HOST_FLAG \
        --enable-static --disable-shared \
        --disable-openmp --without-x --without-perl \
        --without-magick-plus-plus --without-bzlib \
        --without-dps --without-fpx --without-djvu \
        --without-fftw --without-flif --without-fontconfig \
        --without-freetype --without-jxl --without-rsvg \
        --without-wmf --without-xml --without-lqr \
        --without-pango \
        --without-openexr \
        --without-lzma --without-zstd \
        --with-jpeg=yes \
        --with-png=yes \
        --with-tiff=yes \
        --with-gif=yes \
        --with-webp=yes \
        --with-lcms=yes \
        --with-openjp2=yes \
        --with-heic=yes

    env -i \
        HOME="$HOME" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin" \
        DEVELOPER_DIR="$(xcode-select -p)" \
    make -j"$JOBS" install

    local version
    version=$("$PREFIX/bin/magick" -version 2>/dev/null | head -1)
    local delegates
    delegates=$("$PREFIX/bin/magick" -version 2>/dev/null | grep "Delegates")
    echo "✓ $version"
    echo "  $delegates"
}

# arm64 build (her zaman)
build_imagemagick arm64 "$ARM64_PREFIX" "$MACOS_MIN_ARM" "$ARM64_BREW"

# x86_64 build
# Önce Intel Homebrew'a bak, yoksa kendi derlediğimiz x86_64 prefix'ini kullan
if [ -f "$X86_BREW/bin/brew" ]; then
    echo "→ Intel Homebrew bulundu, x86_64 build yapılıyor..."
    build_imagemagick x86_64 "$X86_PREFIX" "$MACOS_MIN_X86" "$X86_BREW"
elif [ -f "$X86_PREFIX/lib/libjpeg.a" ]; then
    echo "→ x86_64 kaynak lib'leri bulundu (build_x86_deps.sh), ImageMagick x86_64 derleniyor..."
    # SKIP_DEPS=1: lib'ler zaten build_x86_deps.sh tarafından x86_64 olarak derlenmiş
    build_imagemagick x86_64 "$X86_PREFIX" "$MACOS_MIN_X86" "$ARM64_BREW" 1
else
    echo "⚠ x86_64 lib'leri bulunamadı — x86_64 build atlandı."
    echo "  Intel Mac desteği için: bash third_party/build_x86_deps.sh"
fi

# Universal binary oluştur
echo ""; echo "═══ Universal binary oluşturuluyor ═══"
mkdir -p "$UNIVERSAL/lib"

lipo_merge() {
    local name=$1
    local arm="$ARM64_PREFIX/lib/$name"
    local x86="$X86_PREFIX/lib/$name"
    local out="$UNIVERSAL/lib/$name"
    if [ -f "$arm" ] && [ -f "$x86" ]; then
        lipo -create "$arm" "$x86" -output "$out"
        echo "✓ Universal (arm64+x86_64): $name"
    elif [ -f "$arm" ]; then
        cp "$arm" "$out"
        echo "⚠ Sadece arm64: $name"
    else
        echo "✗ Bulunamadı: $name"
    fi
}

lipo_merge libMagickWand-7.Q16HDRI.a
lipo_merge libMagickCore-7.Q16HDRI.a

# Tüm bağımlı static lib'leri de universal'a birleştir
for lib in \
    libjpeg.a libpng16.a libtiff.a libgif.a \
    libwebp.a libwebpmux.a libwebpdemux.a libsharpyuv.a \
    liblcms2.a libopenjp2.a \
    libheif.a libde265.a libx265.a \
    libaom.a libvmaf.a \
    libzstd.a liblzma.a; do
    lipo_merge "$lib"
done

# Headers — arm64'ten al (mimari bağımsız)
rm -rf "$UNIVERSAL/include/ImageMagick-7"
cp -R "$ARM64_PREFIX/include/ImageMagick-7" "$UNIVERSAL/include/"

echo ""; echo "✅ ImageMagick derlendi!"
lipo -info "$UNIVERSAL/lib/libMagickCore-7.Q16HDRI.a" 2>/dev/null | head -1
echo "   Universal: $UNIVERSAL/lib/"
