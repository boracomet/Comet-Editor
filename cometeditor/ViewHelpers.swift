import SwiftUI
import AppKit
import Combine

// MARK: - Language Manager
// Changes app language at runtime without resetting the view hierarchy.
// Updating `currentLanguage` triggers `.environment(\.locale, ...)` which causes
// SwiftUI to re-resolve all LocalizedStringKey bindings in place.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    @Published var currentLanguage: String

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           Self.bundleExists(saved) {
            currentLanguage = saved
        } else {
            currentLanguage = Self.resolveSystemLanguage()
        }
    }

    func setLanguage(_ lang: String) {
        UserDefaults.standard.set(lang, forKey: "appLanguage")
        withAnimation(.easeInOut(duration: 0.15)) {
            currentLanguage = lang
        }
    }

    func string(_ key: String) -> String {
        for code in Self.bundleCandidates(for: currentLanguage) {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                if value != key {
                    return value
                }
            }
        }
        return NSLocalizedString(key, comment: "")
    }

    /// `convert.scale.percent` — e.g. "Mevcut çözünürlüğün %25’i" / "Reduce to 25% of current resolution".
    func scalePercentLabel(_ percent: Int) -> String {
        String(format: string("convert.scale.percent"), Int64(percent))
    }

    func scaleMenuTitle(for option: String) -> String {
        if option == "convert.scale.original" || option.hasPrefix("convert.") {
            return string(option)
        }
        let digits = option.filter(\.isNumber)
        if let percent = Int(digits), percent > 0 {
            return scalePercentLabel(percent)
        }
        return option
    }

    /// Bundled `*.lproj` codes actually present in the app (or development tree).
    static func availableCodes() -> Set<String> {
        let urls = Bundle.main.urls(forResourcesWithExtension: "lproj", subdirectory: nil) ?? []
        var codes = Set(urls.map { $0.deletingPathExtension().lastPathComponent })
        codes.remove("Base")
        if codes.isEmpty {
            // Preview / unit-test fallback when the bundle is not the app bundle
            codes = ["en", "tr"]
        }
        return codes
    }

    static func bundleExists(_ code: String) -> Bool {
        if Bundle.main.path(forResource: code, ofType: "lproj") != nil {
            return true
        }
        return availableCodes().contains(code)
    }

    static func resolveSystemLanguage() -> String {
        let available = availableCodes()
        var candidates = Locale.preferredLanguages
        let current = Locale.current.identifier
        if !candidates.contains(where: {
            $0.replacingOccurrences(of: "_", with: "-")
                .caseInsensitiveCompare(current.replacingOccurrences(of: "_", with: "-")) == .orderedSame
        }) {
            candidates.append(current)
        }
        for pref in candidates {
            if let match = matchPreferred(pref, available: available) {
                return match
            }
        }
        if available.contains("en") { return "en" }
        return available.sorted().first ?? "en"
    }

    static func matchPreferred(_ preferred: String, available: Set<String>) -> String? {
        let norm = preferred.replacingOccurrences(of: "_", with: "-")
        if available.contains(norm) { return norm }

        let aliases: [String: String] = [
            "nb": "no", "nn": "no",
            "iw": "he",
            "in": "id",
            "tl": "fil", "fil-PH": "fil",
            "zh": "zh-Hans",
            "pt": "pt-PT",
        ]
        if let mapped = aliases[norm], available.contains(mapped) { return mapped }

        let parts = norm.split(separator: "-").map(String.init)
        let lang = parts.first ?? norm

        if lang == "zh" {
            let rest = norm.lowercased()
            if rest.contains("hk") || rest.contains("mo") || rest.contains("hant-hk") {
                if available.contains("zh-Hant-HK") { return "zh-Hant-HK" }
            }
            if rest.contains("tw") || rest.contains("hant") {
                if available.contains("zh-Hant-TW") { return "zh-Hant-TW" }
            }
            if available.contains("zh-Hans") { return "zh-Hans" }
            if available.contains("zh-CN") { return "zh-CN" }
        }

        if lang == "es" {
            if norm.contains("MX"), available.contains("es-MX") { return "es-MX" }
            if norm.contains("AR"), available.contains("es-AR") { return "es-AR" }
            if norm.contains("CL"), available.contains("es-CL") { return "es-CL" }
            if available.contains("es") { return "es" }
        }

        if lang == "pt" {
            if norm.contains("BR"), available.contains("pt-BR") { return "pt-BR" }
            if available.contains("pt-PT") { return "pt-PT" }
        }

        if lang == "en" {
            if norm.contains("CA"), available.contains("en-CA") { return "en-CA" }
            if available.contains("en") { return "en" }
        }

        if let mapped = aliases[lang], available.contains(mapped) { return mapped }
        if available.contains(lang) { return lang }
        return nil
    }

    static func bundleCandidates(for code: String) -> [String] {
        var out: [String] = [code]
        let parts = code.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            let lang = parts[0]
            if lang == "zh" {
                if code.hasPrefix("zh-Hant") {
                    out += ["zh-Hant-TW", "zh-Hant-HK"]
                } else {
                    out += ["zh-Hans", "zh-CN"]
                }
            } else if lang == "es" {
                out.append("es")
            } else if lang == "pt" {
                out += ["pt-PT", "pt-BR"]
            } else if lang == "en" {
                out.append("en")
            } else {
                out.append(lang)
            }
        }
        out.append("en")
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}

