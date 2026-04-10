import SwiftUI
import Foundation
import Combine
import os
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
    /// AVFoundation'ın desteklemediği formatlar (AVI, WMV vb.) için ffmpeg ile
    /// oluşturulan geçici MP4 dosyası. Preview bu URL üzerinden oynatılır.
    var playbackURL: URL?

    var isCompleted: Bool = false
    var savedSizeString: String? = nil
    var convertedSizeString: String? = nil

    var fileName: String { url.lastPathComponent }

    /// AVFoundation'ın doğrudan desteklemediği formatlar
    static let avUnsupportedExtensions: Set<String> = ["avi", "wmv", "flv", "mkv", "webm", "mpeg", "mpg", "3gp"]
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

// Snapshot of a full PDF document state for undo/redo (used for reorder/compress)
struct PDFSnapshot {
    let documentData: Data // full serialized PDF
}

// Single deleted page stored for fast page-level undo/redo
struct PDFDeletedPage {
    let originalIndex: Int
    let pageData: Data  // serialized single-page PDF (fast to capture/restore)
}

// Undo/redo entry: either a full doc snapshot (reorder, compress) or page-level op (deletion)
enum PDFUndoEntry {
    case fullSnapshot(PDFSnapshot)
    /// Applying = re-insert stored pages at their original indices (undo of a deletion)
    case pageInsertion([PDFDeletedPage])
    /// Applying = re-delete pages at stored indices (redo of a deletion)
    case pageDeletion([PDFDeletedPage])
}

class GlobalAppState: ObservableObject {
    /// Hangi menü öğesinde batch işlem devam ediyor — sidebar'da loader gösterilir
    @Published var processingMenuItem: MenuItem? = nil
    /// Video dönüşüm task'ı — iptal için (VideoConvertView dışından da erişilebilir)
    var videoConversionTask: Task<Void, Never>? = nil

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
    @Published var pdfIsDeletingPage = false

    // Undo/Redo stacks
    private(set) var pdfUndoStack: [PDFUndoEntry] = []
    private(set) var pdfRedoStack: [PDFUndoEntry] = []

    var canUndo: Bool { !pdfUndoStack.isEmpty }
    var canRedo: Bool { !pdfRedoStack.isEmpty }

    private let maxUndoStackSize = 10

    // Push a full-document snapshot (used for reorder, compress, add-content)
    func pushPDFUndo(data: Data) {
        pdfUndoStack.append(.fullSnapshot(PDFSnapshot(documentData: data)))
        if pdfUndoStack.count > maxUndoStackSize { pdfUndoStack.removeFirst() }
        pdfRedoStack = []
        objectWillChange.send()
    }

    // Push a fast page-deletion undo entry (stores only deleted page(s), not the full doc)
    func pushPageDeletionUndo(_ records: [PDFDeletedPage]) {
        pdfUndoStack.append(.pageInsertion(records))
        if pdfUndoStack.count > maxUndoStackSize { pdfUndoStack.removeFirst() }
        pdfRedoStack = []
        objectWillChange.send()
    }

    func pdfUndo(document: PDFDocument) {
        guard let entry = pdfUndoStack.popLast() else { return }
        switch entry {
        case .fullSnapshot(let snapshot):
            if let currentData = document.dataRepresentation() {
                pdfRedoStack.append(.fullSnapshot(PDFSnapshot(documentData: currentData)))
            }
            restoreSnapshot(snapshot, into: document)

        case .pageInsertion(let records):
            // Undo a deletion: re-insert pages; push pageDeletion (same records) for redo
            pdfRedoStack.append(.pageDeletion(records))
            let sorted = records.sorted { $0.originalIndex < $1.originalIndex }
            for record in sorted {
                if let singleDoc = PDFDocument(data: record.pageData),
                   let page = singleDoc.page(at: 0) {
                    let insertAt = min(record.originalIndex, document.pageCount)
                    document.insert(page, at: insertAt)
                }
            }
            if let first = sorted.first {
                pdfPageIndex = min(first.originalIndex, document.pageCount - 1)
            }
            pdfDocumentVersion += 1
            objectWillChange.send()

        case .pageDeletion:
            // pageDeletion lives only in the redo stack, not the undo stack — ignore
            break
        }
    }

