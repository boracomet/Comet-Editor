//
//  HomeView.swift
//  cometeditor
//
//  Ana sayfa: hızlı işlem kartları + özellik rehberi + hazır ayar yükleme.
//

import SwiftUI

struct HomeView: View {
    var onQuickImage: ((HomeQuickImagePreset) -> Void)?
    var onQuickVideo: ((HomeQuickVideoPreset) -> Void)?
    var onQuickPdf: ((HomePDFPreset?) -> Void)?
    var onNavigate: ((MenuItem) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Quick Cards

    private struct QuickCard: Identifiable {
        let id = UUID()
        let icon: String
        let titleKey: LocalizedStringKey
        let subtitleKey: LocalizedStringKey
        let colors: [Color]
        let action: () -> Void
    }

    private var quickCards: [QuickCard] {
        [
            QuickCard(
                icon: "arrow.down.right.and.arrow.up.left",
                titleKey: "home.quick.shrink.title",
                subtitleKey: "home.quick.shrink.subtitle",
                colors: [.blue, .cyan],
                action: { onQuickImage?(.shrinkPng) }
            ),
            QuickCard(
                icon: "photo.on.rectangle.angled",
                titleKey: "home.quick.pngWebp.title",
                subtitleKey: "home.quick.pngWebp.subtitle",
                colors: [.teal, .green],
                action: { onQuickImage?(.pngToWebp) }
            ),
            QuickCard(
                icon: "doc.text.fill",
                titleKey: "home.quick.pdf.title",
                subtitleKey: "home.quick.pdf.subtitle",
                colors: [.orange, .pink],
                action: { onQuickPdf?(nil) }
            )
        ]
    }

    // MARK: - Feature Guide Data

    struct FeatureGuide: Identifiable {
        let menuItem: MenuItem
        var id: String { menuItem.rawValue }
        let icon: String
        let titleKey: LocalizedStringKey
        let descKey: LocalizedStringKey
        let steps: [LocalizedStringKey]
        let tipKey: LocalizedStringKey
        let presets: [FeaturePreset]
    }

    struct FeaturePreset: Identifiable {
        let id = UUID()
        let labelKey: LocalizedStringKey
        let icon: String
        let action: () -> Void
    }

    private var featureGuides: [FeatureGuide] {
        [
            FeatureGuide(
                menuItem: .convertImage,
                icon: "photo.on.rectangle.angled",
                titleKey: "menu.convertImage",
                descKey: "home.guide.convertImage.desc",
                steps: [
                    "home.guide.step.drop",
                    "home.guide.convertImage.step2",
                    "home.guide.convertImage.step3",
                    "home.guide.step.convert"
                ],
                tipKey: "home.guide.convertImage.tip",
                presets: [
                    FeaturePreset(labelKey: "home.quick.shrink.title",   icon: "arrow.down.right.and.arrow.up.left", action: { onQuickImage?(.shrinkPng) }),
                    FeaturePreset(labelKey: "home.quick.pngWebp.title",  icon: "photo.on.rectangle.angled",          action: { onQuickImage?(.pngToWebp) }),
                    FeaturePreset(labelKey: "home.preset.pngAvif.title", icon: "photo.on.rectangle.angled",          action: { onQuickImage?(.pngToAvif) }),
                    FeaturePreset(labelKey: "home.preset.jpgWebp.title", icon: "photo.on.rectangle.angled",          action: { onQuickImage?(.jpgToWebp) })
                ]
            ),
            FeatureGuide(
                menuItem: .upscaleImage,
                icon: "arrow.up.left.and.arrow.down.right",
                titleKey: "menu.upscaleImage",
                descKey: "home.guide.upscale.desc",
                steps: [
                    "home.guide.step.drop",
                    "home.guide.upscale.step2",
                    "home.guide.upscale.step3",
                    "home.guide.upscale.step4"
                ],
                tipKey: "home.guide.upscale.tip",
                presets: [
                    FeaturePreset(labelKey: "upscale.convert", icon: "wand.and.stars", action: { onNavigate?(.upscaleImage) }),
                    FeaturePreset(labelKey: "upscale.upscaleAll", icon: "arrow.up.left.and.arrow.down.right", action: { onNavigate?(.upscaleImage) })
                ]
            ),
            FeatureGuide(
                menuItem: .videoConvert,
                icon: "video.fill",
                titleKey: "menu.videoConvert",
                descKey: "home.guide.video.desc",
                steps: [
                    "home.guide.step.drop",
                    "home.guide.video.step2",
                    "home.guide.video.step3",
                    "home.guide.step.convert"
                ],
                tipKey: "home.guide.video.tip",
                presets: [
                    FeaturePreset(labelKey: "home.preset.videoShrink.title", icon: "arrow.down.right.and.arrow.up.left", action: { onQuickVideo?(.shrinkVideo) }),
                    FeaturePreset(labelKey: "home.preset.mp4ToGif.title",  icon: "photo.on.rectangle.angled", action: { onQuickVideo?(.mp4ToGif) }),
                    FeaturePreset(labelKey: "home.preset.aviToMp4.title",  icon: "video.fill",               action: { onQuickVideo?(.aviToMp4) }),
                    FeaturePreset(labelKey: "home.preset.movToMp4.title",  icon: "video.fill",               action: { onQuickVideo?(.movToMp4) })
                ]
            ),
            FeatureGuide(
                menuItem: .stockImage,
                icon: "photo.stack.fill",
                titleKey: "menu.stockImage",
                descKey: "home.guide.stock.desc",
                steps: [
                    "home.guide.stock.step1",
                    "home.guide.stock.step2",
                    "home.guide.stock.step3"
                ],
                tipKey: "home.guide.stock.tip",
                presets: []
            ),
            FeatureGuide(
                menuItem: .pdfEdit,
                icon: "doc.text.fill",
                titleKey: "menu.pdfEdit",
                descKey: "home.guide.pdf.desc",
                steps: [
                    "home.guide.pdf.step1",
                    "home.guide.pdf.step2",
                    "home.guide.pdf.step3",
                    "home.guide.pdf.step4"
                ],
                tipKey: "home.guide.pdf.tip",
                presets: [
                    FeaturePreset(labelKey: "home.preset.pdf.deletePage",  icon: "trash",               action: { onQuickPdf?(.deletePage) }),
                    FeaturePreset(labelKey: "home.preset.pdf.reorder",     icon: "arrow.up.arrow.down", action: { onQuickPdf?(.reorderPages) }),
                    FeaturePreset(labelKey: "home.preset.pdf.optimize",    icon: "doc.zipper",          action: { onQuickPdf?(.optimize) })
                ]
            ),
            FeatureGuide(
                menuItem: .qrCode,
                icon: "qrcode",
                titleKey: "menu.qrCode",
                descKey: "home.guide.qr.desc",
                steps: [
                    "home.guide.qr.step1",
                    "home.guide.qr.step2",
                    "home.guide.qr.step3"
                ],
                tipKey: "home.guide.qr.tip",
                presets: []
            ),
            FeatureGuide(
                menuItem: .bgRemove,
                icon: "person.and.background.dotted",
                titleKey: "menu.bgRemove",
                descKey: "home.guide.bgRemove.desc",
                steps: [
                    "home.guide.step.drop",
                    "home.guide.bgRemove.step2",
                    "home.guide.bgRemove.step3"
                ],
                tipKey: "home.guide.bgRemove.tip",
                presets: []
            ),
            FeatureGuide(
                menuItem: .ocr,
                icon: "text.viewfinder",
                titleKey: "menu.ocr",
                descKey: "home.guide.ocr.desc",
                steps: [
                    "home.guide.step.drop",
                    "home.guide.ocr.step2",
                    "home.guide.ocr.step3"
                ],
                tipKey: "home.guide.ocr.tip",
                presets: []
            ),
            FeatureGuide(
                menuItem: .fontDownload,
                icon: "character.textbox",
                titleKey: "menu.fontDownload",
                descKey: "home.guide.font.desc",
                steps: [
                    "home.guide.font.step1",
                    "home.guide.font.step2",
                    "home.guide.font.step3"
                ],
                tipKey: "home.guide.font.tip",
                presets: []
            )
        ]
    }

    // Kartlar varsayılan olarak kapalı; kullanıcı başlığa tıklayarak açar.
    @State private var expandedGuides: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {

                // MARK: - Header
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey("home.hero.title"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.primary)

                        Text(LocalizedStringKey("home.hero.subtitle"))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Link(destination: URL(string: "https://cometeditor.com") ?? URL(fileURLWithPath: "/")) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey("home.visitWebsite"))
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }

