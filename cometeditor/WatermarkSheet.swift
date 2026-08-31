//
//  WatermarkSheet.swift
//  cometeditor
//

import SwiftUI
import UniformTypeIdentifiers

struct WatermarkSheet: View {
    @Binding var parentImage: NSImage?
    @Binding var parentURL: URL?
    @Binding var parentText: String
    @Binding var parentPosition: WatermarkPosition
    @Binding var parentScale: Double
    @Binding var parentOpacity: Double
    @Binding var parentColorOverlay: WatermarkColorOverlay
    @Binding var parentTileMode: Bool
    @Binding var parentRotation: Double
    @Binding var parentEnabled: Bool
    let images: [ImageItem]
    let focusedItemID: UUID?
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var watermarkImage: NSImage? = nil
    @State private var watermarkURL: URL? = nil
    @State private var watermarkText: String = ""
    @State private var watermarkPosition: WatermarkPosition = .bottomRight
    @State private var watermarkScale: Double = 0.15
    @State private var watermarkOpacity: Double = 0.8
    @State private var watermarkColorOverlay: WatermarkColorOverlay = .none
    @State private var watermarkTileMode: Bool = false
    @State private var watermarkRotation: Double = 0
    @State private var previewItemID: UUID?

    private var trimmedText: String {
        WatermarkStamper.trimmedText(watermarkText)
    }

    private var hasMark: Bool {
        watermarkImage != nil || !trimmedText.isEmpty
    }

    private var previewItem: ImageItem? {
        if let id = previewItemID, let match = images.first(where: { $0.id == id }) {
            return match
        }
        return images.first
    }

    private var composedPreview: NSImage? {
        guard let source = previewItem?.image else { return nil }
        return WatermarkStamper.composePreview(
            base: source,
            logo: watermarkImage,
            text: watermarkText,
            position: watermarkPosition,
            scale: watermarkScale,
            opacity: watermarkOpacity,
            colorOverlay: watermarkColorOverlay,
            tileMode: watermarkTileMode,
            rotationDegrees: watermarkRotation
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(languageManager.string("watermark.title"))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .padding(7)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .handCursor()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                previewColumn
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)

                Divider()

                ScrollView {
                    controlsColumn
                        .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                Spacer()
                Button(languageManager.string("watermark.cancel")) {
                    dismiss()
                }
                .controlSize(.regular)
                .keyboardShortcut(.escape, modifiers: [])
                .handCursor()

                Button(languageManager.string("watermark.apply")) {
                    let text = trimmedText
                    parentImage = watermarkImage
                    parentURL = watermarkURL
                    parentText = text
                    parentPosition = watermarkPosition
                    parentScale = watermarkScale
                    parentOpacity = watermarkOpacity
                    parentColorOverlay = watermarkColorOverlay
                    parentTileMode = watermarkTileMode
                    parentRotation = watermarkRotation
                    parentEnabled = watermarkImage != nil || !text.isEmpty
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!hasMark)
                .handCursor()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 720, height: 580)
        .onAppear {
            watermarkImage = parentImage
            watermarkURL = parentURL
            watermarkText = parentText
            watermarkPosition = parentPosition
            watermarkScale = parentScale
            watermarkOpacity = parentOpacity
            watermarkColorOverlay = parentColorOverlay
            watermarkTileMode = parentTileMode
            watermarkRotation = parentRotation
            if let focused = focusedItemID, images.contains(where: { $0.id == focused }) {
                previewItemID = focused
            } else {
                previewItemID = images.first?.id
            }
        }
    }

    // MARK: - Preview

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(languageManager.string("watermark.preview"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)

            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 200)

