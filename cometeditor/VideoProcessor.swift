//
//  VideoProcessor.swift
//  cometeditor
//
//  Stub: UI only until a new conversion backend is wired (no FFmpeg / CVC).
//

import Foundation
import Combine

enum VideoConversionError: Error, LocalizedError {
    case invalidSource
    case cannotCreateAssetWriter
    case cannotCreatePixelBufferPool
    case decoderError
    case writerFailure
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSource: return NSLocalizedString("video.error.invalidSource", comment: "")
        case .cannotCreateAssetWriter: return NSLocalizedString("video.error.assetWriter", comment: "")
        case .cannotCreatePixelBufferPool: return NSLocalizedString("video.error.pixelBufferPool", comment: "")
        case .decoderError: return NSLocalizedString("video.error.decoder", comment: "")
        case .writerFailure: return NSLocalizedString("video.error.writerFailure", comment: "")
        case .converterUnavailable: return NSLocalizedString("app.comingSoon.message", comment: "")
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
        _ = (inputURL, outputURL, format, quality, settings)
        throw VideoConversionError.converterUnavailable
    }
}
