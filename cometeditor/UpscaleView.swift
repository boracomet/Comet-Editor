//
//  UpscaleView.swift
//  cometeditor
//
//  Resim dönüştürme sayfasına benzer: sürükle-bırak, sağ panel ayarları, NCNN upscale.
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
    @State private var isProcessing = false
    @State private var progressLabel: String = ""
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorAlertMessage: String = ""
    @State private var isDropTargeted = false
    @State private var isWrongTypeDrop = false
    @State private var wrongTypeTask: Task<Void, Never>? = nil

    @State private var previewItem: ImageItem?
    @State private var previewFullImage: NSImage?
    @State private var previewUpscaledImage: NSImage?
    @State private var previewScale: UpscaleScale = .x4
    @State private var isPreviewUpscaling = false
    @State private var previewProgressPercent: Int = 0
    @State private var previewZoom: CGFloat = 1.0
    @State private var previewOffset: CGSize = .zero
    @State private var previewImageFrame: CGSize = .zero
    @State private var beforeAfterRatio: CGFloat = 0.5
    @State private var isSavingPreview = false
    @AppStorage("comet.upscale.autoSavePreview") private var autoSaveAfterPreview = false

    private var items: [ImageItem] { appState.upscaleImages }

    var body: some View {
        HStack(spacing: 0) {
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

            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .onChange(of: previewItem) { item in
            guard let item else {
                previewFullImage = nil
                previewUpscaledImage = nil
                return
            }
            previewUpscaledImage = nil
            beforeAfterRatio = 0.5
            previewScale = selectedScale
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
        .alert(LocalizedStringKey("alert.error.title"), isPresented: $showErrorAlert) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
        } message: {
            Text(errorAlertMessage)
        }
        .onDisappear { wrongTypeTask?.cancel() }
    }

    // MARK: - Preview (Before / After)

    private var inlinePreview: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                if let item = previewItem {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(item.dimensionsString.isEmpty ? item.fileSizeString : "\(item.fileSizeString) · \(item.dimensionsString)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                // Scale picker in header
                Picker("", selection: $previewScale) {
                    ForEach(UpscaleScale.allCases) { scale in
                        Text(scale.label).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)

                Button {
                    runPreviewUpscale()
                } label: {
                    HStack(spacing: 4) {
                        if isPreviewUpscaling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(languageManager.string("upscale.preview.run"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isPreviewUpscaling || previewItem == nil)

                Button {
                    savePreviewResult()
                } label: {
                    HStack(spacing: 4) {
                        if isSavingPreview {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(languageManager.string("upscale.preview.save"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSavingPreview || previewUpscaledImage == nil || previewItem == nil)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        previewItem = nil
                        previewFullImage = nil
                        previewUpscaledImage = nil
                        previewZoom = 1.0
                        previewOffset = .zero
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

            // Before / After area
            GeometryReader { containerGeo in
                ZStack {
                    Color(NSColor.underPageBackgroundColor)

                    if previewFullImage == nil && previewItem?.image == nil {
                        ProgressView().controlSize(.large)
                    } else if let upscaled = previewUpscaledImage, let original = previewFullImage ?? previewItem?.image {
                        beforeAfterComparison(original: original, upscaled: upscaled, containerSize: containerGeo.size)
                    } else if let nsImage = previewFullImage ?? previewItem?.image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(previewZoom)
                            .offset(previewOffset)
                            .allowsHitTesting(false)

                        if !isPreviewUpscaling {
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
                        }
                    }

                    if isPreviewUpscaling {
                        Color.black.opacity(0.3)
                        VStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            Text(languageManager.string("upscale.preview.processing"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                            Text("\(previewProgressPercent)%")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    @ViewBuilder
    private func beforeAfterComparison(original: NSImage, upscaled: NSImage, containerSize: CGSize) -> some View {
        let imgW = original.representations.first.map { CGFloat($0.pixelsWide) } ?? original.size.width
        let imgH = original.representations.first.map { CGFloat($0.pixelsHigh) } ?? original.size.height
        let imgAspect = imgW / max(1, imgH)
        let containerAspect = containerSize.width / max(1, containerSize.height)
        let displaySize: CGSize = {
            if imgAspect > containerAspect {
                let w = containerSize.width
                return CGSize(width: w, height: w / imgAspect)
            } else {
                let h = containerSize.height
                return CGSize(width: h * imgAspect, height: h)
            }
        }()

        ZStack {
            Color(NSColor.underPageBackgroundColor)
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
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
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let relX = value.location.x / max(1, displaySize.width)
                                beforeAfterRatio = max(0.05, min(0.95, relX))
                            }
                    )
                    .handCursor()
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private func runPreviewUpscale() {
        guard let item = previewItem else { return }
        isPreviewUpscaling = true
        previewProgressPercent = 0
        let scale = previewScale

        Task.detached(priority: .userInitiated) {
            let (url, accessed) = item.securityScopedURL()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let fm = FileManager.default
            let tmpOut = fm.temporaryDirectory
                .appendingPathComponent("comet_preview_\(UUID().uuidString).png")

            do {
                try await UpscaleEngine.upscale(inputURL: url, outputURL: tmpOut, scale: scale) { pct in
                    Task { @MainActor in
                        previewProgressPercent = pct
                    }
                }

                let resultImage: NSImage? = {
                    if let img = NSImage(contentsOf: tmpOut) {
                        return img
                    }
                    guard let src = CGImageSourceCreateWithURL(tmpOut as CFURL, nil),
                          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
                    let rep = NSBitmapImageRep(cgImage: cg)
                    let img = NSImage(size: rep.size)
                    img.addRepresentation(rep)
                    return img
                }()
                try? fm.removeItem(at: tmpOut)

                await MainActor.run {
                    guard let resultImage else {
                        isPreviewUpscaling = false
                        previewProgressPercent = 0
                        errorAlertMessage = String(localized: "upscale.preview.loadFailed")
                        showErrorAlert = true
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        previewUpscaledImage = resultImage
                        beforeAfterRatio = 0.5
                    }
                    isPreviewUpscaling = false
                    previewProgressPercent = 0
                    if UserDefaults.standard.bool(forKey: "comet.upscale.autoSavePreview") {
                        savePreviewResult()
                    }
                }
            } catch {
                try? fm.removeItem(at: tmpOut)
                await MainActor.run {
                    isPreviewUpscaling = false
                    previewProgressPercent = 0
                    errorAlertMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private static func previewImageData(from image: NSImage, format: UpscaleOutputFormat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
    }

    private func savePreviewResult() {
        guard let image = previewUpscaledImage, let item = previewItem else { return }
        guard let folder = appState.targetFolder else {
            errorAlertMessage = String(localized: "upscale.preview.saveNeedFolder")
            showErrorAlert = true
            return
        }
        isSavingPreview = true
        let fmt = outputFormat
        let base = item.url.deletingPathExtension().lastPathComponent
        Task { @MainActor in
            defer { isSavingPreview = false }
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            guard let data = Self.previewImageData(from: image, format: fmt) else {
                errorAlertMessage = String(localized: "upscale.preview.saveFailed")
                showErrorAlert = true
                return
            }
            var outURL = folder.appendingPathComponent("\(base)_upscaled_preview.\(fmt.fileExtension)")
            var n = 1
            while FileManager.default.fileExists(atPath: outURL.path) {
                n += 1
                outURL = folder.appendingPathComponent("\(base)_upscaled_preview_\(n).\(fmt.fileExtension)")
            }
            do {
                try data.write(to: outURL)
                showSuccessAlert = true
                CometAnalytics.shared.trackEvent(page: "upscaleImage", eventType: .imageUpscaled, metadata: ["previewSave": "1"])
            } catch {
                errorAlertMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func clampedOffset(_ offset: CGSize) -> CGSize {
        let maxX = max(0, previewImageFrame.width * (previewZoom - 1) / 2)
        let maxY = max(0, previewImageFrame.height * (previewZoom - 1) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }

    // MARK: - Main

    @ViewBuilder
    private var mainContentArea: some View {
        if items.isEmpty {
            emptyDropZone
        } else {
            imageGrid
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

    private var imageGrid: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    let columnCount = max(2, Int(geo.size.width / 240))
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            imageGridItem(item)
                        }
                    }
                    .padding(24)
                }
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

    private func imageGridItem(_ item: ImageItem) -> some View {
        GeometryReader { geo in
            imageGridItemContent(item: item, geo: geo)
        }
        .frame(height: 180)
    }

    @ViewBuilder
    private func imageGridItemContent(item: ImageItem, geo: GeometryProxy) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let nsImage = item.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { previewItem = item }
            }
            .handCursor()
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.dimensionsString.isEmpty ? item.fileSizeString : "\(item.fileSizeString) · \(item.dimensionsString)")
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
                .allowsHitTesting(false)
            }

            Button {
                appState.upscaleImages.removeAll(where: { $0.id == item.id })
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

    // MARK: - Inspector

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(languageManager.string("upscale.settings.title"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                inspectorSection("upscale.settings.model") {
                    HStack {
                        Text(languageManager.string("upscale.model.cometStandard"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                }

                Divider()

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

                Divider()

                inspectorSection("upscale.settings.outputFormat") {
                    Picker("", selection: $outputFormat) {
                        Text("PNG").tag(UpscaleOutputFormat.png)
                        Text("JPEG").tag(UpscaleOutputFormat.jpeg)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Divider()

                inspectorSection("upscale.preview.saveSettings") {
                    Toggle(isOn: $autoSaveAfterPreview) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(languageManager.string("upscale.preview.autoSave"))
                                .font(.system(size: 13, weight: .medium))
                            Text(languageManager.string("upscale.preview.autoSaveHint"))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Divider()

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

                if !UpscaleEngine.isBackendAvailable() {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(LocalizedStringKey("upscale.backend.missing.hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(16)
                }

                Divider()

                VStack {
                    Button {
                        isProcessing = true
                        progressLabel = ""
                        Task { await performUpscale() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                if progressLabel.isEmpty {
                                    Text(LocalizedStringKey("video.processing"))
                                } else {
                                    Text(progressLabel)
                                }
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("upscale.runButton")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        appState.targetFolder == nil
                        || items.isEmpty
                        || isProcessing
                        || !UpscaleEngine.isBackendAvailable()
                    )
                }
                .padding(16)
            }
        }
        .background(Material.bar)
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

    // MARK: - Upscale

    private func performUpscale() async {
        guard let targetFolder = appState.targetFolder else { return }
        appState.processingMenuItem = .upscaleImage
        defer {
            isProcessing = false
            appState.processingMenuItem = nil
        }

        let list = items
        let scale = selectedScale
        let fmt = outputFormat
        var success = 0
        var errors: [String] = []
        let total = list.count

        let accessedOut = targetFolder.startAccessingSecurityScopedResource()
        defer { if accessedOut { targetFolder.stopAccessingSecurityScopedResource() } }

        for (index, item) in list.enumerated() {
            await MainActor.run {
                progressLabel = "\(index + 1)/\(total)"
            }

            let (inputURL, accessedIn) = item.securityScopedURL()
            defer { if accessedIn { inputURL.stopAccessingSecurityScopedResource() } }

            let base = inputURL.deletingPathExtension().lastPathComponent
            let ext = fmt.fileExtension
            var outURL = targetFolder.appendingPathComponent("\(base)_upscaled.\(ext)")
            if FileManager.default.fileExists(atPath: outURL.path) {
                outURL = targetFolder.appendingPathComponent("\(base)_upscaled_\(index + 1).\(ext)")
            }

            do {
                try await UpscaleEngine.upscale(inputURL: inputURL, outputURL: outURL, scale: scale)
                success += 1
            } catch {
                errors.append("\(inputURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            if success > 0 {
                showSuccessAlert = true
                CometAnalytics.shared.trackEvent(page: "upscaleImage", eventType: .imageUpscaled, metadata: ["count": "\(success)"])
            }
            if !errors.isEmpty {
                errorAlertMessage = errors.joined(separator: "\n")
                showErrorAlert = true
            } else if success == 0 {
                errorAlertMessage = String(localized: "upscale.error.none")
                showErrorAlert = true
            }
        }
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
