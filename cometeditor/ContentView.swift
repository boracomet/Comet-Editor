//
//  ContentView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedItem: MenuItem = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @EnvironmentObject var appState: GlobalAppState

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    ZStack {
                        if appState.showingTeamModal {
                            Color.black.opacity(0.6)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        appState.showingTeamModal = false
                                    }
                                }

                            TeamModalView()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
                                .padding(40)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .allowsHitTesting(appState.showingTeamModal)
                    .animation(.easeInOut(duration: 0.2), value: appState.showingTeamModal)
                    .zIndex(200)
                }
        }
        .navigationTitle("")
    }

    // MARK: - Content Router
    @ViewBuilder
    private var contentView: some View {
        switch selectedItem {
        case .home:
            HomeView()
        case .convertImage:
            ConvertImageView(columnVisibility: $columnVisibility)
        case .videoConvert:
            VideoConvertView(columnVisibility: $columnVisibility)
        case .pdfEdit:
            PDFEditView(columnVisibility: $columnVisibility)
        case .qrCode:
            QRCodeView(columnVisibility: $columnVisibility)
        }
    }
}
