#!/bin/bash
# ImageMagick'i --without-openexr --without-avif --without-lzma --without-zstd ile yeniden derler.
# Önceki build klasörlerini temizler, pkg-config ve env tamamen izole edilir.
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

# Daha önce indirilmemişse indir
if [ ! -f "$SRC/$IM_TAR" ]; then
    echo "→ İndiriliyor: $IM_TAR"
    curl -L "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/$IM_VER.tar.gz" -o "$SRC/$IM_TAR"
fi

build_imagemagick() {
    local ARCH=$1; local PREFIX=$2; local MIN=$3
    local FLAGS="-arch $ARCH -mmacosx-version-min=$MIN -isysroot $XCODE_SDK"

    echo ""; echo "═══ ImageMagick ($ARCH) — temiz derleme ═══"

    # Eski build klasörünü sil (her zaman)
    rm -rf "$SRC/build_im_$ARCH"
    mkdir -p "$SRC/build_im_$ARCH"
    cd "$SRC/build_im_$ARCH"
    tar -xf "../$IM_TAR"
    cd "ImageMagick-$IM_VER"

    # Homebrew path'lerini tamamen env'den çıkar
    # CPPFLAGS ve LDFLAGS sadece kendi prefix'imizi göster
    # libpng/libtiff zlib'e bağımlı — macOS sistem zlib için pkgconfig stub oluştur
    cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF2
prefix=/usr
exec_prefix=/usr
libdir=/usr/lib
includedir=/usr/include

Name: zlib
Description: zlib compression library
Version: 1.2.12
Libs: -lz
Cflags:
EOF2

    # libtiff libdeflate'e bağımlı — libtiff'i TIFF_LIBS ile direkt ver, pkg-config'i geç
    # libtiff dependency chain: libdeflate, zlib, jpeg — hepsini TIFF_LIBS'de belirt
    export TIFF_CFLAGS="-I$PREFIX/include"
    export TIFF_LIBS="-L$PREFIX/lib -ltiff -lz"

    env -i \
        HOME="$HOME" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin" \
        DEVELOPER_DIR="$(xcode-select -p)" \
        PKG_CONFIG="/opt/homebrew/bin/pkg-config" \
        PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
        PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
        CC="clang" \
        CXX="clang++" \
        CFLAGS="$FLAGS -I$PREFIX/include" \
        CPPFLAGS="-I$PREFIX/include" \
        LDFLAGS="$FLAGS -L$PREFIX/lib -lsharpyuv -lz -lm" \
        PNG_CFLAGS="-I$PREFIX/include/libpng16" \
        PNG_LIBS="-L$PREFIX/lib -lpng16 $ZLIB_FLAGS" \
        TIFF_CFLAGS="-I$PREFIX/include" \
        TIFF_LIBS="-L$PREFIX/lib -ltiff $ZLIB_FLAGS" \
        WEBP_CFLAGS="-I$PREFIX/include" \
        WEBP_LIBS="-L$PREFIX/lib -lwebp -lwebpmux -lwebpdemux -lsharpyuv" \
        GIF_CFLAGS="-I$PREFIX/include" \
        GIF_LIBS="-L$PREFIX/lib -lgif" \
        LCMS2_CFLAGS="-I$PREFIX/include" \
        LCMS2_LIBS="-L$PREFIX/lib -llcms2" \
        JPEG_CFLAGS="-I$PREFIX/include" \
        JPEG_LIBS="-L$PREFIX/lib -ljpeg" \
    ./configure \
        --prefix="$PREFIX" \
        --enable-static --disable-shared \
        --disable-openmp --without-x --without-perl \
        --without-magick-plus-plus --without-bzlib \
        --without-dps --without-fpx --without-djvu \
        --without-fftw --without-flif --without-fontconfig \
        --without-freetype --without-jxl --without-rsvg \
        --without-wmf --without-xml --without-lqr \
        --without-pango \
        --without-heic --without-avif \
        --without-openexr --without-openjp2 \
        --without-lzma --without-zstd \
        --with-jpeg=yes \
        --with-png=yes \
        --with-tiff=yes \
        --with-gif=yes \
        --with-webp=yes \
        --with-lcms=yes

    env -i \
        HOME="$HOME" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin" \
        DEVELOPER_DIR="$(xcode-select -p)" \
    make -j"$JOBS" install

    # Verify
    local version=$("$PREFIX/bin/magick" -version 2>/dev/null | head -1)
    local delegates=$("$PREFIX/bin/magick" -version 2>/dev/null | grep "Delegates")
    echo "✓ $version"
    echo "  $delegates"
    if echo "$delegates" | grep -q "openexr"; then
        echo "⚠️  UYARI: openexr hâlâ var!"
    else
        echo "✓ openexr yok"
    fi
}

build_imagemagick arm64  "$ARM64_PREFIX" "$MACOS_MIN_ARM"
build_imagemagick x86_64 "$X86_PREFIX"  "$MACOS_MIN_X86"

# Universal fat binary
echo ""; echo "═══ Universal fat binary ═══"

lipo_merge() {
    local name=$1
    local arm="$ARM64_PREFIX/lib/$name"
    local x86="$X86_PREFIX/lib/$name"
    local out="$UNIVERSAL/lib/$name"
    if [ -f "$arm" ] && [ -f "$x86" ]; then
        lipo -create "$arm" "$x86" -output "$out"
        echo "✓ Universal: $name"
    elif [ -f "$arm" ]; then
        cp "$arm" "$out"
        echo "⚠ Sadece arm64: $name"
    else
        echo "✗ Bulunamadı: $name"
    fi
}

lipo_merge libMagickWand-7.Q16HDRI.a
lipo_merge libMagickCore-7.Q16HDRI.a

# Headers kopyala
rm -rf "$UNIVERSAL/include/ImageMagick-7"
cp -R "$ARM64_PREFIX/include/ImageMagick-7" "$UNIVERSAL/include/"

echo ""; echo "✅ ImageMagick yeniden derlendi!"
echo "   Universal: $UNIVERSAL/lib/"
