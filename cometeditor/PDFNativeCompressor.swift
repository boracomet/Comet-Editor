//
//  PDFNativeCompressor.swift
//  cometeditor
//
//  Hibrit PDF sıkıştırıcı.
//  Her sayfa için image render alanının sayfa alanına oranı hesaplanır:
//    - Coverage < %20 → drawPDFPage stream-copy (metin/vektör/bayrak vb. korunur)
//    - Coverage ≥ %20 → bitmap render → JPEG encode (görsel ağırlıklı sayfa)
//
//  Kalite → JPEG quality:
//    %25 → 0.40  (agresif)
//    %50 → 0.65  (dengeli)
//    %75 → 0.82  (yüksek kalite)
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PDFKit

// MARK: - Kalite seviyesi

enum PDFCompressionQuality: Int, CaseIterable, Identifiable {
    case low    = 25
    case medium = 50
    case high   = 75

    var id: Int { rawValue }

    var jpegQuality: CGFloat {
        switch self {
        case .low:    return 0.40
        case .medium: return 0.65
        case .high:   return 0.82
        }
    }

    nonisolated var maxLongEdgePx: CGFloat {
        switch self {
        case .low:    return 1280
        case .medium: return 1600
        case .high:   return 2048
        }
    }

    var label: String { "\(rawValue)%" }
}

// MARK: - Tahmini boyut

enum PDFSizeEstimator {
    /// CGPDFDocument'ı analiz eder; coverage-based hibrit stratejiye göre tahmini boyut döner.
    nonisolated static func estimate(data: Data, quality: PDFCompressionQuality) -> Int64 {
        guard data.count > 5 else { return -1 }

        guard let cfData = CFDataCreate(nil, (data as NSData).bytes.assumingMemoryBound(to: UInt8.self), data.count),
              let provider = CGDataProvider(data: cfData),
              let cgDoc = CGPDFDocument(provider) else {
            return fallbackEstimate(data: data, quality: quality)
        }

        let pageCount = cgDoc.numberOfPages
        guard pageCount > 0 else { return fallbackEstimate(data: data, quality: quality) }

        // Kalibre edilmiş bytes/pixel (source.pdf ölçümlerinden)
        let bytesPerPixel: Double = switch quality {
        case .low:    0.076
        case .medium: 0.117
        case .high:   0.128
        }

        var rasterJPEGBytes: Int64 = 0

        for i in 1...pageCount {
            guard let page = cgDoc.page(at: i) else { continue }
            let bounds = page.getBoxRect(.mediaBox)
            let coverage = imageRenderCoverage(page: page)

            if coverage >= 0.20 {
                // Rasterize edilecek sayfa
                let longEdge = max(bounds.width, bounds.height)
                let scale = min(quality.maxLongEdgePx / longEdge, 2.0)
                let pxW = max(1.0, bounds.width * scale)
                let pxH = max(1.0, bounds.height * scale)
                rasterJPEGBytes += Int64(pxW * pxH * bytesPerPixel)
            }
        }

        // Sabit overhead: font/xref/metadata/stream-copy sayfaları ≈ 820 KB
        let overhead: Int64 = 820_000
        return max(rasterJPEGBytes + overhead, 1024)
    }

    // MARK: - Fallback

    private nonisolated static func fallbackEstimate(data: Data, quality: PDFCompressionQuality) -> Int64 {
        let ratio: Double = switch quality {
        case .low: 0.15; case .medium: 0.27; case .high: 0.42
        }
        return Int64(Double(data.count) * ratio)
    }

    // MARK: - Coverage hesabı (PDFNativeCompressor ile paylaşılır)

    /// Content stream'i parse ederek image XObject'lerin render alanının
    /// sayfa alanına oranını döner (0.0–1.0+).
    nonisolated static func imageRenderCoverage(page: CGPDFPage) -> Double {
        let bounds = page.getBoxRect(.mediaBox)
        let pageArea = Double(bounds.width * bounds.height)
        guard pageArea > 0 else { return 0 }

        // XObject isimlerini al — sadece Image subtype'ları
        guard let pgDict = page.dictionary else { return 0 }
        var res: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pgDict, "Resources", &res), let res else { return 0 }
        var xo: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(res, "XObject", &xo), let xo else { return 0 }

        var imageNames = Set<String>()
        withUnsafeMutablePointer(to: &imageNames) { ptr in
            CGPDFDictionaryApplyBlock(xo, { key, obj, ctx in
                guard let ctx else { return true }
                let names = ctx.assumingMemoryBound(to: Set<String>.self)
                var st: CGPDFStreamRef?
                guard CGPDFObjectGetValue(obj, .stream, &st), let st,
                      let d = CGPDFStreamGetDictionary(st) else { return true }
                var sub: UnsafePointer<CChar>?
                guard CGPDFDictionaryGetName(d, "Subtype", &sub),
                      let sub, String(cString: sub) == "Image" else { return true }
                names.pointee.insert(String(cString: key))
                return true
            }, ptr)
        }
        guard !imageNames.isEmpty else { return 0 }

        // Content stream token parser — cm + Do operatörlerini izle
        guard let contentData = pageContentData(page: page),
              let text = String(data: contentData, encoding: .isoLatin1) else { return 0 }

        let tokens = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var stack: [String] = []
        var matrixStack: [CGAffineTransform] = [.identity]
        var current = CGAffineTransform.identity
        var totalArea: Double = 0

