import SwiftUI
import Foundation
import Combine

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

class GlobalAppState: ObservableObject {
    // Shared File Lists
    @Published var selectedImages: [ImageItem] = []
    @Published var selectedVideos: [VideoItem] = []
    
    // Persistent Folder
    @Published var targetFolder: URL? = nil {
        didSet {
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
