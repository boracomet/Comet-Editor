//
//  WatermarkTypes.swift
//  cometeditor
//

import AppKit
import CoreGraphics
import SwiftUI

enum WatermarkColorOverlay: String, CaseIterable, Identifiable {
    case none, black, darkGray, gray, lightGray, white

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .none:      return "watermark.color.none"
        case .black:     return "watermark.color.black"
        case .darkGray:  return "watermark.color.darkGray"
        case .gray:      return "watermark.color.gray"
        case .lightGray: return "watermark.color.lightGray"
        case .white:     return "watermark.color.white"
        }
    }

    var cgColor: CGColor? {
        switch self {
        case .none:      return nil
        case .black:     return CGColor(gray: 0, alpha: 1)
        case .darkGray:  return CGColor(gray: 0.33, alpha: 1)
        case .gray:      return CGColor(gray: 0.5, alpha: 1)
        case .lightGray: return CGColor(gray: 0.75, alpha: 1)
        case .white:     return CGColor(gray: 1, alpha: 1)
        }
    }

    var swiftUIColor: Color? {
        switch self {
        case .none:      return nil
        case .black:     return .black
        case .darkGray:  return Color(white: 0.33)
        case .gray:      return .gray
        case .lightGray: return Color(white: 0.75)
        case .white:     return .white
        }
    }

    var previewCircleColor: Color {
        switch self {
        case .none:      return .clear
        case .black:     return .black
        case .darkGray:  return Color(white: 0.33)
        case .gray:      return .gray
        case .lightGray: return Color(white: 0.75)
        case .white:     return .white
        }
    }
}

enum WatermarkPosition: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .topLeft:      return "watermark.pos.topLeft"
        case .topCenter:    return "watermark.pos.topCenter"
        case .topRight:     return "watermark.pos.topRight"
        case .centerLeft:   return "watermark.pos.centerLeft"
        case .center:       return "watermark.pos.center"
        case .centerRight:  return "watermark.pos.centerRight"
        case .bottomLeft:   return "watermark.pos.bottomLeft"
        case .bottomCenter: return "watermark.pos.bottomCenter"
        case .bottomRight:  return "watermark.pos.bottomRight"
        }
    }

    var icon: String {
        switch self {
        case .topLeft:      return "arrow.up.left"
        case .topCenter:    return "arrow.up"
        case .topRight:     return "arrow.up.right"
        case .centerLeft:   return "arrow.left"
        case .center:       return "circle.fill"
        case .centerRight:  return "arrow.right"
        case .bottomLeft:   return "arrow.down.left"
        case .bottomCenter: return "arrow.down"
        case .bottomRight:  return "arrow.down.right"
        }
    }

    func origin(imageSize: CGSize, watermarkSize: CGSize, margin: CGFloat = 0.03) -> CGPoint {
        let mx = imageSize.width * margin
        let my = imageSize.height * margin
        let ww = watermarkSize.width
        let wh = watermarkSize.height
        let cx = (imageSize.width - ww) / 2
        let cy = (imageSize.height - wh) / 2
        switch self {
        case .topLeft:      return CGPoint(x: mx, y: imageSize.height - wh - my)
        case .topCenter:    return CGPoint(x: cx, y: imageSize.height - wh - my)
        case .topRight:     return CGPoint(x: imageSize.width - ww - mx, y: imageSize.height - wh - my)
        case .centerLeft:   return CGPoint(x: mx, y: cy)
        case .center:       return CGPoint(x: cx, y: cy)
        case .centerRight:  return CGPoint(x: imageSize.width - ww - mx, y: cy)
        case .bottomLeft:   return CGPoint(x: mx, y: my)
        case .bottomCenter: return CGPoint(x: cx, y: my)
        case .bottomRight:  return CGPoint(x: imageSize.width - ww - mx, y: my)
        }
    }
}

enum WatermarkStamper {

    static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasContent(logo: CGImage?, text: String) -> Bool {
        logo != nil || !trimmedText(text).isEmpty
    }

