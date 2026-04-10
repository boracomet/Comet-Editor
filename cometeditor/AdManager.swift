import SwiftUI
import AppKit
import Combine
import StoreKit

// MARK: - Ad Manager

/// Reklamları yönetir: config'den alınan ads listesini saklar,
/// sayfa geçişinde modal tetikler, inline banner sunar.
@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager()
    private init() {}

    @Published private(set) var ads: [AppConfig.AdInfo] = []
    @Published var adsRemoved: Bool = false

    // Modal için: gösterilecek reklam
    @Published var pendingModalAd: AppConfig.AdInfo? = nil

    func updateAds(_ newAds: [AppConfig.AdInfo]) {
        ads = newAds
    }

    /// Uygulama açılışında çağrılır — remove_ads satın alındıysa reklamları gizle
    func checkPurchaseStatus() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == "remove_ads" {
                purchased = true
                break
            }
        }
        adsRemoved = purchased
    }

    var pendingModalAdBinding: Binding<AppConfig.AdInfo?> {
        Binding(
            get: { self.pendingModalAd },
            set: { self.pendingModalAd = $0 }
        )
    }

    /// Sayfa geçişinde çağrılır. O sayfaya ait veya tüm sayfalara ait modal varsa tetikler.
    func triggerModalIfNeeded(for page: String) {
        guard !adsRemoved, pendingModalAd == nil else { return }
        let candidates = ads.filter {
            $0.type == "modal" && ($0.targetPage == nil || $0.targetPage == page)
        }
        pendingModalAd = candidates.max(by: { $0.priority < $1.priority })
    }

    /// Belirli bir sayfa için inline reklamları döner (targetPage eşleşen + tüm sayfalara açık).
    func inlineAds(for page: String) -> [AppConfig.AdInfo] {
        guard !adsRemoved else { return [] }
        return ads.filter {
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
            if let url = URL(string: ad.imageUrl) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 10
                if let (data, _) = try? await URLSession.shared.data(for: req),
                   let img = NSImage(data: data) {
                    loadedImage = img
                }
            }
            isLoading = false
        }
    }
}

// MARK: - Floating Ad Card (sağ alt köşe, içeriğe dokunmaz)

struct FloatingAdCard: View {
    let ads: [AppConfig.AdInfo]   // tüm inline reklamlar
    let onDismiss: () -> Void     // X → tamamen kapat
    @State private var currentIndex = 0
    @State private var loadedImages: [Int: NSImage] = [:]
    @State private var progress: Double = 0.0

    private let autoAdvanceInterval: Double = 6.0
    private var safeIndex: Int { min(currentIndex, max(0, ads.count - 1)) }
    private var ad: AppConfig.AdInfo { ads[safeIndex] }

    var body: some View {
        VStack(spacing: 0) {
            // Üst bar: sponsorlu + sayaç (döngüsel) + kapat
            HStack(spacing: 6) {
                Text(LocalizedStringKey("ad.sponsored"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if ads.count > 1 {
                    // Dairesel progress + sayaç — tıklanınca manuel geçiş
                    Button {
                        advanceIndex()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(currentIndex + 1)/\(ads.count)")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.2)) { onDismiss() } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider().opacity(0.5)

            // Görsel — oranı korunur, max 120px yüksek, yanlar boş kalır
            Button {
                if let url = URL(string: ad.linkUrl) { NSWorkspace.shared.open(url) }
            } label: {
                ZStack {
                    Color.primary.opacity(0.04)
                    if let img = loadedImages[currentIndex] {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 120)
            }
            .buttonStyle(.plain)
            .handCursor()

            Divider().opacity(0.5)

            // Alt: başlık + git butonu
            HStack(spacing: 8) {
                Text(ad.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Button(LocalizedStringKey("ad.visit")) {
                    if let url = URL(string: ad.linkUrl) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 260, maxWidth: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 4)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .task(id: currentIndex) {
            // Görsel yükle
            if loadedImages[currentIndex] == nil,
               let url = URL(string: ads[currentIndex].imageUrl) {
                var req = URLRequest(url: url); req.timeoutInterval = 10
                if let (data, _) = try? await URLSession.shared.data(for: req) {
                    loadedImages[currentIndex] = NSImage(data: data)
                }
            }
            guard ads.count > 1 else { return }
            // Progress animasyonu — her 0.05s'de güncelle → 6s'de tamamlanır
            progress = 0.0
            let steps = 120 // 6s / 0.05s
            for _ in 0..<steps {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                if Task.isCancelled { return }
                progress = min(progress + 1.0 / Double(steps), 1.0)
            }
            if !Task.isCancelled {
                advanceIndex()
            }
        }
    }

    private func advanceIndex() {
        guard ads.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex = (safeIndex + 1) % ads.count
        }
        progress = 0.0
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
    @State private var dismissed = false

    func body(content: Content) -> some View {
        let inlineAds = adManager.inlineAds(for: page)
        return content
            .overlay(alignment: .bottomTrailing) {
                if !inlineAds.isEmpty && !dismissed {
                    FloatingAdCard(ads: inlineAds, onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dismissed = true
                        }
                    })
                }
            }
            .onAppear {
                dismissed = false
                adManager.triggerModalIfNeeded(for: page)
            }
            .onChange(of: page) { newPage in
                dismissed = false
                adManager.triggerModalIfNeeded(for: newPage)
            }
            .onChange(of: inlineAds.count) { _ in
                // Reklam eklenince göster, tamamen kaldırılınca dismissed sıfırla
                if inlineAds.isEmpty {
                    dismissed = false
                } else if dismissed {
                    dismissed = false
                }
            }
            .sheet(
                isPresented: Binding<Bool>(
                    get: { adManager.pendingModalAd != nil },
                    set: { if !$0 { adManager.pendingModalAd = nil } }
                )
            ) {
                if let ad = adManager.pendingModalAd {
                    AdModalView(ad: ad, onDismiss: { adManager.pendingModalAd = nil })
                }
            }
    }
}
