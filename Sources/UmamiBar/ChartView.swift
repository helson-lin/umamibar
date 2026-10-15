import AppKit

final class ChartView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); onClick?() }
    var colorIndex = 0
    var showsScale = true
    var points: [Point] = [] { didSet { rebuildTracking(); needsDisplay = true } }
    private var hovered: Int?
    override var acceptsFirstResponder: Bool { true }
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 90) }
    override func draw(_ dirtyRect: NSRect) {
        let maxValue = max(2, points.map(\.y).max() ?? 1)
        let chart = NSRect(x: showsScale ? 20 : 0, y: 3, width: bounds.width - (showsScale ? 20 : 0), height: bounds.height - 6)
        NSColor.labelColor.withAlphaComponent(showsScale ? 0.07 : 0).setStroke()
        for fraction in [0.0, 0.5, 1.0] {
            let line = NSBezierPath(); line.move(to: NSPoint(x: chart.minX, y: chart.minY + chart.height * fraction)); line.line(to: NSPoint(x: bounds.width, y: chart.minY + chart.height * fraction)); line.setLineDash([2, 3], count: 2, phase: 0); line.stroke()
        }
        if showsScale {
            for (i, value) in [maxValue, maxValue / 2, 0].enumerated() {
                (String(Int(value)) as NSString).draw(at: NSPoint(x: 0, y: CGFloat(i) * chart.height / 2 - 2), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor])
            }
        }
        guard !points.isEmpty else { return }
        let step = chart.width / CGFloat(points.count)
        for (index, point) in points.enumerated() {
            if point.y == 0 {
                // A muted baseline tick marks an empty bucket, not a visit.
                NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: NSRect(x: chart.minX + CGFloat(index) * step + 1, y: chart.maxY - 0.75, width: max(1, step - 5), height: 0.75), xRadius: 0.375, yRadius: 0.375).fill()
                continue
            }
            let height = max(2, CGFloat(point.y / maxValue) * chart.height)
            let colors: [(NSColor, NSColor)] = [
                (.init(srgbRed: 1, green: 173/255, blue: 120/255, alpha: 1), .init(srgbRed: 230/255, green: 123/255, blue: 50/255, alpha: 1)),
                (.init(srgbRed: 1, green: 223/255, blue: 197/255, alpha: 1), .init(srgbRed: 1, green: 173/255, blue: 120/255, alpha: 1)),
                (.init(srgbRed: 230/255, green: 123/255, blue: 50/255, alpha: 1), .init(srgbRed: 172/255, green: 90/255, blue: 35/255, alpha: 1))]
            let color = colors[min(colorIndex, 2)]
            let rect = NSRect(x: chart.minX + CGFloat(index) * step + 1, y: chart.maxY - height, width: max(1, step - 5), height: height)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
            NSGradient(starting: hovered == index ? .init(srgbRed: 1, green: 223/255, blue: 197/255, alpha: 1) : color.0, ending: color.1)?.draw(in: shape, angle: 90)
        }
        if let index = hovered, points.indices.contains(index) {
            let value = "\(points[index].x) · \(Int(points[index].y)) 次会话"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor]
            let width = min(bounds.width - 4, (value as NSString).size(withAttributes: attributes).width + 16)
            let x = min(bounds.width - width - 2, max(2, chart.minX + CGFloat(index) * step - width/2))
            let bubble = NSRect(x: x, y: 2, width: width, height: 23)
            NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: bubble, xRadius: 5, yRadius: 5).fill()
            NSColor.separatorColor.setStroke(); NSBezierPath(roundedRect: bubble, xRadius: 5, yRadius: 5).stroke()
            (value as NSString).draw(at: NSPoint(x: x + 8, y: 7), withAttributes: attributes)

        }
    }
    override func updateTrackingAreas() { super.updateTrackingAreas(); rebuildTracking() }
    private func rebuildTracking() {
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        guard !points.isEmpty, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x - (showsScale ? 20 : 0)
        let index = min(points.count - 1, max(0, Int(x / max(1, bounds.width - (showsScale ? 20 : 0)) * CGFloat(points.count))))
        hovered = index; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        // Return/Space open the card; without a handler (detail chart) let the key reach the responder chain.
        if event.keyCode == 36 || event.keyCode == 49, let onClick = onClick { onClick(); return }
        guard !points.isEmpty else { super.keyDown(with: event); return }
        if event.keyCode == 123 || event.keyCode == 124 {
            hovered = min(points.count - 1, max(0, (hovered ?? 0) + (event.keyCode == 124 ? 1 : -1)))
            needsDisplay = true
        } else { super.keyDown(with: event) }
    }
}
