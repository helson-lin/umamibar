import Foundation

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
        guard let visitorCount = try number(.visitors) else { throw ServiceError.message("统计响应缺少访客数。") }
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
        return seconds < 60 ? "\(seconds)秒" : "\(seconds / 60)分\(seconds % 60)秒"
    }
    static func change(current: Int?, previous: Int?) -> String {
        guard let current = current, let previous = previous else { return "— 较上期" }
        if previous == 0 { return current > 0 ? "新增 · 上期为 0" : "— 持平" }
        let percent = Double(current - previous) / Double(previous) * 100
        return String(format: "%@ %.1f%% 较上期", percent > 0 ? "↑" : percent < 0 ? "↓" : "—", abs(percent))
    }
}
struct MetricRow: Decodable {
    let x: String?
    let y: Double
}
enum Period: Int, CaseIterable {
    case day, week, month
    var title: String { ["最近 24 小时", "最近 7 天", "最近一个月"][rawValue] }
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
            throw ServiceError.message("请输入 HTTPS 服务地址（本地 localhost 可使用 HTTP）。")
        }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { path = host == "api.umami.is" ? "v1" : "api" }
        parts.path = "/" + path
        guard let url = parts.url else { throw ServiceError.message("服务地址无效。") }
        return url
    }
    func dashboard(_ website: Website) -> URL? {
        if base.host == "api.umami.is" { return URL(string: "https://cloud.umami.is/websites/\(website.id)") }
        return base.deletingLastPathComponent().appendingPathComponent("websites").appendingPathComponent(website.id)
    }
}
enum ServiceError: LocalizedError {
    case message(String)
    /// The key was rejected or rate limited: automatic refresh stops until the user acts.
    case blocking(String)
    var errorDescription: String? { switch self { case .message(let text), .blocking(let text): return text } }
    var pausesRefresh: Bool { if case .blocking = self { return true }; return false }
}
