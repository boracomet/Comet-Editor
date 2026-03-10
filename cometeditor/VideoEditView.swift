// VideoEditView.swift
// cometeditor — MiniCut logic ported to SwiftUI + AVFoundation (no SpriteKit)

import SwiftUI
import AVFoundation
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - ClipCategory
enum ClipCategory: Hashable {
    case video, audio, other
}

// MARK: - ClipContent
enum ClipContent {
    case audiovisual(AVAsset)
    case text(String, CGFloat, NSColor)
    case image(NSImage)
    case color(NSColor)

    var duration: TimeInterval? {
        if case .audiovisual(let a) = self {
            let d = a.duration.seconds
            return d.isFinite && d > 0 ? d : nil
        }
        return nil
    }
}

// MARK: - Clip
struct Clip: Identifiable {
    static var defaultLength: TimeInterval = 10
    var id: UUID = UUID()
    var name: String = "<unnamed>"
    var category: ClipCategory = .other
    var content: ClipContent
    private var _start: TimeInterval = 0
    private var _length: TimeInterval
    var start: TimeInterval {
        get { _start }
        set { _start = max(0, newValue) }
    }
    var length: TimeInterval {
        get { _length }
        set { _length = min(max(0, newValue), content.duration.map { $0 - _start } ?? .infinity) }
    }
    var visualOffsetDx: Double = 0
    var visualOffsetDy: Double = 0
    private var _visualScale: Double = 1
    private var _visualAlpha: Double = 1
    var visualScale: Double {
        get { _visualScale }
        set { _visualScale = max(0, newValue) }
    }
    var visualAlpha: Double {
        get { _visualAlpha }
        set { _visualAlpha = min(1, max(0, newValue)) }
    }
    var volume: Double = 1

    var swiftUIColor: Color {
        switch (content, category) {
        case (.text, _): return Color(red: 0.6, green: 0.3, blue: 0.7)
        case (.audiovisual, .audio): return Color(red: 0, green: 0.5, blue: 0)
        case (.color(let c), _): return Color(c)
        default: return Color(red: 0, green: 0.4, blue: 0.7)
        }
    }

    init(id: UUID = UUID(), name: String = "<unnamed>", category: ClipCategory = .other,
         content: ClipContent, start: TimeInterval = 0, length: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.content = content
        _start = max(0, start)
        _length = max(0, length ?? content.duration ?? Self.defaultLength)
    }

    init(url: URL) {
        let asset = AVURLAsset(url: url)
        let hasvideo = !asset.tracks(withMediaType: .video).isEmpty
        let hasaudio = !asset.tracks(withMediaType: .audio).isEmpty
        let cat: ClipCategory = hasvideo ? .video : (hasaudio ? .audio : .other)
        self.init(
            name: url.deletingPathExtension().lastPathComponent,
            category: cat,
            content: .audiovisual(asset)
        )
    }
}

// MARK: - OffsetClip
struct OffsetClip: Identifiable {
    var id: UUID = UUID()
    var clip: Clip
    private var _offset: TimeInterval = 0
    var offset: TimeInterval {
        get { _offset }
        set { _offset = max(0, newValue) }
    }
    init(id: UUID = UUID(), clip: Clip, offset: TimeInterval = 0) {
        self.id = id
        self.clip = clip
        _offset = max(0, offset)
    }
    func isPlaying(at t: TimeInterval) -> Bool { t >= offset && t < offset + clip.length }
    func relativeOffset(for t: TimeInterval) -> TimeInterval { t - offset }
    func clipOffset(for t: TimeInterval) -> TimeInterval { relativeOffset(for: t) + clip.start }
}

