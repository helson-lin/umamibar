import AppKit

/// Shared painted design system used by the popover and the settings window.
enum Ink {
    static var dark: Bool {
        if #available(macOS 11.0, *) { return NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
        return NSAppearance.current.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    static var text: NSColor { dark ? .init(white: 0.98, alpha: 1) : .init(white: 0.13, alpha: 1) }
    static var secondary: NSColor { .init(white: dark ? 0.62 : 0.48, alpha: 1) }
    static var line: NSColor { .init(white: dark ? 1 : 0, alpha: 0.08) }
    static var green: NSColor { .init(srgbRed: dark ? 0.035294 : 0.027451, green: dark ? 0.588235 : 0.517647, blue: dark ? 0.411765 : 0.360784, alpha: 1) }
}
func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func text(_ value: String, _ rect: NSRect, size: CGFloat = 11, color: NSColor? = nil, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color ?? Ink.text, .paragraphStyle: style])
}
/// Glass surface shared by the popover and the settings window; radius 0 fills a window edge to edge.
func drawSurface(_ bounds: NSRect, radius: CGFloat) {
    let opacity: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.95
    let base = NSGradient(starting: NSColor(white: Ink.dark ? 0.137 : 1, alpha: opacity), ending: NSColor(white: Ink.dark ? 0.118 : 0.955, alpha: opacity))
    base?.draw(in: NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius), angle: 55)
    let sheen = NSGradient(starting: NSColor(white: 1, alpha: Ink.dark ? 0.035 : 0.28), ending: NSColor(white: 1, alpha: 0))
    sheen?.draw(in: NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius), angle: 45)
    guard radius > 0 else { return }
    NSColor(white: Ink.dark ? 0.5 : 1, alpha: Ink.dark ? 0.25 : 0.95).setStroke(); NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: radius, yRadius: radius).stroke()
    NSColor(white: 1, alpha: Ink.dark ? 0.045 : 0.4).setStroke()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 1.7, dy: 1.7), xRadius: radius - 1, yRadius: radius - 1).stroke()
}
/// Motion tokens. Entrances use a strong ease-out: cubic-bezier(0.23, 1, 0.32, 1).
enum Motion {
    static var easeOutTiming: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }
    /// System "Reduce motion": keep opacity feedback, drop movement.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// The ease-out curve evaluated at linear progress x in 0...1, for timer-driven drawing.
    static func easeOutProgress(_ x: Double) -> Double { bezier(x, 0.23, 1, 0.32, 1) }
    /// CSS cubic-bezier timing function: solves for t at time x by bisection, returns the eased value.
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }; if x >= 1 { return 1 }
        func coord(_ t: Double, _ p1: Double, _ p2: Double) -> Double { let u = 1 - t; return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<30 { let value = coord(t, x1, x2); if abs(value - x) < 1e-5 { break }; if value < x { lo = t } else { hi = t }; t = (lo + hi) / 2 }
        return coord(t, y1, y2)
    }
}
/// Chart colors a site can use; each bar is a vertical gradient from `top` to `base`.
/// Orange comes first so a single site keeps the brand color.
enum Palette {
    struct Swatch { let name: String; let top: NSColor; let base: NSColor }
    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    static let swatches = [
        Swatch(name: "橙", top: rgb(0xFFAD78), base: rgb(0xE67B32)), Swatch(name: "绿", top: rgb(0x7ED9A8), base: rgb(0x1E9E68)),
        Swatch(name: "蓝", top: rgb(0x8DB8FF), base: rgb(0x3B7DE8)), Swatch(name: "紫", top: rgb(0xC2A6FF), base: rgb(0x8B5CF6)),
        Swatch(name: "粉", top: rgb(0xFFA3CC), base: rgb(0xE0528F)), Swatch(name: "青", top: rgb(0x7FE0D6), base: rgb(0x14A39A)),
        Swatch(name: "金", top: rgb(0xFFD873), base: rgb(0xD99A0B)), Swatch(name: "红", top: rgb(0xFF9B8F), base: rgb(0xDE4B3E))]
    static func swatch(_ index: Int) -> Swatch { swatches[(index % swatches.count + swatches.count) % swatches.count] }
    /// A filled dot for menus and legends.
    static func dot(_ index: Int, diameter: CGFloat = 12) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            swatch(index).base.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill(); return true
        }
    }
}
/// Shared date formatters: building a DateFormatter on every draw() is expensive.
enum Formats {
    static let range = make("MM/dd HH:mm"), hour = make("HH:mm"), day = make("MM/dd"), time = make("HH:mm:ss")
    static func axis(_ period: Period) -> DateFormatter { period == .day ? hour : day }
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter(); formatter.dateFormat = format; formatter.timeZone = .autoupdatingCurrent; return formatter
    }
}
class FlippedView: NSView { override var isFlipped: Bool { true }; override var allowsVibrancy: Bool { false } }
final class PaintedButton: NSButton {
    enum Style { case plain, primary, segment, icon, secondary, destructive, navigation }
    var style: Style = .plain
    var selected = false
    var callback: (() -> Void)?
    private var hovering = false
    private var area: NSTrackingArea?
    init(_ title: String, frame: NSRect, style: Style = .plain, action: @escaping () -> Void) {
        super.init(frame: frame); self.title = title; self.style = style; callback = action
        isBordered = false; target = self; self.action = #selector(invoke); setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    @objc private func invoke() { callback?() }
    override var isFlipped: Bool { true }
    override var allowsVibrancy: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area = area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(next); area = next
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if style == .primary {
            fill(bounds.insetBy(dx: 0.5, dy: 0.5), Ink.green.withAlphaComponent(isEnabled ? 1 : 0.5), radius: 7)
            NSColor(white: 1, alpha: 0.20).setStroke(); shape.stroke()
            let top = NSBezierPath(); top.move(to: NSPoint(x: 8, y: 1.5)); top.line(to: NSPoint(x: bounds.width-8, y: 1.5)); top.stroke()
        } else if selected {
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(Ink.dark ? 0.25 : 0.12); shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1)
            NSGraphicsContext.saveGraphicsState(); shadow.set()
            fill(bounds.insetBy(dx: 1, dy: 1), NSColor(white: Ink.dark ? 0.23 : 1, alpha: 1), radius: 6); NSGraphicsContext.restoreGraphicsState()
            let gradient = NSGradient(starting: NSColor(white: Ink.dark ? 0.255 : 1, alpha: 1), ending: NSColor(white: Ink.dark ? 0.205 : 1, alpha: 1)); gradient?.draw(in: shape, angle: 90)
            NSColor(white: 1, alpha: Ink.dark ? 0.13 : 0.85).setStroke(); shape.stroke()
        } else if style == .navigation {
            let base = NSColor(white: Ink.dark ? 1 : 0, alpha: isHighlighted ? 0.10 : hovering ? 0.075 : 0.04)
            fill(bounds.insetBy(dx: 0.5, dy: 0.5), base, radius: 7)
            NSColor(white: Ink.dark ? 1 : 0, alpha: hovering ? 0.15 : 0.09).setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        } else if style == .secondary || style == .destructive {
            if hovering || isHighlighted {
                let base: NSColor = style == .destructive ? .systemRed : (Ink.dark ? .white : .black)
                fill(bounds.insetBy(dx: 0.5, dy: 0.5), base.withAlphaComponent(isHighlighted ? 0.12 : 0.065), radius: 8)
                base.withAlphaComponent(0.07).setStroke()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            }
        } else if hovering || isHighlighted {
            fill(bounds.insetBy(dx: 1, dy: 1), NSColor(white: Ink.dark ? 1 : 0, alpha: isHighlighted ? 0.09 : 0.045), radius: 6)
        }
        // Do not let the popover's vibrancy blend white selected tabs into gray.
        if selected && !Ink.dark { fill(bounds.insetBy(dx: 1, dy: 1), NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), radius: 6) }
        let color = (style == .primary ? NSColor.white : style == .destructive && hovering ? NSColor.systemRed : selected || (style == .secondary && hovering) ? Ink.text : Ink.secondary).withAlphaComponent(isEnabled ? 1 : 0.4)
        if style == .navigation && title == "‹" {
            color.setStroke()
            let arrow = NSBezierPath(); arrow.lineWidth = 1.6; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            arrow.move(to: NSPoint(x: center.x + 2.5, y: center.y - 5))
            arrow.line(to: NSPoint(x: center.x - 2.5, y: center.y))
            arrow.line(to: NSPoint(x: center.x + 2.5, y: center.y + 5))
            arrow.stroke()
        }
        else if style == .icon { drawIcon(title, in: bounds, color: color) }
        else { text(title, NSRect(x: 4, y: (bounds.height - (style == .navigation ? 23 : 15)) / 2, width: bounds.width - 8, height: style == .navigation ? 26 : 17), size: style == .navigation ? (title == "‹" ? 23 : 17) : style == .primary ? 12 : 11, color: color, weight: selected || style == .primary ? .medium : .regular, alignment: .center) }
    }
    private func drawIcon(_ kind: String, in rect: NSRect, color: NSColor) {
        color.setStroke(); let p = NSBezierPath(); p.lineWidth = 1.35; p.lineCapStyle = .round; p.lineJoinStyle = .round
        let center = NSPoint(x: rect.midX, y: rect.midY)
        if kind == "刷新数据" {
            p.appendArc(withCenter: center, radius: 5.4, startAngle: 25, endAngle: 325, clockwise: false)
            p.move(to: NSPoint(x: center.x + 7, y: center.y - 6)); p.line(to: NSPoint(x: center.x + 7, y: center.y)); p.line(to: NSPoint(x: center.x + 1, y: center.y))
        } else {
            for i in 0..<24 { let angle = CGFloat(i) * .pi / 12; let radius: CGFloat = i % 3 == 1 ? 5.5 : 6.8
                let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if i == 0 { p.move(to: point) } else { p.line(to: point) }
            }; p.close(); p.appendOval(in: NSRect(x: center.x - 2.7, y: center.y - 2.7, width: 5.4, height: 5.4))
        }; p.stroke()
    }
}
// Keep native secure editing inside a surface matching the reference inputs.
final class GlassInput: FlippedView, NSTextFieldDelegate {
    private let field: NSTextField
    private var focused = false
    init(field: NSTextField, frame: NSRect) {
        self.field = field; super.init(frame: frame)
        field.frame = NSRect(x: 11, y: 10, width: frame.width - 22, height: 19)
        field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 12); field.textColor = .labelColor
        field.delegate = self; addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    var onChange: (() -> Void)?
    func controlTextDidChange(_ notification: Notification) { onChange?() }
    func controlTextDidBeginEditing(_ notification: Notification) { focused = true; needsDisplay = true }
    func controlTextDidEndEditing(_ notification: Notification) { focused = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        fill(rect, NSColor(white: Ink.dark ? 0.065 : 1, alpha: Ink.dark ? 0.65 : 0.7), radius: 7)
        (focused ? Ink.green : NSColor(white: Ink.dark ? 0.27 : 0.82, alpha: 1)).setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7); path.lineWidth = 1; path.stroke()
        if focused { Ink.green.withAlphaComponent(0.12).setStroke(); let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6); ring.lineWidth = 2; ring.stroke() }
    }
}
final class WebsiteChoice: NSButton {
    let website: Website
    init(_ website: Website, frame: NSRect, target: AnyObject, action: Selector) {
        self.website = website; super.init(frame: frame)
        setButtonType(.switch); isBordered = false; self.target = target; self.action = action
        identifier = NSUserInterfaceItemIdentifier(website.id)
        setAccessibilityLabel(website.name + " · " + website.domain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0.5, y: 17, width: 13, height: 13)
        fill(box, state == .on ? Ink.green : NSColor(white: 0.5, alpha: 0.06), radius: 3)
        if state == .on { NSColor.white.setStroke(); let check = NSBezierPath(); check.lineWidth = 1.5; check.lineCapStyle = .round; check.move(to: NSPoint(x: 3, y: 23)); check.line(to: NSPoint(x: 6, y: 26)); check.line(to: NSPoint(x: 11, y: 20)); check.stroke() }
        else { Ink.secondary.withAlphaComponent(0.4).setStroke(); NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).stroke() }
        // Leave room on the right for the color dot of a selected site.
        text(website.name, NSRect(x: 24, y: 10, width: bounds.width-64, height: 17), size: 12)
        text(website.domain, NSRect(x: 24, y: 29, width: bounds.width-64, height: 15), size: 10, color: Ink.secondary)
        fill(NSRect(x: 0, y: bounds.height-0.5, width: bounds.width, height: 0.5), Ink.line)
    }
}
/// Chart color dot on a selected website row; clicking it opens a menu of palette colors.
final class ColorSwatch: NSButton {
    var color: Int { didSet { needsDisplay = true; setAccessibilityValue(Palette.swatch(color).name) } }
    var onPick: ((Int) -> Void)?
    private var hovering = false
    private var area: NSTrackingArea?
    init(color: Int, frame: NSRect) {
        self.color = color; super.init(frame: frame)
        isBordered = false; title = ""; target = self; action = #selector(openMenu)
        toolTip = "图表颜色"; setAccessibilityLabel("图表颜色"); setAccessibilityValue(Palette.swatch(color).name)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override var isFlipped: Bool { true }
    override var allowsVibrancy: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area = area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(next); area = next
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    @objc private func openMenu() {
        let menu = NSMenu()
        for (index, swatch) in Palette.swatches.enumerated() {
            let item = NSMenuItem(title: swatch.name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; item.image = Palette.dot(index); item.state = index == color ? .on : .off
            menu.addItem(item)
        }
        // Open with the current color under the pointer, like a native pop-up button.
        menu.popUp(positioning: menu.item(withTag: color), at: NSPoint(x: 0, y: bounds.height), in: self)
    }
    @objc private func pick(_ item: NSMenuItem) { color = item.tag; onPick?(item.tag) }
    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted { fill(bounds.insetBy(dx: 1, dy: 1), NSColor(white: Ink.dark ? 1 : 0, alpha: isHighlighted ? 0.09 : 0.05), radius: bounds.height / 2) }
        let dot = NSRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14)
        let swatch = Palette.swatch(color)
        NSGradient(starting: swatch.top, ending: swatch.base)?.draw(in: NSBezierPath(ovalIn: dot), angle: 90)
        NSColor(white: Ink.dark ? 1 : 0, alpha: 0.12).setStroke(); NSBezierPath(ovalIn: dot.insetBy(dx: 0.25, dy: 0.25)).stroke()
    }
}

