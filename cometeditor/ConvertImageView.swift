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
    @State private var quality: Double = 80
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
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var windowState: WindowStateObserver
    @State private var isProcessing = false
    @State private var conversionProgress: String = ""
    @State private var showSuccessAlert = false
    @State private var showConversionError = false
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

    // Watermark
    @State private var watermarkEnabled = false
    @State private var watermarkImage: NSImage? = nil
    @State private var watermarkURL: URL? = nil
    @State private var watermarkPosition: WatermarkPosition = .bottomRight
    @State private var watermarkScale: Double = 0.15
    @State private var watermarkOpacity: Double = 0.8
    @State private var watermarkColorOverlay: WatermarkColorOverlay = .none
    @State private var watermarkTileMode = false
    @State private var showWatermarkSheet = false

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
        .onAppear { applyPendingHomeQuickImagePresetIfNeeded() }
        .onChange(of: appState.pendingHomeQuickImagePreset) { newValue in
            guard newValue != nil else { return }
            applyPendingHomeQuickImagePresetIfNeeded()
        }
        .onChange(of: previewItem) { item in
            guard let item else {
                previewFullImage = nil
                return
            }
            Task.detached(priority: .userInitiated) {
                let (url, accessed) = item.securityScopedURL()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let ext = url.pathExtension.lowercased()
                let fullImage: NSImage?
                if ext == "svg" || ext == "ai" {
                    fullImage = NSImage(contentsOf: url)
                } else if ext == "psd" {
                    if let nsImg = NSImage(contentsOf: url) {
                        fullImage = nsImg
                    } else {
                        let request = QLThumbnailGenerator.Request(
                            fileAt: url,
                            size: CGSize(width: 4096, height: 4096),
                            scale: 2.0,
                            representationTypes: .all
                        )
                        fullImage = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
                    }
                } else if ext == "pdf" {
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
        .alert(LocalizedStringKey("alert.error.title"), isPresented: $showConversionError) {
            Button(LocalizedStringKey("alert.ok"), role: .cancel) { }
        } message: {
            Text(LocalizedStringKey("alert.error.conversion"))
        }
        .onDisappear {
            wrongTypeTask?.cancel()
        }
        .sheet(isPresented: $showWatermarkSheet) {
            WatermarkSheet(
                parentImage: $watermarkImage,
                parentURL: $watermarkURL,
                parentPosition: $watermarkPosition,
                parentScale: $watermarkScale,
                parentOpacity: $watermarkOpacity,
                parentColorOverlay: $watermarkColorOverlay,
                parentTileMode: $watermarkTileMode,
                parentEnabled: $watermarkEnabled,
                images: appState.selectedImages
            )
            .environmentObject(languageManager)
        }
    }

    /// Ana sayfadan gelen hazır ayar (bir kez tüketilir).
    private func applyPendingHomeQuickImagePresetIfNeeded() {
        guard let preset = appState.consumePendingHomeQuickImagePreset() else { return }
        switch preset {
        case .shrinkPng:
            resizeEnabled = false
            customWidth = ""
            customHeight = ""
            scaleEnabled = true
            scaleSelection = "%50"
            quality = 90
        case .pngToWebp:
            selectedFormat = .webp
            resizeEnabled = false
            customWidth = ""
            customHeight = ""
            scaleEnabled = false
            scaleSelection = "convert.scale.original"
            quality = 85
        case .pngToAvif:
            selectedFormat = .avif
            resizeEnabled = false
            customWidth = ""
            customHeight = ""
            scaleEnabled = false
            scaleSelection = "convert.scale.original"
            quality = 80
        case .jpgToWebp:
            selectedFormat = .webp
            resizeEnabled = false
            customWidth = ""
            customHeight = ""
            scaleEnabled = false
            scaleSelection = "convert.scale.original"
            quality = 85
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
                        Text(item.dimensionsString.isEmpty ? item.fileSizeString : "\(item.fileSizeString) · \(item.dimensionsString)")
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
            imageGridItemContent(item: item, geo: geo)
        }
        .frame(height: 180)
    }

    @ViewBuilder
    private func imageGridItemContent(item: ImageItem, geo: GeometryProxy) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Group {
                    if let nsImage = item.image {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.secondary.opacity(0.2)
                    }
                }

                if watermarkEnabled, let wm = watermarkImage {
                    WatermarkOverlayView(
                        watermarkImage: wm,
                        containerSize: geo.size,
                        scale: watermarkScale,
                        opacity: watermarkOpacity,
                        position: watermarkPosition,
                        colorOverlay: watermarkColorOverlay,
                        tileMode: watermarkTileMode
                    )
                    .allowsHitTesting(false)
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

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
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
                        Slider(value: $quality, in: 1...100, step: 1)
                        Text("\(Int(quality))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 36, alignment: .trailing)
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
                                    Text(option.hasPrefix("convert.") ? languageManager.string(option) : option)
                                        .tag(option as String)
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
                            pickFolder { url in
    appState.handleFolderSelected(url)
    appState.targetFolder = url
}
                        }
                        .controlSize(.small)
                    }
                }

                Divider()

                // Watermark Section
                VStack(spacing: 10) {
                    Button {
                        showWatermarkSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: watermarkEnabled ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 12))
                            Text(languageManager.string("watermark.button"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .handCursor()
                    .tint(watermarkEnabled ? .green : nil)

                    if watermarkEnabled, let wm = watermarkImage {
                        HStack(spacing: 8) {
                            Image(nsImage: wm)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(languageManager.string(watermarkPosition.labelKey))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                Text("\(Int(watermarkScale * 100))% · \(Int(watermarkOpacity * 100))%")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Button {
                                watermarkEnabled = false
                                watermarkImage = nil
                                watermarkURL = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .handCursor()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Convert Button
                VStack {
                    Button {
                        isProcessing = true
                        conversionProgress = ""
                        Task { await performConversion() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text(conversionProgress.isEmpty ? LocalizedStringKey("video.processing") : LocalizedStringKey(conversionProgress))
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

    // MARK: - Conversion Logic
    private func performConversion() async {
        guard let targetFolder = appState.targetFolder else { return }
        appState.processingMenuItem = .convertImage
        defer {
            isProcessing = false
            appState.processingMenuItem = nil
        }

        let images = appState.selectedImages
        let format = selectedFormat
        let qualityValue = Int(quality) // 1-100
        let scaleEnabledCopy = scaleEnabled
        let scaleSelectionCopy = scaleSelection
        let resizeEnabledCopy = resizeEnabled
        let customWidthCopy = customWidth
        let customHeightCopy = customHeight

        var successCount = 0
        let total = images.count

        for (index, item) in images.enumerated() {
            conversionProgress = "\(index + 1)/\(total)"
            let (url, accessed) = item.securityScopedURL()

            let ext = url.pathExtension.lowercased()

            // CGImage yükle
            var cgImage: CGImage? = nil

            if ext == "svg" || ext == "ai" {
                // macOS NSImage natively renders SVG and AI (PDF-based)
                if let nsImg = NSImage(contentsOf: url) {
                    var rect = CGRect(origin: .zero, size: nsImg.size)
                    cgImage = nsImg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
                }
            } else if ext == "psd" {
                // PSD: try NSImage first (macOS may handle it), else QuickLook
                if let nsImg = NSImage(contentsOf: url) {
                    var rect = CGRect(origin: .zero, size: nsImg.size)
                    cgImage = nsImg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
                } else {
                    let request = QLThumbnailGenerator.Request(
                        fileAt: url,
                        size: CGSize(width: 4096, height: 4096),
                        scale: 1.0,
                        representationTypes: .all
                    )
                    if let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                        cgImage = thumb.nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    }
                }
            } else if ext == "pdf" {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: CGSize(width: 4096, height: 4096),
                    scale: 1.0,
                    representationTypes: .all
                )
                if let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
                   let cg = thumb.nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    cgImage = cg
                }
            } else {
                var srcOpts: [CFString: Any] = [:]
                if ext == "jfif" || ext == "jpe" {
                    srcOpts[kCGImageSourceTypeIdentifierHint] = "public.jpeg" as CFString
                }
                if let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts as CFDictionary) {
                    cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
                }
            }

            if accessed { url.stopAccessingSecurityScopedResource() }
            guard var cg = cgImage else { continue }

            // Ölçek / Boyutlandırma
            if scaleEnabledCopy && scaleSelectionCopy != "convert.scale.original" {
                let factor: CGFloat
                switch scaleSelectionCopy {
                case "%75": factor = 0.75
                case "%50": factor = 0.50
                case "%25": factor = 0.25
                default:    factor = 1.0
                }
                let newW = max(1, Int(CGFloat(cg.width) * factor))
                let newH = max(1, Int(CGFloat(cg.height) * factor))
                if let ctx = CGContext(data: nil, width: newW, height: newH,
                                       bitsPerComponent: 8, bytesPerRow: newW * 4,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: newW, height: newH))
                    if let scaled = ctx.makeImage() { cg = scaled }
                }
            } else if resizeEnabledCopy,
                      let tw = Int(customWidthCopy), tw > 0,
                      let th = Int(customHeightCopy), th > 0 {
                if let ctx = CGContext(data: nil, width: tw, height: th,
                                       bitsPerComponent: 8, bytesPerRow: tw * 4,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
                    if let resized = ctx.makeImage() { cg = resized }
                }
            }

            // Watermark stamp
            if watermarkEnabled, let wmNS = watermarkImage {
                var rect = CGRect(origin: .zero, size: wmNS.size)
                if let wmCG = wmNS.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                   let stamped = WatermarkStamper.stamp(
                    onto: cg,
                    watermark: wmCG,
                    position: watermarkPosition,
                    scale: watermarkScale,
                    opacity: watermarkOpacity,
                    colorOverlay: watermarkColorOverlay,
                    tileMode: watermarkTileMode
                ) {
                    cg = stamped
                }
            }

            // Çıktı dosya adı — çakışmayı önle
            let baseName = url.deletingPathExtension().lastPathComponent
            let outputExt = format.fileExtension
            var outputURL = targetFolder.appendingPathComponent("\(baseName).\(outputExt)")
            if FileManager.default.fileExists(atPath: outputURL.path) {
                outputURL = targetFolder.appendingPathComponent("\(baseName)_converted.\(outputExt)")
            }

            let magickFmt = format.magickFormat
            let q = CodecQuality(value: qualityValue)
            do {
                _ = try await CometImageCodec.shared.convert(
                    cgImage: cg,
                    outputURL: outputURL,
                    quality: q,
                    magickFormat: magickFmt
                )
                successCount += 1
            } catch {
                // Bu görseli atla, diğerlerine devam et
            }
        }

        await MainActor.run {
            if successCount > 0 {
                showSuccessAlert = true
                CometAnalytics.shared.trackEvent(page: "convertImage", eventType: .imageConverted, metadata: ["count": successCount])
            } else {
                showConversionError = true
            }
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
                } else if ext0 == "psd" {
                    if let img = NSImage(contentsOf: url) {
                        nsImage = img
                        let sz = img.size
                        dimStr = sz.width > 0 ? "\(Int(sz.width))×\(Int(sz.height))" : ""
                    } else {
                        let request = QLThumbnailGenerator.Request(
                            fileAt: url,
                            size: CGSize(width: 720, height: 720),
                            scale: 2.0,
                            representationTypes: .all
                        )
                        if let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                            nsImage = thumb.nsImage
                            let sz = thumb.nsImage.size
                            dimStr = sz.width > 0 ? "\(Int(sz.width))×\(Int(sz.height))" : ""
                        }
                    }
                } else if ext0 == "pdf" {
                    let request = QLThumbnailGenerator.Request(
                        fileAt: url,
                        size: CGSize(width: 720, height: 720),
                        scale: 2.0,
                        representationTypes: .all
                    )
                    if let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                        nsImage = thumb.nsImage
                        let sz = thumb.nsImage.size
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
                    }
                }

                if accessed { url.stopAccessingSecurityScopedResource() }
                built.append(ImageItem(url: url, image: nsImage, fileSizeString: fileSizeStr, dimensionsString: dimStr, bookmarkData: bookmark))
            }

            let items = built
            await MainActor.run {
                self.appState.selectedImages.append(contentsOf: items)
            }
        }
    }
}

