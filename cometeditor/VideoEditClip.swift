import Foundation
import AVFoundation
import AppKit

// MARK: - VideoEditClip Model

struct VideoEditClip: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var startTime: Double
    var endTime: Double
    var duration: Double
    var thumbnail: NSImage?
    var fileName: String { url.lastPathComponent }
    var trimmedDuration: Double { max(0, endTime - startTime) }
    var fileSizeString: String

    var isImageClip: Bool = false
    var imageDuration: Double = 5.0
    var fullImage: NSImage?

    static func == (lhs: VideoEditClip, rhs: VideoEditClip) -> Bool { lhs.id == rhs.id }

    init(url: URL, duration: Double, thumbnail: NSImage?, fileSizeString: String, isImageClip: Bool = false) {
        self.id = UUID()
        self.url = url
        self.startTime = 0
        self.endTime = duration
        self.duration = duration
        self.thumbnail = thumbnail
        self.fileSizeString = fileSizeString
        self.isImageClip = isImageClip
        if isImageClip { self.imageDuration = duration }
    }

    static func load(from url: URL) async -> VideoEditClip? {
        let asset = AVURLAsset(url: url)
        guard let durationValue = try? await asset.load(.duration) else { return nil }
        let duration = CMTimeGetSeconds(durationValue)
        guard duration > 0 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        let thumbTime = CMTime(seconds: min(1.0, duration * 0.1), preferredTimescale: 600)
        let thumb: NSImage? = await withCheckedContinuation { cont in
            generator.generateCGImageAsynchronously(for: thumbTime) { img, _, _ in
                if let img { cont.resume(returning: NSImage(cgImage: img, size: .zero)) }
                else { cont.resume(returning: nil) }
            }
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? Int64) ?? 0
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file

        return VideoEditClip(url: url, duration: duration, thumbnail: thumb, fileSizeString: fmt.string(fromByteCount: bytes))
    }

    static let supportedImageExtensions = Set(["png", "jpg", "jpeg", "webp", "heic", "bmp", "tiff", "tif", "gif", "avif"])

    static func loadImage(from url: URL, duration: Double) async -> VideoEditClip? {
        guard let image = NSImage(contentsOf: url) else { return nil }

        let thumbSize = CGSize(width: 160, height: 90)
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? Int64) ?? 0
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file

        var clip = VideoEditClip(url: url, duration: duration, thumbnail: thumb,
                                 fileSizeString: fmt.string(fromByteCount: bytes), isImageClip: true)
        clip.fullImage = image
        return clip
    }
}
