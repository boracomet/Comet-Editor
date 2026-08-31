import Foundation
import CoreGraphics
import AppKit
import os

// MARK: - Types

public enum CodecFormat {
    case webp
    case avif
    case auto
}

public enum CodecError: Error {
    case outOfMemory
    case invalidParameter
    case unsupportedFormat
    case fileIoError
    case decodeFailed
    case encodeFailed
    case cancelled
    case unknown(Int32)
}

public struct CodecMetrics: Sendable {
    public let decodeTimeUs: UInt64
    public let encodeTimeUs: UInt64
    public let totalTimeUs: UInt64
    public let peakMemoryBytes: Int
    public let inputSizeBytes: Int
    public let outputSizeBytes: Int
}

/// Continuation'ı en fazla bir kez resume eder (Magick abort asılı kalırsa timeout güvenli).
nonisolated private final class ContinuationGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

public struct CodecQuality {
    public var value: Int32
    public var lossless: Bool

    nonisolated public init(value: Int, lossless: Bool = false) {
        self.value = Int32(max(0, min(100, value)))
        self.lossless = lossless
    }
}

// MARK: - MagickWand abort token

/// MagickProgressMonitor C callback'inden okunabilen iptal bayrağı.
/// `Task.detached` iptali miras almaz; ImageMagick encode de kooperatif değil —
/// progress monitor MagickFalse döndürünce wand işlemi kesilir.
nonisolated final class CodecCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// ImageMagick progress monitor: iptalde MagickFalse → encode/decode abort.
nonisolated private func magickAbortIfCancelled(
    _ text: UnsafePointer<CChar>?,
    _ offset: MagickOffsetType,
    _ span: MagickSizeType,
    _ clientData: UnsafeMutableRawPointer?
) -> MagickBooleanType {
    guard let clientData else { return MagickTrue }
    let token = Unmanaged<CodecCancelToken>.fromOpaque(clientData).takeUnretainedValue()
    return token.isCancelled ? MagickFalse : MagickTrue
}

/// MagickWand uçuş token'ı — MainActor dışı Task.detached'tan da güvenli.
nonisolated private final class InFlightCancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: CodecCancelToken?

    var current: CodecCancelToken? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func replace(_ newToken: CodecCancelToken) {
        lock.lock()
        token = newToken
        lock.unlock()
    }

    func clear(ifSame token: CodecCancelToken) {
        lock.lock()
        if self.token === token { self.token = nil }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let current = token
        lock.unlock()
        current?.cancel()
    }
}

// MARK: - MagickWand Bridge

public class CometImageCodec {
    public static let shared = CometImageCodec()

    private let logger = Logger(subsystem: "com.cometeditor", category: "CometImageCodec")
    private let inFlight = InFlightCancelBox()

    private init() {
        MagickWandGenesis()
    }

    deinit {
        MagickWandTerminus()
    }

    /// Uçuştaki MagickWand encode'u abort eder (progress monitor + token).
    public func cancel() {
        inFlight.cancel()
    }

    /// MagickWand hâlâ encode/abort ediyor mu (UI timeout sonrası ikinci işi bekletmek için).
    public var hasInFlightWork: Bool {
        inFlight.current != nil
    }

