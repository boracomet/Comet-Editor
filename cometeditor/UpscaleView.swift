//
//  UpscaleView.swift
//  cometeditor
//
//  Liste + modal: satıra tıklayınca karşılaştırma; Dönüştür cometscaly çalıştırır.
//  Sonuç bellekte kalır. Sayfa değişince Task iptal edilmez.
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing
import AppKit

struct UpscaleView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var windowState: WindowStateObserver

    @State private var outputFormat: UpscaleOutputFormat = .png
    @State private var selectedScale: UpscaleScale = .x4
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorAlertMessage: String = ""
    @State private var isDropTargeted = false
    @State private var isWrongTypeDrop = false
    @State private var wrongTypeTask: Task<Void, Never>? = nil
    @State private var isSavingDownloads = false

    @State private var previewItem: ImageItem?
    @State private var previewFullImage: NSImage?
    @State private var previewScale: UpscaleScale = .x4
    @State private var previewZoom: CGFloat = 1.0
    @State private var previewOffset: CGSize = .zero
    @State private var beforeAfterRatio: CGFloat = 0.5

    private var items: [ImageItem] { appState.upscaleImages }
    private var completedCount: Int { items.filter { $0.isCompleted && $0.upscaledImage != nil }.count }

    var body: some View {
        HStack(spacing: 0) {
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .sheet(item: $previewItem) { item in
            UpscaleCompareSheet(
                itemID: item.id,
                previewScale: $previewScale,
                previewFullImage: $previewFullImage,
                beforeAfterRatio: $beforeAfterRatio,
                previewZoom: $previewZoom,
                previewOffset: $previewOffset,
                onConvert: {
                    startUpscale(itemIDs: [item.id], scale: previewScale)
                },
                onClose: {
                    previewItem = nil
                    previewFullImage = nil
                    previewZoom = 1.0
                    previewOffset = .zero
                }
            )
            .frame(minWidth: 860, idealWidth: 980, minHeight: 580, idealHeight: 680)
            .environmentObject(appState)
            .environmentObject(languageManager)
        }
        .onChange(of: previewItem) { item in
            guard let item else {
                previewFullImage = nil
                return
            }
            beforeAfterRatio = 0.5
            previewScale = selectedScale
            previewZoom = 1.0
            previewOffset = .zero
            loadFullImage(for: item)
        }
        .alert(LocalizedStringKey("alert.success.title"), isPresented: $showSuccessAlert) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
            if let folderURL = appState.targetFolder {
                Button(LocalizedStringKey("alert.openFolder")) {
                    NSWorkspace.shared.open(folderURL)
                }
            }
        } message: {
            if let path = appState.targetFolder?.path {
                Text(String(format: NSLocalizedString("alert.success.message.image", comment: ""), path))
            }
        }
        .alert(LocalizedStringKey("alert.error.title"), isPresented: $showErrorAlert) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
        } message: {
            Text(errorAlertMessage)
        }
        .onAppear { consumePendingAlerts() }
        .onChange(of: appState.upscalePendingSuccess) { ok in
            if ok { consumePendingAlerts() }
        }
        .onChange(of: appState.upscalePendingErrorMessage) { msg in
            if msg != nil { consumePendingAlerts() }
        }
        .onDisappear {
            // Yalnızca yanlış-tür uyarısını temizle — upscale Task'ı iptal etme.
            wrongTypeTask?.cancel()
        }
    }

    private func consumePendingAlerts() {
        if appState.upscalePendingSuccess {
            appState.upscalePendingSuccess = false
            showSuccessAlert = true
        }
        if let msg = appState.upscalePendingErrorMessage {
            appState.upscalePendingErrorMessage = nil
            errorAlertMessage = msg
            showErrorAlert = true
        }
    }

    private func loadFullImage(for item: ImageItem) {
        Task.detached(priority: .userInitiated) {
            let (url, accessed) = item.securityScopedURL()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            let fullImage: NSImage?
            if ext == "svg" || ext == "ai" {
                fullImage = NSImage(contentsOf: url)
            } else {
                var srcOpts: [CFString: Any] = [:]
                if ext == "jfif" || ext == "jpe" {
                    srcOpts[kCGImageSourceTypeIdentifierHint] = "public.jpeg" as CFString
                }
                guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts as CFDictionary),
                      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
                fullImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            guard let img = fullImage else { return }
            await MainActor.run {
                guard previewItem?.id == item.id else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    previewFullImage = img
                }
            }
        }
    }

    // MARK: - Main

    @ViewBuilder
    private var mainContentArea: some View {
        if items.isEmpty {
            emptyDropZone
        } else {
            imageList
        }
    }

    private var emptyDropZone: some View {
        Button(action: selectFilesFromFinder) {
            VStack(spacing: 16) {
                Image(systemName: isWrongTypeDrop ? "exclamationmark.triangle" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(isWrongTypeDrop ? Color.red.opacity(0.7) : Color.secondary.opacity(0.6))

                VStack(spacing: 8) {
                    Text(isWrongTypeDrop ? LocalizedStringKey("upscale.wrongType") : LocalizedStringKey("upscale.drop.title"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isWrongTypeDrop ? Color.red.opacity(0.8) : Color.primary)

                    Text("upscale.drop.subtitle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .opacity(isWrongTypeDrop ? 0 : 1)

                    Text(LocalizedStringKey("upscale.drop.formats"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .opacity(isWrongTypeDrop ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .padding(24)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isWrongTypeDrop ? Color.red.opacity(0.5) : (isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .padding(24)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isWrongTypeDrop)
    }

    private var imageList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        UpscaleListRow(
                            item: item,
                            isProcessing: appState.upscaleActiveItemID == item.id,
                            onOpen: {
                                previewItem = item
                            },
                            onRemove: {
                                appState.upscaleImages.removeAll(where: { $0.id == item.id })
                                if previewItem?.id == item.id {
                                    previewItem = nil
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if isWrongTypeDrop {
                    wrongTypeOverlay(message: LocalizedStringKey("upscale.wrongType"))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isWrongTypeDrop)

            Divider()

            HStack(spacing: 16) {
                Button {
                    appState.upscaleImages.removeAll()
                    previewItem = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("convert.clearAll")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.primary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .handCursor()

                Button(action: selectFilesFromFinder) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("convert.addMore")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .handCursor()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Inspector

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inspectorSection("upscale.settings.model") {
                    HStack {
                        Text(languageManager.string("upscale.model.cometStandard"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                }

                inspectorSection("upscale.settings.scale") {
                    Picker("", selection: $selectedScale) {
                        ForEach(UpscaleScale.allCases) { scale in
                            Text(scale.label).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if selectedScale.rawValue > 4 {
                        Text(languageManager.string("upscale.scale.multiPassHint"))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                            .padding(.top, 2)
                    }
                }

                inspectorSection("inspector.output") {
                    InspectorMenuChip(title: outputFormat.rawValue.uppercased(), selection: $outputFormat, options: Array(UpscaleOutputFormat.allCases)) { $0.rawValue.uppercased() }
                }

                inspectorSection("convert.settings.targetFolder") {
                    FolderPickerRow(
                        folder: appState.targetFolder,
                        isStale: appState.targetFolderStale
                    ) {
                        pickFolder { url in
                            appState.handleFolderSelected(url)
                            appState.targetFolder = url
                        }
                    }
                }

                if !UpscaleEngine.isBackendAvailable() {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(LocalizedStringKey("upscale.backend.missing.hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }

                VStack(spacing: 8) {
                    Button {
                        Task { await downloadCompletedUpscales() }
                    } label: {
                        HStack {
                            if isSavingDownloads {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("upscale.downloadUpscaled")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(completedCount == 0 || isSavingDownloads)

                    Button {
                        let ids = items.filter { $0.upscaledImage == nil }.map(\.id)
                        let targetIDs = ids.isEmpty ? items.map(\.id) : ids
                        startUpscale(itemIDs: targetIDs, scale: selectedScale)
                    } label: {
                        HStack {
                            if appState.isUpscaling {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                if appState.upscaleProgressLabel.isEmpty {
                                    Text(LocalizedStringKey("video.processing"))
                                } else {
                                    Text(appState.upscaleProgressLabel)
                                }
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("upscale.upscaleAll")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        items.isEmpty
                        || appState.isUpscaling
                        || !UpscaleEngine.isBackendAvailable()
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .padding(.top, 16)
        }
        .inspectorPanelChrome()
    }

    // MARK: - Drop & files

    private static let supportedImageTypes: [UTType] = [.png, .jpeg, .webP, .tiff, .gif, .heic, .bmp]

    private static let videoTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie, .mpeg, .avi]

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpeg", "mpg", "3gp"]

    private static let upscaleRasterExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "tif", "tiff", "gif", "bmp", "heic", "heif"]

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            let isVideo = Self.videoTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
                || provider.registeredTypeIdentifiers.contains { id in
                    id.contains("mpeg") || id.contains("mp4") || id.contains("video") || id.contains("movie")
                }
            let isSupported = Self.supportedImageTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }

            if isVideo {
                wrongTypeTask?.cancel()
                isWrongTypeDrop = true
                wrongTypeTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { isWrongTypeDrop = false }
                }
                handled = true
                continue
            }

            if isSupported || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = {
                        if let u = item as? URL { return u }
                        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                        return nil
                    }()
                    if let url {
                        loadImages(from: [url])
                    }
                }
                handled = true
            }
        }
        return handled
    }

    private func selectFilesFromFinder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedImageTypes
        panel.allowsOtherFileTypes = true

        if panel.runModal() == .OK {
            loadImages(from: panel.urls)
        }
    }

    private func loadImages(from urls: [URL]) {
        let existing = Set(appState.upscaleImages.map(\.url))
        let newURLs = urls.filter {
            !existing.contains($0) &&
            Self.upscaleRasterExtensions.contains($0.pathExtension.lowercased()) &&
            !Self.videoExtensions.contains($0.pathExtension.lowercased())
        }
        guard !newURLs.isEmpty else {
            if urls.contains(where: { !Self.upscaleRasterExtensions.contains($0.pathExtension.lowercased()) }) {
                wrongTypeTask?.cancel()
                isWrongTypeDrop = true
                wrongTypeTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { isWrongTypeDrop = false }
                }
            }
            return
        }

        Task.detached(priority: .userInitiated) {
            var built: [ImageItem] = []
            for url in newURLs {
                let accessed = url.startAccessingSecurityScopedResource()
                let bookmark = ImageItem.makeBookmark(for: url)

                var fileSizeStr = "0 KB"
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    fileSizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                }

                var dimStr = ""
                var nsImage: NSImage? = nil
                let ext0 = url.pathExtension.lowercased()

                if ext0 == "svg" || ext0 == "ai" {
                    if let img = NSImage(contentsOf: url) {
                        nsImage = img
                        let sz = img.size
                        dimStr = sz.width > 0 ? "\(Int(sz.width))×\(Int(sz.height))" : ""
                    }
                } else {
                    var srcOpts: [CFString: Any] = [:]
                    if ext0 == "jfif" || ext0 == "jpe" {
                        srcOpts[kCGImageSourceTypeIdentifierHint] = "public.jpeg" as CFString
                    }
                    if let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts as CFDictionary) {
                        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                           let w = props[kCGImagePropertyPixelWidth] as? Int,
                           let h = props[kCGImagePropertyPixelHeight] as? Int {
                            dimStr = "\(w)×\(h)"
                        }
                        let thumbOpts: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 720,
                            kCGImageSourceCreateThumbnailWithTransform: true
                        ]
                        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) {
                            nsImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        }
                    } else {
                        let request = QLThumbnailGenerator.Request(
                            fileAt: url,
                            size: CGSize(width: 720, height: 720),
                            scale: 2.0,
                            representationTypes: .all
                        )
                        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                            nsImage = rep.nsImage
                            dimStr = "\(Int(rep.nsImage.size.width))×\(Int(rep.nsImage.size.height))"
                        }
                    }
                }

                if accessed { url.stopAccessingSecurityScopedResource() }
                built.append(ImageItem(url: url, image: nsImage, fileSizeString: fileSizeStr, dimensionsString: dimStr, bookmarkData: bookmark))
            }

            let items = built
            await MainActor.run {
                appState.upscaleImages.append(contentsOf: items)
            }
        }
    }

    // MARK: - Upscale (bellekte; sayfa değişince kesilmez)

    @MainActor
    private func startUpscale(itemIDs: [UUID], scale: UpscaleScale) {
        guard appState.upscaleTask == nil, !itemIDs.isEmpty else { return }
        let state = appState
        state.isUpscaling = true
        state.upscaleProgressPercent = 0
        state.upscaleProgressLabel = ""
        state.processingMenuItem = .upscaleImage

        state.upscaleTask = Task { @MainActor in
            defer {
                state.isUpscaling = false
                state.upscaleProgressLabel = ""
                state.upscaleProgressPercent = 0
                state.upscaleActiveItemID = nil
                state.processingMenuItem = nil
                state.upscaleTask = nil
            }

            var success = 0
            var errors: [String] = []
            let total = itemIDs.count

            for (index, id) in itemIDs.enumerated() {
                guard let item = state.upscaleImages.first(where: { $0.id == id }) else { continue }
                state.upscaleActiveItemID = id
                state.upscaleProgressLabel = "\(index + 1)/\(total)"
                state.upscaleProgressPercent = 0

                do {
                    let image = try await Self.upscaleToMemory(item: item, scale: scale) { pct in
                        Task { @MainActor in
                            state.upscaleProgressPercent = pct
                        }
                    }
                    if let i = state.upscaleImages.firstIndex(where: { $0.id == id }) {
                        state.upscaleImages[i].upscaledImage = image
                        state.upscaleImages[i].isCompleted = true
                        state.upscaleImages[i].outputDimensionsString = Self.pixelDimensionsString(image)
                    }
                    success += 1
                } catch {
                    if error is CancellationError { break }
                    errors.append("\(item.fileName): \(error.localizedDescription)")
                }
            }

            if !errors.isEmpty {
                state.upscalePendingErrorMessage = errors.joined(separator: "\n")
            } else if success == 0 {
                state.upscalePendingErrorMessage = String(localized: "upscale.error.none")
            }
        }
    }

    private static func upscaleToMemory(
        item: ImageItem,
        scale: UpscaleScale,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> NSImage {
        let (url, accessed) = item.securityScopedURL()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let tmpOut = fm.temporaryDirectory
            .appendingPathComponent("comet_upscale_\(UUID().uuidString).png")
        defer { try? fm.removeItem(at: tmpOut) }

        try await UpscaleEngine.upscale(inputURL: url, outputURL: tmpOut, scale: scale, progress: progress)

        if let img = NSImage(contentsOf: tmpOut) {
            return img
        }
        guard let src = CGImageSourceCreateWithURL(tmpOut as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw UpscaleEngineError.processFailed(code: -1, message: String(localized: "upscale.preview.loadFailed"))
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let img = NSImage(size: NSSize(width: cg.width, height: cg.height))
        img.addRepresentation(rep)
        return img
    }

    private static func pixelDimensionsString(_ image: NSImage) -> String {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return "\(cg.width)×\(cg.height)"
        }
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return "\(rep.pixelsWide)×\(rep.pixelsHigh)"
        }
        let w = Int(image.size.width.rounded())
        let h = Int(image.size.height.rounded())
        return w > 0 && h > 0 ? "\(w)×\(h)" : ""
    }

    private static func outputImageData(from image: NSImage, format: UpscaleOutputFormat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
    }

    @MainActor
    private func downloadCompletedUpscales() async {
        let completed = appState.upscaleImages.filter { $0.isCompleted && $0.upscaledImage != nil }
        guard !completed.isEmpty else { return }
        guard let folder = await appState.resolveOutputFolder() else { return }

        isSavingDownloads = true
        defer { isSavingDownloads = false }

        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

        let fmt = outputFormat
        var success = 0
        var errors: [String] = []

        for item in completed {
            guard let image = item.upscaledImage else { continue }
            guard let data = Self.outputImageData(from: image, format: fmt) else {
                errors.append("\(item.fileName): \(String(localized: "upscale.preview.saveFailed"))")
                continue
            }
            let base = item.url.deletingPathExtension().lastPathComponent
            var outURL = folder.appendingPathComponent("\(base)_upscaled.\(fmt.fileExtension)")
            var n = 1
            while FileManager.default.fileExists(atPath: outURL.path) {
                n += 1
                outURL = folder.appendingPathComponent("\(base)_upscaled_\(n).\(fmt.fileExtension)")
            }
            do {
                try data.write(to: outURL)
                let size = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int64) ?? Int64(data.count)
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                if let i = appState.upscaleImages.firstIndex(where: { $0.id == item.id }) {
                    appState.upscaleImages[i].outputURL = outURL
                    appState.upscaleImages[i].outputFileSizeString = sizeStr
                }
                success += 1
            } catch {
                errors.append("\(item.fileName): \(error.localizedDescription)")
            }
        }

        if success > 0 {
            appState.upscalePendingSuccess = true
        }
        if !errors.isEmpty {
            appState.upscalePendingErrorMessage = errors.joined(separator: "\n")
        } else if success == 0 {
            appState.upscalePendingErrorMessage = String(localized: "upscale.error.none")
        }
    }
}

// MARK: - Compare modal

private struct UpscaleCompareSheet: View {
    let itemID: UUID
    @Binding var previewScale: UpscaleScale
    @Binding var previewFullImage: NSImage?
    @Binding var beforeAfterRatio: CGFloat
    @Binding var previewZoom: CGFloat
    @Binding var previewOffset: CGSize
    let onConvert: () -> Void
    let onClose: () -> Void

    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var languageManager: LanguageManager

    @State private var fittedSize: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var pinchStart: CGFloat = 1.0
    @State private var isPinching = false
    @State private var splitStart: CGFloat = 0.5
    @State private var dragKind: CompareDragKind = .undecided

    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 8.0
    private static let zoomStep: CGFloat = 1.25

    private var live: ImageItem? {
        appState.upscaleImages.first(where: { $0.id == itemID })
    }

    private var isThisProcessing: Bool {
        appState.isUpscaling && appState.upscaleActiveItemID == itemID
    }

    private var zoomPercent: Int {
        Int((previewZoom * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { containerGeo in
                ZStack {
                    Color(NSColor.underPageBackgroundColor)
                    canvas(containerSize: containerGeo.size)
                    if isThisProcessing {
                        processingOverlay
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onScrollWheel { event in
                handleScrollWheel(event)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
            if let live {
                VStack(alignment: .leading, spacing: 1) {
                    Text(live.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(live.dimensionsString.isEmpty ? live.fileSizeString : "\(live.fileSizeString) · \(live.dimensionsString)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
            }

            Spacer()

            zoomControls

            Picker("", selection: $previewScale) {
                ForEach(UpscaleScale.allCases) { scale in
                    Text(scale.label).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            Button(action: onConvert) {
                HStack(spacing: 4) {
                    if isThisProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(languageManager.string("upscale.convert"))
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.isUpscaling || !UpscaleEngine.isBackendAvailable())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .padding(7)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .handCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    applyZoom(previewZoom / Self.zoomStep)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(previewZoom <= Self.minZoom + 0.001)
            .help(languageManager.string("upscale.zoom.out"))
            .accessibilityLabel(languageManager.string("upscale.zoom.out"))

            Button(action: resetZoom) {
                Text("\(zoomPercent)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 40)
            }
            .buttonStyle(.plain)
            .help(languageManager.string("upscale.zoom.reset"))
            .accessibilityLabel(languageManager.string("upscale.zoom.reset"))

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    applyZoom(previewZoom * Self.zoomStep)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(previewZoom >= Self.maxZoom - 0.001)
            .help(languageManager.string("upscale.zoom.in"))
            .accessibilityLabel(languageManager.string("upscale.zoom.in"))
        }
        .foregroundStyle(Color.primary.opacity(0.78))
        .padding(.horizontal, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .handCursor()
    }

    @ViewBuilder
    private func canvas(containerSize: CGSize) -> some View {
        let thumb = live?.image
        let result = live?.upscaledImage
        if previewFullImage == nil && thumb == nil {
            ProgressView().controlSize(.large)
        } else if let upscaled = result, let original = previewFullImage ?? thumb {
            beforeAfterComparison(original: original, upscaled: upscaled, containerSize: containerSize)
        } else if let nsImage = previewFullImage ?? thumb {
            let displaySize = fittedDisplaySize(for: nsImage, in: containerSize)
            ZStack {
                Color(NSColor.underPageBackgroundColor)
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        withCompareZoom(displaySize: displaySize, allowsSplitDrag: false) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: displaySize.width, height: displaySize.height)
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }

                if !isThisProcessing && previewZoom <= 1.01 {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(languageManager.string("upscale.preview.hint"))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(languageManager.string("upscale.preview.processing"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text("\(appState.upscaleProgressPercent)%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func beforeAfterComparison(original: NSImage, upscaled: NSImage, containerSize: CGSize) -> some View {
        let displaySize = fittedDisplaySize(for: original, in: containerSize)

        ZStack {
            Color(NSColor.underPageBackgroundColor)
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    withCompareZoom(displaySize: displaySize, allowsSplitDrag: true) {
                        ZStack(alignment: .leading) {
                            Image(nsImage: upscaled)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: displaySize.width, height: displaySize.height)
                                .clipped()

                            Image(nsImage: original)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: displaySize.width, height: displaySize.height)
                                .clipped()
                                .mask(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: max(1, displaySize.width * beforeAfterRatio), height: displaySize.height)
                                }

                            Rectangle()
                                .fill(.white)
                                .frame(width: 2, height: displaySize.height)
                                .offset(x: displaySize.width * beforeAfterRatio - 1)
                                .shadow(color: .black.opacity(0.45), radius: 3)

                            Circle()
                                .fill(.white)
                                .frame(width: 28, height: 28)
                                .shadow(color: .black.opacity(0.35), radius: 4)
                                .overlay {
                                    HStack(spacing: 2) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 8, weight: .bold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundStyle(.black.opacity(0.6))
                                }
                                .offset(x: displaySize.width * beforeAfterRatio - 14, y: displaySize.height / 2 - 14)

                            HStack {
                                Text(languageManager.string("upscale.preview.before"))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.55), in: Capsule())
                                Spacer()
                                Text(languageManager.string("upscale.preview.after"))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.55), in: Capsule())
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    // MARK: - Zoom / pan

    private func withCompareZoom<Content: View>(
        displaySize: CGSize,
        allowsSplitDrag: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: displaySize.width, height: displaySize.height)
            .clipped()
            .scaleEffect(previewZoom)
            .offset(previewOffset)
            .contentShape(Rectangle())
            .gesture(imageDragGesture(displaySize: displaySize, allowsSplitDrag: allowsSplitDrag))
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(TapGesture(count: 2).onEnded { _ in resetZoom() })
            .onAppear { fittedSize = displaySize }
            .onChange(of: displaySize.width) { _ in fittedSize = displaySize }
            .onChange(of: displaySize.height) { _ in fittedSize = displaySize }
            .handCursor()
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchStart = previewZoom
                }
                applyZoom(pinchStart * value)
            }
            .onEnded { _ in
                isPinching = false
                pinchStart = previewZoom
                if previewZoom < 1.05 {
                    previewZoom = 1.0
                    previewOffset = .zero
                    panStart = .zero
                }
            }
    }

    private func imageDragGesture(displaySize: CGSize, allowsSplitDrag: Bool) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragKind == .undecided {
                    let splitX = displaySize.width * beforeAfterRatio
                    let handleSlop = 24 / max(previewZoom, 1)
                    let nearSplit = abs(value.startLocation.x - splitX) < handleSlop
                    if allowsSplitDrag && (previewZoom <= 1.01 || nearSplit) {
                        dragKind = .split
                        splitStart = beforeAfterRatio
                    } else if previewZoom > 1.01 {
                        dragKind = .pan
                        panStart = previewOffset
                    } else {
                        dragKind = .ignored
                    }
                }
                switch dragKind {
                case .split:
                    if previewZoom <= 1.01 {
                        let relX = value.location.x / max(1, displaySize.width)
                        beforeAfterRatio = max(0.05, min(0.95, relX))
                    } else {
                        beforeAfterRatio = max(0.05, min(0.95, splitStart + value.translation.width / max(1, displaySize.width)))
                    }
                case .pan:
                    previewOffset = clampedOffset(CGSize(
                        width: panStart.width + value.translation.width,
                        height: panStart.height + value.translation.height
                    ))
                case .undecided, .ignored:
                    break
                }
            }
            .onEnded { _ in
                if dragKind == .pan {
                    panStart = previewOffset
                }
                dragKind = .undecided
            }
    }

    private func handleScrollWheel(_ event: NSEvent) {
        if event.type == .magnify {
            let delta = event.magnification
            guard abs(delta) > 0 else { return }
            applyZoom(previewZoom * (1 + delta))
            return
        }
        guard event.type == .scrollWheel else { return }

        let dy = event.scrollingDeltaY
        if abs(dy) > 0.01 {
            if event.hasPreciseScrollingDeltas {
                applyZoom(previewZoom * (1 + dy * 0.008))
            } else {
                applyZoom(previewZoom * (dy > 0 ? 1.08 : 1 / 1.08))
            }
            return
        }

        if previewZoom > 1.001, abs(event.scrollingDeltaX) > 0 {
            previewOffset = clampedOffset(CGSize(
                width: previewOffset.width - event.scrollingDeltaX,
                height: previewOffset.height
            ))
        }
    }

    private func applyZoom(_ z: CGFloat) {
        let clamped = min(Self.maxZoom, max(Self.minZoom, z))
        previewZoom = clamped
        if clamped <= 1.001 {
            previewOffset = .zero
            panStart = .zero
        } else {
            previewOffset = clampedOffset(previewOffset)
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            previewZoom = 1.0
            previewOffset = .zero
        }
        panStart = .zero
        pinchStart = 1.0
        isPinching = false
        dragKind = .undecided
    }

    private func clampedOffset(_ offset: CGSize) -> CGSize {
        let maxX = max(0, fittedSize.width * (previewZoom - 1) / 2)
        let maxY = max(0, fittedSize.height * (previewZoom - 1) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }

    private func fittedDisplaySize(for image: NSImage, in container: CGSize) -> CGSize {
        let imgW = image.representations.first.map { CGFloat($0.pixelsWide) } ?? image.size.width
        let imgH = image.representations.first.map { CGFloat($0.pixelsHigh) } ?? image.size.height
        let imgAspect = imgW / max(1, imgH)
        let containerAspect = container.width / max(1, container.height)
        if imgAspect > containerAspect {
            let w = container.width
            return CGSize(width: w, height: w / imgAspect)
        }
        let h = container.height
        return CGSize(width: h * imgAspect, height: h)
    }
}

private enum CompareDragKind {
    case undecided, split, pan, ignored
}

// MARK: - Finder-style upscale list row

private struct UpscaleListRow: View {
    let item: ImageItem
    let isProcessing: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private var formatLabel: String {
        item.url.pathExtension.uppercased()
    }

    private var subtitle: String {
        var parts: [String] = []
        if !item.fileSizeString.isEmpty { parts.append(item.fileSizeString) }
        if !item.dimensionsString.isEmpty { parts.append(item.dimensionsString) }
        if !formatLabel.isEmpty { parts.append(formatLabel) }
        return parts.joined(separator: " · ")
    }

    private var resultMint: Color {
        Color(red: 0.40, green: 0.84, blue: 0.58)
    }

    private var resultSuffix: String? {
        guard item.isCompleted else { return nil }
        var parts: [String] = []
        if let dim = item.outputDimensionsString, !dim.isEmpty {
            parts.append(dim)
        }
        if let size = item.outputFileSizeString, !size.isEmpty {
            parts.append(size)
        }
        guard !parts.isEmpty else { return nil }
        return "→ " + parts.joined(separator: " · ")
    }

    private var metadataLine: Text {
        let base = Text(subtitle).foregroundColor(Color.secondary)
        guard let suffix = resultSuffix else { return base }
        return base + Text(" \(suffix)").foregroundColor(resultMint)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        metadataLine
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()

            if item.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, resultMint)
                    .font(.system(size: 16))
                    .accessibilityLabel(Text(LocalizedStringKey("upscale.convert")))
            } else if isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .padding(6)
                    .background(Color.primary.opacity(isHovered ? 0.12 : 0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .handCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 72)
        }
        .onHover { isHovered = $0 }
    }

    private var thumbnail: some View {
        Group {
            if let nsImage = item.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview {
    UpscaleView(columnVisibility: .constant(.all))
        .environmentObject(GlobalAppState())
        .environmentObject(LanguageManager.shared)
        .environmentObject(WindowStateObserver())
}
#endif
