//
//  BgRemoveEngine.swift
//  cometeditor
//
//  macOS 14+: VNGenerateForegroundInstanceMaskRequest
//  + vImage erode/dilate (Accelerate)
//  + CoreImage GaussianBlur feather + BlendWithMask

import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate
import AppKit

@available(macOS 14.0, *)
final class BgRemoveEngine {
    static let shared = BgRemoveEngine()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private init() {}

    // MARK: - Public

    func removeBackground(from cgImage: CGImage, featherRadius: Float = 1.5) async throws -> CGImage {
        let mask = try await generateMask(for: cgImage)
        return try applyMask(image: cgImage, mask: mask, featherRadius: featherRadius)
    }

    // MARK: - Step 1: Vision mask

    private func generateMask(for cgImage: CGImage) async throws -> CGImage {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateForegroundInstanceMaskRequest { req, error in
                if let error { continuation.resume(throwing: error); return }
                guard let obs = req.results?.first as? VNInstanceMaskObservation else {
                    continuation.resume(throwing: BgRemoveError.noMaskFound); return
                }
                do {
                    let buffer = try obs.generateScaledMaskForImage(
                        forInstances: obs.allInstances, from: handler
                    )
                    let ci = CIImage(cvPixelBuffer: buffer)
                    let size = CGSize(width: cgImage.width, height: cgImage.height)
                    let scaled = ci.transformed(by: CGAffineTransform(
                        scaleX: size.width / ci.extent.width,
                        y: size.height / ci.extent.height
                    ))
                    guard let mask = self.ciContext.createCGImage(scaled, from: CGRect(origin: .zero, size: size)) else {
                        continuation.resume(throwing: BgRemoveError.maskConversionFailed); return
                    }
                    continuation.resume(returning: mask)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            do { try handler.perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: - Step 2: Apply mask via pixel-level alpha writing

    private func applyMask(image: CGImage, mask: CGImage, featherRadius: Float) throws -> CGImage {
        let w = image.width, h = image.height
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        let cs = CGColorSpaceCreateDeviceRGB()

        // Orijinal resmi RGBA buffer'a çiz
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw BgRemoveError.compositeFailed }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Mask'ı ayrı buffer'a çiz
        var maskPixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        guard let maskCtx = CGContext(data: &maskPixels, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw BgRemoveError.compositeFailed }

        // Feather: mask'a gaussian blur uygula
        if featherRadius > 0 {
            let ciMask = CIImage(cgImage: mask)
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = ciMask
            blur.radius = featherRadius
            if let blurred = blur.outputImage,
               let blurredCG = ciContext.createCGImage(blurred, from: ciMask.extent) {
                maskCtx.draw(blurredCG, in: CGRect(x: 0, y: 0, width: w, height: h))
            } else {
                maskCtx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        } else {
            maskCtx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        // Alpha = mask R kanalı (luminance) * orijinal alpha
        for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let maskVal = maskPixels[i]
            pixels[i + 3] = UInt8(Int(maskVal) * Int(pixels[i + 3]) / 255)
        }

        guard let result = ctx.makeImage() else { throw BgRemoveError.compositeFailed }
        return result
    }
}

// MARK: - Errors

enum BgRemoveError: LocalizedError {
    case noMaskFound, maskConversionFailed, compositeFailed
    var errorDescription: String? {
        switch self {
        case .noMaskFound: return "No foreground mask found."
        case .maskConversionFailed: return "Mask conversion failed."
        case .compositeFailed: return "Image compositing failed."
        }
    }
}
