//
//  PDFEditView.swift
//  cometeditor
//
//  Created by Antigravity on 6.03.2026.
//

import SwiftUI
@preconcurrency import PDFKit
import UniformTypeIdentifiers
import CoreGraphics

// NSImage is safe to pass across concurrency boundaries for display-only use.
// macOS 14+ marks it Sendable; this wrapper silences the warning on older targets.
private struct SentImage: @unchecked Sendable { let nsImage: NSImage? }

struct PDFItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let document: PDFDocument?
    let fileSizeString: String
    var fileName: String { url.lastPathComponent }

    static func == (lhs: PDFItem, rhs: PDFItem) -> Bool { lhs.id == rhs.id }
}

struct PDFEditView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var selectedPDF: PDFItem? = nil
    @State private var currentPageIndex: Int = 0
    @State private var documentVersion: Int = 0
    @State private var isDropTargeted = false

    // Compression state
    @State private var isCompressing = false
    @State private var compressionProgress: Double = 0
    @State private var compressionTargetFolder: URL? = nil

    // Reorder modal
    @State private var showReorderModal = false

    @EnvironmentObject var appState: GlobalAppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspectorPanel
                .frame(width: 260)
        }
        .ignoresSafeArea(edges: columnVisibility == .detailOnly ? [] : .top)
        .sheet(isPresented: $showReorderModal) {
            if let pdf = selectedPDF, let document = pdf.document {
                PDFPageReorderView(document: document) { newOrder in
                    applyReorder(newOrder, for: pdf)
                }
            }
        }
    }

    // MARK: - Main Content Area
    @ViewBuilder
    private var mainContentArea: some View {
        if let pdf = selectedPDF {
            pdfViewer(pdf)
        } else {
            emptyDropZone
        }
    }

    // MARK: - PDF Viewer
    private func pdfViewer(_ pdf: PDFItem) -> some View {
        VStack(spacing: 0) {
            // Info bar — PDF name + page count centered above the page
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Text(pdf.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 400)
                    Text(String(
                        format: NSLocalizedString("pdf.page.info", comment: ""),
                        currentPageIndex + 1,
                        pdf.document?.pageCount ?? 0
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.025))

            Divider()

            // Page viewer + arrows
            ZStack {
                Color.primary.opacity(0.02)

                if let document = pdf.document {
                    PDFSinglePageView(
                        document: document,
                        pageIndex: currentPageIndex,
                        version: documentVersion
                    )
                }

                // Navigation arrows
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentPageIndex = max(0, currentPageIndex - 1)
                        }
                    } label: {
                        navArrow(systemName: "chevron.left", enabled: currentPageIndex > 0)
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .disabled(currentPageIndex == 0)
                    .padding(.leading, 16)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            currentPageIndex = min((pdf.document?.pageCount ?? 1) - 1, currentPageIndex + 1)
                        }
                    } label: {
                        let hasNext = currentPageIndex < (pdf.document?.pageCount ?? 1) - 1
                        navArrow(systemName: "chevron.right", enabled: hasNext)
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .disabled(currentPageIndex >= (pdf.document?.pageCount ?? 1) - 1)
                    .padding(.trailing, 16)
                }

                // Keyboard arrow navigation
                HStack(spacing: 0) {
                    Button("") { currentPageIndex = max(0, currentPageIndex - 1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .opacity(0).frame(width: 0, height: 0)
                    Button("") { currentPageIndex = min((pdf.document?.pageCount ?? 1) - 1, currentPageIndex + 1) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .opacity(0).frame(width: 0, height: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            thumbnailStrip(pdf)
        }
    }

    private func navArrow(systemName: String, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.primary.opacity(enabled ? 0.07 : 0.04)))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Thumbnail Strip (LazyHStack for performance)
    private func thumbnailStrip(_ pdf: PDFItem) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    if let document = pdf.document {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            PDFThumbnailCell(
                                document: document,
                                index: index,
                                isSelected: currentPageIndex == index
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    currentPageIndex = index
                                }
                            }
                            .id(index)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .id(documentVersion)
            }
            .frame(height: 108)
            .background(Color.primary.opacity(0.02))
            .mask {
                HStack(spacing: 0) {
                    // Left "imaginary line" mask
                    Rectangle()
                        .fill(LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 40)
                    
                    Rectangle()
                        .fill(Color.black)
                    
                    // Subtle right fade (optional, but keeps it symmetrical)
                    Rectangle()
                        .fill(LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.95),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 40)
                }
            }
            .onChange(of: currentPageIndex) { index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
            .onChange(of: documentVersion) { _ in
                withAnimation { proxy.scrollTo(currentPageIndex, anchor: .center) }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Empty Drop Zone
    private var emptyDropZone: some View {
        Button(action: selectFileFromFinder) {
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                Text("pdf.drop.title")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)
                Text("pdf.drop.subtitle")
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
                    isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .padding(24)
        )
        .onDrop(of: [.pdf], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { DispatchQueue.main.async { loadPDF(url: url) } }
            }
            return true
        }
    }

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header — always "Ayarlar"
                HStack {
                    Text("pdf.settings.title")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if selectedPDF != nil {
                        Button {
                            withAnimation {
                                selectedPDF = nil
                                currentPageIndex = 0
                                documentVersion = 0
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.secondary.opacity(0.5))
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                if selectedPDF == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                        Text(LocalizedStringKey("pdf.drop.title"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Text(LocalizedStringKey("pdf.drop.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .padding(.horizontal, 20)
                }

                if let pdf = selectedPDF {
                    let pageCount = pdf.document?.pageCount ?? 0

                    // Current Page
                    inspectorSection("pdf.tools.currentPage") {
                        HStack {
                            Text("\(currentPageIndex + 1) / \(pageCount)")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            HStack(spacing: 0) {
                                Button {
                                    if currentPageIndex > 0 { withAnimation { currentPageIndex -= 1 } }
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 28, height: 26)
                                }
                                .buttonStyle(.plain)
                                .disabled(currentPageIndex == 0)

                                Divider().frame(height: 16)

                                Button {
                                    if currentPageIndex < pageCount - 1 { withAnimation { currentPageIndex += 1 } }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 28, height: 26)
                                }
                                .buttonStyle(.plain)
                                .disabled(currentPageIndex >= pageCount - 1)
                            }
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                        }
                    }

                    Divider()

                    // Page Management
                    inspectorSection("pdf.tools.pageManagement") {
                        VStack(spacing: 2) {
                            toolButton(icon: "trash", title: "pdf.tools.deletePage", tint: .red) {
                                deletePage(at: currentPageIndex, from: pdf)
                            }
                            .disabled(pageCount <= 1)

                            toolButton(icon: "arrow.up.doc", title: "pdf.tools.insertBefore") {
                                insertPage(at: currentPageIndex, after: false, into: pdf)
                            }

                            toolButton(icon: "arrow.down.doc", title: "pdf.tools.insertAfter") {
                                insertPage(at: currentPageIndex, after: true, into: pdf)
                            }

                            toolButton(icon: "arrow.up.arrow.down", title: "pdf.tools.reorder") {
                                showReorderModal = true
                            }
                        }
                    }

                    Divider()

                    // PDF Actions
                    inspectorSection("pdf.tools.actions") {
                        VStack(spacing: 2) {
                            toolButton(icon: "doc.on.doc", title: "pdf.tools.merge") {
                                mergePDF(into: pdf)
                            }
                        }
                    }

                    Divider()

                    // WebP Compression
                    inspectorSection("pdf.tools.compressSection") {
                        VStack(alignment: .leading, spacing: 10) {
                            // Target folder picker
                            HStack(spacing: 8) {
                                Group {
                                    if let folder = compressionTargetFolder {
                                        Text(truncatedPath(folder.path))
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
                                }

                                Button("convert.settings.chooseFolder") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    if panel.runModal() == .OK { compressionTargetFolder = panel.url }
                                }
                                .controlSize(.small)
                            }

                            // Progress bar
                            if isCompressing {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: compressionProgress, total: 1.0)
                                        .progressViewStyle(.linear)
                                    Text("%\(Int(compressionProgress * 100))")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.secondary)
                                }
                            }

                            // Compress button
                            Button {
                                Task { await compressWithWebP(pdf) }
                            } label: {
                                HStack {
                                    if isCompressing {
                                        ProgressView().controlSize(.small)
                                        Text(LocalizedStringKey("video.processing"))
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                        Text("pdf.tools.compress")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(compressionTargetFolder == nil || isCompressing)
                        }
                    }

                    Divider()

                    // Save
                    VStack {
                        Button { savePDF(pdf) } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("pdf.tools.save")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(16)
                }
            }
        }
        .background(Material.bar)
    }

    // MARK: - Inspector Section
    private func inspectorSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func toolButton(icon: String, title: LocalizedStringKey, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(tint == .red ? tint : Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    // MARK: - PDF Operations

    private func deletePage(at index: Int, from pdf: PDFItem) {
        guard let document = pdf.document, document.pageCount > 1 else { return }
        document.removePage(at: index)
        currentPageIndex = min(index, document.pageCount - 1)
        documentVersion += 1
    }

    private func insertPage(at index: Int, after: Bool, into pdf: PDFItem) {
        guard let document = pdf.document else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }

        let insertAt = after ? index + 1 : index
        for url in panel.urls {
            guard let src = PDFDocument(url: url) else { continue }
            for i in 0..<src.pageCount {
                if let page = src.page(at: i) {
                    document.insert(page, at: insertAt + i)
                }
            }
        }
        currentPageIndex = insertAt
        documentVersion += 1
    }

    private func mergePDF(into pdf: PDFItem) {
        guard let document = pdf.document else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let src = PDFDocument(url: url) else { continue }
            for i in 0..<src.pageCount {
                if let page = src.page(at: i) {
                    document.insert(page, at: document.pageCount)
                }
            }
        }
        documentVersion += 1
    }

    /// Renders every page to a CGImage, compresses via CometImageCodec WebP,
    /// and packs the result into a new PDF — significantly reduces file size for image-heavy PDFs.
    @MainActor
    private func compressWithWebP(_ pdf: PDFItem) async {
        guard let document = pdf.document,
              let targetFolder = compressionTargetFolder else { return }

        isCompressing = true
        compressionProgress = 0
        defer { isCompressing = false }

        // Output path with counter to avoid overwrite
        let baseName = pdf.url.deletingPathExtension().lastPathComponent
        var outputURL = targetFolder.appendingPathComponent("\(baseName)_compressed.pdf")
        var counter = 1
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = targetFolder.appendingPathComponent("\(baseName)_compressed_\(counter).pdf")
            counter += 1
        }

        let dpi: CGFloat = 150.0
        var mediaBox = CGRect.zero
        guard let ctx = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else { return }

        let pageCount = document.pageCount

        for i in 0..<pageCount {
            guard !Task.isCancelled else { break }
            guard let page = document.page(at: i) else { continue }

            let bounds = page.bounds(for: .mediaBox)
            let scale = dpi / 72.0
            let pxW = Int(bounds.width * scale)
            let pxH = Int(bounds.height * scale)

            // 1. Render page to bitmap on a background thread (CGPDFPage rendering is thread-safe)
            let cgImage = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                let cs = CGColorSpaceCreateDeviceRGB()
                guard let bCtx = CGContext(
                    data: nil, width: pxW, height: pxH,
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                bCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                bCtx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
                bCtx.scaleBy(x: CGFloat(pxW) / bounds.width, y: CGFloat(pxH) / bounds.height)
                if let ref = page.pageRef { bCtx.drawPDFPage(ref) }
                return bCtx.makeImage()
            }.value

            guard let cgImage else { continue }

            // 2. Encode to WebP via CometImageCodec
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".webp")
            _ = try? await CometImageCodec.shared.convert(
                cgImage: cgImage, outputURL: tempURL,
                format: .webp, quality: CodecQuality(value: 80)
            )

            // 3. Decode WebP back to CGImage (native on macOS 14+; falls back to rendered CGImage on older)
            var finalImage: CGImage = cgImage
            if let src = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
               let decoded = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                finalImage = decoded
            }
            try? FileManager.default.removeItem(at: tempURL)

            // 4. Draw into output PDF at the original page dimensions
            var pageBox = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            ctx.beginPDFPage([
                kCGPDFContextMediaBox: NSData(bytes: &pageBox, length: MemoryLayout<CGRect>.size)
            ] as CFDictionary)
            ctx.draw(finalImage, in: pageBox)
            ctx.endPDFPage()

            compressionProgress = Double(i + 1) / Double(pageCount)
        }

        ctx.closePDF()
        compressionProgress = 1.0
    }

    private func applyReorder(_ newOrder: [Int], for pdf: PDFItem) {
        guard let document = pdf.document, newOrder.count == document.pageCount else { return }
        // Collect all pages before any removal (PDFPage is a reference type, stays alive)
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        // Remove all (back to front)
        for i in stride(from: document.pageCount - 1, through: 0, by: -1) {
            document.removePage(at: i)
        }
        // Re-insert in new order
        for (insertIndex, originalIndex) in newOrder.enumerated() {
            guard originalIndex < pages.count else { continue }
            document.insert(pages[originalIndex], at: insertIndex)
        }
        currentPageIndex = min(currentPageIndex, document.pageCount - 1)
        documentVersion += 1
    }

    private func savePDF(_ pdf: PDFItem) {
        guard let document = pdf.document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = pdf.fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        document.write(to: url)
    }

    // MARK: - Load Helpers
    private func selectFileFromFinder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url { loadPDF(url: url) }
    }

    private func loadPDF(url: URL) {
        let doc = PDFDocument(url: url)
        var sizeString = ""
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            let fmt = ByteCountFormatter()
            fmt.allowedUnits = [.useAll]
            fmt.countStyle = .file
            sizeString = fmt.string(fromByteCount: size)
        }
        currentPageIndex = 0
        documentVersion = 0
        withAnimation { selectedPDF = PDFItem(url: url, document: doc, fileSizeString: sizeString) }
    }
}

