import Foundation

/// Localized UI text. Keys are the Chinese source strings; en.lproj translates them and any
/// missing entry falls back to the key. Format keys use %@ / %ld placeholders.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Localization.bundle.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? format : String(format: format, arguments: args)
}

/// The UI language: follow macOS, or a language chosen in Settings. Strings come from that
/// language's .lproj bundle, so a change applies immediately without relaunching.
enum Localization {
    /// Language codes offered in Settings; "" follows the system.
    static let choices = ["", "zh-Hans", "en"]
    static let changed = Notification.Name("UmamiBarLanguageChanged")
    private static let key = "language"
    static var choice: String { UserDefaults.standard.string(forKey: key) ?? "" }
    private(set) static var bundle = load()

    static func set(_ code: String) {
        guard choices.contains(code), code != choice else { return }
        UserDefaults.standard.set(code, forKey: key)
        // Also the app's own AppleLanguages, so system-provided text matches after a relaunch.
        if code.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") } else { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
        bundle = load()
        NotificationCenter.default.post(name: changed, object: nil)
    }
    private static func load() -> Bundle {
        let available = Bundle.main.localizations.filter { $0 != "Base" }
        let code = choice.isEmpty ? Bundle.preferredLocalizations(from: available, forPreferences: UserDefaults.standard.stringArray(forKey: "AppleLanguages")).first : choice
        guard let code = code, let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

struct Website: Codable, Equatable {
    let id: String
    let name: String
    let domain: String
}
struct Point: Decodable { let x: String; let y: Double }
struct Series: Decodable { let sessions: [Point] }
struct Stats: Decodable {
    let visitors: Int
    let pageviews: Int?
    let visits: Int?
    let bounces: Int?
    let totalTime: Double?
    enum CodingKeys: String, CodingKey { case visitors, pageviews, visits, bounces, totaltime }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) throws -> Double? {
            guard c.contains(key), !(try c.decodeNil(forKey: key)) else { return nil }
            if let value = try? c.decode(Double.self, forKey: key) { return value }
            return try c.decode(LegacyCount.self, forKey: key).value
        }
        guard let visitorCount = try number(.visitors) else { throw ServiceError.message(L("统计响应缺少访客数。")) }
        visitors = Int(visitorCount)
        pageviews = try number(.pageviews).map(Int.init)
        visits = try number(.visits).map(Int.init)
        bounces = try number(.bounces).map(Int.init)
        totalTime = try number(.totaltime)
    }
    private struct LegacyCount: Decodable { let value: Double }
    var bounceText: String {
        guard let visits = visits, visits > 0, let bounces = bounces else { return "—" }
        return String(format: "%.0f%%", Double(bounces) / Double(visits) * 100)
    }
    var durationText: String {
        guard let visits = visits, let bounces = bounces, visits > bounces, let totalTime = totalTime else { return "—" }
        let seconds = max(0, Int(totalTime / Double(visits - bounces)))
        return seconds < 60 ? L("%ld秒", seconds) : L("%ld分%ld秒", seconds / 60, seconds % 60)
    }
    static func change(current: Int?, previous: Int?) -> String {
        guard let current = current, let previous = previous else { return L("— 较上期") }
        if previous == 0 { return current > 0 ? L("新增 · 上期为 0") : L("— 持平") }
        let percent = Double(current - previous) / Double(previous) * 100
        return L("%@ %.1f%% 较上期", percent > 0 ? "↑" : percent < 0 ? "↓" : "—", abs(percent))
    }
}
struct MetricRow: Decodable {
    let x: String?
    let y: Double
}
enum DetailDimension: String, CaseIterable {
    case pages = "path", sources = "referrer"
    case utmSource, utmMedium, utmCampaign, utmTerm, utmContent
    case country, region, city

    var category: String {
        switch self {
        case .pages: return "pages"
        case .sources: return "sources"
        case .utmSource, .utmMedium, .utmCampaign, .utmTerm, .utmContent: return "utm"
        case .country, .region, .city: return "location"
        }
    }
    static func options(for category: String) -> [DetailDimension] {
        allCases.filter { $0.category == category }
    }
    var title: String {
        switch self {
        case .pages: return L("页面路径")
        case .sources: return L("来源")
        case .utmSource: return L("来源") + " · utm_source"
        case .utmMedium: return L("媒介") + " · utm_medium"
        case .utmCampaign: return L("活动") + " · utm_campaign"
        case .utmTerm: return L("关键词") + " · utm_term"
        case .utmContent: return L("内容") + " · utm_content"
        case .country: return L("国家 / 地区")
        case .region: return L("省份 / 州")
        case .city: return L("城市")
        }
    }
    func label(for value: String?, locale: Locale = .current) -> String {
        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            switch self {
            case .pages: return "/"
            case .sources: return L("直接访问")
            case .country, .region, .city: return L("未知位置")
            default: return L("未设置")
            }
        }
        if self == .country { return locale.localizedString(forRegionCode: value) ?? value }
        return value
    }
}
enum Period: Int, CaseIterable {
    case day, week, month
    var title: String { [L("最近 24 小时"), L("最近 7 天"), L("最近一个月")][rawValue] }
    var unit: String { self == .day ? "hour" : "day" }
    func start(before end: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .day: return end.addingTimeInterval(-86400)
        case .week: return end.addingTimeInterval(-7 * 86400)
        case .month: return calendar.date(byAdding: .month, value: -1, to: end) ?? end
        }
    }
    func query(end: Date) -> [URLQueryItem] {
        [URLQueryItem(name: "startAt", value: String(Int(start(before: end).timeIntervalSince1970 * 1000))),
         URLQueryItem(name: "endAt", value: String(Int(end.timeIntervalSince1970 * 1000))),
         URLQueryItem(name: "unit", value: unit), URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
    }
}
struct Connection {
    let base: URL
    let key: String
    static func baseURL(_ input: String) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw ServiceError.message(L("请输入 HTTPS 服务地址（本地 localhost 可使用 HTTP）。"))
        }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { path = host == "api.umami.is" ? "v1" : "api" }
        parts.path = "/" + path
        guard let url = parts.url else { throw ServiceError.message(L("服务地址无效。")) }
        return url
    }
    func dashboard(_ website: Website) -> URL? {
        if base.host == "api.umami.is" { return URL(string: "https://cloud.umami.is/websites/\(website.id)") }
        return base.deletingLastPathComponent().appendingPathComponent("websites").appendingPathComponent(website.id)
    }
}
/// Per-site chart colors, stored as palette indexes keyed by website ID.
enum SiteColors {
    static let key = "siteColors"
    /// The first palette index nobody uses yet; once all are taken, colors repeat in order.
    static func next(after used: [Int], count: Int) -> Int {
        (0..<count).first { !used.contains($0) } ?? used.count % count
    }
    /// Keeps each site's saved color and gives sites without one the next free color, in list order.
    static func fill(_ ids: [String], saved: [String: Int], count: Int) -> [String: Int] {
        var result = saved.filter { ids.contains($0.key) && (0..<count).contains($0.value) }
        for id in ids where result[id] == nil { result[id] = next(after: ids.compactMap { result[$0] }, count: count) }
        return result
    }
}
enum ServiceError: LocalizedError {
    case message(String)
    /// The key was rejected or rate limited: automatic refresh stops until the user acts.
    case blocking(String)
    var errorDescription: String? { switch self { case .message(let text), .blocking(let text): return text } }
    var pausesRefresh: Bool { if case .blocking = self { return true }; return false }
}