// MARK: - Watermark Color Overlay

enum WatermarkColorOverlay: String, CaseIterable, Identifiable {
    case none, black, darkGray, gray, lightGray, white

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .none:      return "watermark.color.none"
        case .black:     return "watermark.color.black"
        case .darkGray:  return "watermark.color.darkGray"
        case .gray:      return "watermark.color.gray"
        case .lightGray: return "watermark.color.lightGray"
        case .white:     return "watermark.color.white"
        }
    }

    var cgColor: CGColor? {
        switch self {
        case .none:      return nil
        case .black:     return CGColor(gray: 0, alpha: 1)
        case .darkGray:  return CGColor(gray: 0.33, alpha: 1)
        case .gray:      return CGColor(gray: 0.5, alpha: 1)
        case .lightGray: return CGColor(gray: 0.75, alpha: 1)
        case .white:     return CGColor(gray: 1, alpha: 1)
        }
    }

    var swiftUIColor: Color? {
        switch self {
        case .none:      return nil
        case .black:     return .black
        case .darkGray:  return Color(white: 0.33)
        case .gray:      return .gray
        case .lightGray: return Color(white: 0.75)
        case .white:     return .white
        }
    }

    var previewCircleColor: Color {
        switch self {
        case .none:      return .clear
        case .black:     return .black
        case .darkGray:  return Color(white: 0.33)
        case .gray:      return .gray
        case .lightGray: return Color(white: 0.75)
        case .white:     return .white
        }
    }
}

