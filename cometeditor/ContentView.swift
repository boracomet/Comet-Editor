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
        case .stockImage:
            StockImageView(columnVisibility: $columnVisibility) { item in
                selectedItem.wrappedValue = item
            }
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
        case .settings:
            AppSettingsView()
        }
    }
}