// MARK: - Track
struct Track: Identifiable {
    var id: UUID = UUID()
    var name: String = "New Track"
    var clipsById: [UUID: OffsetClip] = [:]
    var clips: [OffsetClip] { Array(clipsById.values) }
    subscript(id: UUID) -> OffsetClip? {
        get { clipsById[id] }
        set { clipsById[id] = newValue }
    }
    mutating func insert(clip: OffsetClip) { self[clip.id] = clip }
    @discardableResult
    mutating func remove(clipId: UUID) -> OffsetClip? {
        let c = self[clipId]; self[clipId] = nil; return c
    }
    @discardableResult
    mutating func cut(clipId: UUID, at offset: TimeInterval) -> (UUID, UUID)? {
        guard self[clipId]?.isPlaying(at: offset) ?? false,
              let clip = remove(clipId: clipId) else { return nil }
        var left = clip; var right = clip
        let rel = clip.relativeOffset(for: offset)
        left.id = UUID(); left.clip.length = rel
        right.id = UUID(); right.offset += rel; right.clip.start += rel; right.clip.length -= rel
        insert(clip: left); insert(clip: right)
        return (left.id, right.id)
    }
}

// MARK: - Timeline
struct VETimeline: Identifiable {
    var id: UUID = UUID()
    var tracks: [Track] = []
    var maxOffset: TimeInterval {
        tracks.compactMap { $0.clips.map { $0.offset + $0.clip.length }.max() }.max() ?? 0
    }
    subscript(id: UUID) -> Track? {
        get { tracks.first { $0.id == id } }
        set {
            if let t = newValue {
                if let i = tracks.firstIndex(where: { $0.id == id }) { tracks[i] = t }
                else { tracks.append(t) }
            } else { tracks.removeAll { $0.id == id } }
        }
    }
    struct PlayingClip: Identifiable {
        let trackId: UUID; let clip: OffsetClip; let zIndex: Int
        var id: UUID { clip.id }
    }
    func playingClips(at t: TimeInterval) -> [PlayingClip] {
        tracks.enumerated().flatMap { (z, track) in
            track.clips.filter { $0.isPlaying(at: t) }.map {
                PlayingClip(trackId: track.id, clip: $0, zIndex: -z)
            }
        }.sorted { $0.zIndex < $1.zIndex }
    }
}

// MARK: - Selection
struct VESelection { var trackId: UUID; var clipId: UUID }

// MARK: - Library
struct VELibrary { var clips: [Clip] = [] }

// MARK: - ViewModel
final class VideoEditState: ObservableObject {
    @Published var library = VELibrary()
    @Published var timeline = VETimeline()
    @Published var selection: VESelection? = nil
    @Published var isPlaying: Bool = false
    @Published var timelineZoom: Double = 80

    private var _cursor: TimeInterval = 0
    var cursor: TimeInterval {
        get { _cursor }
        set {
            let v = max(0, newValue)
            guard _cursor != v else { return }
            _cursor = v
            objectWillChange.send()
        }
    }

    private var _timelineOffset: TimeInterval = 0
    var timelineOffset: TimeInterval {
        get { _timelineOffset }
        set {
            let v = max(0, newValue)
            guard _timelineOffset != v else { return }
            _timelineOffset = v
            objectWillChange.send()
        }
    }

    private var undoStack: [VETimeline] = []

    func pushUndo() {
        undoStack.append(timeline)
        if undoStack.count > 15 { undoStack.removeFirst() }
    }

    func undo() {
        if let s = undoStack.popLast() { timeline = s }
    }

    func cut() {
        guard let sel = selection,
              let (leftId, _) = timeline[sel.trackId]?.cut(clipId: sel.clipId, at: cursor) else { return }
        selection?.clipId = leftId
    }
}

// MARK: - VideoEditView (Ana View)
struct VideoEditView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @StateObject private var state = VideoEditState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VELibraryPanel(state: state)
                    .frame(width: 200)
                Divider()
                VEVideoPanel(state: state)
                    .frame(maxWidth: .infinity)
                Divider()
                VEInspectorPanel(state: state)
                    .frame(width: 200)
            }
            .frame(maxHeight: .infinity)

            Divider()

            VEToolbar(state: state)

            Divider()

            VETimelineView(state: state)
                .frame(height: 200)
        }
        .background(Color(white: 0.15))
        .background(VEUndoMonitor { state.undo() })
        .onReceive(state.$isPlaying) { _ in }
    }
}

// MARK: - Library Panel
struct VELibraryPanel: View {
    @ObservedObject var state: VideoEditState
    @State private var activeTab: VELibTab = .video