// MARK: - App Language Catalog
struct AppLanguage: Identifiable, Hashable {
    let code: String
    let flag: String
    let name: String
    var id: String { code }

    static func named(_ code: String) -> AppLanguage {
        all.first { $0.code == code }
            ?? AppLanguage(code: "en", flag: "🇬🇧", name: "English")
    }

    static let all: [AppLanguage] = [
        AppLanguage(code: "tr",       flag: "🇹🇷", name: "Türkçe"),
        AppLanguage(code: "en",       flag: "🇬🇧", name: "English"),
        AppLanguage(code: "en-CA",    flag: "🇨🇦", name: "English (Canada)"),
        AppLanguage(code: "de",       flag: "🇩🇪", name: "Deutsch"),
        AppLanguage(code: "fr",       flag: "🇫🇷", name: "Français"),
        AppLanguage(code: "it",       flag: "🇮🇹", name: "Italiano"),
        AppLanguage(code: "es",       flag: "🇪🇸", name: "Español"),
        AppLanguage(code: "es-MX",    flag: "🇲🇽", name: "Español (México)"),
        AppLanguage(code: "es-AR",    flag: "🇦🇷", name: "Español (Argentina)"),
        AppLanguage(code: "es-CL",    flag: "🇨🇱", name: "Español (Chile)"),
        AppLanguage(code: "ca",       flag: "🇦🇩", name: "Català"),
        AppLanguage(code: "gl",       flag: "🇪🇸", name: "Galego"),
        AppLanguage(code: "eu",       flag: "🇪🇸", name: "Euskara"),
        AppLanguage(code: "pt-PT",    flag: "🇵🇹", name: "Português"),
        AppLanguage(code: "pt-BR",    flag: "🇧🇷", name: "Português (Brasil)"),
        AppLanguage(code: "nl",       flag: "🇳🇱", name: "Nederlands"),
        AppLanguage(code: "sv",       flag: "🇸🇪", name: "Svenska"),
        AppLanguage(code: "no",       flag: "🇳🇴", name: "Norsk"),
        AppLanguage(code: "da",       flag: "🇩🇰", name: "Dansk"),
        AppLanguage(code: "fi",       flag: "🇫🇮", name: "Suomi"),
        AppLanguage(code: "is",       flag: "🇮🇸", name: "Íslenska"),
        AppLanguage(code: "pl",       flag: "🇵🇱", name: "Polski"),
        AppLanguage(code: "cs",       flag: "🇨🇿", name: "Čeština"),
        AppLanguage(code: "sk",       flag: "🇸🇰", name: "Slovenčina"),
        AppLanguage(code: "hu",       flag: "🇭🇺", name: "Magyar"),
        AppLanguage(code: "ro",       flag: "🇷🇴", name: "Română"),
        AppLanguage(code: "bg",       flag: "🇧🇬", name: "Български"),
        AppLanguage(code: "hr",       flag: "🇭🇷", name: "Hrvatski"),
        AppLanguage(code: "sl",       flag: "🇸🇮", name: "Slovenščina"),
        AppLanguage(code: "bs",       flag: "🇧🇦", name: "Bosanski"),
        AppLanguage(code: "sr",       flag: "🇷🇸", name: "Српски"),
        AppLanguage(code: "mk",       flag: "🇲🇰", name: "Македонски"),
        AppLanguage(code: "sq",       flag: "🇦🇱", name: "Shqip"),
        AppLanguage(code: "lt",       flag: "🇱🇹", name: "Lietuvių"),
        AppLanguage(code: "lv",       flag: "🇱🇻", name: "Latviešu"),
        AppLanguage(code: "et",       flag: "🇪🇪", name: "Eesti"),
        AppLanguage(code: "el",       flag: "🇬🇷", name: "Ελληνικά"),
        AppLanguage(code: "ga",       flag: "🇮🇪", name: "Gaeilge"),
        AppLanguage(code: "cy",       flag: "🇬🇧", name: "Cymraeg"),
        AppLanguage(code: "ru",       flag: "🇷🇺", name: "Русский"),
        AppLanguage(code: "uk",       flag: "🇺🇦", name: "Українська"),
        AppLanguage(code: "be",       flag: "🇧🇾", name: "Беларуская"),
        AppLanguage(code: "kk",       flag: "🇰🇿", name: "Қазақша"),
        AppLanguage(code: "ky",       flag: "🇰🇬", name: "Кыргызча"),
        AppLanguage(code: "uz",       flag: "🇺🇿", name: "Oʻzbek"),
        AppLanguage(code: "tk",       flag: "🇹🇲", name: "Türkmen"),
        AppLanguage(code: "az",       flag: "🇦🇿", name: "Azərbaycan"),
        AppLanguage(code: "tt",       flag: "🇷🇺", name: "Татарча"),
        AppLanguage(code: "ba",       flag: "🇷🇺", name: "Башҡортса"),
        AppLanguage(code: "cv",       flag: "🇷🇺", name: "Чăвашла"),
        AppLanguage(code: "sah",      flag: "🇷🇺", name: "Саха тыла"),
        AppLanguage(code: "tyv",      flag: "🇷🇺", name: "Тыва дыл"),
        AppLanguage(code: "alt",      flag: "🇷🇺", name: "Алтай тил"),
        AppLanguage(code: "gag",      flag: "🇲🇩", name: "Gagauzça"),
        AppLanguage(code: "ug",       flag: "🇨🇳", name: "ئۇيغۇرچە"),
        AppLanguage(code: "mn",       flag: "🇲🇳", name: "Монгол"),
        AppLanguage(code: "ka",       flag: "🇬🇪", name: "ქართული"),
        AppLanguage(code: "hy",       flag: "🇦🇲", name: "Հայերեն"),
        AppLanguage(code: "he",       flag: "🇮🇱", name: "עברית"),
        AppLanguage(code: "ar",       flag: "🇸🇦", name: "العربية"),
        AppLanguage(code: "fa",       flag: "🇮🇷", name: "فارسی"),
        AppLanguage(code: "sw",       flag: "🇹🇿", name: "Kiswahili"),
        AppLanguage(code: "am",       flag: "🇪🇹", name: "አማርኛ"),
        AppLanguage(code: "af",       flag: "🇿🇦", name: "Afrikaans"),
        AppLanguage(code: "zh-Hans",    flag: "🇨🇳", name: "中文(简体)"),
        AppLanguage(code: "zh-CN",      flag: "🇨🇳", name: "中文(中国)"),
        AppLanguage(code: "zh-Hant-TW", flag: "🇹🇼", name: "中文(繁體·台灣)"),
        AppLanguage(code: "zh-Hant-HK", flag: "🇭🇰", name: "中文(繁體·香港)"),
        AppLanguage(code: "ja",       flag: "🇯🇵", name: "日本語"),
        AppLanguage(code: "ko",       flag: "🇰🇷", name: "한국어"),
        AppLanguage(code: "hi",       flag: "🇮🇳", name: "हिन्दी"),
        AppLanguage(code: "bn",       flag: "🇧🇩", name: "বাংলা"),
        AppLanguage(code: "ur",       flag: "🇵🇰", name: "اردو"),
        AppLanguage(code: "pa",       flag: "🇮🇳", name: "ਪੰਜਾਬੀ"),
        AppLanguage(code: "ta",       flag: "🇮🇳", name: "தமிழ்"),
        AppLanguage(code: "te",       flag: "🇮🇳", name: "తెలుగు"),
        AppLanguage(code: "ml",       flag: "🇮🇳", name: "മലയാളം"),
        AppLanguage(code: "ne",       flag: "🇳🇵", name: "नेपाली"),
        AppLanguage(code: "si",       flag: "🇱🇰", name: "සිංහල"),
        AppLanguage(code: "th",       flag: "🇹🇭", name: "ภาษาไทย"),
        AppLanguage(code: "vi",       flag: "🇻🇳", name: "Tiếng Việt"),
        AppLanguage(code: "km",       flag: "🇰🇭", name: "ខ្មែរ"),
        AppLanguage(code: "lo",       flag: "🇱🇦", name: "ລາວ"),
        AppLanguage(code: "my",       flag: "🇲🇲", name: "မြန်မာ"),
        AppLanguage(code: "id",       flag: "🇮🇩", name: "Indonesia"),
        AppLanguage(code: "ms",       flag: "🇲🇾", name: "Melayu"),
        AppLanguage(code: "fil",      flag: "🇵🇭", name: "Filipino"),
    ]
}

