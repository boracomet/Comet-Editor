//
//  ConvertImageView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

struct ConvertImageView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var selectedFormat: ImageFormat = .png
    @State private var quality: Double = 8
    @State private var resizeEnabled = false
    @State private var scaleEnabled = false
    @State private var scaleSelection: String = "convert.scale.original"
    var scaleOptions: [String] {
        ["convert.scale.original", "%75", "%50", "%25"]
    }
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""
    @State private var metadataEnabled = true

    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver
    @State private var isProcessing = false
    @State private var showSuccessAlert = false
    @State private var showConversionStubAlert = false
    @State private var isDropTargeted = false
    @State private var isWrongTypeDrop = false
    @State private var wrongTypeTask: Task<Void, Never>? = nil
    @Environment(\.colorScheme) private var colorScheme

    // Preview Image Modal
    @State private var previewItem: ImageItem?
    @State private var previewFullImage: NSImage?
    @State private var previewZoom: CGFloat = 1.0
    @State private var previewOffset: CGSize = .zero
    @State private var previewImageFrame: CGSize = .zero

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Main Area
            Group {
                if previewItem != nil {
                    inlinePreview
                } else {
                    mainContentArea
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: previewItem != nil)

            Divider()

            // MARK: - Right Inspector Panel
            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .onChange(of: previewItem) { item in
            guard let item else {
                previewFullImage = nil
                return
            }
            Task.detached(priority: .userInitiated) {
                let url = item.url
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                let ext = url.pathExtension.lowercased()
                let fullImage: NSImage?
                if ext == "svg" || ext == "ai" || ext == "pdf" {
                    let request = QLThumbnailGenerator.Request(
                        fileAt: url,
                        size: CGSize(width: 4096, height: 4096),
                        scale: 2.0,
                        representationTypes: .all
                    )
                    fullImage = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
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
                    withAnimation(.easeInOut(duration: 0.15)) {
                        previewFullImage = img
                    }
                }
            }
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
        .alert(LocalizedStringKey("app.comingSoon.title"), isPresented: $showConversionStubAlert) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
        } message: {
            Text(LocalizedStringKey("app.comingSoon.message"))
        }
    }

    // MARK: - Inline Preview (full-area, replaces grid)
    private var inlinePreview: some View {
        VStack(spacing: 0) {
            // Info bar
            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                if let item = previewItem {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(item.fileSizeString + " " + item.dimensionsString)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        previewItem = nil; previewFullImage = nil
                        previewZoom = 1.0; previewOffset = .zero
                    }
                } label: {
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

            Divider()

            // Image canvas
            ZStack {
                Color(NSColor.underPageBackgroundColor)
                if previewFullImage == nil && previewItem?.image == nil {
                    ProgressView().controlSize(.large)
                }
                if let nsImage = previewFullImage ?? previewItem?.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .background(
                            GeometryReader { g in
                                Color.clear
                                    .onAppear { previewImageFrame = g.size }
                                    .onChange(of: g.size) { previewImageFrame = $0 }
                            }
                        )
                        .scaleEffect(previewZoom)
                        .offset(previewOffset)
                        .allowsHitTesting(false)
                    // Gesture capture layer — separate from image so buttons above remain clickable
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onChanged { v in
                            if previewZoom > 1.0 { previewOffset = clampedOffset(v.translation) }
                        })
                        .gesture(MagnificationGesture()
                            .onChanged { v in
                                previewZoom = max(1.0, min(v, 6.0))
                                previewOffset = clampedOffset(previewOffset)
                            }
                            .onEnded { _ in
                                if previewZoom < 1.05 {
                                    withAnimation(.spring()) { previewZoom = 1.0; previewOffset = .zero }
                                }
                            }
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onScrollWheel { event in
                if event.type == .magnify {
                    let delta = event.magnification
                    if abs(delta) > 0 {
                        let z = max(1.0, min(previewZoom + delta * previewZoom, 6.0))
                        previewZoom = z
                        previewOffset = clampedOffset(previewOffset)
                        if z <= 1.0 { previewOffset = .zero }
                    }
                } else if event.type == .scrollWheel && previewZoom > 1.0 {
                    previewOffset = clampedOffset(CGSize(
                        width: previewOffset.width - event.scrollingDeltaX,
                        height: previewOffset.height - event.scrollingDeltaY
                    ))
                }
            }
        }
    }

    // MARK: - Main Content Area
    @ViewBuilder
    private var mainContentArea: some View {
        if appState.selectedImages.isEmpty {
            emptyDropZone
        } else {
            imageGrid
        }
    }

    private var emptyDropZone: some View {
        Button(action: selectFilesFromFinder) {
            VStack(spacing: 16) {
                Image(systemName: isWrongTypeDrop ? "exclamationmark.triangle" : "photo.badge.plus")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(isWrongTypeDrop ? Color.red.opacity(0.7) : Color.secondary.opacity(0.6))

                VStack(spacing: 8) {
                    Text(isWrongTypeDrop ? LocalizedStringKey("convert.wrongType.image") : LocalizedStringKey("convert.drop.title"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isWrongTypeDrop ? Color.red.opacity(0.8) : Color.primary)

                    Text("convert.drop.subtitle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .opacity(isWrongTypeDrop ? 0 : 1)

                    Text(LocalizedStringKey("convert.drop.formats"))
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
            return handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isWrongTypeDrop)
    }

    private var imageGrid: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    let columnCount = max(2, Int(geo.size.width / 240))
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.selectedImages) { item in
                            imageGridItem(item)
                        }
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                return handleDrop(providers)
            }
            .overlay {
                if isWrongTypeDrop {
                    wrongTypeOverlay(message: LocalizedStringKey("convert.wrongType.image"))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isWrongTypeDrop)

            Divider()

            // Bottom Action Bar
            HStack(spacing: 16) {
                Button {
                    appState.selectedImages.removeAll()
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

                Button {
                    selectFilesFromFinder()
                } label: {
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

    private func imageGridItem(_ item: ImageItem) -> some View {
        GeometryReader { geo in
            Group {
                if let nsImage = item.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { previewItem = item }
            }
            .handCursor()
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            // Bottom info bar
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.fileSizeString) · \(item.dimensionsString)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.72)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                )
            }
            // Delete button — top-right corner
            .overlay(alignment: .topTrailing) {
                Button {
                    appState.selectedImages.removeAll(where: { $0.id == item.id })
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .handCursor()
                .padding(6)
            }
        }
        .frame(height: 180)
    }

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text(LanguageManager.shared.string("convert.settings.title"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                // Format Section
                inspectorSection("convert.settings.format") {
                    Picker("", selection: $selectedFormat) {
                        ForEach(ImageFormat.exportCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                // Quality Section
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

                // Scale Section
                inspectorSection("convert.settings.scale") {
                    HStack {
                        Text("convert.settings.enable")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $scaleEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .onChange(of: scaleEnabled) { newValue in
                                if newValue { resizeEnabled = false }
                            }
                    }

                    if scaleEnabled {
                        HStack {
                            Text("convert.settings.scale.amount")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                            Spacer()
                            Picker("", selection: $scaleSelection) {
                                ForEach(scaleOptions, id: \.self) { option in
                                    Text(LocalizedStringKey(option)).tag(option as String)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 100)
                        }
                        .padding(.top, 6)
                    }
                }

                Divider()

                // Resize Section
                inspectorSection("convert.settings.resize") {
                    HStack {
                        Text("convert.settings.enable")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $resizeEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .onChange(of: resizeEnabled) { newValue in
                                if newValue { scaleEnabled = false }
                            }
                    }

                    if resizeEnabled {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("convert.settings.width")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                TextField("px", text: $customWidth)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("convert.settings.height")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                TextField("px", text: $customHeight)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                Divider()

                // Metadata Section
                inspectorSection("meta.info") {
                    HStack {
                        Text("convert.settings.enable")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $metadataEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                Divider()

                // Target Folder Section
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

                // Convert Button
                VStack {
                    Button {
                        isProcessing = true
                        Task { await performConversion() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text(LocalizedStringKey("video.processing"))
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("convert.settings.convertButton")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.targetFolder == nil || appState.selectedImages.isEmpty || isProcessing)
                }
                .padding(16)
            }
        }
        .background(Material.bar)
    }

    // MARK: - Preview Offset Clamp
    // Limits pan so the image never scrolls beyond its own edges.
    private func clampedOffset(_ offset: CGSize) -> CGSize {
        let maxX = max(0, previewImageFrame.width * (previewZoom - 1) / 2)
        let maxY = max(0, previewImageFrame.height * (previewZoom - 1) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }

    // MARK: - Conversion Logic (UI only — backend TBD)
    private func performConversion() async {
        guard appState.targetFolder != nil else { return }
        appState.processingMenuItem = .convertImage
        defer {
            isProcessing = false
            appState.processingMenuItem = nil
        }
        try? await Task.sleep(for: .milliseconds(120))
        await MainActor.run {
            showConversionStubAlert = true
        }
    }

    // MARK: - Helper Methods
    private static let supportedImageTypes: [UTType] = {
        let optionalTypes: [UTType?] = [
            .image, .rawImage, .svg, .pdf,
            UTType("com.adobe.photoshop-image"),
            UTType("com.adobe.illustrator.ai-image"),
        ]
        return optionalTypes.compactMap { $0 }
    }()

    private static let videoTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie, .mpeg, .avi]

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            let isVideo = Self.videoTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
                       || provider.registeredTypeIdentifiers.contains { id in id.contains("mpeg") || id.contains("mp4") || id.contains("video") || id.contains("movie") }
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
                        self.loadImages(from: [url])
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

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpeg", "mpg", "3gp"]

    private func loadImages(from urls: [URL]) {
        let existing = Set(appState.selectedImages.map(\.url))
        let newURLs = urls.filter {
            !existing.contains($0) &&
            !Self.videoExtensions.contains($0.pathExtension.lowercased())
        }
        guard !newURLs.isEmpty else { return }

        Task.detached(priority: .userInitiated) {
            var built: [ImageItem] = []
            for url in newURLs {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }

                var fileSizeStr = "0 KB"
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    fileSizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                }

                var dimStr = ""
                var nsImage: NSImage? = nil
                let ext0 = url.pathExtension.lowercased()

                if ext0 == "svg" || ext0 == "ai" || ext0 == "pdf" {
                    // Use QuickLook for vector formats — same quality as Finder previews
                    let request = QLThumbnailGenerator.Request(
                        fileAt: url,
                        size: CGSize(width: 720, height: 720),
                        scale: 2.0,
                        representationTypes: .all
                    )
                    if let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                        nsImage = thumb.nsImage
                        let sz = thumb.nsImage.size
                        dimStr = sz.width > 0 ? "- \(Int(sz.width))x\(Int(sz.height))" : ""
                    }
                } else {
                    let ext2 = url.pathExtension.lowercased()
                    var srcOpts: [CFString: Any] = [:]
                    if ext2 == "jfif" || ext2 == "jpe" {
                        srcOpts[kCGImageSourceTypeIdentifierHint] = "public.jpeg" as CFString
                    }
                    if let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts as CFDictionary) {
                        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                           let w = props[kCGImagePropertyPixelWidth] as? Int,
                           let h = props[kCGImagePropertyPixelHeight] as? Int {
                            dimStr = "- \(w)x\(h)"
                        }
                        let thumbOpts: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 720,
                            kCGImageSourceCreateThumbnailWithTransform: true
                        ]
                        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) {
                            nsImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        }
                    }
                }

                built.append(ImageItem(url: url, image: nsImage, fileSizeString: fileSizeStr, dimensionsString: dimStr))
            }

            let items = built
            await MainActor.run {
                self.appState.selectedImages.append(contentsOf: items)
            }
        }
    }
}

// MARK: - Image Format
enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, webp, avif, bmp, heif, tiff, gif

    var id: String { rawValue }

    // Çıkış formatı olarak kullanıcıya gösterilen formatlar (BMP, HEIF, TIFF hariç)
    static var exportCases: [ImageFormat] { [.png, .jpeg, .webp, .avif, .gif] }

    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .bmp: return "BMP"
        case .heif: return "HEIF"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        }
    }
}

#Preview {
    ConvertImageView(columnVisibility: .constant(.all))
        .environmentObject(GlobalAppState())
        .frame(width: 800, height: 500)
}
