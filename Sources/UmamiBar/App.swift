import AppKit
import Sparkle

@main
struct UmamiBarMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnose-details") { Diagnostics.details(); return }
        if CommandLine.arguments.contains("--diagnose-series") { Diagnostics.run(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let cacheIndicator = CacheIndicator(frame: .zero)
    private var controller: MainController!
    private let settings = SettingsWindowController()
    private var updater: SPUStandardUpdaterController!
    private var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        settings.onCheckForUpdates = { [weak self] in self?.updater.checkForUpdates(nil) }
        NSApp.mainMenu = Self.editMenu()
        NotificationCenter.default.addObserver(forName: Localization.changed, object: nil, queue: .main) { _ in NSApp.mainMenu = Self.editMenu() }
        controller = MainController()
        controller.onOpenSettings = { [weak self] tab in self?.openSettings(tab) }
        settings.onSave = { [weak self] connection, sites, colors in try self?.controller.apply(connection, sites: sites, colors: colors) }
        controller.onSummary = { [weak self] summary in
            self?.item?.button?.title = summary.title
            self?.item?.button?.imagePosition = summary.title.isEmpty ? .imageOnly : .imageLeft
            self?.item?.button?.toolTip = summary.tooltip
            self?.item?.button?.setAccessibilityLabel(summary.tooltip)
            self?.item?.button?.alignment = summary.title.isEmpty ? .center : .left
            self?.item?.length = summary.title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
            if let self = self, let button = self.item?.button {
                button.layoutSubtreeIfNeeded()
                let rect = button.cell?.imageRect(forBounds: button.bounds) ?? .zero
                self.cacheIndicator.frame = NSRect(x: rect.maxX - 3, y: rect.maxY - 3, width: 3, height: 3)
                // Same spot, different meaning: orange for saved data, green for a live count.
                self.cacheIndicator.live = summary.live
                self.cacheIndicator.isHidden = !summary.cached && !summary.live
            }
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.labelColor.setFill()
            for (x, height) in [(1.0, 7.0), (6.0, 13.0), (11.0, 10.0)] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: 3, height: height), xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = true; item.button?.image = image; item.button?.title = " —"
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.alignment = .left
        item.button?.imagePosition = .imageLeft
        item.button?.target = self; item.button?.action = #selector(toggle)
        cacheIndicator.isHidden = true; item.button?.addSubview(cacheIndicator)
        popover.contentViewController = controller; popover.behavior = .transient; popover.delegate = self
        // Stats refresh at most once a minute while the popover is open; live counts every 30 seconds,
        // and every minute in the background only when the menu bar shows a live number.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.popover.isShown { self.controller.refreshIfNeeded(); self.controller.refreshLive() }
            else if self.controller.showsLiveMenu { self.controller.refreshLive(maxAge: 55) }
        }
        controller.updateMenu()
        controller.refreshIfNeeded()
        if controller.showsLiveMenu { controller.refreshLive() }
        if controller.connection == nil, !CommandLine.arguments.contains("--launch-at-login") { openSettings(.connection) }
    }
    private func openSettings(_ tab: SettingsWindowController.Tab) {
        popover.performClose(nil)
        settings.show(tab, connection: controller.connection, sites: controller.sites, colors: controller.colors)
    }
    /// Accessory apps show no menu bar, but text fields still need the standard
    /// key equivalents (⌘V to paste an API key, ⌘W to close settings).
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu(); app.addItem(withTitle: L("退出 UmamiBar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: L("编辑"))
        edit.addItem(withTitle: L("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenu(title: L("窗口")); window.addItem(withTitle: L("关闭"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        for menu in [app, edit, window] { let item = NSMenuItem(); item.submenu = menu; main.addItem(item) }
        return main
    }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            controller.refreshIfNeeded(); controller.refreshLive()
        }
    }
}

