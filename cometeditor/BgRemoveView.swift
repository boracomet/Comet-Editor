//
//  BgRemoveView.swift
//  cometeditor
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Entry point (version gate)

struct BgRemoveView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    var body: some View {
        if #available(macOS 14.0, *) {
            BgRemoveMainView(columnVisibility: $columnVisibility)
        } else {
            BgRemoveUnavailableView()
        }
    }
}

// MARK: - macOS 13 locked screen

private struct BgRemoveUnavailableView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(spacing: 8) {
                Text(LocalizedStringKey("bgremove.unavailable.title"))
                    .font(.system(size: 18, weight: .semibold))
                Text(LocalizedStringKey("bgremove.unavailable.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Model

struct BgRemoveItem: Identifiable {
    let id = UUID()
    let url: URL
    let original: NSImage
    var result: NSImage? = nil
    var isProcessing: Bool = false
    var error: String? = nil

    var fileName: String { url.lastPathComponent }
    var fileSizeString: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Main View (macOS 14+)

@available(macOS 14.0, *)
private struct BgRemoveMainView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver
    @Environment(\.colorScheme) private var colorScheme

    @State private var isDropTargeted = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    private var readyCount: Int { appState.bgRemoveItems.filter { $0.result != nil }.count }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Animated content area (ConvertImageView gibi — toolbar altta)
                Group {
                    if let id = appState.bgRemovePreviewItemID,
                       let item = appState.bgRemoveItems.first(where: { $0.id == id }) {
                        inlinePreview(item: item)
                    } else if appState.bgRemoveItems.isEmpty {
                        dropZone
                    } else {
                        itemGridWithBottomBar
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.18), value: appState.bgRemovePreviewItemID != nil)
            }

            Divider()
            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .onChange(of: appState.bgRemoveFeatherRadius) { _ in
            guard !appState.bgRemoveItems.isEmpty else { return }
            Task { await reprocessAll() }
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

    // MARK: - Inline Preview (Before / After split)

    @ViewBuilder
    private func inlinePreview(item: BgRemoveItem) -> some View {
        VStack(spacing: 0) {
            // Info bar — same layout as ConvertImageView
            HStack(spacing: 12) {
                Image(systemName: "person.and.background.dotted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.fileSizeString)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { appState.bgRemovePreviewItemID = nil }
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

            // Before / After canvases
            HStack(spacing: 0) {
                // Before — original image fills the pane
                ZStack {
                    Color(NSColor.underPageBackgroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Image(nsImage: item.original)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 9, weight: .medium))
                        Text(LocalizedStringKey("bgremove.before"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(10)
                }

                Divider()

                // After — checkerboard fills the pane, result on top
                ZStack {
                    CheckerboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let result = item.result {
                        Image(nsImage: result)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if item.isProcessing {
                        ProgressView().controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .medium))
                        Text(LocalizedStringKey("bgremove.after"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        Button { openFilePicker() } label: {
            VStack(spacing: 16) {
                Image(systemName: "person.and.background.dotted")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                VStack(spacing: 6) {
                    Text(LocalizedStringKey("bgremove.drop.title"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(LocalizedStringKey("bgremove.drop.subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
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
                    isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .padding(24)
        )
        .onDrop(of: [UTType.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Item grid + Bottom bar (ConvertImageView yapısı — butonlar altta, tıklanabilir)
    private var itemGridWithBottomBar: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 520), spacing: 16)], spacing: 16) {
                    ForEach($appState.bgRemoveItems) { $item in
                        BgRemoveCard(
                            item: $item,
                            onRemove: { removeItem(item) },
                            onTap: {
                                if item.result != nil {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        appState.bgRemovePreviewItemID = item.id
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [UTType.image], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            Divider()

            // Bottom Action Bar — orta alanın altında ortalanmış
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                Button {
                    appState.bgRemoveItems = []
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                        Text(LocalizedStringKey("convert.clearAll"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.primary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .handCursor()

                Button {
                    openFilePicker()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(LocalizedStringKey("convert.addMore"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .handCursor()

                Spacer(minLength: 0)

                if appState.bgRemoveItems.contains(where: { $0.isProcessing }) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(LocalizedStringKey("bgremove.processing"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Inspector

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(LanguageManager.shared.string("bgremove.settings.title"))
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                inspectorSection("bgremove.settings.format") {
                    Picker("", selection: $appState.bgRemoveFormat) {
                        ForEach(BgRemoveFormat.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                inspectorSection("bgremove.settings.targetFolder") {
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
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                        } else {
                            Text("convert.settings.noFolder")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.red.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.2), lineWidth: 1))
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

                inspectorSection("bgremove.settings.refine") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(LocalizedStringKey("bgremove.settings.feather"), isOn: Binding(
                            get: { appState.bgRemoveFeatherRadius > 0 },
                            set: { appState.bgRemoveFeatherRadius = $0 ? 1.5 : 0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        if appState.bgRemoveFeatherRadius > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(LocalizedStringKey("bgremove.settings.featherAmount"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f", appState.bgRemoveFeatherRadius))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                                Slider(value: $appState.bgRemoveFeatherRadius, in: 0.5...8.0, step: 0.5)
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    Button {
                        Task { await saveAll() }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text(readyCount > 0
                                 ? String(format: NSLocalizedString("bgremove.save.count", comment: ""), readyCount)
                                 : NSLocalizedString("bgremove.save.all", comment: ""))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(readyCount == 0 || appState.targetFolder == nil)

                }
                .padding(16)
            }
        }
        .background(Material.bar)
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .bmp, .tiff]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        addImages(urls: panel.urls)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                if let url = item as? URL { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { addImages(urls: urls) }
        return true
    }

    private func addImages(urls: [URL]) {
        let newItems: [BgRemoveItem] = urls.compactMap { url in
            guard let img = NSImage(contentsOf: url) else { return nil }
            return BgRemoveItem(url: url, original: img)
        }
        appState.bgRemoveItems.append(contentsOf: newItems)
        Task { await processAll(newItems) }
    }

    @MainActor
    private func processAll(_ newItems: [BgRemoveItem]) async {
        appState.processingMenuItem = .bgRemove
        defer { appState.processingMenuItem = nil }
        for item in newItems {
            guard let idx = appState.bgRemoveItems.firstIndex(where: { $0.id == item.id }) else { continue }
            appState.bgRemoveItems[idx].isProcessing = true

            guard let cg = item.original.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                appState.bgRemoveItems[idx].isProcessing = false
                continue
            }

            do {
                let resultCG = try await BgRemoveEngine.shared.removeBackground(
                    from: cg, featherRadius: appState.bgRemoveFeatherRadius
                )
                appState.bgRemoveItems[idx].result = NSImage(cgImage: resultCG,
                                            size: NSSize(width: resultCG.width, height: resultCG.height))
            } catch {
                appState.bgRemoveItems[idx].error = error.localizedDescription
            }
            appState.bgRemoveItems[idx].isProcessing = false
        }
    }

    @MainActor
    private func reprocessAll() async {
        appState.processingMenuItem = .bgRemove
        defer { appState.processingMenuItem = nil }
        let snapshot = appState.bgRemoveItems
        for item in snapshot {
            guard let idx = appState.bgRemoveItems.firstIndex(where: { $0.id == item.id }) else { continue }
            appState.bgRemoveItems[idx].isProcessing = true
            appState.bgRemoveItems[idx].result = nil
            guard let cg = item.original.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                appState.bgRemoveItems[idx].isProcessing = false
                continue
            }
            do {
                let resultCG = try await BgRemoveEngine.shared.removeBackground(
                    from: cg, featherRadius: appState.bgRemoveFeatherRadius
                )
                appState.bgRemoveItems[idx].result = NSImage(cgImage: resultCG,
                                            size: NSSize(width: resultCG.width, height: resultCG.height))
            } catch {
                appState.bgRemoveItems[idx].error = error.localizedDescription
            }
            appState.bgRemoveItems[idx].isProcessing = false
        }
    }

    private func removeItem(_ item: BgRemoveItem) {
        appState.bgRemoveItems.removeAll { $0.id == item.id }
    }

    @MainActor
    private func saveAll() async {
        guard let folder = appState.targetFolder else { return }
        var savedCount = 0
        for item in appState.bgRemoveItems where item.result != nil {
            guard let result = item.result,
                  let tiff = result.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { continue }

            let baseName = item.url.deletingPathExtension().lastPathComponent
            let outputURL = folder.appendingPathComponent("\(baseName)_nobg.\(appState.bgRemoveFormat.ext)")

            switch appState.bgRemoveFormat {
            case .png:
                if let data = rep.representation(using: .png, properties: [:]),
                   (try? data.write(to: outputURL)) != nil { savedCount += 1 }
            case .webp:
                if let cg = result.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   (try? await CometImageCodec.shared.convert(cgImage: cg, outputURL: outputURL, format: .webp, quality: CodecQuality(value: 90))) != nil {
                    savedCount += 1
                }
            case .avif:
                if let cg = result.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   (try? await CometImageCodec.shared.convert(cgImage: cg, outputURL: outputURL, format: .avif, quality: CodecQuality(value: 85))) != nil {
                    savedCount += 1
                }
            }
        }

        if savedCount > 0 {
            alertMessage = String(format: NSLocalizedString("alert.success.message.image", comment: ""), folder.path)
            showSuccessAlert = true
        }
    }
}

// MARK: - Before/After Card

@available(macOS 14.0, *)
private struct BgRemoveCard: View {
    @Binding var item: BgRemoveItem
    let onRemove: () -> Void
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Before / After panels
            HStack(spacing: 2) {
                // Before
                ZStack(alignment: .topLeading) {
                    Image(nsImage: item.original)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()

                    Text(LocalizedStringKey("bgremove.before"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
                .frame(maxWidth: .infinity)

                // After
                ZStack(alignment: .topLeading) {
                    if let result = item.result {
                        ZStack {
                            CheckerboardView()
                            Image(nsImage: result)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipped()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onTap() }
                        .handCursor()
                    } else if item.isProcessing {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .overlay(ProgressView().controlSize(.regular))
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                    } else {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                    }

                    Text(LocalizedStringKey("bgremove.after"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)

                    // X butonu sağ üst
                    VStack {
                        HStack {
                            Spacer()
                            Button { onRemove() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(Color.black.opacity(0.55))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .handCursor()
                            .padding(6)
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(item.fileSizeString)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)

                    if item.result != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 9))
                            Text(LocalizedStringKey("bgremove.preview.ready"))
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.accentColor)
                    } else if item.isProcessing {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text(LocalizedStringKey("bgremove.processing"))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                        }
                    } else if let err = item.error {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.red)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Checkerboard (şeffaflık göstergesi)

struct CheckerboardView: NSViewRepresentable {
    func makeNSView(context: Context) -> CheckerNSView { CheckerNSView() }
    func updateNSView(_ nsView: CheckerNSView, context: Context) {}
}

class CheckerNSView: NSView {
    override func draw(_ rect: NSRect) {
        let size: CGFloat = 8
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colorA = isDark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.75, alpha: 1)
        let colorB = isDark ? NSColor(white: 0.30, alpha: 1) : NSColor(white: 0.90, alpha: 1)
        for row in 0...Int(rect.height / size) {
            for col in 0...Int(rect.width / size) {
                ((row + col) % 2 == 0 ? colorA : colorB).setFill()
                NSRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size).fill()
            }
        }
    }
}

// MARK: - Format enum

enum BgRemoveFormat: String, CaseIterable, Identifiable {
    case png, webp, avif
    var id: String { rawValue }
    var label: String {
        switch self {
        case .png: return "PNG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        }
    }
    var ext: String { rawValue }
}
