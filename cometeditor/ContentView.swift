//
//  ContentView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI
import Combine

struct ContentView: View {
    @AppStorage("selectedMenuItem") private var selectedItemRaw: String = MenuItem.home.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver

    @State private var maintenanceMessage: String? = nil
    @State private var forceUpdateInfo: AppConfig.ForceUpdateInfo? = nil
    @State private var showMaintenance = false
    @State private var showForceUpdate = false
    @State private var pendingAnnouncements: [AppConfig.AnnouncementInfo] = []
    @State private var shownAnnouncementIds: Set<Int> = {
        let arr = UserDefaults.standard.array(forKey: "comet_shown_announcement_ids") as? [Int] ?? []
        return Set(arr)
    }()
    @State private var currentAnnouncement: AppConfig.AnnouncementInfo? = nil

    private var selectedItem: Binding<MenuItem> {
        Binding(
            get: { MenuItem(rawValue: selectedItemRaw) ?? .home },
            set: {
                selectedItemRaw = $0.rawValue
                CometAnalytics.shared.trackEvent(page: $0.rawValue, eventType: .pageView)
                // Feature bazlı sayfa görüntüleme
                let featurePageViewEvent: CometEventType? = switch $0 {
                case .convertImage:  .imagePageView
                case .upscaleImage:  .upscalePageView
                case .videoConvert:  .videoPageView
                case .ocr:           .ocrPageView
                case .bgRemove:      .bgPageView
                case .qrCode:        .qrPageView
                case .pdfEdit:       .pdfPageView
                case .fontDownload:  .fontPageView
                case .stockImage:    .stockPageView
                default:             nil
                }
                if let event = featurePageViewEvent {
                    CometAnalytics.shared.trackEvent(page: $0.rawValue, eventType: event)
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedItem: selectedItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .withAds(page: selectedItem.wrappedValue.rawValue)
        }
        .navigationTitle("")
        .task { await checkAppConfig(forceRefresh: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkAppConfig(forceRefresh: true) }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            Task { await checkAppConfig(forceRefresh: true) }
        }
        .overlay {
            if showMaintenance {
                maintenanceScreen
                    .zIndex(999)
            }
        }
        .overlay {
            if showForceUpdate {
                forceUpdateScreen
                    .zIndex(999)
            }
        }
        .sheet(item: $currentAnnouncement) { ann in
            AnnouncementSheetView(announcement: ann) {
                currentAnnouncement = nil
                showNextAnnouncementIfNeeded()
            }
        }
        .toolbar(showMaintenance || showForceUpdate ? .hidden : .automatic)
        .alert(LocalizedStringKey("folder.default.prompt.title"), isPresented: $appState.showDefaultFolderPrompt) {
            Button(LocalizedStringKey("folder.default.prompt.yes")) {
                if let url = appState.pendingDefaultFolderURL {
                    appState.targetFolder = url
                }
                appState.pendingDefaultFolderURL = nil
            }
            Button(LocalizedStringKey("folder.default.prompt.no"), role: .cancel) {
                appState.pendingDefaultFolderURL = nil
            }
        } message: {
            Text(LocalizedStringKey("folder.default.prompt.body"))
        }
    }

    // MARK: - App Config Check

    private func checkAppConfig(forceRefresh: Bool = false) async {
        let config = await CometAnalytics.shared.fetchConfig(forceRefresh: forceRefresh)

        AdManager.shared.updateAds(config.ads)

        if !config.maintenanceMode.isEnabled {
            showMaintenance = false
        } else {
            maintenanceMessage = config.maintenanceMode.message
            showMaintenance = true
            return
        }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        if config.forceUpdate.isEnabled,
           CometAnalytics.isVersionBelow(currentVersion, minimum: config.forceUpdate.minVersion) {
            forceUpdateInfo = config.forceUpdate
            showForceUpdate = true
        } else {
            showForceUpdate = false
        }

        // macOS hedefli duyuruları filtrele ve kaydet
        let macAnnouncements = config.announcements.filter { $0.target == "all" || $0.target == "macos" }
        appState.cachedAnnouncements = macAnnouncements

        // Sunucuda artık olmayan id'leri temizle (silinmiş duyurular tekrar bloklamasın)
        let activeIds = Set(macAnnouncements.map { $0.id })
        let staleIds = shownAnnouncementIds.subtracting(activeIds)
        if !staleIds.isEmpty {
            shownAnnouncementIds.subtract(staleIds)
            UserDefaults.standard.set(Array(shownAnnouncementIds), forKey: "comet_shown_announcement_ids")
        }

        // Daha önce gösterilmemiş duyuruları kuyruğa al
        let unseen = macAnnouncements.filter { !shownAnnouncementIds.contains($0.id) }
        if !unseen.isEmpty {
            pendingAnnouncements = unseen
            showNextAnnouncementIfNeeded()
        }
    }

    private func showNextAnnouncementIfNeeded() {
        guard currentAnnouncement == nil, let next = pendingAnnouncements.first else { return }
        pendingAnnouncements.removeFirst()
        shownAnnouncementIds.insert(next.id)
        UserDefaults.standard.set(Array(shownAnnouncementIds), forKey: "comet_shown_announcement_ids")
        currentAnnouncement = next
    }

    // MARK: - Maintenance Full Screen

    private var maintenanceScreen: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey("app.maintenance.title2"))
                    .font(.system(size: 28, weight: .bold))
                Text(LocalizedStringKey("app.maintenance.body"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Button(LocalizedStringKey("app.quit2")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                .padding(.top, 8)
            }
            .padding(60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Force Update Full Screen

    private var forceUpdateScreen: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.blue)
                Text(LocalizedStringKey("app.forceUpdate.title2"))
                    .font(.system(size: 28, weight: .bold))
                Text(LocalizedStringKey("app.forceUpdate.body"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                HStack(spacing: 12) {
                    if let info = forceUpdateInfo,
                       !info.storeUrl.isEmpty,
                       let url = URL(string: info.storeUrl) {
                        Button(LocalizedStringKey("app.forceUpdate.button2")) {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(LocalizedStringKey("app.quit2")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Content Router
    @ViewBuilder
    private var contentView: some View {
        switch selectedItem.wrappedValue {
        case .home:
            HomeView(
                onQuickImage: { preset in
                    appState.pendingHomeQuickImagePreset = preset
                    selectedItem.wrappedValue = .convertImage
                },
                onQuickVideo: { preset in
                    appState.pendingHomeQuickVideoPreset = preset
                    selectedItem.wrappedValue = .videoConvert
                },
                onQuickPdf: { preset in
                    if let preset { appState.pendingHomePDFPreset = preset }
                    selectedItem.wrappedValue = .pdfEdit
                },
                onNavigate: { item in
                    selectedItem.wrappedValue = item
                }
            )
        case .convertImage:
            ConvertImageView(columnVisibility: $columnVisibility)
        case .upscaleImage:
            UpscaleView(columnVisibility: $columnVisibility)
        case .videoConvert:
            VideoConvertView(columnVisibility: $columnVisibility)
        case .videoEdit:
            VideoEditView(columnVisibility: $columnVisibility)
        case .stockImage:
            StockImageView(columnVisibility: $columnVisibility)
        case .pdfEdit:
            PDFEditView(columnVisibility: $columnVisibility)
        case .qrCode:
            QRCodeView(columnVisibility: $columnVisibility)
        case .bgRemove:
            BgRemoveView(columnVisibility: $columnVisibility)
        case .ocr:
            OCRView(columnVisibility: $columnVisibility)
        case .fontDownload:
            FontDownloadView(columnVisibility: $columnVisibility)
        case .suggestion:
            SuggestionView()
        case .announcements:
            AnnouncementsView()
        case .settings:
            AppSettingsView()
        case .team:
            TeamModalView()
        }
    }
}
