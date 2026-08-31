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

enum QRContentType: String, CaseIterable, Identifiable {
    case website  = "website"
    case wifi     = "wifi"
    case vcard    = "vcard"
    case email    = "email"
    case phone    = "phone"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .website: return "globe"
        case .wifi:    return "wifi"
        case .vcard:   return "person.crop.rectangle"
        case .email:   return "envelope"
        case .phone:   return "phone"
        }
    }

    var localizationKey: String { "qr.type.\(rawValue)" }
}

enum WiFiEncryption: String, CaseIterable, Identifiable {
    case wpa  = "WPA"
    case wep  = "WEP"
    case none = "nopass"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .wpa:  return "qr.wifi.enc.wpa"
        case .wep:  return "qr.wifi.enc.wep"
        case .none: return "qr.wifi.noEncryption"
        }
    }
}

struct QRCodeView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    // MARK: - QR Type
    @State private var selectedType: QRContentType = .website

    // MARK: - Website
    @State private var qrText: String = "https://cometeditor.com"

    // MARK: - Wi-Fi
    @State private var wifiSSID: String = ""
    @State private var wifiPassword: String = ""
    @State private var wifiEncryption: WiFiEncryption = .wpa
    @State private var wifiHidden: Bool = false

    // MARK: - vCard
    @State private var vcardFirstName: String = ""
    @State private var vcardLastName: String = ""
    @State private var vcardPhone: String = ""
    @State private var vcardEmail: String = ""
    @State private var vcardCompany: String = ""
    @State private var vcardTitle: String = ""
    @State private var vcardAddress: String = ""
    @State private var vcardWebsite: String = ""

    // MARK: - Email
    @State private var emailAddress: String = ""
    @State private var emailSubject: String = ""
    @State private var emailBody: String = ""

    // MARK: - Phone
    @State private var phoneNumber: String = ""

    // MARK: - Appearance
    @State private var fgColor: Color = .black
    @State private var bgColor: Color = .white
    @State private var cornerRadius: Double = 16.0
    @State private var showBackground: Bool = true
    @State private var selectedFormat: QRExportFormat = .png

    @State private var selectedSize: CGFloat = 1024
    @State private var customSize: String = "1024"
    private let sizeOptions: [CGFloat] = [256, 512, 1024, 2048]
    private let cornerRadiusRefSize: Double = 280.0

    @State private var cachedQRImage: NSImage? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var windowState: WindowStateObserver

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        HStack(spacing: 0) {
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspectorPanel
                .frame(width: 260)
        }
        .detailIgnoresSafeArea(columnVisibility: columnVisibility, isFullScreen: windowState.isFullScreen)
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
        .onChange(of: selectedType) { _ in updateQRImage() }
        .onChange(of: wifiSSID) { _ in updateQRImage() }
        .onChange(of: wifiPassword) { _ in updateQRImage() }
        .onChange(of: wifiEncryption) { _ in updateQRImage() }
        .onChange(of: wifiHidden) { _ in updateQRImage() }
        .onChange(of: vcardFirstName) { _ in updateQRImage() }
        .onChange(of: vcardLastName) { _ in updateQRImage() }
        .onChange(of: vcardPhone) { _ in updateQRImage() }
        .onChange(of: vcardEmail) { _ in updateQRImage() }
        .onChange(of: vcardCompany) { _ in updateQRImage() }
        .onChange(of: vcardTitle) { _ in updateQRImage() }
        .onChange(of: vcardAddress) { _ in updateQRImage() }
        .onChange(of: vcardWebsite) { _ in updateQRImage() }
        .onChange(of: emailAddress) { _ in updateQRImage() }
        .onChange(of: emailSubject) { _ in updateQRImage() }
        .onChange(of: emailBody) { _ in updateQRImage() }
        .onChange(of: phoneNumber) { _ in updateQRImage() }
    }

    private var qrPayload: String {
        switch selectedType {
        case .website:
            return qrText

        case .wifi:
            let t = wifiEncryption.rawValue
            let escaped = wifiSSID
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ":", with: "\\:")
            let pEscaped = wifiPassword
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ":", with: "\\:")
            let hidden = wifiHidden ? "H:true;" : ""
            return "WIFI:T:\(t);S:\(escaped);P:\(pEscaped);\(hidden);"

        case .vcard:
            var lines = ["BEGIN:VCARD", "VERSION:3.0"]
            let fn = "\(vcardFirstName) \(vcardLastName)".trimmingCharacters(in: .whitespaces)
            if !fn.isEmpty {
                lines.append("N:\(vcardLastName);\(vcardFirstName);;;")
                lines.append("FN:\(fn)")
            }
            if !vcardCompany.isEmpty { lines.append("ORG:\(vcardCompany)") }
            if !vcardTitle.isEmpty   { lines.append("TITLE:\(vcardTitle)") }
            if !vcardPhone.isEmpty   { lines.append("TEL:\(vcardPhone)") }
            if !vcardEmail.isEmpty   { lines.append("EMAIL:\(vcardEmail)") }
            if !vcardAddress.isEmpty { lines.append("ADR:;;\(vcardAddress);;;;") }
            if !vcardWebsite.isEmpty { lines.append("URL:\(vcardWebsite)") }
            lines.append("END:VCARD")
            return lines.joined(separator: "\n")

        case .email:
            var mailto = "mailto:\(emailAddress)"
            var params: [String] = []
            if !emailSubject.isEmpty {
                params.append("subject=\(emailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? emailSubject)")
            }
            if !emailBody.isEmpty {
                params.append("body=\(emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? emailBody)")
            }
            if !params.isEmpty { mailto += "?" + params.joined(separator: "&") }
            return mailto

        case .phone:
            return "tel:\(phoneNumber)"
        }
    }

    private func updateQRImage() {
        DispatchQueue.main.async {
            self.cachedQRImage = self.generateQRCode(from: self.qrPayload)
        }
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
                inputFieldsForType
                    .animation(.easeInOut(duration: 0.2), value: selectedType)

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

                Button(action: downloadQRCode) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(languageManager.string("qr.download"))
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
            .frame(maxWidth: 440)
            .padding(40)

            Spacer()
        }
    }

    // MARK: - Dynamic Input Fields
    @ViewBuilder
    private var inputFieldsForType: some View {
        switch selectedType {
        case .website:
            qrInputField("qr.input.placeholder", text: $qrText)

        case .wifi:
            VStack(spacing: 10) {
                qrInputField("qr.wifi.ssid", text: $wifiSSID, icon: "wifi")
                qrInputField("qr.wifi.password", text: $wifiPassword, icon: "lock", isSecure: true)
                HStack(spacing: 8) {
                    ForEach(WiFiEncryption.allCases) { enc in
                        Button {
                            wifiEncryption = enc
                        } label: {
                            Text(languageManager.string(enc.localizationKey))
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(wifiEncryption == enc ? Color.accentColor : Color.primary.opacity(0.05))
                                .foregroundStyle(wifiEncryption == enc ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text(languageManager.string("qr.wifi.hidden"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $wifiHidden)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .padding(.horizontal, 4)
            }

        case .vcard:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    qrInputField("qr.vcard.firstName", text: $vcardFirstName, icon: "person")
                    qrInputField("qr.vcard.lastName", text: $vcardLastName, icon: "person")
                }
                qrInputField("qr.vcard.phone", text: $vcardPhone, icon: "phone")
                qrInputField("qr.vcard.email", text: $vcardEmail, icon: "envelope")
                qrInputField("qr.vcard.company", text: $vcardCompany, icon: "building.2")
                qrInputField("qr.vcard.jobTitle", text: $vcardTitle, icon: "briefcase")
                qrInputField("qr.vcard.address", text: $vcardAddress, icon: "mappin.and.ellipse")
                qrInputField("qr.vcard.website", text: $vcardWebsite, icon: "globe")
            }

        case .email:
            VStack(spacing: 10) {
                qrInputField("qr.email.address", text: $emailAddress, icon: "envelope")
                qrInputField("qr.email.subject", text: $emailSubject, icon: "text.alignleft")
                qrInputField("qr.email.body", text: $emailBody, icon: "doc.text", lineLimit: 3)
            }

        case .phone:
            qrInputField("qr.phone.number", text: $phoneNumber, icon: "phone")
        }
    }

    private func qrInputField(
        _ placeholderKey: String,
        text: Binding<String>,
        icon: String? = nil,
        isSecure: Bool = false,
        lineLimit: Int = 1
    ) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            if isSecure {
                SecureField(languageManager.string(placeholderKey), text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            } else if lineLimit > 1 {
                TextField(languageManager.string(placeholderKey), text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(lineLimit...lineLimit + 2)
            } else {
                TextField(languageManager.string(placeholderKey), text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Inspector Panel
    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inspectorSection("qr.settings.type") {
                    VStack(spacing: 6) {
                        ForEach(QRContentType.allCases) { type in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedType = type
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: 18)
                                    Text(languageManager.string(type.localizationKey))
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    if selectedType == type {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(selectedType == type ? Color.accentColor : Color.primary.opacity(0.04))
                                .foregroundStyle(selectedType == type ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                inspectorSection("qr.settings.resolution") {
                    VStack(alignment: .leading, spacing: 12) {
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.string("qr.settings.customSize"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                            TextField(languageManager.string("qr.settings.sizeUnit"), text: $customSize)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .onChange(of: customSize) { newValue in
                                    if !sizeOptions.contains(where: { "\(Int($0))" == newValue }) {
                                        selectedSize = 0
                                    }
                                }
                        }
                    }
                }

                inspectorSection("qr.settings.colors") {
                    VStack(spacing: 12) {
                        HStack {
                            Text(languageManager.string("qr.settings.showBg"))
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
                                Text(languageManager.string("qr.settings.cornerRadius"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                Slider(value: $cornerRadius, in: 0...60)
                                    .controlSize(.small)
                            }

                            Divider()
                                .opacity(0.5)

                            HStack {
                                Text(languageManager.string("qr.settings.fgColor"))
                                    .font(.system(size: 13))
                                Spacer()
                                ColorPicker("", selection: $fgColor)
                                    .labelsHidden()
                            }

                            Divider()
                                .opacity(0.5)

                            HStack {
                                Text(languageManager.string("qr.settings.bgColor"))
                                    .font(.system(size: 13))
                                Spacer()
                                ColorPicker("", selection: $bgColor)
                                    .labelsHidden()
                            }
                        } else {
                            Divider()
                                .opacity(0.5)

                            HStack {
                                Text(languageManager.string("qr.settings.fgColor"))
                                    .font(.system(size: 13))
                                Spacer()
                                ColorPicker("", selection: $fgColor)
                                    .labelsHidden()
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
        .inspectorPanelChrome()
    }

    // MARK: - QR Code Generation
    func generateQRCode(from string: String) -> NSImage? {
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            let parsedCustom = Int(customSize)
            let currentSize: CGFloat = {
                if let custom = parsedCustom, custom > 0 { return CGFloat(custom) }
                if sizeOptions.contains(selectedSize) { return selectedSize }
                return 512
            }()

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
                    guard let cgBitmap = CGContext(
                        data: nil,
                        width: Int(currentSize), height: Int(currentSize),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else { return nil }

                    let rx = CGFloat(cornerRadius * (Double(currentSize) / cornerRadiusRefSize))
                    let bgCGColor = NSColor(bgColor).cgColor
                    let fullRect = CGRect(x: 0, y: 0, width: currentSize, height: currentSize)
                    let roundedPath = CGPath(roundedRect: fullRect, cornerWidth: rx, cornerHeight: rx, transform: nil)
                    cgBitmap.addPath(roundedPath)
                    cgBitmap.setFillColor(bgCGColor)
                    cgBitmap.fillPath()

                    if let qrCGImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                        let paddingRatio: CGFloat = 0.05
                        let padding = currentSize * paddingRatio
                        let qrSize = currentSize - (padding * 2)
                        cgBitmap.draw(qrCGImage, in: CGRect(x: padding, y: padding, width: qrSize, height: qrSize))
                    }

                    if let finalCG = cgBitmap.makeImage() {
                        return NSImage(cgImage: finalCG, size: NSSize(width: currentSize, height: currentSize))
                    }
                    return nil
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
            let rx = String(format: "%.2f", cornerRadius * Double(total) / cornerRadiusRefSize)
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
        savePanel.directoryURL = appState.targetFolder
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        switch selectedFormat {
        case .svg:
            if let svgData = generateSVG(from: qrPayload) {
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
