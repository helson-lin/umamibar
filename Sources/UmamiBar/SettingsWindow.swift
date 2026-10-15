import AppKit

/// Standalone settings window drawn with the popover's design system. Unlike the
/// transient popover it stays open while the user switches apps to copy an API key.
final class SettingsWindowController: NSWindowController {
    enum Tab: Int, CaseIterable {
        case connection, websites, general
        var title: String { ["连接", "网站", "通用"][rawValue] }
    }
    /// Persists the verified connection and selected websites; throws if the key cannot be stored.
    var onSave: ((Connection, [Website], [String: Int]) throws -> Void)?
    private let api = API()
    private let panel = SettingsPanel()
    private var tab = Tab.connection
    private var saved: Connection?
    private var candidate: Connection?
    private var available: [Website] = []
    private var chosen: Set<String> = []
    /// Palette index per website ID; kept for deselected sites so re-selecting restores their color.
    private var colors: [String: Int] = [:]
    private var generation = UUID()
    private var busy = false
    private var listError: String?
    private var connectionStatus = ""
    private var connectionFailed = false

    private let server = NSTextField()
    private let key = NSSecureTextField()
    private let search = NSTextField()
    private lazy var serverInput = GlassInput(field: server, frame: NSRect(x: 20, y: SettingsPanel.top + 19, width: 400, height: 38))
    private lazy var keyInput = GlassInput(field: key, frame: NSRect(x: 20, y: SettingsPanel.top + 109, width: 400, height: 38))
    private lazy var searchInput = GlassInput(field: search, frame: NSRect(x: 20, y: SettingsPanel.top, width: 400, height: 38))
    private weak var verify: PaintedButton?
    private weak var save: PaintedButton?
    private weak var list: NSScrollView?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsPanel.width, height: SettingsPanel.height), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = "UmamiBar 设置"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false
        super.init(window: window)
        let material = NSVisualEffectView()
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        window.contentView = material
        panel.frame = material.bounds; panel.autoresizingMask = [.width, .height]; material.addSubview(panel)
        server.placeholderString = "https://api.umami.is/v1"; server.setAccessibilityLabel("Umami 服务地址")
        key.setAccessibilityLabel("API Key"); server.nextKeyView = key; key.nextKeyView = server
        search.placeholderString = "按名称或域名搜索"; search.setAccessibilityLabel("搜索网站")
        searchInput.onChange = { [weak self] in self?.reloadList() }
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func show(_ tab: Tab, connection: Connection?, sites: [Website], colors: [String: Int]) {
        if window?.isVisible != true {
            saved = connection; self.colors = colors; generation = UUID(); busy = false
            candidate = nil; available = []; chosen = Set(sites.map(\.id)); listError = nil; search.stringValue = ""
            server.stringValue = connection?.base.absoluteString ?? "https://api.umami.is/v1"
            key.stringValue = ""; key.placeholderString = connection == nil ? "输入 Umami API Key" : "已保存 · 留空保留当前密钥"
            connectionStatus = ""; connectionFailed = false
            window?.center()
        }
        select(tab)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        if tab == .connection { window?.makeFirstResponder(server) }
    }

    // MARK: Layout

    private func select(_ next: Tab) {
        tab = next; render()
        if next == .websites { websitesAppeared() }
    }
    private func button(_ title: String, _ rect: NSRect, style: PaintedButton.Style = .plain, action: @escaping () -> Void) -> PaintedButton {
        let b = PaintedButton(title, frame: rect, style: style, action: action); panel.addSubview(b); return b
    }
    /// Rebuilds the current tab. The text fields are kept across rebuilds so typed input survives.
    private func render() {
        panel.subviews.forEach { $0.removeFromSuperview() }
        panel.tab = tab
        for item in Tab.allCases {
            let b = button(item.title, NSRect(x: 23 + CGFloat(item.rawValue) * 132, y: 95, width: 131, height: 29), style: .segment) { [weak self] in self?.select(item) }
            b.selected = item == tab; b.setAccessibilityValue(b.selected ? "已选中" : "未选中")
        }
        let top = SettingsPanel.top
        switch tab {
        case .connection:
            panel.addSubview(serverInput); panel.addSubview(keyInput)
            verify = button("验证并选择网站", NSRect(x: 20, y: top + 185, width: 400, height: 36), style: .primary) { [weak self] in self?.verifyConnection() }
            verify?.keyEquivalent = "\r"
        case .websites:
            panel.addSubview(searchInput)
            _ = button("全选", NSRect(x: 16, y: top + 48, width: 40, height: 24)) { [weak self] in self?.selectAllSites() }
            _ = button("取消全选", NSRect(x: 60, y: top + 48, width: 65, height: 24)) { [weak self] in self?.selectNoSites() }
            let scroll = NSScrollView(frame: NSRect(x: 20, y: top + 80, width: 400, height: 164))
            scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
            panel.addSubview(scroll); list = scroll
            save = button("保存并查看", NSRect(x: 20, y: top + 256, width: 400, height: 36), style: .primary) { [weak self] in self?.saveSelection() }
            reloadList()
        case .general:
            _ = button("退出 UmamiBar", NSRect(x: 20, y: top + 104, width: 400, height: 36), style: .destructive) { NSApp.terminate(nil) }
        }
        updateState()
    }
    private func updateState() {
        verify?.title = busy ? "正在验证连接…" : "验证并选择网站"; verify?.isEnabled = !busy
        let count = available.filter { chosen.contains($0.id) }.count
        save?.isEnabled = candidate != nil && count > 0 && !busy
        panel.connectionStatus = connectionStatus; panel.connectionFailed = connectionFailed
        panel.selectionFailed = listError != nil
        panel.selectionStatus = busy ? "正在加载网站…" : listError ?? (available.isEmpty ? "请先在“连接”中验证服务地址和 API Key。" : "已选 \(count) / \(available.count) 个网站")
        panel.needsDisplay = true; verify?.needsDisplay = true; save?.needsDisplay = true
    }

    // MARK: Connection

    private func verifyConnection() {
        do {
            let base = try Connection.baseURL(server.stringValue)
            let typed = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            // Reuse the saved key only for the exact same origin and API path.
            let effective = typed.isEmpty && base == saved?.base ? saved?.key ?? "" : typed
            guard !effective.isEmpty else { throw ServiceError.message("请输入 API Key。") }
            discover(Connection(base: base, key: effective), thenShowWebsites: true)
        } catch { connectionStatus = error.localizedDescription; connectionFailed = true; updateState() }
    }
    private func websitesAppeared() {
        // Opening the window to manage websites lists them with the saved connection.
        if candidate == nil, !busy, listError == nil, let saved = saved { discover(saved, thenShowWebsites: false) }
    }
    private func discover(_ proposed: Connection, thenShowWebsites: Bool) {
        let token = UUID(); generation = token; listError = nil; busy = true
        connectionStatus = "正在验证连接…"; connectionFailed = false; updateState()
        api.websites(connection: proposed) { [weak self] result in
            guard let self = self, self.generation == token else { return }
            self.busy = false
            switch result {
            case .failure(let error): self.listError = error.localizedDescription
            case .success(let sites) where sites.isEmpty: self.listError = "暂无可访问的网站，请添加网站后重试。"
            case .success(let sites):
                // Keep the current selection when re-listing the saved server.
                self.chosen = proposed.base == self.saved?.base ? self.chosen.intersection(sites.map(\.id)) : []
                self.candidate = proposed; self.available = sites; self.pinColors()
                self.connectionStatus = "已连接 · 共 \(sites.count) 个网站"
            }
            if let error = self.listError { self.connectionStatus = error; self.connectionFailed = true }
            if thenShowWebsites && self.listError == nil { self.select(.websites) } else if self.tab == .websites { self.reloadList() } else { self.updateState() }
        }
    }

    // MARK: Websites

    private func selectAllSites() { chosen.formUnion(available.map(\.id)); pinColors(); reloadList() }
    /// Every selected site carries an explicit color, so selecting one site never shifts another's.
    private func pinColors() {
        colors.merge(SiteColors.fill(available.map(\.id).filter(chosen.contains), saved: colors, count: Palette.swatches.count)) { $1 }
    }
    /// Shows the color dot only on selected rows.
    private func attachSwatch(to row: WebsiteChoice) {
        row.subviews.filter { $0 is ColorSwatch }.forEach { $0.removeFromSuperview() }
        let id = row.website.id
        guard chosen.contains(id), let color = colors[id] else { return }
        let swatch = ColorSwatch(color: color, frame: NSRect(x: row.bounds.width - 36, y: 13, width: 26, height: 26))
        swatch.onPick = { [weak self] in self?.colors[id] = $0 }
        row.addSubview(swatch)
    }
    private func selectNoSites() { chosen = []; reloadList() }
    @objc private func toggleSite(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if sender.state == .on { chosen.insert(id); pinColors() } else { chosen.remove(id) }
        if let row = sender as? WebsiteChoice { attachSwatch(to: row) }
        updateState()
    }
    /// Replaces only the list so the search field keeps focus while filtering.
    private func reloadList() {
        guard let scroll = list else { return }
        let query = search.stringValue
        // Keep rows (and their color dots) out of the scroller lane, which overlay scrollers draw over while scrolling.
        let width = scroll.contentSize.width - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let document = FlippedView(); var y: CGFloat = 0
        for site in available where query.isEmpty || (site.name + site.domain).localizedCaseInsensitiveContains(query) {
            let check = WebsiteChoice(site, frame: NSRect(x: 0, y: y, width: width, height: 52), target: self, action: #selector(toggleSite))
            check.state = chosen.contains(site.id) ? .on : .off; attachSwatch(to: check); document.addSubview(check); y += 52
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y, scroll.bounds.height)); scroll.documentView = document
        updateState()
    }
    private func saveSelection() {
        guard let candidate = candidate else { return }
        let selected = available.filter { chosen.contains($0.id) }
        do {
            try onSave?(candidate, selected, SiteColors.fill(selected.map(\.id), saved: colors, count: Palette.swatches.count))
            saved = candidate; key.stringValue = ""
            window?.close()
        } catch { listError = error.localizedDescription; updateState() }
    }
}