    enum VELibTab: String, CaseIterable {
        case video = "Video", title = "Title", color = "Color", audio = "Audio"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(VELibTab.allCases, id: \.self) { tab in
                    Button(tab.rawValue) { activeTab = tab }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundStyle(activeTab == tab ? Color.white : Color.white.opacity(0.5))
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(activeTab == tab ? Color.white.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                }
            }
            .padding(8)

            Divider().background(Color.white.opacity(0.2))

            ScrollView {
                switch activeTab {
                case .video:
                    VELibraryClipsGrid(state: state, category: .video)
                case .audio:
                    VELibraryClipsGrid(state: state, category: .audio)
                case .title:
                    VELibraryStaticGrid(clips: [
                        Clip(name: "Text", content: .text("Text", 24, .white))
                    ], state: state)
                case .color:
                    VELibraryStaticGrid(clips: [
                        Clip(name: "Black",   content: .color(.black)),
                        Clip(name: "Blue",    content: .color(.blue)),
                        Clip(name: "Green",   content: .color(.green)),
                        Clip(name: "Magenta", content: .color(.magenta)),
                        Clip(name: "Yellow",  content: .color(.yellow)),
                        Clip(name: "White",   content: .color(.white)),
                    ], state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.white.opacity(0.2))

            if activeTab == .video || activeTab == .audio {
                Button("Import...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.allowedContentTypes = activeTab == .video
                        ? [.movie, .video, .mpeg4Movie, .quickTimeMovie]
                        : [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
                    if panel.runModal() == .OK {
                        state.library.clips += panel.urls.map { Clip(url: $0) }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(8)
            }
        }
        .background(Color.white.opacity(0.08))
    }
}

struct VELibraryClipsGrid: View {
    @ObservedObject var state: VideoEditState
    let category: ClipCategory

    var clips: [Clip] { state.library.clips.filter { $0.category == category } }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
            ForEach(clips) { clip in
                VELibraryClipThumb(clip: clip, state: state)
            }
        }
        .padding(8)
    }
}

struct VELibraryStaticGrid: View {
    let clips: [Clip]
    @ObservedObject var state: VideoEditState

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
            ForEach(clips) { clip in
                VELibraryClipThumb(clip: clip, state: state)
            }
        }
        .padding(8)
    }
}

struct VELibraryClipThumb: View {
    let clip: Clip
    @ObservedObject var state: VideoEditState

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(clip.swiftUIColor.opacity(0.8))
                    .frame(width: 70, height: 39)

                switch (clip.content, clip.category) {
                case (.audiovisual, .audio):
                    Image(systemName: "waveform").foregroundStyle(.white).font(.system(size: 16))
                case (.text(let t, _, _), _):
                    Text(t).foregroundStyle(.white).font(.system(size: 10)).lineLimit(1)
                default:
                    Image(systemName: "film").foregroundStyle(.white.opacity(0.6)).font(.system(size: 16))
                }
            }
            Text(clip.name)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
        }
        .onTapGesture(count: 2) { addToTimeline() }
        .onTapGesture { }
        .contextMenu {
            Button("Timeline'a Ekle") { addToTimeline() }
        }
    }

    private func addToTimeline() {
        state.pushUndo()
        let matchingTrack = state.timeline.tracks.first { track in
            if clip.category == .audio {
                return track.clips.first?.clip.category == .audio || track.name.lowercased().contains("audio")
            } else {
                return track.clips.first?.clip.category != .audio && !track.name.lowercased().contains("audio")
            }
        }
        if let trackId = matchingTrack?.id {
            let offset = state.timeline[trackId]?.clips.map { $0.offset + $0.clip.length }.max() ?? 0
            state.timeline[trackId]?.insert(clip: OffsetClip(clip: clip, offset: offset))
        } else {
            var newTrack = Track(name: clip.category == .audio
                ? "Audio \(state.timeline.tracks.count + 1)"
                : "Track \(state.timeline.tracks.count + 1)")
            newTrack.insert(clip: OffsetClip(clip: clip, offset: 0))
            state.timeline.tracks.append(newTrack)
        }
    }
}

