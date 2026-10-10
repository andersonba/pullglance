// Renders the app icon from an SF Symbol into an .iconset folder. Run with: swift Scripts/make-icon.swift <out.iconset>
import AppKit

let outDir = CommandLine.arguments[1]
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in sizes {
    let px = points * scale
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22).fill()
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.52, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return false }
        let s = symbol.size
        symbol.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
        return true
    }
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("no cgImage") }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = size
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    let suffix = scale == 2 ? "@2x" : ""
    try png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(points)x\(points)\(suffix).png"))
}
print("iconset written to \(outDir)")