// MARK: - Full Screen Detection
@MainActor
final class WindowStateObserver: ObservableObject {
    @Published var isFullScreen: Bool = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.isFullScreen = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.isFullScreen = false }
            .store(in: &cancellables)
    }
}

// MARK: - Detail Top Safe Area Helper
// Ignores safe area on top only when sidebar is visible (not detailOnly, not fullscreen).
extension View {
    func detailIgnoresSafeArea(columnVisibility: NavigationSplitViewVisibility, isFullScreen: Bool) -> some View {
        ignoresSafeArea(edges: (columnVisibility == .detailOnly || isFullScreen) ? [] : .top)
    }
}

// MARK: - Hand Cursor Hover
extension View {
    func handCursor() -> some View {
        self.modifier(HandCursorModifier())
    }
}

private struct HandCursorModifier: ViewModifier {
    @State private var isCurrentlyHovered = false

    func body(content: Content) -> some View {
        content.onHover { isHovered in
            DispatchQueue.main.async {
                if isHovered && !isCurrentlyHovered {
                    NSCursor.pointingHand.push()
                    isCurrentlyHovered = true
                } else if !isHovered && isCurrentlyHovered {
                    NSCursor.pop()
                    isCurrentlyHovered = false
                }
            }
        }
    }
}

// MARK: - Shared Inspector Section (ConvertImageView / VideoConvertView style)
/// Dil değişiminde yeniden çizim için `LanguageManager` ortam nesnesini kullanır.
/// Bölüm başlığı kartın dışında; mevcut kontroller yuvarlatılmış kartın içinde.
struct LabeledInspectorSection<Content: View>: View {
    let titleKey: String
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(languageManager.string(titleKey))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.horizontal, InspectorCardMetrics.contentInset)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: InspectorCardMetrics.cornerRadius, style: .continuous)
                    .fill(InspectorCardMetrics.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: InspectorCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(InspectorCardMetrics.cardBorder(for: colorScheme), lineWidth: InspectorCardMetrics.borderWidth)
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

enum InspectorCardMetrics {
    static let cornerRadius: CGFloat = 10
    static let chipCornerRadius: CGFloat = 8
    static let contentInset: CGFloat = 12
    static let borderWidth: CGFloat = 1

    /// Inspector sayfa zemini — koyu modda neredeyse siyah (#181818).
    static func panelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)
            : Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)
    }

    /// Kart dolgusu — zeminden yalnızca bir ton açık (#252525), süt gibi gri değil.
    static func cardFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 37 / 255, green: 37 / 255, blue: 37 / 255)
            : Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
    }

    /// 1px, çok düşük kontrastlı kart çerçevesi.
    static func cardBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    /// FORMAT chip / path alanı — karttan bir kademe açık (#333).
    static func chipFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
            : Color(red: 235 / 255, green: 235 / 255, blue: 235 / 255)
    }

    /// Chip hover / açık durum — #333 üzerinde hafif yükselme.
    static func chipFillRaised(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 58 / 255, green: 58 / 255, blue: 58 / 255)
            : Color(red: 226 / 255, green: 226 / 255, blue: 226 / 255)
    }

    static func chipBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.12)
    }

    static let menuCornerRadius: CGFloat = 10

    /// Açık format listesi — #2c2c2c, karttan ayrı panel.
    static func menuFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 44 / 255, green: 44 / 255, blue: 44 / 255)
            : Color(red: 248 / 255, green: 248 / 255, blue: 248 / 255)
    }

    static func menuBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.12)
    }

    static func menuItemHover(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    static func separator(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.08)
    }
}

