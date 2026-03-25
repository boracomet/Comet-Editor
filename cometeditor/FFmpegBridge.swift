import Foundation
import os

// MARK: - FFmpegBridge
// Bundled ffmpeg binary'yi Process API üzerinden çalıştırır.
// Tüm ffmpeg binary'leri app bundle'ına Resources/ffmpeg olarak eklenir.

enum FFmpegError: Error, LocalizedError {
    case binaryNotFound
    case conversionFailed(Int32, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "FFmpeg binary bulunamadı. Uygulama bütünlüğü bozulmuş olabilir."
        case .conversionFailed(let code, let output):
            return "FFmpeg dönüştürme başarısız (çıkış kodu \(code)): \(output)"
        case .cancelled:
            return "Dönüştürme iptal edildi."
        }
    }
}

actor FFmpegBridge {
    static let shared = FFmpegBridge()

    private let logger = Logger(subsystem: "com.cometeditor", category: "FFmpegBridge")
    private var activeProcess: Process?

    private init() {}

    // Bundle içindeki ffmpeg binary yolunu döndürür
    static func ffmpegURL() -> URL? {
        // App bundle'a eklenen binary: Resources/ffmpeg
        if let url = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            return url
        }
        // Development fallback: third_party/ffmpeg/universal/ffmpeg
        let devPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("third_party/ffmpeg/universal/ffmpeg")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath
        }
        return nil
    }

    /// FFmpeg'i verilen argümanlarla çalıştırır.
    /// progress callback: 0.0 – 1.0 arası değer, MainActor'da çağrılır.
    func run(
        arguments: [String],
        totalDurationSeconds: Double,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {

        guard let ffmpegURL = FFmpegBridge.ffmpegURL() else {
            throw FFmpegError.binaryNotFound
        }

        // Execute permission'ı garanti et
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: ffmpegURL.path
        )

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = arguments

        let outputPipe = Pipe()
        // ffmpeg progress output stderr'e gider
        process.standardError = outputPipe
        process.standardOutput = FileHandle.nullDevice

        let outputHandle = outputPipe.fileHandleForReading
        // stderrBuffer: readabilityHandler'dan güvenli erişim için actor-isolated değil,
        // sadece readabilityHandler serial queue'sinde mutate ediliyor.
        // Swift 6 için nonisolated(unsafe) kullanıyoruz.
        nonisolated(unsafe) var stderrBuffer = ""

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                stderrBuffer += str
                let lines = stderrBuffer.components(separatedBy: "\r")
                for line in lines {
                    if let progress = FFmpegBridge.parseProgress(from: line, totalDuration: totalDurationSeconds) {
                        Task { @MainActor in
                            onProgress(progress)
                        }
                    }
                }
                stderrBuffer = lines.last ?? ""
            }
        }

        activeProcess = process

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            activeProcess = nil
            throw error
        }

        // Process bitene kadar bekle (async-safe)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        outputHandle.readabilityHandler = nil
        activeProcess = nil

        let exitCode = process.terminationStatus
        if exitCode != 0 {
            throw FFmpegError.conversionFailed(exitCode, stderrBuffer)
        }

        // %100 bildir
        Task { @MainActor in
            onProgress(1.0)
        }
    }

    func cancel() {
        activeProcess?.terminate()
        activeProcess = nil
    }

    // MARK: - Progress Parsing
    // ffmpeg progress satırı örneği: "frame= 240 fps=60 ... time=00:00:08.00 ..."
    static func parseProgress(from line: String, totalDuration: Double) -> Double? {
        guard totalDuration > 0 else { return nil }
        guard let timeRange = line.range(of: "time=") else { return nil }

        let afterTime = line[timeRange.upperBound...]
        // HH:MM:SS.xx formatı
        let parts = afterTime.prefix(11).components(separatedBy: CharacterSet(charactersIn: ":"))
        guard parts.count >= 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2].prefix(5)) else { return nil }

        let currentTime = hours * 3600 + minutes * 60 + seconds
        return min(1.0, max(0.0, currentTime / totalDuration))
    }
}

// MARK: - Argument Builder
struct FFmpegArgBuilder {
    let inputURL: URL
    let outputURL: URL
    let format: VideoFormat
    let quality: Double            // 0–10 slider
    let settings: VideoConversionSettings