            if let item = previewItem {
                Text(item.fileName)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if images.count > 1 {
                thumbnailStrip
            }
        }
        .padding(16)
    }

    private var previewPane: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))

            if let preview = composedPreview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else if previewItem != nil {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            } else {
                GeometryReader { geo in
                    VStack(spacing: 10) {
                        placeholderMark(in: geo.size)
                        if !hasMark {
                            Text(languageManager.string("watermark.preview.empty"))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func placeholderMark(in size: CGSize) -> some View {
        if hasMark {
            WatermarkOverlayView(
                watermarkImage: watermarkImage,
                watermarkText: watermarkText,
                containerSize: size,
                scale: watermarkScale,
                opacity: watermarkOpacity,
                position: watermarkPosition,
                colorOverlay: watermarkColorOverlay,
                tileMode: watermarkTileMode,
                rotationDegrees: watermarkRotation
            )
            .allowsHitTesting(false)
            .frame(width: size.width, height: size.height)
        } else {
            Image(systemName: "seal")
                .font(.system(size: 28))
                .foregroundStyle(Color.secondary.opacity(0.35))
        }
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(images) { item in
                    Button {
                        previewItemID = item.id
                    } label: {
                        Group {
                            if let nsImage = item.image {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.secondary.opacity(0.12)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    previewItemID == item.id ? Color.accentColor : Color.primary.opacity(0.1),
                                    lineWidth: previewItemID == item.id ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                logoPicker
                    .frame(maxWidth: .infinity, alignment: .leading)
                positionGridBlock
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(languageManager.string("watermark.text"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .textCase(.uppercase)

                TextField(languageManager.string("watermark.text.placeholder"), text: $watermarkText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                sliderBlock(
                    titleKey: "watermark.scale",
                    value: $watermarkScale,
                    range: 0.03...0.5,
                    step: 0.01,
                    label: "\(Int(watermarkScale * 100))%"
                )
                sliderBlock(
                    titleKey: "watermark.opacity",
                    value: $watermarkOpacity,
                    range: 0.05...1.0,
                    step: 0.05,
                    label: "\(Int(watermarkOpacity * 100))%"
                )
            }

            sliderBlock(
                titleKey: "watermark.rotation",
                value: $watermarkRotation,
                range: -180...180,
                step: 1,
                label: "\(Int(watermarkRotation))°"
            )

            Divider()

            HStack(alignment: .top, spacing: 16) {
                colorOverlayBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                tileModeBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var logoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.string("watermark.logo"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                if let img = watermarkImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.secondary.opacity(0.5))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Button(languageManager.string("watermark.selectLogo")) {
                        pickWatermarkFile()
                    }
                    .controlSize(.small)
                    .handCursor()

                    if let url = watermarkURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if watermarkImage != nil {
                        Button(languageManager.string("watermark.removeLogo")) {
                            watermarkImage = nil
                            watermarkURL = nil
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red.opacity(0.8))
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                }
            }
        }
    }

    private var positionGridBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.string("watermark.position"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)

            positionGrid
        }
    }

    private var positionGrid: some View {
        let positions: [[WatermarkPosition]] = [
            [.topLeft, .topCenter, .topRight],
            [.centerLeft, .center, .centerRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ]
        return VStack(spacing: 4) {
            ForEach(Array(positions.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { pos in
                        Button {
                            watermarkPosition = pos
                        } label: {
                            Image(systemName: pos.icon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(watermarkPosition == pos ? Color.white : Color.primary.opacity(0.6))
                                .frame(width: 36, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(watermarkPosition == pos ? Color.accentColor : Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                }
            }
        }
    }

    private func sliderBlock(
        titleKey: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(languageManager.string(titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                Slider(value: value, in: range, step: step)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var colorOverlayBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.string("watermark.colorOverlay"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)

            HStack(spacing: 4) {
                ForEach(WatermarkColorOverlay.allCases) { overlay in
                    Button {
                        watermarkColorOverlay = overlay
                    } label: {
                        if overlay == .none {
                            Image(systemName: "circle.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 26, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(watermarkColorOverlay == overlay ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(watermarkColorOverlay == overlay ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                        } else {
                            Circle()
                                .fill(overlay.previewCircleColor)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                                .frame(width: 26, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(watermarkColorOverlay == overlay ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(watermarkColorOverlay == overlay ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }
            }
        }
    }

    private var tileModeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.string("watermark.tileMode"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)

            Button {
                watermarkTileMode.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: watermarkTileMode ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(watermarkTileMode ? Color.accentColor : Color.secondary.opacity(0.5))
                    Text(languageManager.string("watermark.tileMode.desc"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
        }
    }

    private func pickWatermarkFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .svg]
        if panel.runModal() == .OK, let url = panel.url {
            watermarkURL = url
            watermarkImage = NSImage(contentsOf: url)
        }
    }
}

// MARK: - Overlay (placeholder / empty-list preview)

struct WatermarkOverlayView: View {
    var watermarkImage: NSImage?
    var watermarkText: String = ""
    let containerSize: CGSize
    let scale: Double
    let opacity: Double
    let position: WatermarkPosition
    let colorOverlay: WatermarkColorOverlay
    let tileMode: Bool
    var rotationDegrees: Double = 0

    var body: some View {
        let shortSide = min(containerSize.width, containerSize.height)
        let markW = shortSide * scale
        let tintColor = colorOverlay.swiftUIColor ?? (watermarkImage == nil ? Color.white : nil)

        if tileMode {
            let spacingX = markW * 1.6
            let spacingY = markW * 1.6
            Canvas { ctx, size in
                guard let resolved = ctx.resolveSymbol(id: "wm") else { return }
                var row = 0
                var y = -markW * 0.5
                while y < size.height + markW {
                    let xOff: CGFloat = (row % 2 == 0) ? 0 : spacingX * 0.5
                    var x = -markW * 0.5 + xOff
                    while x < size.width + markW {
                        ctx.draw(resolved, at: CGPoint(x: x + markW / 2, y: y + markW / 2))
                        x += spacingX
                    }
                    y += spacingY
                    row += 1
                }
            } symbols: {
                markContent(width: markW, tintColor: tintColor)
                    .tag("wm")
            }
            .allowsHitTesting(false)
        } else {
            let alignH: HorizontalAlignment = {
                switch position {
                case .topLeft, .centerLeft, .bottomLeft: return .leading
                case .topCenter, .center, .bottomCenter: return .center
                case .topRight, .centerRight, .bottomRight: return .trailing
                }
            }()
            let alignV: VerticalAlignment = {
                switch position {
                case .topLeft, .topCenter, .topRight: return .top
                case .centerLeft, .center, .centerRight: return .center
                case .bottomLeft, .bottomCenter, .bottomRight: return .bottom
                }
            }()

            VStack {
                if alignV == .center || alignV == .bottom { Spacer(minLength: 0) }
                HStack {
                    if alignH == .center || alignH == .trailing { Spacer(minLength: 0) }
                    markContent(width: markW, tintColor: tintColor)
                    if alignH == .center || alignH == .leading { Spacer(minLength: 0) }
                }
                if alignV == .center || alignV == .top { Spacer(minLength: 0) }
            }
            .padding(containerSize.width * 0.03)
        }
    }

    @ViewBuilder
    private func markContent(width: CGFloat, tintColor: Color?) -> some View {
        VStack(spacing: 4) {
            if let watermarkImage {
                if let tint = colorOverlay.swiftUIColor {
                    Image(nsImage: watermarkImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width)
                        .colorMultiply(tint)
                } else {
                    Image(nsImage: watermarkImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width)
                }
            }
            if !WatermarkStamper.trimmedText(watermarkText).isEmpty {
                Text(WatermarkStamper.trimmedText(watermarkText))
                    .font(.system(size: max(10, width * 0.22), weight: .semibold))
                    .foregroundStyle(tintColor ?? .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: width * 1.15)
            }
        }
        .opacity(opacity)
        .rotationEffect(.degrees(rotationDegrees))
    }
}
