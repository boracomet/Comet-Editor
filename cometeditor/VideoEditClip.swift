import Foundation
import AVFoundation
import AppKit

// MARK: - VideoEditClip Model

struct VideoEditClip: Identifiable, Equatable {
    let id: UUID
    let url: URL
    /// WMV, AVI vb. için bundle ffmpeg ile üretilen geçici MP4 — oynatıcı bunu kullanır; dışa aktarma `url` üzerinden yapılır.
    var previewURL: URL?
    /// Dışa aktarımda özel çözünürlük / otomatik kapla için (0 ise ffprobe ile yeniden okunur).
    let sourceWidth: Int
    let sourceHeight: Int
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

    var playbackURL: URL { previewURL ?? url }

    static func == (lhs: VideoEditClip, rhs: VideoEditClip) { lhs.id == rhs.id }

    init(
        url: URL,
        duration: Double,
        thumbnail: NSImage?,
        fileSizeString: String,
        isImageClip: Bool = false,
        previewURL: URL? = nil,
        sourceWidth: Int = 0,
        sourceHeight: Int = 0
    ) {
        self.id = UUID()
        self.url = url
        self.previewURL = previewURL
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.startTime = 0
        self.endTime = duration
        self.duration = duration
        self.thumbnail = thumbnail
        self.fileSizeString = fileSizeString
        self.isImageClip = isImageClip
        if isImageClip { self.imageDuration = duration }
    }

    static func load(from url: URL) async -> VideoEditClip? {
        let ext = url.pathExtension.lowercased()
        let preferFFmpeg = VideoItem.avUnsupportedExtensions.contains(ext)

        if !preferFFmpeg {
            let asset = AVURLAsset(url: url)
            if let durationValue = try? await asset.load(.duration) {
                let duration = CMTimeGetSeconds(durationValue)
                if duration > 0 {
                    return await makeClip(url: url, duration: duration, thumbnail: nil, previewURL: nil, asset: asset)
                }
            }
        }

        guard let duration = await VideoEditFFmpegProbe.durationSeconds(url: url), duration > 0 else { return nil }
        guard let previewURL = await VideoEditFFmpegProbe.transcodePreviewMP4(url: url) else { return nil }
        let thumb = await VideoEditFFmpegProbe.thumbnailPNG(url: url, maxWidth: 160)
        let asset = AVURLAsset(url: previewURL)
        return await makeClip(url: url, duration: duration, thumbnail: thumb, previewURL: previewURL, asset: asset)
    }

    private static func makeClip(
        url: URL,
        duration: Double,
        thumbnail: NSImage?,
        previewURL: URL?,
        asset: AVURLAsset
    ) async -> VideoEditClip? {
        var sw = 0
        var sh = 0
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let sz = try? await track.load(.naturalSize),
           let tr = try? await track.load(.preferredTransform) {
            let r = CGRect(origin: .zero, size: sz).applying(tr)
            sw = Int(abs(r.width).rounded())
            sh = Int(abs(r.height).rounded())
        }
        if sw < 2 || sh < 2, let px = await VideoEditFFmpegProbe.videoPixelSize(url: url) {
            sw = px.0
            sh = px.1
        }

        let thumb: NSImage?
        if let thumbnail {
            thumb = thumbnail
        } else {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)
            let thumbTime = CMTime(seconds: min(1.0, duration * 0.1), preferredTimescale: 600)
            thumb = await withCheckedContinuation { cont in
                generator.generateCGImageAsynchronously(for: thumbTime) { img, _, _ in
                    if let img { cont.resume(returning: NSImage(cgImage: img, size: .zero)) }
                    else { cont.resume(returning: nil) }
                }
            }
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? Int64) ?? 0
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file

        return VideoEditClip(
            url: url,
            duration: duration,
            thumbnail: thumb,
            fileSizeString: fmt.string(fromByteCount: bytes),
            previewURL: previewURL,
            sourceWidth: sw,
            sourceHeight: sh
        )
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

        let (pw, ph) = pixelSize(for: image)
        var clip = VideoEditClip(
            url: url,
            duration: duration,
            thumbnail: thumb,
            fileSizeString: fmt.string(fromByteCount: bytes),
            isImageClip: true,
            sourceWidth: pw,
            sourceHeight: ph
        )
        clip.fullImage = image
        return clip
    }

    private static func pixelSize(for image: NSImage) -> (Int, Int) {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (max(1, Int(image.size.width)), max(1, Int(image.size.height)))
    }
}

// MARK: - ffprobe / ffmpeg (VideoConvertView ile aynı bundle ikilisi)

private enum VideoEditFFmpegProbe {
    static func ffprobeURL() -> URL? {
        guard let ffmpeg = FFmpegBridge.ffmpegURL() else { return nil }
        let probe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        return FileManager.default.fileExists(atPath: probe.path) ? probe : nil
    }

    static func durationSeconds(url: URL) async -> Double? {
        guard let ffprobeURL = ffprobeURL() else { return nil }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = ffprobeURL
            process.arguments = [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                url.path
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let format = json["format"] as? [String: Any],
                  let durStr = format["duration"] as? String,
                  let dur = Double(durStr), dur > 0 else { return nil }
            return dur
        }.value
    }

    static func videoPixelSize(url: URL) async -> (Int, Int)? {
        guard let ffprobeURL = ffprobeURL() else { return nil }
        return await Task.detached(priority: .utility) { () -> (Int, Int)? in
            let process = Process()
            process.executableURL = ffprobeURL
            process.arguments = [
                "-v", "quiet",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height",
                "-print_format", "json",
                url.path
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streams = json["streams"] as? [[String: Any]],
                  let first = streams.first,
                  let w = first["width"] as? Int,
                  let h = first["height"] as? Int,
                  w > 0, h > 0 else { return nil }
            return (w, h)
        }.value
    }

    static func thumbnailPNG(url: URL, maxWidth: Int) async -> NSImage? {
        guard let ffmpegURL = FFmpegBridge.ffmpegURL() else { return nil }
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ve_thumb_\(UUID().uuidString).png")
        let data: Data? = await Task.detached(priority: .utility) { () -> Data? in
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = [
                "-y",
                "-i", url.path,
                "-vframes", "1",
                "-vf", "scale=\(maxWidth):-1",
                "-f", "image2",
                tmpURL.path
            ]
            process.standardError = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            guard process.terminationStatus == 0 else { return nil }
            return try? Data(contentsOf: tmpURL)
        }.value
        return data.flatMap { NSImage(data: $0) }
    }

    static func transcodePreviewMP4(url: URL) async -> URL? {
        guard let ffmpegURL = FFmpegBridge.ffmpegURL() else { return nil }
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ve_preview_\(UUID().uuidString).mp4")
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = [
                "-y", "-i", url.path,
                "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
                "-c:a", "aac", "-b:a", "96k",
                "-movflags", "+faststart",
                tmpURL.path
            ]
            process.standardError = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return tmpURL
        }.value
    }
}