// MARK: - PDFSinglePageView
// Renders the current page asynchronously at HD resolution to avoid blocking the main thread.
// Uses .task(id:) so a new render is automatically triggered when pageIndex or documentVersion changes.
struct PDFSinglePageView: View {
    let document: PDFDocument
    let pageIndex: Int
    let version: Int

    @State private var renderedImage: NSImage? = nil

    var body: some View {
        ZStack {
            if let image = renderedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
            } else {
                // Placeholder with approximate page aspect ratio
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .aspectRatio(pageAspectRatio, contentMode: .fit)
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                    .overlay(ProgressView().controlSize(.regular))
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(pageIndex)-\(version)") {
            renderedImage = nil
            await renderAsync()
        }
    }

    private var pageAspectRatio: CGFloat {
        guard let page = document.page(at: pageIndex) else { return 0.707 }
        let b = page.bounds(for: .mediaBox)
        return b.width / b.height
    }

    private func renderAsync() async {
        guard let page = document.page(at: pageIndex) else { return }
        let bounds = page.bounds(for: .mediaBox)
        // Render at fixed HD resolution; SwiftUI scales to fit, no re-render needed on window resize
        let maxDim: CGFloat = 1600
        let scale = maxDim / max(bounds.width, bounds.height)
        let renderSize = CGSize(
            width: (bounds.width * scale).rounded(),
            height: (bounds.height * scale).rounded()
        )
        let result = await Task.detached(priority: .userInitiated) {
            SentImage(nsImage: page.thumbnail(of: renderSize, for: .mediaBox))
        }.value
        if !Task.isCancelled { renderedImage = result.nsImage }
    }
}