// MARK: - Video Panel
struct VEVideoPanel: View {
    @ObservedObject var state: VideoEditState
    @State private var players: [UUID: AVPlayer] = [:]
    @State private var playTimer: Timer? = nil
    @State private var playStartDate: Date? = nil
    @State private var playStartCursor: TimeInterval? = nil

    var body: some View {
        ZStack {
            Color.black

            let playing = state.timeline.playingClips(at: state.cursor)
            ForEach(playing) { p in
                if case .audiovisual = p.clip.clip.content {
                    VEAVPlayerView(player: playerFor(p))
                        .offset(
                            x: CGFloat(p.clip.clip.visualOffsetDx) * 300,
                            y: CGFloat(p.clip.clip.visualOffsetDy) * 168
                        )
                        .scaleEffect(CGFloat(p.clip.clip.visualScale))
                        .opacity(p.clip.clip.visualAlpha)
                        .zIndex(Double(p.zIndex + 100))
                } else if case .color(let c) = p.clip.clip.content {
                    Color(c)
                        .opacity(p.clip.clip.visualAlpha)
                        .zIndex(Double(p.zIndex + 100))
                } else if case .text(let t, let sz, let col) = p.clip.clip.content {
                    Text(t)
                        .font(.system(size: sz))
                        .foregroundStyle(Color(col))
                        .offset(
                            x: CGFloat(p.clip.clip.visualOffsetDx) * 300,
                            y: CGFloat(p.clip.clip.visualOffsetDy) * 168
                        )
                        .zIndex(Double(p.zIndex + 100))
                }
            }

            if playing.isEmpty {
                Text("No media at this position")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
        .onChange(of: state.cursor) { _ in syncPlayers() }
        .onChange(of: state.isPlaying) { playing in
            if playing {
                playStartDate = Date()
                playStartCursor = state.cursor
                syncPlayers()
                playTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    guard let startDate = playStartDate, let startCursor = playStartCursor else { return }
                    state.cursor = startCursor + (-startDate.timeIntervalSinceNow)
                }
                players.values.forEach { $0.play() }
            } else {
                playTimer?.invalidate(); playTimer = nil
                players.values.forEach { $0.pause() }
            }
        }
    }

    private func playerFor(_ p: VETimeline.PlayingClip) -> AVPlayer {
        if let existing = players[p.clip.id] { return existing }
        guard case .audiovisual(let asset) = p.clip.clip.content else { return AVPlayer() }
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.volume = Float(p.clip.clip.volume)
        players[p.clip.id] = player
        return player
    }

    private func syncPlayers() {
        let playing = state.timeline.playingClips(at: state.cursor)
        let playingIds = Set(playing.map { $0.clip.id })
        for id in players.keys where !playingIds.contains(id) {
            players[id]?.pause()
            players.removeValue(forKey: id)
        }
        for p in playing {
            let clipOffset = p.clip.clipOffset(for: state.cursor)
            let player = playerFor(p)
            player.seek(to: CMTime(seconds: clipOffset, preferredTimescale: 1000))
            if state.isPlaying {
                player.volume = Float(p.clip.clip.volume)
                player.play()
            }
        }
    }
}

struct VEAVPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> VEAVPlayerNSView { VEAVPlayerNSView() }
    func updateNSView(_ v: VEAVPlayerNSView, context: Context) { v.player = player }
}

class VEAVPlayerNSView: NSView {
    private var playerLayer = AVPlayerLayer()
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    override func layout() { super.layout(); playerLayer.frame = bounds }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Inspector Panel
struct VEInspectorPanel: View {
    @ObservedObject var state: VideoEditState

    var body: some View {
        VStack(spacing: 0) {
            Text("Inspector")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(8)

            Divider().background(Color.white.opacity(0.2))

            if let sel = state.selection,
               let track = state.timeline[sel.trackId],
               let oc = track[sel.clipId] {
                VEInspectorClipForm(state: state, oc: oc, trackId: sel.trackId, clipId: sel.clipId)
            } else {
                Text("Select a timeline clip to inspect it!")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white.opacity(0.08))
    }
}

struct VEInspectorClipForm: View {
    @ObservedObject var state: VideoEditState
    let oc: OffsetClip
    let trackId: UUID
    let clipId: UUID