/// Sağ inspector zeminini kart paletiyle eşler (`Material.bar` yerine).
struct InspectorPanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(InspectorCardMetrics.panelBackground(for: colorScheme))
    }
}

extension View {
    func inspectorPanelChrome() -> some View {
        modifier(InspectorPanelBackground())
    }
}

/// Kart içi satır: sol etiket, sağ kontrol.
struct InspectorSettingRow<Label: View, Control: View>: View {
    @ViewBuilder var label: () -> Label
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            label()
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 24)
    }
}

/// Kart kenarına kadar uzanan ince satır ayırıcı.
struct InspectorCardSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        InspectorCardMetrics.separator(for: colorScheme)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -InspectorCardMetrics.contentInset)
    }
}

/// FORMAT / dosya tipi seçici: solda "Biçim", sağda yükselen chip + özel popover listesi.
/// Native `Menu`/`Picker` kullanılmaz — macOS sistem menüsü (kırpık / buzlu) yerine
/// inspector üzerinde duran yuvarlatılmış panel açılır.
struct InspectorMenuChip<Selection: Hashable>: View {
    let title: String
    var labelKey: String = "inspector.format"
    @Binding var selection: Selection
    private let options: [InspectorMenuOption<Selection>]

    @State private var isOpen = false
    @State private var isChipHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var languageManager: LanguageManager

