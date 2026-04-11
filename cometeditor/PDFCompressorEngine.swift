//
//  PDFCompressorEngine.swift
//  cometeditor
//
//  PDFCompressor projesinden taşınan vektör-koruyucu sıkıştırma motoru
//  (ImageStreamOptimizer + VectorPreservingCompressor).
//

import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Compression Configuration

struct CompressionConfig {
    var imageQuality: CGFloat
    var maxImageDPI: CGFloat
    var preferHEIC: Bool
    var stripMetadata: Bool
    var deduplicateStreams: Bool
    var subsetFonts: Bool

    init(
        imageQuality: CGFloat = 0.65,
        maxImageDPI: CGFloat = 150,
        preferHEIC: Bool = false,
        stripMetadata: Bool = true,
        deduplicateStreams: Bool = true,
        subsetFonts: Bool = true
    ) {
        self.imageQuality = imageQuality
        self.maxImageDPI = maxImageDPI
        self.preferHEIC = preferHEIC
        self.stripMetadata = stripMetadata
        self.deduplicateStreams = deduplicateStreams
        self.subsetFonts = subsetFonts
    }
}

// MARK: - Compression Result

struct CompressionResult {
    let originalSize: Int64
    let compressedSize: Int64
    let outputURL: URL
    let pageCount: Int
    let imagesProcessed: Int
    let duration: TimeInterval
}

// MARK: - Errors

enum PDFCompressorError: LocalizedError {
    case fileNotFound(URL)
    case invalidPDF(URL)
    case outputWriteFailed(URL)
    case cgContextFailed
    case noPages

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url): return "Dosya bulunamadı: \(url.lastPathComponent)"
        case .invalidPDF(let url): return "Geçersiz PDF: \(url.lastPathComponent)"
        case .outputWriteFailed(let url): return "Çıktı yazılamadı: \(url.path)"
        case .cgContextFailed: return "CG render context oluşturulamadı"
        case .noPages: return "PDF'de sayfa bulunamadı"
        }
    }
}

// MARK: - Vector-Preserving Compressor

/// PDF içindeki raster resim stream'lerini optimize eder; metin/vektör içeriğine dokunmaz.
final class VectorPreservingCompressor {

    private let config: CompressionConfig

    init(config: CompressionConfig) {
        self.config = config
    }