// MARK: - PDFThumbnailCell
// Renders its thumbnail lazily (only when visible in LazyHStack) via .task modifier.
struct PDFThumbnailCell: View {
    let document: PDFDocument
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var thumbnail: NSImage? = nil

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.white
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipped()
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 56, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.07),
                    radius: isSelected ? 4 : 2, x: 0, y: 2)

            Text("\(index + 1)")
                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .onTapGesture { onTap() }
        .handCursor()
        .task {
            guard thumbnail == nil else { return }
            let doc = document
            let idx = index
            let result = await Task.detached(priority: .utility) {
                SentImage(nsImage: doc.page(at: idx)?.thumbnail(
                    of: CGSize(width: 112, height: 144), for: .mediaBox
                ))
            }.value
            if let img = result.nsImage { thumbnail = img }
        }
    }
}

// MARK: - PDFPageReorderView

struct PDFPageReorderView: View {
    let document: PDFDocument
    let onSave: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pageOrder: [Int]
    @State private var selectedPositions: Set<Int> = []
    @State private var draggingPositions: Set<Int> = []
    @State private var dropTargetPosition: Int? = nil

    init(document: PDFDocument, onSave: @escaping ([Int]) -> Void) {
        self.document = document
        self.onSave = onSave
        self._pageOrder = State(initialValue: Array(0..<document.pageCount))
    }

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("pdf.reorder.title"))
                        .font(.system(size: 15, weight: .bold))
                    Text(String(format: NSLocalizedString("pdf.page.count", comment: ""), document.pageCount))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !selectedPositions.isEmpty {
                    Text("\(selectedPositions.count) seçili")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Button(role: .cancel) { dismiss() } label: {
                    Text(LocalizedStringKey("alert.cancel"))
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button {
                    onSave(pageOrder)
                    dismiss()
                } label: {
                    Text(LocalizedStringKey("pdf.reorder.save"))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 20)
            .frame(height: 56)

            Divider()

            // Hint bar
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey("pdf.reorder.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.025))

            Divider()

            // Page grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(pageOrder.enumerated()), id: \.element) { position, pageIndex in
                        reorderCell(position: position, pageIndex: pageIndex)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 700, minHeight: 520)
    }

    @ViewBuilder
    private func reorderCell(position: Int, pageIndex: Int) -> some View {
        let isSelected = selectedPositions.contains(position)
        let isDragTarget = dropTargetPosition == position && !draggingPositions.contains(position)

        ReorderPageCell(
            document: document,
            pageIndex: pageIndex,
            displayNumber: position + 1,
            isSelected: isSelected,
            isDragTarget: isDragTarget
        )
        .onTapGesture {
            let ctrl = NSApp.currentEvent?.modifierFlags.contains(.control) ?? false
            if ctrl {
                if selectedPositions.contains(position) {
                    selectedPositions.remove(position)
                } else {
                    selectedPositions.insert(position)
                }
            } else {
                selectedPositions = [position]
            }
        }
        .onDrag {
            if !selectedPositions.contains(position) {
                selectedPositions = [position]
            }
            draggingPositions = selectedPositions
            return NSItemProvider(object: NSString(string: "\(position)"))
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: PageDropDelegate(
                targetPosition: position,
                pageOrder: $pageOrder,
                selectedPositions: $selectedPositions,
                draggingPositions: $draggingPositions,
                dropTargetPosition: $dropTargetPosition
            )
        )
    }
}

