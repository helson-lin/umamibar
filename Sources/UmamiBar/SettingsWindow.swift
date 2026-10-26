import AppKit

final class SettingsWindowController: NSWindowController {
    enum Tab: Int, CaseIterable {
        case connection, websites, general
        var title: String { [L("连接"), L("网站"), L("通用")][rawValue] }
    }
    var onCheckForUpdates: (() -> Void)?
    var onSave: ((Connection, [Website], [String: Int]) throws -> Void)?
    private let api = API()
    private let preferences: Preferences
    private let snapshots: SnapshotStore
    private let login: LoginLaunch
    private let panel = SettingsPanel()
    private var tab = Tab.connection
    private var saved: Connection?, candidate: Connection?
    private var available: [Website] = [], chosen = Set<String>(), colors: [String: Int] = [:]
    private var layout = WebsiteLayout()
    private var generation = UUID(), busy = false, needsConnectionCommit = false
    private var listError: String?, connectionStatus = "", connectionFailed = false, footerStatus = ""
    private var generalError: String?
    private enum Confirmation { case clear, disable }
    private var confirmation: Confirmation?
    private var showingSavedData = false
    private var pendingFocus: (String, String)?
    private var observers: [NSObjectProtocol] = []
    private let server = NSTextField(), key = NSSecureTextField(), search = NSTextField()
    private lazy var serverInput = GlassInput(field: server, frame: NSRect(x: 0, y: 0, width: 400, height: 38))
    private lazy var keyInput = GlassInput(field: key, frame: NSRect(x: 0, y: 0, width: 400, height: 38))
    private lazy var searchInput = GlassInput(field: search, frame: NSRect(x: 0, y: 0, width: 400, height: 34))
    private weak var contentScroll: NSScrollView?, list: NSScrollView?
    private weak var verify: PaintedButton?, save: PaintedButton?
    private weak var selectionLabel: NSTextField?, footerLabel: NSTextField?

