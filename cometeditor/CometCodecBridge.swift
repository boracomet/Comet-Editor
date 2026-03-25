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

public struct CodecMetrics {
    public let decodeTimeUs: UInt64
    public let encodeTimeUs: UInt64
    public let totalTimeUs: UInt64
    public let peakMemoryBytes: Int
    public let inputSizeBytes: Int
    public let outputSizeBytes: Int
}

public struct CodecQuality {
    public var value: Int32
    public var lossless: Bool

    nonisolated public init(value: Int, lossless: Bool = false) {
        self.value = Int32(max(0, min(100, value)))
        self.lossless = lossless
    }
}

// MARK: - MagickWand Bridge

private let logger = Logger(subsystem: "com.cometeditor", category: "CometImageCodec")

public class CometImageCodec {
    public static let shared = CometImageCodec()

    private init() {
        MagickWandGenesis()
    }

    deinit {
        MagickWandTerminus()
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

        let start = DispatchTime.now()

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let bufferSize = bytesPerRow * height

        // CGContext ve piksel kopyalaması Task içinde yapılıyor;
        // böylece ctx'in ömrü pixelData'nın ömrüyle garantili örtüşüyor.
        return try await Task.detached(priority: .userInitiated) {
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

            // Memory'e yaz (blob) — sandbox izin sorununu önler
            var blobSize: Int = 0
            guard let blobPtr = MagickGetImagesBlob(wand, &blobSize), blobSize > 0 else {
                logger.error("MagickGetImagesBlob failed for format: \(finalFormat)")
                throw CodecError.encodeFailed
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

            return CodecMetrics(
                decodeTimeUs: 0,
                encodeTimeUs: us,
                totalTimeUs: us,
                peakMemoryBytes: bufferSize,
                inputSizeBytes: bufferSize,
                outputSizeBytes: outputData.count
            )
        }.value
    }
}