// MARK: - Watermark CGImage Helpers

enum WatermarkStamper {

    static func tintedImage(_ source: CGImage, color: CGColor) -> CGImage? {
        let w = source.width, h = source.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: rect, mask: source)
        ctx.setFillColor(color)
        ctx.fill(rect)
        return ctx.makeImage()
    }

    static func stamp(
        onto base: CGImage,
        watermark wm: CGImage,
        position: WatermarkPosition,
        scale: Double,
        opacity: Double,
        colorOverlay: WatermarkColorOverlay,
        tileMode: Bool
    ) -> CGImage? {
        let imgW = CGFloat(base.width)
        let imgH = CGFloat(base.height)

        let finalWM: CGImage
        if let tintColor = colorOverlay.cgColor, let tinted = tintedImage(wm, color: tintColor) {
            finalWM = tinted
        } else {
            finalWM = wm
        }

        guard let ctx = CGContext(
            data: nil, width: Int(imgW), height: Int(imgH),
            bitsPerComponent: 8, bytesPerRow: Int(imgW) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        ctx.draw(base, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

        let shortSide = min(imgW, imgH)
        let wmAspect = CGFloat(finalWM.width) / max(CGFloat(finalWM.height), 1)
        let wmDrawW = shortSide * scale
        let wmDrawH = wmDrawW / max(wmAspect, 0.01)
        let wmSize = CGSize(width: wmDrawW, height: wmDrawH)

        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setAlpha(CGFloat(opacity))

        if tileMode {
            let spacingX = wmDrawW * 1.6
            let spacingY = wmDrawH * 1.6
            var row = 0
            var y = -wmDrawH * 0.5
            while y < imgH + wmDrawH {
                let xOffset: CGFloat = (row % 2 == 0) ? 0 : spacingX * 0.5
                var x = -wmDrawW * 0.5 + xOffset
                while x < imgW + wmDrawW {
                    ctx.draw(finalWM, in: CGRect(x: x, y: y, width: wmDrawW, height: wmDrawH))
                    x += spacingX
                }
                y += spacingY
                row += 1
            }
        } else {
            let origin = position.origin(imageSize: CGSize(width: imgW, height: imgH), watermarkSize: wmSize)
            ctx.draw(finalWM, in: CGRect(origin: origin, size: wmSize))
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()

        return ctx.makeImage()
    }
}

// MARK: - Watermark Position

enum WatermarkPosition: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .topLeft:      return "watermark.pos.topLeft"
        case .topCenter:    return "watermark.pos.topCenter"
        case .topRight:     return "watermark.pos.topRight"
        case .centerLeft:   return "watermark.pos.centerLeft"
        case .center:       return "watermark.pos.center"
        case .centerRight:  return "watermark.pos.centerRight"
        case .bottomLeft:   return "watermark.pos.bottomLeft"
        case .bottomCenter: return "watermark.pos.bottomCenter"
        case .bottomRight:  return "watermark.pos.bottomRight"
        }
    }

    var icon: String {
        switch self {
        case .topLeft:      return "arrow.up.left"
        case .topCenter:    return "arrow.up"
        case .topRight:     return "arrow.up.right"
        case .centerLeft:   return "arrow.left"
        case .center:       return "circle.fill"
        case .centerRight:  return "arrow.right"
        case .bottomLeft:   return "arrow.down.left"
        case .bottomCenter: return "arrow.down"
        case .bottomRight:  return "arrow.down.right"
        }
    }

    func origin(imageSize: CGSize, watermarkSize: CGSize, margin: CGFloat = 0.03) -> CGPoint {
        let mx = imageSize.width * margin
        let my = imageSize.height * margin
        let ww = watermarkSize.width
        let wh = watermarkSize.height
        let cx = (imageSize.width - ww) / 2
        let cy = (imageSize.height - wh) / 2
        switch self {
        case .topLeft:      return CGPoint(x: mx, y: imageSize.height - wh - my)
        case .topCenter:    return CGPoint(x: cx, y: imageSize.height - wh - my)
        case .topRight:     return CGPoint(x: imageSize.width - ww - mx, y: imageSize.height - wh - my)
        case .centerLeft:   return CGPoint(x: mx, y: cy)
        case .center:       return CGPoint(x: cx, y: cy)
        case .centerRight:  return CGPoint(x: imageSize.width - ww - mx, y: cy)
        case .bottomLeft:   return CGPoint(x: mx, y: my)
        case .bottomCenter: return CGPoint(x: cx, y: my)
        case .bottomRight:  return CGPoint(x: imageSize.width - ww - mx, y: my)
        }
    }
}

