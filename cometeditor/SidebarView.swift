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
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItem) {
            // MARK: - Logo
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
        
        // MARK: - Bottom Footer
        footerView
        }
    }

    // MARK: - Logo
    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Image("CometMenuLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 41)
                Spacer()
            }
            .padding(.top, 4)

            Divider()
        }
    }

    // MARK: - Section Items
    @ViewBuilder
    private func sectionItems(_ section: MenuSection) -> some View {
        ForEach(section.items) { item in
            Label(item.title, systemImage: item.icon)
                .tag(item)
        }
    }
    // MARK: - Bottom Footer
    private var footerView: some View {
        HStack {
            // Language Picker Mock/Button
            Menu {
                Button {
                    appLanguage = "tr"
                } label: {
                    Text("🇹🇷 Türkçe")
                }
                
                Button {
                    appLanguage = "en"
                } label: {
                    Text("🇬🇧 English")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(appLanguage == "tr" ? "🇹🇷" : "🇬🇧")
                        .font(.system(size: 14))
                    Text(appLanguage == "tr" ? "Türkçe" : "English")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            
            Spacer()
            
            // Team Button
            Button {
                appState.showingTeamModal = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SidebarView(selectedItem: .constant(.home))
        .frame(width: 240, height: 500)
}
