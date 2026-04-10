//
//  PDFQualityPickerSheet.swift
//  cometeditor
//

import SwiftUI

struct PDFQualityPickerSheet: View {
    let pdf: PDFItem
    @Binding var selectedQuality: PDFCompressionQuality
    let onConfirm: (PDFCompressionQuality) -> Void
    let onCancel: () -> Void

    // Tahminler arka planda bir kez hesaplanır, hazır string olarak saklanır
    @State private var estimates: [PDFCompressionQuality: (size: String, saving: String)] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 28)
                Text(LocalizedStringKey("pdf.quality.modal.title"))
                    .font(.system(size: 17, weight: .bold))
                Text(LocalizedStringKey("pdf.quality.modal.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 24)

            // Kalite seçenekleri
            VStack(spacing: 10) {
                ForEach(PDFCompressionQuality.allCases) { quality in
                    QualityOptionRow(
                        quality: quality,
                        isSelected: selectedQuality == quality,
                        estimatedSize: estimates[quality]?.size ?? "—",
                        savingPercent: estimates[quality]?.saving ?? ""
                    ) {
                        selectedQuality = quality
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 20)

            // Butonlar
            HStack(spacing: 12) {
                Button(LocalizedStringKey("pdf.quality.modal.cancel")) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button {
                    onConfirm(selectedQuality)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(LocalizedStringKey("pdf.quality.modal.confirm"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            // Arka planda — main thread'i bloke etmez
            await computeEstimates()
        }
    }

    private func computeEstimates() async {
        let url = pdf.url
        let originalSize = pdf.fileSizeBytes

        // Dosya okuma + hesaplama background'da
        let result: [PDFCompressionQuality: (String, String)] = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else {
                // Dosya okunamazsa orijinal boyuttan basit oran
                return PDFCompressionQuality.allCases.reduce(into: [:]) { dict, q in
                    let ratio: Double = switch q {
                    case .low: 0.20; case .medium: 0.35; case .high: 0.55
                    }
                    let est = Int64(Double(originalSize) * ratio)
                    let sizeStr = ByteCountFormatter.string(fromByteCount: est, countStyle: .file)
                    let pct = originalSize > 0 ? Int((1.0 - Double(est) / Double(originalSize)) * 100) : 0
                    dict[q] = (sizeStr, pct > 0 ? "-\(pct)%" : "")
                }
            }

            // Her kalite için tek seferde parse et
            return PDFCompressionQuality.allCases.reduce(into: [:]) { dict, q in
                let est = PDFSizeEstimator.estimate(data: data, quality: q)
                let sizeStr: String
                let savingStr: String
                if est > 0 {
                    sizeStr = ByteCountFormatter.string(fromByteCount: est, countStyle: .file)
                    let pct = originalSize > 0 ? Int((1.0 - Double(est) / Double(originalSize)) * 100) : 0
                    savingStr = pct > 0 ? "-\(pct)%" : ""
                } else {
                    sizeStr = "—"
                    savingStr = ""
                }
                dict[q] = (sizeStr, savingStr)
            }
        }.value

        estimates = result
    }
}

// MARK: - Kalite seçenek satırı

private struct QualityOptionRow: View {
    let quality: PDFCompressionQuality
    let isSelected: Bool
    let estimatedSize: String
    let savingPercent: String
    let onTap: () -> Void

    private var titleKey: LocalizedStringKey {
        switch quality {
        case .low:    return "pdf.quality.low.title"
        case .medium: return "pdf.quality.medium.title"
        case .high:   return "pdf.quality.high.title"
        }
    }

    private var descKey: LocalizedStringKey {
        switch quality {
        case .low:    return "pdf.quality.low.desc"
        case .medium: return "pdf.quality.medium.desc"
        case .high:   return "pdf.quality.high.desc"
        }
    }

    private var icon: String {
        switch quality {
        case .low:    return "doc.zipper"
        case .medium: return "doc.badge.arrow.up"
        case .high:   return "doc.richtext"
        }
    }

    private var accentColor: Color {
        switch quality {
        case .low:    return .orange
        case .medium: return .blue
        case .high:   return .green
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(isSelected ? 0.15 : 0.07))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(titleKey)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text(quality.label)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(accentColor.opacity(0.12)))
                    }
                    Text(descKey)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(estimatedSize)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? accentColor : Color.primary)
                        .contentTransition(.numericText())
                    if !savingPercent.isEmpty {
                        Text(savingPercent)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accentColor.opacity(0.8))
                    }
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? accentColor : Color.secondary.opacity(0.3))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? accentColor.opacity(0.05) : Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            )
        }
        .buttonStyle(.plain)
    }
}