    private var clip: Clip { oc.clip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if case .audiovisual = clip.content {
                    VEInspectorSlider(label: "Volume", value: Binding(
                        get: { state.timeline[trackId]?[clipId]?.clip.volume ?? 1 },
                        set: { state.timeline[trackId]?[clipId]?.clip.volume = $0 }
                    ), range: 0...1)
                }

                if case .text(let t, let sz, _) = clip.content {
                    VEInspectorTextRow(label: "Text", value: t) { newVal in
                        guard case .text(_, let s, let c) = state.timeline[trackId]?[clipId]?.clip.content else { return }
                        state.timeline[trackId]?[clipId]?.clip.content = .text(newVal, s, c)
                    }
                    VEInspectorSlider(label: "Size", value: Binding(
                        get: { Double(sz) },
                        set: { v in
                            guard case .text(let t2, _, let c) = state.timeline[trackId]?[clipId]?.clip.content else { return }
                            state.timeline[trackId]?[clipId]?.clip.content = .text(t2, CGFloat(v), c)
                        }
                    ), range: 1...300)
                }

                if clip.category != .audio {
                    VEInspectorSlider(label: "X", value: Binding(
                        get: { state.timeline[trackId]?[clipId]?.clip.visualOffsetDx ?? 0 },
                        set: { state.timeline[trackId]?[clipId]?.clip.visualOffsetDx = $0 }
                    ), range: -1...1)
                    VEInspectorSlider(label: "Y", value: Binding(
                        get: { state.timeline[trackId]?[clipId]?.clip.visualOffsetDy ?? 0 },
                        set: { state.timeline[trackId]?[clipId]?.clip.visualOffsetDy = $0 }
                    ), range: -1...1)
                    VEInspectorSlider(label: "Scale", value: Binding(
                        get: { state.timeline[trackId]?[clipId]?.clip.visualScale ?? 1 },
                        set: { state.timeline[trackId]?[clipId]?.clip.visualScale = $0 }
                    ), range: 0...4)
                    VEInspectorSlider(label: "Alpha", value: Binding(
                        get: { state.timeline[trackId]?[clipId]?.clip.visualAlpha ?? 1 },
                        set: { state.timeline[trackId]?[clipId]?.clip.visualAlpha = $0 }
                    ), range: 0...1)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VEInspectorSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5))
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: "%.2f", value))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 40)
            }
        }
    }
}

struct VEInspectorTextRow: View {
    let label: String
    let value: String
    let onChange: (String) -> Void
    @State private var editing: String

    init(label: String, value: String, onChange: @escaping (String) -> Void) {
        self.label = label
        self.value = value
        self.onChange = onChange
        _editing = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5))
            TextField("", text: $editing)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.white)
                .padding(4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(3)
                .onChange(of: editing) { newVal in onChange(newVal) }
        }
    }
}

// MARK: - Toolbar
struct VEToolbar: View {
    @ObservedObject var state: VideoEditState

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                VEToolBtn(icon: "plus", tip: "Add Track") {
                    state.timeline.tracks.append(Track(name: "Track \(state.timeline.tracks.count + 1)"))
                }
                VEToolBtn(icon: "trash", tip: "Delete") {
                    if let sel = state.selection {
                        state.pushUndo()
                        state.timeline[sel.trackId]?.remove(clipId: sel.clipId)
                        state.selection = nil
                    } else if !state.timeline.tracks.isEmpty {
                        state.pushUndo()
                        state.timeline.tracks.removeLast()
                    }
                }
                VEToolBtn(icon: "scissors", tip: "Cut") {
                    state.pushUndo()
                    state.cut()
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            HStack(spacing: 8) {
                VEToolBtn(icon: "backward.end.fill", tip: "Back to Start") {
                    state.cursor = 0; state.timelineOffset = 0
                }
                VEToolBtn(icon: "gobackward.10", tip: "-10s") { state.cursor -= 10 }
                Button {
                    state.isPlaying.toggle()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.white)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                VEToolBtn(icon: "goforward.10", tip: "+10s") { state.cursor += 10 }
                VEToolBtn(icon: "forward.end.fill", tip: "Skip to End") {
                    state.cursor = state.timeline.maxOffset
                    state.timelineOffset = state.timeline.maxOffset
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text(formatVETime(state.cursor))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.8))
                Slider(value: $state.timelineZoom, in: 10...400)
                    .frame(width: 80)
                Text(String(format: "%.0f", state.timelineZoom))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 30)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .background(Color(white: 0.12))
    }
}