    init(
        title: String,
        labelKey: String = "inspector.format",
        selection: Binding<Selection>,
        options: [InspectorMenuOption<Selection>]
    ) {
        self.title = title
        self.labelKey = labelKey
        self._selection = selection
        self.options = options
    }

    init<C: Sequence>(
        title: String,
        labelKey: String = "inspector.format",
        selection: Binding<Selection>,
        options: C,
        label: (Selection) -> String
    ) where C.Element == Selection {
        self.title = title
        self.labelKey = labelKey
        self._selection = selection
        self.options = options.map { InspectorMenuOption(label: label($0), value: $0) }
    }

    var body: some View {
        InspectorSettingRow {
            Text(languageManager.string(labelKey))
                .font(.system(size: 13))
        } control: {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .textCase(.uppercase)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: InspectorCardMetrics.chipCornerRadius, style: .continuous)
                        .fill(chipFill)
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.10),
                            radius: 1.5,
                            y: 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: InspectorCardMetrics.chipCornerRadius, style: .continuous)
                        .strokeBorder(InspectorCardMetrics.chipBorder(for: colorScheme), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .handCursor()
            .onHover { isChipHovered = $0 }
            .popover(isPresented: $isOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                InspectorMenuChipList(
                    options: options,
                    selection: $selection,
                    isOpen: $isOpen
                )
            }
            .accessibilityLabel(languageManager.string(labelKey))
            .accessibilityValue(title)
            .accessibilityAddTraits(.isButton)
        }
    }

    private var chipFill: Color {
        (isOpen || isChipHovered)
            ? InspectorCardMetrics.chipFillRaised(for: colorScheme)
            : InspectorCardMetrics.chipFill(for: colorScheme)
    }
}

