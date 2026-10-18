import Foundation

/// Ordinary order survives pinning; the pinned group maintains its own order.
struct WebsiteLayout: Codable, Equatable {
    var order: [String] = []
    var pinned: [String] = []

    mutating func reconcile(_ ids: [String]) {
        let valid = Set(ids)
        var seen = Set<String>()
        order = (order + ids).filter { valid.contains($0) && seen.insert($0).inserted }
        seen = []
        pinned = pinned.filter { valid.contains($0) && seen.insert($0).inserted }
    }
    func sorted(_ sites: [Website]) -> [Website] {
        let byID = Dictionary(sites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return (pinned + order + sites.map(\.id)).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
    }
    mutating func togglePin(_ id: String) {
        if pinned.contains(id) { pinned.removeAll { $0 == id } } else { pinned.append(id) }
    }
    @discardableResult
    mutating func move(_ id: String, by delta: Int, selected: Set<String>) -> Bool {
        let group = (pinned.contains(id) ? pinned : order.filter { !pinned.contains($0) }).filter(selected.contains)
        guard let index = group.firstIndex(of: id), group.indices.contains(index + delta) else { return false }
        return place(id, relativeTo: group[index + delta], after: delta > 0, selected: selected)
    }
    @discardableResult
    mutating func place(_ id: String, relativeTo target: String, after: Bool, selected: Set<String>) -> Bool {
        guard id != target, selected.contains(id), selected.contains(target), pinned.contains(id) == pinned.contains(target) else { return false }
        if pinned.contains(id) { Self.place(id, relativeTo: target, after: after, in: &pinned) }
        else { Self.place(id, relativeTo: target, after: after, in: &order) }
        return true
    }
    private static func place(_ id: String, relativeTo target: String, after: Bool, in ids: inout [String]) {
        guard ids.contains(id), ids.contains(target) else { return }
        ids.removeAll { $0 == id }
        if let index = ids.firstIndex(of: target) { ids.insert(id, at: index + (after ? 1 : 0)) }
    }
}

enum MenuDisplay: String, CaseIterable {
    case total, website, icon
    var title: String { switch self { case .total: return L("合计访客"); case .website: return L("指定网站"); case .icon: return L("仅图标") } }
}

final class Preferences {
    static let shared = Preferences()
    static let changed = Notification.Name("UmamiBarPreferencesChanged")
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var menuDisplay: MenuDisplay {
        get { MenuDisplay(rawValue: defaults.string(forKey: "menuDisplay") ?? "") ?? .total }
        set { defaults.set(newValue.rawValue, forKey: "menuDisplay"); notify() }
    }
    var menuWebsiteID: String? {
        get { defaults.string(forKey: "menuWebsiteID") }
        set { defaults.set(newValue, forKey: "menuWebsiteID"); notify() }
    }
    var retainData: Bool {
        get { defaults.object(forKey: "retainSuccessfulData") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "retainSuccessfulData"); notify() }
    }
    func layout(for base: URL, available: [String]) -> WebsiteLayout {
        let key = "websiteLayout." + base.absoluteString
        var value = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WebsiteLayout.self, from: $0) } ?? WebsiteLayout()
        value.reconcile(available)
        return value
    }
    func setLayout(_ layout: WebsiteLayout, for base: URL) {
        if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: "websiteLayout." + base.absoluteString); notify() }
    }
    @discardableResult
    func reconcileMenuSource(selected: [String]) -> Bool {
        guard menuDisplay == .website, !selected.contains(menuWebsiteID ?? "") else { return false }
        defaults.set(MenuDisplay.total.rawValue, forKey: "menuDisplay")
        defaults.removeObject(forKey: "menuWebsiteID")
        notify()
        return true
    }
    private func notify() { NotificationCenter.default.post(name: Self.changed, object: self) }
}

struct MenuSummary {
    var count: Int?
    var title: String
    var tooltip: String
    var cached: Bool
    static func make(mode: MenuDisplay, websiteID: String?, sites: [Website], records: [String: SiteSnapshot], period: Period, stale: Set<String>) -> MenuSummary {
        let chosen = mode == .website ? sites.filter { $0.id == websiteID } : sites
        let snapshots = chosen.compactMap { records[$0.id] }.filter { $0.period == period.rawValue }
        // A total across different query windows is misleading, even if every station has a value.
        let complete = !chosen.isEmpty && snapshots.count == chosen.count && Set(snapshots.map(\.end)).count == 1
        let count = complete ? snapshots.reduce(0) { $0 + $1.stats.visitors } : nil
        let source = mode == .website ? chosen.first?.name ?? L("指定网站") : L("已选网站访客合计（跨站未去重）")
        var tooltip = L("Umami · %@ · %@ · %@", period.title, count.map(String.init) ?? L("数据不可用"), source)
        if complete, let snapshot = snapshots.first {
            tooltip += "\n" + Formats.range.string(from: snapshot.start) + " — " + Formats.range.string(from: snapshot.end)
            if chosen.contains(where: { stale.contains($0.id) }) {
                let savedAt = snapshots.map(\.savedAt).min() ?? snapshot.savedAt
                tooltip += "\n" + L("本地数据 · %@ 保存", Formats.range.string(from: savedAt))
            }
        }
        return MenuSummary(count: count, title: mode == .icon || chosen.isEmpty ? "" : " " + compact(count), tooltip: tooltip, cached: complete && mode != .icon && chosen.contains(where: { stale.contains($0.id) }))
    }
    static func compact(_ count: Int?) -> String {
        guard let count = count else { return "—" }
        guard count >= 10_000 else { return String(count) }
        let units = ["K", "M", "B", "T", "P", "E"]
        var value = Double(count) / 1_000, unit = 0
        while value >= 999.95 && unit < units.count - 1 { value /= 1_000; unit += 1 }
        return String(format: "%.1f%@", locale: Locale(identifier: "en_US_POSIX"), value, units[unit])
    }
}