// MARK: - ReorderPageCell

struct ReorderPageCell: View {
    let document: PDFDocument
    let pageIndex: Int
    let displayNumber: Int
    let isSelected: Bool
    let isDragTarget: Bool

    @State private var thumbnail: NSImage? = nil

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Color.white
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                } else {
                    ProgressView().controlSize(.mini)
                }
                if isDragTarget {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                }
            }
            .frame(width: 84, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        isSelected ? Color.accentColor
                            : (isDragTarget ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1)),
                        lineWidth: isSelected ? 2.5 : (isDragTarget ? 2 : 1)
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.06),
                    radius: isSelected ? 6 : 2, x: 0, y: 2)

            Text("\(displayNumber)")
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.07) : Color.clear)
        )
        .task {
            guard thumbnail == nil else { return }
            let doc = document
            let idx = pageIndex
            let result = await Task.detached(priority: .utility) {
                SentImage(nsImage: doc.page(at: idx)?.thumbnail(
                    of: CGSize(width: 168, height: 216), for: .mediaBox
                ))
            }.value
            if let img = result.nsImage { thumbnail = img }
        }
    }
}

// MARK: - PageDropDelegate

struct PageDropDelegate: DropDelegate {
    let targetPosition: Int
    @Binding var pageOrder: [Int]
    @Binding var selectedPositions: Set<Int>
    @Binding var draggingPositions: Set<Int>
    @Binding var dropTargetPosition: Int?

