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
    @State private var audioEnabled: Bool = false
    @State private var metadataEnabled: Bool = true

    @State private var selectedFPS: FPSLimit = .original
    @State private var selectedScale: ResolutionScale = .original

    @EnvironmentObject var appState: GlobalAppState
    @State private var previewItem: VideoItem? = nil
    @State private var isDropTargeted = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var currentError: Error? = nil
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentProcessingIndex: Int = 0
    @State private var totalProcessingCount: Int = 0

    @StateObject private var processor = VideoProcessor()

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Main Area
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // MARK: - Right Inspector Panel
            inspectorPanel
                .frame(width: 260)
        }
        .ignoresSafeArea(edges: columnVisibility == .detailOnly ? [] : .top)
        .overlay {
            // ZStack is always present; allowsHitTesting disables interaction immediately on dismiss,
            // preventing the macOS SwiftUI hit-test lingering bug after transition animations.
            ZStack {
                if let preview = previewItem {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                previewItem = nil
                            }
                        }

                    InlineVideoPlayer(url: preview.url)
                        .frame(minWidth: 600, minHeight: 400)
                        .padding(60)
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)

                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    previewItem = nil
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(Circle().fill(Color.white.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                            .handCursor()
                            .padding(.top, 20)
                            .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(previewItem != nil)
            .animation(.easeInOut(duration: 0.2), value: previewItem != nil)
            .zIndex(100)
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
                Text(String(format: NSLocalizedString("alert.success.message.video", comment: ""), path))
            }
        }
        .alert(LocalizedStringKey("alert.error.title"), isPresented: $showErrorAlert, presenting: currentError) { _ in
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
        } message: { error in
            Text(error.localizedDescription)
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
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color.secondary.opacity(0.6))

                Text("video.drop.title")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)

                Text("video.drop.subtitle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
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
                    isDropTargeted
                        ? Color.accentColor.opacity(0.5)
                        : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .padding(24)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            return handleDrop(providers)
        }
    }

    private var videoGrid: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)], spacing: 20) {
                    ForEach(appState.selectedVideos) { item in
                        videoGridItem(item)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                return handleDrop(providers)
            }

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
        VStack(alignment: .leading, spacing: 8) {
            // Video Box
            GeometryReader { geo in
                Group {
                    if let nsImage = item.thumbnail {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.secondary)
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        previewItem = item
                    }
                }
                .handCursor()
                .frame(width: geo.size.width, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    Button {
                        appState.selectedVideos.removeAll(where: { $0.id == item.id })
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .padding(6)
                }
            }
            .frame(height: 110)

            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(item.fileSizeString) • \(item.durationString)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)

                if let res = item.resolutionString, let fps = item.fpsString {
                    Text("\(res) • \(fps)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }

                if let savedStr = item.savedSizeString {
                    Text(savedStr)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.green)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("convert.settings.title")
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
                            Text(format.rawValue.uppercased()).tag(format)
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
                        Toggle("", isOn: $audioEnabled)
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
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK, let url = panel.url {
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
                }
                .padding(16)
            }
        }
        .background(Material.bar)
    }

    // MARK: - Core Conversion Trigger
    private func performVideoConversion() {
        guard let folder = appState.targetFolder else { return }

        // Reset old statuses
        for i in 0..<appState.selectedVideos.count {
            appState.selectedVideos[i].isCompleted = false
            appState.selectedVideos[i].savedSizeString = nil
        }

        totalProcessingCount = appState.selectedVideos.count
        currentProcessingIndex = 0

        Task {
            do {
                for (index, video) in appState.selectedVideos.enumerated() {
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
                        removeAudio: !audioEnabled,
                        keepMetadata: metadataEnabled
                    )

                    let originalSize = (try? FileManager.default.attributesOfItem(atPath: video.url.path)[.size] as? Int64) ?? 0

                    try await processor.convert(
                        inputURL: video.url,
                        outputURL: outputURL,
                        format: selectedFormat,
                        quality: quality,
                        settings: settings
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

                    await MainActor.run {
                        appState.selectedVideos[index].isCompleted = true
                        appState.selectedVideos[index].savedSizeString = savedStr
                    }
                }
                showSuccessAlert = true
            } catch {
                currentError = error
                showErrorAlert = true
            }
        }
    }

    // MARK: - Helper Methods
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.loadVideos(from: [url])
                        }
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

    private func loadVideos(from urls: [URL]) {
        for url in urls {
            if appState.selectedVideos.contains(where: { $0.url == url }) { continue }

            let asset = AVAsset(url: url)

            Task {
                let duration = try? await asset.load(.duration)
                let durationSecs = CMTimeGetSeconds(duration ?? .zero)
                let durationStr = String(format: "%02d:%02d", Int(durationSecs) / 60, Int(durationSecs) % 60)

                var fileSizeStr = "0 KB"
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    let formatter = ByteCountFormatter()
                    formatter.allowedUnits = [.useAll]
                    formatter.countStyle = .file
                    fileSizeStr = formatter.string(fromByteCount: size)
                }

                // Fetch Resolution and FPS metadata
                var resStr: String? = nil
                var fpsStr: String? = nil

                if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                    let size = try? await videoTrack.load(.naturalSize)
                    let fps = try? await videoTrack.load(.nominalFrameRate)

                    if let size = size {
                        resStr = "\(Int(size.width))x\(Int(size.height))"
                    }
                    if let fps = fps {
                        fpsStr = "\(Int(fps)) FPS"
                    }
                }

                let item = VideoItem(url: url, fileSizeString: fileSizeStr, durationString: durationStr, resolutionString: resStr, fpsString: fpsStr)

                await MainActor.run {
                    appState.selectedVideos.append(item)
                }

                // Fetch thumbnail asynchronously
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 400, height: 400)
                let time = CMTime(seconds: 0.0, preferredTimescale: 600)

                if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    await MainActor.run {
                        if let index = appState.selectedVideos.firstIndex(where: { $0.id == item.id }) {
                            appState.selectedVideos[index].thumbnail = nsImage
                        }
                    }
                }
            }
        }
    }
}

