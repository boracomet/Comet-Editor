//
//  StockImageView.swift
//  cometeditor
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO

// MARK: - Models

struct UnsplashPhoto: Identifiable, Equatable {
    let id: String
    let thumbURL: URL
    let fullURL: URL
    let regularURL: URL
    let description: String?
    let photographerName: String
    let unsplashURL: URL
    let originalWidth: Int?
    let originalHeight: Int?
    var isSelected: Bool = false
}

// MARK: - StockImageView

struct StockImageView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchQuery: String = ""
    @State private var photos: [UnsplashPhoto] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = true

    // Inspector
    @State private var selectedFormat: ImageFormat = .jpeg
    @State private var quality: Double = 8
    @State private var scaleEnabled: Bool = false
    @State private var scaleSelection: String = "75%"
    @State private var metadataEnabled: Bool = true
    @State private var isDownloading: Bool = false
    @State private var downloadProgress: Double = 0

    @State private var previewPhoto: UnsplashPhoto? = nil
    @State private var showScrollTop: Bool = false

    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var alertMessage: String = ""
    @EnvironmentObject var windowState: WindowStateObserver

    private var scaleOptions: [String] {
        ["25%", "50%", "75%"]
    }
    private var selectedPhotos: [UnsplashPhoto] { photos.filter(\.isSelected) }
    private var selectedCount: Int { selectedPhotos.count }

    var body: some View {
        HStack(spacing: 0) {
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .onAppear { if photos.isEmpty { Task { await loadRandom() } } }
        .overlay {
            if let photo = previewPhoto {
                StockPhotoPreviewModal(photo: photo, onClose: { previewPhoto = nil })
            }
        }
        .alert(LocalizedStringKey("alert.success.title"), isPresented: $showSuccessAlert) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) {}
            if let folder = appState.targetFolder {
                Button(LocalizedStringKey("alert.openFolder")) { NSWorkspace.shared.open(folder) }
            }
        } message: { Text(alertMessage) }
        .alert(LocalizedStringKey("alert.error.title"), isPresented: $showErrorAlert) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) {}
        } message: { Text(alertMessage) }
    }

    // MARK: - Main Content

    private var mainContentArea: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            contentArea
        }
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)
                .font(.system(size: 13))
                .padding(.leading, 12)

            TextField(LocalizedStringKey("stock.search.placeholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .onSubmit { Task { await performSearch(reset: true) } }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    Task { await loadRandom() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }

            Divider().frame(height: 20)

            Button {
                Task { await performSearch(reset: true) }
            } label: {
                Text(LocalizedStringKey("stock.search.button"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .handCursor()

            Divider().frame(height: 20)

            Button {
                Task { await loadRandom() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text(LocalizedStringKey("stock.random"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .handCursor()
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && photos.isEmpty {
            VStack(spacing: 16) {
                ProgressView()
                Text(LocalizedStringKey("stock.loading"))
                    .foregroundStyle(Color.secondary)
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, photos.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.secondary)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            VStack(spacing: 0) {
                // Selected count bar — only shown when items are selected
                if selectedCount > 0 {
                    HStack {
                        Spacer()
                        Text(String(format: NSLocalizedString("stock.selected", comment: ""), selectedCount))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Button {
                            for i in photos.indices { photos[i].isSelected = false }
                        } label: {
                            Text(LocalizedStringKey("stock.deselectAll"))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)

                    Divider()
                }

                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            MasonryGrid(
                                photos: photos,
                                availableWidth: geo.size.width,
                                hasMore: hasMore,
                                isLoading: isLoading,
                                onTap: { i in photos[i].isSelected.toggle() },
                                onPreview: { i in previewPhoto = photos[i] },
                                onLoadMore: { Task { await loadMore() } },
                                onScroll: { _ in }
                            )
                            .id("top")
                            .background(
                                GeometryReader { inner in
                                    Color.clear.preference(
                                        key: ScrollOffsetKey.self,
                                        value: -inner.frame(in: .named("stockScroll")).minY
                                    )
                                }
                            )
                        }
                        .coordinateSpace(name: "stockScroll")
                        .onPreferenceChange(ScrollOffsetKey.self) { offset in
                            showScrollTop = offset > 300
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if showScrollTop {
                                Button {
                                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(Color.primary.opacity(0.75)))
                                        .shadow(radius: 4)
                                }
                                .buttonStyle(.plain)
                                .handCursor()
                                .padding(16)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: showScrollTop)
                    }
                }
            }
        }
    }

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(LanguageManager.shared.string("convert.settings.title"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                // Export Format
                inspectorSection("convert.settings.format") {
                    Picker("", selection: $selectedFormat) {
                        ForEach(ImageFormat.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                // Quality
                inspectorSection("convert.settings.quality") {
                    HStack(spacing: 8) {
                        Slider(value: $quality, in: 0...10, step: 1)
                        Text("\(Int(quality))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }

                Divider()

                // Scale
                inspectorSection("convert.settings.scale") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(LocalizedStringKey("convert.settings.enable"))
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $scaleEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .onChange(of: scaleEnabled) { _ in }
                        }
                        if scaleEnabled {
                            Picker("", selection: $scaleSelection) {
                                ForEach(scaleOptions, id: \.self) { opt in
                                    Text(LocalizedStringKey(opt)).tag(opt)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .padding(.top, 2)
                        }
                    }
                }

                Divider()

                // Metadata
                inspectorSection("meta.info") {
                    HStack {
                        Text(LocalizedStringKey("convert.settings.enable"))
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $metadataEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                Divider()

                // Target Folder
                inspectorSection("convert.settings.targetFolder") {
                    HStack(spacing: 8) {
                        if let folderURL = appState.targetFolder {
                            Text(truncatedPath(folderURL.path))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.primary.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        } else {
                            Text("convert.settings.noFolder")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.red.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                )
                        }

                        Button("convert.settings.chooseFolder") {
                            pickFolder { appState.targetFolder = $0 }
                        }
                        .controlSize(.small)
                    }
                }

                Divider()

                // Download Button
                VStack(spacing: 10) {
                    if isDownloading {
                        ProgressView(value: downloadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 4)
                        Text(String(format: "%d%%", Int(downloadProgress * 100)))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }

                    Button {
                        isDownloading = true
                        downloadProgress = 0
                        Task { await downloadSelected() }
                    } label: {
                        HStack {
                            if isDownloading {
                                ProgressView().controlSize(.small)
                                Text(LocalizedStringKey("video.processing"))
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text(selectedCount > 0
                                     ? String(format: languageManager.string("stock.download.count"), selectedCount)
                                     : languageManager.string("stock.download"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedCount == 0 || appState.targetFolder == nil || isDownloading)
                }
                .padding(16)
            }
        }
        .background(Material.bar)
    }

    // MARK: - API

    private let headers: [String: String] = [
        "Authorization": "Client-ID 8672af113b0a8573edae3aa3713886265d9bb741d707f6c01a486cde8c278980",
        "Accept-Version": "v1"
    ]

    @MainActor
    private func loadRandom() async {
        searchQuery = ""
        currentPage = 1
        photos = []
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var request = URLRequest(url: URL(string: "https://api.unsplash.com/photos/random?count=30")!, cachePolicy: .reloadIgnoringLocalCacheData)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let items = try JSONDecoder().decode([UnsplashRandomItem].self, from: data)
            photos = items.compactMap(\.toPhoto)
            hasMore = true  // Aşağı kaydırınca daha fazla random yüklensin
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadRandomMore() async {
        guard searchQuery.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var request = URLRequest(url: URL(string: "https://api.unsplash.com/photos/random?count=30")!, cachePolicy: .reloadIgnoringLocalCacheData)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let items = try JSONDecoder().decode([UnsplashRandomItem].self, from: data)
            photos.append(contentsOf: items.compactMap(\.toPhoto))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performSearch(reset: Bool) async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            await loadRandom(); return
        }
        if reset {
            currentPage = 1
            photos = []
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let query = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
        var request = URLRequest(url: URL(string: "https://api.unsplash.com/search/photos?query=\(query)&per_page=30&page=\(currentPage)")!)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(UnsplashSearchResult.self, from: data)
            let newPhotos = result.results.compactMap(\.toPhoto)
            if reset { photos = newPhotos } else { photos.append(contentsOf: newPhotos) }
            hasMore = currentPage < result.total_pages
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        if searchQuery.isEmpty {
            await loadRandomMore()
        } else {
            currentPage += 1
            await performSearch(reset: false)
        }
    }

    // MARK: - Download

    @MainActor
    private func downloadSelected() async {
        guard let folder = appState.targetFolder else {
            isDownloading = false
            return
        }
        appState.processingMenuItem = .stockImage
        defer {
            isDownloading = false
            appState.processingMenuItem = nil
        }

        let toDownload = selectedPhotos
        let scaleFactor: Double
        if scaleEnabled && scaleSelection != "convert.scale.original" {
            scaleFactor = (Double(scaleSelection.dropLast()) ?? 100.0) / 100.0
        } else {
            scaleFactor = 1.0
        }
        for (i, photo) in toDownload.enumerated() {
            let url = photo.regularURL
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let nsImage = NSImage(data: data) else { continue }

                let ext = selectedFormat.rawValue == "jpeg" ? "jpg" : selectedFormat.rawValue
                let outputName = "\(photo.id)_unsplash.\(ext)"
                let outputURL = folder.appendingPathComponent(outputName)

                try await save(image: nsImage, to: outputURL, format: selectedFormat, scale: scaleFactor, customSize: nil)
            } catch { }

            downloadProgress = Double(i + 1) / Double(toDownload.count)
        }

        for i in photos.indices { photos[i].isSelected = false }
        CometAnalytics.shared.trackEvent(
            page: "stockImage",
            eventType: .stockDownloaded,
            metadata: ["count": toDownload.count, "format": selectedFormat.rawValue]
        )
        alertMessage = String(format: NSLocalizedString("alert.success.message.image", comment: ""), folder.path)
        showSuccessAlert = true
    }

    private func save(image: NSImage, to url: URL, format: ImageFormat, scale: Double, customSize: CGSize?) async throws {
        var finalImage = image

        // Apply custom size if set
        if let size = customSize, size.width > 0, size.height > 0 {
            let newSize = NSSize(width: size.width, height: size.height)
            let scaled = NSImage(size: newSize)
            scaled.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            scaled.unlockFocus()
            finalImage = scaled
        } else if scale != 1.0 {
            let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let scaled = NSImage(size: newSize)
            scaled.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            scaled.unlockFocus()
            finalImage = scaled
        }

        let qualityFactor = quality / 10.0

        guard let tiff = finalImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return }

        switch format {
        case .jpeg:
            let data = rep.representation(using: .jpeg, properties: [.compressionFactor: qualityFactor])
            try data?.write(to: url)
        case .png:
            let data = rep.representation(using: .png, properties: [:])
            try data?.write(to: url)
        case .bmp:
            let data = rep.representation(using: .bmp, properties: [:])
            try data?.write(to: url)
        case .tiff:
            let data = rep.representation(using: .tiff, properties: [:])
            try data?.write(to: url)
        case .gif:
            let data = rep.representation(using: .gif, properties: [:])
            try data?.write(to: url)
        case .webp:
            guard let cg = finalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let codecQuality = CodecQuality(value: Int(qualityFactor * 100))
            _ = try await CometImageCodec.shared.convert(cgImage: cg, outputURL: url, format: .webp, quality: codecQuality)
        case .avif:
            guard let cg = finalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let codecQuality = CodecQuality(value: Int(qualityFactor * 100))
            _ = try await CometImageCodec.shared.convert(cgImage: cg, outputURL: url, format: .avif, quality: codecQuality)
        case .heif:
            if let cgImage = finalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.heic" as CFString, 1, nil)
                if let dest = dest {
                    let options: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: qualityFactor]
                    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
                    CGImageDestinationFinalize(dest)
                }
            }
        case .heic:
            guard let cg = finalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let heicQuality = CodecQuality(value: Int(qualityFactor * 100))
            _ = try await CometImageCodec.shared.convert(cgImage: cg, outputURL: url, quality: heicQuality, magickFormat: "HEIC")
        case .jp2:
            guard let cg = finalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let jp2Quality = CodecQuality(value: Int(qualityFactor * 100))
            _ = try await CometImageCodec.shared.convert(cgImage: cg, outputURL: url, quality: jp2Quality, magickFormat: "JP2")
        }
    }
}

// MARK: - Masonry Grid
// Distributes photos into N columns using a true masonry layout (shortest column first).
// Each image renders at its natural aspect ratio so rows never misalign.

private struct MasonryGrid: View {
    let photos: [UnsplashPhoto]
    let availableWidth: CGFloat
    let hasMore: Bool
    let isLoading: Bool
    let onTap: (Int) -> Void
    let onPreview: (Int) -> Void
    let onLoadMore: () -> Void
    let onScroll: (CGFloat) -> Void
    private let columnCount = 4
    private let spacing: CGFloat = 2

    var body: some View {
        let colWidth = (availableWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<columnCount, id: \.self) { col in
                    let items = columnPhotos(col: col, total: columnCount)
                    LazyVStack(spacing: spacing) {
                        ForEach(items, id: \.offset) { item in
                            StockPhotoCell(
                                photo: item.photo,
                                isSelected: item.photo.isSelected,
                                width: colWidth,
                                onTap: { onTap(item.globalIndex) },
                                onPreview: { onPreview(item.globalIndex) }
                            )
                            // Son kolondaki son elemana gelince otomatik yükle
                            .onAppear {
                                if col == columnCount - 1 && item.offset == items.count - 1 && hasMore && !isLoading {
                                    onLoadMore()
                                }
                            }
                        }
                    }
                }
            }

            if isLoading && !photos.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct IndexedPhoto {
        let offset: Int       // position within column (for ForEach id)
        let globalIndex: Int  // index in photos array
        let photo: UnsplashPhoto
    }

    private func columnPhotos(col: Int, total: Int) -> [IndexedPhoto] {
        var result: [IndexedPhoto] = []
        var colOffset = 0
        for (i, photo) in photos.enumerated() {
            if i % total == col {
                result.append(IndexedPhoto(offset: colOffset, globalIndex: i, photo: photo))
                colOffset += 1
            }
        }
        return result
    }
}

// MARK: - Photo Cell

private struct StockPhotoCell: View {
    let photo: UnsplashPhoto
    let isSelected: Bool
    let width: CGFloat
    let onTap: () -> Void
    let onPreview: () -> Void

    @State private var loadedImage: NSImage? = nil
    @State private var imageSize: CGSize = CGSize(width: 4, height: 3) // default 4:3
    @State private var isHovered = false

    private var cellHeight: CGFloat {
        width * (imageSize.height / imageSize.width)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            Group {
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(width: width, height: cellHeight)
            .clipped()

            // Hover overlay with info
            if isHovered || isSelected {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    if let desc = photo.description {
                        Text(desc)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    Link(destination: photo.unsplashURL) {
                        Text(String(format: NSLocalizedString("stock.photo.by", comment: ""), photo.photographerName))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.8))
                            .underline()
                    }
                    if let w = photo.originalWidth, let h = photo.originalHeight {
                        Text("\(w)×\(h)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(8)
            }

            // Selection indicator top-right + web icon top-left + preview bottom-right
            VStack {
                HStack {
                    Link(destination: photo.unsplashURL) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(6)
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.black.opacity(0.3))
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(6)
                }
                Spacer()
                HStack {
                    Spacer()
                    if isHovered || isSelected {
                        Button { onPreview() } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .overlay(
            Rectangle()
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
        .handCursor()
        .task(id: photo.id) {
            guard loadedImage == nil else { return }
            if let (data, _) = try? await URLSession.shared.data(from: photo.regularURL),
               let img = NSImage(data: data) {
                loadedImage = img
                imageSize = img.size
            }
        }
    }
}

// MARK: - Scroll Offset Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Unsplash JSON Models

private struct UnsplashRandomItem: Decodable {
    let id: String
    let description: String?
    let alt_description: String?
    let urls: UnsplashURLs
    let links: UnsplashLinks
    let user: UnsplashUser
    let width: Int?
    let height: Int?

    var toPhoto: UnsplashPhoto? {
        guard let thumb = URL(string: urls.thumb),
              let full = URL(string: urls.full),
              let regular = URL(string: urls.regular),
              let htmlLink = URL(string: links.html) else { return nil }
        return UnsplashPhoto(
            id: id,
            thumbURL: thumb,
            fullURL: full,
            regularURL: regular,
            description: description ?? alt_description,
            photographerName: user.name,
            unsplashURL: htmlLink,
            originalWidth: width,
            originalHeight: height
        )
    }
}

private struct UnsplashSearchResult: Decodable {
    let results: [UnsplashRandomItem]
    let total_pages: Int
}

private struct UnsplashURLs: Decodable {
    let thumb: String
    let regular: String
    let full: String
}

private struct UnsplashLinks: Decodable {
    let html: String
}

private struct UnsplashUser: Decodable {
    let name: String
}

// MARK: - Photo Preview Modal

private struct StockPhotoPreviewModal: View {
    let photo: UnsplashPhoto
    let onClose: () -> Void

    @State private var loadedImage: NSImage? = nil
    @State private var isLoading = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }

                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            if let desc = photo.description {
                                Text(desc)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                            Link(destination: photo.unsplashURL) {
                                Text(String(format: NSLocalizedString("stock.photo.by", comment: ""), photo.photographerName))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Spacer()
                        Button { onClose() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.secondary)
                                .padding(7)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                    Divider()

                    ZStack {
                        Color.black
                        if isLoading {
                            ProgressView()
                                .controlSize(.large)
                        }
                        if let img = loadedImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(
                    width: min(900, geo.size.width * 0.92),
                    height: min(620, geo.size.height * 0.90)
                )
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        .task {
            isLoading = true
            if let (data, _) = try? await URLSession.shared.data(from: photo.fullURL),
               let img = NSImage(data: data) {
                loadedImage = img
            }
            isLoading = false
        }
    }
}
