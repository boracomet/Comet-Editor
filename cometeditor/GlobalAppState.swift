import SwiftUI
import Foundation
import Combine
@preconcurrency import PDFKit

// MARK: - Models
struct ImageItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let image: NSImage?
    let fileSizeString: String
    let dimensionsString: String
    var fileName: String { url.lastPathComponent }
}

struct VideoItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileSizeString: String
    let durationString: String
    var resolutionString: String?
    var fpsString: String?
    var thumbnail: NSImage?
    
    var isCompleted: Bool = false
    var savedSizeString: String? = nil
    
    var fileName: String { url.lastPathComponent }
}

struct PDFItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let document: PDFDocument?
    let fileSizeString: String
    let fileSizeBytes: Int64
    var fileName: String { url.lastPathComponent }

    static func == (lhs: PDFItem, rhs: PDFItem) -> Bool { lhs.id == rhs.id }
}

enum PDFViewMode {
    case viewer   // single page with thumbnails
    case scroll   // all pages stacked vertically
    case reorder  // drag-to-reorder grid
}

// Snapshot of a full PDF document state for undo/redo
struct PDFSnapshot {
    let documentData: Data // full serialized PDF
}

class GlobalAppState: ObservableObject {
    // Shared File Lists
    @Published var selectedImages: [ImageItem] = []
    @Published var selectedVideos: [VideoItem] = []

    // PDF Editor State
    @Published var selectedPDF: PDFItem? = nil
    @Published var pdfPageIndex: Int = 0
    @Published var pdfDocumentVersion: Int = 0
    @Published var pdfViewMode: PDFViewMode = .viewer
    @Published var pdfCompressionTargetFolder: URL? = nil {
        didSet { savePDFFolderBookmark() }
    }
    @Published var pdfReorderPageOrder: [Int]? = nil

    // Undo/Redo stacks (full document snapshots)
    private(set) var pdfUndoStack: [PDFSnapshot] = []
    private(set) var pdfRedoStack: [PDFSnapshot] = []

    var canUndo: Bool { !pdfUndoStack.isEmpty }
    var canRedo: Bool { !pdfRedoStack.isEmpty }

    // Serialize the document state in the background and push onto the undo stack.
    // Must be called AFTER the mutation so the UI updates instantly.
    // PDFDocument.dataRepresentation() is called on a background thread via a
    // detached Task; the document must not be mutated again until this completes,
    // but for single-page deletions this is safe in practice.
    func pushPDFUndo(data: Data) {
        pdfUndoStack.append(PDFSnapshot(documentData: data))
        pdfRedoStack = []
        objectWillChange.send()
    }

    func pdfUndo(document: PDFDocument) {
        guard let snapshot = pdfUndoStack.popLast() else { return }
        if let currentData = document.dataRepresentation() {
            pdfRedoStack.append(PDFSnapshot(documentData: currentData))
        }
        restoreSnapshot(snapshot, into: document)
    }

    func pdfRedo(document: PDFDocument) {
        guard let snapshot = pdfRedoStack.popLast() else { return }
        if let currentData = document.dataRepresentation() {
            pdfUndoStack.append(PDFSnapshot(documentData: currentData))
        }
        restoreSnapshot(snapshot, into: document)
    }

    func clearPDFHistory() {
        pdfUndoStack = []
        pdfRedoStack = []
        objectWillChange.send()
    }

    private func restoreSnapshot(_ snapshot: PDFSnapshot, into document: PDFDocument) {
        guard let restored = PDFDocument(data: snapshot.documentData) else { return }
        // Replace all pages in-place
        for i in stride(from: document.pageCount - 1, through: 0, by: -1) {
            document.removePage(at: i)
        }
        for i in 0..<restored.pageCount {
            if let page = restored.page(at: i) {
                document.insert(page, at: i)
            }
        }
        pdfPageIndex = min(pdfPageIndex, document.pageCount - 1)
        pdfDocumentVersion += 1
        objectWillChange.send()
    }

    // Persistent Folder
    @Published var targetFolder: URL? = nil {
        didSet {
            if let old = oldValue {
                old.stopAccessingSecurityScopedResource()
            }
            saveFolderBookmark()
        }
    }

    @Published var showingTeamModal = false

    // OCR State
    @Published var ocrImage: NSImage? = nil
    @Published var ocrImageURL: URL? = nil
    @Published var ocrRecognizedText: String = ""
    @Published var ocrIsProcessing: Bool = false

    // BgRemove State
    @Published var bgRemoveItems: [BgRemoveItem] = []
    @Published var bgRemovePreviewItemID: UUID? = nil
    @Published var bgRemoveFormat: BgRemoveFormat = .png
    @Published var bgRemoveFeatherRadius: Float = 1.5

    // QR State
    @Published var qrText: String = "https://cometeditor.com"
    @Published var qrFgColor: Color = .black
    @Published var qrBgColor: Color = .white
    @Published var qrCornerRadius: Double = 16.0
    @Published var qrShowBackground: Bool = true
    @Published var qrSelectedFormat: QRExportFormat = .png
    @Published var qrSelectedSize: CGFloat = 1024
    @Published var qrCustomSize: String = "1024"

    // Stock Image State
    @Published var stockSearchQuery: String = ""

    private let bookmarkKey = "LastSelectedFolderBookmark"
    private let pdfFolderBookmarkKey = "LastPDFFolderBookmark"

    init() {
        loadFolderBookmark()
        loadPDFFolderBookmark()
    }

    // MARK: - Bookmark Persistence
    private func saveFolderBookmark() {
        guard let url = targetFolder else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        } catch {
            print("Failed to save folder bookmark: \(error.localizedDescription)")
        }
    }

    private func loadFolderBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                if let freshData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(freshData, forKey: bookmarkKey)
                }
            }
            if url.startAccessingSecurityScopedResource() {
                DispatchQueue.main.async { self.targetFolder = url }
            }
        } catch {
            print("Failed to resolve folder bookmark: \(error.localizedDescription)")
        }
    }

    private func savePDFFolderBookmark() {
        guard let url = pdfCompressionTargetFolder else {
            UserDefaults.standard.removeObject(forKey: pdfFolderBookmarkKey)
            return
        }
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: pdfFolderBookmarkKey)
        } catch {
            print("Failed to save PDF folder bookmark: \(error.localizedDescription)")
        }
    }

    private func loadPDFFolderBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: pdfFolderBookmarkKey) else { return }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                if let freshData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(freshData, forKey: pdfFolderBookmarkKey)
                }
            }
            if url.startAccessingSecurityScopedResource() {
                DispatchQueue.main.async { self.pdfCompressionTargetFolder = url }
            }
        } catch {
            print("Failed to resolve PDF folder bookmark: \(error.localizedDescription)")
        }
    }
}
