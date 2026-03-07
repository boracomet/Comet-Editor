import SwiftUI

struct TeamModalView: View {
    @EnvironmentObject var appState: GlobalAppState
    
    // Team Members Data
    let teamMembers = [
        TeamMember(initials: "BAT", name: "Bora Ata Türkoğlu", role: "Founder & Lead Developer", linkedin: "https://www.linkedin.com/in/boracomet/?skipRedirect=true", github: "https://github.com/boracomet", website: "https://boraturkoglu.com", imageName: "bora_profile"),
        TeamMember(initials: "MA", name: "Mehmet Atademir", role: "DevOps Engineer", linkedin: "https://www.linkedin.com/in/mehmet-atademir-148656234/", github: nil, website: nil, imageName: "mehmet_profile"),
        TeamMember(initials: "YK", name: "Yılmaz Kavakçıoğlu", role: "Advertising Management", linkedin: "https://www.linkedin.com/in/yilmazkavakcioglu/", github: nil, website: nil, imageName: "yilmaz_profile"),
        TeamMember(initials: "BNK", name: "Beyza Nur Keçeli", role: "Visual Designer", linkedin: "https://www.linkedin.com/in/beyzanurkeceli/", github: nil, website: nil, imageName: "beyza_profile")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.showingTeamModal = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(8)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    DispatchQueue.main.async {
                        if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
            .padding(16)
            
            // Title Area
            VStack(spacing: 12) {
                Text(LocalizedStringKey("menu.team.title"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.primary)
                
                Text(LocalizedStringKey("menu.team.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.bottom, 60)
            
            // Team Grid
            HStack(alignment: .top, spacing: 40) {
                ForEach(teamMembers, id: \.initials) { member in
                    VStack(spacing: 16) {
                        // Profile Image
                        Image(member.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        
                        VStack(spacing: 8) {
                            Text(member.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            
                            Text(member.role)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .multilineTextAlignment(.center)
                            
                            HStack(spacing: 12) {
                                Link(destination: URL(string: member.linkedin)!) {
                                    Image("linkedin")
                                        .resizable()
                                        .renderingMode(.template)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 16, height: 16)
                                        .foregroundStyle(Color.secondary)
                                        .onHover { isHovered in
                                            DispatchQueue.main.async {
                                                if isHovered {
                                                    NSCursor.pointingHand.push()
                                                } else {
                                                    NSCursor.pop()
                                                }
                                            }
                                        }
                                }
                                
                                if let github = member.github, let url = URL(string: github) {
                                    Link(destination: url) {
                                        Image("github")
                                            .resizable()
                                            .renderingMode(.template)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 16, height: 16)
                                            .foregroundStyle(Color.secondary)
                                            .onHover { isHovered in
                                                DispatchQueue.main.async {
                                                    if isHovered {
                                                        NSCursor.pointingHand.push()
                                                    } else {
                                                        NSCursor.pop()
                                                    }
                                                }
                                            }
                                    }
                                }

                                if let website = member.website, let url = URL(string: website) {
                                    Link(destination: url) {
                                        Image(systemName: "safari")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 16, height: 16)
                                            .foregroundStyle(Color.secondary)
                                            .onHover { isHovered in
                                                DispatchQueue.main.async {
                                                    if isHovered {
                                                        NSCursor.pointingHand.push()
                                                    } else {
                                                        NSCursor.pop()
                                                    }
                                                }
                                            }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .frame(minWidth: 800)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TeamMember {
    let initials: String
    let name: String
    let role: String
    let linkedin: String
    let github: String?
    let website: String?
    let imageName: String
}

#Preview {
    TeamModalView()
}
