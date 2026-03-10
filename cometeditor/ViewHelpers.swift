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

    func string(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

// MARK: - Full Screen Detection
final class WindowStateObserver: ObservableObject {
    @Published var isFullScreen: Bool = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.isFullScreen = true } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.isFullScreen = false } }
            .store(in: &cancellables)
    }
}

// MARK: - Detail Top Safe Area Helper
// Ignores safe area on top only when sidebar is visible (not detailOnly, not fullscreen).
extension View {
    func detailIgnoresSafeArea(columnVisibility: NavigationSplitViewVisibility, isFullScreen: Bool) -> some View {
        ignoresSafeArea(edges: (columnVisibility == .detailOnly || isFullScreen) ? [] : .top)
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
// Single inspectorSection — always resolves through LanguageManager for runtime i18n
func inspectorSection<Content: View>(
    _ titleKey: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(LanguageManager.shared.string(titleKey))
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

// MARK: - Scroll Wheel (trackpad pan / zoom)
extension View {
    /// Intercepts NSScrollWheel events via an NSView overlay.
    func onScrollWheel(_ handler: @escaping (NSEvent) -> Void) -> some View {
        overlay(ScrollWheelView(handler: handler))
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let handler: (NSEvent) -> Void

    func makeNSView(context: Context) -> _ScrollWheelNSView {
        let v = _ScrollWheelNSView()
        v.handler = handler
        return v
    }
    func updateNSView(_ nsView: _ScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

final class _ScrollWheelNSView: NSView {
    var handler: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        handler?(event)
    }
    override func magnify(with event: NSEvent) {
        handler?(event)
    }
    // Mouse click/drag event'lerini üst view'a geçir — SwiftUI gesture'larını bloklamaz.
    // hitTest nil YAPILMAMALI: nil yapılırsa scroll event'ler de bu view'a ulaşmaz.
    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        nextResponder?.mouseUp(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        nextResponder?.mouseDragged(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }
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
