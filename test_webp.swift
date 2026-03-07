import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let utType = UTType.webP.identifier
print("Looking for registered encoders for: \(utType)")

let destinations = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
if destinations.contains(utType) {
    print("WebP is natively supported for EXPORT via ImageIO")
} else {
    print("WebP EXPORT is NOT natively supported via ImageIO.")
    print("Supported EXPORT types: \(destinations)")
}
