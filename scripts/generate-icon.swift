import AppKit

// Deterministic master artwork: the existing three-bar mark in warm glass.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 186, yRadius: 186)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = 36; shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.set()
NSColor(white: 0.12, alpha: 1).setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(srgbRed: 0.18, green: 0.19, blue: 0.19, alpha: 1), ending: NSColor(srgbRed: 0.08, green: 0.085, blue: 0.09, alpha: 1))!.draw(in: tile, angle: -65)
NSColor(white: 1, alpha: 0.22).setStroke(); tile.lineWidth = 3; tile.stroke()
let inner = NSBezierPath(roundedRect: NSRect(x: 101, y: 101, width: 822, height: 822), xRadius: 182, yRadius: 182)
NSColor(white: 1, alpha: 0.035).setStroke(); inner.lineWidth = 2; inner.stroke()
let bars: [(CGFloat, CGFloat)] = [(288, 244), (456, 432), (624, 332)]
for (index, bar) in bars.enumerated() {
    let shape = NSBezierPath(roundedRect: NSRect(x: bar.0, y: 296, width: 112, height: bar.1), xRadius: 48, yRadius: 48)
    NSGraphicsContext.saveGraphicsState()
    let lift = NSShadow(); lift.shadowColor = NSColor.black.withAlphaComponent(0.30); lift.shadowBlurRadius = 15; lift.shadowOffset = NSSize(width: 0, height: -9); lift.set()
    NSColor.black.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
    let top = index == 1 ? NSColor(srgbRed: 1, green: 0.88, blue: 0.77, alpha: 1) : NSColor(srgbRed: 1, green: 0.72, blue: 0.51, alpha: 1)
    let bottom = NSColor(srgbRed: 0.90, green: 0.46, blue: 0.20, alpha: 1)
    NSGradient(starting: bottom, ending: top)!.draw(in: shape, angle: 90)
    NSColor(white: 1, alpha: 0.15).setStroke(); shape.lineWidth = 1.5; shape.stroke()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/AppIcon-1024.png"))
