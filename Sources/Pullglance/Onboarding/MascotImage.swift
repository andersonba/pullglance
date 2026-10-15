import AppKit
import SwiftUI

/// One of the flea's poses from the resource bundle. Loaded by URL: `Image(_:bundle:)` does not find
/// SwiftPM-processed PNGs. Cached per pose; the files are large.
struct MascotImage: View {
    let pose: MascotPose
    let size: CGFloat

    init(_ pose: MascotPose, size: CGFloat) {
        self.pose = pose
        self.size = size
    }

    private static let cache = NSCache<NSString, NSImage>()

    private static func image(for pose: MascotPose) -> NSImage? {
        if let cached = cache.object(forKey: pose.rawValue as NSString) { return cached }
        guard let url = Bundle.app.url(forResource: pose.rawValue, withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: pose.rawValue as NSString)
        return image
    }

    var body: some View {
        if let image = Self.image(for: pose) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        } else {
            Image(systemName: "ant").font(.system(size: size * 0.6)).frame(width: size, height: size)
        }
    }
}