// MARK: - Watermark Sheet

struct WatermarkSheet: View {
    @Binding var parentImage: NSImage?
    @Binding var parentURL: URL?
    @Binding var parentPosition: WatermarkPosition
    @Binding var parentScale: Double
    @Binding var parentOpacity: Double
    @Binding var parentColorOverlay: WatermarkColorOverlay
    @Binding var parentTileMode: Bool
    @Binding var parentEnabled: Bool
    let images: [ImageItem]
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var watermarkImage: NSImage? = nil
    @State private var watermarkURL: URL? = nil
    @State private var watermarkPosition: WatermarkPosition = .bottomRight
    @State private var watermarkScale: Double = 0.15
    @State private var watermarkOpacity: Double = 0.8
    @State private var watermarkColorOverlay: WatermarkColorOverlay = .none
    @State private var watermarkTileMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(languageManager.string("watermark.title"))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    dismiss()
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
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Row 1: Logo + Position side by side
                    HStack(alignment: .top, spacing: 16) {
                        // Logo picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text(languageManager.string("watermark.logo"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .textCase(.uppercase)

                            HStack(spacing: 10) {
                                if let img = watermarkImage {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 52, height: 52)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.primary.opacity(0.05))
                                        .frame(width: 52, height: 52)
                                        .overlay(
                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 18))
                                                .foregroundStyle(Color.secondary.opacity(0.5))
                                        )
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Button(languageManager.string("watermark.selectLogo")) {
                                        pickWatermarkFile()
                                    }
                                    .controlSize(.small)
                                    .handCursor()

                                    if let url = watermarkURL {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    if watermarkImage != nil {
                                        Button(languageManager.string("watermark.removeLogo")) {
                                            watermarkImage = nil
                                            watermarkURL = nil
                                        }
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.red.opacity(0.8))
                                        .buttonStyle(.plain)
                                        .handCursor()
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Position picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text(languageManager.string("watermark.position"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .textCase(.uppercase)

                            positionGrid
                        }
                    }

                    Divider()

                    // Row 2: Scale + Opacity side by side
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageManager.string("watermark.scale"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .textCase(.uppercase)

                            HStack(spacing: 6) {
                                Slider(value: $watermarkScale, in: 0.03...0.5, step: 0.01)
                                Text("\(Int(watermarkScale * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageManager.string("watermark.opacity"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .textCase(.uppercase)

                            HStack(spacing: 6) {
                                Slider(value: $watermarkOpacity, in: 0.05...1.0, step: 0.05)
                                Text("\(Int(watermarkOpacity * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Divider()

                    // Row 3: Color overlay + Tile mode side by side
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(languageManager.string("watermark.colorOverlay"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .textCase(.uppercase)

                            HStack(spacing: 4) {
                                ForEach(WatermarkColorOverlay.allCases) { overlay in
                                    Button {
                                        watermarkColorOverlay = overlay
                                    } label: {
                                        if overlay == .none {
                                            Image(systemName: "circle.slash")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.secondary)
                                                .frame(width: 26, height: 24)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .fill(watermarkColorOverlay == overlay ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .strokeBorder(watermarkColorOverlay == overlay ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                                )
                                        } else {
                                            Circle()
                                                .fill(overlay.previewCircleColor)
                                                .frame(width: 16, height: 16)
                                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                                                .frame(width: 26, height: 24)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .fill(watermarkColorOverlay == overlay ? Color.accentColor.opacity(0.2) : Color.clear)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .strokeBorder(watermarkColorOverlay == overlay ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .handCursor()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(languageManager.string("watermark.tileMode"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .textCase(.uppercase)

                            Button {
                                watermarkTileMode.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: watermarkTileMode ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(watermarkTileMode ? Color.accentColor : Color.secondary.opacity(0.5))
                                    Text(languageManager.string("watermark.tileMode.desc"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.primary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .handCursor()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Preview grid (up to 6 images)
                    if !images.isEmpty && watermarkImage != nil {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(languageManager.string("watermark.preview"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .textCase(.uppercase)

                            let previewImages = Array(images.prefix(6))
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(previewImages) { item in
                                    watermarkPreviewCell(item)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom bar
            HStack {
                Spacer()
                Button(languageManager.string("watermark.cancel")) {
                    dismiss()
                }
                .controlSize(.regular)
                .keyboardShortcut(.escape, modifiers: [])
                .handCursor()

                Button(languageManager.string("watermark.apply")) {
                    parentImage = watermarkImage
                    parentURL = watermarkURL
                    parentPosition = watermarkPosition
                    parentScale = watermarkScale
                    parentOpacity = watermarkOpacity
                    parentColorOverlay = watermarkColorOverlay
                    parentTileMode = watermarkTileMode
                    parentEnabled = watermarkImage != nil
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(watermarkImage == nil)
                .handCursor()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 580, height: 540)
        .onAppear {
            watermarkImage = parentImage
            watermarkURL = parentURL
            watermarkPosition = parentPosition
            watermarkScale = parentScale
            watermarkOpacity = parentOpacity
            watermarkColorOverlay = parentColorOverlay
            watermarkTileMode = parentTileMode
        }
    }

    // MARK: - Position Grid

    private var positionGrid: some View {
        let positions: [[WatermarkPosition]] = [
            [.topLeft, .topCenter, .topRight],
            [.centerLeft, .center, .centerRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ]
        return VStack(spacing: 4) {
            ForEach(Array(positions.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { pos in
                        Button {
                            watermarkPosition = pos
                        } label: {
                            Image(systemName: pos.icon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(watermarkPosition == pos ? Color.white : Color.primary.opacity(0.6))
                                .frame(width: 36, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(watermarkPosition == pos ? Color.accentColor : Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                }
            }
        }
    }

    // MARK: - Preview Cell

    @ViewBuilder
    private func watermarkPreviewCell(_ item: ImageItem) -> some View {
        GeometryReader { geo in
            ZStack {
                if let nsImage = item.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.secondary.opacity(0.15)
                }

                if let wm = watermarkImage {
                    WatermarkOverlayView(
                        watermarkImage: wm,
                        containerSize: geo.size,
                        scale: watermarkScale,
                        opacity: watermarkOpacity,
                        position: watermarkPosition,
                        colorOverlay: watermarkColorOverlay,
                        tileMode: watermarkTileMode
                    )
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .frame(height: 120)
    }

    // MARK: - File Picker

    private func pickWatermarkFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .svg]
        if panel.runModal() == .OK, let url = panel.url {
            watermarkURL = url
            watermarkImage = NSImage(contentsOf: url)
        }
    }
}

// MARK: - Shared Watermark Overlay View

struct WatermarkOverlayView: View {
    let watermarkImage: NSImage
    let containerSize: CGSize
    let scale: Double
    let opacity: Double
    let position: WatermarkPosition
    let colorOverlay: WatermarkColorOverlay
    let tileMode: Bool

    var body: some View {
        let wmAspect = watermarkImage.size.width / max(watermarkImage.size.height, 1)
        let wmW = containerSize.width * scale * 2
        let wmH = wmW / max(wmAspect, 0.1)
        let tintColor = colorOverlay.swiftUIColor

        if tileMode {
            let spacingX = wmW * 1.6
            let spacingY = wmH * 1.6
            Canvas { ctx, size in
                guard let resolved = ctx.resolveSymbol(id: "wm") else { return }
                var row = 0
                var y = -wmH * 0.5
                while y < size.height + wmH {
                    let xOff: CGFloat = (row % 2 == 0) ? 0 : spacingX * 0.5
                    var x = -wmW * 0.5 + xOff
                    while x < size.width + wmW {
                        ctx.draw(resolved, at: CGPoint(x: x + wmW / 2, y: y + wmH / 2))
                        x += spacingX
                    }
                    y += spacingY
                    row += 1
                }
            } symbols: {
                wmSingleImage(width: wmW, height: wmH, tintColor: tintColor)
                    .tag("wm")
            }
            .allowsHitTesting(false)
        } else {
            let pos = position
            let alignH: HorizontalAlignment = {
                switch pos {
                case .topLeft, .centerLeft, .bottomLeft: return .leading
                case .topCenter, .center, .bottomCenter: return .center
                case .topRight, .centerRight, .bottomRight: return .trailing
                }
            }()
            let alignV: VerticalAlignment = {
                switch pos {
                case .topLeft, .topCenter, .topRight: return .top
                case .centerLeft, .center, .centerRight: return .center
                case .bottomLeft, .bottomCenter, .bottomRight: return .bottom
                }
            }()

            VStack {
                if alignV == .center || alignV == .bottom { Spacer(minLength: 0) }
                HStack {
                    if alignH == .center || alignH == .trailing { Spacer(minLength: 0) }
                    wmSingleImage(width: wmW, height: wmH, tintColor: tintColor)
                    if alignH == .center || alignH == .leading { Spacer(minLength: 0) }
                }
                if alignV == .center || alignV == .top { Spacer(minLength: 0) }
            }
            .padding(containerSize.width * 0.03)
        }
    }

    @ViewBuilder
    private func wmSingleImage(width: CGFloat, height: CGFloat, tintColor: Color?) -> some View {
        if let tint = tintColor {
            Image(nsImage: watermarkImage)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .colorMultiply(tint)
                .opacity(opacity)
        } else {
            Image(nsImage: watermarkImage)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .opacity(opacity)
        }
    }
}

// MARK: - Image Format
enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, webp, avif, heic, jp2, bmp, heif, tiff, gif

    var id: String { rawValue }

    static var exportCases: [ImageFormat] { [.png, .jpeg, .webp, .avif, .heic, .jp2, .tiff, .gif] }

    var label: String {
        switch self {
        case .png:  return "PNG"
        case .jpeg: return "JPEG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        case .jp2:  return "JP2"
        case .bmp:  return "BMP"
        case .heif: return "HEIF"
        case .tiff: return "TIFF"
        case .gif:  return "GIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .jp2:  return "jp2"
        case .tiff: return "tiff"
        default:    return rawValue
        }
    }

    var magickFormat: String {
        switch self {
        case .png:  return "PNG"
        case .jpeg: return "JPEG"
        case .webp: return "WEBP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        case .jp2:  return "JP2"
        case .bmp:  return "BMP"
        case .heif: return "HEIF"
        case .tiff: return "TIFF"
        case .gif:  return "GIF"
        }
    }
}

#Preview {
    ConvertImageView(columnVisibility: .constant(.all))
        .environmentObject(GlobalAppState())
        .environmentObject(LanguageManager.shared)
        .environmentObject(WindowStateObserver())
        .frame(width: 800, height: 500)
}