    static func tintedImage(_ source: CGImage, color: CGColor) -> CGImage? {
        let w = source.width, h = source.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: rect, mask: source)
        ctx.setFillColor(color)
        ctx.fill(rect)
        return ctx.makeImage()
    }

    static func stamp(
        onto base: CGImage,
        logo: CGImage?,
        text: String,
        position: WatermarkPosition,
        scale: Double,
        opacity: Double,
        colorOverlay: WatermarkColorOverlay,
        tileMode: Bool,
        rotationDegrees: Double
    ) -> CGImage? {
        guard let finalWM = makeMark(logo: logo, text: text, colorOverlay: colorOverlay) else {
            return nil
        }

        let imgW = CGFloat(base.width)
        let imgH = CGFloat(base.height)

        guard let ctx = CGContext(
            data: nil, width: Int(imgW), height: Int(imgH),
            bitsPerComponent: 8, bytesPerRow: Int(imgW) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        ctx.draw(base, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

        let shortSide = min(imgW, imgH)
        let wmAspect = CGFloat(finalWM.width) / max(CGFloat(finalWM.height), 1)
        let wmDrawW = shortSide * scale
        let wmDrawH = wmDrawW / max(wmAspect, 0.01)
        let wmSize = CGSize(width: wmDrawW, height: wmDrawH)

        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setAlpha(CGFloat(opacity))

        if tileMode {
            let spacingX = wmDrawW * 1.6
            let spacingY = wmDrawH * 1.6
            var row = 0
            var y = -wmDrawH * 0.5
            while y < imgH + wmDrawH {
                let xOffset: CGFloat = (row % 2 == 0) ? 0 : spacingX * 0.5
                var x = -wmDrawW * 0.5 + xOffset
                while x < imgW + wmDrawW {
                    drawMark(finalWM, in: ctx, rect: CGRect(x: x, y: y, width: wmDrawW, height: wmDrawH), rotationDegrees: rotationDegrees)
                    x += spacingX
                }
                y += spacingY
                row += 1
            }
        } else {
            let origin = position.origin(imageSize: CGSize(width: imgW, height: imgH), watermarkSize: wmSize)
            drawMark(finalWM, in: ctx, rect: CGRect(origin: origin, size: wmSize), rotationDegrees: rotationDegrees)
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()

        return ctx.makeImage()
    }

    static func composePreview(
        base: NSImage,
        logo: NSImage?,
        text: String,
        position: WatermarkPosition,
        scale: Double,
        opacity: Double,
        colorOverlay: WatermarkColorOverlay,
        tileMode: Bool,
        rotationDegrees: Double
    ) -> NSImage? {
        var baseRect = CGRect(origin: .zero, size: base.size)
        guard let baseCG = base.cgImage(forProposedRect: &baseRect, context: nil, hints: nil) else {
            return base
        }

        var logoCG: CGImage?
        if let logo {
            var logoRect = CGRect(origin: .zero, size: logo.size)
            logoCG = logo.cgImage(forProposedRect: &logoRect, context: nil, hints: nil)
        }

        guard hasContent(logo: logoCG, text: text) else { return base }
        guard let stamped = stamp(
            onto: baseCG,
            logo: logoCG,
            text: text,
            position: position,
            scale: scale,
            opacity: opacity,
            colorOverlay: colorOverlay,
            tileMode: tileMode,
            rotationDegrees: rotationDegrees
        ) else {
            return base
        }
        return NSImage(cgImage: stamped, size: NSSize(width: stamped.width, height: stamped.height))
    }

    // MARK: - Mark construction

    static func makeMark(logo: CGImage?, text: String, colorOverlay: WatermarkColorOverlay) -> CGImage? {
        let trimmed = trimmedText(text)
        let tintedLogo: CGImage?
        if let logo {
            if let tint = colorOverlay.cgColor, let tinted = tintedImage(logo, color: tint) {
                tintedLogo = tinted
            } else {
                tintedLogo = logo
            }
        } else {
            tintedLogo = nil
        }

        let textColor = colorOverlay.cgColor ?? CGColor(gray: 1, alpha: 1)
        let textImg = trimmed.isEmpty ? nil : renderText(trimmed, color: textColor)

        if let logoImg = tintedLogo, let textImg {
            let targetW = max(1, Int(CGFloat(logoImg.width) * 0.95))
            let scaledText = scaleImage(textImg, toWidth: targetW) ?? textImg
            return stackVertically(logoImg, scaledText)
        }
        return tintedLogo ?? textImg
    }

    static func renderText(_ text: String, color: CGColor) -> CGImage? {
        let nsFont = NSFont.systemFont(ofSize: 256, weight: .semibold)
        let nsColor = NSColor(cgColor: color) ?? .white
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: nsColor
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attr.size()
        let pad = nsFont.pointSize * 0.12
        let size = NSSize(
            width: max(1, ceil(textSize.width + pad * 2)),
            height: max(1, ceil(textSize.height + pad * 2))
        )
        let image = NSImage(size: size, flipped: true) { _ in
            attr.draw(at: NSPoint(x: pad, y: pad))
            return true
        }
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func scaleImage(_ source: CGImage, toWidth targetW: Int) -> CGImage? {
        let aspect = CGFloat(source.height) / max(CGFloat(source.width), 1)
        let targetH = max(1, Int(CGFloat(targetW) * aspect))
        guard let ctx = CGContext(
            data: nil, width: targetW, height: targetH,
            bitsPerComponent: 8, bytesPerRow: targetW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return ctx.makeImage()
    }

    private static func stackVertically(_ top: CGImage, _ bottom: CGImage) -> CGImage? {
        let gap = max(4, Int(CGFloat(max(top.height, bottom.height)) * 0.06))
        let w = max(top.width, bottom.width)
        let h = top.height + gap + bottom.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        let topX = (w - top.width) / 2
        let botX = (w - bottom.width) / 2
        ctx.draw(bottom, in: CGRect(x: botX, y: 0, width: bottom.width, height: bottom.height))
        ctx.draw(top, in: CGRect(x: topX, y: bottom.height + gap, width: top.width, height: top.height))
        return ctx.makeImage()
    }

    private static func drawMark(_ wm: CGImage, in ctx: CGContext, rect: CGRect, rotationDegrees: Double) {
        guard abs(rotationDegrees) > 0.01 else {
            ctx.draw(wm, in: rect)
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.rotate(by: CGFloat(rotationDegrees * .pi / 180))
        ctx.draw(wm, in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}
