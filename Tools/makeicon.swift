// Renders Resources/Eyesaver.icns from the 👀 emoji on a dark rounded square.
// Run by build.sh whenever the icon is missing.
import AppKit
import Foundation

let emoji = "👀"
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/Eyesaver.iconset"

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS-style inset: the artwork does not fill the whole canvas.
    let inset = size * 0.06
    let square = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = square.width * 0.2237
    let shape = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1),
                             ending: NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1C / 255, alpha: 1))!
    gradient.draw(in: shape, angle: -90)

    NSColor.white.withAlphaComponent(0.10).setStroke()
    shape.lineWidth = max(1, size * 0.004)
    shape.stroke()

    let font = NSFont.systemFont(ofSize: square.width * 0.58)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let text = NSAttributedString(string: emoji, attributes: attrs)
    let measured = text.size()
    text.draw(at: NSPoint(x: square.midX - measured.width / 2, y: square.midY - measured.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (base, suffixes) in [(16, ["16x16"]), (32, ["16x16@2x", "32x32"]), (64, ["32x32@2x"]),
                         (128, ["128x128"]), (256, ["128x128@2x", "256x256"]),
                         (512, ["256x256@2x", "512x512"]), (1024, ["512x512@2x"])] {
    let rep = render(CGFloat(base))
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    for s in suffixes {
        try? png.write(to: URL(fileURLWithPath: "\(output)/icon_\(s).png"))
    }
}
print("iconset → \(output)")
