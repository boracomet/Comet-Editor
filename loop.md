# Gece Loop Notları — 2026-03-26

## Başlangıç Durumu
- Branch: tabularasa
- Son commit: 28dfb7c (Fix resolution scale logic)
- Kullanıcı uyudu, sabah 8-9'a kadar çalış, yeni özellik ekleme

---

## Apple App Store Audit Sonuçları

### 🔴 KRİTİK (Reddedilme garantisi)
1. **`DYLD_LIBRARY_PATH` sandbox ihlali** — PDFEditView.swift:952
   - macOS sandbox bu env değişkeninin ayarlanmasını yasaklar
   - App Store build bu satırda crash edecek veya direkt reddedilecek
   - FIX: `DYLD_LIBRARY_PATH` satırını kaldır; magick zaten MAGICK_HOME + RPATH ile çalışır

2. **`localhost:3001` hardcoded URL** — cometeditorApp.swift:24
   - Üretim build'inde çalışmaz; analytics tamamen sessiz kalır
   - FIX: Boş string veya gerçek production URL bırak

3. **`changeme_sdk_key_at_least_32_chars_here` placeholder API key** — cometeditorApp.swift:23
   - Gerçek bir anahtar değil; review ekibi fark ederse soru sorabilir
   - FIX: Boş string bırak veya gerçek key ile değiştir

### 🟡 ORTA (Review itirazı riski)
4. **Hardcoded Unsplash API key** — StockImageView.swift:437
   - Client-ID açık kaynak koda gömülü; sızdırılabilir
   - Apple bunu direkt reddetmez ama güvenlik açığı

5. **`#file` compile-time path** — PDFEditView.swift:869-870
   - Dev build'de çalışır, production archive'de kaynak path yok
   - Production build'de magick hiç bulunamaz (sessiz başarısızlık)

6. **`URL(string: ...)!` force unwrap'lar** — HomeView.swift:43, TeamModalView.swift:18/71
   - Static string olduğu için crash riski düşük ama kötü pratik

### 🟢 DÜŞÜK (İyi pratik, review'ı kolaylaştırır)
7. **PrivacyInfo.xcprivacy eksik açıklamalar**
   - `NSPrivacyCollectedDataTypes` boş; analytics sessionId kullanıcı verisi sayılabilir
   - Unsplash API çağrıları için network erişim tanımlanmamış

8. **Bundled binary code signing** — third_party/imagemagick/arm64/bin/magick
   - App notarization için bundled binary imzalı olmalı

---

## Yapılan Düzeltmeler

### [YAPILDI] DYLD_LIBRARY_PATH kaldırıldı
- PDFEditView.swift — DYLD_LIBRARY_PATH satırı silindi, kullanılmayan libPath değişkeni temizlendi
- magick RPATH ile kendi lib dizinini zaten bulur

### [YAPILDI] localhost:3001 → boş string
- cometeditorApp.swift — baseURL boş bırakıldı (analytics silent fail, production'da set edilmeli)

### [YAPILDI] Placeholder API key temizlendi
- cometeditorApp.swift — apiKey boş string (production'da set edilmeli)

### [YAPILDI] #file compile-time path kaldırıldı
- PDFEditView.swift — dev fallback path (URL(fileURLWithPath: #file)) silindi
- FFmpegBridge.swift — aynı pattern kaldırıldı, sadece Bundle.main.url() kaldı
- Production'da kaynak path yok, Bundle.main.url() yeterli

### [YAPILDI] SuggestionView hardcoded Türkçe string'ler lokalize edildi
- "Kategori", "Başlık", "Açıklama" → LocalizedStringKey kullanımına geçildi
- 3 yeni key (suggestion.label.category/title/description) tüm 64 dile eklendi

### [YAPILDI] AdManager hardcoded Türkçe string'ler lokalize edildi
- "Sponsorlu", "Ziyaret Et" → LocalizedStringKey kullanımına geçildi
- 2 yeni key (ad.sponsored, ad.visit) tüm 64 dile eklendi

### [YAPILDI] StockImageView URL force unwrap düzeltildi
- performSearch'teki URL(string:...)! → guard let ile güvenli hale getirildi

### [YAPILDI] HomeView + TeamModalView force unwrap URL'ler
- 3 adet URL(string:...)! → ?? URL(fileURLWithPath: "/") ile güvenli hale getirildi

### [GEREKMİYOR] PrivacyInfo.xcprivacy sysctlbyname
- sysctlbyname Apple'ın Required Reason API listesinde değil, tanımlama gerekmez

---

## Sonraki Kontrol
- [ ] Unsplash API key — Production'da environment variable veya backend proxy kullanılmalı
- [ ] magick binary code signing — notarization için (ayrı süreç)
