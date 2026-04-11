# memguide.md — yalnızca bu repoda (comet-clear) AI bağlamı

## Amaç

Bu dosya oturum değişince asistanın `mempalace.yaml` ve MemPalace eşlemesini **tekrar aynı şekilde** okuyabilmesi için hazırlanmış kısa bir **oturum yenileme notu**dur.

---

## MemPalace yazılımı vs bu repodaki yaml

| Ne | Rol |
|----|-----|
| **MemPalace** (pip, `mempalace init` / `mine`, MCP: `python -m mempalace.mcp_server`) | Yerel bellek; veri `~/.mempalace/`. Resmi repo: [milla-jovovich/mempalace](https://github.com/milla-jovovich/mempalace). |
| **`mempalace.yaml`** (bu repoda, kök) | MemPalace'ın zorunlu dosyası değil. **`wing`** = bu proje için MCP'de kullanılan kanat adı; **`rooms`** = kodun mantıksal bölgeleri. |

Palace içeriği `mine` ile dolar; yaml **bu repodaki isim ve oda sözleşmesi**.

---

## `mempalace.yaml` — bu repoya özel

- **`wing: comet-clear`** — Kanat adı; palace/MCP tarafıyla aynı string olmalı.
- **`rooms`** — Tablo yalnızca comet-clear dizinine göre:

| `name` | Bu repoda |
|--------|-----------|
| `general` | Kök dosyalar — `Info.plist`, `LICENSE`, `loop.md`, `third_party/` |
| `app` | Ana giriş — `cometeditorApp.swift`, `ContentView.swift`, `GlobalAppState.swift`, `MenuItem.swift` |
| `pdf` | PDF araçları — `PDFEditView.swift`, `PDFNativeCompressor.swift`, `PDFQualityPickerSheet.swift` |
| `media` | Görsel/video — `ConvertImageView.swift`, `BgRemoveView.swift`, `BgRemoveEngine.swift`, `StockImageView.swift`, `VideoConvertView.swift`, `VideoProcessor.swift` |
| `tools` | Diğer araçlar — `QRCodeView.swift`, `FontDownloadView.swift`, `OCRView.swift` |
| `bridge` | Native köprüler — `CometCodecBridge.swift`, `FFmpegBridge.swift`, `cometeditor-Bridging-Header.h` |
| `ui` | UI bileşenleri — `SidebarView.swift`, `HomeView.swift`, `ViewHelpers.swift`, `SuggestionView.swift`, vb. |
| `analytics` | Analitik — `CometAnalytics.swift` |
| `localization` | 40+ dil için `*.lproj/Localizable.strings` |

Yapı değişince önce `mempalace.yaml`, sonra bu tabloyu güncelle.

---

## Bu repoda soru türüne göre (AI için tek blok)

`wing: comet-clear` ve yukarıdaki odalar geçerli.
- PDF işlemleri: `pdf` odası
- Görsel/video dönüştürme, bg remove: `media` odası
- QR, font, OCR: `tools` odası
- FFmpeg, codec köprüleri: `bridge` odası
- Genel UI akışı, sidebar, home: `ui` odası
- Çeviri/lokalizasyon: `localization` odası
- Uygulama durumu, routing: `app` odası

---

*Başka proje için ayrı bir `mempalace.yaml` / memguide yazılır; bu dosya comet-clear'a özeldir.*
