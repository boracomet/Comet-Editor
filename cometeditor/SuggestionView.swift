import SwiftUI

struct SuggestionView: View {
    @State private var titleText: String = ""
    @State private var messageText: String = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var showValidation = false
    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool

    @State private var showMathChallenge = false
    @State private var mathA = 0
    @State private var mathB = 0
    @State private var mathAnswer = ""
    @State private var mathWrong = false

    @Environment(\.colorScheme) private var colorScheme

    private static let rateLimitKey = "suggestion_submit_timestamps"
    private static let rateWindow: TimeInterval = 3600
    private static let rateLimit = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                heroSection
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                // Form card
                formCard
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
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
        .alert(LocalizedStringKey("suggestion.captcha.title"), isPresented: $showMathChallenge) {
            TextField(LocalizedStringKey("suggestion.captcha.placeholder"), text: $mathAnswer)
            Button(LocalizedStringKey("suggestion.captcha.confirm")) {
                if Int(mathAnswer) == mathA + mathB {
                    mathAnswer = ""
                    mathWrong = false
                    Task { await sendSuggestion(skipRateCheck: true) }
                } else {
                    mathAnswer = ""
                    mathWrong = true
                    showMathChallenge = true
                }
            }
            Button(LocalizedStringKey("suggestion.captcha.cancel"), role: .cancel) {
                mathAnswer = ""
                mathWrong = false
            }
        } message: {
            if mathWrong {
                Text(LocalizedStringKey("suggestion.captcha.wrong"))
            } else {
                Text(String(format: NSLocalizedString("suggestion.captcha.body", comment: ""), mathA, mathB))
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey("suggestion.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.primary)
                Text(LocalizedStringKey("suggestion.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Title field
            fieldGroup(label: LocalizedStringKey("suggestion.label.title")) {
                ZStack(alignment: .leading) {
                    if titleText.isEmpty {
                        Text(LocalizedStringKey("suggestion.placeholder.title"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary.opacity(0.45))
                            .padding(.leading, 2)
                    }
                    TextField("", text: $titleText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($titleFocused)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(fieldBackground(focused: titleFocused))
                .overlay(fieldBorder(focused: titleFocused))
                .animation(.easeInOut(duration: 0.15), value: titleFocused)
            }

            // Body field
            fieldGroup(label: LocalizedStringKey("suggestion.label.description")) {
                VStack(alignment: .trailing, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        if messageText.isEmpty {
                            Text(LocalizedStringKey("suggestion.placeholder.body"))
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                                .padding(.top, 11)
                                .padding(.leading, 15)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $messageText)
                            .font(.system(size: 13))
                            .focused($bodyFocused)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: 140)
                            .onChange(of: messageText) { v in
                                if v.count > 2000 { messageText = String(v.prefix(2000)) }
                            }
                    }
                    .background(fieldBackground(focused: bodyFocused))
                    .overlay(fieldBorder(focused: bodyFocused))
                    .animation(.easeInOut(duration: 0.15), value: bodyFocused)

                    Text("\(messageText.count) / 2000")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(messageText.count > 1800 ? .orange : Color.secondary.opacity(0.35))
                }
            }

            // Send button
            sendButton
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Field helpers

    @ViewBuilder
    private func fieldGroup<Content: View>(label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
            content()
        }
    }

    private func fieldBackground(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(focused ? 0.055 : 0.035))
    }

    private func fieldBorder(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                focused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                lineWidth: focused ? 1.5 : 1
            )
    }

    // MARK: - Send Button

    private var sendButton: some View {
        let canSend = !titleText.trimmingCharacters(in: .whitespaces).isEmpty &&
                      !messageText.trimmingCharacters(in: .whitespaces).isEmpty

        return Button {
            guard canSend else { showValidation = true; return }
            if isRateLimited() {
                presentMathChallenge()
            } else {
                Task { await sendSuggestion() }
            }
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(isSending
                     ? LocalizedStringKey("suggestion.sending")
                     : LocalizedStringKey("suggestion.send"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSending || !canSend
                          ? Color.accentColor.opacity(0.45)
                          : Color.accentColor)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .scaleEffect(isSending ? 0.985 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSending)
    }

    // MARK: - Rate Limit

    private func isRateLimited() -> Bool {
        let now = Date().timeIntervalSince1970
        let stored = UserDefaults.standard.array(forKey: Self.rateLimitKey) as? [Double] ?? []
        return stored.filter { now - $0 < Self.rateWindow }.count >= Self.rateLimit
    }

    private func recordSubmit() {
        let now = Date().timeIntervalSince1970
        let stored = UserDefaults.standard.array(forKey: Self.rateLimitKey) as? [Double] ?? []
        let recent = stored.filter { now - $0 < Self.rateWindow }
        UserDefaults.standard.set(recent + [now], forKey: Self.rateLimitKey)
    }

    private func presentMathChallenge() {
        mathA = Int.random(in: 1...20)
        mathB = Int.random(in: 1...20)
        mathAnswer = ""
        mathWrong = false
        showMathChallenge = true
    }

    // MARK: - Network

    private func sendSuggestion(skipRateCheck: Bool = false) async {
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
            "category":    "bug",
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
            let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode >= 200 && statusCode < 300 {
                recordSubmit()
                titleText = ""
                messageText = ""
                showSuccess = true
            } else {
                showError = true
            }
        } catch {
            showError = true
        }
    }
}