struct InspectorMenuOption<Selection: Hashable>: Identifiable, Hashable {
    let label: String
    let value: Selection
    var id: Selection { value }
}

private struct InspectorMenuChipList<Selection: Hashable>: View {
    let options: [InspectorMenuOption<Selection>]
    @Binding var selection: Selection
    @Binding var isOpen: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(options) { option in
                InspectorMenuChipRow(
                    label: option.label,
                    isSelected: option.value == selection
                ) {
                    selection = option.value
                    isOpen = false
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 5)
        .frame(minWidth: 132)
        .background(InspectorCardMetrics.menuFill(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: InspectorCardMetrics.menuCornerRadius, style: .continuous)
                .strokeBorder(InspectorCardMetrics.menuBorder(for: colorScheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InspectorCardMetrics.menuCornerRadius, style: .continuous))
        .modifier(InspectorMenuPopoverChrome())
    }
}

private struct InspectorMenuChipRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .opacity(isSelected ? 1 : 0)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer(minLength: 12)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? InspectorCardMetrics.menuItemHover(for: colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// macOS popover çerçevesini #2c2c2c + 10pt köşe + ince çerçeveye çeker.
private struct InspectorMenuPopoverChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .presentationBackground(InspectorCardMetrics.menuFill(for: colorScheme))
                .presentationCornerRadius(InspectorCardMetrics.menuCornerRadius)
                .background(InspectorPopoverChromeView())
        } else {
            content.background(InspectorPopoverChromeView())
        }
    }
}

private struct InspectorPopoverChromeView: NSViewRepresentable {
    func makeNSView(context: Context) -> InspectorPopoverHostView {
        InspectorPopoverHostView()
    }

    func updateNSView(_ nsView: InspectorPopoverHostView, context: Context) {
        nsView.applyChrome()
    }
}

private final class InspectorPopoverHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChrome()
        DispatchQueue.main.async { [weak self] in
            self?.applyChrome()
        }
    }

    func applyChrome() {
        guard let window else { return }
        let isDark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = isDark
            ? NSColor(calibratedRed: 44 / 255, green: 44 / 255, blue: 44 / 255, alpha: 0.98)
            : NSColor(calibratedRed: 248 / 255, green: 248 / 255, blue: 248 / 255, alpha: 0.98)
        let border = NSColor.white.withAlphaComponent(isDark ? 0.16 : 0.0)

        window.isOpaque = false
        window.backgroundColor = fill
        window.hasShadow = true

        if let frameView = window.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.cornerRadius = InspectorCardMetrics.menuCornerRadius
            frameView.layer?.cornerCurve = .continuous
            frameView.layer?.masksToBounds = true
            frameView.layer?.backgroundColor = fill.cgColor
            frameView.layer?.borderWidth = 1
            frameView.layer?.borderColor = (isDark
                ? border
                : NSColor.black.withAlphaComponent(0.12)
            ).cgColor
            hideArrowViews(in: frameView)
        }
    }

    private func hideArrowViews(in view: NSView) {
        for subview in view.subviews {
            let name = String(describing: type(of: subview))
            if name.localizedCaseInsensitiveContains("arrow") {
                subview.isHidden = true
                subview.alphaValue = 0
                continue
            }
            hideArrowViews(in: subview)
        }
    }
}