    /// CGImage'ı ImageMagick MagickWand ile istenilen formata çevirir.
    /// magickFormat: "PNG", "JPEG", "WEBP", "AVIF", "HEIC", "JP2", "BMP", "TIFF", "GIF"
    public func convert(
        cgImage: CGImage,
        outputURL: URL,
        format: CodecFormat = .auto,
        quality: CodecQuality = CodecQuality(value: 85),
        magickFormat: String? = nil
    ) async throws -> CodecMetrics {

        try Task.checkCancellation()

        // Önceki wand hâlâ abort ediyorsa kısa süre bekle; inFlight paylaşılmasın.
        let inFlight = self.inFlight
        for _ in 0..<40 {
            guard let previous = inFlight.current else { break }
            previous.cancel()
            try await Task.sleep(nanoseconds: 100_000_000)
            try Task.checkCancellation()
        }

        let token = CodecCancelToken()
        inFlight.replace(token)

        let start = DispatchTime.now()

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let bufferSize = bytesPerRow * height

        let gate = ContinuationGate<CodecMetrics>()

        // Continuation ile bekle: parent Task.cancel() Magick abort bitene kadar durur.
        // Progress monitor yanıt vermezse 4 sn sonra UI'yi serbest bırak (çift resume yok).
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CodecMetrics, Error>) in
                gate.attach(continuation)
                Task.detached(priority: .userInitiated) { [logger] in
                    defer { inFlight.clear(ifSame: token) }
                    do {
                        if token.isCancelled { throw CodecError.cancelled }

                        // byteOrder32Little + premultipliedFirst = BGRA (native macOS format)
                        guard let ctx = CGContext(
                            data: nil,
                            width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                        ) else {
                            throw CodecError.decodeFailed
                        }
                        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                        guard let dataPtr = ctx.data else { throw CodecError.decodeFailed }

                        if token.isCancelled { throw CodecError.cancelled }

                        // ctx bu scope'ta hayatta; Data kopyası güvenli.
                        let pixelData = Data(bytes: dataPtr, count: bufferSize)

                        let wand = NewMagickWand()
                        defer { DestroyMagickWand(wand) }

                        // BGRA map: byteOrder32Little+premultipliedFirst = B,G,R,A sırası
                        let importStatus = pixelData.withUnsafeBytes { ptr in
                            MagickConstituteImage(wand, width, height, "BGRA", CharPixel,
                                                  ptr.baseAddress!)
                        }
                        if importStatus != MagickTrue {
                            logger.error("MagickConstituteImage failed")
                            throw CodecError.decodeFailed
                        }

                        if token.isCancelled { throw CodecError.cancelled }

                        let clientPtr = Unmanaged.passUnretained(token).toOpaque()
                        MagickSetProgressMonitor(wand, magickAbortIfCancelled, clientPtr)
                        MagickSetImageProgressMonitor(wand, magickAbortIfCancelled, clientPtr)

                        // Format belirle
                        let finalFormat: String
                        if let mf = magickFormat {
                            finalFormat = mf
                        } else {
                            switch format {
                            case .webp: finalFormat = "WEBP"
                            case .avif: finalFormat = "AVIF"
                            case .auto: finalFormat = "PNG"
                            }
                        }
                        MagickSetFormat(wand, finalFormat)
                        MagickSetImageFormat(wand, finalFormat)

                        // Kalite
                        if quality.lossless {
                            MagickSetImageCompressionQuality(wand, 100)
                            if finalFormat == "WEBP" {
                                MagickSetOption(wand, "webp:lossless", "true")
                            }
                        } else {
                            MagickSetImageCompressionQuality(wand, Int(quality.value))
                        }

                        if token.isCancelled { throw CodecError.cancelled }

                        // Memory'e yaz (blob) — sandbox izin sorununu önler
                        var blobSize: Int = 0
                        guard let blobPtr = MagickGetImagesBlob(wand, &blobSize), blobSize > 0 else {
                            if token.isCancelled {
                                throw CodecError.cancelled
                            }
                            logger.error("MagickGetImagesBlob failed for format: \(finalFormat)")
                            throw CodecError.encodeFailed
                        }

                        if token.isCancelled {
                            MagickRelinquishMemory(blobPtr)
                            throw CodecError.cancelled
                        }

                        let outputData = Data(bytes: blobPtr, count: blobSize)
                        MagickRelinquishMemory(blobPtr)

                        do {
                            try outputData.write(to: outputURL, options: .atomic)
                        } catch {
                            logger.error("Disk write failed: \(error)")
                            throw CodecError.fileIoError
                        }

                        let end = DispatchTime.now()
                        let us = (end.uptimeNanoseconds - start.uptimeNanoseconds) / 1000

                        gate.resume(with: .success(CodecMetrics(
                            decodeTimeUs: 0,
                            encodeTimeUs: us,
                            totalTimeUs: us,
                            peakMemoryBytes: bufferSize,
                            inputSizeBytes: bufferSize,
                            outputSizeBytes: outputData.count
                        )))
                    } catch {
                        gate.resume(with: .failure(error))
                    }
                }
            }
        } onCancel: {
            token.cancel()
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                gate.resume(with: .failure(CodecError.cancelled))
            }
        }
    }
}
