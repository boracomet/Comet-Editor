//
//  ContentView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("selectedMenuItem") private var selectedItemRaw: String = MenuItem.home.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver

    private var selectedItem: Binding<MenuItem> {
        Binding(
            get: { MenuItem(rawValue: selectedItemRaw) ?? .home },
            set: { selectedItemRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedItem: selectedItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
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
        case .videoEdit:
            VideoEditView(columnVisibility: $columnVisibility)
        case .team:
            TeamModalView()
        }
    }
}

// MARK: - Coming Soon
struct ComingSoonView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.fill")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Text(LocalizedStringKey("app.comingSoon.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.primary)
            Text(LocalizedStringKey("app.comingSoon.message"))
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
