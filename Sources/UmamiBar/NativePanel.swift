import AppKit

private enum Ink {
    static var dark: Bool {
        if #available(macOS 11.0, *) { return NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
        return NSAppearance.current.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    static var text: NSColor { dark ? .init(white: 0.98, alpha: 1) : .init(white: 0.13, alpha: 1) }
    static var secondary: NSColor { .init(white: dark ? 0.62 : 0.48, alpha: 1) }
    static var line: NSColor { .init(white: dark ? 1 : 0, alpha: 0.08) }
    static var green: NSColor { .init(srgbRed: dark ? 0.035294 : 0.027451, green: dark ? 0.588235 : 0.517647, blue: dark ? 0.411765 : 0.360784, alpha: 1) }
}
private func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
private func text(_ value: String, _ rect: NSRect, size: CGFloat = 11, color: NSColor? = nil, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color ?? Ink.text, .paragraphStyle: style])
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
        text(website.name, NSRect(x: 24, y: 10, width: bounds.width-30, height: 17), size: 12)
        text(website.domain, NSRect(x: 24, y: 29, width: bounds.width-30, height: 15), size: 10, color: Ink.secondary)
        fill(NSRect(x: 0, y: bounds.height-0.5, width: bounds.width, height: 0.5), Ink.line)
    }
}
struct PanelSite { let website: Website; let total: Int?; let points: [Point]?; let error: String?; var stats: Stats? = nil; var previousVisitors: Int? = nil }
struct PanelState {
    var screen: String; var server: String; var hasKey: Bool; var connecting: Bool; var loading: Bool
    var period: Period; var start: Date; var end: Date; var updated: String; var message: String
    var sites: [PanelSite]; var available: [Website]; var selected: [String]
    var detailID: String? = nil; var breakdown = "pages"; var rows: [MetricRow]? = nil
    var detailLoading = false; var detailError: String? = nil
}
final class NativePanel: FlippedView {
    var onAction: ((String, [String: Any]) -> Void)?
    private var state: PanelState?
    private var server = NSTextField()
    private var key = NSSecureTextField()
    private var search = NSSearchField()
    private var chosen: Set<String> = []
    private var previousScreen = ""
    private var renderedSize = NSSize.zero
    private weak var overviewScroll: NSScrollView?
    private var overviewOffset = NSPoint.zero
    private weak var detailScroll: NSScrollView?
    private var detailOffset = NSPoint.zero
    private weak var choicesScroll: NSScrollView?
    private var previousDetailID: String?
    override func layout() {
        super.layout()
        if bounds.size != renderedSize, bounds.width > 0, let state = state { render(state) }
    }
    override func cancelOperation(_ sender: Any?) {
        if state?.screen == "detail" { action("back") } else { super.cancelOperation(sender) }
    }
    private func action(_ name: String, _ values: [String: Any] = [:]) { onAction?(name, values) }
    private func button(_ title: String, _ rect: NSRect, style: PaintedButton.Style = .plain, action: @escaping () -> Void) -> PaintedButton {
        let b = PaintedButton(title, frame: rect, style: style, action: action); addSubview(b); return b
    }
    func render(_ next: PanelState) {
        let oldServer = server.stringValue, oldKey = key.stringValue
        let preserveInput = previousScreen == "setup" && next.screen == "setup"
        let preserveSelection = previousScreen == "selection" && next.screen == "selection"
        renderedSize = bounds.size
        if previousScreen == "overview", let scroll = overviewScroll { overviewOffset = scroll.contentView.bounds.origin }
        if previousScreen == "detail", let scroll = detailScroll { detailOffset = scroll.contentView.bounds.origin }
        if next.detailID != previousDetailID { detailOffset = .zero }
        previousDetailID = next.detailID
        state = next; subviews.forEach { $0.removeFromSuperview() }
        if next.screen == "setup" {
            server = NSTextField(string: preserveInput ? oldServer : next.server)
            key = NSSecureTextField(string: preserveInput ? oldKey : "")
            configure(server, at: 112, placeholder: "https://api.umami.is/v1")
            configure(key, at: 187, placeholder: next.hasKey ? "已保存 · 留空保留当前密钥" : "输入 Umami API Key")
            let b = button(next.connecting ? "正在验证连接…" : "连接并选择网站", NSRect(x: 22, y: 268, width: 316, height: 36), style: .primary) { [weak self] in
                guard let self = self else { return }; let values = ["server": self.server.stringValue, "key": self.key.stringValue]; self.key.stringValue = ""; self.action("connect", values)
            }; b.isEnabled = !next.connecting
            if !next.sites.isEmpty { _ = button("返回网站概览 →", NSRect(x: 22, y: 316, width: 316, height: 36), style: .secondary) { [weak self] in self?.action("back") } }
            _ = button("退出 UmamiBar", NSRect(x: 22, y: next.sites.isEmpty ? 316 : 360, width: 316, height: 36), style: .destructive) { [weak self] in self?.action("quit") }
        } else if next.screen == "detail", let selected = next.sites.first(where: { $0.website.id == next.detailID }) {
            let back = button("‹", NSRect(x: 20, y: 20, width: 29, height: 29), style: .navigation) { [weak self] in self?.action("back") }
            back.setAccessibilityLabel("返回网站概览"); back.toolTip = "返回网站概览"
            _ = button("↗", NSRect(x: 310, y: 20, width: 29, height: 29), style: .navigation) { [weak self] in self?.action("dashboard", ["id": selected.website.id]) }
            for p in Period.allCases {
                let b = button(p.title, NSRect(x: 23 + CGFloat(p.rawValue) * 105, y: 79, width: 104, height: 29), style: .segment) { [weak self] in self?.action("period", ["value": p.rawValue]) }; b.selected = p == next.period
            }
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 145, width: bounds.width, height: max(40, bounds.height - 185)))
            scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
            let body = DetailBody(frame: NSRect(x: 0, y: 0, width: 360, height: 566), site: selected, state: next)
            body.onBreakdown = { [weak self] value in self?.action("breakdown", ["value": value]) }
            body.onRetry = { [weak self] in self?.action("detailRetry") }
            scroll.documentView = body; addSubview(scroll); detailScroll = scroll
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(detailOffset.y, max(0, body.bounds.height-scroll.bounds.height)))); scroll.reflectScrolledClipView(scroll.contentView)
            _ = button("打开仪表盘 ↗", NSRect(x: 250, y: bounds.height - 34, width: 92, height: 26)) { [weak self] in self?.action("dashboard", ["id": selected.website.id]) }
        } else if next.screen == "overview" {
            let refresh = button("刷新数据", NSRect(x: 264, y: 22, width: 30, height: 30), style: .icon) { [weak self] in self?.action("refresh") }
            refresh.isEnabled = !next.loading; refresh.toolTip = "立即刷新所有网站"; refresh.isHidden = next.loading
            if next.loading {
                let spinner = NSProgressIndicator(frame: NSRect(x: 271, y: 29, width: 16, height: 16))
                spinner.style = .spinning; spinner.controlSize = .small; spinner.isIndeterminate = true
                spinner.setAccessibilityLabel("正在刷新网站数据")
                addSubview(spinner); spinner.startAnimation(nil)
            }
            let settings = button("连接设置", NSRect(x: 301, y: 22, width: 30, height: 30), style: .icon) { [weak self] in self?.action("settings") }; settings.toolTip = "连接与网站设置"
            for p in Period.allCases {
                let b = button(p.title, NSRect(x: 23 + CGFloat(p.rawValue) * 105, y: 79, width: 104, height: 29), style: .segment) { [weak self] in self?.action("period", ["value": p.rawValue]) }; b.selected = p == next.period; b.setAccessibilityValue(b.selected ? "已选中" : "未选中")
            }
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 135, width: bounds.width, height: max(40, bounds.height - 175)))
            scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
            let document = FlippedView(); var y: CGFloat = 0
            for (i, site) in next.sites.enumerated() {
                let height: CGFloat = 218 + (site.error == nil ? 0 : 30)
                let card = SiteCard(frame: NSRect(x: 0, y: y, width: 360, height: height), site: site, index: i, state: next)
                card.open = { [weak self] in self?.action("detail", ["id": site.website.id]) }; document.addSubview(card); y += height
            }
            document.frame = NSRect(x: 0, y: 0, width: 360, height: max(scroll.bounds.height, y)); scroll.documentView = document; addSubview(scroll); overviewScroll = scroll
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(overviewOffset.y, max(0, y-scroll.bounds.height)))); scroll.reflectScrolledClipView(scroll.contentView)
            _ = button("管理网站", NSRect(x: 272, y: bounds.height - 34, width: 70, height: 26)) { [weak self] in self?.action("manage") }
        } else {
            if !preserveSelection { chosen = Set(next.selected) }
            search.frame = NSRect(x: 22, y: 84, width: 316, height: 30); search.sendsSearchStringImmediately = true; search.target = self; search.action = #selector(filterSites); addSubview(search)
            _ = button("全选", NSRect(x: 18, y: 122, width: 40, height: 24)) { [weak self] in guard let self = self else { return }; self.chosen = Set(next.available.map(\.id)); self.fillChoices(next.available) }
            _ = button("取消全选", NSRect(x: 62, y: 122, width: 65, height: 24)) { [weak self] in self?.chosen = []; self?.fillChoices(next.available) }
            let scroll = NSScrollView(frame: NSRect(x: 22, y: 155, width: 316, height: max(60, bounds.height - 270))); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
            addSubview(scroll); choicesScroll = scroll; fillChoices(next.available)
            _ = button("保存并查看", NSRect(x: 22, y: bounds.height - 99, width: 316, height: 36), style: .primary) { [weak self] in guard let self = self else { return }; self.action("save", ["ids": Array(self.chosen)]) }
            _ = button("返回连接设置", NSRect(x: 22, y: bounds.height - 52, width: 316, height: 26)) { [weak self] in self?.action("settings") }
        }
        previousScreen = next.screen; needsDisplay = true
    }
    // Rebuild only the list: re-rendering the panel would remove the search field mid-edit and reselect its text.
    @objc private func filterSites() { if let state = state { fillChoices(state.available) } }
    private func fillChoices(_ available: [Website]) {
        guard let scroll = choicesScroll else { return }
        let query = search.stringValue
        let document = FlippedView(); var y: CGFloat = 0
        for site in available where query.isEmpty || (site.name + site.domain).localizedCaseInsensitiveContains(query) {
            let check = WebsiteChoice(site, frame: NSRect(x: 0, y: y, width: 310, height: 52), target: self, action: #selector(checkSite))
            check.state = chosen.contains(site.id) ? .on : .off; document.addSubview(check); y += 52
        }
        document.frame = NSRect(x: 0, y: 0, width: 316, height: max(y, scroll.bounds.height)); scroll.documentView = document
    }
    @objc private func checkSite(_ sender: NSButton) { guard let id = sender.identifier?.rawValue else { return }; if sender.state == .on { chosen.insert(id) } else { chosen.remove(id) } }
    private func configure(_ field: NSTextField, at y: CGFloat, placeholder: String) {
        field.placeholderString = placeholder
        field.setAccessibilityLabel(field === key ? "API Key" : "Umami 服务地址")
        addSubview(GlassInput(field: field, frame: NSRect(x: 22, y: y, width: 316, height: 38)))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let surface = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
        let opacity: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.95
        let base = NSGradient(starting: NSColor(white: Ink.dark ? 0.137 : 1, alpha: opacity), ending: NSColor(white: Ink.dark ? 0.118 : 0.955, alpha: opacity))
        base?.draw(in: surface, angle: 55)
        let sheen = NSGradient(starting: NSColor(white: 1, alpha: Ink.dark ? 0.035 : 0.28), ending: NSColor(white: 1, alpha: 0))
        sheen?.draw(in: NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18), angle: 45)
        NSColor(white: Ink.dark ? 0.5 : 1, alpha: Ink.dark ? 0.25 : 0.95).setStroke(); NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 18, yRadius: 18).stroke()
        NSColor(white: 1, alpha: Ink.dark ? 0.045 : 0.4).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1.7, dy: 1.7), xRadius: 17, yRadius: 17).stroke()
        guard let s = state else { return }
        if s.screen == "setup" {
            text("连接 Umami", NSRect(x: 22, y: 22, width: 300, height: 22), size: 15, weight: .semibold)
            text("添加服务地址和 API Key，即可集中查看多个网站。", NSRect(x: 22, y: 55, width: 316, height: 32), color: Ink.secondary)
            text("服务地址", NSRect(x: 22, y: 93, width: 316, height: 16), color: Ink.secondary)
            text("API Key", NSRect(x: 22, y: 168, width: 316, height: 16), color: Ink.secondary)

            text("密钥仅保存在 macOS 钥匙串。", NSRect(x: 22, y: 240, width: 316, height: 16), size: 10, color: Ink.secondary)
        } else if s.screen == "detail", let site = s.sites.first(where: { $0.website.id == s.detailID }) {
            text(site.website.name, NSRect(x: 60, y: 19, width: 240, height: 18), size: 13, weight: .semibold)
            text(site.website.domain, NSRect(x: 60, y: 40, width: 240, height: 16), size: 10, color: Ink.secondary)
            fill(NSRect(x: 20, y: 76, width: 320, height: 35), NSColor(white: Ink.dark ? 0 : 0.2, alpha: Ink.dark ? 0.3 : 0.07), radius: 9)
            let formatter = DateFormatter(); formatter.dateFormat = "MM/dd HH:mm"
            text(formatter.string(from: s.start) + " — " + formatter.string(from: s.end), NSRect(x: 21, y: 123, width: 300, height: 15), size: 10, color: Ink.secondary)
            fill(NSRect(x: 0, y: bounds.height-40, width: 360, height: 0.5), Ink.line)
            text(s.loading ? "正在刷新…" : s.updated, NSRect(x: 20, y: bounds.height-28, width: 225, height: 17), size: 10, color: Ink.secondary)
        } else if s.screen == "overview" {
            fill(NSRect(x: 20, y: 20, width: 32, height: 32), NSColor(white: 0.5, alpha: 0.18), radius: 9)
            for (i,h) in [9.0,15,12].enumerated() { fill(NSRect(x: 29 + Double(i)*5, y: 44-h, width: 2, height: h), Ink.text, radius: 1) }
            text("网站概览", NSRect(x: 62, y: 19, width: 180, height: 18), size: 13, weight: .semibold); text("\(s.sites.count) 个网站", NSRect(x: 62, y: 40, width: 180, height: 16), color: Ink.secondary)
            let toolRect = NSRect(x: 260, y: 18, width: 76, height: 38)
            fill(toolRect, NSColor(white: 0.5, alpha: 0.025), radius: 9)
            NSColor(white: Ink.dark ? 1 : 0, alpha: Ink.dark ? 0.05 : 0.045).setStroke(); NSBezierPath(roundedRect: toolRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
            fill(NSRect(x: 298, y: 31, width: 1, height: 13), Ink.line)
            fill(NSRect(x: 20, y: 76, width: 320, height: 35), NSColor(white: Ink.dark ? 0 : 0.2, alpha: Ink.dark ? 0.3 : 0.07), radius: 9)
            let formatter = DateFormatter(); formatter.dateFormat = "MM/dd HH:mm"
            text(formatter.string(from: s.start) + " — " + formatter.string(from: s.end), NSRect(x: 21, y: 123, width: 235, height: 15), size: 10, color: Ink.secondary)
            text(TimeZone.current.abbreviation() ?? "", NSRect(x: 262, y: 123, width: 76, height: 15), size: 10, color: Ink.secondary, alignment: .right)
            let footerTop = bounds.height - 40
            let shade = NSGradient(starting: NSColor.black.withAlphaComponent(Ink.dark ? 0.11 : 0.035), ending: .clear)
            shade?.draw(in: NSRect(x: 0, y: footerTop - 6, width: bounds.width, height: 6), angle: 270)
            fill(NSRect(x: 0, y: footerTop, width: bounds.width, height: 0.5), Ink.line)
            fill(NSRect(x: 0, y: footerTop + 0.5, width: bounds.width, height: 0.5), NSColor.white.withAlphaComponent(Ink.dark ? 0.025 : 0.8))
            fill(NSRect(x: 21, y: bounds.height-22, width: 4, height: 4), Ink.green, radius: 2)
            text(s.loading ? "正在刷新 \(s.sites.count) 个网站…" : s.updated, NSRect(x: 30, y: bounds.height-28, width: 230, height: 17), size: 10, color: Ink.secondary)
        } else {
            text("选择关注的网站", NSRect(x: 22, y: 22, width: 316, height: 22), size: 15, weight: .semibold)
            text("所有已选网站将同时展示。", NSRect(x: 22, y: 54, width: 316, height: 16), color: Ink.secondary)
        }
        if !s.message.isEmpty { fill(NSRect(x: 12, y: bounds.height-80, width: 336, height: 64), NSColor(white: Ink.dark ? 0.22 : 0.93, alpha: 1), radius: 8); text(s.message, NSRect(x: 23, y: bounds.height-69, width: 314, height: 44), size: 11) }
    }
}
private func drawGrowth(_ site: PanelSite, rect: NSRect) {
    let change = Stats.change(current: site.total, previous: site.previousVisitors)
    let positive = change.hasPrefix("↑")
    let color = positive ? Ink.green : change.hasPrefix("↓") || change.hasPrefix("新增") ? NSColor.systemOrange : Ink.secondary
    text(change, rect, size: 9, color: color, alignment: .right)
}
private func drawStats(_ stats: Stats?, y: CGFloat) {
    let fields = [("浏览量", stats?.pageviews.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "—"), ("跳出率", stats?.bounceText ?? "—"), ("平均时长", stats?.durationText ?? "—")]
    for (i, field) in fields.enumerated() {
        let x = CGFloat(20 + i * 107)
        if i > 0 { fill(NSRect(x: x-10, y: y, width: 0.5, height: 31), Ink.line) }
        text(field.0, NSRect(x: x, y: y, width: 100, height: 14), size: 9, color: Ink.secondary)
        text(field.1, NSRect(x: x, y: y+18, width: 100, height: 17), size: 12, weight: .medium)
    }
}
final class SiteCard: FlippedView {
    private let site: PanelSite; private let index: Int; private let state: PanelState
    var open: (() -> Void)?
    init(frame: NSRect, site: PanelSite, index: Int, state: PanelState) {
        self.site = site; self.index = index; self.state = state; super.init(frame: frame)
        let openButton = PaintedButton("", frame: NSRect(x: 18, y: 12, width: 220, height: 40)) { [weak self] in self?.open?() }; openButton.toolTip = "查看 \(site.website.name) 详情"; openButton.setAccessibilityLabel("查看 \(site.website.name) 详情"); addSubview(openButton)
        do {
            let chart = ChartView(frame: NSRect(x: 20, y: 74, width: 320, height: 65)); chart.points = site.points ?? []; chart.colorIndex = index; chart.showsScale = false
            chart.onClick = { [weak self] in self?.open?() }; chart.setAccessibilityLabel("查看 \(site.website.name) 详情"); addSubview(chart)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        if index > 0 { fill(NSRect(x: 20, y: 0, width: 320, height: 0.5), Ink.line) }
        text(site.website.name, NSRect(x: 20, y: 17, width: 218, height: 17), size: 12, weight: .medium)
        text(site.website.domain, NSRect(x: 20, y: 36, width: 218, height: 16), size: 10, color: Ink.secondary)
        let count = site.total.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "—"
        let line = NSMutableAttributedString(string: count, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium), .foregroundColor: Ink.text])
        line.append(NSAttributedString(string: " 访客", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: Ink.secondary]))
        line.draw(at: NSPoint(x: bounds.width - 20 - line.size().width, y: 17))
        drawGrowth(site, rect: NSRect(x: 180, y: 51, width: 160, height: 15))
        do {
            if site.points == nil { text(state.loading ? "正在加载…" : "趋势暂无数据", NSRect(x: 20, y: 94, width: 320, height: 18), color: Ink.secondary, alignment: .center) }
            let formatter = DateFormatter(); formatter.dateFormat = state.period == .day ? "HH:mm" : "MM/dd"
            for (i,date) in [state.start, Date(timeIntervalSince1970: (state.start.timeIntervalSince1970+state.end.timeIntervalSince1970)/2),state.end].enumerated() { text(formatter.string(from: date), NSRect(x: 20+CGFloat(i)*106, y: 145, width: 106, height: 14), size: 9, color: Ink.secondary, alignment: i == 0 ? .left : i == 2 ? .right : .center) }
        }
        drawStats(site.stats, y: 171)
        if let error = site.error { text("更新失败 · " + error, NSRect(x: 20, y: bounds.height-25, width: 320, height: 24), size: 10, color: .systemOrange) }
    }
}
final class DetailBody: FlippedView {
    let site: PanelSite; let state: PanelState
    var onBreakdown: ((String) -> Void)?
    var onRetry: (() -> Void)?
    init(frame: NSRect, site: PanelSite, state: PanelState) {
        self.site = site; self.state = state; super.init(frame: frame)
        let chart = ChartView(frame: NSRect(x: 20, y: 181, width: 320, height: 90)); chart.points = site.points ?? []; addSubview(chart)
        for (i, value) in ["pages", "sources"].enumerated() {
            let b = PaintedButton(i == 0 ? "热门页面" : "流量来源", frame: NSRect(x: 16+CGFloat(i)*88, y: 301, width: 80, height: 30), style: .segment) { [weak self] in self?.onBreakdown?(value) }; b.selected = state.breakdown == value; addSubview(b)
        }
        if state.detailError != nil {
            let retry = PaintedButton("重新加载", frame: NSRect(x: 122, y: 401, width: 116, height: 30), style: .secondary) { [weak self] in self?.onRetry?() }; addSubview(retry)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        text("访客数", NSRect(x: 20, y: 20, width: 120, height: 16), size: 10, color: Ink.secondary)
        text(site.total.map(String.init) ?? "—", NSRect(x: 20, y: 40, width: 190, height: 43), size: 34, weight: .medium)
        drawGrowth(site, rect: NSRect(x: 185, y: 65, width: 155, height: 16))
        drawStats(site.stats, y: 100)
        fill(NSRect(x: 20, y: 148, width: 320, height: 0.5), Ink.line)
        text("会话趋势", NSRect(x: 20, y: 161, width: 160, height: 17), weight: .semibold)
        text(state.period == .day ? "每小时" : "每天", NSRect(x: 265, y: 161, width: 75, height: 17), size: 9, color: Ink.secondary, alignment: .right)
        if site.points == nil { text("趋势暂无数据", NSRect(x: 90, y: 214, width: 180, height: 16), color: Ink.secondary, alignment: .center) }
        let formatter = DateFormatter(); formatter.dateFormat = state.period == .day ? "HH:mm" : "MM/dd"
        text(formatter.string(from: state.start), NSRect(x: 20, y: 279, width: 100, height: 14), size: 9, color: Ink.secondary)
        text(formatter.string(from: state.end), NSRect(x: 240, y: 279, width: 100, height: 14), size: 9, color: Ink.secondary, alignment: .right)
        fill(NSRect(x: 20, y: 335, width: 320, height: 0.5), Ink.line)
        text(state.breakdown == "pages" ? "页面路径" : "来源", NSRect(x: 20, y: 348, width: 160, height: 15), size: 9, color: Ink.secondary)
        text("次数 / 前5项占比", NSRect(x: 210, y: 348, width: 130, height: 15), size: 9, color: Ink.secondary, alignment: .right)
        if state.detailLoading { text("正在加载…", NSRect(x: 20, y: 383, width: 320, height: 20), color: Ink.secondary, alignment: .center) }
        else if let error = state.detailError { text(error, NSRect(x: 20, y: 377, width: 320, height: 24), size: 10, color: .systemOrange) }
        else if let rows = state.rows, !rows.isEmpty {
            let sum = rows.reduce(0) { $0 + $1.y }
            for (i,row) in rows.prefix(5).enumerated() {
                let y = CGFloat(371+i*32); let ratio = sum > 0 ? row.y/sum : 0
                fill(NSRect(x: 20, y: y, width: 320*ratio, height: 29), NSColor.systemOrange.withAlphaComponent(0.07), radius: 4)
                text(row.x.flatMap { $0.isEmpty ? nil : $0 } ?? (state.breakdown == "sources" ? "直接访问" : "/"), NSRect(x: 28, y: y+8, width: 205, height: 15), size: 10)
                text("\(Int(row.y))   \(Int((ratio*100).rounded()))%", NSRect(x: 235, y: y+8, width: 97, height: 15), size: 10, alignment: .right)
            }
        } else { text("该时段暂无数据", NSRect(x: 20, y: 383, width: 320, height: 20), color: Ink.secondary, alignment: .center) }
        text("仅展示前 5 项 · 占比按当前返回的前 5 项计算", NSRect(x: 20, y: 535, width: 320, height: 17), size: 9, color: Ink.secondary)
    }
}