// Pure AppKit panel; each saved record is scoped to one connection, period and query window.
final class MainController: NSViewController {
    var onSummary: ((MenuSummary) -> Void)?
    var onOpenSettings: ((SettingsWindowController.Tab) -> Void)?
    private let api: API
    private let preferences: Preferences
    private let snapshots: SnapshotStore
    private var panel: NativePanel!
    private(set) var connection: Connection?
    private(set) var sites: [Website] = []
    private(set) var colors: [String: Int] = [:]
    private var period: Period
    private var screen = "empty", loading = false, ready = false, paused = false
    private var generation = UUID()
    private var tasks: [URLSessionDataTask] = []
    private var lastAttempt: Date?
    private var end = Date()
    private var records: [String: SiteSnapshot] = [:]
    private var memory: [Int: [String: SiteSnapshot]] = [:]
    private var stale = Set<String>()
    private var errors: [String: String] = [:]
    private var detailID: String?, detailRows: [MetricRow]?, detailError: String?
    private var breakdown = "pages", dimension: DetailDimension = .pages
    private var utmDimension: DetailDimension = .utmSource, locationDimension: DetailDimension = .country
    private var detailLoading = false, detailToken = UUID()
    private var detailTask: URLSessionDataTask?
    private var observers: [NSObjectProtocol] = []
    /// Live counts are never saved: each expires after the 5-minute window it describes.
    private var live: [String: (visitors: Int, at: Date)] = [:]
    private var liveFailures = Set<String>()
    private var liveTasks: [URLSessionDataTask] = []
    private var liveAttempt: Date?, liveToken = UUID()

