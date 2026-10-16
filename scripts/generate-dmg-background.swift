import AppKit

// Finder uses a 640 × 400 point canvas. Render at 2× for Retina displays.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 800,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: 640, height: 400)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGradient(starting: NSColor(srgbRed: 1, green: 0.97, blue: 0.93, alpha: 1),
    ending: NSColor(srgbRed: 0.96, green: 0.93, blue: 0.89, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: 640, height: 400), angle: -90)
func label(_ text: String, y: CGFloat, size: CGFloat, color: NSColor, bold: Bool = false) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    (text as NSString).draw(in: NSRect(x: 24, y: y, width: 592, height: size * 1.6),
        withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                         .foregroundColor: color, .paragraphStyle: style])
}
let ink = NSColor(srgbRed: 0.23, green: 0.19, blue: 0.16, alpha: 1)
label("UmamiBar", y: 306, size: 30, color: ink, bold: true)
label("A little closer to your analytics.", y: 278, size: 14, color: ink.withAlphaComponent(0.65))
// Icon centers in Finder: (170, 200) and (470, 200).
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 285, y: 200)); arrow.line(to: NSPoint(x: 355, y: 200))
arrow.move(to: NSPoint(x: 343, y: 212)); arrow.line(to: NSPoint(x: 355, y: 200)); arrow.line(to: NSPoint(x: 343, y: 188))
arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(srgbRed: 0.80, green: 0.43, blue: 0.22, alpha: 1).setStroke(); arrow.stroke()
label("Drag UmamiBar to Applications", y: 64, size: 16, color: ink, bold: true)
label("拖动 UmamiBar 到「应用程序」完成安装", y: 35, size: 13, color: ink.withAlphaComponent(0.65))
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.dropFirst().first ?? "assets/dmg-background.png"
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
