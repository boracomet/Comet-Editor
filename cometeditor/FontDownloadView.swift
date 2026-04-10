//
//  FontDownloadView.swift
//  cometeditor
//

import SwiftUI
import AppKit
import Combine

// MARK: - Models

struct GoogleFont: Identifiable, Equatable {
    let id: String        // family name
    let family: String
    let category: String
    let variants: [String]
    let subsets: [String]
    let files: [String: String] // variant -> url
    let previewText: String?
}

// MARK: - Feeling Tags

enum FontFeeling: String, CaseIterable {
    case business     = "business"
    case calm         = "calm"
    case cute         = "cute"
    case vintage      = "vintage"
    case sophisticated = "sophisticated"
    case active       = "active"
    case innovative   = "innovative"
    case fancy        = "fancy"
    case playful      = "playful"
    case artistic     = "artistic"
    case loud         = "loud"
    case futuristic   = "futuristic"
    case stiff        = "stiff"
    case happy        = "happy"

    // Map feelings to font categories/keywords for filtering
    var filterKeywords: [String] {
        switch self {
        case .business:      return ["sans-serif", "serif"]
        case .calm:          return ["serif", "handwriting"]
        case .cute:          return ["handwriting", "display"]
        case .vintage:       return ["serif", "display"]
        case .sophisticated: return ["serif"]
        case .active:        return ["sans-serif", "display"]
        case .innovative:    return ["sans-serif", "monospace"]
        case .fancy:         return ["display", "handwriting"]
        case .playful:       return ["display", "handwriting"]
        case .artistic:      return ["display", "handwriting"]
        case .loud:          return ["display"]
        case .futuristic:    return ["sans-serif", "monospace"]
        case .stiff:         return ["monospace", "serif"]
        case .happy:         return ["display", "handwriting"]
        }
    }

    var localizedStringKey: String { "font.feeling.\(rawValue)" }

    var isItalic: Bool {
        switch self {
        case .fancy, .artistic, .cute, .sophisticated: return true
        default: return false
        }
    }
}

// MARK: - Google Fonts API Service

@MainActor
final class GoogleFontsService: ObservableObject {
    static let apiKey = "AIzaSyA8dcK5a5Ych9R7zTQ-Np3b8t0q1774hUM"
    static let baseURL = "https://www.googleapis.com/webfonts/v1/webfonts"

    @Published var fonts: [GoogleFont] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    private var allFonts: [GoogleFont] = []