    init(preferences: Preferences = .shared, snapshots: SnapshotStore = .shared, api: API = API(), connectionOverride: Connection? = nil, selectedSites: [Website] = []) {
        self.preferences = preferences; self.snapshots = snapshots; self.api = api
        period = Period(rawValue: preferences.defaults.integer(forKey: "period")) ?? .day
        super.init(nibName: nil, bundle: nil)
        if let override = connectionOverride { connection = override; sites = selectedSites }
        else if let address = preferences.defaults.string(forKey: "server"), let base = try? Connection.baseURL(address), let key = Keychain.read() {
            connection = Connection(base: base, key: key)
            if let data = preferences.defaults.data(forKey: "sites"), let saved = try? JSONDecoder().decode([Website].self, from: data) { sites = saved }
        }
        colors = SiteColors.fill(sites.map(\.id), saved: preferences.defaults.dictionary(forKey: SiteColors.key) as? [String: Int] ?? [:], count: Palette.swatches.count)
        sortSites(); restore()
        screen = sites.isEmpty ? "empty" : "overview"
        _ = preferences.reconcileMenuSource(selected: sites.map(\.id))
        observers.append(NotificationCenter.default.addObserver(forName: Localization.changed, object: nil, queue: .main) { [weak self] _ in self?.publish() })
        observers.append(NotificationCenter.default.addObserver(forName: Preferences.changed, object: preferences, queue: .main) { [weak self] _ in
            self?.sortSites(); self?.publish()
            if self?.showsLiveMenu == true { self?.refreshLive() }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    var isRefreshing: Bool { loading }
    var showsLiveMenu: Bool { preferences.menuDisplay.isLive }
    func updateMenu() {
        onSummary?(MenuSummary.make(mode: preferences.menuDisplay, websiteID: preferences.menuWebsiteID, sites: sites, records: records, period: period, stale: stale, live: liveCounts, liveFailed: !liveFailures.isEmpty))
    }
    private var liveCounts: [String: Int] {
        live.filter { Date().timeIntervalSince($0.value.at) < 300 }.mapValues(\.visitors)
    }
    /// Fetches every selected site's live count unless one was attempted within maxAge seconds.
    func refreshLive(maxAge: TimeInterval = 25) {
        guard let connection = connection, !sites.isEmpty, !paused, liveTasks.isEmpty,
              liveAttempt.map({ Date().timeIntervalSince($0) >= maxAge }) ?? true else { return }
        let token = UUID(); liveToken = token; liveAttempt = Date()
        for site in sites {
            let task = api.get(Active.self, connection: connection, path: "websites/\(site.id)/active") { [weak self] result in
                guard let self = self, self.liveToken == token else { return }
                switch result {
                case .success(let active): self.live[site.id] = (active.visitors, Date()); self.liveFailures.remove(site.id)
                case .failure(let error):
                    self.live[site.id] = nil; self.liveFailures.insert(site.id)
                    if (error as? ServiceError)?.pausesRefresh == true { self.paused = true }
                }
                self.liveTasks.removeAll { $0.state == .completed || $0.state == .canceling }
                self.publish()
            }
            liveTasks.append(task)
        }
    }
    private func cancelLive() {
        liveToken = UUID(); liveTasks.forEach { $0.cancel() }; liveTasks = []; liveAttempt = nil
    }
    private func sortSites() {
        guard let base = connection?.base else { return }
        sites = preferences.layout(for: base, available: sites.map(\.id)).sorted(sites)
    }
    private func restore() {
        if let values = memory[period.rawValue] { records = values }
        else if preferences.retainData, let base = connection?.base { records = snapshots.records(base: base, period: period) }
        else { records = [:] }
        records = records.filter { id, value in sites.contains { $0.id == id } && value.timezone == TimeZone.current.identifier }
        stale = Set(records.keys)
        end = records.values.map(\.end).max() ?? Date()
    }
    override func loadView() {
        let material = NSVisualEffectView()
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        panel = NativePanel(); panel.translatesAutoresizingMaskIntoConstraints = false
        // The system popover alone owns the outer rounded outline.
        panel.wantsLayer = true; panel.layer?.masksToBounds = true
        panel.onAction = { [weak self] action, values in self?.handle(action, body: values) }
        material.addSubview(panel)
        NSLayoutConstraint.activate([panel.leadingAnchor.constraint(equalTo: material.leadingAnchor), panel.trailingAnchor.constraint(equalTo: material.trailingAnchor), panel.topAnchor.constraint(equalTo: material.topAnchor), panel.bottomAnchor.constraint(equalTo: material.bottomAnchor)])
        view = material; ready = true; publish()
    }
    private func handle(_ action: String, body: [String: Any]) {
        switch action {
        case "settings": onOpenSettings?(.general)
        case "manage": onOpenSettings?(.websites)
        case "back": detailTask?.cancel(); detailToken = UUID(); detailID = nil; screen = sites.isEmpty ? "empty" : "overview"; publish(); refreshIfNeeded()
        case "detail":
            guard let id = body["id"] as? String, sites.contains(where: { $0.id == id }) else { return }
            detailID = id; screen = "detail"; breakdown = "pages"; dimension = .pages; detailRows = nil; publish(); loadBreakdown()
        case "breakdown":
            guard let value = body["value"] as? String, ["pages", "sources", "utm", "location", "events"].contains(value) else { return }
            breakdown = value; dimension = value == "utm" ? utmDimension : value == "location" ? locationDimension : value == "sources" ? .sources : value == "events" ? .events : .pages
            loadBreakdown()
        case "dimension":
            guard let raw = body["value"] as? String, let value = DetailDimension(rawValue: raw), value.category == breakdown else { return }
            dimension = value
            if breakdown == "utm" { utmDimension = value }; if breakdown == "location" { locationDimension = value }
            loadBreakdown()
        case "detailRetry": loadBreakdown()
        case "refresh": refresh(); refreshLive(maxAge: 0)
        case "period":
            guard let raw = body["value"] as? Int, let value = Period(rawValue: raw), value != period else { return }
            memory[period.rawValue] = records; cancel(); period = value; preferences.defaults.set(raw, forKey: "period")
            detailRows = nil; errors = [:]; lastAttempt = nil; paused = false; restore(); publish(); refresh()
        case "dashboard":
            if let id = body["id"] as? String, let site = sites.first(where: { $0.id == id }), let url = connection?.dashboard(site) { NSWorkspace.shared.open(url) }
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
    private func cancel() {
        detailToken = UUID(); detailTask?.cancel(); detailLoading = false; generation = UUID()
        tasks.forEach { $0.cancel() }; tasks = []; loading = false
    }
    func apply(_ proposed: Connection, sites selected: [Website], colors chosen: [String: Int]) throws {
        let changedConnection = connection?.base != proposed.base || connection?.key != proposed.key
        if changedConnection {
            // A rotated key may have different permissions; never expose data saved with the old credentials.
            let oldKey = connection?.key
            try Keychain.save(proposed.key)
            do { try snapshots.clear() }
            catch {
                if let oldKey = oldKey { try? Keychain.save(oldKey) } else { Keychain.delete() }
                throw error
            }
        }
        let data = try JSONEncoder().encode(selected)
        preferences.defaults.set(proposed.base.absoluteString, forKey: "server")
        preferences.defaults.set(data, forKey: "sites")
        let savedColors = preferences.defaults.dictionary(forKey: SiteColors.key) as? [String: Int] ?? [:]
        preferences.defaults.set(savedColors.merging(chosen, uniquingKeysWith: { _, new in new }), forKey: SiteColors.key)
        let oldIDs = Set(sites.map(\.id))
        connection = proposed; sites = selected; colors = chosen; sortSites()
        _ = preferences.reconcileMenuSource(selected: sites.map(\.id))
        if changedConnection {
            cancel(); records = [:]; memory = [:]; stale = []; errors = [:]; lastAttempt = nil; paused = false
            cancelLive(); live = [:]; liveFailures = []
        } else {
            records = records.filter { id, _ in sites.contains { $0.id == id } }
            live = live.filter { id, _ in sites.contains { $0.id == id } }; liveFailures = liveFailures.filter { id in sites.contains { $0.id == id } }
            if preferences.retainData {
                let restored = snapshots.records(base: proposed.base, period: period)
                for id in sites.map(\.id) where records[id] == nil { if let record = restored[id] { records[id] = record; stale.insert(id) } }
            }
        }
        if let id = detailID, !sites.contains(where: { $0.id == id }) { detailTask?.cancel(); detailToken = UUID(); detailID = nil }
        screen = sites.isEmpty ? "empty" : detailID == nil ? "overview" : "detail"
        publish()
        if changedConnection || oldIDs != Set(sites.map(\.id)) { cancel(); paused = false; refresh(); cancelLive(); refreshLive() }
    }
    private func publish() {
        updateMenu()
        guard ready else { return }
        let latest = records.values.map(\.savedAt).max()
        let hasStale = sites.contains { stale.contains($0.id) && records[$0.id] != nil }
        let updated: String
        if hasStale { updated = L("本地数据 · %@", latest.map { Formats.time.string(from: $0) } ?? "—") }
        else if !errors.isEmpty { updated = L("更新失败 · 保留上次数据") }
        else { updated = latest.map { L("%@ 已刷新", Formats.time.string(from: $0)) } ?? L("等待更新") }
        let layout = connection.map { preferences.layout(for: $0.base, available: sites.map(\.id)) } ?? WebsiteLayout()
        let liveNow = liveCounts
        let displayedEnd = detailID.flatMap { records[$0]?.end } ?? (Set(records.values.map(\.end)).count == 1 ? records.values.first?.end ?? end : end)
        let state = PanelState(screen: screen, loading: loading, period: period, start: period.start(before: displayedEnd), end: displayedEnd, updated: updated, sites: sites.map { site in
            let value = records[site.id]
            return PanelSite(website: site, total: value?.stats.visitors, points: value?.points, error: errors[site.id], stats: value?.stats, previousVisitors: value?.previousVisitors, color: colors[site.id] ?? 0, pinned: layout.pinned.contains(site.id), rangeStart: value?.start, rangeEnd: value?.end, savedAt: value?.savedAt, cached: stale.contains(site.id) && value != nil, live: liveNow[site.id], liveFailed: liveFailures.contains(site.id))
        }, detailID: detailID, breakdown: breakdown, dimension: dimension, rows: detailRows, detailLoading: detailLoading, detailError: detailError, hasConnection: connection != nil, hasCachedData: hasStale)
        preferredContentSize = NSSize(width: 360, height: min(screen == "empty" ? 206 : 640, (NSScreen.main?.visibleFrame.height ?? 760) - 60))
        panel.render(state)
    }
    func refreshIfNeeded() {
        // Startup runs this before the view is loaded so a recovered menu count updates in the background.
        guard ["overview", "detail"].contains(screen), !paused, !loading, lastAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        refresh()
    }
    private func refresh() {
        guard !loading, let connection = connection, !sites.isEmpty else { return }
        loading = true; errors = [:]; end = Date(); let queryEnd = end, token = UUID(), requestedPeriod = period
        generation = token; lastAttempt = Date(); stale.formUnion(records.keys)
        let query = requestedPeriod.query(end: queryEnd)
        var queue = sites
        var blocked = false
        func failure(_ error: Error, site: Website) {
            errors[site.id] = error.localizedDescription
            if (error as? ServiceError)?.pausesRefresh == true { blocked = true }
        }
        func finish() {
            loading = false; tasks = []; paused = blocked; memory[requestedPeriod.rawValue] = records; publish()
            if screen == "detail" { loadBreakdown() }
        }
        func next() {
            guard generation == token else { return }
            guard !queue.isEmpty, !blocked else { finish(); return }
            let site = queue.removeFirst()
            fetch(site, path: "websites/\(site.id)")
        }
        func fetch(_ site: Website, path: String) {
            let task = api.get(Stats.self, connection: connection, path: path + "/stats", query: query) { result in
                guard self.generation == token else { return }
                switch result {
                case .failure(let error): failure(error, site: site); self.publish(); next()
                case .success(let stats):
                    let trend = self.api.get(Series.self, connection: connection, path: path + "/pageviews", query: query) { result in
                        guard self.generation == token else { return }
                        switch result {
                        case .failure(let error): failure(error, site: site); self.publish(); next()
                        case .success(let series):
                            do {
                                let points = try TimeBuckets.expand(series.sessions, period: requestedPeriod, end: queryEnd, wallClockLabels: true)
                                let start = requestedPeriod.start(before: queryEnd), previousWindow = requestedPeriod.previous(before: queryEnd)
                                let previousQuery = [URLQueryItem(name: "startAt", value: String(Int(previousWindow.start.timeIntervalSince1970 * 1000))), URLQueryItem(name: "endAt", value: String(Int(previousWindow.end.timeIntervalSince1970 * 1000)))]
                                let previous = self.api.get(Stats.self, connection: connection, path: path + "/stats", query: previousQuery) { result in
                                    guard self.generation == token else { return }
                                    var previousVisitors: Int?
                                    if case .success(let value) = result { previousVisitors = value.visitors }
                                    if case .failure(let error) = result, (error as? ServiceError)?.pausesRefresh == true { blocked = true }
                                    let record = SiteSnapshot(websiteID: site.id, period: requestedPeriod.rawValue, timezone: TimeZone.current.identifier, start: start, end: queryEnd, savedAt: Date(), stats: stats, points: points, previousVisitors: previousVisitors)
                                    self.records[site.id] = record; self.stale.remove(site.id)
                                    if self.preferences.retainData { try? self.snapshots.save(record, base: connection.base) }
                                    self.publish(); next()
                                }
                                self.tasks.append(previous)
                            } catch { failure(error, site: site); self.publish(); next() }
                        }
                    }
                    self.tasks.append(trend)
                }
            }
            tasks.append(task)
        }
        publish(); next()
    }
    private func loadBreakdown() {
        guard let connection = connection, let id = detailID, screen == "detail" else { return }
        detailTask?.cancel(); let token = UUID(); detailToken = token
        let detailEnd = records[id]?.end ?? end
        let restored = preferences.retainData ? snapshots.detail(base: connection.base, websiteID: id, period: period, dimension: dimension, end: detailEnd) : nil
        detailRows = restored; detailError = nil; detailLoading = restored == nil; publish()
        let requestedPeriod = period, requestedDimension = dimension
        // Events keep every row so shares are of all events; other breakdowns only need the top 5.
        let limit = dimension == .events ? 500 : 5
        let query = period.query(end: detailEnd) + [URLQueryItem(name: "type", value: dimension.rawValue), URLQueryItem(name: "limit", value: String(limit))]
        detailTask = api.get([MetricRow].self, connection: connection, path: "websites/\(id)/metrics", query: query) { [weak self] result in
            guard let self = self, self.detailToken == token, self.detailID == id, self.screen == "detail" else { return }
            self.detailLoading = false
            switch result {
            case .success(let rows):
                self.detailRows = Array(rows.sorted { $0.y > $1.y }.prefix(limit))
                if self.preferences.retainData { try? self.snapshots.saveDetail(DetailSnapshot(websiteID: id, period: requestedPeriod.rawValue, dimension: requestedDimension.rawValue, end: detailEnd, rows: self.detailRows!), base: connection.base) }
            case .failure(let error):
                self.detailError = error.localizedDescription
                // Keep a matching successful breakdown visible on offline refreshes.
                if self.detailRows != nil { self.detailError = nil }
            }
            self.publish()
        }
    }
}


private final class CacheIndicator: NSView {
    var live = false { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { (live ? NSColor.systemGreen : NSColor.systemOrange).setFill(); NSBezierPath(ovalIn: bounds).fill() }
}
