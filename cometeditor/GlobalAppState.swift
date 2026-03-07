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
    case viewer
    case reorder
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
    @Published var pdfCompressionTargetFolder: URL? = nil
    @Published var pdfReorderPageOrder: [Int]? = nil
    
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

    private let bookmarkKey = "LastSelectedFolderBookmark"
    
    init() {
        loadFolderBookmark()
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
                // Bookmark is stale — save fresh bookmark data directly
                if let freshData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(freshData, forKey: bookmarkKey)
                }
            }
            
            // Start accessing the security-scoped resource
            if url.startAccessingSecurityScopedResource() {
                DispatchQueue.main.async {
                    self.targetFolder = url
                }
            }
        } catch {
            print("Failed to resolve folder bookmark: \(error.localizedDescription)")
        }
    }
}
