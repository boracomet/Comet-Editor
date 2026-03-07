//
//  QRCodeView.swift
//  cometeditor
//
//  Created by Antigravity on 6.03.2026.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import AppKit

enum QRExportFormat: String, CaseIterable, Identifiable {
    case svg = "SVG"
    case png = "PNG"
    case jpg = "JPG"
    case webp = "WEBP"
    case avif = "AVIF"

    var id: String { rawValue }
}

struct QRCodeView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var qrText: String = "https://cometeditor.com"
    @State private var fgColor: Color = .black
    @State private var bgColor: Color = .white
    @State private var cornerRadius: Double = 16.0
    @State private var showBackground: Bool = true
    @State private var selectedFormat: QRExportFormat = .png

    // Resolution Settings
    @State private var selectedSize: CGFloat = 1024
    @State private var customSize: String = "1024"
    private let sizeOptions: [CGFloat] = [256, 512, 1024, 2048]

    // Cached QR image — updated via onChange instead of recomputing on every render
    @State private var cachedQRImage: NSImage? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: GlobalAppState

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Main Area
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // MARK: - Right Inspector Panel
            inspectorPanel
                .frame(width: 260)
        }
        .ignoresSafeArea(edges: columnVisibility == .detailOnly ? [] : .top)
        .onAppear {
            updateQRImage()
            centerColorPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if notification.object is NSColorPanel {
                centerColorPanel()
            }
        }
        .onChange(of: qrText) { _ in updateQRImage() }
        .onChange(of: fgColor) { _ in updateQRImage() }
        .onChange(of: bgColor) { _ in updateQRImage() }
        .onChange(of: showBackground) { _ in updateQRImage() }
        .onChange(of: cornerRadius) { _ in updateQRImage() }
        .onChange(of: customSize) { _ in updateQRImage() }
        .onChange(of: selectedSize) { _ in updateQRImage() }
    }

    private func updateQRImage() {
        cachedQRImage = generateQRCode(from: qrText)
    }

    private func centerColorPanel() {
        if let window = NSApp.mainWindow, NSColorPanel.shared.isVisible {
            let windowFrame = window.frame
            let panelFrame = NSColorPanel.shared.frame
            let x = windowFrame.origin.x + (windowFrame.width - panelFrame.width) / 2
            let y = windowFrame.origin.y + (windowFrame.height - panelFrame.height) / 2
            NSColorPanel.shared.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - Main Content Area
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Input Field
                TextField("qr.input.placeholder", text: $qrText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                // QR Code — same width as field (fills container)
                if let qrImage = cachedQRImage {
                    ZStack {
                        if showBackground {
                            RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                                .fill(bgColor)
                                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        }

                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(showBackground ? 16 : 0)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .transition(.scale.combined(with: .opacity))
                }

                // Format buttons — full width, equal split
                HStack(spacing: 8) {
                    ForEach(QRExportFormat.allCases) { format in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFormat = format
                            }
                        } label: {
                            Text(format.rawValue)
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(selectedFormat == format ? Color.accentColor : Color.primary.opacity(0.05))
                                .foregroundStyle(selectedFormat == format ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                }

                // Download button — full width
                Button(action: downloadQRCode) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("qr.download")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .handCursor()
            }
            .frame(maxWidth: 400)
            .padding(40)

            Spacer()
        }
    }

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("convert.settings.title")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()

                // Resolution Section
                inspectorSection("qr.settings.resolution") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Preset Sizes
                        HStack(spacing: 8) {
                            ForEach(sizeOptions, id: \.self) { size in
                                Button {
                                    selectedSize = size
                                    customSize = "\(Int(size))"
                                } label: {
                                    Text(String(format: "%dpx", Int(size)))
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(selectedSize == size ? Color.accentColor : Color.primary.opacity(0.05))
                                        .foregroundStyle(selectedSize == size ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Custom Size
                        VStack(alignment: .leading, spacing: 4) {
                            Text("qr.settings.customSize")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                            TextField("px", text: $customSize)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .onChange(of: customSize) { _ in
                                    selectedSize = 0 // Deselect presets
                                }
                        }
                    }
                }

                Divider()

                inspectorSection("qr.settings.colors") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("qr.settings.showBg")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $showBackground)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        if showBackground {
                            Divider()
                                .opacity(0.5)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("qr.settings.cornerRadius")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                Slider(value: $cornerRadius, in: 0...60)
                                    .controlSize(.small)
                            }

                            Divider()
                                .opacity(0.5)

                            HStack {
                                Text("qr.settings.fgColor")
                                    .font(.system(size: 13))
                                Spacer()
                                ColorPicker("", selection: $fgColor)
                                    .labelsHidden()
                            }

                            Divider()
                                .opacity(0.5)

                            HStack {
                                Text("qr.settings.bgColor")
                                    .font(.system(size: 13))
                                Spacer()
                                ColorPicker("", selection: $bgColor)
                                    .labelsHidden()
                            }
                        } else {
                            Divider()
                                .opacity(0.5)

                            HStack {
                                Text("qr.settings.fgColor")
                                    .font(.system(size: 13))
                                Spacer()
                                ColorPicker("", selection: $fgColor)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                Divider()
            }
        }
    }

    // MARK: - Inspector Section (QR-specific styling)
    private func inspectorSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - QR Code Generation
    func generateQRCode(from string: String) -> NSImage? {
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            let currentSize = CGFloat(Int(customSize) ?? Int(selectedSize))

            // Apply foreground color; use clear background to avoid color mismatch
            let colorFilter = CIFilter.falseColor()
            colorFilter.inputImage = outputImage
            colorFilter.color0 = CIColor(color: NSColor(fgColor)) ?? .black
            colorFilter.color1 = .clear

            if let coloredImage = colorFilter.outputImage {
                let scale = currentSize / outputImage.extent.width
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                let scaledImage = coloredImage.transformed(by: transform)

                if showBackground {
                    let backgroundNSColor = NSColor(bgColor)
                    let qrFinalImage = NSImage(size: NSSize(width: currentSize, height: currentSize))
                    qrFinalImage.lockFocus()

                    let rx = CGFloat(cornerRadius * (Double(currentSize) / 280.0))
                    let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: currentSize, height: currentSize),
                                          xRadius: rx, yRadius: rx)
                    backgroundNSColor.setFill()
                    path.fill()

                    if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                        let paddingRatio: CGFloat = 0.05
                        let padding = currentSize * paddingRatio
                        let qrSize = currentSize - (padding * 2)
                        let qrRect = NSRect(x: padding, y: padding, width: qrSize, height: qrSize)
                        NSImage(cgImage: cgImage, size: NSSize(width: currentSize, height: currentSize)).draw(in: qrRect)
                    }

                    qrFinalImage.unlockFocus()
                    return qrFinalImage
                } else {
                    if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                        return NSImage(cgImage: cgImage, size: NSSize(width: currentSize, height: currentSize))
                    }
                }
            }
        }

        return nil
    }

    // MARK: - SVG Generation
    private func generateSVG(from string: String) -> Data? {
        filter.message = Data(string.utf8)
        guard let rawOutput = filter.outputImage else { return nil }

        let modules = Int(rawOutput.extent.width)
        guard modules > 0 else { return nil }

        // Render raw QR to a grayscale bitmap to read module data
        var pixelData = [UInt8](repeating: 255, count: modules * modules)
        guard let cgImage = context.createCGImage(rawOutput, from: rawOutput.extent),
              let grayCtx = CGContext(
                data: &pixelData,
                width: modules,
                height: modules,
                bitsPerComponent: 8,
                bytesPerRow: modules,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }

        grayCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: modules, height: modules))

        let fgHex = NSColor(fgColor).toSVGHex()
        let quietZone = 4
        let total = modules + quietZone * 2

        var svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \#(total) \#(total)" shape-rendering="crispEdges">"#

        if showBackground {
            let bgHex = NSColor(bgColor).toSVGHex()
            let rx = String(format: "%.2f", cornerRadius * Double(total) / 280.0)
            svg += #"\n<rect width="\#(total)" height="\#(total)" fill="\#(bgHex)" rx="\#(rx)"/>"#
        }

        for row in 0..<modules {
            for col in 0..<modules {
                if pixelData[row * modules + col] < 128 {
                    svg += #"\n<rect x="\#(col + quietZone)" y="\#(row + quietZone)" width="1" height="1" fill="\#(fgHex)"/>"#
                }
            }
        }

        svg += "\n</svg>"
        return svg.data(using: .utf8)
    }

    // MARK: - Download
    func downloadQRCode() {
        let savePanel = NSSavePanel()
        let ext = selectedFormat.rawValue.lowercased()
        savePanel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .png]
        savePanel.nameFieldStringValue = "qr_code_\(Int(Date().timeIntervalSince1970))"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        switch selectedFormat {
        case .svg:
            if let svgData = generateSVG(from: qrText) {
                try? svgData.write(to: url)
            }

        case .webp, .avif:
            guard let qrImage = cachedQRImage,
                  let cgImage = qrImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let codecFormat: CodecFormat = selectedFormat == .webp ? .webp : .avif
            Task {
                try? await CometImageCodec.shared.convert(
                    cgImage: cgImage,
                    outputURL: url,
                    format: codecFormat,
                    quality: CodecQuality(value: 90)
                )
            }

        case .png:
            guard let qrImage = cachedQRImage,
                  let tiffData = qrImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let data = bitmapImage.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: url)

        case .jpg:
            guard let qrImage = cachedQRImage,
                  let tiffData = qrImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let data = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
            try? data.write(to: url)
        }
    }
}
