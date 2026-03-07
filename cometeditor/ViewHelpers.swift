import SwiftUI
import AppKit
import Combine

// MARK: - Language Manager
// Changes app language at runtime without resetting the view hierarchy.
// Updating `currentLanguage` triggers `.environment(\.locale, ...)` which causes
// SwiftUI to re-resolve all LocalizedStringKey bindings in place.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    @Published var currentLanguage: String

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage") {
            currentLanguage = saved
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            currentLanguage = preferred.hasPrefix("tr") ? "tr" : "en"
        }
    }

    func setLanguage(_ lang: String) {
        UserDefaults.standard.set(lang, forKey: "appLanguage")
        withAnimation(.easeInOut(duration: 0.15)) {
            currentLanguage = lang
        }
    }
}

// MARK: - Hand Cursor Hover
extension View {
    func handCursor() -> some View {
        onHover { isHovered in
            DispatchQueue.main.async {
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

// MARK: - Shared Inspector Section (ConvertImageView / VideoConvertView style)
func inspectorSection<Content: View>(
    _ titleKey: LocalizedStringKey,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(titleKey)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .textCase(.uppercase)
        content()
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
}

// MARK: - Shared Path Truncation
func truncatedPath(_ path: String) -> String {
    let components = path.components(separatedBy: "/")
    guard components.count > 3 else { return path }
    let firstPart = components[1...2].joined(separator: "/")
    let lastPart = components[(components.count - 2)...].joined(separator: "/")
    return "/" + firstPart + "/.../" + lastPart
}

// MARK: - NSColor SVG Hex
extension NSColor {
    func toSVGHex() -> String {
        guard let srgb = usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }
}