                Divider()

                // MARK: - Feature Guide Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey("home.guide.title"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.primary)

                    Text(LocalizedStringKey("home.guide.subtitle"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    ForEach(featureGuides) { guide in
                        FeatureGuideCard(
                            guide: guide,
                            isExpanded: expandedGuides.contains(guide.id),
                            colorScheme: colorScheme,
                            onTap: {
                                if expandedGuides.contains(guide.id) {
                                    expandedGuides.remove(guide.id)
                                } else {
                                    expandedGuides.insert(guide.id)
                                }
                            },
                            onNavigate: { onNavigate?(guide.menuItem) }
                        )
                    }
                }

            }
            .padding(32)
        }
    }
}

// MARK: - Feature Guide Card

private struct FeatureGuideCard: View {
    let guide: HomeView.FeatureGuide
    let isExpanded: Bool
    let colorScheme: ColorScheme
    let onTap: () -> Void
    let onNavigate: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onTap) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07))
                            .frame(width: 40, height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
                            )
                        Image(systemName: guide.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(guide.titleKey)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text(guide.descKey)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .handCursor()

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 16) {
                    // Steps
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                                        .frame(width: 20, height: 20)
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.primary)
                                }
                                .padding(.top, 1)

                                Text(step)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // Tip
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                        Text(guide.tipKey)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )

                    // Open button + Presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button(action: onNavigate) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(LocalizedStringKey("home.guide.open"))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary)
                                )
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            }
                            .buttonStyle(.plain)
                            .handCursor()

                            ForEach(guide.presets) { preset in
                                PresetChip(preset: preset)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(hovered ? 0.07 : 0.04)
                        : Color.black.opacity(hovered ? 0.04 : 0.02)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.09)
                        : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Hızlı işlem kartı

private struct QuickActionTile: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let gradient: [Color]
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradient.map { $0.opacity(0.35) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: gradient.map { $0.opacity(0.45) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(hovered ? 0.09 : 0.05)
                            : Color.black.opacity(hovered ? 0.05 : 0.025)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.1)
                            : Color.black.opacity(0.07),
                        lineWidth: 1
                    )
            )
            .scaleEffect(hovered ? 1.02 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .handCursor()
    }
}

// MARK: - Preset Chip (hoverable)

private struct PresetChip: View {
    let preset: HomeView.FeaturePreset
    @State private var isHovered = false

    var body: some View {
        Button(action: preset.action) {
            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(preset.labelKey)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.10), lineWidth: 1)
            )
            .foregroundStyle(Color.primary)
            .scaleEffect(isHovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

#Preview {
    HomeView(
        onQuickImage: { _ in },
        onQuickVideo: { _ in },
        onQuickPdf: { _ in },
        onNavigate: { _ in }
    )
    .environmentObject(LanguageManager.shared)
}
