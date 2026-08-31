# Comet Editor

**English** | [Türkçe](README.tr.md)

A native macOS media toolkit. Image conversion, AI upscaling, video conversion, PDF editing, background removal, OCR, QR codes, stock photos, and font download — in one app.

Processing runs on device. Images and videos are not uploaded to a server. The app is sandboxed (`com.cometeditor.app`).

**Version:** 2.0 · **Minimum:** macOS 13.0 · **Website:** [cometeditor.com](https://cometeditor.com)

<p align="center">
  <img src="comet-logo.svg" alt="Comet Editor" width="120">
</p>

<p align="center">
  <a href="https://apps.apple.com/tr/app/comet-editor/id6760206823?mt=12">
    <img src="readmess/mac-app-store-en.svg" alt="Download on the Mac App Store" height="40">
  </a>
</p>

<p align="center">
  <a href="https://apps.apple.com/tr/app/comet-editor/id6760206823?mt=12">Mac App Store — Comet Editor</a>
</p>

<p align="center">
  <img src="readmess/1.png" alt="Convert Image">
</p>

## Features

| Tool | What it does |
| --- | --- |
| **Convert Image** | PNG, JPEG, HEIC, WebP, AVIF, TIFF, GIF, BMP, ICO, SVG, PSD, RAW, and more. Quality, scale, dimensions, metadata protection, batch processing, and watermarks (text or logo). |
| **Image Upscale** | On-device AI upscaler (`cometscaly`, Upscayl Standard 4×). 2×–16×; 8× and 16× run multiple passes. Before/after preview slider. |
| **Video Convert** | MP4, MOV, MKV, AVI, WebM, GIF, M4V, MPEG, 3GP, FLV, WMV. FPS, resolution, strip audio. Local FFmpeg encode. |
| **Stock Image** | Search and download from [Unsplash](https://unsplash.com). |
| **PDF Edit** | Delete, reorder, and compress pages; insert PDF or images. |
| **QR Code** | Website, Wi-Fi, vCard, email, and phone. Export PNG, SVG, JPG, WebP, AVIF. |
| **Background Remover** | On-device masking with Apple’s Neural Engine. macOS 14 Sonoma or later recommended. |
| **Image to Text (OCR)** | Extract text with Vision; copy or save as a file. |
| **Font Download** | Browse the Google Fonts catalog and install selected styles on your Mac. |

### Image Upscale

<p align="center">
  <img src="readmess/2.png" alt="Image upscale — before / after">
</p>

### Stock Image

<p align="center">
  <img src="readmess/3.png" alt="Unsplash stock photo search">
</p>

### PDF Edit

<p align="center">
  <img src="readmess/4.png" alt="PDF edit and compress">
</p>

### QR Code

<p align="center">
  <img src="readmess/5.png" alt="QR code generator">
</p>

### Background Remover

<p align="center">
  <img src="readmess/6.png" alt="Background remover">
</p>

### Font Download

<p align="center">
  <img src="readmess/7.png" alt="Google Fonts download">
</p>

The home screen includes ready-made presets for common jobs (shrink an image, PNG → WebP, open a PDF).

The in-app language picker covers dozens of locales (English, Turkish, German, Japanese, Arabic, and more).

## Contributing

Pull requests are welcome.

If your contribution is accepted, it will ship in the [Mac App Store](https://apps.apple.com/tr/app/comet-editor/id6760206823?mt=12) release of Comet Editor, and **your name will be added to the in-app credits**.

Open an issue or a PR describing the change. Keep the scope focused; match the existing SwiftUI style and localization flow (`i18n/master.json`).

## Requirements

- macOS 13.0 or later (14.0 recommended for background removal)
- Xcode 16 or later (Swift 5, SwiftUI)
- Apple Development signing (sandbox and hardened runtime)

ImageMagick, FFmpeg, and upscale models ship under `third_party/`. No separate Homebrew install is required.

## Development

```bash
git clone https://github.com/boracomet/Comet-Editor.git
cd Comet-Editor
open cometeditor.xcodeproj
```

Select the **Comet Editor** scheme in Xcode and run.

### Google Fonts API key

Font Download uses the Google Fonts Webfonts API. The key is not in source control.

1. Copy `cometeditor/Secrets.example.plist` to `cometeditor/Secrets.plist`.
2. Set `GoogleFontsAPIKey` to your own key.
3. `Secrets.plist` is gitignored.

Without that file the app still builds; the font catalog will not load.

Unsplash uses a public Client-ID; no extra setup is required.

## Architecture

| Layer | Stack |
| --- | --- |
| UI | SwiftUI, macOS NavigationSplitView |
| Image codecs | ImageMagick 7 (`CometCodecBridge`) |
| Video | FFmpeg (`FFmpegBridge`, `VideoProcessor`) |
| Upscale | `cometscaly` + NCNN models (`UpscaleEngine`) |
| Background / OCR | Vision / Neural Engine |
| Localization | `i18n/master.json` → `*.lproj/Localizable.strings` |

Localization keys live under `i18n/`. After adding strings, use the sync scripts — do not hand-edit `Localizable.strings` files.

## License

[MIT](LICENSE) © 2026 Bora Ata Türkoğlu

Development: [Bora Ata Türkoğlu](https://boraturkoglu.com) · Visual contribution: [Beyza Nur Keçeli](https://www.linkedin.com/in/beyzanurkeceli/)
