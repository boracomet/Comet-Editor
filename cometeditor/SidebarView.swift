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
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var windowState: WindowStateObserver

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
            HStack(spacing: 8) {
                Label(item.title, systemImage: item.icon)
                    .badge(item.badge.map { Text(LocalizedStringKey($0)) })
                if appState.processingMenuItem == item {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
            }
            .tag(item)
        }
    }
    // MARK: - All supported languages
    private struct AppLanguage {
        let code: String
        let flag: String
        let name: String
    }

    private let allLanguages: [AppLanguage] = [
        // Türkçe & İngilizce önce
        AppLanguage(code: "tr",       flag: "🇹🇷", name: "Türkçe"),
        AppLanguage(code: "en",       flag: "🇬🇧", name: "English"),
        AppLanguage(code: "en-CA",    flag: "🇨🇦", name: "English (Canada)"),
        // Avrupa
        AppLanguage(code: "de",       flag: "🇩🇪", name: "Deutsch"),
        AppLanguage(code: "fr",       flag: "🇫🇷", name: "Français"),
        AppLanguage(code: "it",       flag: "🇮🇹", name: "Italiano"),
        AppLanguage(code: "es",       flag: "🇪🇸", name: "Español"),
        AppLanguage(code: "es-MX",    flag: "🇲🇽", name: "Español (México)"),
        AppLanguage(code: "es-AR",    flag: "🇦🇷", name: "Español (Argentina)"),
        AppLanguage(code: "es-CL",    flag: "🇨🇱", name: "Español (Chile)"),
        AppLanguage(code: "pt-PT",    flag: "🇵🇹", name: "Português"),
        AppLanguage(code: "pt-BR",    flag: "🇧🇷", name: "Português (Brasil)"),
        AppLanguage(code: "nl",       flag: "🇳🇱", name: "Nederlands"),
        AppLanguage(code: "sv",       flag: "🇸🇪", name: "Svenska"),
        AppLanguage(code: "no",       flag: "🇳🇴", name: "Norsk"),
        AppLanguage(code: "da",       flag: "🇩🇰", name: "Dansk"),
        AppLanguage(code: "fi",       flag: "🇫🇮", name: "Suomi"),
        AppLanguage(code: "is",       flag: "🇮🇸", name: "Íslenska"),
        AppLanguage(code: "pl",       flag: "🇵🇱", name: "Polski"),
        AppLanguage(code: "cs",       flag: "🇨🇿", name: "Čeština"),
        AppLanguage(code: "sk",       flag: "🇸🇰", name: "Slovenčina"),
        AppLanguage(code: "hu",       flag: "🇭🇺", name: "Magyar"),
        AppLanguage(code: "ro",       flag: "🇷🇴", name: "Română"),
        AppLanguage(code: "bg",       flag: "🇧🇬", name: "Български"),
        AppLanguage(code: "hr",       flag: "🇭🇷", name: "Hrvatski"),
        AppLanguage(code: "sl",       flag: "🇸🇮", name: "Slovenščina"),
        AppLanguage(code: "bs",       flag: "🇧🇦", name: "Bosanski"),
        AppLanguage(code: "sr",       flag: "🇷🇸", name: "Српски"),
        AppLanguage(code: "mk",       flag: "🇲🇰", name: "Македонски"),
        AppLanguage(code: "sq",       flag: "🇦🇱", name: "Shqip"),
        AppLanguage(code: "lt",       flag: "🇱🇹", name: "Lietuvių"),
        AppLanguage(code: "lv",       flag: "🇱🇻", name: "Latviešu"),
        AppLanguage(code: "et",       flag: "🇪🇪", name: "Eesti"),
        AppLanguage(code: "el",       flag: "🇬🇷", name: "Ελληνικά"),
        // Doğu Avrupa / Orta Asya
        AppLanguage(code: "ru",       flag: "🇷🇺", name: "Русский"),
        AppLanguage(code: "uk",       flag: "🇺🇦", name: "Українська"),
        AppLanguage(code: "kk",       flag: "🇰🇿", name: "Қазақша"),
        AppLanguage(code: "ky",       flag: "🇰🇬", name: "Кыргызча"),
        AppLanguage(code: "uz",       flag: "🇺🇿", name: "O'zbek"),
        AppLanguage(code: "tk",       flag: "🇹🇲", name: "Türkmen"),
        AppLanguage(code: "az",       flag: "🇦🇿", name: "Azərbaycan"),
        AppLanguage(code: "tt",       flag: "🇷🇺", name: "Татарча"),
        AppLanguage(code: "ba",       flag: "🇷🇺", name: "Башҡортса"),
        AppLanguage(code: "cv",       flag: "🇷🇺", name: "Чăвашла"),
        AppLanguage(code: "sah",      flag: "🇷🇺", name: "Саха тыла"),
        AppLanguage(code: "tyv",      flag: "🇷🇺", name: "Тыва дыл"),
        AppLanguage(code: "alt",      flag: "🇷🇺", name: "Алтай тил"),
        AppLanguage(code: "gag",      flag: "🇲🇩", name: "Gagauzça"),
        AppLanguage(code: "ug",       flag: "🇨🇳", name: "ئۇيغۇرچە"),
        // Kafkasya
        AppLanguage(code: "ka",       flag: "🇬🇪", name: "ქართული"),
        AppLanguage(code: "hy",       flag: "🇦🇲", name: "Հայերեն"),
        AppLanguage(code: "he",       flag: "🇮🇱", name: "עברית"),
        // Asya
        AppLanguage(code: "zh-Hans",    flag: "🇨🇳", name: "中文(简体)"),
        AppLanguage(code: "zh-CN",      flag: "🇨🇳", name: "中文(中国)"),
        AppLanguage(code: "zh-Hant-TW", flag: "🇹🇼", name: "中文(繁體·台灣)"),
        AppLanguage(code: "zh-Hant-HK", flag: "🇭🇰", name: "中文(繁體·香港)"),
        AppLanguage(code: "ja",       flag: "🇯🇵", name: "日本語"),
        AppLanguage(code: "ko",       flag: "🇰🇷", name: "한국어"),
        AppLanguage(code: "hi",       flag: "🇮🇳", name: "हिन्दी"),
        AppLanguage(code: "bn",       flag: "🇧🇩", name: "বাংলা"),
        AppLanguage(code: "ur",       flag: "🇵🇰", name: "اردو"),
        AppLanguage(code: "th",       flag: "🇹🇭", name: "ภาษาไทย"),
        AppLanguage(code: "vi",       flag: "🇻🇳", name: "Tiếng Việt"),
        AppLanguage(code: "id",       flag: "🇮🇩", name: "Indonesia"),
        AppLanguage(code: "ms",       flag: "🇲🇾", name: "Melayu"),
    ]

    private var currentLang: AppLanguage {
        allLanguages.first { $0.code == languageManager.currentLanguage }
            ?? AppLanguage(code: "en", flag: "🇬🇧", name: "English")
    }

    // MARK: - Bottom Footer
    private var footerView: some View {
        GeometryReader { geo in
            HStack(spacing: 8) {
                // Language Picker
                Menu {
                    ForEach(allLanguages, id: \.code) { lang in
                        Button {
                            languageManager.setLanguage(lang.code)
                        } label: {
                            Text("\(lang.flag) \(lang.name)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentLang.flag)
                            .font(.system(size: 13))
                        if geo.size.width > 130 {
                            Text(currentLang.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, geo.size.width > 130 ? 10 : 6)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Team / Help Button
                Button {
                    withAnimation { selectedItem = .team }
                } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: geo.size.width)
        }
        .frame(height: 52)
    }
}

#Preview {
    SidebarView(selectedItem: .constant(.home))
        .frame(width: 240, height: 500)
}
