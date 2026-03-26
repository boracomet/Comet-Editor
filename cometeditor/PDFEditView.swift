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
import Quartz
import os

// NSImage is safe to pass across concurrency boundaries for display-only use.
// macOS 14+ marks it Sendable; this wrapper silences the warning on older targets.
private struct SentImage: @unchecked Sendable { let nsImage: NSImage? }



struct PDFEditView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var isDropTargeted = false

    // Compression state
    @State private var isCompressing = false
    @State private var compressionProgress: Double = 0

    // Color conversion state
    enum ColorTarget: String, CaseIterable {
        case rgb = "RGB", cmyk = "CMYK"
    }
    @State private var colorConversionEnabled: Bool = false
    @State private var colorTarget: ColorTarget = .rgb
    @State private var isConvertingColor = false
    @State private var colorConversionProgress: Double = 0

    // Reorder state (lifted so inspector can access)
    @State private var reorderSelectedPositions: Set<Int> = []
    @State private var reorderNoSelectionHint = false

    // Add Content modal
    @State private var showAddContentModal = false

    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver
    @Environment(\.colorScheme) private var colorScheme
 
    var body: some View {
        HStack(spacing: 0) {
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
        .sheet(isPresented: $showAddContentModal) {
            if let pdf = appState.selectedPDF {
                AddContentModal(pdf: pdf, currentPageIndex: appState.pdfPageIndex,
                    onWillInsert: { document in
                        if let data = document.dataRepresentation() {
                            appState.pushPDFUndo(data: data)
                        }
                    },
                    onDone: { _ in
                        appState.pdfDocumentVersion += 1
                    }
                )
            }
        }
    }

    // MARK: - Main Content Area
    @ViewBuilder
    private var mainContentArea: some View {
        if let pdf = appState.selectedPDF {
            switch appState.pdfViewMode {
            case .viewer:
                pdfViewer(pdf)
                    .transition(.opacity)
            case .scroll:
                pdfScrollView(pdf)
                    .transition(.opacity)
            case .reorder:
                if let document = pdf.document {
                    PDFPageReorderView(
                        document: document,
                        selectedPositions: $reorderSelectedPositions,
                        noSelectionHint: $reorderNoSelectionHint,
                        onSave: { newOrder in
                            await applyReorder(newOrder, for: pdf)
                            appState.pdfReorderPageOrder = nil
                            reorderSelectedPositions = []
                            withAnimation(.easeInOut(duration: 0.25)) { appState.pdfViewMode = .viewer }
                        }, onCancel: {
                            appState.pdfReorderPageOrder = nil
                            reorderSelectedPositions = []
                            withAnimation(.easeInOut(duration: 0.25)) { appState.pdfViewMode = .viewer }
                        }
                    )
                    .transition(.opacity)
                }
            }
        } else {
            emptyDropZone
        }
    }

    // MARK: - PDF Viewer
    // MARK: - Shared Info Bar
    private func pdfInfoBar(_ pdf: PDFItem) -> some View {
        ZStack {
            // Center — file name + page info
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text(pdf.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        withAnimation {
                            appState.selectedPDF = nil
                            appState.pdfPageIndex = 0
                            appState.pdfDocumentVersion = 0
                            appState.clearPDFHistory()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }
                .frame(maxWidth: 400)

                HStack(spacing: 6) {
                    if appState.pdfIsDeletingPage {
                        ProgressView().controlSize(.small)
                        Text(LocalizedStringKey("pdf.deleting"))
                            .foregroundStyle(Color.secondary)
                    } else if appState.pdfViewMode == .viewer {
                        Text(String(
                            format: NSLocalizedString("pdf.page.info", comment: ""),
                            appState.pdfPageIndex + 1,
                            pdf.document?.pageCount ?? 0
                        ))
                    } else {
                        Text(String(format: NSLocalizedString("pdf.page.count", comment: ""), pdf.document?.pageCount ?? 0))
                    }
                    if !pdf.fileSizeString.isEmpty {
                        Text("•")
                        Text(pdf.fileSizeString)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
            }

            // Left — undo/redo
            HStack {
                HStack(spacing: 4) {
                    Button {
                        if let document = pdf.document { appState.pdfUndo(document: document) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(appState.canUndo ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(appState.canUndo ? 0.07 : 0.03)))
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .disabled(!appState.canUndo)
                    .keyboardShortcut("z", modifiers: .command)

                    Button {
                        if let document = pdf.document { appState.pdfRedo(document: document) }
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(appState.canRedo ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(appState.canRedo ? 0.07 : 0.03)))
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .disabled(!appState.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            // Right — view mode toggle
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { appState.pdfViewMode = .viewer }
                    } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appState.pdfViewMode == .viewer ? .white : Color.primary.opacity(0.4))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(appState.pdfViewMode == .viewer ? Color.accentColor : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .handCursor()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { appState.pdfViewMode = .scroll }
                    } label: {
                        Image(systemName: "rectangle.grid.1x2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appState.pdfViewMode == .scroll ? .white : Color.primary.opacity(0.4))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(appState.pdfViewMode == .scroll ? Color.accentColor : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }
                .padding(.trailing, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.025))
    }

    private func pdfViewer(_ pdf: PDFItem) -> some View {
        VStack(spacing: 0) {
            pdfInfoBar(pdf)

            Divider()

            // Page viewer + arrows
            HStack(spacing: 0) {
                // Left arrow — outside page area
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.pdfPageIndex = max(0, appState.pdfPageIndex - 1)
                    }
                } label: {
                    navArrow(systemName: "chevron.left", enabled: appState.pdfPageIndex > 0)
                }
                .buttonStyle(.plain)
                .handCursor()
                .disabled(appState.pdfPageIndex == 0)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(Color.primary.opacity(0.02))

                ZStack {
                    Color.primary.opacity(0.02)
                    if let document = pdf.document {
                        PDFSinglePageView(
                            document: document,
                            pageIndex: appState.pdfPageIndex,
                            version: appState.pdfDocumentVersion
                        )
                    }
                    // Keyboard arrow navigation (invisible)
                    HStack(spacing: 0) {
                        Button("") { appState.pdfPageIndex = max(0, appState.pdfPageIndex - 1) }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .opacity(0).frame(width: 0, height: 0)
                        Button("") { appState.pdfPageIndex = min((pdf.document?.pageCount ?? 1) - 1, appState.pdfPageIndex + 1) }
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .opacity(0).frame(width: 0, height: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right arrow — outside page area
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.pdfPageIndex = min((pdf.document?.pageCount ?? 1) - 1, appState.pdfPageIndex + 1)
                    }
                } label: {
                    let hasNext = appState.pdfPageIndex < (pdf.document?.pageCount ?? 1) - 1
                    navArrow(systemName: "chevron.right", enabled: hasNext)
                }
                .buttonStyle(.plain)
                .handCursor()
                .disabled(appState.pdfPageIndex >= (pdf.document?.pageCount ?? 1) - 1)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(Color.primary.opacity(0.02))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            thumbnailStrip(pdf)
        }
    }

    // MARK: - PDF Scroll View (all pages stacked)
    private func pdfScrollView(_ pdf: PDFItem) -> some View {
        VStack(spacing: 0) {
            pdfInfoBar(pdf)

            Divider()

            ScrollView(.vertical) {
                if let document = pdf.document {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            PDFSinglePageView(
                                document: document,
                                pageIndex: index,
                                version: appState.pdfDocumentVersion,
                                canDelete: document.pageCount > 1 && !appState.pdfIsDeletingPage,
                                onDelete: { deletePage(at: index, from: pdf) }
                            )
                            .id(index)
                            .onTapGesture {
                                appState.pdfPageIndex = index
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.02))
        }
    }

    private func navArrow(systemName: String, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.3))
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.primary.opacity(enabled ? 0.07 : 0.03)))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Thumbnail Strip (LazyHStack for performance)
    private func thumbnailStrip(_ pdf: PDFItem) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    if let document = pdf.document {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            PDFThumbnailCell(
                                document: document,
                                index: index,
                                isSelected: appState.pdfPageIndex == index,
                                canDelete: document.pageCount > 1 && !appState.pdfIsDeletingPage,
                                onTap: {
                                    appState.pdfPageIndex = index
                                },
                                onDelete: {
                                    deletePage(at: index, from: pdf)
                                }
                            )
                            // Use version+index composite ID so cells fully rebuild after deletion
                            .id("\(appState.pdfDocumentVersion)-\(index)")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .fixedSize(horizontal: false, vertical: true)
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
            .onChange(of: appState.pdfPageIndex) { index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
            .onChange(of: appState.pdfDocumentVersion) { _ in
                withAnimation { proxy.scrollTo(appState.pdfPageIndex, anchor: .center) }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Empty Drop Zone
    private var emptyDropZone: some View {
        ZStack {
            PDFDropTargetView(isTargeted: $isDropTargeted, onDrop: { url in
                loadPDF(url: url)
            }, onClick: {
                selectFileFromFinder()
            })

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
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .padding(24)
        )
    }

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header — always "Ayarlar"
                HStack {
                    Text(LanguageManager.shared.string("convert.settings.title"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                Group {
                    let pdf = appState.selectedPDF
                    let pageCount = pdf?.document?.pageCount ?? 0

                    // Page Management
                    inspectorSection("pdf.tools.pageManagement") {
                        VStack(spacing: 2) {
                            toolButton(icon: "plus.rectangle.on.rectangle", title: "pdf.tools.addContent") {
                                showAddContentModal = true
                            }

                            toolButton(icon: "arrow.up.arrow.down", title: "pdf.tools.reorder") {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if appState.pdfReorderPageOrder == nil {
                                        appState.pdfReorderPageOrder = Array(0..<pageCount)
                                    }
                                    appState.pdfViewMode = .reorder
                                }
                            }
                        }
                    }

                    Divider()

                    // Renk Uzayı Dönüşümü
                    inspectorSection("pdf.color.title") {
                        VStack(alignment: .leading, spacing: 10) {
                            // Toggle satırı
                            HStack {
                                Text(LocalizedStringKey("pdf.color.enable"))
                                    .font(.system(size: 12))
                                Spacer()
                                Toggle("", isOn: $colorConversionEnabled)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .disabled(isConvertingColor)
                            }

                            // Hedef seçici — sadece toggle açıksa
                            if colorConversionEnabled {
                                Picker("", selection: $colorTarget) {
                                    ForEach(ColorTarget.allCases, id: \.self) { t in
                                        Text(t.rawValue).tag(t)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: .infinity)
                                .disabled(isConvertingColor || isCompressing)
                            }
                        }
                    }

                    Divider()

                    // Hedef Klasör
                    inspectorSection("pdf.tools.targetFolder") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Group {
                                    if let folder = appState.pdfCompressionTargetFolder {
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
                                    pickFolder { appState.pdfCompressionTargetFolder = $0 }
                                }
                                .controlSize(.small)
                            }

                            if isCompressing || isConvertingColor {
                                let prog = isConvertingColor ? colorConversionProgress : compressionProgress
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: prog, total: 1.0)
                                        .progressViewStyle(.linear)
                                    Text("%\(Int(prog * 100))")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    // Optimize + Save
                    VStack(spacing: 10) {
                        // Tahmini boyut — sadece optimize modunda göster
                        if !colorConversionEnabled, let pdf = pdf, pdf.fileSizeBytes > 0 {
                            let estimatedBytes = Int64(Double(pdf.fileSizeBytes) * 0.35)
                            let estimatedStr = ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                                Text("~\(estimatedStr)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                Spacer()
                                Text(LocalizedStringKey("pdf.estimatedSize"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.secondary.opacity(0.7))
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        }

                        Button {
                            if let pdf = pdf {
                                Task {
                                    if colorConversionEnabled {
                                        await convertColorSpace(pdf, target: colorTarget)
                                    } else {
                                        await compressPDF(pdf)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isCompressing || isConvertingColor {
                                    ProgressView().controlSize(.small)
                                    Text(LocalizedStringKey("video.processing"))
                                } else {
                                    Image(systemName: colorConversionEnabled ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                                    Text(LocalizedStringKey(colorConversionEnabled ? "pdf.color.convert" : "pdf.tools.optimize"))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(appState.pdfCompressionTargetFolder == nil || isCompressing || isConvertingColor || pdf == nil)

                        Button {
                            if let pdf = pdf { savePDF(pdf) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text(LocalizedStringKey("pdf.tools.save"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(pdf == nil)
                    }
                    .padding(16)
                }
                .disabled(appState.selectedPDF == nil)
                .opacity(appState.selectedPDF == nil ? 0.6 : 1.0)
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

    private func deleteReorderSelected(from pdf: PDFItem) {
        guard let document = pdf.document, !reorderSelectedPositions.isEmpty else { return }
        let pageOrder = appState.pdfReorderPageOrder ?? Array(0..<document.pageCount)

        let indicesToDelete = reorderSelectedPositions
            .compactMap { pos -> Int? in pos < pageOrder.count ? pageOrder[pos] : nil }
            .sorted(by: >)

        guard document.pageCount - indicesToDelete.count >= 1 else { return }

        // Serialize only the pages being deleted (sorted ascending for correct undo re-insert)
        var undoRecords: [PDFDeletedPage] = []
        for idx in indicesToDelete.sorted() {
            if let page = document.page(at: idx) {
                let singleDoc = PDFDocument()
                singleDoc.insert(page, at: 0)
                if let data = singleDoc.dataRepresentation() {
                    undoRecords.append(PDFDeletedPage(originalIndex: idx, pageData: data))
                }
            }
        }

        // Delete pages immediately for instant visual feedback (descending to keep indices valid)
        let oldPageCount = document.pageCount
        let deletedSet = Set(indicesToDelete)
        for idx in indicesToDelete { document.removePage(at: idx) }
        let newPageCount = document.pageCount
        appState.updateSelectedPDFSizeAfterPageDeletion(oldPageCount: oldPageCount, newPageCount: newPageCount)

        let newPageOrder = pageOrder
            .filter { !deletedSet.contains($0) }
            .map { origIdx -> Int in origIdx - indicesToDelete.filter { $0 < origIdx }.count }

        appState.pdfReorderPageOrder = newPageOrder
        appState.pdfDocumentVersion += 1
        reorderSelectedPositions = []

        if !undoRecords.isEmpty {
            appState.pushPageDeletionUndo(undoRecords)
        }
    }

    private func deletePage(at index: Int, from pdf: PDFItem) {
        guard let document = pdf.document, document.pageCount > 1 else { return }
        guard let page = document.page(at: index) else { return }

        // Serialize only the single page being deleted — much faster than the full doc
        let singlePageDoc = PDFDocument()
        singlePageDoc.insert(page, at: 0)
        let pageData = singlePageDoc.dataRepresentation()

        // Delete the page immediately for instant visual feedback
        let oldPageCount = document.pageCount
        document.removePage(at: index)
        let newCount = document.pageCount
        appState.pdfPageIndex = index >= newCount ? newCount - 1 : index
        appState.pdfDocumentVersion += 1
        appState.updateSelectedPDFSizeAfterPageDeletion(oldPageCount: oldPageCount, newPageCount: newCount)

        // Push lightweight undo record (just the single deleted page)
        if let data = pageData {
            appState.pushPageDeletionUndo([PDFDeletedPage(originalIndex: index, pageData: data)])
        }
    }


    /// Her sayfayı JPEG olarak render edip PDF'e yazar.
    /// magick varsa JPEG'leri birleştirir (gerçek sıkıştırma),
    /// yoksa CGContext PDF stream fallback kullanır.
    /// outputURL: nil ise targetFolder'a _optimized.pdf olarak yazar.
    @MainActor
    /// PDF içindeki raster imajları sıkıştırır; vektörel içerik ve yazılar bitmap'e dönüştürülmez.
    /// QuartzFilter ile CGPDFContext'e sayfalar draw edilir — filter sadece raster XObject'lere uygulanır.
    private func compressPDF(_ pdf: PDFItem, outputURL explicitURL: URL? = nil) async {
        guard let document = pdf.document else { return }

        // outputURL verilmediyse targetFolder'dan türet
        let outputURL: URL
        if let explicit = explicitURL {
            outputURL = explicit
        } else {
            guard let targetFolder = appState.pdfCompressionTargetFolder else { return }
            let baseName = pdf.url.deletingPathExtension().lastPathComponent
            var url = targetFolder.appendingPathComponent("\(baseName)_optimized.pdf")
            var counter = 1
            while FileManager.default.fileExists(atPath: url.path) {
                url = targetFolder.appendingPathComponent("\(baseName)_optimized_\(counter).pdf")
                counter += 1
            }
            outputURL = url
        }

        isCompressing = true
        compressionProgress = 0
        defer { isCompressing = false }

        let log = Logger(subsystem: "com.cometeditor", category: "PDFCompress")
        let pageCount = document.pageCount

        // pageRef + bounds MainActor'da topla
        var pageRefs: [(CGPDFPage, CGRect)] = []
        for i in 0..<pageCount {
            guard let page = document.page(at: i), let ref = page.pageRef else { continue }
            pageRefs.append((ref, page.bounds(for: .mediaBox)))
        }
        guard !pageRefs.isEmpty else { log.error("pageRefs empty"); return }

        compressionProgress = 0.1

        // QuartzFilter: macOS sistem filtresi ile raster imajları sıkıştır.
        // Vektörler ve yazılar bitmap'e dönüştürülmez — sadece gömülü raster imajlar sıkıştırılır.
        let destURL = outputURL
        let written = await Task.detached(priority: .userInitiated) { () -> Bool in
            // Önce system filter dosyasından yükle — en güvenilir yol
            let systemFilterURL = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
            let filter: QuartzFilter?
            if FileManager.default.fileExists(atPath: systemFilterURL.path) {
                filter = QuartzFilter(url: systemFilterURL)
            } else {
                // System filter yoksa (nadiren) manuel properties ile dene
                let scaleSettings: [AnyHashable: Any] = [
                    "ImageResolution": 144,
                    "ImageScaleInterpolate": true,
                    "ImageSizeMax": 1920,
                    "ImageSizeMin": 0
                ]
                let imageSettings: [AnyHashable: Any] = [
                    "Compression Quality": 0.50,
                    "ImageCompression": "ImageJPEGCompress",
                    "ImageScaleSettings": scaleSettings
                ]
                let filterProps: [AnyHashable: Any] = [
                    "FilterType": 1,
                    "Name": "Reduce File Size",
                    "FilterData": [
                        "ColorSettings": [
                            "ImageSettings": imageSettings
                        ] as [AnyHashable: Any]
                    ] as [AnyHashable: Any]
                ]
                filter = QuartzFilter(properties: filterProps)
            }
            guard let filter else {
                log.error("QuartzFilter init failed")
                return false
            }

            let mutableData = NSMutableData()
            guard let consumer = CGDataConsumer(data: mutableData) else { return false }

            // İlk sayfanın media box'ını varsayılan olarak kullan
            var defaultBox = pageRefs.first.map { $0.1 } ?? CGRect(x: 0, y: 0, width: 595, height: 842)
            guard let ctx = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else { return false }

            // Filter'ı context'e uygula — bu aşamadan sonra context'e çizilen
            // raster imajlar otomatik olarak JPEG ile sıkıştırılır
            filter.apply(to: ctx)

            for (pageRef, bounds) in pageRefs {
                var box = bounds
                ctx.beginPage(mediaBox: &box)
                // drawPDFPage: vektörler, fontlar, yazılar AYNEN kopyalanır (stream copy)
                // Raster XObject'ler filter tarafından sıkıştırılır
                ctx.drawPDFPage(pageRef)
                ctx.endPage()
            }
            ctx.closePDF()

            do {
                try (mutableData as Data).write(to: destURL, options: .atomic)
                return true
            } catch {
                log.error("write failed: \(error)")
                return false
            }
        }.value

        compressionProgress = 1.0
        if written {
            log.info("QuartzFilter compress succeeded → \(destURL.path)")
            CometAnalytics.shared.trackEvent(page: "pdfEdit", eventType: .pdfEdited,
                metadata: ["action": "compress_quartz", "pages": pageCount])
        } else {
            log.error("QuartzFilter compress failed")
        }
    }

    /// Her sayfayı hedef renk uzayında re-render ederek yeni PDF oluşturur.
    @MainActor
    private func convertColorSpace(_ pdf: PDFItem, target: ColorTarget) async {
        guard let document = pdf.document,
              let targetFolder = appState.pdfCompressionTargetFolder else { return }

        isConvertingColor = true
        colorConversionProgress = 0
        defer { isConvertingColor = false }

        let suffix = target == .rgb ? "_rgb" : "_cmyk"
        let baseName = pdf.url.deletingPathExtension().lastPathComponent
        var outputURL = targetFolder.appendingPathComponent("\(baseName)\(suffix).pdf")
        var counter = 1
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = targetFolder.appendingPathComponent("\(baseName)\(suffix)_\(counter).pdf")
            counter += 1
        }

        var mediaBox = CGRect.zero
        guard let ctx = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else { return }

        let pageCount = document.pageCount
        let dpi: CGFloat = 150.0

        let colorSpace: CGColorSpace = target == .rgb
            ? CGColorSpaceCreateDeviceRGB()
            : (CGColorSpace(name: CGColorSpace.genericCMYK) ?? CGColorSpaceCreateDeviceCMYK())
        let bitmapInfo: UInt32 = target == .rgb
            ? (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            : CGImageAlphaInfo.none.rawValue  // CMYK has no alpha
        let bgComponents: [CGFloat] = target == .rgb ? [1, 1, 1, 1] : [0, 0, 0, 0, 1]

        for i in 0..<pageCount {
            guard !Task.isCancelled else { break }
            guard let page = document.page(at: i) else { continue }

            let bounds = page.bounds(for: .mediaBox)
            let scale = dpi / 72.0
            let pxW = Int(bounds.width * scale)
            let pxH = Int(bounds.height * scale)
            let pageRef = page.pageRef

            let cgImage = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let pageRef,
                      let bCtx = CGContext(
                          data: nil, width: pxW, height: pxH,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: bitmapInfo
                      ),
                      let bgColor = CGColor(colorSpace: colorSpace, components: bgComponents)
                else { return nil }
                bCtx.setFillColor(bgColor)
                bCtx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
                bCtx.scaleBy(x: CGFloat(pxW) / bounds.width, y: CGFloat(pxH) / bounds.height)
                bCtx.drawPDFPage(pageRef)
                return bCtx.makeImage()
            }.value

            guard let cgImage else { continue }

            var pageBox = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            ctx.beginPDFPage([
                kCGPDFContextMediaBox: NSData(bytes: &pageBox, length: MemoryLayout<CGRect>.size)
            ] as CFDictionary)
            ctx.draw(cgImage, in: pageBox)
            ctx.endPDFPage()

            colorConversionProgress = Double(i + 1) / Double(pageCount)
        }

        ctx.closePDF()
        colorConversionProgress = 1.0
        CometAnalytics.shared.trackEvent(
            page: "pdfEdit",
            eventType: .pdfEdited,
            metadata: ["action": "colorConvert", "target": target.rawValue, "pages": pageCount]
        )
    }

    private func applyReorder(_ newOrder: [Int], for pdf: PDFItem) async {
        guard let document = pdf.document, !newOrder.isEmpty else { return }
        // newOrder contains current sequential indices (0..<document.pageCount after deletions)
        // Just reorder existing pages by the given order
        let pageCount = document.pageCount
        let validOrder = newOrder.filter { $0 < pageCount }
        guard validOrder.count == pageCount else { return }

        await Task.yield()

        guard let data = document.dataRepresentation() else { return }
        appState.pushPDFUndo(data: data)
        await Task.yield()

        let pages = (0..<pageCount).compactMap { document.page(at: $0) }
        for i in stride(from: pageCount - 1, through: 0, by: -1) {
            document.removePage(at: i)
        }
        await Task.yield()

        for (insertIndex, originalIndex) in validOrder.enumerated() {
            guard originalIndex < pages.count else { continue }
            document.insert(pages[originalIndex], at: insertIndex)
            if insertIndex % 5 == 4 { await Task.yield() }
        }
        appState.pdfPageIndex = min(appState.pdfPageIndex, document.pageCount - 1)
        appState.pdfDocumentVersion += 1
    }

    private func savePDF(_ pdf: PDFItem) {
        guard let document = pdf.document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = pdf.fileName
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        // Belge değiştirilmediyse (version == 0) orijinal dosyayı kopyala.
        // PDFKit'in write(to:) metodu yeniden serialize ederek boyutu şişiriyor.
        if appState.pdfDocumentVersion == 0 {
            try? FileManager.default.removeItem(at: saveURL)
            try? FileManager.default.copyItem(at: pdf.url, to: saveURL)
        } else if let data = document.dataRepresentation() {
            try? data.write(to: saveURL, options: .atomic)
        } else {
            document.write(to: saveURL)
        }
        CometAnalytics.shared.trackEvent(page: "pdfEdit", eventType: .pdfEdited, metadata: ["action": "save"])
    }

    // MARK: - Load Helpers
    private func selectFileFromFinder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self.loadPDF(url: url) }
        }
    }

    private func loadPDF(url: URL) {
        let doc = PDFDocument(url: url)
        var sizeString = ""
        var sizeBytes: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            sizeBytes = size
            let fmt = ByteCountFormatter()
            fmt.allowedUnits = [.useAll]
            fmt.countStyle = .file
            sizeString = fmt.string(fromByteCount: size)
        }
        appState.pdfPageIndex = 0
        appState.pdfDocumentVersion = 0
        appState.pdfReorderPageOrder = nil
        withAnimation { appState.selectedPDF = PDFItem(url: url, document: doc, fileSizeString: sizeString, fileSizeBytes: sizeBytes) }
    }
}

// MARK: - AddContentModal
private struct AddContentModal: View {
    let pdf: PDFItem
    let currentPageIndex: Int
    var onWillInsert: (PDFDocument) -> Void
    var onDone: (PDFDocument) -> Void

    enum ContentType { case pdf, image }
    enum InsertPosition { case before, after, atEnd }

    @State private var contentType: ContentType = .pdf
    @State private var insertPosition: InsertPosition = .after
    @State private var customPageNumber: Int = 1
    @State private var useCurrentPage: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack {
                Text(LocalizedStringKey("pdf.addContent.title"))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Content type picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey("pdf.addContent.typeLabel"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            typeButton(label: "pdf.addContent.typePDF", icon: "doc.fill", selected: contentType == .pdf) {
                                contentType = .pdf
                            }
                            typeButton(label: "pdf.addContent.typeImage", icon: "photo.fill", selected: contentType == .image) {
                                contentType = .image
                            }
                        }
                    }

                    Divider()

                    // Insert position
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey("pdf.addContent.positionLabel"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        // Use current page or custom
                        Toggle(isOn: $useCurrentPage) {
                            Text(String(format: NSLocalizedString("pdf.addContent.currentPage", comment: ""), currentPageIndex + 1))
                                .font(.system(size: 13))
                        }
                        .toggleStyle(.checkbox)

                        if !useCurrentPage {
                            HStack(spacing: 8) {
                                Text(LocalizedStringKey("pdf.addContent.pageNumber"))
                                    .font(.system(size: 13))
                                TextField("", value: $customPageNumber, formatter: {
                                    let f = NumberFormatter()
                                    f.minimum = 1
                                    f.maximum = NSNumber(value: pdf.document?.pageCount ?? 1)
                                    return f
                                }())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            }
                        }

                        Picker("", selection: $insertPosition) {
                            Text(LocalizedStringKey("pdf.addContent.before")).tag(InsertPosition.before)
                            Text(LocalizedStringKey("pdf.addContent.after")).tag(InsertPosition.after)
                            Text(LocalizedStringKey("pdf.addContent.atEnd")).tag(InsertPosition.atEnd)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }
                .padding(20)
            }

            Divider()

            // Action button
            HStack {
                Spacer()
                Button {
                    performInsert()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text(LocalizedStringKey("pdf.addContent.chooseFile"))
                    }
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func typeButton(label: LocalizedStringKey, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 1.5 : 1)
            )
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func performInsert() {
        guard let document = pdf.document else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = contentType == .pdf
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        switch contentType {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        case .image:
            panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .bmp, .gif, .webP]
        }

        guard panel.runModal() == .OK else { return }

        onWillInsert(document)

        let refPage = useCurrentPage ? currentPageIndex : max(0, customPageNumber - 1)

        let insertAt: Int
        switch insertPosition {
        case .before: insertAt = refPage
        case .after:  insertAt = refPage + 1
        case .atEnd:  insertAt = document.pageCount
        }

        var offset = 0
        for url in panel.urls {
            switch contentType {
            case .pdf:
                guard let src = PDFDocument(url: url) else { continue }
                for i in 0..<src.pageCount {
                    if let page = src.page(at: i) {
                        document.insert(page, at: min(insertAt + offset, document.pageCount))
                        offset += 1
                    }
                }
            case .image:
                guard let nsImage = NSImage(contentsOf: url),
                      let page = PDFPage(image: nsImage) else { continue }
                document.insert(page, at: min(insertAt + offset, document.pageCount))
                offset += 1
            }
        }

        onDone(document)
    }
}

// MARK: - PDFDropTargetView
// Uses AppKit NSDraggingDestination directly to avoid SwiftUI onDrop conflicts
// inside NavigationSplitView (kDragIPCWithinWindow issue).
private struct PDFDropTargetView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: (URL) -> Void
    var onClick: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let view = DropView()
        view.coordinator = context.coordinator
        view.registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.adobe.pdf")])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DropView)?.coordinator = context.coordinator
    }

    class Coordinator {
        var parent: PDFDropTargetView
        init(_ parent: PDFDropTargetView) { self.parent = parent }
    }

    class DropView: NSView {
        weak var coordinator: Coordinator?

        // Allows the view to receive the first click even when the window is not key
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            coordinator?.parent.onClick()
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            if urlFromDragging(sender) != nil {
                coordinator?.parent.isTargeted = true
                return .copy
            }
            return []
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            coordinator?.parent.isTargeted = false
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            coordinator?.parent.isTargeted = false
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let url = urlFromDragging(sender) else { return false }
            DispatchQueue.main.async { self.coordinator?.parent.onDrop(url) }
            return true
        }

        private func urlFromDragging(_ sender: NSDraggingInfo) -> URL? {
            guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: ["com.adobe.pdf"]
            ]) as? [URL] else { return nil }
            return items.first
        }
    }
}

// MARK: - PDFSinglePageView
// Renders the current page asynchronously at HD resolution to avoid blocking the main thread.
// Uses .task(id:) so a new render is automatically triggered when pdfPageIndex or pdfDocumentVersion changes.
struct PDFSinglePageView: View {
    let document: PDFDocument
    let pageIndex: Int
    let version: Int
    var canDelete: Bool = false
    var onDelete: (() -> Void)? = nil

    @State private var renderedImage: NSImage? = nil
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
            .padding(.horizontal, 48)
            .padding(.vertical, 5)

            // Delete button — top-right corner, visible on hover
            if canDelete, isHovered, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .handCursor()
                .padding(.top, 12)
                .padding(.trailing, 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { isHovered = $0 }
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
    let canDelete: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var aspectRatio: CGFloat = 0.707

    private let cellHeight: CGFloat = 160

    // Compute aspect ratio synchronously from document on init to avoid layout flash
    private var initialAspectRatio: CGFloat {
        guard let bounds = document.page(at: index)?.bounds(for: .mediaBox),
              bounds.height > 0 else { return 0.707 }
        return bounds.width / bounds.height
    }

    private var cellWidth: CGFloat { cellHeight * aspectRatio }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.white
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    ProgressView().controlSize(.mini)
                }

                // Delete button — inside image, top-right corner
                if canDelete {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                onDelete()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.55))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(5)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: cellWidth, height: cellHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.07),
                    radius: isSelected ? 4 : 2, x: 0, y: 2)

            Text("\(index + 1)")
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .onTapGesture { onTap() }
        .handCursor()
        .onAppear {
            aspectRatio = initialAspectRatio
        }
        .task(id: index) {
            guard thumbnail == nil else { return }
            let doc = document
            let idx = index
            let ratio = initialAspectRatio
            aspectRatio = ratio
            let renderH = cellHeight * 2
            let renderW = renderH * ratio
            let result = await Task.detached(priority: .utility) {
                SentImage(nsImage: doc.page(at: idx)?.thumbnail(
                    of: CGSize(width: renderW, height: renderH), for: .mediaBox
                ))
            }.value
            if let img = result.nsImage { thumbnail = img }
        }
    }
}

// MARK: - PDFPageReorderView

struct PDFPageReorderView: View {
    let document: PDFDocument
    @Binding var selectedPositions: Set<Int>
    @Binding var noSelectionHint: Bool
    let onSave: ([Int]) async -> Void
    let onCancel: () -> Void

    @EnvironmentObject var appState: GlobalAppState
    @State private var lastSelectedIndex: Int? = nil
    @State private var draggingPositions: Set<Int> = []
    @State private var scrollPosition: Int? = nil // To programmatically scroll
    @State private var isSavingOrder = false

    // Helper to get a stable pageOrder binding from appState
    private var pageOrderBinding: Binding<[Int]> {
        Binding(
            get: { appState.pdfReorderPageOrder ?? Array(0..<document.pageCount) },
            set: { appState.pdfReorderPageOrder = $0 }
        )
    }

    private var pageOrder: [Int] {
        appState.pdfReorderPageOrder ?? Array(0..<document.pageCount)
    }

    private let columns = [GridItem(.adaptive(minimum: 162, maximum: 210), spacing: 14)]

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
                HStack(spacing: 4) {
                    Button {
                        appState.pdfUndo(document: document)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(appState.canUndo ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(appState.canUndo ? 0.07 : 0.03)))
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .disabled(!appState.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    Button {
                        appState.pdfRedo(document: document)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(appState.canRedo ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(appState.canRedo ? 0.07 : 0.03)))
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .disabled(!appState.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                if !selectedPositions.isEmpty {
                    Text(String(format: NSLocalizedString("pdf.reorder.selectedCount", comment: ""), selectedPositions.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Button(role: .cancel) { onCancel() } label: {
                    Text(LocalizedStringKey("alert.cancel"))
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(isSavingOrder)
                Button {
                    let order = pageOrder
                    isSavingOrder = true
                    Task { @MainActor in
                        await Task.yield()
                        await onSave(order)
                        isSavingOrder = false
                    }
                } label: {
                    if isSavingOrder {
                        ProgressView().controlSize(.small)
                        Text(LocalizedStringKey("pdf.reorder.saving"))
                    } else {
                        Text(LocalizedStringKey("pdf.reorder.save"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(isSavingOrder)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)

            Divider()

            // Hint bar
            HStack(spacing: 6) {
                if appState.pdfIsDeletingPage {
                    ProgressView().controlSize(.small)
                    Text(LocalizedStringKey("pdf.deleting"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                } else {
                    Image(systemName: noSelectionHint ? "exclamationmark.triangle" : "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(noSelectionHint ? Color.orange : Color.secondary)
                    Text(LocalizedStringKey(noSelectionHint ? "pdf.reorder.selectToDelete" : "pdf.reorder.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(noSelectionHint ? Color.orange : Color.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(noSelectionHint ? Color.orange.opacity(0.08) : Color.primary.opacity(0.025))
            .animation(.easeInOut(duration: 0.2), value: noSelectionHint)
            .onChange(of: selectedPositions) { _ in
                if noSelectionHint { noSelectionHint = false }
            }

            Divider()
 
            // Page grid
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .top) {
                            // Page grid
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(Array(pageOrder.enumerated()), id: \.element) { position, pageIndex in
                                    reorderCell(position: position, pageIndex: pageIndex)
                                        .id("\(appState.pdfDocumentVersion)-\(pageIndex)")
                                        .onDrop(of: [UTType.plainText], delegate: ReorderDropDelegate(
                                            targetPosition: position,
                                            pageOrder: pageOrderBinding,
                                            selectedPositions: $selectedPositions,
                                            draggingPositions: $draggingPositions,
                                            geometry: geometry,
                                            proxy: proxy
                                        ))
                                }

                                // Invisible end drop zone — allows dropping after the last page
                                Color.clear
                                    .frame(height: 10)
                                    .onDrop(of: [UTType.plainText], delegate: ReorderDropDelegate(
                                        targetPosition: pageOrder.count - 1,
                                        pageOrder: pageOrderBinding,
                                        selectedPositions: $selectedPositions,
                                        draggingPositions: $draggingPositions,
                                        geometry: geometry,
                                        proxy: proxy
                                    ))
                            }
                            .padding(20)
                            .animation(.easeInOut(duration: 0.15), value: pageOrder)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder
    private func reorderCell(position: Int, pageIndex: Int) -> some View {
        let isSelected = selectedPositions.contains(position)
        
        ReorderPageCell(
            document: document,
            pageIndex: pageIndex,
            displayNumber: position + 1,
            isSelected: isSelected,
            onDelete: {
                let currentOrder = appState.pdfReorderPageOrder ?? Array(0..<document.pageCount)
                guard currentOrder.count > 1 else { return }
                let pageIndexToDelete = pageIndex
                guard currentOrder.contains(pageIndexToDelete),
                      let positionInOrder = currentOrder.firstIndex(of: pageIndexToDelete) else { return }
                guard let pageToDelete = document.page(at: pageIndexToDelete) else { return }

                // Serialize only the single page (fast)
                let singleDoc = PDFDocument()
                singleDoc.insert(pageToDelete, at: 0)
                let pageData = singleDoc.dataRepresentation()

                // Delete immediately — instant visual feedback
                let oldPageCount = document.pageCount
                document.removePage(at: pageIndexToDelete)
                appState.updateSelectedPDFSizeAfterPageDeletion(oldPageCount: oldPageCount, newPageCount: document.pageCount)
                var newOrder = currentOrder
                newOrder.remove(at: positionInOrder)
                let updated = newOrder.map { idx -> Int in
                    idx > pageIndexToDelete ? idx - 1 : idx
                }
                appState.pdfReorderPageOrder = updated
                selectedPositions.removeAll()
                appState.pdfDocumentVersion += 1

                if let data = pageData {
                    appState.pushPageDeletionUndo([PDFDeletedPage(originalIndex: pageIndexToDelete, pageData: data)])
                }
            }
        )
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            let isCommand = flags.contains(.command) || flags.contains(.control)
            let isShift = flags.contains(.shift)
            
            if isShift, let last = lastSelectedIndex {
                let start = min(last, position)
                let end = max(last, position)
                let range = Set(start...end)
                selectedPositions.formUnion(range)
            } else if isCommand {
                if selectedPositions.contains(position) {
                    selectedPositions.remove(position)
                } else {
                    selectedPositions.insert(position)
                }
            } else {
                selectedPositions = [position]
            }
            lastSelectedIndex = position
        }
        .onDrag {
            if !selectedPositions.contains(position) {
                selectedPositions = [position]
                lastSelectedIndex = position
            }
            draggingPositions = selectedPositions
            return NSItemProvider(object: NSString(string: "\(position)"))
        }
    }
}

// MARK: - ReorderPageCell

struct ReorderPageCell: View {
    let document: PDFDocument
    let pageIndex: Int
    let displayNumber: Int
    let isSelected: Bool
    let onDelete: () -> Void

    @EnvironmentObject var appState: GlobalAppState
    @State private var thumbnail: NSImage? = nil
    @State private var isHovered = false
    @State private var aspectRatio: CGFloat = 0.707 // default A4 portrait

    private let cellWidth: CGFloat = 135

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.white
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .trim(from: 0, to: 0.3)
                                .stroke(Color.secondary, lineWidth: 2)
                                .rotationEffect(.degrees(thumbnail == nil ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: thumbnail == nil)
                        )
                }

                // Overlay for selection/hover
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.03) : Color.clear))

                // Delete button on hover (hidden during delete to prevent double-tap)
                if isHovered, !appState.pdfIsDeletingPage {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onDelete) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .handCursor()
                            .padding(4)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: cellWidth, height: cellWidth / aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05),
                    radius: isSelected ? 4 : 2, x: 0, y: 2)

            Text("\(displayNumber)")
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .task {
            guard thumbnail == nil else { return }
            let doc = document
            let idx = pageIndex
            // Read aspect ratio before detached task
            if let bounds = doc.page(at: idx)?.bounds(for: .mediaBox), bounds.height > 0 {
                aspectRatio = bounds.width / bounds.height
            }
            let ratio = aspectRatio
            let renderW = cellWidth * 2
            let renderH = renderW / ratio
            let result = await Task.detached(priority: .utility) {
                SentImage(nsImage: doc.page(at: idx)?.thumbnail(
                    of: CGSize(width: renderW, height: renderH), for: .mediaBox
                ))
            }.value
            if let img = result.nsImage { thumbnail = img }
        }
    }
}

// MARK: - ReorderDropDelegate

struct ReorderDropDelegate: DropDelegate {
    let targetPosition: Int
    @Binding var pageOrder: [Int]
    @Binding var selectedPositions: Set<Int>
    @Binding var draggingPositions: Set<Int>
    let geometry: GeometryProxy
    let proxy: ScrollViewProxy

    func validateDrop(info: DropInfo) -> Bool {
        !draggingPositions.isEmpty && !draggingPositions.contains(targetPosition)
    }

    func dropEntered(info: DropInfo) {
        handleScroll(at: info.location)

        guard !draggingPositions.contains(targetPosition) else { return }

        let sortedDragging = draggingPositions.sorted()

        withAnimation(.easeInOut(duration: 0.25)) {
            var newOrder = pageOrder
            let draggedItems = sortedDragging.map { pageOrder[$0] }

            for index in sortedDragging.reversed() {
                newOrder.remove(at: index)
            }

            // Insert after target if dragging from before it, insert before otherwise.
            // This gives natural "slide past" behaviour.
            let minDragging = sortedDragging.min() ?? 0
            let insertAfter = minDragging < targetPosition

            var insertionIndex = targetPosition
            let itemsBeforeTarget = sortedDragging.filter { $0 < targetPosition }.count
            insertionIndex -= itemsBeforeTarget
            if insertAfter { insertionIndex += 1 }

            newOrder.insert(contentsOf: draggedItems, at: min(max(0, insertionIndex), newOrder.count))
            pageOrder = newOrder

            var newSelection: Set<Int> = []
            for item in draggedItems {
                if let newIdx = newOrder.firstIndex(of: item) {
                    newSelection.insert(newIdx)
                }
            }
            selectedPositions = newSelection
            draggingPositions = newSelection
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        handleScroll(at: info.location)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingPositions = []
        return true
    }

    private func handleScroll(at location: CGPoint) {
        let scrollPadding: CGFloat = 80
        if location.y > geometry.size.height - scrollPadding {
            // Scroll down
            let nextIndex = min(pageOrder.count - 1, targetPosition + 2)
            withAnimation {
                proxy.scrollTo(nextIndex, anchor: .bottom)
            }
        } else if location.y < scrollPadding {
            // Scroll up: Subtract more to ensure we move beyond current visibility
            let prevIndex = max(0, targetPosition - 4)
            withAnimation {
                proxy.scrollTo(prevIndex, anchor: .top)
            }
        }
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