/// Painted backdrop and static text for the settings window.
final class SettingsPanel: FlippedView {
    static let width: CGFloat = 440, height: CGFloat = 480, top: CGFloat = 145
    var tab = SettingsWindowController.Tab.connection
    var connectionStatus = "", connectionFailed = false
    var selectionStatus = "", selectionFailed = false
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        drawSurface(bounds, radius: 0)
        fill(NSRect(x: 20, y: 40, width: 32, height: 32), NSColor(white: 0.5, alpha: 0.18), radius: 9)
        for (i, h) in [9.0, 15, 12].enumerated() { fill(NSRect(x: 29 + Double(i) * 5, y: 64 - h, width: 2, height: h), Ink.text, radius: 1) }
        text("UmamiBar 设置", NSRect(x: 62, y: 39, width: 300, height: 18), size: 13, weight: .semibold)
        text("连接、关注的网站与通用选项", NSRect(x: 62, y: 60, width: 300, height: 16), color: Ink.secondary)
        fill(NSRect(x: 20, y: 92, width: 400, height: 35), NSColor(white: Ink.dark ? 0 : 0.2, alpha: Ink.dark ? 0.3 : 0.07), radius: 9)
        let top = Self.top
        switch tab {
        case .connection:
            text("服务地址", NSRect(x: 20, y: top, width: 400, height: 16), color: Ink.secondary)
            text("Umami Cloud 使用 https://api.umami.is/v1；自托管填写站点地址，默认补全 /api。", NSRect(x: 20, y: top + 63, width: 400, height: 15), size: 10, color: Ink.secondary)
            text("API Key", NSRect(x: 20, y: top + 90, width: 400, height: 16), color: Ink.secondary)
            text("密钥仅保存在 macOS 钥匙串。", NSRect(x: 20, y: top + 153, width: 400, height: 15), size: 10, color: Ink.secondary)
            text(connectionStatus, NSRect(x: 20, y: top + 233, width: 400, height: 16), color: connectionFailed ? .systemOrange : Ink.secondary, alignment: .center)
        case .websites:
            text(selectionStatus, NSRect(x: 132, y: top + 52, width: 288, height: 16), size: 10, color: selectionFailed ? .systemOrange : Ink.secondary, alignment: .right)
            fill(NSRect(x: 20, y: top + 80, width: 400, height: 0.5), Ink.line)
            fill(NSRect(x: 20, y: top + 244, width: 400, height: 0.5), Ink.line)
            text("点击色点更改图表颜色 · 取消选择不会删除 Umami 中的网站。", NSRect(x: 20, y: top + 302, width: 400, height: 15), size: 10, color: Ink.secondary, alignment: .center)
        case .general:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            text("UmamiBar", NSRect(x: 20, y: top, width: 400, height: 18), size: 13, weight: .semibold)
            text(version.map { "版本 " + $0 } ?? "开发版本", NSRect(x: 20, y: top + 21, width: 400, height: 16), color: Ink.secondary)
            text("在菜单栏集中查看多个 Umami 网站的访客与趋势。", NSRect(x: 20, y: top + 50, width: 400, height: 16))
            text("API Key 保存在 macOS 钥匙串，网站选择与偏好保存在本地。", NSRect(x: 20, y: top + 70, width: 400, height: 15), size: 10, color: Ink.secondary)
        }
    }
}