    func build() -> [String] {
        var args: [String] = []

        // Overwrite output, no interactive prompts
        args += ["-y"]

        // Input
        args += ["-i", inputURL.path]

        // Metadata
        if !settings.keepMetadata {
            args += ["-map_metadata", "-1"]
        }

        // Audio
        if settings.removeAudio {
            args += ["-an"]
        }

        // FPS limit
        if let fps = settings.fpsLimit.value {
            args += ["-r", String(Int(fps))]
        }

        // Resolution scale
        if settings.resolutionScale != .original {
            let m = settings.resolutionScale.multiplier
            // width/height must be divisible by 2 for most codecs
            args += ["-vf", "scale=iw*\(m):ih*\(m),scale=trunc(iw/2)*2:trunc(ih/2)*2"]
        }

        // Codec + quality per format
        switch format {
        case .mp4, .m4v:
            // H.264 via libx264
            let crf = crfH264(quality: quality)
            args += ["-c:v", "libx264", "-crf", "\(crf)", "-preset", "medium"]
            if !settings.removeAudio { args += ["-c:a", "aac", "-b:a", "128k"] }

        case .mov:
            let crf = crfH264(quality: quality)
            args += ["-c:v", "libx264", "-crf", "\(crf)", "-preset", "medium"]
            if !settings.removeAudio { args += ["-c:a", "aac", "-b:a", "128k"] }

        case .mkv:
            // H.265 / HEVC for MKV (better compression)
            let crf = crfH265(quality: quality)
            args += ["-c:v", "libx265", "-crf", "\(crf)", "-preset", "medium"]
            if !settings.removeAudio { args += ["-c:a", "libopus", "-b:a", "128k"] }

        case .avi:
            // MPEG-4 for AVI compatibility
            let qscale = qscaleMpeg4(quality: quality)
            args += ["-c:v", "mpeg4", "-qscale:v", "\(qscale)"]
            if !settings.removeAudio { args += ["-c:a", "libmp3lame", "-q:a", "4"] }

        case .webm:
            // VP9 for WebM
            let crf = crfVP9(quality: quality)
            args += ["-c:v", "libvpx-vp9", "-crf", "\(crf)", "-b:v", "0"]
            if !settings.removeAudio { args += ["-c:a", "libopus", "-b:a", "96k"] }

        case .mpeg:
            // MPEG-2
            let qscale = qscaleMpeg4(quality: quality)
            args += ["-c:v", "mpeg2video", "-qscale:v", "\(qscale)"]
            if !settings.removeAudio { args += ["-c:a", "mp2", "-b:a", "192k"] }

        case .threeGP:
            // 3GP: H.264 + AAC (mobile compatible)
            args += ["-c:v", "libx264", "-crf", "28", "-preset", "fast"]
            args += ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
            if !settings.removeAudio { args += ["-c:a", "aac", "-b:a", "64k"] }

        case .flv:
            // FLV: H.264
            let crf = crfH264(quality: quality)
            args += ["-c:v", "libx264", "-crf", "\(crf)", "-preset", "medium"]
            if !settings.removeAudio { args += ["-c:a", "aac", "-b:a", "128k"] }

        case .wmv:
            // WMV: mpeg4 (wmv2 encoder kapalı olduğu için mpeg4 kullanılır)
            let qscale = qscaleMpeg4(quality: quality)
            args += ["-c:v", "mpeg4", "-qscale:v", "\(qscale)"]
            if !settings.removeAudio { args += ["-c:a", "libmp3lame", "-q:a", "4"] }
        }

        // Output file
        args.append(outputURL.path)

        return args
    }

    // quality 0–10 → CRF 51–18 (higher quality = lower CRF)
    private func crfH264(quality: Double) -> Int {
        let crf = 51 - Int((quality / 10.0) * 33)  // 0→51, 10→18
        return max(18, min(51, crf))
    }

    private func crfH265(quality: Double) -> Int {
        let crf = 51 - Int((quality / 10.0) * 35)  // 0→51, 10→16
        return max(16, min(51, crf))
    }

    private func crfVP9(quality: Double) -> Int {
        let crf = 63 - Int((quality / 10.0) * 45)  // 0→63, 10→18
        return max(18, min(63, crf))
    }

    private func qscaleMpeg4(quality: Double) -> Int {
        let q = 31 - Int((quality / 10.0) * 27)  // 0→31, 10→4
        return max(4, min(31, q))
    }
}
