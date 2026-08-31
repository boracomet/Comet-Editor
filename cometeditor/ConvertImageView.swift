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
    @State private var watermarkText: String = ""
    @State private var watermarkPosition: WatermarkPosition = .bottomRight
    @State private var watermarkScale: Double = 0.15
    @State private var watermarkOpacity: Double = 0.8
    @State private var watermarkColorOverlay: WatermarkColorOverlay = .none
    @State private var watermarkTileMode = false
    @State private var watermarkRotation: Double = 0
    @State private var showWatermarkSheet = false
    @State private var lastWatermarkPreviewID: UUID?

    private var hasWatermarkContent: Bool {
        watermarkImage != nil || !WatermarkStamper.trimmedText(watermarkText).isEmpty
    }

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
        .onAppear {
            applyPendingHomeQuickImagePresetIfNeeded()
            // View recreate (sekme değişimi) @State'i sıfırlardı; asılı kalsa bile footer boş kalmasın.
            if appState.isConvertingImages && appState.imageConversionTask == nil {
                appState.endImageConversion()
            }
        }
        .onChange(of: appState.pendingHomeQuickImagePreset) { newValue in
            guard newValue != nil else { return }
            applyPendingHomeQuickImagePresetIfNeeded()
        }
        .onChange(of: previewItem) { item in
            guard let item else {
                previewFullImage = nil
                return
            }
            lastWatermarkPreviewID = item.id
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
                parentText: $watermarkText,
                parentPosition: $watermarkPosition,
                parentScale: $watermarkScale,
                parentOpacity: $watermarkOpacity,
                parentColorOverlay: $watermarkColorOverlay,
                parentTileMode: $watermarkTileMode,
                parentRotation: $watermarkRotation,
                parentEnabled: $watermarkEnabled,
                images: appState.selectedImages,
                focusedItemID: previewItem?.id ?? lastWatermarkPreviewID
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

    // MARK: - Inline Preview (full-area, replaces list)
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
            imageList
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

    private var imageList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.selectedImages) { item in
                        ImageConvertListRow(
                            item: item,
                            onPreview: {
                                withAnimation(.easeInOut(duration: 0.2)) { previewItem = item }
                            },
                            onRemove: {
                                appState.selectedImages.removeAll(where: { $0.id == item.id })
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
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

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                inspectorSettings
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }
            Divider()
            convertFooter
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .inspectorPanelChrome()
    }

    private var inspectorSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
                // Format
                inspectorSection("inspector.output") {
                    InspectorMenuChip(title: selectedFormat.label, selection: $selectedFormat, options: ImageFormat.exportCases) { $0.label }
                }

                // Quality
                inspectorSection("convert.settings.quality") {
                    HStack(spacing: 8) {
                        Slider(value: $quality, in: 1...100, step: 1)
                        Text("\(Int(quality))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                // Scale
                inspectorSection("convert.settings.scale") {
                    InspectorSettingRow {
                        Text("convert.settings.enable")
                            .font(.system(size: 13))
                    } control: {
                        Toggle("", isOn: $scaleEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .onChange(of: scaleEnabled) { newValue in
                                if newValue { resizeEnabled = false }
                            }
                    }

                    if scaleEnabled {
                        InspectorCardSeparator()
                        InspectorSettingRow {
                            Text("convert.settings.scale.amount")
                                .font(.system(size: 13))
                        } control: {
                            Picker("", selection: $scaleSelection) {
                                ForEach(scaleOptions, id: \.self) { option in
                                    Text(languageManager.scaleMenuTitle(for: option))
                                        .lineLimit(1)
                                        .tag(option as String)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(minWidth: 132, maxWidth: 176)
                        }
                    }
                }

                // Resize
                inspectorSection("convert.settings.resize") {
                    InspectorSettingRow {
                        Text("convert.settings.enable")
                            .font(.system(size: 13))
                    } control: {
                        Toggle("", isOn: $resizeEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .onChange(of: resizeEnabled) { newValue in
                                if newValue { scaleEnabled = false }
                            }
                    }

                    if resizeEnabled {
                        InspectorCardSeparator()
                        InspectorSettingRow {
                            Text("convert.settings.width")
                                .font(.system(size: 13))
                        } control: {
                            TextField("px", text: $customWidth)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .frame(width: 72)
                                .controlSize(.small)
                        }
                        InspectorCardSeparator()
                        InspectorSettingRow {
                            Text("convert.settings.height")
                                .font(.system(size: 13))
                        } control: {
                            TextField("px", text: $customHeight)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .frame(width: 72)
                                .controlSize(.small)
                        }
                    }
                }

                // Metadata
                inspectorSection("meta.info") {
                    InspectorSettingRow {
                        Text("convert.settings.enable")
                            .font(.system(size: 13))
                    } control: {
                        Toggle("", isOn: $metadataEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }

                // Target Folder
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

                // Watermark
                inspectorSection("watermark.title") {
                    InspectorSettingRow {
                        Text("convert.settings.enable")
                            .font(.system(size: 13))
                    } control: {
                        Toggle("", isOn: $watermarkEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .onChange(of: watermarkEnabled) { newValue in
                                if newValue {
                                    if !hasWatermarkContent {
                                        showWatermarkSheet = true
                                    }
                                } else {
                                    watermarkImage = nil
                                    watermarkURL = nil
                                    watermarkText = ""
                                    watermarkRotation = 0
                                }
                            }
                    }

                    InspectorCardSeparator()

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
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(InspectorCardMetrics.chipFill(for: colorScheme))
                    )
                    .foregroundStyle(Color.primary)

                    if watermarkEnabled, hasWatermarkContent {
                        HStack(spacing: 8) {
                            if let wm = watermarkImage {
                                Image(nsImage: wm)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: "textformat")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                if !WatermarkStamper.trimmedText(watermarkText).isEmpty {
                                    Text(WatermarkStamper.trimmedText(watermarkText))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                } else {
                                    Text(languageManager.string(watermarkPosition.labelKey))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.primary)
                                }
                                Text("\(Int(watermarkScale * 100))% · \(Int(watermarkOpacity * 100))% · \(Int(watermarkRotation))°")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Button {
                                watermarkEnabled = false
                                watermarkImage = nil
                                watermarkURL = nil
                                watermarkText = ""
                                watermarkRotation = 0
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .handCursor()
                        }
                    }
                }
                .onChange(of: showWatermarkSheet) { isShowing in
                    if !isShowing && !hasWatermarkContent {
                        watermarkEnabled = false
                    }
                }
        }
    }

    /// Sticky footer: Dönüştür / Durdur inspector kaydırılınca ekrandan düşmesin.
    private var convertFooter: some View {
        VStack(spacing: 8) {
            Button {
                startImageConversion()
            } label: {
                HStack {
                    if appState.isConvertingImages {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        if appState.imageConversionProgress.isEmpty {
                            Text(LocalizedStringKey("video.processing"))
                        } else {
                            Text(appState.imageConversionProgress)
                        }
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("convert.settings.convertButton")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.isConvertingImages || appState.targetFolder == nil || appState.selectedImages.isEmpty)

            if appState.isConvertingImages {
                Button {
                    appState.requestCancelImageConversion()
                } label: {
                    Text(LocalizedStringKey("convert.cancel"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func startImageConversion() {
        guard !appState.isConvertingImages, appState.imageConversionTask == nil else { return }
        guard !appState.selectedImages.isEmpty else { return }
        let task = Task { @MainActor in
            await performConversion()
        }
        appState.imageConversionTask = task
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
    @MainActor
    private func performConversion() async {
        let state = appState
        defer { state.endImageConversion() }
        guard let targetFolder = await state.resolveOutputFolder() else { return }
        if Task.isCancelled { return }

        state.isConvertingImages = true
        state.imageConversionProgress = ""
        state.processingMenuItem = .convertImage

        for i in appState.selectedImages.indices {
            appState.selectedImages[i].isCompleted = false
            appState.selectedImages[i].outputURL = nil
            appState.selectedImages[i].outputFileSizeString = nil
            appState.selectedImages[i].outputDimensionsString = nil
            appState.selectedImages[i].outputSizeDropPercent = nil
        }

        let images = appState.selectedImages
        let format = selectedFormat
        let qualityValue = Int(quality) // 1-100
        let scaleEnabledCopy = scaleEnabled
        let scaleSelectionCopy = scaleSelection
        let resizeEnabledCopy = resizeEnabled
        let customWidthCopy = customWidth
        let customHeightCopy = customHeight
        let wmEnabled = watermarkEnabled
        let wmNSImage = watermarkImage
        let wmText = watermarkText
        let wmPosition = watermarkPosition
        let wmScale = watermarkScale
        let wmOpacity = watermarkOpacity
        let wmColor = watermarkColorOverlay
        let wmTile = watermarkTileMode
        let wmRotation = watermarkRotation

        var successCount = 0
        let total = images.count

        var wasCancelled = false

        for (index, item) in images.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            state.imageConversionProgress = "\(index + 1)/\(total)"
            let (url, accessed) = item.securityScopedURL()
            let originalSizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

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
            if wmEnabled {
                var logoCG: CGImage?
                if let wmNS = wmNSImage {
                    var rect = CGRect(origin: .zero, size: wmNS.size)
                    logoCG = wmNS.cgImage(forProposedRect: &rect, context: nil, hints: nil)
                }
                if WatermarkStamper.hasContent(logo: logoCG, text: wmText),
                   let stamped = WatermarkStamper.stamp(
                    onto: cg,
                    logo: logoCG,
                    text: wmText,
                    position: wmPosition,
                    scale: wmScale,
                    opacity: wmOpacity,
                    colorOverlay: wmColor,
                    tileMode: wmTile,
                    rotationDegrees: wmRotation
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

            if Task.isCancelled {
                wasCancelled = true
                break
            }

            let magickFmt = format.magickFormat
            let q = CodecQuality(value: qualityValue)
            do {
                let metrics = try await CometImageCodec.shared.convert(
                    cgImage: cg,
                    outputURL: outputURL,
                    quality: q,
                    magickFormat: magickFmt
                )
                recordConversionResult(
                    itemID: item.id,
                    outputURL: outputURL,
                    outputWidth: cg.width,
                    outputHeight: cg.height,
                    originalSizeBytes: originalSizeBytes,
                    encodedSizeBytes: metrics.outputSizeBytes
                )
                successCount += 1
            } catch is CancellationError {
                wasCancelled = true
                try? FileManager.default.removeItem(at: outputURL)
                break
            } catch CodecError.cancelled {
                wasCancelled = true
                try? FileManager.default.removeItem(at: outputURL)
                break
            } catch {
                // Bu görseli atla, diğerlerine devam et
            }
        }

        if wasCancelled || Task.isCancelled { return }

        await MainActor.run {
            if successCount > 0 {
                showSuccessAlert = true
            } else {
                showConversionError = true
            }
        }
    }

    private func recordConversionResult(
        itemID: UUID,
        outputURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        originalSizeBytes: Int64,
        encodedSizeBytes: Int
    ) {
        let attrsSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        let newSize = attrsSize > 0 ? attrsSize : Int64(encodedSizeBytes)

        var dim = (outputWidth > 0 && outputHeight > 0) ? "\(outputWidth)×\(outputHeight)" : ""
        if let src = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int,
           w > 0, h > 0 {
            dim = "\(w)×\(h)"
        } else if dim.isEmpty, let img = NSImage(contentsOf: outputURL), img.size.width > 0 {
            dim = "\(Int(img.size.width))×\(Int(img.size.height))"
        }

        let sizeStr = newSize > 0 ? ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file) : nil
        var drop: Double? = nil
        if originalSizeBytes > 0, newSize > 0 {
            drop = (1.0 - Double(newSize) / Double(originalSizeBytes)) * 100.0
        }

        if let i = appState.selectedImages.firstIndex(where: { $0.id == itemID }) {
            appState.selectedImages[i].isCompleted = true
            appState.selectedImages[i].outputURL = outputURL
            appState.selectedImages[i].outputFileSizeString = sizeStr
            appState.selectedImages[i].outputDimensionsString = dim.isEmpty ? nil : dim
            appState.selectedImages[i].outputSizeDropPercent = drop
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

// MARK: - Finder-style convert list row

private struct ImageConvertListRow: View {
    let item: ImageItem
    let onPreview: () -> Void
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

    /// Koyu arayüzde okunan, neon olmayan nane yeşili.
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
            if let pct = item.outputSizeDropPercent {
                parts.append("\(size) (\(Self.formatDropPercent(pct)))")
            } else {
                parts.append(size)
            }
        } else if let pct = item.outputSizeDropPercent {
            parts.append(Self.formatDropPercent(pct))
        }
        guard !parts.isEmpty else { return nil }
        return "→ " + parts.joined(separator: " · ")
    }

    private static func formatDropPercent(_ drop: Double) -> String {
        let absVal = abs(drop)
        let number: String
        if absVal > 0 && absVal < 10 {
            number = String(format: "%.1f", absVal)
        } else {
            number = String(format: "%.0f", absVal.rounded())
        }
        if drop > 0.049 {
            return "−\(number)%"
        } else if drop < -0.049 {
            return "+\(number)%"
        } else {
            return "0%"
        }
    }

    private var metadataLine: Text {
        let base = Text(subtitle).foregroundColor(Color.secondary)
        guard let suffix = resultSuffix else { return base }
        return base + Text(" \(suffix)").foregroundColor(resultMint)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreview) {
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