struct VEToolBtn: View {
    let icon: String; let tip: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(tip)
    }
}

// MARK: - Timeline Drag State
enum VETimelineDrag {
    case inactive
    case scrolling(startX: CGFloat, startOffset: TimeInterval, moved: Bool)
    case cursor
    case clip(trackId: UUID, clipId: UUID, dxInClip: CGFloat)
    case trimLeft(trackId: UUID, clipId: UUID, startX: CGFloat, startClip: OffsetClip)
    case trimRight(trackId: UUID, clipId: UUID, startX: CGFloat, startClip: OffsetClip)
}

// MARK: - Timeline View
struct VETimelineView: View {
    @ObservedObject var state: VideoEditState
    @State private var drag: VETimelineDrag = .inactive

    let trackH: CGFloat = 36
    let labelW: CGFloat = 100
    let cursorHitW: CGFloat = 25
    let trimHitW: CGFloat = 10

    var pps: CGFloat { CGFloat(state.timelineZoom) }

    func timeToX(_ t: TimeInterval, laneW: CGFloat) -> CGFloat {
        labelW + CGFloat((t - state.timelineOffset) * state.timelineZoom)
    }

    func xToTime(_ x: CGFloat, laneW: CGFloat) -> TimeInterval {
        TimeInterval((x - labelW) / pps) + state.timelineOffset
    }

    var body: some View {
        GeometryReader { geo in
            let laneW = geo.size.width
            let totalH = max(geo.size.height, CGFloat(state.timeline.tracks.count) * trackH + 20)
            let contentW = max(laneW, CGFloat(state.timeline.maxOffset + 5) * pps + labelW)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Color(white: 0.13).frame(width: contentW, height: totalH)

                    VETimelineRuler(state: state, width: contentW, labelW: labelW)
                        .frame(height: 20)

                    VStack(spacing: 0) {
                        Spacer().frame(height: 20)
                        ForEach(Array(state.timeline.tracks.enumerated()), id: \.element.id) { (idx, track) in
                            VETrackRow(
                                state: state,
                                track: track,
                                trackIdx: idx,
                                trackH: trackH,
                                labelW: labelW,
                                pps: pps,
                                drag: $drag,
                                timeToX: { timeToX($0, laneW: laneW) },
                                xToTime: { xToTime($0, laneW: laneW) }
                            )
                        }
                        if state.timeline.tracks.isEmpty {
                            Text("Create a track with '+' and add a clip from the library to get started!")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.3))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(20)
                        }
                    }
                    .frame(width: contentW)

