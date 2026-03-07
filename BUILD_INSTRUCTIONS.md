# Comet Editor - Build Instructions

## Xcode Build Hatalarını Çözme

### Sorun: Header dosyaları bulunamıyor

Eğer şu hataları alıyorsanız:
```
'avif/avif.h' file not found
'libavcodec/avcodec.h' file not found
'webp/decode.h' file not found
```

### Çözüm 1: Kütüphaneleri Build Edin (Yerel Geliştirme)

```bash
# Image codec'leri build et (libwebp, libavif)
./build_codecs.sh

# Video codec'leri build et (FFmpeg)
./build_video_codecs.sh
```

Bu script'ler şu dizinleri oluşturacak:
- `third_party/install/` - libwebp ve libavif
- `third_party/ffmpeg_install/` - FFmpeg kütüphaneleri

### Çözüm 2: Xcode Cloud için CI Script

Xcode Cloud otomatik olarak `ci_scripts/ci_post_clone.sh` script'ini çalıştırır ve kütüphaneleri build eder.

### Çözüm 3: Önceden Build Edilmiş Kütüphaneleri Commit Edin

Eğer build süresini kısaltmak istiyorsanız:

```bash
# Kütüphaneleri build edin
./build_codecs.sh
./build_video_codecs.sh

# Git'e ekleyin
git add third_party/install/
git add third_party/ffmpeg_install/
git commit -m "Add pre-built third-party libraries"
```

## Xcode Proje Ayarları

Proje şu header search path'leri kullanıyor:
- `$(SRCROOT)/CometImageCodec/Core`
- `$(SRCROOT)/CometVideoCodec/Core`
- `$(SRCROOT)/third_party/install/include`
- `$(SRCROOT)/third_party/ffmpeg_install/universal/include`

Library search path'leri:
- `$(SRCROOT)/third_party/install/lib`
- `$(SRCROOT)/third_party/ffmpeg_install/universal/lib`

## Gereksinimler

- macOS 13.0+
- Xcode 14.0+
- CMake (codec build için)
- Yasm veya NASM (opsiyonel, x86_64 optimizasyonları için)

## Sorun Giderme

### Build süresi çok uzun
Önceden build edilmiş kütüphaneleri commit edin (Çözüm 3).

### Xcode Cloud'da build başarısız
`ci_scripts/ci_post_clone.sh` script'inin executable olduğundan emin olun:
```bash
chmod +x ci_scripts/ci_post_clone.sh
git add ci_scripts/ci_post_clone.sh
git commit -m "Make CI script executable"
```

### Header dosyaları hala bulunamıyor
Kütüphanelerin doğru build edildiğini kontrol edin:
```bash
ls -la third_party/install/include/
ls -la third_party/ffmpeg_install/universal/include/
```
