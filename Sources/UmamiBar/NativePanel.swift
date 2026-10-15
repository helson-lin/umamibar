import AppKit

struct PanelSite { let website: Website; let total: Int?; let points: [Point]?; let error: String?; var stats: Stats? = nil; var previousVisitors: Int? = nil }
struct PanelState {
    var screen: String; var loading: Bool
    var period: Period; var start: Date; var end: Date; var updated: String
    var sites: [PanelSite]
    var detailID: String? = nil; var breakdown = "pages"; var rows: [MetricRow]? = nil
    var detailLoading = false; var detailError: String? = nil
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
    override func layout() {
        super.layout()
        if bounds.size != renderedSize, bounds.width > 0, let state = state { render(state) }
    }
    override func cancelOperation(_ sender: Any?) {
        // NSResponder has no cancelOperation(_:) of its own, so calling super would crash; hand Esc up the chain instead.
        if state?.screen == "detail" { action("back") } else { nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender) }
    }
    private func action(_ name: String, _ values: [String: Any] = [:]) { onAction?(name, values) }
    private func button(_ title: String, _ rect: NSRect, style: PaintedButton.Style = .plain, action: @escaping () -> Void) -> PaintedButton {
        let b = PaintedButton(title, frame: rect, style: style, action: action); addSubview(b); return b
    }
    func render(_ next: PanelState) {
        // Data refreshes keep the scroll view and update cards in place, so hover,
        // scroll momentum and in-progress clicks survive; only layout changes rebuild.
        let overviewCards = (overviewScroll?.documentView?.subviews ?? []).compactMap { $0 as? SiteCard }
        let reuseOverview = next.screen == "overview" && previousScreen == "overview" && overviewScroll != nil
            && overviewCards.map(\.layoutKey) == next.sites.map(SiteCard.layoutKey)
        let reuseDetail = next.screen == "detail" && previousScreen == "detail" && next.detailID == previousDetailID && detailScroll?.documentView is DetailBody
        renderedSize = bounds.size
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
            _ = button("打开设置", NSRect(x: 22, y: 104, width: 316, height: 36), style: .primary) { [weak self] in self?.action("settings") }
            _ = button("退出 UmamiBar", NSRect(x: 22, y: 148, width: 316, height: 36), style: .destructive) { [weak self] in self?.action("quit") }
        } else if next.screen == "detail", let selected = next.sites.first(where: { $0.website.id == next.detailID }) {
            let back = button("‹", NSRect(x: 20, y: 20, width: 29, height: 29), style: .navigation) { [weak self] in self?.action("back") }
            back.setAccessibilityLabel("返回网站概览"); back.toolTip = "返回网站概览"
            _ = button("↗", NSRect(x: 310, y: 20, width: 29, height: 29), style: .navigation) { [weak self] in self?.action("dashboard", ["id": selected.website.id]) }
            for p in Period.allCases {
                let b = button(p.title, NSRect(x: 23 + CGFloat(p.rawValue) * 105, y: 79, width: 104, height: 29), style: .segment) { [weak self] in self?.action("period", ["value": p.rawValue]) }; b.selected = p == next.period
            }
            let frame = NSRect(x: 0, y: 145, width: bounds.width, height: max(40, bounds.height - 185))
            if reuseDetail, let scroll = detailScroll, let body = scroll.documentView as? DetailBody {
                scroll.frame = frame; body.update(site: selected, state: next)
            } else {
                let scroll = NSScrollView(frame: frame)
                scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
                let body = DetailBody(frame: NSRect(x: 0, y: 0, width: 360, height: 566), site: selected, state: next)
                body.onBreakdown = { [weak self] value in self?.action("breakdown", ["value": value]) }
                body.onRetry = { [weak self] in self?.action("detailRetry") }
                scroll.documentView = body; addSubview(scroll); detailScroll = scroll
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(detailOffset.y, max(0, body.bounds.height-scroll.bounds.height)))); scroll.reflectScrolledClipView(scroll.contentView)
            }
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
                    let height: CGFloat = 218 + (site.error == nil ? 0 : 30)
                    let card = SiteCard(frame: NSRect(x: 0, y: y, width: 360, height: height), site: site, index: i, state: next)
                    card.open = { [weak self] in self?.action("detail", ["id": site.website.id]) }; document.addSubview(card); y += height
                }
                document.frame = NSRect(x: 0, y: 0, width: 360, height: max(scroll.bounds.height, y)); scroll.documentView = document; addSubview(scroll); overviewScroll = scroll
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(overviewOffset.y, max(0, y-scroll.bounds.height)))); scroll.reflectScrolledClipView(scroll.contentView)
            }
            _ = button("管理网站", NSRect(x: 272, y: bounds.height - 34, width: 70, height: 26)) { [weak self] in self?.action("manage") }
        }
        previousScreen = next.screen; needsDisplay = true
        // The header text is drawn in draw(_:), not by subviews; render it now so it slides with its screen.
        if transitioned { displayIfNeeded() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        drawSurface(bounds, radius: 18)
        guard let s = state else { return }
        if s.screen == "empty" {
            text("连接 Umami", NSRect(x: 22, y: 22, width: 300, height: 22), size: 15, weight: .semibold)
            text("在设置中填写服务地址和 API Key，并选择要关注的网站。", NSRect(x: 22, y: 55, width: 316, height: 32), color: Ink.secondary)
        } else if s.screen == "detail", let site = s.sites.first(where: { $0.website.id == s.detailID }) {
            text(site.website.name, NSRect(x: 60, y: 19, width: 240, height: 18), size: 13, weight: .semibold)
            text(site.website.domain, NSRect(x: 60, y: 40, width: 240, height: 16), size: 10, color: Ink.secondary)
            fill(NSRect(x: 20, y: 76, width: 320, height: 35), NSColor(white: Ink.dark ? 0 : 0.2, alpha: Ink.dark ? 0.3 : 0.07), radius: 9)
            text(Formats.range.string(from: s.start) + " — " + Formats.range.string(from: s.end), NSRect(x: 21, y: 123, width: 300, height: 15), size: 10, color: Ink.secondary)
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
            text(Formats.range.string(from: s.start) + " — " + Formats.range.string(from: s.end), NSRect(x: 21, y: 123, width: 235, height: 15), size: 10, color: Ink.secondary)
            text(TimeZone.current.abbreviation() ?? "", NSRect(x: 262, y: 123, width: 76, height: 15), size: 10, color: Ink.secondary, alignment: .right)
            let footerTop = bounds.height - 40
            let shade = NSGradient(starting: NSColor.black.withAlphaComponent(Ink.dark ? 0.11 : 0.035), ending: .clear)
            shade?.draw(in: NSRect(x: 0, y: footerTop - 6, width: bounds.width, height: 6), angle: 270)
            fill(NSRect(x: 0, y: footerTop, width: bounds.width, height: 0.5), Ink.line)
            fill(NSRect(x: 0, y: footerTop + 0.5, width: bounds.width, height: 0.5), NSColor.white.withAlphaComponent(Ink.dark ? 0.025 : 0.8))
            fill(NSRect(x: 21, y: bounds.height-22, width: 4, height: 4), Ink.green, radius: 2)
            text(s.loading ? "正在刷新 \(s.sites.count) 个网站…" : s.updated, NSRect(x: 30, y: bounds.height-28, width: 230, height: 17), size: 10, color: Ink.secondary)
        }
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
    private var site: PanelSite; private let index: Int; private var state: PanelState
    private let chart = ChartView(frame: NSRect(x: 20, y: 74, width: 320, height: 65))
    var open: (() -> Void)?
    /// Cards can be updated in place only while the website and card height stay the same.
    static func layoutKey(_ site: PanelSite) -> String { site.website.id + (site.error == nil ? "" : "#error") }
    var layoutKey: String { Self.layoutKey(site) }
    init(frame: NSRect, site: PanelSite, index: Int, state: PanelState) {
        self.site = site; self.index = index; self.state = state; super.init(frame: frame)
        let openButton = PaintedButton("", frame: NSRect(x: 18, y: 12, width: 220, height: 40)) { [weak self] in self?.open?() }; openButton.toolTip = "查看 \(site.website.name) 详情"; openButton.setAccessibilityLabel("查看 \(site.website.name) 详情"); addSubview(openButton)
        chart.points = site.points ?? []; chart.colorIndex = index; chart.showsScale = false
        chart.onClick = { [weak self] in self?.open?() }; chart.setAccessibilityLabel("查看 \(site.website.name) 详情"); addSubview(chart)
    }
    func update(site: PanelSite, state: PanelState) { self.site = site; self.state = state; chart.points = site.points ?? []; needsDisplay = true }
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
            let formatter = Formats.axis(state.period)
            for (i,date) in [state.start, Date(timeIntervalSince1970: (state.start.timeIntervalSince1970+state.end.timeIntervalSince1970)/2),state.end].enumerated() { text(formatter.string(from: date), NSRect(x: 20+CGFloat(i)*106, y: 145, width: 106, height: 14), size: 9, color: Ink.secondary, alignment: i == 0 ? .left : i == 2 ? .right : .center) }
        }
        drawStats(site.stats, y: 171)
        if let error = site.error { text("更新失败 · " + error, NSRect(x: 20, y: bounds.height-25, width: 320, height: 24), size: 10, color: .systemOrange) }
    }
}
final class DetailBody: FlippedView {
    private(set) var site: PanelSite; private(set) var state: PanelState
    private let chart = ChartView(frame: NSRect(x: 20, y: 181, width: 320, height: 90))
    var onBreakdown: ((String) -> Void)?
    var onRetry: (() -> Void)?
    init(frame: NSRect, site: PanelSite, state: PanelState) {
        self.site = site; self.state = state; super.init(frame: frame)
        chart.points = site.points ?? []; addSubview(chart); addControls()
    }
    func update(site: PanelSite, state: PanelState) {
        self.site = site; self.state = state; chart.points = site.points ?? []
        subviews.filter { $0 !== chart }.forEach { $0.removeFromSuperview() }; addControls(); needsDisplay = true
    }
    private func addControls() {
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
        let formatter = Formats.axis(state.period)
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
