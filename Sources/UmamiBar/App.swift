import AppKit

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
    private var controller: MainController!
    private var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainController()
        controller.onTotal = { [weak self] total, period in
            self?.item.button?.title = " " + Self.menuCount(total)
            let exact = total.map { String($0) } ?? "正在更新"
            self?.item.button?.toolTip = "Umami · \(period.title) · \(exact) · 已选网站访客合计（跨站未去重）"
        }
        item = NSStatusBar.system.statusItem(withLength: 80)
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
        popover.contentViewController = controller; popover.behavior = .transient; popover.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }; self.controller.refreshIfNeeded()
        }
    }
    private static func menuCount(_ count: Int?) -> String {
        guard let count = count else { return "—" }
        guard count >= 10_000 else { return String(count) }
        let units = ["K", "M", "B", "T", "P", "E"]
        var value = Double(count) / 1_000
        var unit = 0
        while value >= 999.95 && unit < units.count - 1 { value /= 1_000; unit += 1 }
        return String(format: "%.1f%@", locale: Locale(identifier: "en_US_POSIX"), value, units[unit])
    }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            controller.refreshIfNeeded()
        }
    }
}

// Pure AppKit panel; all controls and charts are drawn locally.
final class MainController: NSViewController {
    var onTotal: ((Int?, Period) -> Void)?
    private let api = API()
    private var panel: NativePanel!
    private var connection: Connection?
    private var candidate: Connection?
    private var sites: [Website] = []
    private var available: [Website] = []
    private var period = Period(rawValue: UserDefaults.standard.integer(forKey: "period")) ?? .day
    private var screen = "setup"
    private var connecting = false
    private var loading = false
    private var ready = false
    private var generation = UUID()
    private var tasks: [URLSessionDataTask] = []
    private var lastUpdate: Date?
    private var end = Date()
    private var paused = false
    private var cache: [String: (Int, [Point])] = [:]
    private var errors: [String: String] = [:]
    private var message = ""
    private var statistics: [String: Stats] = [:]
    private var previousVisitors: [String: Int] = [:]
    private var detailID: String?
    private var breakdown = "pages"
    private var detailRows: [MetricRow]?
    private var detailError: String?
    private var detailLoading = false
    private var detailToken = UUID()
    private var detailTask: URLSessionDataTask?

