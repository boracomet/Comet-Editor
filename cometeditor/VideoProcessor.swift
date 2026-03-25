//
//  VideoProcessor.swift
//  cometeditor
//
//  FFmpeg tabanlı video dönüştürme motoru.
//

import Foundation
import Combine
import AVFoundation

enum VideoConversionError: Error, LocalizedError {
    case invalidSource
    case cannotCreateAssetWriter
    case cannotCreatePixelBufferPool
    case decoderError
    case writerFailure
    case converterUnavailable
    case ffmpegNotFound

    var errorDescription: String? {
        switch self {
        case .invalidSource: return NSLocalizedString("video.error.invalidSource", comment: "")
        case .cannotCreateAssetWriter: return NSLocalizedString("video.error.assetWriter", comment: "")
        case .cannotCreatePixelBufferPool: return NSLocalizedString("video.error.pixelBufferPool", comment: "")
        case .decoderError: return NSLocalizedString("video.error.decoder", comment: "")
        case .writerFailure: return NSLocalizedString("video.error.writerFailure", comment: "")
        case .converterUnavailable: return NSLocalizedString("app.comingSoon.message", comment: "")
        case .ffmpegNotFound: return "FFmpeg binary not found in app bundle."
        }
    }
}

@MainActor
class VideoProcessor: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var isProcessing: Bool = false

    init() {}

    func convert(
        inputURL: URL,
        outputURL: URL,
        format: VideoFormat,
        quality: Double,
        settings: VideoConversionSettings? = nil,
        manageProcessingState: Bool = true
    ) async throws {
        if manageProcessingState {
            isProcessing = true
            progress = 0.0
        }
        defer {
            if manageProcessingState {
                isProcessing = false
            }
        }

        // FFmpeg binary kontrolü
        guard FFmpegBridge.ffmpegURL() != nil else {
            throw VideoConversionError.ffmpegNotFound
        }

        // Video süresini al (progress hesabı için)
        let duration = await loadDuration(from: inputURL)

        let convSettings = settings ?? VideoConversionSettings(
            fpsLimit: .original,
            resolutionScale: .original,
            removeAudio: false,
            keepMetadata: true
        )

        let argBuilder = FFmpegArgBuilder(
            inputURL: inputURL,
            outputURL: outputURL,
            format: format,
            quality: quality,
            settings: convSettings
        )
        let arguments = argBuilder.build()

        // Cancellation için Task kontrol noktası
        try Task.checkCancellation()

        let progressCapture: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in
                self?.progress = value
            }
        }

        do {
            try await FFmpegBridge.shared.run(
                arguments: arguments,
                totalDurationSeconds: duration,
                onProgress: progressCapture
            )
        } catch is CancellationError {
            await FFmpegBridge.shared.cancel()
            throw CancellationError()
        } catch let ffErr as FFmpegError {
            switch ffErr {
            case .binaryNotFound:
                throw VideoConversionError.ffmpegNotFound
            case .cancelled:
                throw CancellationError()
            case .conversionFailed:
                throw VideoConversionError.writerFailure
            }
        }
    }

    // MARK: - Helpers

    private func loadDuration(from url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(duration)
            if secs.isFinite && secs > 0 { return secs }
        }
        return 0
    }
}
