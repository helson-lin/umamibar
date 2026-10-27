import Foundation

/// An indivisible result: statistics and the trend always share the same exact query window.
struct SiteSnapshot: Codable {
    let websiteID: String
    let period: Int
    let timezone: String
    let start: Date
    let end: Date
    let savedAt: Date
    let stats: Stats
    let points: [Point]
    let previousVisitors: Int?
}
struct DetailSnapshot: Codable {
    let websiteID: String
    let period: Int
    let dimension: String
    let end: Date
    let rows: [MetricRow]
    /// The row limit the rows were fetched with; snapshots from before "Show more" have none.
    var limit: Int? = nil
}

final class SnapshotStore {
    static let shared = SnapshotStore()
    static let changed = Notification.Name("UmamiBarSnapshotsChanged")
    private struct Archive: Codable {
        var version = 1
        var sites: [String: [String: SiteSnapshot]] = [:]
        var details: [String: [String: DetailSnapshot]] = [:]
    }
    private var archive = Archive()
    private let fileURL: URL
    private(set) var lastError: String?
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UmamiBar", isDirectory: true)) {
        fileURL = directory.appendingPathComponent("successful-data.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(Archive.self, from: data)
            guard decoded.version == 1 else { throw ServiceError.message(L("本地数据版本不兼容，请联网刷新。")) }
            archive = decoded
        } catch { lastError = L("无法读取已保存数据，请联网刷新。") }
    }
    func records(base: URL, period: Period, timezone: String = TimeZone.current.identifier) -> [String: SiteSnapshot] {
        var result: [String: SiteSnapshot] = [:]
        for record in (archive.sites[base.absoluteString] ?? [:]).values
        where record.period == period.rawValue && record.timezone == timezone && record.start < record.end {
            result[record.websiteID] = record
        }
        return result
    }
    func save(_ record: SiteSnapshot, base: URL) throws {
        var next = archive
        next.sites[base.absoluteString, default: [:]][siteKey(record.websiteID, record.period)] = record
        // Details for a previous window cannot accompany the new summary, even on the same dimension.
        next.details[base.absoluteString] = (next.details[base.absoluteString] ?? [:]).filter { _, value in
            value.websiteID != record.websiteID || value.period != record.period || value.end == record.end
        }
        try commit(next)
    }
    func saveDetail(_ record: DetailSnapshot, base: URL) throws {
        guard archive.sites[base.absoluteString]?[siteKey(record.websiteID, record.period)]?.end == record.end else { return }
        var next = archive
        let key = siteKey(record.websiteID, record.period) + "|" + record.dimension
        next.details[base.absoluteString, default: [:]][key] = record
        try commit(next)
    }
    func detail(base: URL, websiteID: String, period: Period, dimension: DetailDimension, end: Date) -> [MetricRow]? {
        let key = siteKey(websiteID, period.rawValue) + "|" + dimension.rawValue
        // Rows saved under another limit would misstate how many items the shares cover.
        guard let record = archive.details[base.absoluteString]?[key], record.end == end, record.limit == dimension.fetchLimit else { return nil }
        return record.rows
    }
    func allRecords(base: URL) -> [SiteSnapshot] { Array((archive.sites[base.absoluteString] ?? [:]).values) }
    func clear(base: URL? = nil) throws {
        var next = archive
        if let base = base { next.sites.removeValue(forKey: base.absoluteString); next.details.removeValue(forKey: base.absoluteString) }
        else { next = Archive() }
        try commit(next)
    }
    private func siteKey(_ id: String, _ period: Int) -> String { "\(period)|\(id)" }
    private func commit(_ next: Archive) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(next)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            archive = next; lastError = nil
            NotificationCenter.default.post(name: Self.changed, object: self)
        } catch {
            lastError = L("未能保存本地数据，请检查磁盘空间与权限。")
            NotificationCenter.default.post(name: Self.changed, object: self)
            throw error
        }
    }
}