    override func loadView() {
        let material = NSVisualEffectView()
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        panel = NativePanel(); panel.translatesAutoresizingMaskIntoConstraints = false
        panel.onAction = { [weak self] action, values in self?.handle(action, body: values) }
        material.addSubview(panel)
        NSLayoutConstraint.activate([panel.leadingAnchor.constraint(equalTo: material.leadingAnchor), panel.trailingAnchor.constraint(equalTo: material.trailingAnchor), panel.topAnchor.constraint(equalTo: material.topAnchor), panel.bottomAnchor.constraint(equalTo: material.bottomAnchor)])
        view = material
        preferredContentSize = NSSize(width: 360, height: min(640, (NSScreen.main?.visibleFrame.height ?? 760) - 60))
        if let address = UserDefaults.standard.string(forKey: "server"), let base = try? Connection.baseURL(address), let key = Keychain.read() {
            connection = Connection(base: base, key: key)
            if let data = UserDefaults.standard.data(forKey: "sites"), let saved = try? JSONDecoder().decode([Website].self, from: data) { sites = saved }
            if !sites.isEmpty { screen = "overview" }
        }
        ready = true; publish()
    }
    private func handle(_ action: String, body: [String: Any]) {
        switch action {
        case "ready": ready = true; publish(); refreshIfNeeded()
        case "settings": cancel(); screen = "setup"; publish()
        case "back": if !sites.isEmpty { detailTask?.cancel(); detailToken = UUID(); detailID = nil; screen = "overview"; publish(); refreshIfNeeded() }
        case "detail":
            guard let id = body["id"] as? String, sites.contains(where: { $0.id == id }) else { return }
            detailID = id; screen = "detail"; breakdown = "pages"; detailRows = nil; publish(); loadBreakdown()
        case "breakdown": breakdown = body["value"] as? String == "sources" ? "sources" : "pages"; loadBreakdown()
        case "detailRetry": loadBreakdown()
        case "refresh": refresh()
        case "period":
            guard let raw = body["value"] as? Int, let value = Period(rawValue: raw) else { return }
            cancel(); period = value; UserDefaults.standard.set(raw, forKey: "period")
            cache = [:]; statistics = [:]; previousVisitors = [:]; detailRows = nil; errors = [:]; lastUpdate = nil; paused = false; onTotal?(nil, period); refresh()
        case "connect": connect(address: body["server"] as? String ?? "", key: body["key"] as? String ?? "")
        case "manage": if let connection = connection { discover(connection) }
        case "save": save(ids: body["ids"] as? [String] ?? [])
        case "dashboard":
            if let id = body["id"] as? String, let site = sites.first(where: { $0.id == id }), let url = connection?.dashboard(site) { NSWorkspace.shared.open(url) }
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
    private func cancel() { detailToken = UUID(); detailTask?.cancel(); detailLoading = false; generation = UUID(); tasks.forEach { $0.cancel() }; tasks = []; loading = false; connecting = false }
    private func connect(address: String, key: String) {
        do {
            let base = try Connection.baseURL(address)
            let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            // Reuse saved credentials only for the exact same origin and API path.
            let effective = key.isEmpty && base == connection?.base ? connection?.key ?? "" : key
            guard !effective.isEmpty else { throw ServiceError.message("请输入 API Key。") }
            discover(Connection(base: base, key: effective))
        } catch { message = error.localizedDescription; publish() }
    }
    private func discover(_ proposed: Connection) {
        cancel(); connecting = true; publish(); let token = generation
        api.websites(connection: proposed) { [weak self] result in
            guard let self = self, self.generation == token else { return }
            self.connecting = false
            switch result {
            case .failure(let error): self.message = error.localizedDescription
            case .success(let sites):
                if sites.isEmpty { self.message = "暂无可访问的网站，请添加网站后重试。" }
                else { self.candidate = proposed; self.available = sites; self.screen = "selection" }
            }
            self.publish()
        }
    }
    private func save(ids: [String]) {
        guard let candidate = candidate else { return }
        let selected = available.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { message = "请至少选择一个网站。"; publish(); return }
        do {
            try Keychain.save(candidate.key)
            connection = candidate; sites = selected; cache = [:]; statistics = [:]; previousVisitors = [:]; errors = [:]; lastUpdate = nil; paused = false
            UserDefaults.standard.set(candidate.base.absoluteString, forKey: "server")
            UserDefaults.standard.set(try JSONEncoder().encode(selected), forKey: "sites")
            screen = "overview"; publish(); refresh()
        } catch { message = error.localizedDescription; publish() }
    }
    private func publish() {
        guard ready else { return }
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        let updated = lastUpdate.map { errors.isEmpty ? formatter.string(from: $0) + " 已刷新" : "更新失败 · 保留上次数据" } ?? "等待更新"
        let state = PanelState(screen: screen, server: connection?.base.absoluteString ?? "https://api.umami.is/v1", hasKey: connection != nil, connecting: connecting, loading: loading, period: period, start: period.start(before: end), end: end, updated: updated, message: message, sites: sites.map { site in
            let data = cache[site.id]
            return PanelSite(website: site, total: statistics[site.id]?.visitors ?? data?.0, points: data?.1, error: errors[site.id], stats: statistics[site.id], previousVisitors: previousVisitors[site.id])
        }, available: available, selected: sites.map(\.id), detailID: detailID, breakdown: breakdown, rows: detailRows, detailLoading: detailLoading, detailError: detailError)
        let desiredHeight: CGFloat = screen == "setup" ? (sites.isEmpty ? 374 : 418) : screen == "selection" ? 520 : 640
        preferredContentSize = NSSize(width: 360, height: min(desiredHeight, (NSScreen.main?.visibleFrame.height ?? 760) - 60))
        panel.render(state)
        message = ""
    }
    func refreshIfNeeded() {
        guard ready, ["overview", "detail"].contains(screen), !paused, !loading, lastUpdate.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        refresh()
    }
    private func refresh() {
        guard ["overview", "detail"].contains(screen), !loading, let connection = connection, !sites.isEmpty else { return }
        loading = true; errors = [:]; end = Date(); let query = period.query(end: end)
        let token = UUID(); generation = token; if screen == "detail" { loadBreakdown() }; publish()
        var queue = sites
        // Visitors fetched in this round only; failed sites must not contribute stale values to the total.
        var fresh: [String: Int] = [:]
        func next() {
            guard self.generation == token else { return }
            guard !queue.isEmpty else {
                self.loading = false; self.tasks = []; self.lastUpdate = self.end
                self.paused = self.errors.values.contains { $0.contains("API Key") || $0.contains("限流") }
                self.onTotal?(fresh.count == self.sites.count ? fresh.values.reduce(0, +) : nil, self.period)
                self.publish(); return
            }
            let site = queue.removeFirst(); let path = "websites/\(site.id)"
            let task = self.api.get(Stats.self, connection: connection, path: path + "/stats", query: query) { result in
                guard self.generation == token else { return }
                switch result {
                case .failure(let error): self.errors[site.id] = error.localizedDescription; self.publish(); next()
                case .success(let stats):
                    self.statistics[site.id] = stats; fresh[site.id] = stats.visitors
                    let task = self.api.get(Series.self, connection: connection, path: path + "/pageviews", query: query) { result in
                        guard self.generation == token else { return }
                        switch result {
                        case .success(let series):
                            do {
                                let points = try TimeBuckets.expand(series.sessions, period: self.period, end: self.end, wallClockLabels: true)
                                self.cache[site.id] = (stats.visitors, points)
                            } catch { self.errors[site.id] = error.localizedDescription }
                        case .failure(let error): self.errors[site.id] = error.localizedDescription
                        }
                        self.publish()
                        let start = self.period.start(before: self.end)
                        let previousEnd = start.addingTimeInterval(-0.001)
                        let previousStart = start.addingTimeInterval(-self.end.timeIntervalSince(start))
                        let previousQuery = [URLQueryItem(name: "startAt", value: String(Int(previousStart.timeIntervalSince1970 * 1000))), URLQueryItem(name: "endAt", value: String(Int(previousEnd.timeIntervalSince1970 * 1000)))]
                        let previousTask = self.api.get(Stats.self, connection: connection, path: path + "/stats", query: previousQuery) { result in
                            guard self.generation == token else { return }
                            if case .success(let previous) = result { self.previousVisitors[site.id] = previous.visitors }
                            else { self.previousVisitors.removeValue(forKey: site.id) }
                            self.publish(); next()
                        }
                        self.tasks.append(previousTask)
                    }; self.tasks.append(task)
                }
            }; self.tasks.append(task)
        }
        next()
    }

    private func loadBreakdown() {
        guard let connection = connection, let id = detailID, screen == "detail" else { return }
        detailTask?.cancel(); let token = UUID(); detailToken = token
        detailLoading = true; detailRows = nil; detailError = nil; publish()
        let query = period.query(end: end) + [URLQueryItem(name: "type", value: breakdown == "pages" ? "path" : "referrer"), URLQueryItem(name: "limit", value: "5")]
        detailTask = api.get([MetricRow].self, connection: connection, path: "websites/\(id)/metrics", query: query) { [weak self] result in
            guard let self = self, self.detailToken == token, self.detailID == id, self.screen == "detail" else { return }
            self.detailLoading = false
            switch result {
            case .success(let rows): self.detailRows = Array(rows.sorted { $0.y > $1.y }.prefix(5))
            case .failure(let error): self.detailError = error.localizedDescription
            }
            self.publish()
        }
    }
}
