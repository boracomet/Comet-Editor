import SwiftUI

struct AnnouncementSheetView: View {
    let announcement: AppConfig.AnnouncementInfo
    let onDismiss: () -> Void

    private var accentColor: Color {
        switch announcement.type {
        case "warning":  return Color.orange
        case "critical": return Color.red
        default:         return Color.blue
        }
    }

    private var iconName: String {
        switch announcement.type {
        case "warning":  return "exclamationmark.triangle.fill"
        case "critical": return "exclamationmark.octagon.fill"
        default:         return "info.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(announcement.title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            // Body
            if !announcement.body.isEmpty {
                ScrollView {
                    Text(announcement.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // Footer
            HStack {
                Text(announcement.createdAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(LocalizedStringKey("announcement.understood")) {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
