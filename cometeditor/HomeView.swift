//
//  HomeView.swift
//  cometeditor
//
//  Created by Bora Ata Türkoğlu on 4.03.2026.
//

import SwiftUI

struct HomeView: View {
    var onNavigate: ((MenuItem) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    private let toolCards: [(MenuItem, Color)] = [
        (.convertImage,  .blue),
        (.videoConvert,  .indigo),
        (.stockImage,    .teal),
        (.pdfEdit,       .orange),
        (.qrCode,        .purple),
        (.bgRemove,      .pink),
        (.ocr,           .green),
        (.fontDownload,  .cyan),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // MARK: - Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey("home.welcome"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.primary)

                        Text(LocalizedStringKey("home.welcome.subtitle"))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.secondary)
                    }

                    Spacer()

                    Link(destination: URL(string: "https://cometeditor.com") ?? URL(fileURLWithPath: "/")) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey("home.visitWebsite"))
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }

                // MARK: - Hero Image
                Image("banner-main")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.black.opacity(0.06),
                                lineWidth: 0.5
                            )
                    )

                // MARK: - Tool Cards Grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(toolCards, id: \.0) { item, color in
                        FeatureCard(
                            icon: item.icon,
                            title: item.title,
                            description: "home.feature.\(item.rawValue).desc",
                            accentColor: color,
                            onTap: { onNavigate?(item) }
                        )
                    }
                }

                Spacer()
            }
            .padding(32)
        }
    }
}

// MARK: - Feature Card
struct FeatureCard: View {
    let icon: String
    let title: LocalizedStringKey
    let description: String
    let accentColor: Color
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Text(LocalizedStringKey(description))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(isHovered ? 0.08 : 0.04)
                            : Color.black.opacity(isHovered ? 0.04 : 0.02)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .handCursor()
    }
}




#Preview {
    HomeView()
}