func inspectorSection<Content: View>(
    _ titleKey: String,
    @ViewBuilder content: @escaping () -> Content
) -> some View {
    LabeledInspectorSection(titleKey: titleKey, content: content)
}

// MARK: - Wrong Drop Type Overlay
@ViewBuilder
func wrongTypeOverlay(message: LocalizedStringKey) -> some View {
    ZStack {
        Color.red.opacity(0.08)
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.red.opacity(0.8))
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
    .allowsHitTesting(false)
}

// MARK: - Folder Picker Row
/// Inspector'lardaki klasör seçim satırı. Stale (yol bulunamadı) durumunu da gösterir.
struct FolderPickerRow: View {
    let folder: URL?
    let isStale: Bool
    let onPick: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            if isStale {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("folder.missing.title"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text(LocalizedStringKey("folder.missing.subtitle"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.orange.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.orange.opacity(0.22), lineWidth: 1))
            } else if let url = folder {
                Text(truncatedPath(url.path))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(InspectorCardMetrics.chipFill(for: colorScheme)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(InspectorCardMetrics.cardBorder(for: colorScheme), lineWidth: 1))
            } else {
                Text(LocalizedStringKey("convert.settings.noFolder"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.red.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.red.opacity(0.18), lineWidth: 1))
            }

            Button(LocalizedStringKey(isStale ? "folder.missing.pick" : "convert.settings.chooseFolder")) {
                onPick()
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Shared Path Truncation
func truncatedPath(_ path: String) -> String {
    let components = path.components(separatedBy: "/")
    guard components.count > 3 else { return path }
    let firstPart = components[1...2].joined(separator: "/")
    let lastPart = components[(components.count - 2)...].joined(separator: "/")
    return "/" + firstPart + "/.../" + lastPart
}

// MARK: - Scroll Wheel (trackpad pan / zoom)
extension View {
    /// Intercepts NSScrollWheel events via an NSView overlay.
    func onScrollWheel(_ handler: @escaping (NSEvent) -> Void) -> some View {
        overlay(ScrollWheelView(handler: handler))
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let handler: (NSEvent) -> Void

    func makeNSView(context: Context) -> _ScrollWheelNSView {
        let v = _ScrollWheelNSView()
        v.handler = handler
        return v
    }
    func updateNSView(_ nsView: _ScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

final class _ScrollWheelNSView: NSView {
    var handler: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        handler?(event)
    }
    override func magnify(with event: NSEvent) {
        handler?(event)
    }
    // Mouse click/drag event'lerini üst view'a geçir — SwiftUI gesture'larını bloklamaz.
    // hitTest nil YAPILMAMALI: nil yapılırsa scroll event'ler de bu view'a ulaşmaz.
    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        nextResponder?.mouseUp(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        nextResponder?.mouseDragged(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }
}

// MARK: - Folder Picker
/// Opens a directory-only NSOpenPanel and calls `onSelect` with the chosen URL.
func pickFolder(onSelect: @escaping (URL) -> Void) {
    DispatchQueue.main.async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }
}

// MARK: - NSColor SVG Hex
extension NSColor {
    func toSVGHex() -> String {
        guard let srgb = usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }
}