    func pdfRedo(document: PDFDocument) {
        guard let entry = pdfRedoStack.popLast() else { return }
        switch entry {
        case .fullSnapshot(let snapshot):
            if let currentData = document.dataRepresentation() {
                pdfUndoStack.append(.fullSnapshot(PDFSnapshot(documentData: currentData)))
            }
            restoreSnapshot(snapshot, into: document)

        case .pageDeletion(let records):
            // Redo a deletion: delete pages again; reuse stored records for undo
            pdfUndoStack.append(.pageInsertion(records))
            let sorted = records.sorted { $0.originalIndex > $1.originalIndex }
            for record in sorted {
                guard record.originalIndex < document.pageCount else { continue }
                document.removePage(at: record.originalIndex)
            }
            pdfPageIndex = min(pdfPageIndex, max(0, document.pageCount - 1))
            pdfDocumentVersion += 1
            objectWillChange.send()

        case .pageInsertion:
            // pageInsertion lives only in the undo stack — ignore
            break
        }
    }

    func clearPDFHistory() {
        pdfUndoStack = []
        pdfRedoStack = []
        objectWillChange.send()
    }

    /// Updates selectedPDF's estimated file size when pages are deleted.
    /// Uses proportional estimation: newSize ≈ oldSize × (newPageCount / oldPageCount)
    func updateSelectedPDFSizeAfterPageDeletion(oldPageCount: Int, newPageCount: Int) {
        guard let pdf = selectedPDF, oldPageCount > 0, newPageCount > 0 else { return }
        let newBytes = Int64(Double(pdf.fileSizeBytes) * Double(newPageCount) / Double(oldPageCount))
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        let newSizeString = formatter.string(fromByteCount: newBytes)
        selectedPDF = PDFItem(url: pdf.url, document: pdf.document, fileSizeString: newSizeString, fileSizeBytes: newBytes)
    }

    private func restoreSnapshot(_ snapshot: PDFSnapshot, into document: PDFDocument) {
        guard let restored = PDFDocument(data: snapshot.documentData) else { return }
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
        pdfReorderPageOrder = nil
        let newBytes = Int64(snapshot.documentData.count)
        if let pdf = selectedPDF, newBytes > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = .useAll
            formatter.countStyle = .file
            let newSizeString = formatter.string(fromByteCount: newBytes)
            selectedPDF = PDFItem(url: pdf.url, document: pdf.document, fileSizeString: newSizeString, fileSizeBytes: newBytes)
        }
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

    // Default klasör prompt: kullanıcıya bir kez sorulur
    @Published var showDefaultFolderPrompt: Bool = false
    @Published var pendingDefaultFolderURL: URL? = nil

    /// Bir view'da klasör seçilince çağrılır.
    /// targetFolder henüz ayarlanmamışsa kullanıcıya "varsayılan yap?" diye sorar.
    func handleFolderSelected(_ url: URL) {
        if targetFolder == nil {
            pendingDefaultFolderURL = url
            showDefaultFolderPrompt = true
        }
    }

    // Announcements
    @Published var cachedAnnouncements: [AppConfig.AnnouncementInfo] = []

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

    private enum Keys {
        static let folderBookmark = "LastSelectedFolderBookmark"
        static let pdfFolderBookmark = "LastPDFFolderBookmark"
    }

    init() {
        loadFolderBookmark()
        loadPDFFolderBookmark()
    }

    // MARK: - Bookmark Persistence

    private func saveFolderBookmark() {
        saveBookmark(url: targetFolder, forKey: Keys.folderBookmark)
    }

    private func loadFolderBookmark() {
        loadBookmark(forKey: Keys.folderBookmark) { self.targetFolder = $0 }
    }

    private func savePDFFolderBookmark() {
        saveBookmark(url: pdfCompressionTargetFolder, forKey: Keys.pdfFolderBookmark)
    }

    private func loadPDFFolderBookmark() {
        loadBookmark(forKey: Keys.pdfFolderBookmark) { self.pdfCompressionTargetFolder = $0 }
    }

    private func saveBookmark(url: URL?, forKey key: String) {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cometeditor", category: "GlobalAppState").error("Failed to save bookmark (\(key)): \(error.localizedDescription)")
        }
    }

    private func loadBookmark(forKey key: String, assign: @escaping (URL) -> Void) {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: key)
            }
            if url.startAccessingSecurityScopedResource() {
                DispatchQueue.main.async { assign(url) }
            }
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cometeditor", category: "GlobalAppState").error("Failed to resolve bookmark (\(key)): \(error.localizedDescription)")
        }
    }
}
