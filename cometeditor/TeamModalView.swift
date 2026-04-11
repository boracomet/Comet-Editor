import SwiftUI

struct TeamModalView: View {
    @EnvironmentObject var appState: GlobalAppState

    let teamMembers = [
        TeamMember(initials: "BAT", name: "Bora Ata Türkoğlu", role: "Founder & Lead Developer", linkedin: "https://www.linkedin.com/in/boracomet/?skipRedirect=true", github: "https://github.com/boracomet", website: "https://boraturkoglu.com", behance: nil, instagram: nil, imageName: "bora_profile"),
        TeamMember(initials: "MA", name: "Mehmet Atademir", role: "DevOps Engineer", linkedin: "https://www.linkedin.com/in/mehmet-atademir-148656234/", github: "https://github.com/atademirmehmet", website: "http://mehmetatademir.com.tr/", behance: nil, instagram: nil, imageName: "mehmet_profile"),
        TeamMember(initials: "YK", name: "Yılmaz Kavakçıoğlu", role: "Advertising Management", linkedin: "https://www.linkedin.com/in/yilmazkavakcioglu/", github: nil, website: nil, behance: "https://www.behance.net/yilmazkavakcioglu", instagram: "https://instagram.com/yilmaz.creative", imageName: "yilmaz_profile"),
        TeamMember(initials: "BNK", name: "Beyza Nur Keçeli", role: "Visual Designer", linkedin: "https://www.linkedin.com/in/beyzanurkeceli/", github: nil, website: nil, behance: "https://www.behance.net/beyzanurkeceli", instagram: "https://instagram.com/morphiadesign", imageName: "beyza_profile")
    ]

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Title
                    VStack(spacing: 10) {
                        Text(LocalizedStringKey("menu.team.title"))
                            .font(.system(size: min(30, max(26, geo.size.width * 0.034)), weight: .bold))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.center)
                            .tracking(-0.3)

                        Text(LocalizedStringKey("menu.team.subtitle"))
                            .font(.system(size: min(16, max(14, geo.size.width * 0.019)), weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: min(440, geo.size.width - 48))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, max(32, geo.size.height * 0.07))
                    .padding(.bottom, max(28, geo.size.height * 0.045))

                    // Team Grid — always 4 in a single row, capped at max card width
                    let maxCardW: CGFloat = 180
                    let minSpacing: CGFloat = 24
                    let count = CGFloat(teamMembers.count)
                    let totalMax = maxCardW * count + minSpacing * (count - 1)
                    let hPad: CGFloat = max(16, (geo.size.width - totalMax) / 2)
                    let availW = max(0, geo.size.width - hPad * 2)
                    let spacing: CGFloat = minSpacing
                    let cardW = max(80, min(maxCardW, (availW - spacing * (count - 1)) / count))

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(teamMembers, id: \.name) { member in
                            TeamMemberCard(member: member, cardWidth: cardW)
                                .frame(width: cardW)
                        }
                    }
                    .padding(.horizontal, hPad)
                    .padding(.bottom, max(24, geo.size.height * 0.04))

                    Divider()
                        .padding(.horizontal, hPad)
                        .padding(.vertical, max(20, geo.size.height * 0.03))

                    // Grafix footer
                    VStack(spacing: 10) {
                        Link(destination: URL(string: "https://heygrafix.com") ?? URL(fileURLWithPath: "/")) {
                            Image("grafix_logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: min(40, geo.size.height * 0.06))
                                .handCursor()
                        }
                        Text(LocalizedStringKey("team.thanks_grafix"))
                            .font(.system(size: min(12, geo.size.width * 0.018)))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, max(16, geo.size.height * 0.03))

                    // Version
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - Team Member Card

private struct TeamMemberCard: View {
    let member: TeamMember
    let cardWidth: CGFloat

    private var avatarSize: CGFloat { min(110, cardWidth * 0.55) }

    var body: some View {
        VStack(spacing: 16) {
            Image(member.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

            VStack(spacing: 6) {
                Text(member.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(member.role)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            // Social links
            HStack(spacing: 14) {
                socialLink(url: member.linkedin, image: "linkedin")

                if let github = member.github {
                    socialLink(url: github, image: "github")
                }
                if let website = member.website {
                    socialLinkSystem(url: website, systemName: "safari")
                }
                if let behance = member.behance {
                    socialLink(url: behance, image: "behance")
                }
                if let instagram = member.instagram {
                    socialLink(url: instagram, image: "instagram")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func socialLink(url: String, image: String) -> some View {
        if let dest = URL(string: url) {
            Link(destination: dest) {
                Image(image)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.secondary)
                    .handCursor()
            }
        }
    }

    @ViewBuilder
    private func socialLinkSystem(url: String, systemName: String) -> some View {
        if let dest = URL(string: url) {
            Link(destination: dest) {
                Image(systemName: systemName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.secondary)
                    .handCursor()
            }
        }
    }
}

struct TeamMember {
    let initials: String
    let name: String
    let role: String
    let linkedin: String
    let github: String?
    let website: String?
    let behance: String?
    let instagram: String?
    let imageName: String
}

#Preview {
    TeamModalView()
}