enum VideoFormat: String, CaseIterable, Identifiable {
    case mp4, mov, mkv, avi
    var id: String { rawValue }
}

enum FPSLimit: String, CaseIterable, Identifiable {
    case original = "Orijinal"
    case fps60 = "60 FPS"
    case fps30 = "30 FPS"
    case fps24 = "24 FPS"

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .original: return "convert.scale.original"
        case .fps60: return "60 FPS"
        case .fps30: return "30 FPS"
        case .fps24: return "24 FPS"
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
    case original = "Orijinal"
    case scale75 = "%75 Boyut"
    case scale50 = "%50 Boyut"
    case scale25 = "%25 Boyut (Düşük Kalite)"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .original: return "convert.scale.original"
        case .scale75: return "%75"
        case .scale50: return "%50"
        case .scale25: return "%25"
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

// MARK: - InlineVideoPlayer
// Custom video player with always-visible controls (controlsStyle = .none + SwiftUI toolbar)
struct InlineVideoPlayer: View {
    let url: URL

    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var timeObserver: Any? = nil

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayerView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Always-visible toolbar
            HStack(spacing: 12) {
                Button {
                    if isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Slider(value: $currentTime, in: 0...max(duration, 1)) { editing in
                    if !editing {
                        let target = CMTime(seconds: currentTime, preferredTimescale: 600)
                        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
                .accentColor(.white)

                Text(formatTime(currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.7))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player.pause()
            if let obs = timeObserver {
                player.removeTimeObserver(obs)
            }
        }
    }

    private func setupPlayer() {
        // Load duration
        Task {
            if let item = player.currentItem {
                let dur = try? await item.asset.load(.duration)
                await MainActor.run {
                    duration = CMTimeGetSeconds(dur ?? .zero)
                    if duration.isNaN || duration <= 0 { duration = 1 }
                }
            }
        }

        // Time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }

        // Auto-detect play state
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            isPlaying = false
            currentTime = 0
            player.seek(to: .zero)
        }

        player.play()
        isPlaying = true
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// NSViewRepresentable wrapper for AVPlayerLayer-based playback (no controls chrome)
private struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class PlayerLayerView: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

#Preview {
    VideoConvertView(columnVisibility: .constant(.all))
        .environmentObject(GlobalAppState())
        .frame(width: 800, height: 500)
}
