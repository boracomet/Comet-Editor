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

    private var selectedItem: Binding<MenuItem> {
        Binding(
            get: { MenuItem(rawValue: selectedItemRaw) ?? .home },
            set: {
                selectedItemRaw = $0.rawValue
                CometAnalytics.shared.trackEvent(page: $0.rawValue, eventType: .pageView)
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
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            guard !showMaintenance, !showForceUpdate else { return }
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
        .toolbar(showMaintenance || showForceUpdate ? .hidden : .automatic)
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
                Text(LocalizedStringKey("app.maintenance.title"))
                    .font(.system(size: 28, weight: .bold))
                Text(maintenanceMessage ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Button(LocalizedStringKey("app.quit")) {
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
                Text(LocalizedStringKey("app.forceUpdate.title"))
                    .font(.system(size: 28, weight: .bold))
                if let info = forceUpdateInfo {
                    Text(info.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                HStack(spacing: 12) {
                    Button(LocalizedStringKey("app.quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)

                    if let info = forceUpdateInfo, let url = URL(string: info.storeUrl) {
                        Button(LocalizedStringKey("app.forceUpdate.button")) {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
            HomeView(onNavigate: { item in selectedItemRaw = item.rawValue })
        case .convertImage:
            ConvertImageView(columnVisibility: $columnVisibility)
        case .videoConvert:
            VideoConvertView(columnVisibility: $columnVisibility)
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
        case .team:
            TeamModalView()
        }
    }
}