    func loadFonts(sortBy: SortOption = .trending) async {
        isLoading = true
        errorMessage = nil

        let sortParam: String
        switch sortBy {
        case .trending:   sortParam = "trending"
        case .popular:    sortParam = "popularity"
        case .newest:     sortParam = "date"
        case .alpha:      sortParam = "alpha"
        case .alphaDesc:  sortParam = "alpha"
        }

        guard let url = URL(string: "\(Self.baseURL)?key=\(Self.apiKey)&sort=\(sortParam)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(GoogleFontsResponse.self, from: data)
            var loaded = decoded.items.map { item in
                GoogleFont(
                    id: item.family,
                    family: item.family,
                    category: item.category,
                    variants: item.variants,
                    subsets: item.subsets,
                    files: item.files,
                    previewText: nil
                )
            }
            if sortBy == .alphaDesc {
                loaded.reverse()
            }
            allFonts = loaded
            fonts = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func filter(query: String, feeling: FontFeeling?, writingSystem: String?) {
        var result = allFonts

        if !query.isEmpty {
            result = result.filter { $0.family.localizedCaseInsensitiveContains(query) }
        }

        if let feeling = feeling {
            result = result.filter { font in
                feeling.filterKeywords.contains(font.category)
            }
        }

        if let ws = writingSystem, !ws.isEmpty, ws != "All" {
            let subset = ws.lowercased().replacingOccurrences(of: " ", with: "-")
            result = result.filter { $0.subsets.contains(subset) }
        }

        fonts = result
    }
}

// MARK: - JSON Models

struct GoogleFontsResponse: Decodable {
    let items: [GoogleFontItem]
}

struct GoogleFontItem: Decodable {
    let family: String
    let category: String
    let variants: [String]
    let subsets: [String]
    let files: [String: String]
}

// MARK: - Sort Option

enum SortOption: String, CaseIterable {
    case trending  = "Trending"
    case popular   = "Most Popular"
    case newest    = "Newest"
    case alpha     = "A–Z"
    case alphaDesc = "Z–A"
}

// MARK: - Writing Systems

struct WritingSystem: Identifiable, Equatable, Hashable {
    let id: String          // subset key for API filtering
    let labelKey: String    // i18n key

    static func == (lhs: WritingSystem, rhs: WritingSystem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

let writingSystems: [WritingSystem] = [
    WritingSystem(id: "All",                    labelKey: "font.writing.all"),
    WritingSystem(id: "latin",                  labelKey: "font.writing.latin"),
    WritingSystem(id: "cyrillic",               labelKey: "font.writing.cyrillic"),
    WritingSystem(id: "greek",                  labelKey: "font.writing.greek"),
    WritingSystem(id: "arabic",                 labelKey: "font.writing.arabic"),
    WritingSystem(id: "hebrew",                 labelKey: "font.writing.hebrew"),
    WritingSystem(id: "devanagari",             labelKey: "font.writing.devanagari"),
    WritingSystem(id: "chinese-simplified",     labelKey: "font.writing.chinese_simplified"),
    WritingSystem(id: "chinese-traditional",    labelKey: "font.writing.chinese_traditional"),
    WritingSystem(id: "japanese",               labelKey: "font.writing.japanese"),
    WritingSystem(id: "korean",                 labelKey: "font.writing.korean"),
    WritingSystem(id: "thai",                   labelKey: "font.writing.thai"),
    WritingSystem(id: "vietnamese",             labelKey: "font.writing.vietnamese"),
]

// MARK: - FontDownloadView

struct FontDownloadView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var service = GoogleFontsService()

    @State private var searchQuery = ""
    @State private var selectedFeeling: FontFeeling? = nil
    @State private var selectedWritingSystem: WritingSystem = writingSystems[0]
    @State private var sortOption: SortOption = .trending
    @State private var previewText: String = ""
    @State private var fontSize: CGFloat = 40
    @State private var selectedFont: GoogleFont? = nil
    @State private var downloadingFonts: Set<String> = []
    @State private var downloadedFonts: Set<String> = []

    private let searchDebounce = 0.3

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Main Content
            VStack(spacing: 0) {
                // Top Bar
                topBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Font List
                fontListArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Right Inspector
            rightInspector
                .frame(width: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .task {
            await service.loadFonts(sortBy: sortOption)
        }
        .onChange(of: searchQuery) { _ in applyFilter() }
        .onChange(of: selectedFeeling) { _ in applyFilter() }
        .onChange(of: selectedWritingSystem) { _ in applyFilter() }
        .onChange(of: sortOption) { _ in
            Task { await service.loadFonts(sortBy: sortOption) }
        }
        .overlay {
            if let font = selectedFont {
                FontDetailModal(font: font, onClose: { selectedFont = nil })
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondary)
                    .font(.system(size: 14))
                TextField("font.search.placeholder", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .frame(maxWidth: .infinity)

            // Sort Picker
            Picker("", selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            // Font count
            if !service.isLoading {
                Text(String(format: LanguageManager.shared.string("font.families.count"), service.fonts.count))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .fixedSize()
            }
        }
    }

    // MARK: - Font List Area

    private var fontListArea: some View {
        Group {
            if service.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(LocalizedStringKey("stock.loading"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = service.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.secondary)
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if service.fonts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "textformat")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.secondary)
                    Text(LocalizedStringKey("font.noResults"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(service.fonts) { font in
                            FontRow(
                                font: font,
                                previewText: effectivePreviewText(for: font),
                                fontSize: fontSize,
                                isDownloading: downloadingFonts.contains(font.id),
                                isDownloaded: downloadedFonts.contains(font.id),
                                onDownload: { downloadFont(font) }
                            )
                            .onTapGesture { selectedFont = font }
                            Divider().padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Right Inspector

    private var rightInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack {
                    Text(languageManager.string("convert.settings.title"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                // Preview settings
                inspectorSection(languageManager.string("font.inspector.preview")) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(languageManager.string("font.preview.custom"), text: $previewText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(languageManager.string("font.inspector.fontSize"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                                Spacer()
                                Text("\(Int(fontSize))px")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                            }
                            Slider(value: $fontSize, in: 16...96, step: 2)
                                .controlSize(.small)
                        }
                    }
                }

                Divider()

                // Feeling Filter
                inspectorSection(languageManager.string("font.inspector.feeling")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(FontFeeling.allCases, id: \.self) { feeling in
                            FeelingChip(
                                label: languageManager.string(feeling.localizedStringKey),
                                isSelected: selectedFeeling == feeling,
                                isItalic: feeling.isItalic,
                                onTap: {
                                    selectedFeeling = selectedFeeling == feeling ? nil : feeling
                                }
                            )
                        }
                    }
                }

                Divider()

                // Language / Writing System
                inspectorSection(languageManager.string("font.inspector.language")) {
                    Picker("", selection: $selectedWritingSystem) {
                        ForEach(writingSystems) { ws in
                            Text(languageManager.string(ws.labelKey)).tag(ws)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, -16)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Material.bar)
    }

    // MARK: - Helpers

    private func effectivePreviewText(for font: GoogleFont) -> String {
        if !previewText.isEmpty { return previewText }
        return "The quick brown fox jumps over the lazy dog"
    }

    private func applyFilter() {
        service.filter(
            query: searchQuery,
            feeling: selectedFeeling,
            writingSystem: selectedWritingSystem.id == "All" ? nil : selectedWritingSystem.id
        )
    }

    private func downloadFont(_ font: GoogleFont) {
        guard !downloadingFonts.contains(font.id) else { return }

        // Ask user where to save
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appState.targetFolder
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let destFolder = panel.url else { return }

        downloadingFonts.insert(font.id)

        let variantKey = font.variants.contains("regular") ? "regular" : font.variants.first ?? "regular"
        guard let urlString = font.files[variantKey],
              let url = URL(string: urlString.replacingOccurrences(of: "http://", with: "https://")) else {
            downloadingFonts.remove(font.id)
            return
        }

        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let fileName = "\(font.family.replacingOccurrences(of: " ", with: ""))-\(variantKey).ttf"
                let destURL = destFolder.appendingPathComponent(fileName)
                try data.write(to: destURL)
                downloadingFonts.remove(font.id)
                downloadedFonts.insert(font.id)
                CometAnalytics.shared.trackEvent(
                    page: "fontDownload",
                    eventType: .fontDownloaded,
                    metadata: ["family": font.family]
                )
            } catch {
                downloadingFonts.remove(font.id)
            }
        }
    }
}

// MARK: - FontRow

struct FontRow: View {
    let font: GoogleFont
    let previewText: String
    let fontSize: CGFloat
    let isDownloading: Bool
    let isDownloaded: Bool
    let onDownload: () -> Void

    @State private var loadedFont: NSFont? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // Family name + meta
                HStack(spacing: 8) {
                    Text(font.family)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text(font.variants.count == 1 ? "1 style" : "\(font.variants.count) styles")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)

                    Text("|")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.5))

                    Text(font.category)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }

                // Preview text
                if let nsFont = loadedFont {
                    Text(previewText)
                        .font(.init(nsFont.withSize(fontSize)))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(previewText)
                        .font(.system(size: fontSize))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)

            // Download button (always visible)
            Button(action: onDownload) {
                Group {
                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                    } else if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || isDownloaded)
            .padding(.trailing, 24)
        }
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovered = $0 }
        .task(id: font.id) {
            await loadWebFont()
        }
    }

    private func loadWebFont() async {
        let variantKey = font.variants.contains("regular") ? "regular" : font.variants.first ?? "regular"
        guard let urlString = font.files[variantKey],
              let url = URL(string: urlString.replacingOccurrences(of: "http://", with: "https://")) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                let registered = registerFont(data: data)
                if let registered {
                    loadedFont = registered
                }
            }
        } catch {}
    }

    @MainActor
    private func registerFont(data: Data) -> NSFont? {
        let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor]
        guard let first = descriptors?.first else { return nil }
        let ctFont = CTFontCreateWithFontDescriptor(first, 40, nil)
        return ctFont as NSFont
    }
}

