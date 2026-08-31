import SwiftUI

private enum CreditsInfo {
    static let appName = "Comet Editor"
    static let websiteHost = "cometeditor.com"
    static let developerName = "Bora Ata Türkoğlu"
    static let visualContributorName = "Beyza Nur Keçeli"
    static let websiteURL = URL(string: "https://cometeditor.com")
    static let developerURL = URL(string: "https://boraturkoglu.com")
    static let visualContributorURL = URL(string: "https://www.linkedin.com/in/beyzanurkeceli/")

    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.7"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "10"
        return "\(short) (\(build))"
    }
}

struct AppSettingsView: View {
    @EnvironmentObject var appState: GlobalAppState
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("menu.settings"))
                    .font(.system(size: 22, weight: .bold))
                Text(LocalizedStringKey("settings.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    outputSection
                    languageSection
                    creditsSection
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InspectorCardMetrics.panelBackground(for: colorScheme))
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("settings.section.output")

            settingsCard {
                folderRow(
                    label: "settings.defaultOutputFolder",
                    folder: appState.targetFolder,
                    isStale: appState.targetFolderStale,
                    onChoose: { chooseFolder(for: \.targetFolder) },
                    onClear: { appState.targetFolder = nil }
                )
            }
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("settings.section.language")

            settingsCard {
                settingsRow(label: "settings.language") {
                    languageMenu
                }
            }
        }
    }

    private var currentLanguage: AppLanguage {
        AppLanguage.named(languageManager.currentLanguage)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.all) { lang in
                Button {
                    languageManager.setLanguage(lang.code)
                } label: {
                    Text("\(lang.flag)  \(lang.name)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLanguage.flag)
                Text(currentLanguage.name)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    // MARK: - Credits

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey("settings.credits"))
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 32)
                .padding(.top, 24)

            settingsCard {
                settingsRow(label: "settings.credits.app") {
                    Text(CreditsInfo.appName)
                }

                settingsSeparator

                settingsRow(label: "settings.credits.version") {
                    Text(CreditsInfo.version)
                }

                settingsSeparator

                settingsRow(label: "settings.credits.website") {
                    creditsLink(CreditsInfo.websiteHost, url: CreditsInfo.websiteURL)
                }

                settingsSeparator

                settingsRow(label: "settings.credits.developer") {
                    HStack(spacing: 6) {
                        Text(CreditsInfo.developerName)
                        creditsGlobeLink(url: CreditsInfo.developerURL)
                    }
                }

                settingsSeparator

                settingsRow(label: "settings.credits.visualContributor") {
                    HStack(spacing: 6) {
                        Text(CreditsInfo.visualContributorName)
                        creditsGlobeLink(url: CreditsInfo.visualContributorURL)
                    }
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 0)
    }

    // MARK: - Card chrome (inspector charcoal + hairline border)

    private var settingsCardFill: Color {
        InspectorCardMetrics.cardFill(for: colorScheme)
    }

    private var settingsCardStroke: Color {
        InspectorCardMetrics.cardBorder(for: colorScheme)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: InspectorCardMetrics.cornerRadius, style: .continuous)
                .fill(settingsCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: InspectorCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(settingsCardStroke, lineWidth: InspectorCardMetrics.borderWidth)
        )
        .padding(.horizontal, 32)
    }

    private var settingsSeparator: some View {
        Rectangle()
            .fill(InspectorCardMetrics.separator(for: colorScheme))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func settingsRow<Value: View>(
        label: LocalizedStringKey,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Folder Row

    private func folderRow(
        label: LocalizedStringKey,
        folder: URL?,
        isStale: Bool = false,
        onChoose: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if isStale {
                    Text(LocalizedStringKey("folder.missing.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Group {
                    if isStale {
                        Text(folder?.path ?? "")
                            .foregroundStyle(Color.orange)
                    } else if let folder {
                        Text(folder.path)
                            .foregroundStyle(.primary)
                    } else {
                        Text(LocalizedStringKey("settings.noFolderSelected"))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)

                if folder != nil || isStale {
                    Button(LocalizedStringKey("settings.clearFolder")) {
                        onClear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.75))
                }

                Button(LocalizedStringKey(isStale ? "folder.missing.pick" : "settings.chooseFolder")) {
                    onChoose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func creditsLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Text(title)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .handCursor()
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func creditsGlobeLink(url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(url.host ?? url.absoluteString)
        }
    }

    // MARK: - Folder Picker

    private func chooseFolder(for keyPath: ReferenceWritableKeyPath<GlobalAppState, URL?>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("settings.folderPicker.message", comment: "")
        panel.prompt = NSLocalizedString("settings.folderPicker.button", comment: "")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState[keyPath: keyPath] = url
    }
}