        for token in tokens {
            switch token {
            case "q":
                matrixStack.append(current)
                stack.removeAll()
            case "Q":
                current = matrixStack.popLast() ?? .identity
                stack.removeAll()
            case "cm":
                if stack.count >= 6 {
                    let nums = stack.suffix(6).compactMap { Double($0) }
                    if nums.count == 6 {
                        let m = CGAffineTransform(a: nums[0], b: nums[1],
                                                  c: nums[2], d: nums[3],
                                                  tx: nums[4], ty: nums[5])
                        current = m.concatenating(current)
                    }
                }
                stack.removeAll()
            case "Do":
                if let name = stack.last {
                    // XObject adı / ile gelebilir, temizle
                    let clean = name.hasPrefix("/") ? String(name.dropFirst()) : name
                    if imageNames.contains(clean) {
                        let area = abs(Double(current.a) * Double(current.d)
                                     - Double(current.b) * Double(current.c))
                        totalArea += area
                    }
                }
                stack.removeAll()
            default:
                stack.append(token)
            }
        }

        return totalArea / pageArea
    }

    // MARK: - Content stream verisi

    nonisolated static func pageContentData(page: CGPDFPage) -> Data? {
        guard let d = page.dictionary else { return nil }
        // Tek stream
        var st: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(d, "Contents", &st), let st {
            var fmt: CGPDFDataFormat = .raw
            if let data = CGPDFStreamCopyData(st, &fmt) { return Data(referencing: data) }
        }
        // Array of streams
        var arr: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(d, "Contents", &arr), let arr {
            var combined = Data()
            for i in 0..<CGPDFArrayGetCount(arr) {
                var obj: CGPDFObjectRef?
                guard CGPDFArrayGetObject(arr, i, &obj), let obj else { continue }
                var s: CGPDFStreamRef?
                guard CGPDFObjectGetValue(obj, .stream, &s), let s else { continue }
                var fmt: CGPDFDataFormat = .raw
                if let data = CGPDFStreamCopyData(s, &fmt) { combined.append(Data(referencing: data)) }
            }
            return combined.isEmpty ? nil : combined
        }
        return nil
    }
}

// MARK: - Compressor

enum PDFNativeCompressor {

    struct PageInfo: @unchecked Sendable {
        let cgPage: CGPDFPage
        let bounds: CGRect
        /// true → bitmap render + JPEG; false → stream-copy (metin/vektör korunur)
        let shouldRasterize: Bool
    }

    /// PDF sıkıştır, progress 0→1 döner.
    static func compress(
        sourceURL: URL,
        destURL: URL,
        quality: PDFCompressionQuality,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async -> Bool {
        guard let cgDoc = CGPDFDocument(sourceURL as CFURL) else { return false }
        let pageCount = cgDoc.numberOfPages
        guard pageCount > 0 else { return false }

        // Sayfa analizleri
        var pages: [PageInfo] = []
        for i in 1...pageCount {
            guard let page = cgDoc.page(at: i) else { continue }
            let bounds = page.getBoxRect(.mediaBox)
            let coverage = PDFSizeEstimator.imageRenderCoverage(page: page)
            // Coverage ≥ %20 → rasterize; altında → stream-copy
            pages.append(PageInfo(cgPage: page, bounds: bounds, shouldRasterize: coverage >= 0.20))
        }
        guard !pages.isEmpty else { return false }

        var firstBox = pages[0].bounds
        guard let outCtx = CGContext(destURL as CFURL, mediaBox: &firstBox, nil) else { return false }

        let jpegQ = quality.jpegQuality
        let maxPx = quality.maxLongEdgePx

        for (idx, info) in pages.enumerated() {
            var box = info.bounds

            if info.shouldRasterize {
                // Görsel ağırlıklı sayfa → bitmap render → JPEG
                let longEdge = max(info.bounds.width, info.bounds.height)
                let scale    = min(maxPx / longEdge, 2.0)
                let pxW = max(1, Int(info.bounds.width  * scale))
                let pxH = max(1, Int(info.bounds.height * scale))

                if let bmp = CGContext(
                    data: nil, width: pxW, height: pxH,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                              | CGImageAlphaInfo.premultipliedFirst.rawValue
                ), let jpegImg = renderToJPEGImage(
                    bmp: bmp, page: info.cgPage,
                    bounds: info.bounds, pxW: pxW, pxH: pxH, quality: jpegQ
                ) {
                    outCtx.beginPage(mediaBox: &box)
                    outCtx.draw(jpegImg, in: info.bounds)
                    outCtx.endPage()
                    onProgress(Double(idx + 1) / Double(pages.count))
                    continue
                }
            }

            // Metin/vektör ağırlıklı → stream-copy (yazılar, vektörler korunur)
            outCtx.beginPage(mediaBox: &box)
            outCtx.drawPDFPage(info.cgPage)
            outCtx.endPage()
            onProgress(Double(idx + 1) / Double(pages.count))
        }

        outCtx.closePDF()
        return FileManager.default.fileExists(atPath: destURL.path)
    }

    // MARK: - Helpers

    private static func renderToJPEGImage(
        bmp: CGContext,
        page: CGPDFPage,
        bounds: CGRect,
        pxW: Int, pxH: Int,
        quality: CGFloat
    ) -> CGImage? {
        bmp.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bmp.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        bmp.scaleBy(x: CGFloat(pxW) / bounds.width,
                    y: CGFloat(pxH) / bounds.height)
        bmp.drawPDFPage(page)

        guard let rawImg = bmp.makeImage() else { return nil }

        let jpegData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            jpegData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, rawImg, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        // JPEG-backed CGImage → CGContext JPEG stream olarak gömer
        guard let src = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let jpegImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return jpegImg
    }
}