// MARK: - FeelingChip

struct FeelingChip: View {
    let label: String
    let isSelected: Bool
    let isItalic: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(isItalic
                      ? .system(size: 11, weight: isSelected ? .semibold : .regular).italic()
                      : .system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

// MARK: - Font Detail Modal

private struct FontDetailModal: View {
    let font: GoogleFont
    let onClose: () -> Void

    @State private var previewText: String = ""
    @State private var fontSize: CGFloat = 48
    @State private var loadedFonts: [String: NSFont] = [:]

    private let previewDefault = "Whereas recognition of the inherent dignity"

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            // Modal card
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 16) {
                    // Font info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(font.family)
                            .font(.system(size: 15, weight: .semibold))
                        Text(String(format: LanguageManager.shared.string("font.styles.count"), font.variants.count, font.category))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }

                    Spacer()

                    // Preview input
                    HStack(spacing: 8) {
                        TextField(LocalizedStringKey("font.preview.custom"), text: $previewText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        if !previewText.isEmpty {
                            Button { previewText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    )
                    .frame(width: 260)

                    // Font size slider
                    HStack(spacing: 6) {
                        Text("\(Int(fontSize))px")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 40)
                        Slider(value: $fontSize, in: 16...120, step: 2)
                            .frame(width: 130)
                            .controlSize(.small)
                    }

                    // Close
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .padding(7)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)

                Divider()

                // Variant list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedVariants, id: \.self) { variant in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(variantDisplayName(variant))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                                    .padding(.top, 18)

                                Group {
                                    if let nsFont = loadedFonts[variant] {
                                        Text(effectiveText)
                                            .font(.init(nsFont.withSize(fontSize)))
                                    } else {
                                        Text(effectiveText)
                                            .font(.system(size: fontSize))
                                    }
                                }
                                .foregroundStyle(Color.primary)
                                .lineLimit(2)
                                .padding(.bottom, 18)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)

                            Divider()
                        }
                    }
                }
            }
            .frame(width: 860, height: 600)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
        .task(id: font.id) { await loadAllVariants() }
    }

    private var effectiveText: String { previewText.isEmpty ? previewDefault : previewText }

    private var sortedVariants: [String] {
        let order = ["100","200","300","regular","500","600","700","800","900",
                     "100italic","200italic","300italic","italic","500italic","600italic","700italic","800italic","900italic"]
        return font.variants.sorted {
            (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99)
        }
    }

    private func variantDisplayName(_ v: String) -> String {
        switch v {
        case "regular": return "Regular 400"
        case "italic":  return "Italic 400"
        default:
            let isItalic = v.hasSuffix("italic")
            let weightStr = isItalic ? String(v.dropLast("italic".count)) : v
            let weight = Int(weightStr) ?? 400
            let name: String
            switch weight {
            case 100: name = "Thin"
            case 200: name = "ExtraLight"
            case 300: name = "Light"
            case 500: name = "Medium"
            case 600: name = "SemiBold"
            case 700: name = "Bold"
            case 800: name = "ExtraBold"
            case 900: name = "Black"
            default:  name = "\(weight)"
            }
            return isItalic ? "\(name) \(weight) Italic" : "\(name) \(weight)"
        }
    }

    private func loadAllVariants() async {
        await withTaskGroup(of: (String, Data?).self) { group in
            for variant in font.variants {
                guard let urlStr = font.files[variant],
                      let url = URL(string: urlStr.replacingOccurrences(of: "http://", with: "https://")) else { continue }
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return (variant, nil) }
                    return (variant, data)
                }
            }
            for await (variant, data) in group {
                guard let data else { continue }
                await MainActor.run {
                    let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor]
                    if let first = descriptors?.first {
                        loadedFonts[variant] = CTFontCreateWithFontDescriptor(first, 48, nil) as NSFont
                    }
                }
            }
        }
    }
}

#Preview {
    FontDownloadView(columnVisibility: .constant(NavigationSplitViewVisibility.all))
        .frame(width: 900, height: 700)
}