    init(preferences: Preferences = .shared, snapshots: SnapshotStore = .shared, login: LoginLaunch = LoginLaunch()) {
        self.preferences = preferences; self.snapshots = snapshots; self.login = login
        let height = min(SettingsPanel.height, (NSScreen.main?.visibleFrame.height ?? 760) - 60)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsPanel.width, height: height), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false
        super.init(window: window)
        let material = NSVisualEffectView()
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active; window.contentView = material
        panel.frame = material.bounds; panel.autoresizingMask = [.width, .height]; material.addSubview(panel)
        panel.onCancel = { [weak self] in
            guard let self = self else { return }
            if self.confirmation != nil { self.confirmation = nil; self.render() } else { self.window?.performClose(nil) }
        }
        key.setAccessibilityLabel("API Key"); server.nextKeyView = key; key.nextKeyView = server
        searchInput.onChange = { [weak self] in self?.reloadList() }
        applyStrings(); render()
        observers.append(NotificationCenter.default.addObserver(forName: Localization.changed, object: nil, queue: .main) { [weak self] _ in self?.applyStrings(); self?.render() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true, self.tab == .general else { return }; self.render()
        })
        observers.append(NotificationCenter.default.addObserver(forName: SnapshotStore.changed, object: snapshots, queue: .main) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true, self.tab == .general else { return }; self.render()
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    private func applyStrings() {
        window?.title = L("UmamiBar 设置"); server.setAccessibilityLabel(L("Umami 服务地址"))
        search.placeholderString = L("搜索网站名称或域名"); search.setAccessibilityLabel(L("搜索网站"))
        key.placeholderString = saved == nil ? L("输入 Umami API Key") : L("已保存 · 留空保留当前密钥")
    }
    func show(_ tab: Tab, connection: Connection?, sites: [Website], colors: [String: Int]) {
        if window?.isVisible != true {
            saved = connection
            self.colors = (preferences.defaults.dictionary(forKey: SiteColors.key) as? [String: Int] ?? [:]).merging(colors, uniquingKeysWith: { _, new in new })
            generation = UUID(); busy = false
            candidate = nil; available = sites; chosen = Set(sites.map(\.id)); listError = nil; search.stringValue = ""
            server.stringValue = connection?.base.absoluteString ?? "https://api.umami.is/v1"
            key.stringValue = ""; connectionStatus = ""; connectionFailed = false; generalError = nil
            needsConnectionCommit = false; confirmation = nil; showingSavedData = false; footerStatus = ""
            if let base = connection?.base { layout = preferences.layout(for: base, available: sites.map(\.id)) }
            applyStrings(); window?.center()
        }
        select(tab); NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil)
        if tab == .connection { window?.makeFirstResponder(server) }
    }
    private func select(_ next: Tab) {
        tab = next; contentScroll?.contentView.scroll(to: .zero); render()
        if next == .websites { websitesAppeared() }
    }
    @discardableResult
    private func button(_ title: String, _ frame: NSRect, in parent: NSView, style: PaintedButton.Style = .plain, action: @escaping () -> Void) -> PaintedButton {
        let b = PaintedButton(title, frame: frame, style: style, action: action); parent.addSubview(b); return b
    }
    private func render() {
        let offset = contentScroll?.contentView.bounds.origin ?? .zero
        panel.subviews.forEach { $0.removeFromSuperview() }
        panel.tab = tab
        for item in Tab.allCases {
            let b = button(item.title, NSRect(x: 94 + CGFloat(item.rawValue) * 84, y: 52, width: 84, height: 28), in: panel, style: .segment) { [weak self] in self?.select(item) }
            b.selected = item == tab; b.setAccessibilityValue(b.selected ? L("已选中") : L("未选中"))
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 108, width: 440, height: max(100, panel.bounds.height - 150)))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
        scroll.autoresizingMask = [.width, .height]; panel.addSubview(scroll); contentScroll = scroll
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 440, height: scroll.bounds.height))
        scroll.documentView = document
        switch tab {
        case .connection: renderConnection(in: document)
        case .websites: renderWebsites(in: document)
        case .general: renderGeneral(in: document)
        }
        document.frame.size.height = max(document.bounds.height, scroll.bounds.height)
        let maxOffset = max(0, document.bounds.height-scroll.bounds.height)
        let destination = tab == .general && (confirmation != nil || showingSavedData) ? maxOffset : min(offset.y, maxOffset)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: destination))
        scroll.reflectScrolledClipView(scroll.contentView)
        footerLabel = settingsLabel(footerStatus.isEmpty ? L("更改自动保存") : footerStatus, in: panel, frame: NSRect(x: 20, y: panel.bounds.height - 28, width: 248, height: 18), size: 10, color: .secondaryLabelColor)
        _ = button(L("检查更新…"), NSRect(x: 276, y: panel.bounds.height - 33, width: 100, height: 26), in: panel) { [weak self] in self?.onCheckForUpdates?() }
        _ = button(L("退出"), NSRect(x: 384, y: panel.bounds.height - 33, width: 38, height: 26), in: panel, style: .destructive) { NSApp.terminate(nil) }
        updateState(); panel.needsDisplay = true
    }
    private func renderConnection(in body: FlippedView) {
        settingsLabel(L("服务地址"), in: body, frame: NSRect(x: 20, y: 20, width: 400, height: 18))
        serverInput.frame = NSRect(x: 20, y: 45, width: 400, height: 38); body.addSubview(serverInput)
        settingsLabel(L("Umami Cloud 使用 https://api.umami.is/v1；自托管填写站点地址，默认补全 /api。"), in: body, frame: NSRect(x: 20, y: 91, width: 400, height: 36), size: 10, color: .secondaryLabelColor)
        settingsLabel("API Key", in: body, frame: NSRect(x: 20, y: 140, width: 400, height: 18))
        keyInput.frame = NSRect(x: 20, y: 165, width: 400, height: 38); body.addSubview(keyInput)
        settingsLabel(L("密钥仅保存在 macOS 钥匙串。"), in: body, frame: NSRect(x: 20, y: 211, width: 400, height: 18), size: 10, color: .secondaryLabelColor)
        verify = button(L("验证并选择网站"), NSRect(x: 20, y: 254, width: 400, height: 36), in: body, style: .primary) { [weak self] in self?.verifyConnection() }
        verify?.keyEquivalent = "\r"
        selectionLabel = settingsLabel(connectionStatus, in: body, frame: NSRect(x: 20, y: 308, width: 400, height: 58), size: 11, color: connectionFailed ? .systemOrange : .secondaryLabelColor)
        body.frame.size.height = 386
    }
    private func renderWebsites(in body: FlippedView) {
        searchInput.frame = NSRect(x: 20, y: 20, width: 400, height: 34); body.addSubview(searchInput)
        selectionLabel = settingsLabel("", in: body, frame: NSRect(x: 22, y: 69, width: 220, height: 18), size: 10, color: .secondaryLabelColor)
        let allTitle = L("全选"), noneTitle = L("取消全选")
        let allWidth = ceil((allTitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width) + 12
        let noneWidth = ceil((noneTitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width) + 12
        let all = button(allTitle, NSRect(x: 420-noneWidth-allWidth-6, y: 64, width: allWidth, height: 26), in: body) { [weak self] in self?.selectAllSites() }
        let none = button(noneTitle, NSRect(x: 420-noneWidth, y: 64, width: noneWidth, height: 26), in: body) { [weak self] in self?.selectNoSites() }
        all.isEnabled = candidate != nil && !busy; none.isEnabled = all.isEnabled
        let needsButton = needsConnectionCommit || listError != nil
        let listHeight = max(100, body.bounds.height - (needsButton ? 206 : 154))
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 100, width: 400, height: listHeight))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; body.addSubview(scroll); list = scroll
        settingsLabel(L("勾选以关注，拖动排序；图钉可置顶。"), in: body, frame: NSRect(x: 32, y: scroll.frame.maxY + 10, width: 376, height: 16), size: 10, color: .secondaryLabelColor)
        settingsLabel(L("取消关注不会删除 Umami 中的网站。"), in: body, frame: NSRect(x: 32, y: scroll.frame.maxY + 28, width: 376, height: 16), size: 10, color: .secondaryLabelColor)
        if needsButton {
            let title = candidate == nil ? L("重新加载网站") : needsConnectionCommit ? L("保存并查看") : L("重试保存")
            save = button(title, NSRect(x: 20, y: scroll.frame.maxY + 58, width: 400, height: 34), in: body, style: .primary) { [weak self] in
                guard let self = self else { return }
                if self.candidate == nil { self.listError = nil; self.websitesAppeared(); self.render() }
                else { self.saveSelection(close: self.needsConnectionCommit) }
            }
        }
        reloadList()
    }
    private func group(_ title: String, rows: Int, at y: CGFloat, in body: NSView) -> SettingsGroupView {
        settingsLabel(title, in: body, frame: NSRect(x: 32, y: y, width: 360, height: 16), size: 11, color: .secondaryLabelColor)
        let group = SettingsGroupView(frame: NSRect(x: 20, y: y + 24, width: 400, height: CGFloat(rows)*44), rows: rows)
        body.addSubview(group); return group
    }
    private func rowLabel(_ title: String, row: Int, in box: NSView) {
        settingsLabel(title, in: box, frame: NSRect(x: 12, y: CGFloat(row)*44 + 13, width: 200, height: 20), size: 12)
    }
    @discardableResult
    private func note(_ value: String, at y: CGFloat, in body: NSView) -> CGFloat {
        let measured = (value as NSString).boundingRect(with: NSSize(width: 376, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 10)]).height
        let height = max(18, ceil(measured))
        settingsLabel(value, in: body, frame: NSRect(x: 32, y: y, width: 376, height: height), size: 10, color: .secondaryLabelColor)
        return height
    }
    private func renderGeneral(in body: FlippedView) {
        var y: CGFloat = 20
        let common = group(L("常规"), rows: 2, at: y, in: body)
        rowLabel(L("登录时启动"), row: 0, in: common)
        let status = login.status
        let toggle = ActionSwitch(frame: NSRect(x: 355, y: 12, width: 32, height: 22), label: L("登录时启动"), enabled: status == .enabled) { [weak self] enabled in
            guard let self = self else { return }
            do { try self.login.setEnabled(enabled); self.generalError = nil }
            catch { self.generalError = error.localizedDescription }
            self.render()
        }
        toggle.isEnabled = status != .unavailable && status != .requiresApproval; common.addSubview(toggle)
        rowLabel(L("语言"), row: 1, in: common)
        common.addSubview(ActionPopup(frame: NSRect(x: 210, y: 52, width: 178, height: 28), label: L("语言"), choices: [("", L("跟随系统")), ("zh-Hans", "简体中文"), ("en", "English")], selected: Localization.choice) { Localization.set($0) })
        y = common.frame.maxY + 8
        let launchNote = status == .unavailable ? L("请从已安装的 UmamiBar.app 设置登录启动。") : L("登录后仅在菜单栏运行，不自动打开窗口。")
        y += note(launchNote, at: y, in: body) + 20
        if status == .requiresApproval {
            _ = button(L("登录启动已被系统停用 · 前往系统设置开启 ↗"), NSRect(x: 24, y: y-16, width: 392, height: 28), in: body) { [weak self] in self?.login.openSystemSettings() }; y += 20
        }
        let mode = preferences.menuDisplay
        let menu = group(L("菜单栏"), rows: mode.single ? 2 : 1, at: y, in: body)
        rowLabel(L("显示内容"), row: 0, in: menu)
        let popup = ActionPopup(frame: NSRect(x: 210, y: 8, width: 178, height: 28), label: L("显示内容"), choices: MenuDisplay.allCases.map { ($0.rawValue, $0.title) }, selected: mode.rawValue) { [weak self] raw in
            guard let self = self, let mode = MenuDisplay(rawValue: raw) else { return }
            if mode.single, !self.chosen.contains(self.preferences.menuWebsiteID ?? "") { self.preferences.menuWebsiteID = self.layout.sorted(self.available.filter { self.chosen.contains($0.id) }).first?.id }
            self.preferences.menuDisplay = mode; self.render()
        }
        popup.itemArray.filter { MenuDisplay(rawValue: $0.representedObject as? String ?? "")?.single == true }.forEach { $0.isEnabled = !chosen.isEmpty }
        menu.addSubview(popup)
        if mode.single {
            rowLabel(L("指定网站"), row: 1, in: menu)
            menu.addSubview(ActionPopup(frame: NSRect(x: 210, y: 52, width: 178, height: 28), label: L("指定网站"), choices: layout.sorted(available.filter { chosen.contains($0.id) }).map { ($0.id, $0.name) }, selected: preferences.menuWebsiteID ?? "") { [weak self] id in self?.preferences.menuWebsiteID = id })
        }
        let menuNote: String
        switch mode {
        case .icon: menuNote = L("隐藏数字，保留菜单栏入口。")
        case .website: menuNote = L("所选网站 · 跟随概览的时间范围")
        case .websiteLive: menuNote = L("所选网站 · 最近 5 分钟内的访客 · 每分钟更新")
        case .live: menuNote = L("全部已选网站 · 最近 5 分钟内的访客 · 每分钟更新 · 跨站未去重")
        case .total: menuNote = L("全部已选网站 · 当前时间范围 · 跨站未去重")
        }
        y = menu.frame.maxY + 8; y += note(menuNote, at: y, in: body) + 20
        let data = group(L("本地数据"), rows: 2, at: y, in: body)
        rowLabel(L("保留最近成功数据"), row: 0, in: data)
        data.addSubview(ActionSwitch(frame: NSRect(x: 355, y: 12, width: 32, height: 22), label: L("保留最近成功数据"), enabled: preferences.retainData) { [weak self] enabled in
            guard let self = self else { return }
            if enabled { self.preferences.retainData = true } else { self.confirmation = .disable }
            self.render()
        })
        rowLabel(L("已保存数据"), row: 1, in: data)
        let stored = saved.map { snapshots.allRecords(base: $0.base) } ?? []
        let latest = stored.map(\.savedAt).max()
        let summary = preferences.retainData ? latest.map { L("%@ · %ld 个网站 ›", Formats.time.string(from: $0), Set(stored.map(\.websiteID)).count) } ?? L("尚无已保存数据") : L("本地保存已关闭")
        let details = button(summary, NSRect(x: 176, y: 49, width: 212, height: 32), in: data) { [weak self] in self?.showingSavedData.toggle(); self?.render() }
        details.identifier = NSUserInterfaceItemIdentifier("savedDataDetails"); details.setAccessibilityLabel(L("查看与管理已保存数据")); details.isEnabled = latest != nil
        y = data.frame.maxY + 8
        y += note(L("离线时查看上次结果。仅存于本机，不包含密钥。"), at: y, in: body) + 12
        if showingSavedData {
            for period in Period.allCases {
                let values = stored.filter { $0.period == period.rawValue }
                guard let latest = values.max(by: { $0.savedAt < $1.savedAt }) else { continue }
                settingsLabel(L("%@ · %ld 个网站", period.title, values.count), in: body, frame: NSRect(x: 32, y: y, width: 376, height: 18), size: 11)
                settingsLabel(Formats.range.string(from: latest.start) + " — " + Formats.range.string(from: latest.end), in: body, frame: NSRect(x: 32, y: y+20, width: 376, height: 18), size: 10, color: .secondaryLabelColor); y += 46
            }
            _ = button(L("清除已保存数据…"), NSRect(x: 218, y: y, width: 194, height: 30), in: body, style: .secondary) { [weak self] in self?.confirmation = .clear; self?.render() }; y += 42
        }
        if let confirmation = confirmation {
            let box = SettingsGroupView(frame: NSRect(x: 20, y: y, width: 400, height: 114), rows: 1); body.addSubview(box)
            settingsLabel(confirmation == .disable ? L("关闭并清除已保存数据？") : L("清除已保存的网站数据？"), in: box, frame: NSRect(x: 12, y: 10, width: 376, height: 20), size: 12, weight: .medium)
            settingsLabel(L("连接、API Key、网站顺序和偏好都会保留。"), in: box, frame: NSRect(x: 12, y: 36, width: 376, height: 32), size: 10, color: .secondaryLabelColor)
            _ = button(L("取消"), NSRect(x: 210, y: 76, width: 56, height: 28), in: box) { [weak self] in self?.confirmation = nil; self?.render() }
            _ = button(confirmation == .disable ? L("关闭并清除") : L("清除数据"), NSRect(x: 272, y: 76, width: 116, height: 28), in: box, style: .destructive) { [weak self] in self?.clearSavedData() }; y += 126
        }
        if let error = generalError ?? snapshots.lastError {
            settingsLabel(error, in: body, frame: NSRect(x: 32, y: y, width: 376, height: 48), size: 11, color: .systemOrange); y += 56
        }
        body.frame.size.height = y + 6
    }
    private func clearSavedData() {
        do {
            if confirmation == .disable { try snapshots.clear(); preferences.retainData = false }
            else { try snapshots.clear(base: saved?.base) }
            confirmation = nil; showingSavedData = false; generalError = nil; footerStatus = L("已清除统计数据，连接与偏好已保留。")
        } catch { generalError = snapshots.lastError ?? error.localizedDescription }
        render()
    }
    private func updateState() {
        verify?.title = busy ? L("正在验证连接…") : L("验证并选择网站"); verify?.isEnabled = !busy
        save?.isEnabled = (candidate != nil || saved != nil && listError != nil) && (!needsConnectionCommit || !chosen.isEmpty) && !busy
        let value = busy ? L("正在加载网站…") : listError ?? L("已关注 %ld / %ld 个网站", chosen.count, available.count)
        if tab == .websites { selectionLabel?.stringValue = value; selectionLabel?.toolTip = value; selectionLabel?.textColor = listError == nil ? .secondaryLabelColor : .systemOrange }
        else if tab == .connection { selectionLabel?.stringValue = connectionStatus; selectionLabel?.textColor = connectionFailed ? .systemOrange : .secondaryLabelColor }
        footerLabel?.stringValue = tab == .connection ? L("验证成功后，选择网站并保存。") : footerStatus.isEmpty ? (needsConnectionCommit ? L("验证成功后，选择网站并保存。") : L("更改自动保存")) : footerStatus
    }
    private func verifyConnection() {
        do {
            let base = try Connection.baseURL(server.stringValue)
            let typed = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let effective = typed.isEmpty && base == saved?.base ? saved?.key ?? "" : typed
            guard !effective.isEmpty else { throw ServiceError.message(L("请输入 API Key。")) }
            discover(Connection(base: base, key: effective), thenShowWebsites: true)
        } catch { connectionStatus = error.localizedDescription; connectionFailed = true; updateState() }
    }
    private func websitesAppeared() {
        if candidate == nil, !busy, listError == nil, let saved = saved { discover(saved, thenShowWebsites: false) }
    }
    private func discover(_ proposed: Connection, thenShowWebsites: Bool) {
        let token = UUID(); generation = token; listError = nil; busy = true
        connectionStatus = L("正在验证连接…"); connectionFailed = false; updateState()
        api.websites(connection: proposed) { [weak self] result in
            guard let self = self, self.generation == token else { return }
            self.busy = false
            var removedSelection = false
            switch result {
            case .failure(let error): self.listError = error.localizedDescription
            case .success(let sites) where sites.isEmpty: self.listError = L("暂无可访问的网站，请添加网站后重试。")
            case .success(let sites):
                let oldSelection = self.chosen
                self.chosen = proposed.base == self.saved?.base ? self.chosen.intersection(sites.map(\.id)) : []
                removedSelection = oldSelection != self.chosen
                self.candidate = proposed; self.available = sites
                self.layout = self.preferences.layout(for: proposed.base, available: sites.map(\.id))
                self.needsConnectionCommit = proposed.base != self.saved?.base || proposed.key != self.saved?.key
                self.pinColors(); self.connectionStatus = L("已连接 · 共 %ld 个网站", sites.count)
            }
            if let error = self.listError { self.connectionStatus = error; self.connectionFailed = true }
            if thenShowWebsites && self.listError == nil { self.select(.websites) }
            else if self.tab == .websites { self.render() } else { self.updateState() }
            if removedSelection && !self.needsConnectionCommit && self.listError == nil { self.saveSelection(close: false) }
        }
    }
    private func pinColors() {
        colors.merge(SiteColors.fill(available.map(\.id).filter(chosen.contains), saved: colors, count: Palette.swatches.count)) { $1 }
    }
    private func selectAllSites() { guard candidate != nil, !busy else { return }; chosen = Set(available.map(\.id)); pinColors(); changedSelection() }
    private func selectNoSites() { guard candidate != nil, !busy else { return }; chosen = []; changedSelection() }
    private func changedSelection() {
        if !needsConnectionCommit, candidate != nil { saveSelection(close: false) }
        else { reloadList() }
    }
    private func reloadList() {
        guard let scroll = list else { return }
        let offset = scroll.contentView.bounds.origin
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = layout.sorted(available).filter { query.isEmpty || ($0.name + $0.domain).localizedCaseInsensitiveContains(query) }
        let groups = [(L("置顶"), matched.filter { chosen.contains($0.id) && layout.pinned.contains($0.id) }), (L("其他网站"), matched.filter { chosen.contains($0.id) && !layout.pinned.contains($0.id) }), (L("未关注"), matched.filter { !chosen.contains($0.id) })]
        let width = scroll.contentSize.width - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let document = FlippedView(); var y: CGFloat = 0
        for (title, sites) in groups where !sites.isEmpty {
            if y > 0 { y += 16 }
            settingsLabel(title, in: document, frame: NSRect(x: 12, y: y, width: width - 50, height: 16), size: 10, color: .secondaryLabelColor)
            let count = settingsLabel(String(sites.count), in: document, frame: NSRect(x: width - 42, y: y, width: 30, height: 16), size: 10, color: .secondaryLabelColor); count.alignment = .right
            y += 24
            let group = SettingsGroupView(frame: NSRect(x: 0, y: y, width: width, height: CGFloat(sites.count) * 54), rows: 1); document.addSubview(group)
            for (index, site) in sites.enumerated() {
                let row = WebsiteSettingsRow(frame: NSRect(x: 0, y: CGFloat(index)*54, width: width, height: 54), website: site, selected: chosen.contains(site.id), pinned: layout.pinned.contains(site.id), color: colors[site.id] ?? 0, draggable: query.isEmpty && candidate != nil && !busy, canMoveUp: query.isEmpty && index > 0, canMoveDown: query.isEmpty && index < sites.count-1, onToggle: { [weak self] selected in
                    guard let self = self else { return }; if selected { self.chosen.insert(site.id); self.pinColors() } else { self.chosen.remove(site.id) }; self.pendingFocus = (site.id, "select"); self.changedSelection()
                }, onPin: { [weak self] in self?.layout.togglePin(site.id); self?.pendingFocus = (site.id, "pin"); self?.changedSelection() }, onMove: { [weak self] delta in
                    guard let self = self else { return }; if self.layout.move(site.id, by: delta, selected: self.chosen) { self.pendingFocus = (site.id, delta < 0 ? "⌃" : "⌄"); self.changedSelection() }
                }, onColor: { [weak self] color in self?.colors[site.id] = color; self?.pendingFocus = (site.id, "color"); self?.changedSelection() })
                if candidate == nil || busy { row.subviews.compactMap { $0 as? NSControl }.forEach { $0.isEnabled = false } }
                row.canDrop = { [weak self] id in
                    guard let self = self else { return false }
                    return self.candidate != nil && !self.busy && query.isEmpty && id != site.id && self.chosen.contains(id) && self.chosen.contains(site.id) && self.layout.pinned.contains(id) == self.layout.pinned.contains(site.id)
                }
                row.onDrop = { [weak self] id, after in
                    guard let self = self else { return }; if self.layout.place(id, relativeTo: site.id, after: after, selected: self.chosen) { self.changedSelection() }
                }
                group.addSubview(row)
            }
            y += group.bounds.height
        }
        if matched.isEmpty {
            let message = busy ? L("正在加载网站…") : listError ?? (query.isEmpty ? L("请先在“连接”中验证服务地址和 API Key。") : L("没有匹配的网站"))
            settingsLabel(message, in: document, frame: NSRect(x: 12, y: 28, width: width - 24, height: 72), size: 11, color: .secondaryLabelColor)
            _ = button(query.isEmpty ? L("前往连接设置") : L("清空搜索"), NSRect(x: 80, y: 112, width: width - 160, height: 30), in: document, style: .secondary) { [weak self] in
                guard let self = self else { return }; if query.isEmpty { self.select(.connection) } else { self.search.stringValue = ""; self.reloadList(); self.window?.makeFirstResponder(self.search) }
            }; y = 166
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(scroll.bounds.height, y)); scroll.documentView = document
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset.y, max(0, y - scroll.bounds.height)))); scroll.reflectScrolledClipView(scroll.contentView)
        if let (id, kind) = pendingFocus {
            let rows = document.subviews.flatMap { $0.subviews }.compactMap { $0 as? WebsiteSettingsRow }
            if let row = rows.first(where: { $0.website.id == id }) {
                let target = row.subviews.first { view in
                    if kind == "select" { return view is CallbackCheckbox }
                    if kind == "pin" { return view is PinButton }
                    if kind == "color" { return view is ColorSwatch }
                    return (view as? PaintedButton)?.title == kind && (view as? PaintedButton)?.isEnabled == true
                } ?? row.subviews.first { $0 is CallbackCheckbox }
                if let target = target { window?.makeFirstResponder(target) }
            }
            pendingFocus = nil
        }
        updateState()
        if !query.isEmpty && listError == nil { selectionLabel?.stringValue = L("找到 %ld 个网站 · 搜索时暂停排序", matched.count) }
    }
    private func saveSelection(close: Bool) {
        guard let candidate = candidate else { return }
        let selected = available.filter { chosen.contains($0.id) }
        guard !needsConnectionCommit || !selected.isEmpty else { return }
        let oldMode = preferences.menuDisplay
        do {
            try onSave?(candidate, selected, SiteColors.fill(selected.map(\.id), saved: colors, count: Palette.swatches.count))
            preferences.setLayout(layout, for: candidate.base)
            _ = preferences.reconcileMenuSource(selected: selected.map(\.id))
            saved = candidate; key.stringValue = ""; needsConnectionCommit = false; listError = nil
            footerStatus = oldMode.single && preferences.menuDisplay == .total ? L("数字来源已取消关注，已改为合计访客。") : L("已保存")
            if close { window?.close() } else { reloadList() }
        } catch { listError = error.localizedDescription; footerStatus = L("保存失败，请重试。"); render() }
    }
}

final class SettingsPanel: FlippedView {
    static let width: CGFloat = 440, height: CGFloat = 640
    var tab = SettingsWindowController.Tab.connection
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        drawSurface(bounds, radius: 0)
        text(L("UmamiBar 设置"), NSRect(x: 82, y: 15, width: 276, height: 19), size: 12, weight: .semibold, alignment: .center)
        fill(NSRect(x: 91, y: 49, width: 258, height: 34), NSColor(white: Ink.dark ? 0 : 0.2, alpha: Ink.dark ? 0.3 : 0.07), radius: 9)
        fill(NSRect(x: 0, y: 107, width: bounds.width, height: 0.5), Ink.line)
        fill(NSRect(x: 0, y: bounds.height-42, width: bounds.width, height: 0.5), Ink.line)
    }
}
