//
//  VideoConvertView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 6.03.2026.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit

struct VideoConvertView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var selectedFormat: VideoFormat = .mp4
    @State private var quality: Double = 8

    // Advanced Settings
    @State private var fpsEnabled: Bool = false
    @State private var scaleEnabled: Bool = false
    @State private var removeAudio: Bool = false
    @State private var metadataEnabled: Bool = true

    @State private var selectedFPS: FPSLimit = .original
    @State private var selectedScale: ResolutionScale = .original

    @EnvironmentObject var appState: GlobalAppState
    @State private var previewItem: VideoItem? = nil
    @State private var previewPlayer: AVPlayer? = nil
    @State private var isDropTargeted = false
    @State private var isWrongTypeDrop = false
    @State private var wrongTypeTask: Task<Void, Never>? = nil
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var currentError: Error? = nil
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentProcessingIndex: Int = 0
    @State private var totalProcessingCount: Int = 0

    @EnvironmentObject var processor: VideoProcessor
    @EnvironmentObject var windowState: WindowStateObserver

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
        .alert(LocalizedStringKey("alert.success.title"), isPresented: $showSuccessAlert) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
            if let folderURL = appState.targetFolder {
                Button(LocalizedStringKey("alert.openFolder")) {
                    NSWorkspace.shared.open(folderURL)
                }
            }
        } message: {
            if let path = appState.targetFolder?.path {
                Text(String(format: NSLocalizedString("alert.success.message.video", comment: ""), path))
            }
        }
        .alert(LocalizedStringKey("alert.error.title"), isPresented: $showErrorAlert, presenting: currentError) { _ in
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
        } message: { error in
            Text(error.localizedDescription)
        }
        .onChange(of: previewItem) { item in
            previewPlayer?.pause()
            previewPlayer = nil
            if let item {
                let playURL = item.playbackURL ?? item.url
                _ = playURL.startAccessingSecurityScopedResource()
                previewPlayer = AVPlayer(url: playURL)
                previewPlayer?.play()
            }
        }
    }

    // MARK: - Inline Preview
    private var inlinePreview: some View {
        VStack(spacing: 0) {
            // Info bar
            HStack(spacing: 12) {
                Image(systemName: "video")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                if let item = previewItem {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text([item.fileSizeString, item.durationString, item.resolutionString, item.fpsString].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        previewItem = nil
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

            // Video canvas — NSViewRepresentable ile AVPlayerView
            if let player = previewPlayer {
                AVPlayerViewRepresentable(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(previewItem?.id)
            }
        }
    }

    // MARK: - Main Content Area
    @ViewBuilder
    private var mainContentArea: some View {
        if appState.selectedVideos.isEmpty {
            emptyDropZone
        } else {
            videoGrid
        }
    }

    private var emptyDropZone: some View {
        Button(action: selectFilesFromFinder) {
            VStack(spacing: 12) {
                Image(systemName: isWrongTypeDrop ? "exclamationmark.triangle" : "video.badge.plus")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(isWrongTypeDrop ? Color.red.opacity(0.7) : Color.secondary.opacity(0.6))

                Text(isWrongTypeDrop ? LocalizedStringKey("convert.wrongType.video") : LocalizedStringKey("video.drop.title"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isWrongTypeDrop ? Color.red.opacity(0.8) : Color.primary)

                Text("video.drop.subtitle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .opacity(isWrongTypeDrop ? 0 : 1)

                Text(LocalizedStringKey("video.drop.formats"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(isWrongTypeDrop ? 0 : 1)
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

    private var videoGrid: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    let columnCount = max(2, Int(geo.size.width / 200))
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(appState.selectedVideos) { item in
                            videoGridItem(item)
                        }
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                return handleDrop(providers)
            }
            .overlay {
                if isWrongTypeDrop {
                    wrongTypeOverlay(message: LocalizedStringKey("convert.wrongType.video"))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isWrongTypeDrop)

            Divider()

            // Bottom Action Bar
            HStack(spacing: 16) {
                Button {
                    appState.selectedVideos.removeAll()
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

    private func videoGridItem(_ item: VideoItem) -> some View {
        VStack(spacing: 0) {
            // Thumbnail — 16:9
            GeometryReader { geo in
                Group {
                    if let nsImage = item.thumbnail {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.secondary.opacity(0.6))
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                // Duration badge
                .overlay(alignment: .topLeading) {
                    Text(item.durationString)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
                // Delete button
                .overlay(alignment: .topTrailing) {
                    Button {
                        appState.selectedVideos.removeAll(where: { $0.id == item.id })
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .padding(6)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            // Info bar
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 0) {
                    Text(item.fileSizeString)
                        .foregroundStyle(Color.secondary)
                    if let res = item.resolutionString {
                        Text(" · \(res)")
                            .foregroundStyle(Color.secondary)
                    }
                    if let fps = item.fpsString {
                        Text(" · \(fps)")
                            .foregroundStyle(Color.secondary)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)

                if item.isCompleted, let saved = item.savedSizeString {
                    Text(saved)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { previewItem = item }
        }
        .handCursor()
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
                inspectorSection("video.settings.format") {
                    Picker("", selection: $selectedFormat) {
                        ForEach(VideoFormat.allCases) { format in
                            Text(format.displayName).tag(format)
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

                // Advanced Settings (FPS, Resolution Scale, Audio, Metadata)
                inspectorSection("video.settings.fps") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("convert.settings.enable")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $fpsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        if fpsEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                Picker("", selection: $selectedFPS) {
                                    ForEach(FPSLimit.allCases) { fps in
                                        Text(fps.title).tag(fps)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()

                                Text(LocalizedStringKey("video.settings.fps.desc"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                Divider()

                inspectorSection("video.settings.resize") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("convert.settings.enable")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $scaleEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        if scaleEnabled {
                            Picker("", selection: $selectedScale) {
                                ForEach(ResolutionScale.allCases) { scale in
                                    Text(scale.title).tag(scale)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .padding(.top, 4)
                        }
                    }
                }

                Divider()

                inspectorSection("video.settings.audio") {
                    HStack {
                        Text("video.settings.audio.remove")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $removeAudio)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                Divider()

                inspectorSection("video.settings.metadata") {
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
                            pickFolder { url in
    appState.handleFolderSelected(url)
    appState.targetFolder = url
}
                        }
                        .controlSize(.small)
                    }
                }

                Divider()

                // Convert Button & Progress
                VStack(spacing: 12) {
                    if processor.isProcessing {
                        ProgressView(value: processor.progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 4)

                        Text("%\(Int(processor.progress * 100)) - \(currentProcessingIndex)/\(totalProcessingCount)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            performVideoConversion()
                        } label: {
                            HStack {
                                if processor.isProcessing {
                                    ProgressView().controlSize(.small)
                                    Text(LocalizedStringKey("video.processing"))
                                } else {
                                    Image(systemName: "video.fill")
                                    Text("convert.settings.convertButton")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(appState.targetFolder == nil || appState.selectedVideos.isEmpty || processor.isProcessing)

                        if processor.isProcessing {
                            Button {
                                appState.videoConversionTask?.cancel()
                            } label: {
                                Text(LocalizedStringKey("video.cancel"))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Material.bar)
    }

    // MARK: - Core Conversion Trigger
    private func performVideoConversion() {
        guard let folder = appState.targetFolder else { return }

        processor.isProcessing = true
        processor.progress = 0

        // Reset old statuses
        for i in 0..<appState.selectedVideos.count {
            appState.selectedVideos[i].isCompleted = false
            appState.selectedVideos[i].savedSizeString = nil
            appState.selectedVideos[i].convertedSizeString = nil
        }

        totalProcessingCount = appState.selectedVideos.count
        currentProcessingIndex = 0

        appState.processingMenuItem = .videoConvert
        appState.videoConversionTask = Task {
            do {
                for (index, video) in appState.selectedVideos.enumerated() {
                    if Task.isCancelled { break }

                    await MainActor.run {
                        currentProcessingIndex = index + 1
                    }

                    let fileName = video.url.deletingPathExtension().lastPathComponent
                    let ext = selectedFormat.rawValue

                    // Use counter to avoid overwriting existing files
                    var outputURL = folder.appendingPathComponent("\(fileName).\(ext)")
                    var counter = 1
                    while FileManager.default.fileExists(atPath: outputURL.path) {
                        outputURL = folder.appendingPathComponent("\(fileName)_\(counter).\(ext)")
                        counter += 1
                    }

                    let settings = VideoConversionSettings(
                        fpsLimit: fpsEnabled ? selectedFPS : .original,
                        resolutionScale: scaleEnabled ? selectedScale : .original,
                        removeAudio: removeAudio,
                        keepMetadata: metadataEnabled
                    )

                    let originalSize = (try? FileManager.default.attributesOfItem(atPath: video.url.path)[.size] as? Int64) ?? 0

                    try await processor.convert(
                        inputURL: video.url,
                        outputURL: outputURL,
                        format: selectedFormat,
                        quality: quality,
                        settings: settings,
                        manageProcessingState: false
                    )

                    let newSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
                    var savedStr: String? = nil

                    if originalSize > 0, newSize > 0 {
                        let formatter = ByteCountFormatter()
                        formatter.allowedUnits = [.useAll]
                        formatter.countStyle = .file

                        if originalSize > newSize {
                            let savedBytes = originalSize - newSize
                            savedStr = "\(formatter.string(fromByteCount: savedBytes)) \(NSLocalizedString("video.saved.gain", comment: ""))"
                        } else {
                            let extraBytes = newSize - originalSize
                            savedStr = "+\(formatter.string(fromByteCount: extraBytes)) \(NSLocalizedString("video.saved.increased", comment: ""))"
                        }
                    }

                    let newSizeStr = newSize > 0 ? ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file) : nil

                    await MainActor.run {
                        appState.selectedVideos[index].isCompleted = true
                        appState.selectedVideos[index].savedSizeString = savedStr
                        appState.selectedVideos[index].convertedSizeString = newSizeStr
                    }
                }
                if !Task.isCancelled {
                    CometAnalytics.shared.trackEvent(
                        page: "videoConvert",
                        eventType: .videoConverted,
                        metadata: ["count": appState.selectedVideos.count, "format": selectedFormat.rawValue]
                    )
                    showSuccessAlert = true
                }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) {
                    currentError = error
                    showErrorAlert = true
                }
            }
            processor.isProcessing = false
            appState.processingMenuItem = nil
            appState.videoConversionTask = nil
        }
    }

    // MARK: - Helper Methods
    private static let imageTypes: [UTType] = [.image, .png, .jpeg, .webP, .heic, .bmp, .tiff, .gif, .svg, .rawImage]

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            let isImage = Self.imageTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
                       || provider.registeredTypeIdentifiers.contains { id in id.contains("image") || id.contains("png") || id.contains("jpeg") || id.contains("webp") || id.contains("heic") || id.contains("tiff") || id.contains("gif") }

            if isImage {
                wrongTypeTask?.cancel()
                isWrongTypeDrop = true
                wrongTypeTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { isWrongTypeDrop = false }
                }
                handled = true
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = {
                        if let u = item as? URL { return u }
                        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                        return nil
                    }()
                    if let url {
                        self.loadVideos(from: [url])
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
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie]

        if panel.runModal() == .OK {
            loadVideos(from: panel.urls)
        }
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "heif", "bmp", "tiff", "tif", "gif", "svg", "avif", "raw", "cr2", "nef"]

    private func loadVideos(from urls: [URL]) {
        for url in urls {
            if appState.selectedVideos.contains(where: { $0.url == url }) { continue }
            if Self.imageExtensions.contains(url.pathExtension.lowercased()) { continue }

            let ext = url.pathExtension.lowercased()
            let needsFFmpeg = VideoItem.avUnsupportedExtensions.contains(ext)

            _ = url.startAccessingSecurityScopedResource()

            Task {
                var fileSizeStr = "0 KB"
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    let formatter = ByteCountFormatter()
                    formatter.allowedUnits = [.useAll]
                    formatter.countStyle = .file
                    fileSizeStr = formatter.string(fromByteCount: size)
                }

                var durationStr = "00:00"
                var resStr: String? = nil
                var fpsStr: String? = nil
                var thumbnail: NSImage? = nil
                var playbackURL: URL? = nil

                if needsFFmpeg {
                    // ffprobe ile metadata al
                    if let meta = await probeVideoWithFFmpeg(url: url) {
                        durationStr = meta.durationStr
                        resStr = meta.resolution
                        fpsStr = meta.fps
                    }
                    // ffmpeg ile thumbnail çek (1. frame PNG)
                    thumbnail = await extractThumbnailWithFFmpeg(url: url)
                    // Geçici MP4 oluştur (preview için)
                    playbackURL = await makePreviewMP4WithFFmpeg(url: url)
                } else {
                    let asset = AVURLAsset(url: url)
                    let duration = try? await asset.load(.duration)
                    let durationSecs = CMTimeGetSeconds(duration ?? .zero)
                    durationStr = String(format: "%02d:%02d", Int(durationSecs) / 60, Int(durationSecs) % 60)

                    if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                        if let s = try? await videoTrack.load(.naturalSize) {
                            resStr = "\(Int(s.width))x\(Int(s.height))"
                        }
                        if let f = try? await videoTrack.load(.nominalFrameRate) {
                            fpsStr = "\(Int(f)) FPS"
                        }
                    }

                    // AVFoundation thumbnail
                    let imageGenerator = AVAssetImageGenerator(asset: asset)
                    imageGenerator.appliesPreferredTrackTransform = true
                    imageGenerator.maximumSize = CGSize(width: 400, height: 400)
                    let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                    if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                        thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    }
                }

                var item = VideoItem(url: url, fileSizeString: fileSizeStr, durationString: durationStr, resolutionString: resStr, fpsString: fpsStr)
                item.thumbnail = thumbnail
                item.playbackURL = playbackURL

                await MainActor.run {
                    appState.selectedVideos.append(item)
                }
            }
        }
    }

    // MARK: - FFmpeg Helpers

    private struct FFprobeResult {
        let durationStr: String
        let resolution: String?
        let fps: String?
    }

    private func probeVideoWithFFmpeg(url: URL) async -> FFprobeResult? {
        guard let ffmpegURL = FFmpegBridge.ffmpegURL() else { return nil }
        let ffprobeURL = ffmpegURL.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.fileExists(atPath: ffprobeURL.path) else { return nil }

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = ffprobeURL
            process.arguments = [
                "-v", "quiet",
                "-print_format", "json",
                "-show_streams", "-show_format",
                url.path
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var durationSecs: Double = 0
            if let format = json["format"] as? [String: Any],
               let durStr = format["duration"] as? String,
               let dur = Double(durStr) {
                durationSecs = dur
            }
            let durationStr = String(format: "%02d:%02d", Int(durationSecs) / 60, Int(durationSecs) % 60)

            var resolution: String? = nil
            var fps: String? = nil
            if let streams = json["streams"] as? [[String: Any]] {
                for stream in streams {
                    if let codecType = stream["codec_type"] as? String, codecType == "video" {
                        if let w = stream["width"] as? Int, let h = stream["height"] as? Int {
                            resolution = "\(w)x\(h)"
                        }
                        if let rFrameRate = stream["r_frame_rate"] as? String {
                            let parts = rFrameRate.split(separator: "/")
                            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                                let fpsVal = num / den
                                fps = "\(Int(fpsVal.rounded())) FPS"
                            }
                        }
                        break
                    }
                }
            }
            return FFprobeResult(durationStr: durationStr, resolution: resolution, fps: fps)
        }.value
    }

    private func extractThumbnailWithFFmpeg(url: URL) async -> NSImage? {
        guard let ffmpegURL = FFmpegBridge.ffmpegURL() else { return nil }
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("thumb_\(UUID().uuidString).png")

        // Data döndür, NSImage'ı Task dışında oluştur (Sendable uyarısını önler)
        let data: Data? = await Task.detached(priority: .utility) { () -> Data? in
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = [
                "-y",
                "-i", url.path,
                "-vframes", "1",
                "-vf", "scale=400:-1",
                "-f", "image2",
                tmpURL.path
            ]
            process.standardError = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            defer { try? FileManager.default.removeItem(at: tmpURL) }
            guard process.terminationStatus == 0 else { return nil }
            return try? Data(contentsOf: tmpURL)
        }.value
        return data.flatMap { NSImage(data: $0) }
    }

    private func makePreviewMP4WithFFmpeg(url: URL) async -> URL? {
        guard let ffmpegURL = FFmpegBridge.ffmpegURL() else { return nil }
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview_\(UUID().uuidString).mp4")

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = [
                "-y", "-i", url.path,
                "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
                "-c:a", "aac", "-b:a", "96k",
                "-movflags", "+faststart",
                tmpURL.path
            ]
            process.standardError = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            return tmpURL
        }.value
    }
}

enum VideoFormat: String, CaseIterable, Identifiable {
    case mp4
    case mov
    case mkv
    case avi
    case webm
    case m4v
    case mpeg
    case threeGP = "3gp"
    case flv
    case wmv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .threeGP: return "3GP"
        default: return rawValue.uppercased()
        }
    }

    /// ffmpeg muxer adı
    var ffmpegMuxer: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .mkv: return "matroska"
        case .avi: return "avi"
        case .webm: return "webm"
        case .m4v: return "mp4"
        case .mpeg: return "mpeg"
        case .threeGP: return "3gp"
        case .flv: return "flv"
        case .wmv: return "asf"
        }
    }

    /// Çıktı dosya uzantısı
    var fileExtension: String { rawValue }
}

enum FPSLimit: String, CaseIterable, Identifiable {
    case original = "original"
    case fps60 = "fps60"
    case fps30 = "fps30"
    case fps24 = "fps24"

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .original: return "video.fps.original"
        case .fps60: return "video.fps.60"
        case .fps30: return "video.fps.30"
        case .fps24: return "video.fps.24"
        }
    }

    var value: Double? {
        switch self {
        case .original: return nil
        case .fps60: return 60.0
        case .fps30: return 30.0
        case .fps24: return 24.0
        }
    }
}

enum ResolutionScale: String, CaseIterable, Identifiable {
    case original = "original"
    case scale75 = "scale75"
    case scale50 = "scale50"
    case scale25 = "scale25"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .original: return "video.resolution.original"
        case .scale75: return "video.resolution.75"
        case .scale50: return "video.resolution.50"
        case .scale25: return "video.resolution.25"
        }
    }

    var multiplier: Double {
        switch self {
        case .original: return 1.0
        case .scale75: return 0.75
        case .scale50: return 0.50
        case .scale25: return 0.25
        }
    }
}

struct VideoConversionSettings {
    let fpsLimit: FPSLimit
    let resolutionScale: ResolutionScale
    let removeAudio: Bool
    let keepMetadata: Bool
}


// MARK: - AVPlayerView NSViewRepresentable (VideoPlayer SwiftUI yerine — macOS beta uyumlu)
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

#Preview {
    VideoConvertView(columnVisibility: .constant(.all))
        .environmentObject(GlobalAppState())
        .frame(width: 800, height: 500)
}
