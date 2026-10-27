import Foundation
import UserNotifications

/// Traffic alerts compare complete hours with the same hours on the previous six days,
/// so a quiet night on a small site is not mistaken for broken tracking.
enum TrafficAlert: String, CaseIterable {
    case zero, spike

    /// Hours of history each check asks for: seven days of complete hours.
    static let history = 7 * 24
    /// Zero: no sessions in this many complete hours...
    static let quietHours = 3
    /// ...while the same hours normally bring at least this many sessions.
    static let zeroBaseline = 5.0
    /// Spike: the last complete hour reaches this multiple of its usual value, and at least `spikeMinimum` sessions.
    static let spikeRatio = 3.0
    static let spikeMinimum = 20.0

    struct Finding: Equatable {
        let kind: TrafficAlert
        /// Sessions in the window that triggered the alert.
        let recent: Double
        /// Average sessions in the same window on the previous six days.
        let usual: Double
    }

    /// `hours` holds complete hourly session counts, oldest first, ending with the last complete hour.
    static func evaluate(_ hours: [Double]) -> [Finding] {
        let days = 1...6
        guard hours.count > quietHours + 24 * days.upperBound else { return [] }
        let end = hours.count
        func window(_ length: Int, daysBack: Int) -> Double {
            hours[(end - length - 24 * daysBack)..<(end - 24 * daysBack)].reduce(0, +)
        }
        func usual(_ length: Int) -> Double { days.map { window(length, daysBack: $0) }.reduce(0, +) / Double(days.count) }
        var findings: [Finding] = []
        let quiet = window(quietHours, daysBack: 0), quietUsual = usual(quietHours)
        if quiet == 0 && quietUsual >= zeroBaseline { findings.append(Finding(kind: .zero, recent: 0, usual: quietUsual)) }
        let last = hours[end - 1], lastUsual = usual(1)
        if last >= spikeMinimum && last >= spikeRatio * lastUsual { findings.append(Finding(kind: .spike, recent: last, usual: lastUsual)) }
        return findings
    }

    /// The query window: the last `history` complete hours before `now`.
    static func window(before now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return (calendar.date(byAdding: .hour, value: -history, to: hour) ?? hour, hour.addingTimeInterval(-0.001))
    }

    func notice(for website: Website, finding: Finding) -> (title: String, body: String) {
        switch self {
        case .zero:
            return (L("%@ 流量归零", website.name), L("最近 %ld 小时没有访问，平时同一时段约 %ld 次会话。统计脚本可能失效。", Self.quietHours, Int(finding.usual.rounded())))
        case .spike:
            let title = L("%@ 流量激增", website.name)
            guard finding.usual >= 1 else { return (title, L("最近 1 小时 %ld 次会话，平时同一时段几乎没有访问。", Int(finding.recent))) }
            return (title, L("最近 1 小时 %ld 次会话，约为平时同一时段的 %.1f 倍。", Int(finding.recent), finding.recent / finding.usual))
        }
    }
}

/// Remembers which alerts are currently active so each fires once and again only after it clears.
struct AlertTracker {
    static let key = "activeTrafficAlerts"
    let defaults: UserDefaults
    private var active: Set<String> { Set(defaults.stringArray(forKey: Self.key) ?? []) }

    /// Records the site's current findings and returns the kinds that just became active.
    func update(websiteID: String, findings: [TrafficAlert.Finding]) -> [TrafficAlert.Finding] {
        var next = active.filter { !$0.hasPrefix(websiteID + "|") }
        let fresh = findings.filter { !active.contains(websiteID + "|" + $0.kind.rawValue) }
        findings.forEach { next.insert(websiteID + "|" + $0.kind.rawValue) }
        defaults.set(next.sorted(), forKey: Self.key)
        return fresh
    }
    /// Forgets sites that are no longer selected, or everything after a connection change.
    func keep(_ websiteIDs: [String]) {
        defaults.set(active.filter { key in websiteIDs.contains { key.hasPrefix($0 + "|") } }.sorted(), forKey: Self.key)
    }
}

/// Posts alerts through Notification Center. Unbundled builds (swift run, tests) have no
/// bundle identifier, and UNUserNotificationCenter would crash there, so they post nothing.
enum AlertNotifier {
    static let websiteKey = "websiteID"
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        guard available else { completion(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    static func post(_ kind: TrafficAlert, website: Website, finding: TrafficAlert.Finding) {
        guard available else { return }
        let text = kind.notice(for: website, finding: finding)
        let content = UNMutableNotificationContent()
        content.title = text.title; content.body = text.body; content.sound = .default
        content.userInfo = [websiteKey: website.id]
        // One identifier per site and kind: a repeat replaces the old banner instead of stacking.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "traffic.\(website.id).\(kind.rawValue)", content: content, trigger: nil))
    }
}
