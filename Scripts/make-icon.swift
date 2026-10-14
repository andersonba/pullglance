// Renders the app icon from the mascot PNG into an .iconset folder, on Apple's macOS icon grid: a rounded
// square of 824/1024 of the canvas, radius 22.5 %, with the mascot centred over a soft shadow.
// Run with: swift Scripts/make-icon.swift <mascot.png> <out.iconset>
import AppKit

let mascotPath = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
guard let mascot = NSImage(contentsOfFile: mascotPath) else { fatalError("no mascot at \(mascotPath)") }

let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in sizes {
    let px = points * scale
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size, flipped: false) { rect in
        let side = rect.width * 824 / 1024
        let tile = NSRect(x: (rect.width - side) / 2, y: (rect.height - side) / 2, width: side, height: side)
        let path = NSBezierPath(roundedRect: tile, xRadius: side * 0.225, yRadius: side * 0.225)
        // Graphite, a touch lighter at the top so it reads on a dark Dock too.
        NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.23, alpha: 1), NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)])?
            .draw(in: path, angle: -90)
        // A soft shadow under the mascot, so it sits rather than floats.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: NSRect(x: tile.midX - side * 0.26, y: tile.minY + side * 0.13, width: side * 0.52, height: side * 0.07)).fill()
        NSGraphicsContext.restoreGraphicsState()
        // The mascot, 70 % of the tile, centred a hair above the middle to leave room for the shadow.
        let m = mascot.size
        let targetWidth = side * 0.70
        let s = targetWidth / max(m.width, m.height)
        let drawSize = NSSize(width: m.width * s, height: m.height * s)
        let origin = NSPoint(x: tile.midX - drawSize.width / 2, y: tile.midY - drawSize.height / 2 + side * 0.03)
        NSGraphicsContext.current?.imageInterpolation = .high
        mascot.draw(in: NSRect(origin: origin, size: drawSize), from: .zero, operation: .sourceOver, fraction: 1)
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
