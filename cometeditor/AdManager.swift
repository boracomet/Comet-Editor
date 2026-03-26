import SwiftUI
import AppKit
import Combine

// MARK: - Ad Manager

/// Reklamları yönetir: config'den alınan ads listesini saklar,
/// sayfa geçişinde modal tetikler, inline banner sunar.
@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager()
    private init() {}

    @Published private(set) var ads: [AppConfig.AdInfo] = []

    // Modal için: gösterilecek reklam
    @Published var pendingModalAd: AppConfig.AdInfo? = nil

    func updateAds(_ newAds: [AppConfig.AdInfo]) {
        ads = newAds
    }

    var pendingModalAdBinding: Binding<AppConfig.AdInfo?> {
        Binding(
            get: { self.pendingModalAd },
            set: { self.pendingModalAd = $0 }
        )
    }

    /// Sayfa geçişinde çağrılır. O sayfaya ait veya tüm sayfalara ait modal varsa tetikler.
    func triggerModalIfNeeded(for page: String) {
        guard pendingModalAd == nil else { return }
        let candidates = ads.filter {
            $0.type == "modal" && ($0.targetPage == nil || $0.targetPage == page)
        }
        // En yüksek öncelikli olanı seç
        pendingModalAd = candidates.max(by: { $0.priority < $1.priority })
    }

    /// Belirli bir sayfa için inline reklamları döner (targetPage eşleşen + tüm sayfalara açık).
    func inlineAds(for page: String) -> [AppConfig.AdInfo] {
        ads.filter {
            $0.type == "inline" && ($0.targetPage == nil || $0.targetPage == page)
        }.sorted { $0.priority > $1.priority }
    }
}

// MARK: - Modal Ad Sheet

struct AdModalView: View {
    let ad: AppConfig.AdInfo
    let onDismiss: () -> Void

    @State private var loadedImage: NSImage? = nil
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(LocalizedStringKey("ad.sponsored"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Görsel
            ZStack {
                Color(NSColor.windowBackgroundColor)
                if isLoading {
                    ProgressView().controlSize(.large)
                }
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)

            Divider()

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ad.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(ad.linkUrl)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(LocalizedStringKey("ad.visit")) {
                    if let url = URL(string: ad.linkUrl) {
                        NSWorkspace.shared.open(url)
                    }
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            isLoading = true
            if let url = URL(string: ad.imageUrl),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let img = NSImage(data: data) {
                loadedImage = img
            }
            isLoading = false
        }
    }
}

// MARK: - Inline Ad Banner

struct InlineAdBanner: View {
    let ad: AppConfig.AdInfo
    @State private var loadedImage: NSImage? = nil
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            ZStack(alignment: .topTrailing) {
                Button {
                    if let url = URL(string: ad.linkUrl) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    ZStack {
                        Color.secondary.opacity(0.08)
                        if let img = loadedImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFill()
                                .clipped()
                        } else {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(ad.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                }
                .buttonStyle(.plain)
                .handCursor()

                // Kapat butonu
                Button { withAnimation { isVisible = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)

                // Sponsorlu etiketi
                Text(LocalizedStringKey("ad.sponsored"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
            }
            .task(id: ad.id) {
                guard let url = URL(string: ad.imageUrl),
                      let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                loadedImage = NSImage(data: data)
            }
        }
    }
}

// MARK: - View Modifier: Sayfa Reklam Desteği

extension View {
    /// Her view'a ekle: modal tetikler. Inline banner HomeView içinde özel konumlandırılır.
    func withAds(page: String) -> some View {
        modifier(AdSupportModifier(page: page))
    }
}

private struct AdSupportModifier: ViewModifier {
    let page: String
    @ObservedObject private var adManager = AdManager.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                adManager.triggerModalIfNeeded(for: page)
            }
            .sheet(item: adManager.pendingModalAdBinding) { ad in
                AdModalView(ad: ad, onDismiss: { adManager.pendingModalAd = nil })
            }
    }
}
