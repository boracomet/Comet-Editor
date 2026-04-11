//
//  PDFNativeCompressor.swift
//  cometeditor
//
//  Sıkıştırma motoru: PDFCompressor projesindeki VectorPreservingCompressor
//  (görsel stream yeniden sıkıştırma, metin/vektör korunur).
//

import Foundation
import CoreGraphics
import PDFKit

// MARK: - Kalite seviyesi

enum PDFCompressionQuality: Int, CaseIterable, Identifiable {
    case low = 25
    case medium = 50
    case high = 75

    var id: Int { rawValue }

    var label: String { "\(rawValue)%" }

    /// PDFCompressor `CompressionConfig` ile hizalı (DPI + JPEG kalitesi).
    nonisolated var compressionConfig: CompressionConfig {
        switch self {
        case .low:
            return CompressionConfig(
                imageQuality: 0.40,
                maxImageDPI: 96,
                preferHEIC: false,
                stripMetadata: true,
                deduplicateStreams: true,
                subsetFonts: true
            )
        case .medium:
            return CompressionConfig(
                imageQuality: 0.65,
                maxImageDPI: 150,
                preferHEIC: false,
                stripMetadata: true,
                deduplicateStreams: true,
                subsetFonts: true
            )
        case .high:
            return CompressionConfig(
                imageQuality: 0.82,
                maxImageDPI: 240,
                preferHEIC: false,
                stripMetadata: false,
                deduplicateStreams: true,
                subsetFonts: false
            )
        }
    }
}

// MARK: - Tahmini boyut (vector-preserving + görsel yoğunluğu)

enum PDFSizeEstimator {
    /// Yaklaşık çıktı boyutu; kaliteye ve sayfadaki Image XObject sayısına göre ölçeklenir.
    nonisolated static func estimate(data: Data, quality: PDFCompressionQuality) -> Int64 {
        guard data.count > 5 else { return -1 }

        guard let cfData = CFDataCreate(nil, (data as NSData).bytes.assumingMemoryBound(to: UInt8.self), data.count),
              let provider = CGDataProvider(data: cfData),
              let cgDoc = CGPDFDocument(provider) else {
            return fallbackEstimate(data: data, quality: quality)
        }

        let pageCount = cgDoc.numberOfPages
        guard pageCount > 0 else { return fallbackEstimate(data: data, quality: quality) }

        let imageRefs = countImageXObjectReferences(document: cgDoc)
        let original = Int64(data.count)

        // Görsel yoksa: çoğunlukla metadata / küçük kazanç
        if imageRefs == 0 {
            let keep: Double = switch quality {
            case .low: 0.90
            case .medium: 0.93
            case .high: 0.96
            }
            return max(Int64(Double(original) * keep), 1024)
        }

        // Görsel stream optimizasyonu — kaliteye göre taban oran + yoğunluğa göre ince ayar
        var baseRatio: Double = switch quality {
        case .low: 0.26
        case .medium: 0.40
        case .high: 0.54
        }
        // Çok sayıda görsel: ek küçülme eğilimi (logaritmik doygunluk)
        let densityBoost = min(0.12, log1p(Double(min(imageRefs, 80))) * 0.018)
        baseRatio = max(0.12, baseRatio - densityBoost)

        return max(Int64(Double(original) * baseRatio), 1024)
    }

    private nonisolated static func fallbackEstimate(data: Data, quality: PDFCompressionQuality) -> Int64 {
        let ratio: Double = switch quality {
        case .low: 0.22
        case .medium: 0.36
        case .high: 0.50
        }
        return Int64(Double(data.count) * ratio)
    }

    private nonisolated static func countImageXObjectReferences(document: CGPDFDocument) -> Int {
        var total = 0
        for i in 1...document.numberOfPages {
            guard let page = document.page(at: i),
                  let pageDict = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
                  let resources else { continue }
            var xObjects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects),
                  let xObjects else { continue }

            class Counter {
                var n = 0
            }
            let counter = Counter()
            let ptr = Unmanaged.passUnretained(counter).toOpaque()

            CGPDFDictionaryApplyBlock(xObjects, { _, object, ctx in
                guard let ctx else { return true }
                let c = Unmanaged<Counter>.fromOpaque(ctx).takeUnretainedValue()
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return true }
                guard let d = CGPDFStreamGetDictionary(stream) else { return true }
                var subtype: UnsafePointer<Int8>?
                guard CGPDFDictionaryGetName(d, "Subtype", &subtype),
                      let st = subtype,
                      String(cString: st) == "Image" else { return true }
                c.n += 1
                return true
            }, ptr)
            total += counter.n
        }
        return total
    }
}

// MARK: - Compressor

enum PDFNativeCompressor {

    /// PDF sıkıştırır; progress 0→1 (motor senkron; ilerleme kaba adımlarla güncellenir).
    static func compress(
        sourceURL: URL,
        destURL: URL,
        quality: PDFCompressionQuality,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            onProgress(0.08)
            let config = quality.compressionConfig
            let engine = VectorPreservingCompressor(config: config)
            do {
                _ = try engine.compress(inputURL: sourceURL, outputURL: destURL)
                onProgress(1.0)
                return FileManager.default.fileExists(atPath: destURL.path)
            } catch {
                try? FileManager.default.removeItem(at: destURL)
                return false
            }
        }.value
    }
}
