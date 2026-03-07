import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage

enum ImageProcessorError: Error, LocalizedError {
    case sourceInvalid
    case destinationCreationFailed
    case formatNotSupported
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .sourceInvalid: return "Could not read the source image."
        case .destinationCreationFailed: return "Could not create the destination file."
        case .formatNotSupported: return "The selected image format is not supported."
        case .conversionFailed: return "Image conversion failed during processing."
        }
    }
}

actor ImageProcessor {
    static let shared = ImageProcessor()
    
    func processImage(
        sourceURL: URL,
        destinationFolder: URL,
        format: ImageFormat,
        quality: Double, // 1 to 10
        scaling: Double? = nil, // e.g. 0.5 for 50%, 1.0 for original
        customSize: CGSize? = nil,
        preserveMetadata: Bool
    ) async throws -> URL {
        
        // Start accessing security-scoped resources
        let sourceScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        let destScopedAccess = destinationFolder.startAccessingSecurityScopedResource()
        
        defer {
            if sourceScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            if destScopedAccess {
                destinationFolder.stopAccessingSecurityScopedResource()
            }
        }
        
        let fileManager = FileManager.default
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let newExtension = fileExtension(for: format)
        var destinationURL = destinationFolder.appendingPathComponent("\(originalName).\(newExtension)")
        
        // Prevent overwriting: append a number if file exists
        var counter = 1
        while fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = destinationFolder.appendingPathComponent("\(originalName)_\(counter).\(newExtension)")
            counter += 1
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ImageProcessorError.sourceInvalid
        }
        
        let options = NSMutableDictionary()
        
        // Quality Mapping (1-10 mapped to 0.1-1.0)
        let normalizedQuality = min(max(quality / 10.0, 0.1), 1.0)
        options[kCGImageDestinationLossyCompressionQuality] = normalizedQuality
        
        // Scale / Resize Logic
        var downsampleOptions: [CFString: Any] = [:]
        
        if let customSize = customSize, customSize.width > 0 || customSize.height > 0 {
            // Priority: Custom Size
            let maxDimension = max(customSize.width, customSize.height)
            downsampleOptions[kCGImageSourceCreateThumbnailFromImageAlways] = true
            downsampleOptions[kCGImageSourceThumbnailMaxPixelSize] = maxDimension
            downsampleOptions[kCGImageSourceCreateThumbnailWithTransform] = true
        } else if let scaling = scaling, scaling < 1.0 {
            // Secondary Priority: Scale by Percentage (if < 100%)
            if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Double,
               let height = properties[kCGImagePropertyPixelHeight] as? Double {
                let maxDimension = max(width, height) * scaling
                downsampleOptions[kCGImageSourceCreateThumbnailFromImageAlways] = true
                downsampleOptions[kCGImageSourceThumbnailMaxPixelSize] = maxDimension
                downsampleOptions[kCGImageSourceCreateThumbnailWithTransform] = true
            }
        }
        
        var finalImage: CGImage?
        
        if !downsampleOptions.isEmpty {
            finalImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary)
        } else {
            finalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        }
        
        guard let cgImage = finalImage else {
            throw ImageProcessorError.conversionFailed
        }
        
        // --- COMET IMAGE CODEC PATH (WEBP & AVIF) ---
        if format == .webp || format == .avif {
            let codecFormat: CodecFormat = format == .webp ? .webp : .avif
            let isLossless = quality >= 10.0
            let codecQuality = CodecQuality(value: Int(quality * 10.0), lossless: isLossless)
            
            _ = try await CometImageCodec.shared.convert(
                cgImage: cgImage,
                outputURL: destinationURL,
                format: codecFormat,
                quality: codecQuality
            )
            
            return destinationURL
        }
        
        // --- NATIVE IMAGEIO PATH (PNG, JPEG, TIFF, GIF, HEIF) ---
        guard let utType = utTypeIdentifier(for: format) else {
            throw ImageProcessorError.formatNotSupported
        }
        
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, utType as CFString, 1, nil) else {
            throw ImageProcessorError.destinationCreationFailed
        }
        
        // Handle Metadata
        var imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        if !preserveMetadata {
            // Strip metadata by removing standard dictionary keys
            imageProperties.removeValue(forKey: kCGImagePropertyExifDictionary)
            imageProperties.removeValue(forKey: kCGImagePropertyTIFFDictionary)
            imageProperties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        }
        
        CGImageDestinationAddImage(destination, cgImage, imageProperties as CFDictionary)
        
        if !CGImageDestinationFinalize(destination) {
            throw ImageProcessorError.conversionFailed
        }
        
        return destinationURL
    }
    
    private func utTypeIdentifier(for format: ImageFormat) -> String? {
        switch format {
        case .png: return UTType.png.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .webp: return UTType.webP.identifier
        case .avif: return "public.avif"
        case .bmp: return UTType.bmp.identifier
        case .heif: return UTType.heic.identifier // or UTType.heif
        case .tiff: return UTType.tiff.identifier
        case .gif: return UTType.gif.identifier
        }
    }
    
    private func fileExtension(for format: ImageFormat) -> String {
        switch format {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .webp: return "webp"
        case .avif: return "avif"
        case .bmp: return "bmp"
        case .heif: return "heic"
        case .tiff: return "tiff"
        case .gif: return "gif"
        }
    }
}
