import SwiftUI

// MARK: - Category Model

private enum SuggestionCategory: String, CaseIterable {
    case bug         = "bug"
    case feature     = "feature"
    case ui          = "ui"
    case performance = "performance"
    case other       = "other"

    var localizedKey: LocalizedStringKey {
        switch self {
        case .bug:         return "suggestion.category.bug"
        case .feature:     return "suggestion.category.feature"
        case .ui:          return "suggestion.category.ui"
        case .performance: return "suggestion.category.performance"
        case .other:       return "suggestion.category.other"
        }
    }

    var icon: String {
        switch self {
        case .bug:         return "ladybug.fill"
        case .feature:     return "star.fill"
        case .ui:          return "paintbrush.fill"
        case .performance: return "bolt.fill"
        case .other:       return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .bug:         return .red
        case .feature:     return .blue
        case .ui:          return .purple
        case .performance: return .orange
        case .other:       return .gray
        }
    }
}

// MARK: - Main View

struct SuggestionView: View {
    @State private var titleText: String = ""
    @State private var messageText: String = ""
    @State private var selectedCategory: SuggestionCategory = .feature
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var showValidation = false
    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: - Hero Header
                headerSection

                Divider()
                    .padding(.horizontal, 32)

                // MARK: - Form
                VStack(alignment: .leading, spacing: 22) {

                    // Category
                    categorySection

                    // Title
                    titleSection

                    // Body
                    bodySection

                    // Send
                    sendButton
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .padding(.leading, 0)
        }
        .alert(LocalizedStringKey("suggestion.sent.title"), isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("suggestion.sent.message"))
        }
        .alert(LocalizedStringKey("suggestion.error"), isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
        .alert(LocalizedStringKey("suggestion.validation.title"), isPresented: $showValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("suggestion.validation.body"))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey("suggestion.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Text(LocalizedStringKey("suggestion.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }

        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey("suggestion.label.category"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)

            HStack(spacing: 6) {
                ForEach(SuggestionCategory.allCases, id: \.self) { cat in
                    CategoryChip(
                        category: cat,
                        isSelected: selectedCategory == cat
                    ) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                            selectedCategory = cat
                        }
                    }
                }
            }
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("suggestion.label.title"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)

            ZStack(alignment: .leading) {
                if titleText.isEmpty {
                    Text(LocalizedStringKey("suggestion.placeholder.title"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .padding(.leading, 2)
                }
                TextField("", text: $titleText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($titleFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(titleFocused ? 0.055 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        titleFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.07),
                        lineWidth: titleFocused ? 1.5 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: titleFocused)
        }
    }

    // MARK: - Body Section

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("suggestion.label.description"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)

            ZStack(alignment: .topLeading) {
                if messageText.isEmpty {
                    Text(LocalizedStringKey("suggestion.placeholder.body"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .padding(.top, 10)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $messageText)
                    .font(.system(size: 13))
                    .focused($bodyFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 120)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(bodyFocused ? 0.055 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        bodyFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.07),
                        lineWidth: bodyFocused ? 1.5 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: bodyFocused)

            HStack {
                Spacer()
                Text("\(messageText.count) / 2000")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(messageText.count > 1800 ? .orange : Color.secondary.opacity(0.35))
            }
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        let canSend = !titleText.trimmingCharacters(in: .whitespaces).isEmpty &&
                      !messageText.trimmingCharacters(in: .whitespaces).isEmpty

        return Button {
            guard canSend else { showValidation = true; return }
            Task { await sendSuggestion() }
        } label: {
            HStack(spacing: 7) {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                Text(isSending
                     ? LocalizedStringKey("suggestion.sending")
                     : LocalizedStringKey("suggestion.send"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSending || !canSend
                            ? Color.accentColor.opacity(0.45)
                            : Color.accentColor
                    )
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .scaleEffect(isSending ? 0.985 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSending)
    }

    // MARK: - Network

    private func sendSuggestion() async {
        isSending = true
        defer { isSending = false }

        let osVersion: String = {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        }()
        let deviceModel: String = {
            var size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            return String(cString: model)
        }()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        let sessionId = UserDefaults.standard.string(forKey: "comet_analytics_session_id") ?? UUID().uuidString
        let sdk = CometAnalytics.shared

        let payload: [String: Any] = [
            "sessionId":   sessionId,
            "title":       titleText.trimmingCharacters(in: .whitespaces),
            "body":        messageText.trimmingCharacters(in: .whitespaces),
            "category":    selectedCategory.rawValue,
            "appVersion":  appVersion,
            "osVersion":   osVersion,
            "deviceModel": deviceModel,
        ]

        guard let base = sdk.baseURL,
              let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            showError = true
            return
        }

        var req = URLRequest(url: base.appendingPathComponent("/api/sdk/suggestion"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sdk.apiKey, forHTTPHeaderField: "X-App-Key")
        req.httpBody = httpBody
        req.timeoutInterval = 15

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode == 200 {
                titleText = ""
                messageText = ""
                selectedCategory = .feature
                showSuccess = true
            } else {
                showError = true
            }
        } catch {
            showError = true
        }
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let category: SuggestionCategory
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(category.localizedKey)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected
                          ? category.color.opacity(0.15)
                          : Color.primary.opacity(isHovered ? 0.07 : 0.04))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? category.color.opacity(0.45) : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .foregroundStyle(isSelected ? category.color : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
