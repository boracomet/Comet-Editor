import SwiftUI
import AppKit

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