    func validateDrop(info: DropInfo) -> Bool {
        !draggingPositions.isEmpty && !draggingPositions.contains(targetPosition)
    }

    func dropEntered(info: DropInfo) {
        guard !draggingPositions.contains(targetPosition) else { return }
        dropTargetPosition = targetPosition
    }

    func dropExited(info: DropInfo) {
        if dropTargetPosition == targetPosition { dropTargetPosition = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetPosition = nil
        let sortedDragging = draggingPositions.sorted()
        guard !sortedDragging.isEmpty, !sortedDragging.contains(targetPosition) else {
            draggingPositions = []
            return false
        }

        let draggedPages = sortedDragging.map { pageOrder[$0] }

        var newOrder = pageOrder
        for pos in sortedDragging.reversed() { newOrder.remove(at: pos) }

        // Adjust insert index for removed items
        var insertAt = targetPosition
        for pos in sortedDragging where pos < targetPosition { insertAt -= 1 }
        insertAt = max(0, min(insertAt, newOrder.count))

        for (i, page) in draggedPages.enumerated() {
            newOrder.insert(page, at: insertAt + i)
        }

        pageOrder = newOrder
        selectedPositions = Set(insertAt..<(insertAt + draggedPages.count))
        draggingPositions = []
        return true
    }
}

// MARK: - PDFThumbnailView (NSViewRepresentable — used for other contexts)
struct PDFThumbnailView: NSViewRepresentable {
    let page: PDFPage

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        render(on: v)
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) { render(on: nsView) }

    private func render(on view: NSImageView) {
        let w: CGFloat = 300
        let b = page.bounds(for: .mediaBox)
        view.image = page.thumbnail(of: CGSize(width: w, height: w * (b.height / b.width)), for: .mediaBox)
    }
}
