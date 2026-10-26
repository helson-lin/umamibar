import AppKit

struct PanelSite { let website: Website; let total: Int?; let points: [Point]?; let error: String?; var stats: Stats? = nil; var previousVisitors: Int? = nil; var color = 0; var pinned = false; var rangeStart: Date? = nil; var rangeEnd: Date? = nil; var savedAt: Date? = nil; var cached = false; var live: Int? = nil; var liveFailed = false }
struct PanelState {
    var screen: String; var loading: Bool
    var period: Period; var start: Date; var end: Date; var updated: String
    var sites: [PanelSite]
    var detailID: String? = nil; var breakdown = "pages"; var dimension: DetailDimension = .pages; var rows: [MetricRow]? = nil; var detailExpanded = false
    var detailLoading = false; var detailError: String? = nil
    var hasConnection = false; var hasCachedData = false
}
final class NativePanel: FlippedView {
    var onAction: ((String, [String: Any]) -> Void)?
    private var state: PanelState?
    private var previousScreen = ""
    private var renderedSize = NSSize.zero
    private weak var overviewScroll: NSScrollView?
    private var overviewOffset = NSPoint.zero
    private weak var detailScroll: NSScrollView?
    private var detailOffset = NSPoint.zero
    private var previousDetailID: String?
    private var renderedLanguage = ""
    override func layout() {
        super.layout()
        if bounds.size != renderedSize, bounds.width > 0, let state = state { render(state) }
    }
    override func cancelOperation(_ sender: Any?) {
        // NSResponder has no cancelOperation(_:) of its own, so calling super would crash; hand Esc up the chain instead.
        if state?.screen == "detail" { action("back") } else { nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender) }
    }
    private func action(_ name: String, _ values: [String: Any] = [:]) { onAction?(name, values) }
    /// Range segments in display order; Today's short label takes a narrower segment so "Last 24 hours" still fits.
    private static let periodSegments: [(Period, NSRect)] = {
        var x: CGFloat = 23
        return Period.displayOrder.map { p in
            let width: CGFloat = p == .today ? 56 : 85
            defer { x += width + 1 }
            return (p, NSRect(x: x, y: 79, width: width, height: 29))
        }
    }()
    private func button(_ title: String, _ rect: NSRect, style: PaintedButton.Style = .plain, action: @escaping () -> Void) -> PaintedButton {
        let b = PaintedButton(title, frame: rect, style: style, action: action); addSubview(b); return b
    }
    func render(_ next: PanelState) {
        // Data refreshes keep the scroll view and update cards in place, so hover,
        // scroll momentum and in-progress clicks survive; only layout changes rebuild.
        let overviewCards = (overviewScroll?.documentView?.subviews ?? []).compactMap { $0 as? SiteCard }
        let reuseOverview = renderedLanguage == Localization.bundle.bundlePath && next.screen == "overview" && previousScreen == "overview" && overviewScroll != nil
            && overviewCards.map(\.layoutKey) == next.sites.map(SiteCard.layoutKey)
        let reuseDetail = next.screen == "detail" && previousScreen == "detail" && next.detailID == previousDetailID && detailScroll?.documentView is DetailBody
        renderedSize = bounds.size; renderedLanguage = Localization.bundle.bundlePath
        if previousScreen == "overview", let scroll = overviewScroll { overviewOffset = scroll.contentView.bounds.origin }
        if previousScreen == "detail", let scroll = detailScroll { detailOffset = scroll.contentView.bounds.origin }
        if next.detailID != previousDetailID { detailOffset = .zero }
        previousDetailID = next.detailID
        // Pointer-initiated overview <-> detail navigation slides to show hierarchy; keyboard (Return on a chart, Esc) stays instant.
        let push: CATransitionSubtype? = previousScreen == "overview" && next.screen == "detail" ? .fromRight : previousScreen == "detail" && next.screen == "overview" ? .fromLeft : nil
        var transitioned = false
        if let push = push, let type = NSApp.currentEvent?.type, [.leftMouseDown, .leftMouseUp].contains(type), let layer = layer {
            let transition = CATransition()
            transition.type = Motion.reduced ? .fade : .push; transition.subtype = push
            transition.duration = Motion.reduced ? 0.15 : 0.25; transition.timingFunction = Motion.easeOutTiming
            layer.add(transition, forKey: kCATransition); transitioned = true
        }
        state = next
        subviews.forEach { if !(reuseOverview && $0 === overviewScroll) && !(reuseDetail && $0 === detailScroll) { $0.removeFromSuperview() } }
        if next.screen == "empty" {
            _ = button(next.hasConnection ? L("选择网站") : L("打开设置"), NSRect(x: 22, y: 104, width: 316, height: 36), style: .primary) { [weak self] in self?.action(next.hasConnection ? "manage" : "settings") }
            _ = button(L("退出 UmamiBar"), NSRect(x: 22, y: 148, width: 316, height: 36), style: .destructive) { [weak self] in self?.action("quit") }
        } else if next.screen == "detail", let selected = next.sites.first(where: { $0.website.id == next.detailID }) {
            let back = button("‹", NSRect(x: 20, y: 20, width: 29, height: 29), style: .navigation) { [weak self] in self?.action("back") }
            back.setAccessibilityLabel(L("返回网站概览")); back.toolTip = L("返回网站概览")
            _ = button("↗", NSRect(x: 310, y: 20, width: 29, height: 29), style: .navigation) { [weak self] in self?.action("dashboard", ["id": selected.website.id]) }
            for (p, rect) in Self.periodSegments {
                let b = button(p.title, rect, style: .segment) { [weak self] in self?.action("period", ["value": p.rawValue]) }; b.selected = p == next.period
            }
            let frame = NSRect(x: 0, y: 145, width: bounds.width, height: max(40, bounds.height - 185))
            if reuseDetail, let scroll = detailScroll, let body = scroll.documentView as? DetailBody {
                scroll.frame = frame; body.update(site: selected, state: next)
            } else {
                let scroll = NSScrollView(frame: frame)
                scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
                let body = DetailBody(frame: NSRect(x: 0, y: 0, width: 360, height: DetailBody.rowsLayout(next).height), site: selected, state: next)
                body.onBreakdown = { [weak self] value in self?.action("breakdown", ["value": value]) }
                body.onDimension = { [weak self] value in self?.action("dimension", ["value": value.rawValue]) }
                body.onRetry = { [weak self] in self?.action("detailRetry") }
                body.onToggleRows = { [weak self] in self?.action("toggleRows") }
                scroll.documentView = body; addSubview(scroll); detailScroll = scroll
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(detailOffset.y, max(0, body.bounds.height-scroll.bounds.height)))); scroll.reflectScrolledClipView(scroll.contentView)
            }
            _ = button(L("打开仪表盘 ↗"), NSRect(x: 250, y: bounds.height - 34, width: 92, height: 26)) { [weak self] in self?.action("dashboard", ["id": selected.website.id]) }
        } else if next.screen == "overview" {
            let refresh = button(L("刷新数据"), NSRect(x: 264, y: 22, width: 30, height: 30), style: .icon) { [weak self] in self?.action("refresh") }
            refresh.symbol = "refresh"; refresh.isEnabled = !next.loading; refresh.toolTip = L("立即刷新所有网站"); refresh.isHidden = next.loading
            if next.loading {
                let spinner = NSProgressIndicator(frame: NSRect(x: 271, y: 29, width: 16, height: 16))
                spinner.style = .spinning; spinner.controlSize = .small; spinner.isIndeterminate = true
                spinner.setAccessibilityLabel(L("正在刷新网站数据"))
                addSubview(spinner); spinner.startAnimation(nil)
            }
            let settings = button(L("连接设置"), NSRect(x: 301, y: 22, width: 30, height: 30), style: .icon) { [weak self] in self?.action("settings") }; settings.toolTip = L("连接与网站设置")
            for (p, rect) in Self.periodSegments {
                let b = button(p.title, rect, style: .segment) { [weak self] in self?.action("period", ["value": p.rawValue]) }; b.selected = p == next.period; b.setAccessibilityValue(b.selected ? L("已选中") : L("未选中"))
            }
            let frame = NSRect(x: 0, y: 135, width: bounds.width, height: max(40, bounds.height - 175))
            if reuseOverview, let scroll = overviewScroll, let document = scroll.documentView {
                scroll.frame = frame
                zip(overviewCards, next.sites).forEach { $0.update(site: $1, state: next) }
                document.frame.size.height = max(frame.height, overviewCards.last?.frame.maxY ?? 0)
            } else {
                let scroll = NSScrollView(frame: frame)
                scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
                let document = FlippedView(); var y: CGFloat = 0
                for (i, site) in next.sites.enumerated() {
                    if (i == 0 && site.pinned) || (i > 0 && next.sites[i-1].pinned && !site.pinned) {
                        let label = NSTextField(labelWithString: site.pinned ? L("置顶") : L("其他网站"))
                        label.font = .systemFont(ofSize: 10); label.textColor = Ink.secondary
                        label.frame = NSRect(x: 20, y: y + 7, width: 320, height: 15); document.addSubview(label); y += 24
                    }
                    let height: CGFloat = 218 + (site.error != nil || site.cached ? 30 : 0)
                    let card = SiteCard(frame: NSRect(x: 0, y: y, width: 360, height: height), site: site, index: i, state: next)
                    card.open = { [weak self] in self?.action("detail", ["id": site.website.id]) }; document.addSubview(card); y += height
                }
                document.frame = NSRect(x: 0, y: 0, width: 360, height: max(scroll.bounds.height, y)); scroll.documentView = document; addSubview(scroll); overviewScroll = scroll
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(overviewOffset.y, max(0, y-scroll.bounds.height)))); scroll.reflectScrolledClipView(scroll.contentView)
            }
            _ = button(L("管理网站"), NSRect(x: 272, y: bounds.height - 34, width: 70, height: 26)) { [weak self] in self?.action("manage") }
        }
        previousScreen = next.screen; needsDisplay = true
        // The header text is drawn in draw(_:), not by subviews; render it now so it slides with its screen.
        if transitioned { displayIfNeeded() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        // Fill every corner beneath NSPopover's native outline instead of adding a second rounded edge.
        drawSurface(bounds, radius: 0)
        guard let s = state else { return }
        if s.screen == "empty" {
            text(s.hasConnection ? L("选择关注的网站") : L("连接 Umami"), NSRect(x: 22, y: 22, width: 300, height: 22), size: 15, weight: .semibold)
            text(s.hasConnection ? L("在网站设置中勾选要关注的网站，即可查看访问趋势。") : L("在设置中填写服务地址和 API Key，并选择要关注的网站。"), NSRect(x: 22, y: 55, width: 316, height: 32), color: Ink.secondary)
        } else if s.screen == "detail", let site = s.sites.first(where: { $0.website.id == s.detailID }) {
            text(site.website.name, NSRect(x: 60, y: 19, width: 240, height: 18), size: 13, weight: .semibold)
            text(site.website.domain, NSRect(x: 60, y: 40, width: 240, height: 16), size: 10, color: Ink.secondary)
            fill(NSRect(x: 20, y: 76, width: 320, height: 35), NSColor(white: Ink.dark ? 0 : 0.2, alpha: Ink.dark ? 0.3 : 0.07), radius: 9)
            text(Formats.range.string(from: s.start) + " — " + Formats.range.string(from: s.end), NSRect(x: 21, y: 123, width: 300, height: 15), size: 10, color: Ink.secondary)
            fill(NSRect(x: 0, y: bounds.height-40, width: 360, height: 0.5), Ink.line)
            text(s.loading ? L("正在刷新…") : s.updated, NSRect(x: 20, y: bounds.height-28, width: 225, height: 17), size: 10, color: Ink.secondary)
        } else if s.screen == "overview" {
            fill(NSRect(x: 20, y: 20, width: 32, height: 32), NSColor(white: 0.5, alpha: 0.18), radius: 9)
            for (i,h) in [9.0,15,12].enumerated() { fill(NSRect(x: 29 + Double(i)*5, y: 44-h, width: 2, height: h), Ink.text, radius: 1) }
            text(L("网站概览"), NSRect(x: 62, y: 19, width: 180, height: 18), size: 13, weight: .semibold); text(L("%ld 个网站", s.sites.count), NSRect(x: 62, y: 40, width: 180, height: 16), color: Ink.secondary)
            let toolRect = NSRect(x: 260, y: 18, width: 76, height: 38)
            fill(toolRect, NSColor(white: 0.5, alpha: 0.025), radius: 9)
            NSColor(white: Ink.dark ? 1 : 0, alpha: Ink.dark ? 0.05 : 0.045).setStroke(); NSBezierPath(roundedRect: toolRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
            fill(NSRect(x: 298, y: 31, width: 1, height: 13), Ink.line)
            fill(NSRect(x: 20, y: 76, width: 320, height: 35), NSColor(white: Ink.dark ? 0 : 0.2, alpha: Ink.dark ? 0.3 : 0.07), radius: 9)
            text(Formats.range.string(from: s.start) + " — " + Formats.range.string(from: s.end), NSRect(x: 21, y: 123, width: 235, height: 15), size: 10, color: Ink.secondary)
            text(TimeZone.current.abbreviation() ?? "", NSRect(x: 262, y: 123, width: 76, height: 15), size: 10, color: Ink.secondary, alignment: .right)
            let footerTop = bounds.height - 40
            let shade = NSGradient(starting: NSColor.black.withAlphaComponent(Ink.dark ? 0.11 : 0.035), ending: .clear)
            shade?.draw(in: NSRect(x: 0, y: footerTop - 6, width: bounds.width, height: 6), angle: 270)
            fill(NSRect(x: 0, y: footerTop, width: bounds.width, height: 0.5), Ink.line)
            fill(NSRect(x: 0, y: footerTop + 0.5, width: bounds.width, height: 0.5), NSColor.white.withAlphaComponent(Ink.dark ? 0.025 : 0.8))
            fill(NSRect(x: 21, y: bounds.height-22, width: 4, height: 4), s.hasCachedData ? .systemOrange : Ink.green, radius: 2)
            text(s.loading ? L("正在刷新 %ld 个网站…", s.sites.count) : s.updated, NSRect(x: 30, y: bounds.height-28, width: 230, height: 17), size: 10, color: Ink.secondary)
        }
    }
}
private func drawGrowth(_ site: PanelSite, period: Period, rect: NSRect) {
    let change = Stats.change(current: site.total, previous: site.previousVisitors, period: period)
    // Color from the numbers, not the localized text: green for growth, orange for a decline or a new site.
    var color = Ink.secondary
    if let current = site.total, let previous = site.previousVisitors {
        if previous > 0 && current > previous { color = Ink.green } else if current < previous || (previous == 0 && current > 0) { color = NSColor.systemOrange }
    }
    text(change, rect, size: 9, color: color, alignment: .right)
}
/// The live marker: a filled dot that breathes while anyone is online, a hollow ring at zero, hidden when unknown.
final class LiveDot: NSView {
    var count: Int? { didSet { if count != oldValue { restyle() } } }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; restyle() }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle() }
    private func restyle() {
        guard let layer = layer else { return }
        isHidden = count == nil
        let previous = NSAppearance.current; NSAppearance.current = effectiveAppearance; defer { NSAppearance.current = previous }
        let active = (count ?? 0) > 0
        layer.cornerRadius = bounds.width / 2
        layer.backgroundColor = active ? Ink.green.cgColor : NSColor.clear.cgColor
        layer.borderWidth = active ? 0 : 1; layer.borderColor = Ink.secondary.cgColor
        layer.removeAnimation(forKey: "breathe")
        guard active, !Motion.reduced else { return }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1; breathe.toValue = 0.35; breathe.duration = 1.2; breathe.autoreverses = true; breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(breathe, forKey: "breathe")
    }
}
private func drawStats(_ stats: Stats?, y: CGFloat) {
    let fields = [(L("浏览量"), stats?.pageviews.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "—"), (L("跳出率"), stats?.bounceText ?? "—"), (L("平均时长"), stats?.durationText ?? "—")]
    for (i, field) in fields.enumerated() {
        let x = CGFloat(20 + i * 107)
        if i > 0 { fill(NSRect(x: x-10, y: y, width: 0.5, height: 31), Ink.line) }
        text(field.0, NSRect(x: x, y: y, width: 100, height: 14), size: 9, color: Ink.secondary)
        text(field.1, NSRect(x: x, y: y+18, width: 100, height: 17), size: 12, weight: .medium)
    }
}
final class SiteCard: FlippedView {
    private var site: PanelSite; private let index: Int; private var state: PanelState
    private let chart = ChartView(frame: NSRect(x: 20, y: 74, width: 320, height: 65))
    private let liveDot = LiveDot(frame: NSRect(x: 0, y: 22, width: 5, height: 5))
    var open: (() -> Void)?
    /// Cards can be updated in place only while the website and card height stay the same.
    static func layoutKey(_ site: PanelSite) -> String { site.website.id + (site.error == nil ? "" : "#error") + (site.cached ? "#cached" : "") + (site.pinned ? "#pinned" : "") }
    var layoutKey: String { Self.layoutKey(site) }
    init(frame: NSRect, site: PanelSite, index: Int, state: PanelState) {
        self.site = site; self.index = index; self.state = state; super.init(frame: frame)
        // Hover area wraps the name (x 20, y 17) and domain (ends y 52) with ~10pt padding; the painted fill insets 1pt.
        let openButton = PaintedButton("", frame: NSRect(x: 9, y: 9, width: 240, height: 48)) { [weak self] in self?.open?() }; openButton.toolTip = L("查看 %@ 详情", site.website.name); openButton.setAccessibilityLabel(L("查看 %@ 详情", site.website.name)); addSubview(openButton)
        chart.points = site.points ?? []; chart.colorIndex = site.color; chart.showsScale = false
        chart.onClick = { [weak self] in self?.open?() }; chart.setAccessibilityLabel(L("查看 %@ 详情", site.website.name)); addSubview(chart)
        addSubview(liveDot); placeLiveDot()
    }
    func update(site: PanelSite, state: PanelState) { self.site = site; self.state = state; chart.colorIndex = site.color; chart.points = site.points ?? []; placeLiveDot(); needsDisplay = true }
    /// The live count follows the name ("Fanbar ● 7"); a long name truncates so the count always stays visible.
    private var nameLayout: (x: CGFloat, width: CGFloat, liveX: CGFloat) {
        let x: CGFloat = site.pinned ? 35 : 20, room = 238 - x
        let liveWidth = ceil(liveCount.size().width) + (site.live == nil ? 0 : 9) + 7
        let name = NSAttributedString(string: site.website.name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        let width = min(ceil(name.size().width) + 1, room - liveWidth)
        return (x, width, x + width + 7)
    }
    private var liveCount: NSAttributedString {
        let value = site.live.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "—"
        return NSAttributedString(string: value, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: (site.live ?? 0) > 0 ? Ink.green : Ink.secondary])
    }
    private func placeLiveDot() { liveDot.frame.origin.x = nameLayout.liveX; liveDot.count = site.live }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        if index > 0 { fill(NSRect(x: 20, y: 0, width: 320, height: 0.5), Ink.line) }
        if site.pinned { drawPin(in: NSRect(x: 20, y: 20, width: 10, height: 11), color: Ink.secondary) }
        let layout = nameLayout
        text(site.website.name, NSRect(x: layout.x, y: 17, width: layout.width, height: 17), size: 12, weight: .medium)
        liveCount.draw(at: NSPoint(x: layout.liveX + (site.live == nil ? 0 : 9), y: 19))
        text(site.website.domain, NSRect(x: 20, y: 36, width: 218, height: 16), size: 10, color: Ink.secondary)
        let count = site.total.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "—"
        let line = NSMutableAttributedString(string: count, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium), .foregroundColor: Ink.text])
        line.append(NSAttributedString(string: " " + L("访客"), attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: Ink.secondary]))
        line.draw(at: NSPoint(x: bounds.width - 20 - line.size().width, y: 17))
        drawGrowth(site, period: state.period, rect: NSRect(x: 180, y: 51, width: 160, height: 15))
        do {
            if site.points == nil { text(state.loading ? L("正在加载…") : site.error != nil && site.total == nil ? L("该范围暂无已保存数据") : L("趋势暂无数据"), NSRect(x: 20, y: 94, width: 320, height: 18), color: Ink.secondary, alignment: .center) }
            let formatter = Formats.axis(state.period)
            for (i,date) in [(site.rangeStart ?? state.start), Date(timeIntervalSince1970: ((site.rangeStart ?? state.start).timeIntervalSince1970+(site.rangeEnd ?? state.end).timeIntervalSince1970)/2),(site.rangeEnd ?? state.end)].enumerated() { text(formatter.string(from: date), NSRect(x: 20+CGFloat(i)*106, y: 145, width: 106, height: 14), size: 9, color: Ink.secondary, alignment: i == 0 ? .left : i == 2 ? .right : .center) }
        }
        drawStats(site.stats, y: 171)
        if site.error != nil || site.cached {
            let saved = site.savedAt.map { L("本地数据 · %@ 保存", Formats.range.string(from: $0)) }
            let note = saved ?? site.error.map { L("更新失败 · %@", $0) } ?? ""
            text(note, NSRect(x: 20, y: bounds.height-25, width: 320, height: 24), size: 9, color: .systemOrange)
            toolTip = [site.error, saved].compactMap { $0 }.joined(separator: "\n")
        } else { toolTip = nil }
    }
}
final class DetailBody: FlippedView {
    private(set) var site: PanelSite; private(set) var state: PanelState
    private let chart = ChartView(frame: NSRect(x: 20, y: 215, width: 320, height: 90))
    private let liveDot = LiveDot(frame: NSRect(x: 20, y: 18, width: 6, height: 6))
    var onBreakdown: ((String) -> Void)?
    var onDimension: ((DetailDimension) -> Void)?
    var onRetry: (() -> Void)?
    var onToggleRows: (() -> Void)?
    /// Breakdown rows start at `top`; the toggle sits under the visible rows and the footnote under that.
    /// The footnote keeps its old place when there is nothing to expand.
    static func rowsLayout(_ state: PanelState) -> (top: CGFloat, visible: Int, toggle: NSRect?, footnote: CGFloat, height: CGFloat) {
        let top: CGFloat = 405 + (state.breakdown == "utm" || state.breakdown == "location" ? 44 : 0)
        let rows = state.detailLoading || state.detailError != nil ? [] : state.rows ?? []
        let visible = state.detailExpanded ? rows.count : min(5, rows.count)
        var toggle: NSRect?, footnote = top + 5 * 32 + 4
        if rows.count > 5 {
            let rect = NSRect(x: 20, y: top + CGFloat(visible) * 32 + 2, width: 320, height: 28)
            toggle = rect; footnote = rect.maxY + 10
        }
        return (top, visible, toggle, footnote, max(644, footnote + 31))
    }
    init(frame: NSRect, site: PanelSite, state: PanelState) {
        self.site = site; self.state = state; super.init(frame: frame)
        chart.colorIndex = site.color; chart.points = site.points ?? []; addSubview(chart); addSubview(liveDot); placeLiveDot(); addControls()
    }
    private func placeLiveDot() { liveDot.count = site.live }
    func update(site: PanelSite, state: PanelState) {
        self.site = site; self.state = state; chart.colorIndex = site.color; chart.points = site.points ?? []; placeLiveDot()
        subviews.filter { $0 !== chart && $0 !== liveDot }.forEach { $0.removeFromSuperview() }; addControls()
        frame.size.height = Self.rowsLayout(state).height; needsDisplay = true
    }
    private func addControls() {
        for (i, value) in ["pages", "sources", "utm", "location", "events"].enumerated() {
            let b = PaintedButton([L("热门页面"), L("流量来源"), "UTM", L("位置"), L("事件")][i], frame: NSRect(x: 16+CGFloat(i)*66, y: 335, width: 64, height: 30), style: .segment) { [weak self] in self?.onBreakdown?(value) }; b.selected = state.breakdown == value; addSubview(b)
        }
        if state.breakdown == "utm" || state.breakdown == "location" {
            let popup = NSPopUpButton(frame: NSRect(x: 112, y: 378, width: 228, height: 26), pullsDown: false)
            for option in DetailDimension.options(for: state.breakdown) {
                popup.addItem(withTitle: option.title)
                popup.lastItem?.representedObject = option.rawValue
            }
            popup.selectItem(withTitle: state.dimension.title)
            popup.font = .systemFont(ofSize: 10)
            popup.target = self; popup.action = #selector(dimensionChanged(_:))
            popup.setAccessibilityLabel(state.breakdown == "utm" ? L("UTM 字段") : L("位置维度"))
            addSubview(popup)
        }
        if let rect = Self.rowsLayout(state).toggle, let count = state.rows?.count {
            let toggle = PaintedButton(state.detailExpanded ? L("收起") : L("显示全部 %ld 项", count), frame: rect) { [weak self] in self?.onToggleRows?() }
            toggle.setAccessibilityValue(state.detailExpanded ? L("已展开") : L("已收起")); addSubview(toggle)
        }
        if state.detailError != nil {
            let retry = PaintedButton(L("重新加载"), frame: NSRect(x: 122, y: 479, width: 116, height: 30), style: .secondary) { [weak self] in self?.onRetry?() }; addSubview(retry)
        }
    }
    @objc private func dimensionChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String, let value = DetailDimension(rawValue: raw) else { return }
        onDimension?(value)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        text(L("访客数"), NSRect(x: 20, y: 54, width: 120, height: 16), size: 10, color: Ink.secondary)
        text(site.total.map(String.init) ?? "—", NSRect(x: 20, y: 74, width: 190, height: 43), size: 34, weight: .medium)
        // The live strip stands apart from the period stats: it always describes the last 5 minutes.
        let live = NSMutableAttributedString(string: L("当前在线") + " ", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: Ink.secondary])
        live.append(NSAttributedString(string: site.live.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "—", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: (site.live ?? 0) > 0 ? Ink.green : Ink.text]))
        live.append(NSAttributedString(string: " " + L("人"), attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: Ink.secondary]))
        live.draw(at: NSPoint(x: site.live == nil ? 20 : 32, y: 13))
        // Offline data never carries a live count, so explain the dash before blaming the request.
        let hint = site.live != nil ? L("最近 5 分钟 · 30 秒刷新") : site.cached ? L("离线时不显示实时数据") : site.liveFailed ? L("实时数据获取失败") : L("正在获取…")
        text(hint, NSRect(x: 160, y: 15, width: 180, height: 13), size: 9, color: site.live == nil && !site.cached && site.liveFailed ? .systemOrange : Ink.secondary, alignment: .right)
        fill(NSRect(x: 20, y: 38, width: 320, height: 0.5), Ink.line)
        drawGrowth(site, period: state.period, rect: NSRect(x: 185, y: 99, width: 155, height: 16))
        drawStats(site.stats, y: 134)
        fill(NSRect(x: 20, y: 182, width: 320, height: 0.5), Ink.line)
        text(L("会话趋势"), NSRect(x: 20, y: 195, width: 160, height: 17), weight: .semibold)
        text(state.period.hourly ? L("每小时") : L("每天"), NSRect(x: 265, y: 195, width: 75, height: 17), size: 9, color: Ink.secondary, alignment: .right)
        if site.points == nil { text(L("趋势暂无数据"), NSRect(x: 90, y: 248, width: 180, height: 16), color: Ink.secondary, alignment: .center) }
        let formatter = Formats.axis(state.period)
        text(formatter.string(from: state.start), NSRect(x: 20, y: 313, width: 100, height: 14), size: 9, color: Ink.secondary)
        text(formatter.string(from: state.end), NSRect(x: 240, y: 313, width: 100, height: 14), size: 9, color: Ink.secondary, alignment: .right)
        fill(NSRect(x: 20, y: 369, width: 320, height: 0.5), Ink.line)
        let offset: CGFloat = state.breakdown == "utm" || state.breakdown == "location" ? 44 : 0
        if offset > 0 { text(state.breakdown == "utm" ? L("UTM 字段") : L("位置维度"), NSRect(x: 20, y: 385, width: 88, height: 16), size: 10, color: Ink.secondary) }
        text(state.dimension.title, NSRect(x: 20, y: 382+offset, width: 160, height: 15), size: 9, color: Ink.secondary)
        text(L("次数 / 占比"), NSRect(x: 210, y: 382+offset, width: 130, height: 15), size: 9, color: Ink.secondary, alignment: .right)
        if state.detailLoading { text(L("正在加载…"), NSRect(x: 20, y: 417+offset, width: 320, height: 20), color: Ink.secondary, alignment: .center) }
        else if let error = state.detailError { text(error, NSRect(x: 20, y: 411+offset, width: 320, height: 24), size: 10, color: .systemOrange) }
        else if let rows = state.rows, !rows.isEmpty {
            // Shares are of every loaded row, not only the visible ones.
            let sum = rows.reduce(0) { $0 + $1.y }, layout = Self.rowsLayout(state)
            for (i,row) in rows.prefix(layout.visible).enumerated() {
                let y = layout.top + CGFloat(i*32); let ratio = sum > 0 ? row.y/sum : 0
                fill(NSRect(x: 20, y: y, width: 320*ratio, height: 29), Palette.swatch(site.color).base.withAlphaComponent(0.09), radius: 4)
                text(state.dimension.label(for: row.x), NSRect(x: 28, y: y+8, width: 205, height: 15), size: 10)
                text("\(Int(row.y))   \(Int((ratio*100).rounded()))%", NSRect(x: 235, y: y+8, width: 97, height: 15), size: 10, alignment: .right)
            }
        } else { text(L("该时段暂无数据"), NSRect(x: 20, y: 417+offset, width: 320, height: 20), color: Ink.secondary, alignment: .center) }
        // Fewer rows than requested means the list is complete; otherwise shares cover only the loaded rows.
        let loaded = state.rows?.count ?? 0
        let scope = loaded < state.dimension.fetchLimit ? L("占比按全部 %ld 项计算", loaded) : L("占比按前 %ld 项计算", loaded)
        let missing = state.breakdown == "utm" ? L("未携带字段显示「未设置」") : state.breakdown == "location" ? L("缺失位置显示「未知位置」") : nil
        text(missing.map { $0 + " · " + scope } ?? scope, NSRect(x: 20, y: Self.rowsLayout(state).footnote, width: 320, height: 17), size: 9, color: Ink.secondary)
    }
}