    func compress(inputURL: URL, outputURL: URL) throws -> CompressionResult {
        let start = Date()

        let originalSize = fileSizeBytes(inputURL)

        guard let srcDoc = CGPDFDocument(inputURL as CFURL) else {
            throw PDFCompressorError.invalidPDF(inputURL)
        }
        let pageCount = srcDoc.numberOfPages
        guard pageCount > 0 else { throw PDFCompressorError.noPages }

        guard let pdfData = try? Data(contentsOf: inputURL) else {
            throw PDFCompressorError.fileNotFound(inputURL)
        }

        let optimizer = ImageStreamOptimizer(config: config)
        let optimizedData = optimizer.optimizeImageStreams(pdfData: pdfData)

        let finalData: Data
        if config.stripMetadata {
            finalData = stripPDFMetadata(from: optimizedData)
        } else {
            finalData = optimizedData
        }

        do {
            try finalData.write(to: outputURL, options: .atomic)
        } catch {
            throw PDFCompressorError.outputWriteFailed(outputURL)
        }

        let compressedSize = fileSizeBytes(outputURL)
        let duration = Date().timeIntervalSince(start)

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: compressedSize,
            outputURL: outputURL,
            pageCount: pageCount,
            imagesProcessed: optimizer.imagesProcessed,
            duration: duration
        )
    }

    private func stripPDFMetadata(from data: Data) -> Data {
        guard var str = String(data: data, encoding: .isoLatin1) else { return data }

        let infoPattern = try? NSRegularExpression(
            pattern: #"<<([^>]*/(Title|Author|Subject|Keywords|Creator|Producer)[^>]*)>>"#,
            options: []
        )
        if let matches = infoPattern?.matches(in: str, range: NSRange(str.startIndex..., in: str)) {
            for match in matches.reversed() {
                if let range = Range(match.range, in: str) {
                    str.replaceSubrange(range, with: "<<>>")
                }
            }
        }

        return str.data(using: .isoLatin1) ?? data
    }

    private func fileSizeBytes(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

// MARK: - Image Stream Optimizer

struct ExtractedImage {
    let width: Int
    let height: Int
    let bitsPerComponent: Int
    let colorComponents: Int
    let rawData: Data
    let format: CGPDFDataFormat
    let originalStreamLength: Int
}

final class ImageStreamOptimizer {

    private let config: CompressionConfig
    private(set) var imagesProcessed = 0
    private(set) var totalBytesSaved = 0

    init(config: CompressionConfig) {
        self.config = config
    }

    func optimizeImageStreams(pdfData: Data) -> Data {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let srcDoc = CGPDFDocument(provider) else {
            return pdfData
        }

        var imageReplacements: [(originalLength: Int, jpegData: Data, width: Int, height: Int)] = []

        for pageNum in 1...srcDoc.numberOfPages {
            guard let page = srcDoc.page(at: pageNum) else { continue }
            let extracted = extractImagesFromPage(page)

            for img in extracted {
                guard let jpegData = recompressExtractedImage(img) else { continue }
                imageReplacements.append((
                    originalLength: img.originalStreamLength,
                    jpegData: jpegData,
                    width: img.width,
                    height: img.height
                ))
            }
        }

        if imageReplacements.isEmpty { return pdfData }

        var result = pdfData
        var searchStart = result.startIndex

        let streamMarker = Data("stream".utf8)
        let endstreamMarker = Data("endstream".utf8)
        let subtypeTag = Data("/Subtype".utf8)
        let imageTag = Data("/Image".utf8)

        while searchStart < result.endIndex {
            guard let streamRange = findData(streamMarker, in: result, from: searchStart) else {
                break
            }

            let lookbackDistance = min(1536, result.distance(from: result.startIndex, to: streamRange.lowerBound))
            let lookbackStart = result.index(streamRange.lowerBound, offsetBy: -lookbackDistance)
            let dictRegion = result[lookbackStart..<streamRange.lowerBound]

            let isImage = containsData(subtypeTag, in: dictRegion) && containsData(imageTag, in: dictRegion)

            guard isImage else {
                searchStart = streamRange.upperBound
                continue
            }

            var contentStart = streamRange.upperBound
            if contentStart < result.endIndex && result[contentStart] == 0x0D { contentStart = result.index(after: contentStart) }
            if contentStart < result.endIndex && result[contentStart] == 0x0A { contentStart = result.index(after: contentStart) }

            guard let endstreamRange = findData(endstreamMarker, in: result, from: contentStart) else {
                searchStart = streamRange.upperBound
                continue
            }

            var contentEnd = endstreamRange.lowerBound
            while contentEnd > contentStart {
                let prev = result.index(before: contentEnd)
                if result[prev] == 0x0A || result[prev] == 0x0D { contentEnd = prev } else { break }
            }

            let originalStreamData = result[contentStart..<contentEnd]
            let dictStr = String(data: Data(dictRegion), encoding: .isoLatin1) ?? ""
            let dictWidth = extractIntValue(from: dictStr, key: "/Width")
            let dictHeight = extractIntValue(from: dictStr, key: "/Height")
            let dictLength = extractIntValue(from: dictStr, key: "/Length")

            var bestMatchIndex: Int?
            for (idx, repl) in imageReplacements.enumerated() {
                let actualLen = originalStreamData.count
                let lengthMatch = (actualLen == repl.originalLength) || (dictLength == repl.originalLength) || abs(actualLen - repl.originalLength) < 20

                if lengthMatch {
                    if let dw = dictWidth, let dh = dictHeight {
                        if dw == repl.width && dh == repl.height {
                            bestMatchIndex = idx
                            break
                        }
                    } else if actualLen > 0 {
                        bestMatchIndex = idx
                    }
                }
            }

            if let idx = bestMatchIndex {
                let replacement = imageReplacements[idx]

                if replacement.jpegData.count < originalStreamData.count || config.imageQuality < 0.95 {
                    let objStart = findObjStart(in: result, before: streamRange.lowerBound)
                    let fullObjectRange = objStart..<endstreamRange.upperBound

                    if let newObject = rebuildImageObject(
                        originalObject: Data(result[fullObjectRange]),
                        newStreamData: replacement.jpegData,
                        newLength: replacement.jpegData.count
                    ) {
                        var newResult = Data()
                        newResult.append(result[result.startIndex..<fullObjectRange.lowerBound])
                        newResult.append(newObject)
                        newResult.append(result[fullObjectRange.upperBound...])
                        result = newResult

                        let newSearchOffset = result.distance(from: result.startIndex, to: fullObjectRange.lowerBound) + newObject.count
                        searchStart = result.index(result.startIndex, offsetBy: min(newSearchOffset, result.count))
                        imagesProcessed += 1
                        totalBytesSaved += max(0, originalStreamData.count - replacement.jpegData.count)
                        continue
                    }
                }
            }

            searchStart = streamRange.upperBound
        }

        return result
    }

    private func extractImagesFromPage(_ page: CGPDFPage) -> [ExtractedImage] {
        class Accumulator {
            var images = [ExtractedImage]()
        }
        let acc = Accumulator()

        guard let pageDict = page.dictionary else { return [] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
              let resources else { return [] }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects),
              let xObjects else { return [] }

        let infoPtr = Unmanaged.passUnretained(acc).toOpaque()

        CGPDFDictionaryApplyBlock(xObjects, { key, object, info in
            guard let info else { return true }
            let acc = Unmanaged<Accumulator>.fromOpaque(info).takeUnretainedValue()

            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return true }
            guard let streamDict = CGPDFStreamGetDictionary(stream) else { return true }

            var subtype: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype),
                  let st = subtype, String(cString: st) == "Image" else { return true }

            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            var bpc: CGPDFInteger = 8
            CGPDFDictionaryGetInteger(streamDict, "Width", &width)
            CGPDFDictionaryGetInteger(streamDict, "Height", &height)
            CGPDFDictionaryGetInteger(streamDict, "BitsPerComponent", &bpc)

            guard width > 0 && height > 0 else { return true }

            var colorComponents = 3
            var csName: UnsafePointer<Int8>?
            if CGPDFDictionaryGetName(streamDict, "ColorSpace", &csName), let cs = csName {
                let csStr = String(cString: cs)
                if csStr == "DeviceGray" { colorComponents = 1 }
                else if csStr == "DeviceCMYK" { colorComponents = 4 }
            }

            var format: CGPDFDataFormat = .raw
            guard let cfData = CGPDFStreamCopyData(stream, &format) else { return true }
            let data = cfData as Data

            var length: CGPDFInteger = data.count
            CGPDFDictionaryGetInteger(streamDict, "Length", &length)

            let extracted = ExtractedImage(
                width: Int(width),
                height: Int(height),
                bitsPerComponent: Int(bpc),
                colorComponents: colorComponents,
                rawData: data,
                format: format,
                originalStreamLength: Int(length)
            )
            acc.images.append(extracted)
            return true
        }, infoPtr)

        return acc.images
    }

    private func recompressExtractedImage(_ img: ExtractedImage) -> Data? {
        let cgImage: CGImage?

        switch img.format {
        case .JPEG2000, .jpegEncoded:
            guard let source = CGImageSourceCreateWithData(img.rawData as CFData, nil) else { return nil }
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)

        case .raw:
            cgImage = createCGImageFromRawPixels(
                data: img.rawData,
                width: img.width,
                height: img.height,
                bitsPerComponent: img.bitsPerComponent,
                colorComponents: img.colorComponents
            )

        @unknown default:
            return nil
        }

        guard let image = cgImage else { return nil }

        let estimatedDPI = CGFloat(img.width) / (595.0 / 72.0)
        let scale = min(1.0, config.maxImageDPI / max(estimatedDPI, 1))
        let finalImage: CGImage

        if scale < 0.90 {
            let newW = Int(CGFloat(image.width) * scale)
            let newH = Int(CGFloat(image.height) * scale)
            finalImage = downsampleCGImage(image, targetWidth: newW, targetHeight: newH) ?? image
        } else {
            finalImage = image
        }

        return encodeAsJPEG(finalImage, quality: config.imageQuality)
    }

    private func createCGImageFromRawPixels(
        data: Data,
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        colorComponents: Int
    ) -> CGImage? {
        let bitsPerPixel = bitsPerComponent * colorComponents
        let bytesPerRow = width * colorComponents * (bitsPerComponent / 8)

        guard data.count >= bytesPerRow * height else { return nil }

        let colorSpace: CGColorSpace
        switch colorComponents {
        case 1: colorSpace = CGColorSpaceCreateDeviceGray()
        case 4: colorSpace = CGColorSpaceCreateDeviceCMYK()
        default: colorSpace = CGColorSpaceCreateDeviceRGB()
        }

        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private func downsampleCGImage(_ image: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        guard targetWidth > 0 && targetHeight > 0 else { return nil }
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage()
    }

    private func encodeAsJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    private func findData(_ needle: Data, in haystack: Data, from: Data.Index) -> Range<Data.Index>? {
        guard from < haystack.endIndex else { return nil }
        return haystack.range(of: needle, options: [], in: from..<haystack.endIndex)
    }

    private func containsData(_ needle: Data, in slice: Data.SubSequence) -> Bool {
        Data(slice).range(of: needle) != nil
    }

    private func extractIntValue(from str: String, key: String) -> Int? {
        guard let keyRange = str.range(of: key) else { return nil }
        let afterKey = str[keyRange.upperBound...]
        let trimmed = afterKey.drop(while: { $0 == " " || $0 == "\n" || $0 == "\r" })
        let numStr = String(trimmed.prefix(while: { $0.isNumber }))
        return Int(numStr)
    }

    private func findObjStart(in data: Data, before: Data.Index) -> Data.Index {
        let lookback = min(200, data.distance(from: data.startIndex, to: before))
        let start = data.index(before, offsetBy: -lookback)
        let region = data[start..<before]

        let objMarker = Data(" obj".utf8)
        if let range = Data(region).range(of: objMarker, options: .backwards) {
            let objPos = data.index(start, offsetBy: range.lowerBound)
            var lineStart = objPos
            while lineStart > start {
                let prevIdx = data.index(before: lineStart)
                let byte = data[prevIdx]
                if byte == 0x0A || byte == 0x0D { break }
                lineStart = prevIdx
            }
            return lineStart
        }
        return start
    }

    private func rebuildImageObject(originalObject: Data, newStreamData: Data, newLength: Int) -> Data? {
        let streamMarker = Data("stream".utf8)
        guard let streamRange = findData(streamMarker, in: originalObject, from: originalObject.startIndex) else {
            return nil
        }

        let dictData = originalObject[originalObject.startIndex..<streamRange.lowerBound]
        guard var dictStr = String(data: dictData, encoding: .isoLatin1) else { return nil }

        dictStr = replaceOrInsertDictKey(in: dictStr, key: "/Filter", value: "/DCTDecode")
        dictStr = replaceOrInsertDictKey(in: dictStr, key: "/Length", value: " \(newLength)")
        dictStr = removeDictKey(in: dictStr, key: "/DecodeParms")

        var result = Data()
        if let dData = dictStr.data(using: .isoLatin1) {
            result.append(dData)
        } else {
            return nil
        }

        result.append(streamMarker)
        result.append(0x0A)
        result.append(newStreamData)
        result.append(Data("\nendstream\nendobj\n".utf8))

        return result
    }

    private func replaceOrInsertDictKey(in dict: String, key: String, value: String) -> String {
        var result = dict

        if let keyRange = result.range(of: key) {
            let afterKey = result[keyRange.upperBound...]
            let trimmed = afterKey.drop(while: { $0 == " " })

            var endIdx = trimmed.startIndex
            var depth = 0
            for (i, ch) in zip(trimmed.indices, trimmed) {
                if ch == "<" { depth += 1 }
                else if ch == ">" { depth -= 1; if depth < 0 { endIdx = i; break } }
                else if ch == "/" && depth == 0 && i != trimmed.startIndex { endIdx = i; break }
                else if ch == "\n" || ch == "\r" { endIdx = trimmed.index(after: i); break }
                endIdx = trimmed.index(after: i)
            }

            result.replaceSubrange(keyRange.upperBound..<endIdx, with: " \(value)")
        }

        return result
    }

    private func removeDictKey(in dict: String, key: String) -> String {
        var result = dict
        guard let keyRange = result.range(of: key) else { return result }

        let afterKey = result[keyRange.upperBound...]
        let trimmed = afterKey.drop(while: { $0 == " " })

        var endIdx = trimmed.startIndex
        if trimmed.first == "<" && trimmed.dropFirst().first == "<" {
            var depth = 0
            for (i, ch) in zip(trimmed.indices, trimmed) {
                if ch == "<" { depth += 1 }
                else if ch == ">" {
                    depth -= 1
                    if depth <= 0 {
                        endIdx = trimmed.index(after: i)
                        break
                    }
                }
                endIdx = trimmed.index(after: i)
            }
        } else {
            for (i, ch) in zip(trimmed.indices, trimmed) {
                if (ch == "/" || ch == ">") && i != trimmed.startIndex {
                    endIdx = i
                    break
                }
                if ch == "\n" || ch == "\r" { endIdx = trimmed.index(after: i); break }
                endIdx = trimmed.index(after: i)
            }
        }

        result.replaceSubrange(keyRange.lowerBound..<endIdx, with: "")
        return result
    }
}