                    let cursorX = timeToX(state.cursor, laneW: laneW)
                    VEPlayhead(x: cursorX, totalH: totalH, hitW: cursorHitW)
                }
                .frame(width: contentW, height: totalH)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in handleDragChanged(v, laneW: laneW) }
                        .onEnded   { v in handleDragEnded(v,   laneW: laneW) }
                )
            }
            .onScrollWheel { event in
                let scrollSpeed = 4.0
                let delta = scrollSpeed * Double(event.scrollingDeltaX) / state.timelineZoom
                state.timelineOffset = max(0, state.timelineOffset + delta)
            }
        }
        .background(Color(white: 0.13))
    }

    // MARK: Drag Handling
    func handleDragChanged(_ v: DragGesture.Value, laneW: CGFloat) {
        let pt = v.location

        switch drag {
        case .inactive:
            // Trim check on selected clip
            if let sel = state.selection, let oc = state.timeline[sel.trackId]?[sel.clipId] {
                let clipX = timeToX(oc.offset, laneW: laneW)
                let clipEndX = timeToX(oc.offset + oc.clip.length, laneW: laneW)
                if abs(pt.x - clipX) <= trimHitW {
                    drag = .trimLeft(trackId: sel.trackId, clipId: sel.clipId, startX: pt.x, startClip: oc)
                    return
                }
                if abs(pt.x - clipEndX) <= trimHitW {
                    drag = .trimRight(trackId: sel.trackId, clipId: sel.clipId, startX: pt.x, startClip: oc)
                    return
                }
            }
            // Clip hit test
            let trackIdx = Int((pt.y - 20) / trackH)
            if trackIdx >= 0 && trackIdx < state.timeline.tracks.count {
                let track = state.timeline.tracks[trackIdx]
                for oc in track.clips {
                    let clipX = timeToX(oc.offset, laneW: laneW)
                    let clipW = CGFloat(oc.clip.length) * pps
                    if pt.x >= clipX && pt.x <= clipX + clipW && pt.x >= labelW {
                        let dx = pt.x - clipX
                        state.selection = VESelection(trackId: track.id, clipId: oc.id)
                        drag = .clip(trackId: track.id, clipId: oc.id, dxInClip: dx)
                        return
                    }
                }
            }
            // Cursor grab
            let cursorX = timeToX(state.cursor, laneW: laneW)
            if abs(pt.x - cursorX) <= cursorHitW {
                drag = .cursor
                return
            }
            // Scroll / deselect
            state.selection = nil
            drag = .scrolling(startX: pt.x, startOffset: state.timelineOffset, moved: false)

        case .scrolling(let sx, let so, _):
            let newOffset = so - Double(pt.x - sx) / state.timelineZoom
            state.timelineOffset = max(0, newOffset)
            drag = .scrolling(startX: sx, startOffset: so, moved: true)

        case .cursor:
            state.cursor = max(0, xToTime(pt.x, laneW: laneW))

        case .clip(let tid, let cid, let dxInClip):
            let newTime = xToTime(pt.x - dxInClip, laneW: laneW)
            let targetIdx = Int((pt.y - 20) / trackH)
            if targetIdx >= 0 && targetIdx < state.timeline.tracks.count {
                let targetTrack = state.timeline.tracks[targetIdx]
                if targetTrack.id != tid {
                    if var movedClip = state.timeline[tid]?.remove(clipId: cid) {
                        movedClip.id = UUID()
                        movedClip.offset = max(0, newTime)
                        state.timeline[targetTrack.id]?.insert(clip: movedClip)
                        state.selection = VESelection(trackId: targetTrack.id, clipId: movedClip.id)
                        drag = .clip(trackId: targetTrack.id, clipId: movedClip.id, dxInClip: dxInClip)
                    }
                    return
                }
            }
            state.timeline[tid]?[cid]?.offset = max(0, newTime)

        case .trimLeft(let tid, let cid, let sx, let startClip):
            let delta = Double(v.location.x - sx) / state.timelineZoom
            var oc = startClip
            oc.offset = startClip.offset + delta
            oc.clip.start = startClip.clip.start + delta
            oc.clip.length = startClip.clip.length - delta
            state.timeline[tid]?[cid] = oc

        case .trimRight(let tid, let cid, let sx, let startClip):
            let delta = Double(v.location.x - sx) / state.timelineZoom
            var oc = startClip
            oc.clip.length = startClip.clip.length + delta
            state.timeline[tid]?[cid] = oc
        }
    }

    func handleDragEnded(_ v: DragGesture.Value, laneW: CGFloat) {
        if case .scrolling(_, _, let moved) = drag, !moved {
            state.cursor = max(0, xToTime(v.location.x, laneW: laneW))
        }
        drag = .inactive
    }
}

// MARK: - Track Row
struct VETrackRow: View {
    @ObservedObject var state: VideoEditState
    let track: Track
    let trackIdx: Int
    let trackH: CGFloat
    let labelW: CGFloat
    let pps: CGFloat
    @Binding var drag: VETimelineDrag
    let timeToX: (TimeInterval) -> CGFloat
    let xToTime: (CGFloat) -> TimeInterval

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: trackIdx % 2 == 0 ? 0.16 : 0.14)

            ForEach(track.clips.sorted(by: { $0.offset < $1.offset })) { oc in
                VEClipView(
                    state: state,
                    oc: oc,
                    track: track,
                    trackH: trackH,
                    labelW: labelW,
                    pps: pps,
                    isSelected: state.selection?.trackId == track.id && state.selection?.clipId == oc.id,
                    timeToX: timeToX
                )
            }

            HStack(spacing: 4) {
                Text(track.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(width: labelW, height: trackH)
            .background(Color(white: 0.1).opacity(0.9))
        }
        .frame(height: trackH)
    }
}

