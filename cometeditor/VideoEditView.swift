import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

// MARK: - VideoEditView

struct VideoEditView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var windowState: WindowStateObserver
    @Environment(\.colorScheme) private var colorScheme

    // Playback (ephemeral)
    @State private var player: AVPlayer? = nil
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var playerDuration: Double = 0
    @State private var timeObserverToken: Any? = nil

    // Trim mode
    @State private var trimmingClipID: UUID? = nil

    // Timeline auto-advance
    @State private var pendingAutoPlay = false
    @State private var pendingSeekTime: Double? = nil

    // Image clip timer
    @State private var imageTimer: Foundation.Timer? = nil

    // Export (ephemeral)
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var showSuccess = false
    @State private var showError = false
    @State private var exportError: String = ""
    @State private var exportTask: Task<Void, Never>? = nil

    // Drop
    @State private var isDropTargeted = false

    private var clips: [VideoEditClip] {
        get { appState.videoEditClips }
        nonmutating set { appState.videoEditClips = newValue }
    }
    private var selectedClipID: UUID? {
        get { appState.videoEditSelectedClipID }
        nonmutating set { appState.videoEditSelectedClipID = newValue }
    }
    private var outputFormat: VideoEditOutputFormat {
        get { appState.videoEditOutputFormat }
        nonmutating set { appState.videoEditOutputFormat = newValue }
    }
    private var outputQuality: Double {
        get { appState.videoEditOutputQuality }
        nonmutating set { appState.videoEditOutputQuality = newValue }
    }
    private var fpsEnabled: Bool {
        get { appState.videoEditFpsEnabled }
        nonmutating set { appState.videoEditFpsEnabled = newValue }
    }
    private var selectedFPS: FPSLimit {
        get { appState.videoEditSelectedFPS }
        nonmutating set { appState.videoEditSelectedFPS = newValue }
    }
    private var scaleEnabled: Bool {
        get { appState.videoEditScaleEnabled }
        nonmutating set { appState.videoEditScaleEnabled = newValue }
    }
    private var selectedScale: ResolutionScale {
        get { appState.videoEditSelectedScale }
        nonmutating set { appState.videoEditSelectedScale = newValue }
    }
    private var removeAudio: Bool {
        get { appState.videoEditRemoveAudio }
        nonmutating set { appState.videoEditRemoveAudio = newValue }
    }
    private var metadataEnabled: Bool {
        get { appState.videoEditMetadataEnabled }
        nonmutating set { appState.videoEditMetadataEnabled = newValue }
    }

    private var selectedClip: VideoEditClip? {
        clips.first { $0.id == selectedClipID }
    }

    private var selectedImageClipIndex: Int? {
        guard let id = selectedClipID,
              let idx = clips.firstIndex(where: { $0.id == id }),
              clips[idx].isImageClip else { return nil }
        return idx
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if clips.isEmpty {
                    emptyDropZone
                } else {
                    VStack(spacing: 0) {
                        previewArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        bottomClipBar
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .onAppear {
            if player == nil, selectedClipID != nil {
                loadPlayer()
            }
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
            if let token = timeObserverToken {
                player?.removeTimeObserver(token)
                timeObserverToken = nil
            }
            player = nil
        }
        .onChange(of: appState.videoEditSelectedClipID) { _ in loadPlayer() }
        .alert(LocalizedStringKey("alert.success.title"), isPresented: $showSuccess) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) {}
            if let folder = appState.targetFolder {
                Button(LocalizedStringKey("alert.openFolder")) { NSWorkspace.shared.open(folder) }
            }
        } message: {
            if let p = appState.targetFolder?.path {
                Text(String(format: NSLocalizedString("alert.success.message.video", comment: ""), p))
            }
        }
        .alert(LocalizedStringKey("alert.error.title"), isPresented: $showError) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) {}
        } message: { Text(exportError) }
    }

    // MARK: - Empty Drop Zone

    private var emptyDropZone: some View {
        Button(action: { pickVideos(insertAt: 0) }) {
            VStack(spacing: 12) {
                Image(systemName: isDropTargeted ? "film.stack.fill" : "scissors")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.6))

                Text(languageManager.string("videoedit.empty.title"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)

                Text(languageManager.string("videoedit.empty.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)

                Text(languageManager.string("videoedit.empty.formats"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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
                    isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .padding(24)
        )
        .onDrop(of: supportedUTTypes, isTargeted: $isDropTargeted) { handleDrop($0, insertAt: 0) }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack {
            Color.black

            if let clip = selectedClip, clip.isImageClip, let img = clip.fullImage ?? clip.thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let player {
                VideoPlayerRepresentable(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(.white)
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if trimmingClipID != nil {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            trimmingClipID = nil
                        }
                    } else {
                        togglePlay()
                    }
                }

            if !isPlaying, player != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                    .allowsHitTesting(false)
            }

            

            VStack {
                Spacer()
                playbackScrubber
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Playback Scrubber

    private var playbackScrubber: some View {
        let totalDur = totalTimelineDuration
        let timelinePos = currentTimelinePosition
        let prog = totalDur > 0 ? min(1, timelinePos / totalDur) : 0.0

        return HStack(spacing: 12) {
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .handCursor()

            Text(fmtTime(timelinePos))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 48, alignment: .trailing)
                .monospacedDigit()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2)).frame(height: 4)
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: max(0, geo.size.width * prog), height: 4)
                    Circle().fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: max(0, geo.size.width * prog - 7))
                }
                .contentShape(Rectangle().inset(by: -8))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = max(0, min(1, v.location.x / geo.size.width))
                        seekToTimeline(f * totalDur)
                    })
            }
            .frame(height: 14)

            Text(fmtTime(totalDur))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 48, alignment: .leading)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Bottom Clip Bar

    private var bottomClipBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { idx, clip in
                        let isTrimming = trimmingClipID == clip.id

                        ClipStripView(
                            clip: clip,
                            index: idx,
                            clipCount: clips.count,
                            isSelected: selectedClipID == clip.id,
                            isTrimming: isTrimming,
                            trimStart: trimStartBinding(for: clip.id),
                            trimEnd: trimEndBinding(for: clip.id),
                            currentTime: selectedClipID == clip.id ? $currentTime : .constant(0),
                            onSelect: {
                                selectedClipID = clip.id
                                if trimmingClipID != clip.id {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        trimmingClipID = clip.id
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation { proxy.scrollTo(clip.id, anchor: .center) }
                                    }
                                }
                            },
                            onConfirmTrim: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    trimmingClipID = nil
                                }
                            },
                            onDelete: { removeClip(clip) },
                            onMoveLeft: idx > 0 ? {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    clips.swapAt(idx, idx - 1)
                                }
                            } : nil,
                            onMoveRight: idx < clips.count - 1 ? {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    clips.swapAt(idx, idx + 1)
                                }
                            } : nil,
                            onInsertAfter: { pickVideos(insertAt: idx + 1) }
                        )
                        .id(clip.id)
                        .onDrop(of: supportedUTTypes, delegate: ClipDropDelegate(
                            insertAt: idx + 1,
                            handleDrop: { handleDrop($0, insertAt: idx + 1) }
                        ))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if trimmingClipID != nil {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    trimmingClipID = nil
                                }
                            }
                        }
                )
            }
            .background(Color(NSColor.windowBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                if trimmingClipID != nil {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        trimmingClipID = nil
                    }
                }
            }
            .onDrop(of: supportedUTTypes, isTargeted: $isDropTargeted) { handleDrop($0, insertAt: clips.count) }
            .onChange(of: appState.videoEditSelectedClipID) { newID in
                guard let id = newID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(languageManager.string("convert.settings.title"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if !clips.isEmpty {
                        Button { pickVideos(insertAt: clips.count) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text(languageManager.string("videoedit.addMore"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                inspectorSection("videoedit.inspector.format") {
                    Picker("", selection: $appState.videoEditOutputFormat) {
                        ForEach(VideoEditOutputFormat.allCases) { f in
                            Text(languageManager.string(f.localizationKey)).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                inspectorSection("videoedit.inspector.quality") {
                    HStack(spacing: 8) {
                        Slider(value: $appState.videoEditOutputQuality, in: 1...10, step: 1)
                        Text("\(Int(outputQuality))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }

                Divider()

                inspectorSection("video.settings.fps") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(languageManager.string("convert.settings.enable"))
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $appState.videoEditFpsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }
                        if appState.videoEditFpsEnabled {
                            Picker("", selection: $appState.videoEditSelectedFPS) {
                                ForEach(FPSLimit.allCases) { fps in
                                    Text(languageManager.string(fps.localizationKey)).tag(fps)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .padding(.top, 4)
                        }
                    }
                }

                Divider()

                inspectorSection("video.settings.resize") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(languageManager.string("convert.settings.enable"))
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $appState.videoEditScaleEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }
                        if appState.videoEditScaleEnabled {
                            Picker("", selection: $appState.videoEditResizeKind) {
                                Text(languageManager.string("videoedit.resize.modePercent")).tag(VideoEditResizeKind.percent)
                                Text(languageManager.string("videoedit.resize.modeCustom")).tag(VideoEditResizeKind.custom)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .padding(.top, 4)

                            if appState.videoEditResizeKind == .percent {
                                Picker("", selection: $appState.videoEditSelectedScale) {
                                    ForEach(ResolutionScale.allCases) { scale in
                                        Text(languageManager.string(scale.localizationKey)).tag(scale)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .padding(.top, 2)
                            } else {
                                HStack(spacing: 6) {
                                    TextField("1920", text: $appState.videoEditCustomWidthText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 72)
                                        .font(.system(size: 12, design: .monospaced))
                                    Text("×")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    TextField("1080", text: $appState.videoEditCustomHeightText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 72)
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .padding(.top, 4)
                                HStack {
                                    Text(languageManager.string("videoedit.resize.autoFill"))
                                        .font(.system(size: 12))
                                    Spacer()
                                    Toggle("", isOn: $appState.videoEditAutoFillCanvas)
                                        .toggleStyle(.switch)
                                        .controlSize(.small)
                                        .labelsHidden()
                                }
                                .padding(.top, 2)
                                Text(languageManager.string("videoedit.resize.autoFillHint"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }

                Divider()

                inspectorSection("video.settings.audio") {
                    HStack {
                        Text(languageManager.string("video.settings.audio.remove"))
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $appState.videoEditRemoveAudio)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                Divider()

                inspectorSection("video.settings.metadata") {
                    HStack {
                        Text(languageManager.string("convert.settings.enable"))
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $appState.videoEditMetadataEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                Divider()

                inspectorSection("videoedit.imageDuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let idx = selectedImageClipIndex {
                            HStack(spacing: 4) {
                                Image(systemName: "photo")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(clips[idx].fileName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            HStack(spacing: 8) {
                                Slider(value: Binding(
                                    get: { clips[idx].imageDuration },
                                    set: { newVal in
                                        clips[idx].imageDuration = newVal
                                        clips[idx].duration = newVal
                                        clips[idx].endTime = newVal
                                        playerDuration = newVal
                                    }
                                ), in: 0.5...60, step: 0.5)
                                Text(String(format: "%.1fs", clips[idx].imageDuration))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        } else {
                            Text(languageManager.string("videoedit.imageDuration.default"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Slider(value: $appState.videoEditImageDuration, in: 0.5...60, step: 0.5)
                                Text(String(format: "%.1fs", appState.videoEditImageDuration))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                        Button {
                            pickImages(insertAt: clips.count)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 11, weight: .medium))
                                Text(languageManager.string("videoedit.addImage"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                inspectorSection("videoedit.inspector.folder") {
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
                            Text(languageManager.string("convert.settings.noFolder"))
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

                        Button {
                            pickFolder { url in
                                appState.handleFolderSelected(url)
                                appState.targetFolder = url
                            }
                        } label: {
                            Text(languageManager.string("convert.settings.chooseFolder"))
                        }
                        .controlSize(.small)
                    }
                }

                Divider()

                VStack(spacing: 12) {
                    if isExporting {
                        ProgressView(value: exportProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 4)

                        Text("\(Int(exportProgress * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }

                    Button {
                        startExport()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView().controlSize(.small)
                                Text(languageManager.string("videoedit.exporting"))
                            } else {
                                Image(systemName: clips.count > 1 ? "film.stack.fill" : "scissors")
                                Text(clips.count > 1
                                     ? languageManager.string("videoedit.export.merge")
                                     : languageManager.string("videoedit.export.trim"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(clips.isEmpty || appState.targetFolder == nil || isExporting)
                }
                .padding(16)
            }
        }
        .background(Material.bar)
    }

    // MARK: - Player

    private func loadPlayer() {
        stopObserver()
        player?.pause(); player = nil
        let wasPlaying = pendingAutoPlay
        if !wasPlaying { isPlaying = false }
        if wasPlaying && trimmingClipID != nil {
            withAnimation(.easeInOut(duration: 0.2)) { trimmingClipID = nil }
        }
        currentTime = 0; playerDuration = 0
        guard let clip = selectedClip else { return }

        if clip.isImageClip {
            playerDuration = clip.imageDuration
            currentTime = 0
            if pendingAutoPlay {
                pendingAutoPlay = false
                startImagePlayback(clip)
            }
            return
        }

        _ = clip.url.startAccessingSecurityScopedResource()
        let p = AVPlayer(url: clip.playbackURL)
        player = p
        let iv = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: iv, queue: .main) { [self] t in
            let s = CMTimeGetSeconds(t)
            currentTime = s
            if let c = selectedClip, s >= c.endTime {
                if let idx = clips.firstIndex(where: { $0.id == selectedClipID }),
                   idx + 1 < clips.count {
                    pendingAutoPlay = true
                    selectedClipID = clips[idx + 1].id
                } else {
                    p.pause(); isPlaying = false
                    if let first = clips.first {
                        selectedClipID = first.id
                    }
                }
            }
        }
        Task {
            if let dur = try? await p.currentItem?.asset.load(.duration) {
                playerDuration = CMTimeGetSeconds(dur)
            }
            if let pending = pendingSeekTime {
                pendingSeekTime = nil
                seekTo(pending)
            } else if let c = selectedClip {
                seekTo(c.startTime)
            }
            if pendingAutoPlay {
                pendingAutoPlay = false
                player?.play()
                isPlaying = true
            }
        }
    }

    private func startImagePlayback(_ clip: VideoEditClip) {
        isPlaying = true
        let clipID = clip.id
        let dur = clip.imageDuration
        let resumeFrom = currentTime
        let startDate = Date()
        imageTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] timer in
            guard selectedClipID == clipID else { timer.invalidate(); return }
            let elapsed = resumeFrom + Date().timeIntervalSince(startDate)
            currentTime = min(elapsed, dur)
            if elapsed >= dur {
                timer.invalidate()
                imageTimer = nil
                if let idx = clips.firstIndex(where: { $0.id == clipID }),
                   idx + 1 < clips.count {
                    pendingAutoPlay = true
                    selectedClipID = clips[idx + 1].id
                } else {
                    isPlaying = false
                    if let first = clips.first { selectedClipID = first.id }
                }
            }
        }
    }

    private func stopObserver() {
        if let t = timeObserverToken { player?.removeTimeObserver(t); timeObserverToken = nil }
        imageTimer?.invalidate(); imageTimer = nil
    }

    private func togglePlay() {
        guard let c = selectedClip else { return }

        if c.isImageClip {
            if isPlaying {
                imageTimer?.invalidate(); imageTimer = nil
                isPlaying = false
            } else {
                if currentTime >= c.imageDuration {
                    currentTime = 0
                }
                startImagePlayback(c)
            }
            return
        }

        guard let p = player else { return }
        if isPlaying { p.pause(); isPlaying = false }
        else {
            if currentTime >= c.endTime {
                if let idx = clips.firstIndex(where: { $0.id == selectedClipID }),
                   idx >= clips.count - 1, let first = clips.first {
                    pendingAutoPlay = true
                    selectedClipID = first.id
                    return
                }
                seekTo(c.startTime)
            }
            p.play(); isPlaying = true
        }
    }

    private func seekTo(_ t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = t
    }

    // MARK: - Timeline helpers

    private func effectiveDuration(_ clip: VideoEditClip) -> Double {
        clip.isImageClip ? clip.imageDuration : clip.trimmedDuration
    }

    private var totalTimelineDuration: Double {
        clips.reduce(0) { $0 + effectiveDuration($1) }
    }

    private var currentTimelinePosition: Double {
        guard let id = selectedClipID, let clip = selectedClip else { return 0 }
        let offset = clipTimelineOffset(for: id)
        if clip.isImageClip { return offset + currentTime }
        let relTime = max(0, currentTime - clip.startTime)
        return offset + relTime
    }

    private func clipTimelineOffset(for clipID: UUID) -> Double {
        var offset: Double = 0
        for clip in clips {
            if clip.id == clipID { return offset }
            offset += effectiveDuration(clip)
        }
        return offset
    }

    private func seekToTimeline(_ position: Double) {
        var remaining = max(0, position)
        for clip in clips {
            let dur = effectiveDuration(clip)
            if remaining <= dur + 0.01 {
                if clip.isImageClip {
                    selectedClipID = clip.id
                } else {
                    let target = clip.startTime + remaining
                    if selectedClipID == clip.id {
                        seekTo(target)
                    } else {
                        pendingSeekTime = target
                        selectedClipID = clip.id
                    }
                }
                return
            }
            remaining -= dur
        }
        if let last = clips.last {
            if selectedClipID != last.id {
                pendingSeekTime = last.endTime
                selectedClipID = last.id
            } else {
                seekTo(last.endTime)
            }
        }
    }

    // MARK: - Clip ops

    private func removeClip(_ clip: VideoEditClip) {
        if let prev = clip.previewURL {
            try? FileManager.default.removeItem(at: prev)
        }
        clips.removeAll { $0.id == clip.id }
        if selectedClipID == clip.id { selectedClipID = clips.first?.id }
        if trimmingClipID == clip.id { trimmingClipID = nil }
    }

    private func trimStartBinding(for id: UUID) -> Binding<Double> {
        Binding(get: { clips.first { $0.id == id }?.startTime ?? 0 },
                set: { v in
                    if let i = clips.firstIndex(where: { $0.id == id }) {
                        clips[i].startTime = v
                        if trimmingClipID == id { seekTo(v) }
                    }
                })
    }

    private func trimEndBinding(for id: UUID) -> Binding<Double> {
        Binding(get: { clips.first { $0.id == id }?.endTime ?? 0 },
                set: { v in
                    if let i = clips.firstIndex(where: { $0.id == id }) {
                        clips[i].endTime = v
                        if trimmingClipID == id { seekTo(v) }
                    }
                })
    }

    // MARK: - File picking / drop

    private var supportedUTTypes: [UTType] { [.fileURL] }

    private let supportedVideoExtensions = Set(["mp4","mov","avi","mkv","webm","flv","wmv","mpeg","mpg","m4v","3gp","ts","mts","m2ts","vob","ogv"])

    private func pickVideos(insertAt index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie,
                                     UTType("public.avi") ?? .movie,
                                     UTType("org.matroska.mkv") ?? .movie,
                                     UTType("org.webmproject.webm") ?? .movie,
                                     UTType("public.mpeg") ?? .movie,
                                     UTType("com.microsoft.windows-media-wmv") ?? .movie,
                                     UTType("public.3gpp") ?? .movie,
                                     UTType("public.flv") ?? .movie,
                                     .item]
        guard panel.runModal() == .OK else { return }
        let filtered = panel.urls.filter { supportedVideoExtensions.contains($0.pathExtension.lowercased()) }
        loadURLs(filtered, insertAt: index)
    }

    private func handleDrop(_ providers: [NSItemProvider], insertAt index: Int) -> Bool {
        let valid = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !valid.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in valid {
                if let url = await loadDropURL(from: provider) {
                    urls.append(url)
                }
            }
            await MainActor.run { loadURLs(urls, insertAt: index) }
        }
        return true
    }

    private func loadDropURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    cont.resume(returning: nil)
                    return
                }
                let ext = url.pathExtension.lowercased()
                let accepted = self.supportedVideoExtensions.contains(ext) || VideoEditClip.supportedImageExtensions.contains(ext)
                cont.resume(returning: accepted ? url : nil)
            }
        }
    }

    private func pickImages(insertAt index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .webP, .heic, .bmp, .tiff]
        guard panel.runModal() == .OK else { return }
        loadURLs(panel.urls, insertAt: index)
    }

    private func loadURLs(_ urls: [URL], insertAt baseIndex: Int) {
        let safe = max(0, min(baseIndex, clips.count))
        let imgDuration = appState.videoEditImageDuration
        Task {
            var loaded: [VideoEditClip] = []
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
                let ext = url.pathExtension.lowercased()
                if VideoEditClip.supportedImageExtensions.contains(ext) {
                    if let c = await VideoEditClip.loadImage(from: url, duration: imgDuration) {
                        loaded.append(c)
                    }
                } else if let c = await VideoEditClip.load(from: url) {
                    loaded.append(c)
                }
            }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    trimmingClipID = nil
                }
                for (i, c) in loaded.enumerated() {
                    clips.insert(c, at: min(safe + i, clips.count))
                }
                if let first = loaded.first {
                    selectedClipID = first.id
                }
            }
        }
    }

    // MARK: - Export

    private func startExport() {
        guard !clips.isEmpty, let folder = appState.targetFolder else { return }
        isExporting = true; exportProgress = 0
        exportTask = Task {
            do {
                if clips.count == 1 { try await exportSingle(clips[0], to: folder) }
                else { try await exportMerged(clips, to: folder) }
                await MainActor.run { isExporting = false; exportProgress = 1; showSuccess = true }
            } catch {
                await MainActor.run { isExporting = false; exportError = error.localizedDescription; showError = true }
            }
        }
    }

    private func exportSingle(_ clip: VideoEditClip, to folder: URL) async throws {
        guard FFmpegBridge.ffmpegURL() != nil else { throw FFmpegError.binaryNotFound }
        let base = clip.url.deletingPathExtension().lastPathComponent + (clip.isImageClip ? "_photo" : "_trimmed")
        let out = uniqueURL(folder: folder, base: base, ext: outputFormat.fileExtension)
        var args: [String]
        if clip.isImageClip {
            args = ["-y", "-loop", "1", "-i", clip.url.path,
                    "-t", String(format: "%.3f", clip.imageDuration)]
            args += buildVideoFilterArgs(for: clip)
            args += ["-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p"]
            args.append("-an")
        } else {
            args = ["-y",
                    "-i", clip.url.path,
                    "-ss", String(format: "%.3f", clip.startTime),
                    "-t", String(format: "%.3f", clip.trimmedDuration)]
            args += buildVideoFilterArgs(for: clip)
            args += outputFormat.codecArgs(quality: outputQuality)
            if removeAudio { args.append("-an") }
        }
        if !metadataEnabled { args += ["-map_metadata", "-1"] }
        args.append(out.path)
        let dur = clip.isImageClip ? clip.imageDuration : clip.trimmedDuration
        try await FFmpegBridge.shared.run(arguments: args, totalDurationSeconds: dur) { p in
            Task { @MainActor in self.exportProgress = p * 0.95 }
        }
    }

    private func exportMerged(_ clips: [VideoEditClip], to folder: URL) async throws {
        guard FFmpegBridge.ffmpegURL() != nil else { throw FFmpegError.binaryNotFound }
        let total = clips.reduce(0) { $0 + ($1.isImageClip ? $1.imageDuration : $1.trimmedDuration) }
        let out = uniqueURL(folder: folder, base: "merged_video", ext: outputFormat.fileExtension)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("comet_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var parts: [URL] = []
        for (i, clip) in clips.enumerated() {
            let clipVF = buildMergeVideoFilter(for: clip)
            let p = tmp.appendingPathComponent("p\(i).mp4")
            var args: [String]
            let clipDur: Double
            if clip.isImageClip {
                clipDur = clip.imageDuration
                args = ["-y", "-loop", "1", "-i", clip.url.path,
                        "-t", String(format: "%.3f", clipDur),
                        "-vf", clipVF,
                        "-c:v", "libx264", "-crf", "18", "-preset", "fast",
                        "-pix_fmt", "yuv420p", "-an"]
            } else {
                clipDur = clip.trimmedDuration
                args = ["-y",
                        "-i", clip.url.path,
                        "-ss", String(format: "%.3f", clip.startTime),
                        "-t", String(format: "%.3f", clipDur),
                        "-vf", clipVF,
                        "-c:v", "libx264", "-crf", "18", "-preset", "fast",
                        "-pix_fmt", "yuv420p"]
                if removeAudio {
                    args.append("-an")
                } else {
                    args += ["-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2"]
                }
            }
            if !metadataEnabled { args += ["-map_metadata", "-1"] }
            args += ["-avoid_negative_ts", "make_zero", p.path]
            let s = Double(i) / Double(clips.count), e = Double(i+1) / Double(clips.count)
            try await FFmpegBridge.shared.run(arguments: args, totalDurationSeconds: clipDur) { p in
                Task { @MainActor in self.exportProgress = (s + p * (e - s)) * 0.85 }
            }
            parts.append(p)
        }
        let list = tmp.appendingPathComponent("list.txt")
        try parts.map { "file '\($0.path)'" }.joined(separator: "\n")
            .write(to: list, atomically: true, encoding: .utf8)
        var concat: [String] = ["-y", "-f", "concat", "-safe", "0", "-i", list.path]
        concat += outputFormat.codecArgs(quality: outputQuality); concat.append(out.path)
        try await FFmpegBridge.shared.run(arguments: concat, totalDurationSeconds: total) { p in
            Task { @MainActor in self.exportProgress = 0.85 + p * 0.15 }
        }
    }

    private func parsedCustomExportSize() -> (Int, Int)? {
        let twRaw = Int(appState.videoEditCustomWidthText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let thRaw = Int(appState.videoEditCustomHeightText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let tw = twRaw & ~1
        let th = thRaw & ~1
        guard tw >= 32, th >= 32, tw <= 8192, th <= 8192 else { return nil }
        return (tw, th)
    }

    /// Özel çözünürlük + otomatik kapla: kaynak büyükse sığdır (letterbox), küçükse doldur (zoom + merkez kırpma).
    private static func customCanvasVideoFilter(
        targetW: Int, targetH: Int,
        autoFill: Bool,
        srcW: Int, srcH: Int
    ) -> String {
        let tW = targetW
        let tH = targetH
        let containPad = "scale=\(tW):\(tH):force_original_aspect_ratio=decrease,pad=\(tW):\(tH):(ow-iw)/2:(oh-ih)/2:black"
        guard srcW >= 2, srcH >= 2 else { return containPad }
        if autoFill {
            if srcW >= tW || srcH >= tH {
                return containPad
            }
            return "scale=\(tW):\(tH):force_original_aspect_ratio=increase,crop=\(tW):\(tH):(iw-ow)/2:(ih-oh)/2"
        }
        return containPad
    }

    private func scaleFilterVideoString(for clip: VideoEditClip) -> String? {
        guard scaleEnabled else { return nil }
        switch appState.videoEditResizeKind {
        case .percent:
            guard selectedScale != .original else { return nil }
            let m = selectedScale.multiplier
            return "scale=trunc(iw*\(m)/2)*2:trunc(ih*\(m)/2)*2"
        case .custom:
            guard let (tw, th) = parsedCustomExportSize() else { return nil }
            return Self.customCanvasVideoFilter(
                targetW: tw, targetH: th,
                autoFill: appState.videoEditAutoFillCanvas,
                srcW: clip.sourceWidth, srcH: clip.sourceHeight
            )
        }
    }

    private func buildVideoFilterComponents(for clip: VideoEditClip) -> [String] {
        var vf: [String] = []
        if let s = scaleFilterVideoString(for: clip) {
            vf.append(s)
        }
        if fpsEnabled, let fpsVal = selectedFPS.value {
            vf.append("fps=\(Int(fpsVal))")
        }
        return vf
    }

    private func buildVideoFilterArgs(for clip: VideoEditClip) -> [String] {
        let parts = buildVideoFilterComponents(for: clip)
        return parts.isEmpty ? [] : ["-vf", parts.joined(separator: ",")]
    }

    private func buildMergeVideoFilter(for clip: VideoEditClip) -> String {
        var vf: [String] = []
        if let s = scaleFilterVideoString(for: clip) {
            vf.append(s)
        } else {
            vf.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")
        }
        if fpsEnabled, let fpsVal = selectedFPS.value {
            vf.append("fps=\(Int(fpsVal))")
        }
        return vf.joined(separator: ",")
    }

    private func uniqueURL(folder: URL, base: String, ext: String) -> URL {
        var u = folder.appendingPathComponent("\(base).\(ext)"); var n = 1
        while FileManager.default.fileExists(atPath: u.path) {
            u = folder.appendingPathComponent("\(base)_\(n).\(ext)"); n += 1
        }
        return u
    }

    func fmtTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let m = Int(s) / 60; let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - ClipStripView
// Tıklayınca genişleyip trim modu açan, ok tuşlarıyla sıralanan, + ile yanına video eklenebilen şerit.

struct ClipStripView: View {
    let clip: VideoEditClip
    let index: Int
    let clipCount: Int
    let isSelected: Bool
    let isTrimming: Bool
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    @Binding var currentTime: Double
    let onSelect: () -> Void
    let onConfirmTrim: () -> Void
    let onDelete: () -> Void
    let onMoveLeft: (() -> Void)?
    let onMoveRight: (() -> Void)?
    let onInsertAfter: () -> Void

    @State private var isHovered = false
    @State private var activeHandle: HandleSide = .none
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var languageManager: LanguageManager

    private enum HandleSide { case start, end, none }

    private var stripW: CGFloat { isTrimming ? 420 : 100 }
    private let handleW: CGFloat = 20
    private let stripH: CGFloat = 56
    private let trimColor = Color(red: 1.0, green: 0.76, blue: 0.03)

    var body: some View {
        HStack(spacing: 4) {
            VStack(spacing: 0) {
                headerRow
                    .frame(width: stripW)

                stripBody
                    .frame(width: stripW, height: stripH)

                footerRow
                    .frame(width: stripW)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isTrimming { onSelect() } }

            if isTrimming {
                confirmAndInsertButtons
            }
        }
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isTrimming)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .padding(.horizontal, 4)
        .contextMenu {
            Button { onInsertAfter() } label: {
                Label(languageManager.string("videoedit.insert.after"), systemImage: "arrow.right.to.line")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label(languageManager.string("videoedit.clip.remove"), systemImage: "trash")
            }
        }
    }

    // MARK: - Header row: index + name + arrows + delete

    private var headerRow: some View {
        HStack(spacing: 4) {
            if onMoveLeft != nil {
                arrowButton(icon: "chevron.left", action: onMoveLeft!)
            }

            Text("\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(isTrimming ? trimColor : Color.secondary)
                .frame(width: 14, height: 14)
                .background(Circle().fill(isTrimming ? trimColor.opacity(0.2) : Color.primary.opacity(0.06)))

            Text(clip.fileName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isHovered || isTrimming {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain).handCursor()
                .transition(.opacity)
            }

            if onMoveRight != nil {
                arrowButton(icon: "chevron.right", action: onMoveRight!)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private func arrowButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    // MARK: - Footer row

    private var footerRow: some View {
        HStack(spacing: 4) {
            if isTrimming {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                    Text(fmtDur(trimStart))
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(trimColor.opacity(0.6))

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text(fmtDur(trimEnd - trimStart))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(trimColor)

                Spacer()

                HStack(spacing: 2) {
                    Text(fmtDur(trimEnd))
                        .font(.system(size: 9, design: .monospaced))
                    Image(systemName: "chevron.left")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(trimColor.opacity(0.6))
            } else {
                Text(fmtDur(clip.trimmedDuration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                if clip.startTime > 0.05 || clip.endTime < clip.duration - 0.05 {
                    Image(systemName: "scissors")
                        .font(.system(size: 8))
                        .foregroundStyle(trimColor.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Confirm trim + insert

    private var confirmAndInsertButtons: some View {
        VStack(spacing: 8) {
            Button(action: onConfirmTrim) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(trimColor)
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(languageManager.string("videoedit.trim.confirm"))

            Button(action: onInsertAfter) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(languageManager.string("videoedit.insert.after"))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    // MARK: - Strip body

    @ViewBuilder
    private var stripBody: some View {
        let w = stripW
        let startFrac = clip.duration > 0 ? trimStart / clip.duration : 0
        let endFrac   = clip.duration > 0 ? trimEnd   / clip.duration : 1

        ZStack(alignment: .leading) {
            filmstrip(width: w, height: stripH)

            if isTrimming {
                if startFrac > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: max(0, w * startFrac), height: stripH)
                }
                if endFrac < 1 {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: max(0, w * (1 - endFrac)), height: stripH)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                let ax = w * startFrac
                let aw = max(0, w * (endFrac - startFrac))

                VStack(spacing: 0) {
                    Rectangle().fill(trimColor).frame(height: 4)
                    Spacer()
                    Rectangle().fill(trimColor).frame(height: 4)
                }
                .frame(width: aw, height: stripH)
                .offset(x: ax)
                .allowsHitTesting(false)

                let playMinX = w * startFrac + handleW
                let playMaxX = w * endFrac - handleW
                let trimRange = trimEnd - trimStart
                let playProg = trimRange > 0 ? max(0, min(1, (currentTime - trimStart) / trimRange)) : 0
                let playX = playMinX + playProg * (playMaxX - playMinX)

                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: stripH + 8)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: playX - 1.25, y: -4)
                    .allowsHitTesting(false)

                handleView(side: .start, isActive: activeHandle == .start)
                    .frame(width: handleW, height: stripH)
                    .offset(x: w * startFrac)
                    .allowsHitTesting(false)

                handleView(side: .end, isActive: activeHandle == .end)
                    .frame(width: handleW, height: stripH)
                    .offset(x: w * endFrac - handleW)
                    .allowsHitTesting(false)
            } else {
                if !isSelected {
                    Rectangle().fill(Color.black.opacity(0.2))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isTrimming ? trimColor.opacity(0) :
                        (isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12)),
                    lineWidth: isSelected && !isTrimming ? 2 : 1
                )
        )
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { v in
                    guard isTrimming else { return }
                    let x = v.location.x
                    let frac = max(0, min(1, x / w))
                    if activeHandle == .none {
                        let ds = abs(x - w * startFrac)
                        let de = abs(x - w * endFrac)
                        activeHandle = ds <= de ? .start : .end
                    }
                    switch activeHandle {
                    case .start: trimStart = max(0, min(trimEnd - 0.3, frac * clip.duration))
                    case .end:   trimEnd = max(trimStart + 0.3, min(clip.duration, frac * clip.duration))
                    case .none:  break
                    }
                }
                .onEnded { _ in activeHandle = .none }
        )
    }

    // MARK: - Filmstrip

    @ViewBuilder
    private func filmstrip(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color(white: 0.12)
            if let thumb = clip.thumbnail {
                HStack(spacing: 0) {
                    let tileW = height * (16.0 / 9.0)
                    let n = max(1, Int(ceil(width / tileW)))
                    ForEach(0..<n, id: \.self) { _ in
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: tileW, height: height)
                            .clipped()
                    }
                }
                .frame(width: width, height: height)
                .clipped()
                .opacity(0.75)
            } else {
                Image(systemName: "film")
                    .font(.system(size: isTrimming ? 20 : 14, weight: .ultraLight))
                    .foregroundStyle(Color.secondary.opacity(0.35))
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Handle (iOS-style cap with chevron)

    private func handleView(side: HandleSide, isActive: Bool = false) -> some View {
        HandleCapShape(roundLeft: side == .start, cornerRadius: 8)
            .fill(trimColor)
            .overlay(
                Image(systemName: side == .start ? "chevron.compact.left" : "chevron.compact.right")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(isActive ? 0.9 : 0.55))
            )
            .scaleEffect(y: isActive ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isActive)
    }

    private struct HandleCapShape: Shape {
        let roundLeft: Bool
        let cornerRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            let r = min(cornerRadius, rect.width / 2, rect.height / 2)
            var p = Path()
            if roundLeft {
                p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
                p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r),
                               control: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
                p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                               control: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            } else {
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                               control: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
                p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                               control: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            p.closeSubpath()
            return p
        }
    }

    private func fmtDur(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        let m = Int(s) / 60; let sec = Int(s) % 60; let ds = Int((s - Double(Int(s))) * 10)
        return String(format: "%d:%02d.%d", m, sec, ds)
    }
}

// MARK: - Output Format

enum VideoEditOutputFormat: String, CaseIterable, Identifiable {
    case mp4, mov, mkv, avi
    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var localizationKey: String {
        switch self {
        case .mp4: return "videoedit.output.mp4"
        case .mov: return "videoedit.output.mov"
        case .mkv: return "videoedit.output.mkv"
        case .avi: return "videoedit.output.avi"
        }
    }
    func codecArgs(quality: Double) -> [String] {
        switch self {
        case .mp4, .mov:
            let crf = max(18, min(51, Int(51 - (quality / 10.0) * 33)))
            return ["-c:v","libx264","-crf","\(crf)","-preset","medium","-c:a","aac","-b:a","128k"]
        case .mkv:
            let crf = max(16, min(51, Int(51 - (quality / 10.0) * 35)))
            return ["-c:v","libx265","-crf","\(crf)","-preset","medium","-c:a","libopus","-b:a","128k"]
        case .avi:
            let q = max(4, min(31, Int(31 - (quality / 10.0) * 27)))
            return ["-c:v","mpeg4","-qscale:v","\(q)","-c:a","libmp3lame","-q:a","4"]
        }
    }
}

// MARK: - Clip Drop Delegate

private struct ClipDropDelegate: DropDelegate {
    let insertAt: Int
    let handleDrop: ([NSItemProvider]) -> Bool

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        return handleDrop(providers)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {}
    func dropExited(info: DropInfo) {}
}

// MARK: - AVPlayer Wrapper

struct VideoPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.player = player; v.controlsStyle = .none
        v.videoGravity = .resizeAspect; return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}
