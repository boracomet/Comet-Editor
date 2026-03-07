import SwiftUI

struct TeamModalView: View {
    @EnvironmentObject var appState: GlobalAppState
    
    // Team Members Data
    let teamMembers = [
        TeamMember(initials: "BAT", name: "Bora Ata Türkoğlu", role: "Founder & Lead Developer", linkedin: "https://www.linkedin.com/in/boracomet/?skipRedirect=true", github: "https://github.com/boracomet", website: "https://boraturkoglu.com", behance: nil, imageName: "bora_profile"),
        TeamMember(initials: "MA", name: "Mehmet Atademir", role: "DevOps Engineer", linkedin: "https://www.linkedin.com/in/mehmet-atademir-148656234/", github: nil, website: nil, behance: nil, imageName: "mehmet_profile"),
        TeamMember(initials: "YK", name: "Yılmaz Kavakçıoğlu", role: "Advertising Management", linkedin: "https://www.linkedin.com/in/yilmazkavakcioglu/", github: nil, website: nil, behance: nil, imageName: "yilmaz_profile"),
        TeamMember(initials: "BNK", name: "Beyza Nur Keçeli", role: "Visual Designer", linkedin: "https://www.linkedin.com/in/beyzanurkeceli/", github: nil, website: nil, behance: "https://www.behance.net/beyzanurkeceli", imageName: "beyza_profile")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 40) // Fixed top offset instead of Spacer to shift content up

            // Top Branding
            VStack(spacing: 0) {
                Link(destination: URL(string: "https://cometdevs.com")!) {
                    Image("cometdev_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80)
                        .onHover { isHovered in
                            DispatchQueue.main.async {
                                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Title Area
            VStack(spacing: 10) {
                Text(LocalizedStringKey("menu.team.title"))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.primary)

                Text(LocalizedStringKey("menu.team.subtitle"))
                    .font(.system(size: 17))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.top, 4)
            .padding(.bottom, 48)

            // Team Grid
            HStack(alignment: .top, spacing: 48) {
                ForEach(teamMembers, id: \.name) { member in
                    VStack(spacing: 18) {
                        // Profile Image
                        Image(member.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                        VStack(spacing: 10) {
                            Text(member.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.primary)

                            Text(member.role)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 14) {
                                Link(destination: URL(string: member.linkedin)!) {
                                    Image("linkedin")
                                        .resizable()
                                        .renderingMode(.template)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(Color.secondary)
                                        .onHover { isHovered in
                                            DispatchQueue.main.async {
                                                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                            }
                                        }
                                }

                                if let github = member.github, let url = URL(string: github) {
                                    Link(destination: url) {
                                        Image("github")
                                            .resizable()
                                            .renderingMode(.template)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(Color.secondary)
                                            .onHover { isHovered in
                                                DispatchQueue.main.async {
                                                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                                }
                                            }
                                    }
                                }

                                if let website = member.website, let url = URL(string: website) {
                                    Link(destination: url) {
                                        Image(systemName: "safari")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(Color.secondary)
                                            .onHover { isHovered in
                                                DispatchQueue.main.async {
                                                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                                }
                                            }
                                    }
                                }

                                if let behance = member.behance, let url = URL(string: behance) {
                                    Link(destination: url) {
                                        Image("behance")
                                            .resizable()
                                            .renderingMode(.template)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(Color.secondary)
                                            .onHover { isHovered in
                                                DispatchQueue.main.async {
                                                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                                }
                                            }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(width: 160)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)

            // Footer / Attribution (Grafix Only)
            VStack(spacing: 32) {
                // Thanks to Grafix
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://heygrafix.com")!) {
                        Image("grafix_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 48)
                            .onHover { isHovered in
                                DispatchQueue.main.async {
                                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }
                    }

                    Text(LocalizedStringKey("team.thanks_grafix"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 40)

            // Version Label
            Text("v1.2.0-beta")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.bottom, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.02))
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
    let imageName: String
}

#Preview {
    TeamModalView()
}
