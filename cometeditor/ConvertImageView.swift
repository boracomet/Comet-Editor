//
//  ConvertImageView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isProcessing = false
    @State private var showSuccessAlert = false
    @State private var isDropTargeted = false
    @Environment(\.colorScheme) private var colorScheme

    // Preview Image Modal
    @State private var previewItem: ImageItem?

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
                if let nsImage = previewItem?.image {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                previewItem = nil
                            }
                        }

                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .padding(60)
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                previewItem = nil
                            }
                        }

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
                Text(String(format: NSLocalizedString("alert.success.message.image", comment: ""), path))
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
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Color.secondary.opacity(0.6))

                Text("convert.drop.title")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.primary)

                Text("convert.drop.subtitle")
                    .font(.system(size: 13))
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

    private var imageGrid: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)], spacing: 20) {
                    ForEach(appState.selectedImages) { item in
                        imageGridItem(item)
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
        VStack(alignment: .leading, spacing: 8) {
            // Image Box
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
                        appState.selectedImages.removeAll(where: { $0.id == item.id })
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
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(item.fileSizeString) \(item.dimensionsString)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
        }
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
                inspectorSection("convert.settings.format") {
                    Picker("", selection: $selectedFormat) {
                        ForEach(ImageFormat.allCases) { format in
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

                // Convert Button
                VStack {
                    Button {
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

    // MARK: - Conversion Logic
    private func performConversion() async {
        guard let folderURL = appState.targetFolder else { return }

        isProcessing = true

        // Parse scale selection
        var mappedScaling: Double? = nil
        if scaleEnabled {
            switch scaleSelection {
            case "%75": mappedScaling = 0.75
            case "%50": mappedScaling = 0.50
            case "%25": mappedScaling = 0.25
            default: mappedScaling = 1.0 // Original
            }
        }

        // Parse custom width/height
        var mappedSize: CGSize? = nil
        if resizeEnabled {
            let w = Double(customWidth) ?? 0
            let h = Double(customHeight) ?? 0
            mappedSize = CGSize(width: w, height: h)
        }

        // PARALLEL PROCESSING - Process all images concurrently
        await withTaskGroup(of: Result<URL, Error>.self) { group in
            for item in appState.selectedImages {
                group.addTask {
                    do {
                        let result = try await ImageProcessor.shared.processImage(
                            sourceURL: item.url,
                            destinationFolder: folderURL,
                            format: selectedFormat,
                            quality: quality,
                            scaling: mappedScaling,
                            customSize: mappedSize,
                            preserveMetadata: metadataEnabled
                        )
                        return .success(result)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            // Collect results
            var hasError = false
            for await result in group {
                if case .failure(let error) = result {
                    print("Failed to convert image: \(error.localizedDescription)")
                    hasError = true
                }
            }

            isProcessing = false
            if !hasError {
                showSuccessAlert = true
            }
        }
    }

    // MARK: - Helper Methods
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            let supportedTypes: [UTType] = [.image, .rawImage,
                                          UTType("com.adobe.photoshop-image")!,
                                          UTType("com.adobe.illustrator.ai-image")!,
                                          UTType("com.adobe.encapsulated-postscript")!]

            let isSupported = supportedTypes.contains { type in
                provider.hasItemConformingToTypeIdentifier(type.identifier)
            }

            if isSupported || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.loadImages(from: [url])
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
        panel.allowedContentTypes = [.image, .rawImage,
                                   UTType("com.adobe.photoshop-image")!,
                                   UTType("com.adobe.illustrator.ai-image")!,
                                   UTType("com.adobe.encapsulated-postscript")!]

        if panel.runModal() == .OK {
            loadImages(from: panel.urls)
        }
    }

    private func loadImages(from urls: [URL]) {
        for url in urls {
            if appState.selectedImages.contains(where: { $0.url == url }) { continue }

            var fileSizeStr = "0 KB"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useAll]
                formatter.countStyle = .file
                fileSizeStr = formatter.string(fromByteCount: size)
            }

            var dimStr = ""
            var nsImage: NSImage? = nil
            if let img = NSImage(contentsOf: url) {
                nsImage = img
                dimStr = "- \(Int(img.size.width))x\(Int(img.size.height))"
            }

            let item = ImageItem(url: url, image: nsImage, fileSizeString: fileSizeStr, dimensionsString: dimStr)
            appState.selectedImages.append(item)
        }
    }
}

// MARK: - Image Format
enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, webp, avif, bmp, heif, tiff, gif

    var id: String { rawValue }

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