// MARK: - Clip View
struct VEClipView: View {
    @ObservedObject var state: VideoEditState
    let oc: OffsetClip
    let track: Track
    let trackH: CGFloat
    let labelW: CGFloat
    let pps: CGFloat
    let isSelected: Bool
    let timeToX: (TimeInterval) -> CGFloat

    let trimHW: CGFloat = 10

    var clipX: CGFloat { timeToX(oc.offset) }
    var clipW: CGFloat { max(trimHW * 2 + 2, CGFloat(oc.clip.length) * pps) }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(oc.clip.swiftUIColor.opacity(isSelected ? 1.0 : 0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                )

            HStack(spacing: 2) {
                Text(oc.clip.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.leading, 4)
                Spacer()
            }

            if isSelected {
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: trimHW)
                    .frame(maxHeight: .infinity)
                    .cornerRadius(2)

                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: trimHW)
                    .frame(maxHeight: .infinity)
                    .cornerRadius(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: clipW, height: trackH - 2)
        .offset(x: clipX)
    }
}

// MARK: - Ruler
struct VETimelineRuler: View {
    @ObservedObject var state: VideoEditState
    let width: CGFloat
    let labelW: CGFloat

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.1)))

            let zoom = state.timelineZoom
            let offset = state.timelineOffset
            let visibleSecs = Double(size.width - labelW) / zoom
            let rawStep = visibleSecs / 7
            let steps = [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0, 600.0]
            let step = steps.min(by: { abs($0 - rawStep) < abs($1 - rawStep) }) ?? 1.0

            var t = Double(Int(offset / step)) * step
            while t <= offset + visibleSecs + step {
                let x = labelW + CGFloat((t - offset) * zoom)
                guard x >= labelW - 2 && x <= size.width + 2 else { t += step; continue }

                let tickH: CGFloat = t.truncatingRemainder(dividingBy: step * 5) == 0 ? 10 : 6
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: size.height - tickH))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                ctx.stroke(path, with: .color(Color.white.opacity(0.4)), lineWidth: 1)

                if t.truncatingRemainder(dividingBy: step * 2) == 0 {
                    let label = formatVETime(t)
                    ctx.draw(
                        Text(label).font(.system(size: 9)).foregroundColor(Color.white.opacity(0.6)),
                        at: CGPoint(x: x, y: size.height / 2), anchor: .center
                    )
                }
                t += step
            }
        }
        .frame(width: width, height: 20)
    }
}

// MARK: - Playhead
struct VEPlayhead: View {
    let x: CGFloat
    let totalH: CGFloat
    let hitW: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: hitW)
                .contentShape(Rectangle())

            Rectangle()
                .fill(Color(red: 0.7, green: 0.1, blue: 0.1))
                .frame(width: 2, height: totalH)

            VETriangle()
                .fill(Color(red: 0.7, green: 0.1, blue: 0.1))
                .frame(width: 12, height: 8)
        }
        .offset(x: x - hitW / 2)
        .allowsHitTesting(false)
    }
}

struct VETriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - Undo Monitor
struct VEUndoMonitor: NSViewRepresentable {
    let onUndo: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onUndo: onUndo) }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
                self.onUndo(); return nil
            }
            return event
        }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {}

    class Coordinator: NSObject {
        var monitor: Any?
        let onUndo: () -> Void
        init(onUndo: @escaping () -> Void) { self.onUndo = onUndo }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

// MARK: - Helpers
func formatVETime(_ t: TimeInterval) -> String {
    let m  = Int(t) / 60
    let s  = Int(t) % 60
    let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
    return String(format: "%d:%02d.%01d", m, s, ms)
}
