import SwiftUI

struct AnnouncementsView: View {
    @EnvironmentObject var appState: GlobalAppState

    private var announcements: [AppConfig.AnnouncementInfo] {
        appState.cachedAnnouncements
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("menu.announcements"))
                    .font(.system(size: 22, weight: .bold))
                Text(LocalizedStringKey("announcements.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 20)

            Divider()

            if announcements.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(announcements) { ann in
                            AnnouncementRow(announcement: ann)
                            Divider().padding(.leading, 56)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(LocalizedStringKey("announcements.empty"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct AnnouncementRow: View {
    let announcement: AppConfig.AnnouncementInfo

    private var typeColor: Color {
        switch announcement.type {
        case "critical": return .red
        case "warning":  return .orange
        default:         return .blue
        }
    }

    private var typeIcon: String {
        switch announcement.type {
        case "critical": return "exclamationmark.triangle.fill"
        case "warning":  return "exclamationmark.circle.fill"
        default:         return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: typeIcon)
                .font(.system(size: 20))
                .foregroundStyle(typeColor)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(announcement.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(announcement.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(announcement.createdAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
