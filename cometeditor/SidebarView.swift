//
//  SidebarView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: MenuItem
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var windowState: WindowStateObserver

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItem) {
            // MARK: - Header
            logoSection
                .listRowSeparator(.hidden)

            // MARK: - Menu Sections
            ForEach(MenuSection.allCases, id: \.self) { section in
                if let title = section.title {
                    Section(title) {
                        sectionItems(section)
                    }
                } else {
                    Section {
                        sectionItems(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .top) {
            // Tam ekranda macOS'un çizdiği üst border çizgisini örtür
            if windowState.isFullScreen {
                Rectangle()
                    .fill(Color(NSColor.windowBackgroundColor))
                    .frame(height: 1)
            }
        }

        // MARK: - Bottom Footer
        footerView
        }
    }

    // MARK: - Header
    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Image("CometMenuLogo")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 40, alignment: .leading)
                    .foregroundStyle(Color.primary)
                    .opacity(1)
                    .accessibilityLabel("Comet Editor")
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            Divider()
        }
    }

    // MARK: - Section Items
    @ViewBuilder
    private func sectionItems(_ section: MenuSection) -> some View {
        ForEach(section.items) { item in
            HStack(spacing: 8) {
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.icon)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            selectedItem == item
                            ? Color.white
                            : Color.primary
                        )
                }
                if appState.processingMenuItem == item
                    || (item == .convertImage && appState.isConvertingImages) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
            }
            .tag(item)
        }
    }

    // MARK: - Bottom Footer
    private var footerView: some View {
        HStack {
            Spacer(minLength: 0)

            Button {
                selectedItem = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selectedItem == .settings ? Color.accentColor : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
                    .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey("menu.settings"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(height: 52)
    }
}

#Preview {
    SidebarView(selectedItem: .constant(.home))
        .frame(width: 240, height: 500)
}
