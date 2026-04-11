//
//  PDFQualityPickerSheet.swift
//  cometeditor
//
//  Metinler LanguageManager üzerinden — in-app dil seçici ile SwiftUI locale uyumu sağlanır.
//

import SwiftUI

struct PDFQualityPickerSheet: View {
    @EnvironmentObject private var languageManager: LanguageManager

    let pdf: PDFItem
    @Binding var selectedQuality: PDFCompressionQuality
    let onConfirm: (PDFCompressionQuality) -> Void
    let onCancel: () -> Void

    @State private var estimates: [PDFCompressionQuality: (size: String, saving: String)] = [:]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(languageManager.string("pdf.quality.modal.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(languageManager.string("pdf.quality.modal.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(spacing: 8) {
                ForEach(PDFCompressionQuality.allCases) { quality in
                    MinimalQualityButton(
                        title: qualityTitle(quality),
                        description: qualityDescription(quality),
                        isSelected: selectedQuality == quality,
                        percentLabel: quality.label,
                        estimatedSize: estimates[quality]?.size ?? "—",
                        savingPercent: estimates[quality]?.saving ?? ""
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedQuality = quality
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 10) {
                Button {
                    onConfirm(selectedQuality)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(languageManager.string("pdf.quality.modal.confirm"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .multilineTextAlignment(.center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)

                Button {
                    onCancel()
                } label: {
                    Text(languageManager.string("pdf.quality.modal.cancel"))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .multilineTextAlignment(.center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await computeEstimates()
        }
    }

    private func qualityTitle(_ quality: PDFCompressionQuality) -> String {
        switch quality {
        case .low:    return languageManager.string("pdf.quality.low.title")
        case .medium: return languageManager.string("pdf.quality.medium.title")
        case .high:   return languageManager.string("pdf.quality.high.title")
        }
    }

    private func qualityDescription(_ quality: PDFCompressionQuality) -> String {
        switch quality {
        case .low:    return languageManager.string("pdf.quality.low.desc")
        case .medium: return languageManager.string("pdf.quality.medium.desc")
        case .high:   return languageManager.string("pdf.quality.high.desc")
        }
    }

    private func computeEstimates() async {
        let url = pdf.url
        let originalSize = pdf.fileSizeBytes

        let result: [PDFCompressionQuality: (String, String)] = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else {
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

// MARK: - Tam genişlik kalite satırı

private struct MinimalQualityButton: View {
    let title: String
    let description: String
    let isSelected: Bool
    let percentLabel: String
    let estimatedSize: String
    let savingPercent: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.22))
                    .frame(width: 3, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text(percentLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                        Spacer(minLength: 4)
                        HStack(spacing: 6) {
                            Text(estimatedSize)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.primary)
                                .contentTransition(.numericText())
                            if !savingPercent.isEmpty {
                                Text(savingPercent)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
