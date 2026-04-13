import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var appState: GlobalAppState

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
                    // MARK: - Output Folder Section
                    sectionHeader("settings.section.output")

                    folderRow(
                        icon: "folder.fill",
                        label: "settings.defaultOutputFolder",
                        folder: appState.targetFolder,
                        onChoose: { chooseFolder(for: \.targetFolder) },
                        onClear: { appState.targetFolder = nil }
                    )

                    Divider().padding(.leading, 32)

                    // MARK: - About Section
                    sectionHeader("settings.section.about")

                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Comet Editor")
                                .font(.system(size: 13, weight: .medium))
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.02))

                    Divider().padding(.leading, 32)
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Section Header

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    // MARK: - Folder Row

    private func folderRow(
        icon: String,
        label: LocalizedStringKey,
        folder: URL?,
        onChoose: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                if let folder {
                    Text(folder.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(LocalizedStringKey("settings.noFolderSelected"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if folder != nil {
                    Button(LocalizedStringKey("settings.clearFolder")) {
                        onClear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
                }

                Button(LocalizedStringKey("settings.chooseFolder")) {
                    onChoose()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.02))
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
